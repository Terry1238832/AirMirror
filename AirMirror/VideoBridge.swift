import AVFoundation
import AppKit
import Combine
import CoreMedia
import Darwin
import Foundation
import os
import SwiftUI

enum VideoBridgeError: LocalizedError {
    case socketPathTooLong
    case listenFailed

    var errorDescription: String? {
        switch self {
        case .socketPathTooLong:
            return "投屏通道路径太长"
        case .listenFailed:
            return "无法建立投屏画面通道"
        }
    }
}

final class VideoBridge: ObservableObject {
    static let headerSize = 32
    static let magic: UInt32 = 0x31564d41

    enum MessageType: UInt32 {
        case size = 1
        case packet = 2
        case end = 3
    }

    let socketPath: String
    let displayLayer: AVSampleBufferDisplayLayer

    @Published private(set) var hasVideo = false
    @Published private(set) var videoSize: CGSize = .zero

    private let logger = Logger(subsystem: "com.liangyu.airmirror", category: "video")
    private let stateLock = NSLock()
    private let acceptQueue = DispatchQueue(label: "com.liangyu.airmirror.video.accept")
    private let decodeQueue = DispatchQueue(label: "com.liangyu.airmirror.video.decode")
    private var listenFD: Int32 = -1
    private var clientFD: Int32 = -1
    private var stopping = false
    private var generation = 0
    private var formatDesc: CMFormatDescription?
    /// iOS resends identical SPS/PPS whenever the stream resumes; only different bytes are a real format change.
    private var formatParameterSets = Data()
    private var sps: Data?
    private var pps: Data?
    private var vps: Data?
    private var codec: UInt32 = 0
    private var pending = [Data]()
    /// Main-thread only. After a decoder failure, P-frames can't decode until the next IDR.
    private var waitingForKeyframe = false
    /// Avoid rewriting `videoGravity` with the same value; that redraws the layer.
    private var lastLetterbox: Bool?

    init() {
        socketPath = "/tmp/airmirror-\(ProcessInfo.processInfo.processIdentifier).sock"
        let layer = AVSampleBufferDisplayLayer()
        layer.videoGravity = .resize
        layer.backgroundColor = NSColor.black.cgColor
        displayLayer = layer
    }

    func startListening() throws {
        let gen: Int = try {
            stateLock.lock()
            defer { stateLock.unlock() }
            stopping = false
            closeSocketsLocked()
            unlink(socketPath)
            generation += 1
            let next = generation

            let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw VideoBridgeError.listenFailed }

            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let pathBytes = Array(socketPath.utf8CString)
            guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
                Darwin.close(fd)
                throw VideoBridgeError.socketPathTooLong
            }
            withUnsafeMutableBytes(of: &address.sun_path) { dest in
                pathBytes.withUnsafeBytes { src in
                    dest.copyMemory(from: src)
                }
            }

            let bindResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            if bindResult != 0 {
                Darwin.close(fd)
                throw VideoBridgeError.listenFailed
            }
            if Darwin.listen(fd, 1) != 0 {
                Darwin.close(fd)
                unlink(socketPath)
                throw VideoBridgeError.listenFailed
            }
            listenFD = fd
            return next
        }()
        acceptQueue.async { [weak self] in
            self?.acceptLoop(gen)
        }
    }

    func stopListening() {
        stateLock.lock()
        stopping = true
        closeSocketsLocked()
        unlink(socketPath)
        stateLock.unlock()
        endSession()
    }

    func endSession() {
        decodeQueue.async { [weak self] in
            self?.resetDecoder()
        }
        DispatchQueue.main.async { [weak self] in
            self?.hasVideo = false
            self?.videoSize = .zero
        }
        flushLayer()
    }

    func setFillMode(letterbox: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let gravity: AVLayerVideoGravity = letterbox ? .resizeAspect : .resize
            guard self.lastLetterbox != letterbox || self.displayLayer.videoGravity != gravity else { return }
            self.lastLetterbox = letterbox
            guard self.displayLayer.videoGravity != gravity else { return }
            self.displayLayer.videoGravity = gravity
        }
    }

    private func acceptLoop(_ generation: Int) {
        while true {
            stateLock.lock()
            let done = stopping || self.generation != generation || listenFD < 0
            let fd = listenFD
            stateLock.unlock()
            if done || fd < 0 { return }
            var address = sockaddr_un()
            var length = socklen_t(MemoryLayout<sockaddr_un>.size)
            let client = withUnsafeMutablePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    Darwin.accept(fd, sockPtr, &length)
                }
            }
            if client < 0 {
                if errno == EINTR { continue }
                stateLock.lock()
                let done = stopping || self.generation != generation || listenFD < 0
                stateLock.unlock()
                if done { return }
                continue
            }
            stateLock.lock()
            clientFD = client
            stateLock.unlock()
            readLoop(client)
            Darwin.close(client)
            stateLock.lock()
            if clientFD == client { clientFD = -1 }
            stateLock.unlock()
            endSession()
        }
    }

    private func readLoop(_ fd: Int32) {
        while true {
            guard let headerData = readExact(fd, count: Self.headerSize) else { return }
            let magic = Self.u32(headerData, 0)
            guard magic == Self.magic else { return }
            let type = Self.u32(headerData, 4)
            let codec = Self.u32(headerData, 8)
            let width = Self.u32(headerData, 12)
            let height = Self.u32(headerData, 16)
            let size = Self.u32(headerData, 20)

            var payload = Data()
            if size > 0 {
                guard let body = readExact(fd, count: Int(size)) else { return }
                payload = body
            }

            switch MessageType(rawValue: type) {
            case .size:
                let next = CGSize(width: CGFloat(width), height: CGFloat(height))
                DispatchQueue.main.async { [weak self] in
                    self?.videoSize = next
                }
            case .packet:
                decodeQueue.async { [weak self] in
                    self?.handlePacket(payload, codec: codec)
                }
            case .end:
                endSession()
            case .none:
                return
            }
        }
    }

    private func handlePacket(_ data: Data, codec: UInt32) {
        self.codec = codec
        let nalus = Self.splitNALUs(data)
        guard !nalus.isEmpty else { return }

        if codec == 1 {
            for nalu in nalus {
                switch Self.hevcType(nalu) {
                case 32: vps = nalu
                case 33: sps = nalu
                case 34: pps = nalu
                default: break
                }
            }
            if let vps, let sps, let pps {
                let key = vps + sps + pps
                if key != formatParameterSets, let next = Self.makeHEVCFormat(vps: vps, sps: sps, pps: pps) {
                    formatDesc = next
                    formatParameterSets = key
                }
            }
        } else {
            for nalu in nalus {
                switch Self.avcType(nalu) {
                case 7: sps = nalu
                case 8: pps = nalu
                default: break
                }
            }
            if let sps, let pps {
                let key = sps + pps
                if key != formatParameterSets, let next = Self.makeH264Format(sps: sps, pps: pps) {
                    formatDesc = next
                    formatParameterSets = key
                }
            }
        }

        guard formatDesc != nil else {
            pending.append(data)
            if pending.count > 24 {
                pending.removeFirst(pending.count - 24)
            }
            return
        }

        let queued = pending
        pending.removeAll(keepingCapacity: true)
        for item in queued {
            enqueue(item)
        }
        enqueue(data)
    }

    private func enqueue(_ annexB: Data) {
        guard let formatDesc else { return }
        let nalus = Self.splitNALUs(annexB).filter { !$0.isEmpty }
        guard let avcc = Self.avcc(from: nalus) else { return }

        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: avcc.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: avcc.count,
            flags: 0,
            blockBufferOut: &block
        )
        guard status == noErr, let block else { return }
        status = avcc.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> OSStatus in
            guard let base = raw.baseAddress else { return OSStatus(-1) }
            return CMBlockBufferReplaceDataBytes(
                with: base,
                blockBuffer: block,
                offsetIntoDestination: 0,
                dataLength: avcc.count
            )
        }
        guard status == noErr else { return }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: .invalid,
            decodeTimeStamp: .invalid
        )
        var sampleSize = avcc.count
        var sample: CMSampleBuffer?
        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sample
        )
        guard status == noErr, let sample else { return }

        let keyframe = isKeyframe(nalus)
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary],
           let first = attachments.first {
            first[kCMSampleAttachmentKey_DisplayImmediately] = true
            first[kCMSampleAttachmentKey_NotSync] = !keyframe
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.enqueueOnLayer(sample, keyframe: keyframe)
            if !self.hasVideo {
                self.hasVideo = true
            }
        }
    }

    /// H.264 and HEVC share the first byte, so the type has to follow the active codec.
    /// Treating an H.264 P-frame as an HEVC parameter set marked it sync and the picture flashed.
    private func isKeyframe(_ nalus: [Data]) -> Bool {
        if codec == 1 {
            return nalus.contains { nalu in
                let type = Self.hevcType(nalu)
                return (16...21).contains(type)
            }
        }
        return nalus.contains { Self.avcType($0) == 5 }
    }

    private func enqueueOnLayer(_ sample: CMSampleBuffer, keyframe: Bool) {
        if #available(macOS 14.0, *) {
            let renderer = displayLayer.sampleBufferRenderer
            if renderer.status == .failed {
                logger.error("video decoder failed: \(String(describing: renderer.error), privacy: .public)")
                renderer.flush(removingDisplayedImage: false)
                waitingForKeyframe = true
            }
            if waitingForKeyframe {
                guard keyframe else { return }
                waitingForKeyframe = false
            }
            renderer.enqueue(sample)
        } else {
            if displayLayer.status == .failed {
                logger.error("video decoder failed: \(String(describing: self.displayLayer.error), privacy: .public)")
                displayLayer.flush()
                waitingForKeyframe = true
            }
            if waitingForKeyframe {
                guard keyframe else { return }
                waitingForKeyframe = false
            }
            displayLayer.enqueue(sample)
        }
    }

    private func flushLayer() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.waitingForKeyframe = false
            if #available(macOS 14.0, *) {
                self.displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true)
            } else {
                self.displayLayer.flushAndRemoveImage()
            }
        }
    }

    private func resetDecoder() {
        formatDesc = nil
        formatParameterSets = Data()
        sps = nil
        pps = nil
        vps = nil
        pending.removeAll()
    }

    private func closeSocketsLocked() {
        if clientFD >= 0 {
            Darwin.close(clientFD)
            clientFD = -1
        }
        if listenFD >= 0 {
            Darwin.close(listenFD)
            listenFD = -1
        }
    }

    private func readExact(_ fd: Int32, count: Int) -> Data? {
        var data = Data(count: count)
        var offset = 0
        while offset < count {
            let got = data.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                return Darwin.read(fd, base + offset, count - offset)
            }
            if got == 0 { return nil }
            if got < 0 {
                if errno == EINTR { continue }
                return nil
            }
            offset += got
        }
        return data
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    private static func splitNALUs(_ data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var starts: [Int] = []
        var index = 0
        while index + 2 < bytes.count {
            if bytes[index] == 0 && bytes[index + 1] == 0 {
                if bytes[index + 2] == 1 {
                    starts.append(index)
                    index += 3
                    continue
                }
                if index + 3 < bytes.count && bytes[index + 2] == 0 && bytes[index + 3] == 1 {
                    starts.append(index)
                    index += 4
                    continue
                }
            }
            index += 1
        }
        guard !starts.isEmpty else { return bytes.isEmpty ? [] : [data] }
        var nalus: [Data] = []
        for (position, start) in starts.enumerated() {
            let code = (start + 3 < bytes.count && bytes[start] == 0 && bytes[start + 1] == 0 && bytes[start + 2] == 0 && bytes[start + 3] == 1) ? 4 : 3
            let payload = start + code
            let end = position + 1 < starts.count ? starts[position + 1] : bytes.count
            if end > payload {
                nalus.append(Data(bytes[payload..<end]))
            }
        }
        return nalus
    }

    private static func avcType(_ nalu: Data) -> Int {
        guard let first = nalu.first else { return -1 }
        return Int(first & 0x1f)
    }

    private static func hevcType(_ nalu: Data) -> Int {
        guard let first = nalu.first else { return -1 }
        return Int((first >> 1) & 0x3f)
    }

    private static func avcc(from nalus: [Data]) -> Data? {
        guard !nalus.isEmpty else { return nil }
        var output = Data()
        output.reserveCapacity(nalus.reduce(0) { $0 + $1.count + 4 })
        for nalu in nalus {
            var length = UInt32(nalu.count).bigEndian
            output.append(Data(bytes: &length, count: 4))
            output.append(nalu)
        }
        return output
    }

    private static func makeH264Format(sps: Data, pps: Data) -> CMVideoFormatDescription? {
        var format: CMVideoFormatDescription?
        let status = sps.withUnsafeBytes { spsRaw -> OSStatus in
            pps.withUnsafeBytes { ppsRaw -> OSStatus in
                guard let spsPtr = spsRaw.bindMemory(to: UInt8.self).baseAddress,
                      let ppsPtr = ppsRaw.bindMemory(to: UInt8.self).baseAddress else {
                    return kCMFormatDescriptionError_InvalidParameter
                }
                let pointers: [UnsafePointer<UInt8>] = [spsPtr, ppsPtr]
                let sizes: [Int] = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: pointers,
                    parameterSetSizes: sizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &format
                )
            }
        }
        return status == noErr ? format : nil
    }

    private static func makeHEVCFormat(vps: Data, sps: Data, pps: Data) -> CMVideoFormatDescription? {
        var format: CMVideoFormatDescription?
        let status = vps.withUnsafeBytes { vpsRaw -> OSStatus in
            sps.withUnsafeBytes { spsRaw -> OSStatus in
                pps.withUnsafeBytes { ppsRaw -> OSStatus in
                    guard let vpsPtr = vpsRaw.bindMemory(to: UInt8.self).baseAddress,
                          let spsPtr = spsRaw.bindMemory(to: UInt8.self).baseAddress,
                          let ppsPtr = ppsRaw.bindMemory(to: UInt8.self).baseAddress else {
                        return kCMFormatDescriptionError_InvalidParameter
                    }
                    let pointers: [UnsafePointer<UInt8>] = [vpsPtr, spsPtr, ppsPtr]
                    let sizes: [Int] = [vps.count, sps.count, pps.count]
                    return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: 3,
                        parameterSetPointers: pointers,
                        parameterSetSizes: sizes,
                        nalUnitHeaderLength: 4,
                        extensions: nil,
                        formatDescriptionOut: &format
                    )
                }
            }
        }
        return status == noErr ? format : nil
    }
}

struct VideoCanvas: NSViewRepresentable {
    let bridge: VideoBridge

    func makeNSView(context: Context) -> NSView {
        let view = VideoHostView(layer: bridge.displayLayer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if nsView.layer !== bridge.displayLayer {
            nsView.layer = bridge.displayLayer
        }
    }
}

final class VideoHostView: NSView {
    private var observers: [NSObjectProtocol] = []

    init(layer: AVSampleBufferDisplayLayer) {
        super.init(frame: .zero)
        wantsLayer = true
        self.layer = layer
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        guard let window else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
            self?.setVideoGravity(.resizeAspect)
        })
        observers.append(center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
            self?.setVideoGravity(.resize)
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    override func layout() {
        super.layout()
        guard let layer else { return }
        // AppKit already sizes a view's layer. Rewriting the same frame still redraws the picture.
        guard layer.bounds.size != bounds.size else { return }
        layer.frame = bounds
    }

    private func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        guard let layer = self.layer as? AVSampleBufferDisplayLayer, layer.videoGravity != gravity else { return }
        layer.videoGravity = gravity
    }
}

struct WindowAspectLock: NSViewRepresentable {
    let streaming: Bool
    let videoSize: CGSize
    let bridge: VideoBridge

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(view.window, context.coordinator) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(nsView.window, context.coordinator) }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastFitted = CGSize.zero
        var lastAspect = CGSize.zero
        var lastMinSize = NSSize.zero
        var styledWindow = false
    }

    private func apply(_ window: NSWindow?, _ coordinator: Coordinator) {
        guard let window else { return }
        if !coordinator.styledWindow {
            window.backgroundColor = .black
            window.titlebarAppearsTransparent = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.title = "镜投"
            coordinator.styledWindow = true
        }

        let fullscreen = window.styleMask.contains(.fullScreen)
        bridge.setFillMode(letterbox: fullscreen || !streaming)

        if streaming, videoSize.width > 1, videoSize.height > 1 {
            if fullscreen {
                setAspect(.zero, on: window, coordinator: coordinator)
            } else {
                let minSize = NSSize(width: 240, height: max(160, 240 * videoSize.height / videoSize.width))
                setAspect(videoSize, minSize: minSize, on: window, coordinator: coordinator)
                if coordinator.lastFitted != videoSize {
                    coordinator.lastFitted = videoSize
                    fit(window, to: videoSize)
                }
            }
        } else {
            coordinator.lastFitted = .zero
            setAspect(.zero, minSize: NSSize(width: 760, height: 620), on: window, coordinator: coordinator)
        }
    }

    private func setAspect(_ aspect: CGSize, minSize: NSSize = .zero, on window: NSWindow, coordinator: Coordinator) {
        if coordinator.lastAspect != aspect {
            coordinator.lastAspect = aspect
            window.contentAspectRatio = aspect
        }
        let resolvedMin = minSize == .zero ? coordinator.lastMinSize : minSize
        if resolvedMin != .zero, coordinator.lastMinSize != resolvedMin {
            coordinator.lastMinSize = resolvedMin
            window.contentMinSize = resolvedMin
        }
    }

    private func fit(_ window: NSWindow, to size: CGSize) {
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let maxW = screen.width * 0.72
        let maxH = screen.height * 0.78
        let scale = min(maxW / size.width, maxH / size.height, 1.15)
        let width = max(320, size.width * scale)
        let height = width * size.height / size.width
        window.setContentSize(NSSize(width: width, height: height))
        window.center()
    }
}

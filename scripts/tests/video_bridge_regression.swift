import AVFoundation
import AppKit
import Combine
import CoreMedia
import CoreVideo
import Darwin
import Foundation

private enum RegressionError: Error, CustomStringConvertible {
    case failure(String)

    var description: String {
        switch self { case .failure(let message): return message }
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw RegressionError.failure(message) }
}

private func pump(_ label: String, tick: (() -> Void)? = nil,
                  until condition: () -> Bool, timeout: TimeInterval = 2) throws {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if condition() { return }
        tick?()
        _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.005))
    } while Date() < deadline
    throw RegressionError.failure("Timed out waiting for \(label)")
}

private func drain(for duration: TimeInterval = 0.05) {
    let deadline = Date().addingTimeInterval(duration)
    while Date() < deadline {
        _ = RunLoop.main.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.005)))
    }
}

private func sample(width: Int, height: Int) throws -> CMSampleBuffer {
    var pixels: CVPixelBuffer?
    let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                    nil, &pixels)
    try require(status == kCVReturnSuccess, "Unable to create synthetic pixel buffer: \(status)")
    guard let pixels else { throw RegressionError.failure("Missing pixel buffer") }
    CVPixelBufferLockBaseAddress(pixels, [])
    if let base = CVPixelBufferGetBaseAddress(pixels) {
        memset(base, 0x80, CVPixelBufferGetBytesPerRow(pixels) * height)
    }
    CVPixelBufferUnlockBaseAddress(pixels, [])
    var format: CMVideoFormatDescription?
    try require(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                           imageBuffer: pixels,
                                                           formatDescriptionOut: &format) == noErr,
                "Unable to create synthetic format description")
    guard let format else { throw RegressionError.failure("Missing format description") }
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 60),
                                   presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
    var buffer: CMSampleBuffer?
    try require(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                       imageBuffer: pixels,
                                                       formatDescription: format,
                                                       sampleTiming: &timing,
                                                       sampleBufferOut: &buffer) == noErr,
                "Unable to create synthetic sample buffer")
    guard let buffer else { throw RegressionError.failure("Missing sample buffer") }
    return buffer
}

private final class SocketClient {
    private var descriptor: Int32

    init(path: String) throws {
        descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw RegressionError.failure("Cannot create test socket") }
        var noSignal: Int32 = 1
        _ = setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8CString)
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            close()
            throw RegressionError.failure("Test socket path is too long")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { dest in
            pathBytes.withUnsafeBytes { dest.copyMemory(from: $0) }
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result != 0 {
            let code = errno
            close()
            throw RegressionError.failure("Cannot connect bridge socket: errno \(code)")
        }
    }

    deinit { close() }

    func close() {
        guard descriptor >= 0 else { return }
        _ = Darwin.shutdown(descriptor, SHUT_RDWR)
        Darwin.close(descriptor)
        descriptor = -1
    }

    func sendSize(width: UInt32, height: UInt32) throws {
        let values: [UInt32] = [VideoBridge.magic, 1, 0, width, height, 0, 0, 0]
        var bytes = Data()
        for value in values {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { bytes.append(contentsOf: $0) }
        }
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { raw in
                Darwin.write(descriptor, raw.baseAddress!.advanced(by: offset), raw.count - offset)
            }
            guard written > 0 else { throw RegressionError.failure("Cannot send bridge size header: errno \(errno)") }
            offset += written
        }
    }
}

@main
private struct VideoBridgeRegression {
    static func main() {
        do {
            _ = NSApplication.shared
            try run()
            print("PASS: USB frames, rotation, bounded delivery, stale frames, and 20 wireless/USB switch cycles")
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        try require(Thread.isMainThread, "Harness must run on the main thread")
        let bridge = VideoBridge()
        defer { bridge.stopListening() }
        let landscape = try sample(width: 640, height: 480)
        let portrait = try sample(width: 480, height: 640)

        var session = bridge.beginExternalSession()
        bridge.enqueueExternalSample(landscape, session: session)
        try pump("initial landscape USB frame", tick: {
            bridge.enqueueExternalSample(landscape, session: session)
        }) { bridge.hasVideo && bridge.videoSize == CGSize(width: 640, height: 480) }
        bridge.enqueueExternalSample(portrait, session: session)
        try pump("portrait USB frame", tick: {
            bridge.enqueueExternalSample(portrait, session: session)
        }) { bridge.hasVideo && bridge.videoSize == CGSize(width: 480, height: 640) }

        // Hold the main queue while flooding capture frames. Delivery must coalesce to the final frame.
        session = bridge.beginExternalSession()
        var publishedSizes: [CGSize] = []
        let subscription = bridge.$videoSize.dropFirst().sink { publishedSizes.append($0) }
        for index in 0..<10_000 {
            bridge.enqueueExternalSample(index.isMultiple(of: 2) ? landscape : portrait, session: session)
        }
        try require(bridge.videoSize == .zero, "Capture delivery unexpectedly ran during the main-queue flood")
        try pump("coalesced final USB frame") { bridge.videoSize == CGSize(width: 480, height: 640) }
        try require(publishedSizes == [CGSize(width: 480, height: 640)],
                    "Raw capture backlog delivered \(publishedSizes.count) size changes instead of the latest frame")
        subscription.cancel()
        // A flush may temporarily make the renderer busy. Live capture supplies another frame.
        try pump("renderer readiness after frame flood", tick: {
            bridge.enqueueExternalSample(portrait, session: session)
        }) { bridge.hasVideo }

        bridge.stopListening()
        bridge.enqueueExternalSample(landscape, session: session)
        drain()
        try require(!bridge.hasVideo && bridge.videoSize == .zero, "Stopped USB session accepted a stale frame")

        // Leave a frame pending, switch sources twice, and prove only the newest session reaches the layer.
        let superseded = bridge.beginExternalSession()
        bridge.enqueueExternalSample(landscape, session: superseded)
        session = bridge.beginExternalSession()
        bridge.enqueueExternalSample(portrait, session: session)
        bridge.enqueueExternalSample(landscape, session: superseded)
        try pump("newest USB session", tick: {
            bridge.enqueueExternalSample(portrait, session: session)
        }) { bridge.hasVideo && bridge.videoSize == CGSize(width: 480, height: 640) }

        for iteration in 0..<20 {
            bridge.stopListening()
            try bridge.startListening()
            let oldClient = try SocketClient(path: bridge.socketPath)
            try oldClient.sendSize(width: 1024, height: 768)
            try pump("AirPlay initial size in cycle \(iteration)") { bridge.videoSize == CGSize(width: 1024, height: 768) }

            // This header can already be queued when USB invalidates its AirPlay generation.
            try oldClient.sendSize(width: 1920, height: 1080)
            session = bridge.beginExternalSession()
            bridge.enqueueExternalSample(portrait, session: session)
            try pump("USB frame after AirPlay in cycle \(iteration)", tick: {
                bridge.enqueueExternalSample(portrait, session: session)
            }) { bridge.hasVideo && bridge.videoSize == CGSize(width: 480, height: 640) }
            oldClient.close()
            drain(for: 0.02)
            try require(bridge.hasVideo && bridge.videoSize == CGSize(width: 480, height: 640),
                        "Old AirPlay disconnect cleared USB in cycle \(iteration)")

            bridge.stopListening()
            try bridge.startListening()
            let newClient = try SocketClient(path: bridge.socketPath)
            try newClient.sendSize(width: 1280, height: 720)
            bridge.enqueueExternalSample(portrait, session: session)
            try pump("wireless size after USB in cycle \(iteration)") { bridge.videoSize == CGSize(width: 1280, height: 720) }
            try require(!bridge.hasVideo, "Stale USB frame entered the new wireless session in cycle \(iteration)")
            newClient.close()
            try pump("wireless disconnect in cycle \(iteration)") { bridge.videoSize == .zero && !bridge.hasVideo }
        }
    }
}

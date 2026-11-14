import AVFoundation
import CoreMedia
import CoreMediaIO
import Foundation

struct WiredDevice: Identifiable, Equatable {
    let id: String
    let name: String
}

enum WiredCaptureEvent {
    case devices([WiredDevice])
    case waiting
    case connecting(String)
    case connected(String)
    case disconnected
    case permissionDenied
    case failed(String)
    case audioUnavailable(String)
}

/// macOS exposes a trusted USB iOS device as a muxed screen capture source.
/// Session work never runs on the main queue; video frames use a separate serial queue.
final class WiredCaptureEngine: NSObject {
    var onEvent: ((WiredCaptureEvent) -> Void)?
    var onVideoSample: ((CMSampleBuffer) -> Void)? {
        get {
            generationLock.lock()
            defer { generationLock.unlock() }
            return videoSampleCallback
        }
        set {
            generationLock.lock()
            videoSampleCallback = newValue
            generationLock.unlock()
        }
    }

    private let sessionQueue = DispatchQueue(label: "com.liangyu.airmirror.usb.session")
    private let sampleQueue = DispatchQueue(label: "com.liangyu.airmirror.usb.frames", qos: .userInteractive)
    private let generationLock = NSLock()
    private var generation = 0
    private var wantsCapture = false
    private var requestedAudio = false
    private var videoSampleCallback: ((CMSampleBuffer) -> Void)?

    // Everything below is owned by sessionQueue.
    private var requested = false
    private var preferredDeviceID: String?
    private var audioEnabled = false
    private var audioRequest = 0
    private var discovery: AVCaptureDevice.DiscoverySession?
    private var discoveryGeneration = 0
    private var discoveryTimer: DispatchSourceTimer?
    private var deviceObservers: [NSObjectProtocol] = []
    private var sessionObservers: [NSObjectProtocol] = []
    private var listedDevices: [WiredDevice] = []
    private var session: AVCaptureSession?
    private var input: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var audioOutput: AVCaptureAudioPreviewOutput?
    private var forwarder: WiredSampleForwarder?
    private var activeDeviceID: String?
    private var attemptedDeviceID: String?
    private var receivedFrame = false

    func start(preferredDeviceID: String?, audioEnabled: Bool) {
        generationLock.lock()
        wantsCapture = true
        requestedAudio = audioEnabled
        generation += 1
        let token = generation
        generationLock.unlock()
        sessionQueue.async { [weak self] in
            guard let self, self.isCurrent(token) else { return }
            self.beginDiscovery(preferredDeviceID: preferredDeviceID, audioEnabled: audioEnabled, token: token)
        }
    }

    func selectDevice(_ id: String?) {
        let token = advanceGeneration()
        sessionQueue.async { [weak self] in
            guard let self, self.isCurrent(token) else { return }
            self.generationLock.lock()
            let shouldStart = self.wantsCapture
            let audio = self.requestedAudio
            self.generationLock.unlock()
            // A selection can overtake an enqueued start before discovery is created.
            if shouldStart, self.discovery == nil {
                self.beginDiscovery(preferredDeviceID: id, audioEnabled: audio, token: token)
                return
            }
            self.discoveryGeneration = token
            self.preferredDeviceID = id
            self.clearCapture()
            self.attemptedDeviceID = nil
            self.requested = shouldStart
            if shouldStart { self.discoverDevices(force: true) }
            else { self.tearDownDiscovery() }
        }
    }

    func setAudioEnabled(_ enabled: Bool) {
        generationLock.lock()
        requestedAudio = enabled
        generationLock.unlock()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.audioEnabled = enabled
            self.audioRequest += 1
            guard self.isCurrent(self.discoveryGeneration) else { return }
            if enabled {
                self.configureAudio(token: self.discoveryGeneration)
            } else {
                self.removeAudioOutput()
            }
        }
    }

    func refreshDevices() {
        sessionQueue.async { [weak self] in
            guard let self, self.requested, self.isCurrent(self.discoveryGeneration) else { return }
            // An explicit refresh is also a retry after a device or capture error.
            if self.session == nil {
                guard let next = self.advanceGeneration(ifCurrent: self.discoveryGeneration) else { return }
                self.discoveryGeneration = next
                self.attemptedDeviceID = nil
            }
            self.discoverDevices(force: true)
        }
    }

    func stop() {
        generationLock.lock()
        wantsCapture = false
        generation += 1
        let token = generation
        generationLock.unlock()
        sessionQueue.async { [weak self] in
            guard let self, self.isCurrent(token) else { return }
            self.requested = false
            self.tearDownDiscovery()
            self.clearCapture()
            self.attemptedDeviceID = nil
            self.listedDevices = []
        }
    }

    private func beginDiscovery(preferredDeviceID: String?, audioEnabled: Bool, token: Int) {
        guard isCurrent(token) else { return }
        tearDownDiscovery()
        clearCapture()
        requested = true
        discoveryGeneration = token
        self.preferredDeviceID = preferredDeviceID
        self.audioEnabled = audioEnabled
        attemptedDeviceID = nil
        listedDevices = []
        guard enableScreenDevices() else {
            emit(.failed(L10n.tr("无法启用 USB 屏幕接收，请重新打开镜投后再试。")), token: token)
            return
        }
        discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external], mediaType: .muxed, position: .unspecified
        )
        let center = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            deviceObservers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.sessionQueue.async { [weak self] in self?.discoverDevices(force: true) }
            })
        }
        // The iOS screen assistant can enumerate after the initial CMIO opt-in.
        // Notifications handle hotplug; the light poll also covers delayed trust/unlock.
        let timer = DispatchSource.makeTimerSource(queue: sessionQueue)
        timer.schedule(deadline: .now() + 0.5, repeating: 2, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in self?.discoverDevices(force: false) }
        discoveryTimer = timer
        timer.resume()
        discoverDevices(force: true)
    }

    private func discoverDevices(force: Bool) {
        guard requested, let discovery, isCurrent(discoveryGeneration) else { return }
        let available = discovery.devices.filter { $0.isConnected && !$0.isContinuityCamera }
        let devices = available.map { WiredDevice(id: $0.uniqueID, name: $0.localizedName) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let listChanged = devices != listedDevices
        listedDevices = devices
        let selected = available.first { $0.uniqueID == preferredDeviceID }
            ?? available.first { $0.uniqueID == activeDeviceID }
            ?? available.sorted { $0.uniqueID < $1.uniqueID }.first

        var token = discoveryGeneration
        if let activeDeviceID, activeDeviceID != selected?.uniqueID {
            guard let next = advanceGeneration(ifCurrent: token) else { return }
            token = next
            discoveryGeneration = next
            clearCapture()
            attemptedDeviceID = nil
            emit(.disconnected, token: token)
        } else if let attemptedDeviceID, activeDeviceID == nil, attemptedDeviceID != selected?.uniqueID {
            // Invalidate an outstanding authorization completion for an unplugged device.
            guard let next = advanceGeneration(ifCurrent: token) else { return }
            token = next
            discoveryGeneration = next
            self.attemptedDeviceID = nil
        }
        if force || listChanged { emit(.devices(devices), token: token) }
        guard let selected else {
            attemptedDeviceID = nil
            if force || listChanged { emit(.waiting, token: token) }
            return
        }
        guard activeDeviceID == nil, attemptedDeviceID != selected.uniqueID else { return }
        attemptedDeviceID = selected.uniqueID
        emit(.connecting(selected.localizedName), token: token)
        authorizeVideo(device: selected, token: token)
    }

    private func authorizeVideo(device: AVCaptureDevice, token: Int) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            connect(device: device, token: token)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                self?.sessionQueue.async { [weak self] in
                    guard let self, self.requested, self.isCurrent(token) else { return }
                    if allowed {
                        self.connect(device: device, token: token)
                    } else {
                        self.emit(.permissionDenied, token: token)
                    }
                }
            }
        case .denied, .restricted:
            emit(.permissionDenied, token: token)
        @unknown default:
            emit(.permissionDenied, token: token)
        }
    }

    private func connect(device: AVCaptureDevice, token: Int) {
        guard requested, isCurrent(token), device.isConnected else { return }
        do {
            let capture = AVCaptureSession()
            let captureInput = try AVCaptureDeviceInput(device: device)
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            let delegate = WiredSampleForwarder(owner: self, token: token, deviceName: device.localizedName)
            output.setSampleBufferDelegate(delegate, queue: sampleQueue)

            capture.beginConfiguration()
            // Input-priority is unavailable on macOS. Unlike fixed HD presets, high
            // leaves output dimensions to the source; never impose a 16:9 buffer size.
            if capture.canSetSessionPreset(.high) { capture.sessionPreset = .high }
            guard capture.canAddInput(captureInput), capture.canAddOutput(output) else {
                capture.commitConfiguration()
                throw WiredCaptureFailure.unsupported
            }
            // Explicit connections ensure video-only mode never attaches an audio output.
            capture.addInputWithNoConnections(captureInput)
            capture.addOutputWithNoConnections(output)
            let ports = captureInput.ports.filter { $0.mediaType == .video }
            guard !ports.isEmpty else {
                capture.commitConfiguration()
                throw WiredCaptureFailure.unsupported
            }
            let connection = AVCaptureConnection(inputPorts: ports, output: output)
            guard capture.canAddConnection(connection) else {
                capture.commitConfiguration()
                throw WiredCaptureFailure.unsupported
            }
            capture.addConnection(connection)
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
            capture.commitConfiguration()
            guard isCurrent(token) else { return }
            session = capture
            input = captureInput
            videoOutput = output
            forwarder = delegate
            activeDeviceID = device.uniqueID
            receivedFrame = false
            observeSession(capture, token: token)
            capture.startRunning()
            guard isCurrent(token) else { clearCapture(); return }
            if audioEnabled { configureAudio(token: token) }
            sessionQueue.asyncAfter(deadline: .now() + 12) { [weak self, weak capture] in
                guard let self, let capture, self.isCurrent(token), self.session === capture,
                      !self.receivedFrame else { return }
                self.failCapture(L10n.tr("还没有收到 iPad 画面。请解锁设备并信任这台 Mac，确认使用支持数据传输的线缆，然后点刷新重试。"), token: token)
            }
        } catch {
            guard isCurrent(token) else { return }
            clearCapture()
            emit(.failed(L10n.tr("无法接收 USB 画面：%1$@", String(describing: error.localizedDescription))), token: token)
        }
    }

    private func configureAudio(token: Int) {
        guard audioEnabled, let session, input != nil, isCurrent(token), audioOutput == nil else { return }
        let request = audioRequest
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            addAudioOutput(to: session, token: token)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self, weak session] allowed in
                self?.sessionQueue.async { [weak self, weak session] in
                    guard let self, let session, self.session === session,
                          self.isCurrent(token), self.audioEnabled, self.audioRequest == request else { return }
                    if allowed {
                        self.addAudioOutput(to: session, token: token)
                    } else {
                        self.emit(.audioUnavailable(L10n.tr("未允许音频输入，画面仍可继续投屏。可在系统设置的「隐私与安全性 → 麦克风」中允许镜投。")), token: token)
                    }
                }
            }
        case .denied, .restricted:
            emit(.audioUnavailable(L10n.tr("未允许音频输入，画面仍可继续投屏。可在系统设置的「隐私与安全性 → 麦克风」中允许镜投。")), token: token)
        @unknown default:
            emit(.audioUnavailable(L10n.tr("暂时无法启用 USB 声音，画面仍可继续投屏。")), token: token)
        }
    }

    private func addAudioOutput(to capture: AVCaptureSession, token: Int) {
        guard let input, audioOutput == nil else { return }
        let ports = input.ports.filter { $0.mediaType == .audio }
        let output = AVCaptureAudioPreviewOutput()
        output.outputDeviceUniqueID = nil
        output.volume = 1
        guard !ports.isEmpty, capture.canAddOutput(output) else {
            emit(.audioUnavailable(L10n.tr("这个 USB 设备没有提供可用的声音通道，画面仍可继续投屏。")), token: token)
            return
        }
        capture.beginConfiguration()
        capture.addOutputWithNoConnections(output)
        let connection = AVCaptureConnection(inputPorts: ports, output: output)
        if capture.canAddConnection(connection) {
            capture.addConnection(connection)
            audioOutput = output
        } else {
            capture.removeOutput(output)
            emit(.audioUnavailable(L10n.tr("无法连接 USB 声音通道，画面仍可继续投屏。")), token: token)
        }
        capture.commitConfiguration()
    }

    private func removeAudioOutput() {
        guard let session, let audioOutput else { return }
        session.beginConfiguration()
        session.removeOutput(audioOutput)
        session.commitConfiguration()
        self.audioOutput = nil
    }

    private func observeSession(_ capture: AVCaptureSession, token: Int) {
        let center = NotificationCenter.default
        sessionObservers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: capture, queue: nil) { [weak self, weak capture] notification in
            let message = (notification.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription
                ?? L10n.tr("设备连接中断，请重新插线后刷新。")
            self?.sessionQueue.async { [weak self, weak capture] in
                guard let self, let capture, self.session === capture, self.isCurrent(token) else { return }
                // Audio is optional: retry the active capture once without its preview output.
                if self.audioOutput != nil {
                    self.removeAudioOutput()
                    self.emit(.audioUnavailable(L10n.tr("USB 声音不可用：%1$@", String(describing: message))), token: token)
                    if !capture.isRunning { capture.startRunning() }
                } else {
                    self.failCapture(L10n.tr("USB 投屏中断：%1$@", String(describing: message)), token: token)
                }
            }
        })
        sessionObservers.append(center.addObserver(forName: AVCaptureSession.didStopRunningNotification, object: capture, queue: nil) { [weak self, weak capture] _ in
            self?.sessionQueue.asyncAfter(deadline: .now() + 0.5) { [weak self, weak capture] in
                guard let self, let capture, self.session === capture, self.isCurrent(token), !capture.isRunning else { return }
                self.failCapture(L10n.tr("USB 投屏已停止。请保持 iPad 解锁，检查线缆后点刷新重试。"), token: token)
            }
        })
    }

    fileprivate func deliver(_ sample: CMSampleBuffer, token: Int, first: Bool, deviceName: String) {
        guard isCurrent(token), CMSampleBufferIsValid(sample), CMSampleBufferDataIsReady(sample) else { return }
        if first {
            sessionQueue.async { [weak self] in
                guard let self, self.isCurrent(token), self.session != nil else { return }
                self.receivedFrame = true
                self.emit(.connected(deviceName), token: token)
            }
        }
        generationLock.lock()
        let callback = generation == token ? videoSampleCallback : nil
        generationLock.unlock()
        callback?(sample)
    }

    private func failCapture(_ message: String, token: Int) {
        guard let next = advanceGeneration(ifCurrent: token) else { return }
        discoveryGeneration = next
        clearCapture()
        emit(.devices(listedDevices), token: next)
        emit(.failed(message), token: next)
    }

    private func clearCapture() {
        audioRequest += 1
        sessionObservers.forEach(NotificationCenter.default.removeObserver)
        sessionObservers.removeAll()
        videoOutput?.setSampleBufferDelegate(nil, queue: nil)
        if session?.isRunning == true { session?.stopRunning() }
        session = nil
        input = nil
        videoOutput = nil
        audioOutput = nil
        forwarder = nil
        activeDeviceID = nil
        receivedFrame = false
    }

    private func tearDownDiscovery() {
        discoveryTimer?.cancel()
        discoveryTimer = nil
        deviceObservers.forEach(NotificationCenter.default.removeObserver)
        deviceObservers.removeAll()
        discovery = nil
    }

    private func enableScreenDevices() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var allow: UInt32 = 1
        let status = CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &allow)
        // Wireless capture is a separate opt-in; this receiver only discovers wired screens.
        address.mSelector = CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowWirelessScreenCaptureDevices)
        var wireless: UInt32 = 0
        _ = CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &wireless)
        return status == noErr
    }

    private func emit(_ event: WiredCaptureEvent, token: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrent(token) else { return }
            self.onEvent?(event)
        }
    }

    private func advanceGeneration() -> Int {
        generationLock.lock()
        defer { generationLock.unlock() }
        generation += 1
        return generation
    }

    private func advanceGeneration(ifCurrent token: Int) -> Int? {
        generationLock.lock()
        defer { generationLock.unlock() }
        guard generation == token else { return nil }
        generation += 1
        return generation
    }

    private func currentGeneration() -> Int {
        generationLock.lock()
        defer { generationLock.unlock() }
        return generation
    }

    private func isCurrent(_ token: Int) -> Bool { currentGeneration() == token }
}

private final class WiredSampleForwarder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    weak var owner: WiredCaptureEngine?
    let token: Int
    let deviceName: String
    private var deliveredFrame = false

    init(owner: WiredCaptureEngine, token: Int, deviceName: String) {
        self.owner = owner
        self.token = token
        self.deviceName = deviceName
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard CMSampleBufferIsValid(sampleBuffer), CMSampleBufferDataIsReady(sampleBuffer),
              CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
        let first = !deliveredFrame
        deliveredFrame = true
        owner?.deliver(sampleBuffer, token: token, first: first, deviceName: deviceName)
    }
}

private enum WiredCaptureFailure: LocalizedError {
    case unsupported
    var errorDescription: String? { L10n.tr("设备没有提供可用的 USB 屏幕通道。请解锁设备并在 iPad 上选择「信任」这台 Mac。") }
}

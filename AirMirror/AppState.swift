import AppKit
import Combine
import Foundation
import os
import Security

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    static var defaultReceiverName: String { ReceiverNamePreference.defaultName }
    private static let pinKey = "requirePin"
    private static let macKey = "deviceMAC"
    private static let qualityKey = "streamQuality"
    private static let fpsKey = "streamFPS"
    private static let customAspectKey = "allowsCustomAspect"
    private static let aspectScaleKey = "aspectScale"
    private static let connectionModeKey = "connectionMode"
    private static let wiredDeviceKey = "wiredDeviceID"
    private static let wiredAudioKey = "wiredAudioEnabled"

    private let logger = Logger(subsystem: "com.liangyu.airmirror", category: "app")
    private let engine = ReceiverEngine()
    private let wiredEngine = WiredCaptureEngine()
    let discovery = DiscoveryMonitor()
    let video = VideoBridge()

    @Published var connectionMode: ConnectionMode {
        didSet {
            guard connectionMode != oldValue else { return }
            UserDefaults.standard.set(connectionMode.rawValue, forKey: Self.connectionModeKey)
            if started { restart() }
        }
    }
    @Published private(set) var wiredDevices: [WiredDevice] = []
    @Published var selectedWiredDeviceID: String? {
        didSet {
            UserDefaults.standard.set(selectedWiredDeviceID, forKey: Self.wiredDeviceKey)
            guard selectedWiredDeviceID != oldValue, connectionMode == .usb, !stoppingIntentionally else { return }
            wiredEngine.selectDevice(selectedWiredDeviceID)
        }
    }
    @Published var wiredAudioEnabled: Bool {
        didSet {
            UserDefaults.standard.set(wiredAudioEnabled, forKey: Self.wiredAudioKey)
            wiredAudioMessage = nil
            if connectionMode == .usb, !stoppingIntentionally { wiredEngine.setAudioEnabled(wiredAudioEnabled) }
        }
    }
    @Published private(set) var wiredPermissionDenied = false
    @Published private(set) var wiredAudioMessage: String?

    @Published private(set) var receiverName: String
    @Published var requirePin: Bool {
        didSet {
            UserDefaults.standard.set(requirePin, forKey: Self.pinKey)
            if connectionMode == .wireless, isAdvertising { restart() }
        }
    }
    @Published var quality: StreamQuality {
        didSet {
            UserDefaults.standard.set(quality.rawValue, forKey: Self.qualityKey)
            scheduleRestart()
        }
    }
    @Published var fps: StreamFPS {
        didSet {
            UserDefaults.standard.set(fps.rawValue, forKey: Self.fpsKey)
            scheduleRestart()
        }
    }
    /// Off: the window only scales at the device ratio. On: the ratio slider in settings is applied.
    @Published var allowsCustomAspect: Bool {
        didSet {
            UserDefaults.standard.set(allowsCustomAspect, forKey: Self.customAspectKey)
            if !allowsCustomAspect, aspectScale != 1 {
                aspectScale = 1
            }
        }
    }
    /// 1 keeps the device picture. Below 1 is narrower, above 1 is wider.
    @Published var aspectScale: Double {
        didSet {
            let clamped = min(1.8, max(0.6, aspectScale))
            if clamped != aspectScale {
                aspectScale = clamped
                return
            }
            UserDefaults.standard.set(aspectScale, forKey: Self.aspectScaleKey)
        }
    }
    /// Bumps when the user asks to restore the device aspect.
    @Published private(set) var aspectResetToken = 0
    @Published var status: ReceiverStatus = .idle
    @Published var connectedClient: String?
    @Published var pinCode: String?
    @Published var localAddresses: [String] = []
    @Published var lastError: String?
    @Published var recentLogs: [String] = []
    @Published var engineFound = false

    private var started = false
    private var stoppingIntentionally = false
    private var restartBudget = ReceiverRestartBudget()
    private var restartWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private let deviceMAC: String

    private init() {
        let defaults = UserDefaults.standard
        connectionMode = ConnectionMode(rawValue: defaults.string(forKey: Self.connectionModeKey) ?? "") ?? .wireless
        selectedWiredDeviceID = defaults.string(forKey: Self.wiredDeviceKey)
        wiredAudioEnabled = defaults.bool(forKey: Self.wiredAudioKey)
        receiverName = ReceiverNamePreference.loadOverride(from: defaults) ?? Self.defaultReceiverName
        requirePin = defaults.bool(forKey: Self.pinKey)
        if let storedQuality = defaults.string(forKey: Self.qualityKey),
           let quality = StreamQuality(rawValue: storedQuality) {
            self.quality = quality
        } else {
            quality = .sharp
        }
        if defaults.object(forKey: Self.fpsKey) != nil,
           let fps = StreamFPS(rawValue: defaults.integer(forKey: Self.fpsKey)) {
            self.fps = fps
        } else {
            fps = .sixty
        }
        allowsCustomAspect = defaults.bool(forKey: Self.customAspectKey)
        let storedScale = defaults.double(forKey: Self.aspectScaleKey)
        aspectScale = (storedScale >= 0.6 && storedScale <= 1.8) ? storedScale : 1
        if let storedMAC = defaults.string(forKey: Self.macKey), Self.isMAC(storedMAC) {
            deviceMAC = storedMAC
        } else {
            deviceMAC = Self.makeMAC()
            defaults.set(deviceMAC, forKey: Self.macKey)
        }

        engine.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
        wiredEngine.onEvent = { [weak self] event in
            self?.handleWired(event)
        }
        discovery.$isVisibleOnLan
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in
                guard let self, self.connectionMode == .wireless, visible, self.status == .starting else { return }
                self.status = .advertising
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .appLanguageDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let name = ReceiverNamePreference.loadOverride(from: .standard) ?? Self.defaultReceiverName
                if self.receiverName != name {
                    self.receiverName = name
                    self.scheduleRestart()
                }
                self.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var statusText: String {
        switch status {
        case .idle: return connectionMode == .usb ? L10n.tr("有线投屏已停止") : L10n.tr("尚未开始广播")
        case .starting: return connectionMode == .usb ? L10n.tr("正在连接 USB 设备…") : L10n.tr("正在启动接收端…")
        case .waitingForDevice: return L10n.tr("等待 USB 连接的 iPhone / iPad")
        case .advertising: return discovery.isVisibleOnLan ? L10n.tr("已可被 iPhone / iPad 搜索到") : L10n.tr("正在局域网广播")
        case .connected: return connectionMode == .usb ? L10n.tr("正在通过 USB 接收投屏") : L10n.tr("正在接收投屏")
        case .missingEngine: return L10n.tr("还没有安装投屏引擎")
        case .failed: return lastError ?? L10n.tr("启动失败")
        }
    }

    var isAdvertising: Bool {
        connectionMode == .wireless && (status == .advertising || status == .connected)
    }

    var isReceiverActive: Bool {
        status == .starting || status == .waitingForDevice || status == .advertising || status == .connected
    }

    func start() {
        guard !started else { return }
        started = true
        ProcessInfo.processInfo.disableAutomaticTermination("airplay receiver")
        refreshNetwork()
        engineFound = EngineLocator.find() != nil
        startReceiver()
        startAddressTimer()
    }

    func startReceiver() {
        if connectionMode == .usb {
            startWiredReceiver()
            return
        }
        engineFound = EngineLocator.find() != nil
        guard engineFound else {
            status = .missingEngine
            lastError = EngineError.missingBinary.localizedDescription
            return
        }

        stoppingIntentionally = false
        let name = receiverName
        status = .starting
        lastError = nil
        pinCode = nil
        connectedClient = nil
        refreshNetwork()

        do {
            try video.startListening()
            try engine.start(
                name: name,
                requirePin: requirePin,
                deviceMAC: deviceMAC,
                quality: quality,
                fps: fps,
                videoSocket: video.socketPath
            )
            discovery.start(lookingFor: name)
        } catch {
            status = .failed
            lastError = error.localizedDescription
            logger.error("start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stopReceiver() {
        stoppingIntentionally = true
        restartBudget.reset()
        restartWork?.cancel()
        discovery.stop()
        engine.stop()
        wiredEngine.stop()
        wiredEngine.onVideoSample = nil
        video.stopListening()
        connectedClient = nil
        pinCode = nil
        status = .idle
    }

    func restart() {
        stopReceiver()
        startReceiver()
    }

    func resetAspectRatio() {
        aspectScale = 1
        allowsCustomAspect = false
        aspectResetToken += 1
    }

    func refreshNetwork() {
        localAddresses = NetworkInfo.ipv4Addresses()
    }

    func refreshWiredDevices() {
        guard connectionMode == .usb else { return }
        if status == .idle || status == .failed {
            restart()
        } else {
            wiredEngine.refreshDevices()
        }
    }

    private func startWiredReceiver() {
        stoppingIntentionally = false
        lastError = nil
        wiredPermissionDenied = false
        wiredAudioMessage = nil
        pinCode = nil
        connectedClient = nil
        status = .starting
        prepareWiredVideoSession()
        wiredEngine.start(preferredDeviceID: selectedWiredDeviceID, audioEnabled: wiredAudioEnabled)
    }

    private func prepareWiredVideoSession() {
        let session = video.beginExternalSession()
        wiredEngine.onVideoSample = { [weak video] sample in
            video?.enqueueExternalSample(sample, session: session)
        }
    }

    private func handleWired(_ event: WiredCaptureEvent) {
        guard connectionMode == .usb, !stoppingIntentionally else { return }
        switch event {
        case .devices(let devices):
            wiredDevices = devices
        case .waiting, .disconnected:
            connectedClient = nil
            prepareWiredVideoSession()
            status = .waitingForDevice
        case .connecting(let name):
            connectedClient = name
            lastError = nil
            wiredPermissionDenied = false
            prepareWiredVideoSession()
            status = .starting
        case .connected(let name):
            connectedClient = name
            status = .connected
            lastError = nil
        case .permissionDenied:
            wiredPermissionDenied = true
            status = .failed
            lastError = L10n.tr("请在系统设置的「隐私与安全性 → 相机」中允许镜投读取 USB 设备画面。")
        case .failed(let message):
            prepareWiredVideoSession()
            connectedClient = nil
            status = .failed
            lastError = message
        case .audioUnavailable(let message):
            wiredAudioMessage = message
        }
    }

    func setReceiverName(_ proposed: String) {
        let name = ReceiverNamePreference.save(proposed, defaultName: Self.defaultReceiverName, to: .standard)
        guard receiverName != name else { return }
        receiverName = name
        scheduleRestart()
    }

    private func scheduleRestart() {
        guard started, connectionMode == .wireless, isReceiverActive else { return }
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.restart()
        }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func startAddressTimer() {
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshNetwork()
            }
        }
    }

    private func handle(_ event: ReceiverEvent) {
        guard connectionMode == .wireless, !stoppingIntentionally else { return }
        switch event.kind {
        case .started:
            restartBudget.didStart()
            status = .starting
        case .advertising:
            if status != .connected {
                status = .advertising
            }
        case .connected(let client):
            restartBudget.reset()
            connectedClient = client
            status = .connected
        case .disconnected:
            connectedClient = nil
            pinCode = nil
            video.endSession()
            if engine.isRunning {
                status = .advertising
            }
        case .pin(let pin):
            pinCode = pin
        case .failed(let message):
            lastError = message
        case .log(let line):
            recentLogs.append(line)
            if recentLogs.count > 80 {
                recentLogs.removeFirst(recentLogs.count - 80)
            }
        case .exited:
            discovery.stop()
            connectedClient = nil
            pinCode = nil
            video.endSession()
            if stoppingIntentionally {
                status = .idle
                lastError = nil
                return
            }
            guard let retryDelay = restartBudget.retryDelayAfterExit() else {
                status = .failed
                lastError = L10n.tr("接收端反复退出，请检查投屏引擎")
                return
            }
            lastError = nil
            status = .advertising
            logger.info("receiver stopped, restarting")
            restartWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.stoppingIntentionally else { return }
                self.startReceiver()
            }
            restartWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay, execute: work)
        }
    }

    private static func makeMAC() -> String {
        var bytes = [UInt8](repeating: 0, count: 6)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        bytes[0] = (bytes[0] | 0x02) & 0xFE
        return bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    private static func isMAC(_ value: String) -> Bool {
        let parts = value.split(separator: ":")
        return parts.count == 6 && parts.allSatisfy { $0.count == 2 && UInt8($0, radix: 16) != nil }
    }
}

enum ReceiverStatus: Equatable {
    case idle
    case starting
    case waitingForDevice
    case advertising
    case connected
    case missingEngine
    case failed
}

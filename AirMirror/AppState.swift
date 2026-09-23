import AppKit
import Combine
import Foundation
import os
import Security

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    private static let nameKey = "receiverName"
    private static let pinKey = "requirePin"
    private static let macKey = "deviceMAC"
    private static let qualityKey = "streamQuality"
    private static let fpsKey = "streamFPS"

    private let logger = Logger(subsystem: "com.liangyu.airmirror", category: "app")
    private let engine = ReceiverEngine()
    let discovery = DiscoveryMonitor()
    let video = VideoBridge()

    @Published var receiverName: String {
        didSet {
            UserDefaults.standard.set(receiverName, forKey: Self.nameKey)
            scheduleRestart()
        }
    }
    @Published var requirePin: Bool {
        didSet {
            UserDefaults.standard.set(requirePin, forKey: Self.pinKey)
            if isAdvertising { restart() }
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
    @Published var status: ReceiverStatus = .idle
    @Published var connectedClient: String?
    @Published var pinCode: String?
    @Published var localAddresses: [String] = []
    @Published var lastError: String?
    @Published var recentLogs: [String] = []
    @Published var engineFound = false

    private var started = false
    private var stoppingIntentionally = false
    private var consecutiveExits = 0
    private var restartWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private let deviceMAC: String

    private init() {
        let defaults = UserDefaults.standard
        let storedName = defaults.string(forKey: Self.nameKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        receiverName = (storedName?.isEmpty == false) ? storedName! : "镜投"
        requirePin = defaults.bool(forKey: Self.pinKey)
        if let storedQuality = defaults.string(forKey: Self.qualityKey),
           let quality = StreamQuality(rawValue: storedQuality) {
            self.quality = quality
        } else {
            quality = .fluent
        }
        if defaults.object(forKey: Self.fpsKey) != nil,
           let fps = StreamFPS(rawValue: defaults.integer(forKey: Self.fpsKey)) {
            self.fps = fps
        } else {
            fps = .sixty
        }
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
        discovery.$isVisibleOnLan
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in
                guard let self, visible, self.status == .starting else { return }
                self.status = .advertising
            }
            .store(in: &cancellables)
    }

    var statusText: String {
        switch status {
        case .idle: return "尚未开始广播"
        case .starting: return "正在启动接收端…"
        case .advertising: return discovery.isVisibleOnLan ? "已可被 iPhone / iPad 搜索到" : "正在局域网广播"
        case .connected: return "正在接收投屏"
        case .missingEngine: return "还没有安装投屏引擎"
        case .failed: return lastError ?? "启动失败"
        }
    }

    var isAdvertising: Bool {
        status == .advertising || status == .connected
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
        engineFound = EngineLocator.find() != nil
        guard engineFound else {
            status = .missingEngine
            lastError = EngineError.missingBinary.localizedDescription
            return
        }

        stoppingIntentionally = false
        let name = sanitizedName
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
        restartWork?.cancel()
        discovery.stop()
        engine.stop()
        video.stopListening()
        connectedClient = nil
        pinCode = nil
        status = .idle
    }

    func restart() {
        stopReceiver()
        startReceiver()
    }

    func refreshNetwork() {
        localAddresses = NetworkInfo.ipv4Addresses()
    }

    private var sanitizedName: String {
        let trimmed = receiverName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "镜投" : trimmed
    }

    private func scheduleRestart() {
        guard started, status != .missingEngine else { return }
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
        switch event.kind {
        case .started:
            consecutiveExits = 0
            status = .starting
        case .advertising:
            if status != .connected {
                status = .advertising
            }
        case .connected(let client):
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
            consecutiveExits += 1
            if consecutiveExits >= 6 {
                status = .failed
                lastError = "接收端反复退出，请检查投屏引擎"
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
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
    case advertising
    case connected
    case missingEngine
    case failed
}

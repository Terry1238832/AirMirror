// Adapted from WindowPaste (MIT), upstream d8f6bcb86a419b410518264798f5931b2d3344d3.
import AppKit
import Carbon
import Combine
import ServiceManagement

@MainActor
final class WindowPasteState: ObservableObject {
    static let shared = WindowPasteState()
    private let defaults: UserDefaults
    private static let prefix = "windowPaste."

    @Published private(set) var isEnabled: Bool
    @Published private(set) var targetApp: WindowPasteTargetApp
    @Published private(set) var availableWindows: [WindowPasteTargetWindow] = []
    @Published private(set) var windowPreviews: [UInt32: NSImage] = [:]
    @Published private(set) var selectedWindowID: UInt32
    @Published private(set) var selectedWindowTitle: String
    @Published private(set) var isRefreshingWindows = false
    @Published private(set) var isBusy = false
    @Published private(set) var hasScreenRecording = false
    @Published private(set) var hasAccessibility = false
    @Published private(set) var launchAtLogin = false
    @Published private(set) var autoPressReturn: Bool
    @Published private(set) var hotKey: WindowPasteHotKey
    @Published private(set) var isRecordingHotKey = false
    @Published private(set) var hotKeyWarning: String?
    @Published private(set) var windowLoadError: String?
    @Published private(set) var lastMessage: String?

    private var started = false
    private var lastTriggerAt: Date = .distantPast
    private var previewTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var recordingMonitor: Any?
    private var refreshGeneration = 0
    private var captureGeneration = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.prefix + "enabled")
        targetApp = defaults.data(forKey: Self.prefix + "target").flatMap { try? JSONDecoder().decode(WindowPasteTargetApp.self, from: $0) } ?? .mirror
        selectedWindowID = UInt32(clamping: defaults.integer(forKey: Self.prefix + "windowID"))
        selectedWindowTitle = defaults.string(forKey: Self.prefix + "windowTitle") ?? ""
        autoPressReturn = defaults.bool(forKey: Self.prefix + "autoReturn")
        if defaults.object(forKey: Self.prefix + "hotKeyCode") != nil {
            hotKey = WindowPasteHotKey(keyCode: UInt32(clamping: defaults.integer(forKey: Self.prefix + "hotKeyCode")),
                                      carbonModifiers: UInt32(clamping: defaults.integer(forKey: Self.prefix + "hotKeyModifiers")))
        } else { hotKey = .default }
    }

    func start() {
        guard !started else { return }
        started = true
        WindowPasteHotKeyManager.shared.setHandler { [weak self] in self?.captureAndPaste() }
        if isEnabled { registerHotKey() }
        refreshPermissions()
    }

    func prepareForOpening() {
        start()
        if defaults.object(forKey: Self.prefix + "enabled") == nil { setEnabled(true) }
    }

    func stop() {
        captureGeneration += 1
        refreshGeneration += 1
        captureTask?.cancel()
        previewTask?.cancel()
        finishRecording(resume: false)
        WindowPasteHotKeyManager.shared.unregister()
        started = false
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.prefix + "enabled")
        if enabled {
            if started { registerHotKey() } else { start() }
        } else {
            finishRecording(resume: false)
            WindowPasteHotKeyManager.shared.suspend()
            captureGeneration += 1
            captureTask?.cancel()
            isBusy = false
            hotKeyWarning = nil
        }
    }

    func captureAndPaste() { capture(copyOnly: false) }
    func copyScreenshot() { capture(copyOnly: true) }

    private func capture(copyOnly: Bool) {
        guard copyOnly || isEnabled, !isBusy, !isRecordingHotKey else { return }
        let now = Date()
        guard now.timeIntervalSince(lastTriggerAt) > 0.7 else { return }
        lastTriggerAt = now
        isBusy = true
        captureGeneration += 1
        let generation = captureGeneration
        let target = targetApp
        let selected = selectedWindowID
        let title = selectedWindowTitle
        let destination = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let pressReturn = autoPressReturn
        captureTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.captureGeneration == generation { self.isBusy = false; self.captureTask = nil }
            }
            do {
                let image = try await WindowPasteCaptureService.capture(target: target, preferredWindowID: selected == 0 ? nil : selected, preferredTitle: title.isEmpty ? nil : title)
                try Task.checkCancellation()
                guard self.captureGeneration == generation else { return }
                guard WindowPasteClipboardService.copyImage(image) else {
                    self.present("无法写入截图，请重试。", success: false)
                    return
                }
                guard !copyOnly, let destination, destination != ProcessInfo.processInfo.processIdentifier else {
                    self.present("已复制截图，可在目标应用中粘贴。", success: true)
                    return
                }
                guard WindowPastePermissionService.hasAccessibility else {
                    self.present("已复制截图。开启辅助功能权限后可自动粘贴。", success: true)
                    return
                }
                let outcome = await WindowPasteClipboardService.pasteWhenReady(into: destination, pressReturn: pressReturn)
                guard !Task.isCancelled, self.captureGeneration == generation else { return }
                switch outcome {
                case .pasted: self.present("已粘贴截图", success: true)
                case .returned: self.present("已粘贴截图并回车", success: true)
                case .targetChanged: self.present("已复制截图，当前应用已切换，未自动粘贴。", success: true)
                case .keysHeld: self.present("已复制截图，请松开修饰键后手动粘贴。", success: true)
                case .unavailable: self.present("已复制截图，请检查辅助功能权限。", success: false)
                case .cancelled: break
                }
                self.refreshPermissions()
            } catch is CancellationError { } catch {
                guard self.captureGeneration == generation else { return }
                self.present(error.localizedDescription, success: false)
                self.refreshPermissions()
            }
        }
    }

    func setTarget(_ target: WindowPasteTargetApp) {
        guard target != targetApp else { return }
        cancelPendingCapture()
        refreshGeneration += 1
        previewTask?.cancel()
        availableWindows = []
        windowPreviews = [:]
        windowLoadError = nil
        targetApp = target
        defaults.set(try? JSONEncoder().encode(target), forKey: Self.prefix + "target")
        setSelectedWindow(id: 0)
        Task { await refreshWindows() }
    }

    func setSelectedWindow(id: UInt32) {
        if id != selectedWindowID { cancelPendingCapture() }
        selectedWindowID = id
        selectedWindowTitle = id == 0 ? "" : availableWindows.first(where: { $0.windowID == id })?.title ?? ""
        defaults.set(Int(id), forKey: Self.prefix + "windowID")
        defaults.set(selectedWindowTitle, forKey: Self.prefix + "windowTitle")
    }

    func refreshWindows() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let target = targetApp
        previewTask?.cancel()
        windowPreviews = [:]
        windowLoadError = nil
        isRefreshingWindows = true
        defer { if refreshGeneration == generation { isRefreshingWindows = false } }
        refreshPermissions()
        do {
            let windows = try await WindowPasteCaptureService.listWindows(for: target)
            guard refreshGeneration == generation, !Task.isCancelled else { return }
            availableWindows = windows
            if selectedWindowID != 0, !windows.contains(where: { $0.windowID == selectedWindowID }),
               !selectedWindowTitle.isEmpty {
                let matches = windows.filter { $0.title == selectedWindowTitle }
                if matches.count == 1 { setSelectedWindow(id: matches[0].windowID) }
            }
            previewTask = Task { [weak self] in
                for window in windows.prefix(8) {
                    guard !Task.isCancelled, self?.refreshGeneration == generation else { return }
                    let image = try? await WindowPasteCaptureService.capture(target: target, preferredWindowID: window.windowID, preferredTitle: window.title, preview: true)
                    guard !Task.isCancelled, self?.refreshGeneration == generation else { return }
                    if let image { self?.windowPreviews[window.windowID] = image }
                }
            }
            await previewTask?.value
        } catch {
            guard refreshGeneration == generation else { return }
            availableWindows = []
            windowLoadError = error.localizedDescription
        }
    }

    func refreshPermissions() {
        hasScreenRecording = WindowPastePermissionService.hasScreenRecording
        hasAccessibility = WindowPastePermissionService.hasAccessibility
    }

    func runningApps() -> [WindowPasteTargetApp] {
        var apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            .compactMap { app -> WindowPasteTargetApp? in
                guard app.bundleIdentifier != Bundle.main.bundleIdentifier, let name = app.localizedName else { return nil }
                return .init(name: name, bundleIdentifier: app.bundleIdentifier)
            }
        if !targetApp.isMirror, !apps.contains(where: { $0.id == targetApp.id }) { apps.append(targetApp) }
        var seen = Set<String>()
        return [.mirror] + apps.filter { !$0.isMirror && seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func setAutoPressReturn(_ enabled: Bool) {
        autoPressReturn = enabled
        defaults.set(enabled, forKey: Self.prefix + "autoReturn")
    }

    func refreshLaunchAtLogin() { launchAtLogin = SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
        } catch { present("登录启动设置失败：\(error.localizedDescription)", success: false) }
        refreshLaunchAtLogin()
    }

    func toggleHotKeyRecording() {
        if isRecordingHotKey { cancelHotKeyRecording(); return }
        hotKeyWarning = nil
        isRecordingHotKey = true
        WindowPasteHotKeyManager.shared.suspend()
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.window?.identifier?.rawValue == "com.liangyu.airmirror.windowpaste" else {
                self?.cancelHotKeyRecording()
                return event
            }
            if event.keyCode == UInt16(kVK_Escape) { self?.cancelHotKeyRecording(); return nil }
            if let shortcut = WindowPasteHotKey(event: event) { self?.applyHotKey(shortcut) }
            return nil
        }
    }

    func cancelHotKeyRecording() {
        guard isRecordingHotKey else { return }
        finishRecording(resume: isEnabled)
    }

    func restoreDefaultHotKey() { applyHotKey(.default) }

    func applyHotKey(_ shortcut: WindowPasteHotKey) {
        finishRecording(resume: false)
        if let problem = shortcut.problem() {
            switch problem { case .invalid(let text), .conflict(let text), .failed(let text): hotKeyWarning = text; case .registered: break }
            if isEnabled { WindowPasteHotKeyManager.shared.resume() }
            return
        }
        if isEnabled {
            switch WindowPasteHotKeyManager.shared.apply(shortcut) {
            case .registered: break
            case .invalid(let text), .conflict(let text), .failed(let text): hotKeyWarning = text; return
            }
        }
        hotKey = shortcut
        hotKeyWarning = nil
        defaults.set(Int(shortcut.keyCode), forKey: Self.prefix + "hotKeyCode")
        defaults.set(Int(shortcut.carbonModifiers), forKey: Self.prefix + "hotKeyModifiers")
    }

    private func registerHotKey() {
        switch WindowPasteHotKeyManager.shared.apply(hotKey) {
        case .registered: hotKeyWarning = nil
        case .invalid(let text), .conflict(let text), .failed(let text):
            hotKeyWarning = text + "。如果独立版窗贴正在运行，请退出它或修改此处快捷键。"
        }
    }

    private func cancelPendingCapture() {
        captureGeneration += 1
        captureTask?.cancel()
        captureTask = nil
        isBusy = false
    }

    private func finishRecording(resume: Bool) {
        isRecordingHotKey = false
        if let recordingMonitor { NSEvent.removeMonitor(recordingMonitor); self.recordingMonitor = nil }
        if resume { WindowPasteHotKeyManager.shared.resume() }
    }

    private func present(_ text: String, success: Bool) {
        lastMessage = text
        WindowPasteHUDController.shared.show(text: text, success: success)
    }
}

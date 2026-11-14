import AppKit
import SwiftUI

/// One auxiliary window; it never owns, replaces, or stops the mirroring receiver.
@MainActor
final class WindowPasteWindowController: NSObject, NSWindowDelegate {
    static let shared = WindowPasteWindowController()
    static let identifier = NSUserInterfaceItemIdentifier("com.liangyu.airmirror.windowpaste")
    private(set) var window: NSWindow?

    func show() {
        let state = WindowPasteState.shared
        state.prepareForOpening()
        if window == nil {
            let hosting = NSHostingController(rootView: WindowPasteView().environmentObject(state))
            let window = NSWindow(contentViewController: hosting)
            window.title = "窗贴 · 镜投辅助功能"
            window.identifier = Self.identifier
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            let height = min(760, (NSScreen.main?.visibleFrame.height ?? 860) - 90)
            window.setContentSize(NSSize(width: 520, height: max(560, height)))
            window.contentMinSize = NSSize(width: 460, height: 560)
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.delegate = self
            window.collectionBehavior = [.managed, .moveToActiveSpace, .fullScreenAuxiliary]
            window.tabbingMode = .disallowed
            window.appearance = NSAppearance(named: .darkAqua)
            window.animationBehavior = .documentWindow
            window.center()
            window.setFrameAutosaveName("AirMirror.WindowPaste.Auxiliary")
            self.window = window
        }
        state.refreshPermissions()
        state.refreshLaunchAtLogin()
        Task { await state.refreshWindows() }
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowDidResignKey(_ notification: Notification) { WindowPasteState.shared.cancelHotKeyRecording() }
    func windowWillMiniaturize(_ notification: Notification) { WindowPasteState.shared.cancelHotKeyRecording() }
    func windowWillClose(_ notification: Notification) { WindowPasteState.shared.cancelHotKeyRecording() }
}

struct AuxiliaryCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var state = WindowPasteState.shared

    var body: some Commands {
        CommandMenu("辅助功能") {
            Button("窗贴 · 截图与粘贴…") { WindowPasteWindowController.shared.show() }
            Button("显示投屏窗口") { openWindow(id: "mirror") }
            Divider()
            Toggle("启用窗贴快捷键", isOn: Binding(get: { state.isEnabled }, set: { state.setEnabled($0) }))
            Button("复制目标窗口截图") { state.copyScreenshot() }
                .disabled(state.isBusy)
        }
    }
}

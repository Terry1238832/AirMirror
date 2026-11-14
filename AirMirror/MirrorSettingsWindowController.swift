import AppKit
import SwiftUI

/// A single settings window that shares the active receiver's state.
@MainActor
final class MirrorSettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = MirrorSettingsWindowController()
    static let identifier = NSUserInterfaceItemIdentifier("com.liangyu.airmirror.settings")
    private(set) var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: MirrorSettingsView().environmentObject(AppState.shared))
            let window = NSWindow(contentViewController: hosting)
            window.title = "设置 · 镜投"
            window.identifier = Self.identifier
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            let availableHeight = (NSScreen.main?.visibleFrame.height ?? 820) - 100
            window.setContentSize(NSSize(width: 460, height: min(720, max(480, availableHeight))))
            window.contentMinSize = NSSize(width: 400, height: 480)
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.delegate = self
            window.collectionBehavior = [.managed, .moveToActiveSpace, .fullScreenAuxiliary]
            window.tabbingMode = .disallowed
            window.appearance = NSAppearance(named: .darkAqua)
            window.animationBehavior = .documentWindow
            window.center()
            window.setFrameAutosaveName("AirMirror.Settings")
            self.window = window
        }
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { window?.performClose(nil) }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Closing an auxiliary window should return focus to an already visible projection.
        // A deliberately hidden or minimized projection stays that way.
        let projection = MirrorWindowRegistry.window
        DispatchQueue.main.async { [weak sender, weak projection] in
            guard sender?.isVisible == false, let projection,
                  projection.isVisible, !projection.isMiniaturized else { return }
            projection.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }
}

import AppKit
import SwiftUI

@main
struct AirMirrorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var appState = AppState.shared

    var body: some Scene {
        Window("镜投", id: "mirror") {
            ContentView()
                .environmentObject(appState)
        }
        .defaultSize(width: 480, height: 402)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { MirrorSettingsWindowController.shared.show() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            ConnectionCommands()
            AuxiliaryCommands()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        AppState.shared.start()
        WindowPasteState.shared.start()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !WindowPasteState.shared.isEnabled
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, !MirrorWindowRegistry.restore(), WindowPasteState.shared.isEnabled {
            WindowPasteWindowController.shared.show()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.stopReceiver()
        WindowPasteState.shared.stop()
    }
}

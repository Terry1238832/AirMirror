import AppKit
import SwiftUI

@main
struct AirMirrorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var language = LanguagePreferences.shared

    var body: some Scene {
        Window(AppBrand.name, id: "mirror") {
            ContentView()
                .environmentObject(appState)
                .appLanguageEnvironment()
                .sheet(isPresented: Binding(get: { language.needsInitialChoice }, set: { _ in })) {
                    LanguageWelcomeView().interactiveDismissDisabled()
                }
        }
        .defaultSize(width: 480, height: 402)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button(L10n.tr("设置…")) { MirrorSettingsWindowController.shared.show() }
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
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        if !LanguagePreferences.shared.needsInitialChoice {
            AppState.shared.start()
            WindowPasteState.shared.start()
        }
        DispatchQueue.main.async { NativeMenuLocalization.update() }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        LanguagePreferences.shared.needsInitialChoice || !WindowPasteState.shared.isEnabled
    }

    func applicationDidUpdate(_ notification: Notification) {
        // SwiftUI may recreate standard AppKit menus after the language publisher fires.
        NativeMenuLocalization.update()
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

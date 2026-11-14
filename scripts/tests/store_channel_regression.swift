import AppKit
import Foundation

@main struct StoreChannelRegression {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let name = "AirMirror.StoreRegression." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "windowPaste.autoReturn")
        let state = WindowPasteState(defaults: defaults)
        precondition(!state.autoPressReturn, "Store must ignore an existing auto-return preference")
        state.setAutoPressReturn(true)
        precondition(!state.autoPressReturn)
        precondition(!WindowPastePermissionService.hasAccessibility)
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        precondition(WindowPasteClipboardService.copyImage(image, to: board))
        precondition(board.data(forType: .png) != nil && board.data(forType: .tiff) != nil)
        let bridge = VideoBridge()
        precondition(bridge.socketPath.hasPrefix(FileManager.default.temporaryDirectory.path))
        try bridge.startListening()
        bridge.stopListening()
        print("PASS: Store copy-only preferences, no Accessibility access, PNG/TIFF and temporary video socket")
    }
}

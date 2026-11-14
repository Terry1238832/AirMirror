// Adapted from WindowPaste (MIT), upstream d8f6bcb86a419b410518264798f5931b2d3344d3.
import AppKit
import Carbon

@MainActor
enum WindowPasteClipboardService {
    enum PasteOutcome { case pasted, returned, targetChanged, keysHeld, cancelled, unavailable }

    @discardableResult
    static func copyImage(_ image: NSImage, to clipboard: NSPasteboard = .general) -> Bool {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        clipboard.clearContents()
        return clipboard.setData(tiff, forType: .tiff) && clipboard.setData(png, forType: .png)
    }

    static func pasteWhenReady(into processID: pid_t, pressReturn: Bool) async -> PasteOutcome {
        for _ in 0..<40 {
            guard !Task.isCancelled else { return .cancelled }
            if NSEvent.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty { break }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        guard !Task.isCancelled else { return .cancelled }
        guard NSEvent.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return .keysHeld }
        try? await Task.sleep(nanoseconds: 40_000_000)
        guard !Task.isCancelled else { return .cancelled }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == processID else { return .targetChanged }
        guard WindowPastePermissionService.hasAccessibility, postKey(kVK_ANSI_V, flags: .maskCommand) else { return .unavailable }
        if pressReturn {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return .cancelled }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == processID else { return .pasted }
            guard WindowPastePermissionService.hasAccessibility, postKey(kVK_Return, flags: []) else { return .pasted }
            return .returned
        }
        return .pasted
    }

    private static func postKey(_ keyCode: Int, flags: CGEventFlags) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false) else { return false }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}

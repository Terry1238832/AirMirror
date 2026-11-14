// Adapted from WindowPaste, MIT; upstream d8f6bcb86a419b410518264798f5931b2d3344d3.
#if !APP_STORE
import ApplicationServices
#endif
import AppKit
import CoreGraphics
import Foundation

enum WindowPastePermissionService {
    static var hasScreenRecording: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static var hasAccessibility: Bool {
        #if APP_STORE
        false
        #else
        AXIsProcessTrusted()
        #endif
    }

    static func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
    }

    #if !APP_STORE
    static func requestAccessibility() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [prompt: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
    #endif

    static func openScreenRecordingSettings() {
        openSettings([
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        ])
    }

    #if !APP_STORE
    static func openAccessibilitySettings() {
        openSettings([
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ])
    }
    #endif

    private static func openSettings(_ candidates: [String]) {
        for value in candidates {
            if let url = URL(string: value), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

// Adapted from WindowPaste, MIT; upstream d8f6bcb86a419b410518264798f5931b2d3344d3.
import AppKit
import Foundation

struct WindowPasteTargetApp: Codable, Equatable, Identifiable, Hashable {
    var name: String
    var bundleIdentifier: String?

    var id: String {
        bundleIdentifier ?? name
    }

    static let mirror = WindowPasteTargetApp(name: "镜投（投屏画面）", bundleIdentifier: "com.liangyu.airmirror")

    var isMirror: Bool { bundleIdentifier == Self.mirror.bundleIdentifier }
    var displayName: String { isMirror ? L10n.tr("镜投（投屏画面）") : name }

    static let letsView = WindowPasteTargetApp(
        name: "LetsView",
        bundleIdentifier: "com.wangxutech.letsview"
    )

    func matches(runningApp app: NSRunningApplication) -> Bool {
        if let bundleIdentifier, let other = app.bundleIdentifier, bundleIdentifier == other {
            return true
        }
        if bundleIdentifier != nil, app.bundleIdentifier != nil { return false }
        return app.localizedName?.caseInsensitiveCompare(name) == .orderedSame
    }

    func matches(applicationName: String?, bundleIdentifier: String?) -> Bool {
        if let expected = self.bundleIdentifier,
           let actual = bundleIdentifier,
           expected == actual {
            return true
        }
        if self.bundleIdentifier != nil, bundleIdentifier != nil { return false }
        guard let applicationName else { return false }
        if applicationName.caseInsensitiveCompare(name) == .orderedSame {
            return true
        }
        return false
    }
}

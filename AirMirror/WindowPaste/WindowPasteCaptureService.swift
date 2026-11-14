// Adapted from WindowPaste (MIT), upstream d8f6bcb86a419b410518264798f5931b2d3344d3.
import AppKit
import ScreenCaptureKit

enum WindowPasteCaptureError: LocalizedError {
    case permissionDenied
    case appNotRunning(String)
    case windowNotFound(String)
    case noVideo

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "请在权限设置中允许镜投录制屏幕，才能截取其他应用窗口。"
        case .appNotRunning(let name): return "没有找到 \(name)，请先打开该软件。"
        case .windowNotFound(let name): return "没有找到「\(name)」。请保持窗口未最小化，刷新后重新选择。"
        case .noVideo: return "还没有可截取的投屏画面，请先连接 iPhone / iPad。"
        }
    }
}

@MainActor
enum WindowPasteCaptureService {
    static var supportsDirectMirrorCapture: Bool {
        if #available(macOS 14.4, *) { return true }
        return false
    }

    static func listWindows(for target: WindowPasteTargetApp) async throws -> [WindowPasteTargetWindow] {
        if target.isMirror {
            guard let window = projectionWindow else { return [] }
            let size = AppState.shared.video.videoSize
            let fallback = window.contentLayoutRect.size
            return [.init(windowID: UInt32(window.windowNumber), title: "镜投投屏画面",
                          width: Int(size.width > 1 ? size.width : fallback.width),
                          height: Int(size.height > 1 ? size.height : fallback.height), isOnScreen: true)]
        }
        guard WindowPastePermissionService.hasScreenRecording else { throw WindowPasteCaptureError.permissionDenied }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return eligibleWindows(content.windows, target: target).map {
            .init(windowID: $0.windowID, title: $0.title ?? "", width: Int($0.frame.width), height: Int($0.frame.height), isOnScreen: $0.isOnScreen)
        }
    }

    static func capture(target: WindowPasteTargetApp, preferredWindowID: UInt32? = nil, preferredTitle: String? = nil, preview: Bool = false) async throws -> NSImage {
        if target.isMirror {
            guard let window = projectionWindow else { throw WindowPasteCaptureError.windowNotFound("镜投投屏窗口") }
            guard AppState.shared.video.hasVideo else { throw WindowPasteCaptureError.noVideo }
            if let image = AppState.shared.video.copyCurrentFrame() { return image }
            // macOS 14.0–14.3 has no decoded-frame snapshot API; retain window capture there.
            guard WindowPastePermissionService.hasScreenRecording else { throw WindowPasteCaptureError.permissionDenied }
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let source = content.windows.first(where: { $0.windowID == UInt32(window.windowNumber) }) else {
                throw WindowPasteCaptureError.windowNotFound("镜投投屏窗口")
            }
            return try await capture(window: source, preview: preview)
        }
        guard NSWorkspace.shared.runningApplications.contains(where: { target.matches(runningApp: $0) }) else {
            throw WindowPasteCaptureError.appNotRunning(target.name)
        }
        guard WindowPastePermissionService.hasScreenRecording else { throw WindowPasteCaptureError.permissionDenied }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let candidates = eligibleWindows(content.windows, target: target)
        let models = candidates.map {
            WindowPasteTargetWindow(windowID: $0.windowID, title: $0.title ?? "", width: Int($0.frame.width), height: Int($0.frame.height), isOnScreen: $0.isOnScreen)
        }
        guard let id = selectedWindowID(in: models, preferredID: preferredWindowID, preferredTitle: preferredTitle),
              let window = candidates.first(where: { $0.windowID == id }) else {
            throw WindowPasteCaptureError.windowNotFound(preferredTitle ?? target.name)
        }
        return try await capture(window: window, preview: preview)
    }

    /// An unavailable explicit selection must never silently capture a different document.
    static func selectedWindowID(in windows: [WindowPasteTargetWindow], preferredID: UInt32?, preferredTitle: String?) -> UInt32? {
        let visible = windows.filter(\.isOnScreen)
        if let id = preferredID, id != 0 {
            if visible.contains(where: { $0.windowID == id }) { return id }
            let title = preferredTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let matches = visible.filter { !$0.title.isEmpty && $0.title.trimmingCharacters(in: .whitespacesAndNewlines) == title }
            return !title.isEmpty && matches.count == 1 ? matches[0].windowID : nil
        }
        return visible.max { $0.width * $0.height < $1.width * $1.height }?.windowID
    }

    private static var projectionWindow: NSWindow? {
        guard let window = MirrorWindowRegistry.window, window.identifier == MirrorWindowRegistry.identifier,
              window.isVisible, !window.isMiniaturized, window.windowNumber > 0 else { return nil }
        return window
    }

    private static func eligibleWindows(_ windows: [SCWindow], target: WindowPasteTargetApp) -> [SCWindow] {
        windows.filter {
            $0.isOnScreen && $0.windowLayer == 0 && $0.frame.width >= 60 && $0.frame.height >= 60 &&
            $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier &&
            target.matches(applicationName: $0.owningApplication?.applicationName, bundleIdentifier: $0.owningApplication?.bundleIdentifier)
        }.sorted { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }
    }

    private static func capture(window: SCWindow, preview: Bool) async throws -> NSImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = max(CGFloat(filter.pointPixelScale), 1)
        let width = max(filter.contentRect.width, window.frame.width) * scale
        let height = max(filter.contentRect.height, window.frame.height) * scale
        let ratio = preview ? min(1, 360 / max(width, height, 1)) : 1
        configuration.width = max(Int((width * ratio).rounded()), 1)
        configuration.height = max(Int((height * ratio).rounded()), 1)
        configuration.showsCursor = false
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.shouldBeOpaque = true
        if #available(macOS 14.2, *) {
            configuration.ignoreShadowsSingleWindow = true
            configuration.captureResolution = preview ? .automatic : .best
        }
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        try Task.checkCancellation()
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

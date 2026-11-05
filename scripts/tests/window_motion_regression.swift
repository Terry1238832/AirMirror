// This harness is appended to VideoBridge.swift by test_window_motion.sh so it can
// exercise private layout code without expanding the production API. Windows stay hidden.

private enum WindowMotionRegressionFailure: Error { case assertion(String) }
private func auditCheck(_ ok: @autoclosure () -> Bool, _ message: String) throws {
    if !ok() { throw WindowMotionRegressionFailure.assertion(message) }
}
private func auditPump(_ duration: TimeInterval) {
    let end = Date().addingTimeInterval(duration)
    while Date() < end {
        _ = RunLoop.main.run(mode: .default, before: min(end, Date().addingTimeInterval(0.004)))
    }
}
extension WindowAspectLock {
    static func runWindowMotionRegression() throws {
        let bridge = VideoBridge()
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 640, height: 540), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let coordinator = Coordinator()
        func state(_ streaming: Bool, _ width: CGFloat, _ height: CGFloat, custom: Bool = false, scale: Double = 1, reset: Int = 0, reduced: Bool = false) -> WindowAspectLock {
            WindowAspectLock(streaming: streaming, videoSize: CGSize(width: width, height: height), allowsCustomAspect: custom, aspectScale: scale, resetToken: reset, reduceMotion: reduced, bridge: bridge)
        }
        func checkRatio(_ expected: CGFloat, _ label: String) throws {
            let size = window.contentRect(forFrameRect: window.frame).size
            try auditCheck(abs(size.width / size.height - expected) < 0.012, "\(label): actual \(size), ratio \(expected)")
            try auditCheck(!coordinator.isAnimating && !coordinator.delegate.correcting, "\(label): animation state did not settle")
            try auditCheck(abs(window.contentAspectRatio.width / window.contentAspectRatio.height - expected) < 0.012, "\(label): aspect lock did not settle")
        }
        state(false, 0, 0).apply(window, coordinator)
        try checkRatio(860 / 720, "initial waiting")
        state(true, 1024, 768).apply(window, coordinator)
        try auditCheck(coordinator.isAnimating, "stream begin failed to animate")
        let generation = coordinator.animationGeneration
        state(true, 2048, 1536).apply(window, coordinator)
        try auditCheck(coordinator.animationGeneration == generation, "same-aspect dimensions restarted animation")
        auditPump(0.5)
        try checkRatio(4 / 3, "stream begin")

        state(true, 768, 1024).apply(window, coordinator)
        try auditCheck(coordinator.isAnimating, "portrait failed to animate")
        auditPump(0.04)
        state(true, 1024, 768).apply(window, coordinator)
        auditPump(0.5)
        try checkRatio(4 / 3, "interrupted rotation")

        state(true, 768, 1024).apply(window, coordinator)
        auditPump(0.04)
        state(true, 768, 1024, reduced: true).apply(window, coordinator)
        try auditCheck(!coordinator.isAnimating, "reduce motion did not cancel")
        auditPump(0.5)
        try checkRatio(3 / 4, "reduced motion completion")

        state(true, 768, 1024, custom: true, scale: 1.4).apply(window, coordinator)
        try auditCheck(!coordinator.isAnimating, "custom ratio slider animated")
        try checkRatio(3 / 4 * 1.4, "custom aspect immediate")
        state(true, 768, 1024, reset: 1).apply(window, coordinator)
        try auditCheck(coordinator.isAnimating, "explicit reset failed to animate")
        auditPump(0.5)
        try checkRatio(3 / 4, "aspect reset")

        state(true, 1024, 768, reset: 1).apply(window, coordinator)
        // The app-local mouse-down monitor cancels before AppKit begins the user drag.
        coordinator.cancelResize(window)
        coordinator.lockedAspect = .zero
        NotificationCenter.default.post(name: NSWindow.willStartLiveResizeNotification, object: window)
        try auditCheck(!coordinator.isAnimating && !coordinator.delegate.correcting, "user resize did not cancel")
        NotificationCenter.default.post(name: NSWindow.didEndLiveResizeNotification, object: window)
        auditPump(0.5)
        try checkRatio(4 / 3, "user resize interruption")

        state(true, 768, 1024, reset: 1).apply(window, coordinator)
        NotificationCenter.default.post(name: NSWindow.willEnterFullScreenNotification, object: window)
        try auditCheck(!coordinator.isAnimating && coordinator.delegate.unlocked, "fullscreen did not cancel")
        coordinator.delegate.windowDidFailToEnterFullScreen(window)
        auditPump(0.5)
        try checkRatio(3 / 4, "fullscreen cancellation restoration")

        state(false, 0, 0, reset: 1).apply(window, coordinator)
        try auditCheck(coordinator.isAnimating, "stream end failed to animate")
        auditPump(0.5)
        try checkRatio(860 / 720, "stream end")
        window.close()
        print("PASS: native resize, source aspect retarget, Reduce Motion, slider, reset, live-resize/fullscreen interruption, and final ratio locks")
    }
}
@main private struct WindowMotionRegressionMain {
    static func main() {
        _ = NSApplication.shared
        do { try WindowAspectLock.runWindowMotionRegression() }
        catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
    }
}

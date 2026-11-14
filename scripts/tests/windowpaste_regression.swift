import AppKit
import AVFoundation
import Carbon

private enum WindowPasteTestError: Error { case failed(String) }
private func expect(_ value: @autoclosure () -> Bool, _ text: String) throws {
    if !value() { throw WindowPasteTestError.failed(text) }
}

private func makeFrame(width: Int, height: Int) throws -> CMSampleBuffer {
    var pixels: CVPixelBuffer?
    try expect(CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &pixels) == kCVReturnSuccess, "pixel buffer")
    guard let pixels else { throw WindowPasteTestError.failed("missing pixels") }
    CVPixelBufferLockBaseAddress(pixels, [])
    if let pointer = CVPixelBufferGetBaseAddress(pixels) { memset(pointer, 0xff, CVPixelBufferGetBytesPerRow(pixels) * height) }
    CVPixelBufferUnlockBaseAddress(pixels, [])
    var format: CMVideoFormatDescription?
    try expect(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixels, formatDescriptionOut: &format) == noErr, "format")
    guard let format else { throw WindowPasteTestError.failed("missing format") }
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 60), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    try expect(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixels, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample) == noErr, "sample")
    guard let sample else { throw WindowPasteTestError.failed("missing sample") }
    return sample
}

@main
private struct WindowPasteRegression {
    @MainActor static func main() {
        _ = NSApplication.shared
        var completed = false
        var failure: Error?
        Task { @MainActor in
            do { try await run() } catch { failure = error }
            completed = true
        }
        let deadline = Date().addingTimeInterval(25)
        while !completed && Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        if let failure { fputs("FAIL: \(failure)\n", stderr); exit(1) }
        if !completed { fputs("FAIL: windowpaste test timed out\n", stderr); exit(1) }
        print("PASS: independent capture source, native frame snapshots/rotation, no stale frame, selection identity, isolated preferences, PNG/TIFF and safe paste cancellation")
    }

    @MainActor private static func run() async throws {
        let suite = "AirMirror.WindowPasteRegression.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw WindowPasteTestError.failed("test defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = WindowPasteState(defaults: defaults)
        try expect(state.targetApp == .mirror && !state.isEnabled && !state.autoPressReturn, "defaults must be opt-in, mirror-first, with return disabled")
        state.setAutoPressReturn(true)
        state.setSelectedWindow(id: 321)
        let restored = WindowPasteState(defaults: defaults)
        try expect(restored.autoPressReturn && restored.selectedWindowID == 321, "namespaced preferences did not persist")
        state.applyHotKey(.init(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: UInt32(cmdKey)))
        try expect(state.hotKey == .default && state.hotKeyWarning != nil, "reserved shortcut was accepted")
        let app = WindowPasteTargetApp(name: "Example", bundleIdentifier: "test.correct")
        try expect(!app.matches(applicationName: "Example", bundleIdentifier: "test.wrong"), "bundle mismatch fell back to name")
        let windows: [WindowPasteTargetWindow] = [
            .init(windowID: 1, title: "first", width: 640, height: 480, isOnScreen: true),
            .init(windowID: 2, title: "second", width: 1280, height: 720, isOnScreen: true),
            .init(windowID: 3, title: "hidden", width: 1920, height: 1080, isOnScreen: false)
        ]
        try expect(WindowPasteCaptureService.selectedWindowID(in: windows, preferredID: nil, preferredTitle: nil) == 2, "automatic source selection")
        try expect(WindowPasteCaptureService.selectedWindowID(in: windows, preferredID: 1, preferredTitle: nil) == 1, "explicit source changed")
        try expect(WindowPasteCaptureService.selectedWindowID(in: windows, preferredID: 99, preferredTitle: "closed") == nil, "closed source fell back to another document")
        try expect(WindowPasteCaptureService.selectedWindowID(in: windows, preferredID: 99, preferredTitle: "first") == 1, "reopened source was not resolved")
        let bridge = AppState.shared.video
        let session = bridge.beginExternalSession()
        defer { bridge.stopListening() }
        try expect(bridge.copyCurrentFrame() == nil, "empty stream returned a snapshot")
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 640, height: 480), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = VideoHostView(layer: bridge.displayLayer)
        window.orderBack(nil)
        defer { window.close() }
        let auxiliary = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 500, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        auxiliary.isReleasedWhenClosed = false
        auxiliary.identifier = WindowPasteWindowController.identifier
        defer { auxiliary.close() }
        try expect(MirrorWindowRegistry.window === window, "auxiliary replaced the mirroring source")
        if #available(macOS 14.4, *) {
            for size in [CGSize(width: 640, height: 480), CGSize(width: 480, height: 640)] {
                let frame = try makeFrame(width: Int(size.width), height: Int(size.height))
                let deadline = Date().addingTimeInterval(5)
                var image: NSImage?
                repeat {
                    bridge.enqueueExternalSample(frame, session: session)
                    try await Task.sleep(nanoseconds: 25_000_000)
                    image = bridge.copyCurrentFrame()
                } while image?.size != size && Date() < deadline
                try expect(image?.size == size, "native snapshot unavailable or wrong orientation")
                let captured = try await WindowPasteCaptureService.capture(target: .mirror)
                try expect(captured.size == size && bridge.hasVideo, "capturing stopped or changed the mirroring stream")
                let clipboard = NSPasteboard.withUniqueName()
                defer { clipboard.releaseGlobally() }
                try expect(WindowPasteClipboardService.copyImage(captured, to: clipboard), "image copy failed")
                try expect(clipboard.data(forType: .png) != nil && clipboard.data(forType: .tiff) != nil, "missing paste formats")
            }
        }
        auxiliary.close()
        try expect(bridge.hasVideo && MirrorWindowRegistry.window === window, "closing auxiliary affected capture")
        bridge.endSession()
        try expect(bridge.copyCurrentFrame() == nil, "disconnected stream returned a stale snapshot")
        let cancelled = Task { await WindowPasteClipboardService.pasteWhenReady(into: -1, pressReturn: true) }
        cancelled.cancel()
        let result = await cancelled.value
        switch result { case .cancelled: break; default: throw WindowPasteTestError.failed("cancelled task attempted paste") }
        let changed = await WindowPasteClipboardService.pasteWhenReady(into: -1, pressReturn: true)
        switch changed { case .targetChanged, .keysHeld: break; default: throw WindowPasteTestError.failed("paste targeted a different application") }
        state.copyScreenshot()
        try expect(state.isBusy, "capture did not begin")
        state.setTarget(.init(name: "Fixture", bundleIdentifier: "test.airmirror.fixture"))
        try expect(!state.isBusy && state.selectedWindowID == 0, "source change retained pending capture")
        state.setTarget(.mirror)
        state.stop()
        defaults.set(false, forKey: "windowPaste.enabled")
        let disabled = WindowPasteState(defaults: defaults)
        disabled.prepareForOpening()
        try expect(!disabled.isEnabled, "reopening the tool overrode an explicitly disabled shortcut")
        disabled.stop()
    }
}

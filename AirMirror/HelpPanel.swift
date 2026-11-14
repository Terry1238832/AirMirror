import AppKit
import SwiftUI

/// A public-AppKit, arrowless help panel anchored to the question-mark button.
struct HelpPanelAnchor: NSViewRepresentable {
    @Binding var isPresented: Bool
    let content: AnyView

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ anchor: NSView, context: Context) {
        context.coordinator.presentation = $isPresented
        if isPresented {
            context.coordinator.show(content: content, from: anchor)
        } else {
            context.coordinator.hide()
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.hide()
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        var presentation: Binding<Bool>?
        private var panel: HelpPanel?
        private var hosting: NSHostingView<AnyView>?
        private weak var anchor: NSView?
        private weak var parent: NSWindow?
        private var eventMonitor: Any?
        private var observers: [NSObjectProtocol] = []

        func show(content: AnyView, from anchor: NSView) {
            guard let parent = anchor.window else { return }
            self.anchor = anchor
            self.parent = parent
            let screen = parent.screen ?? NSScreen.main
            guard let visible = screen?.visibleFrame else { return }

            let measure = NSHostingView(rootView: content)
            let height = min(ceil(measure.fittingSize.height), visible.height - 32)
            let size = NSSize(width: 360, height: max(200, height))
            let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
            let root = AnyView(
                ScrollView(.vertical, showsIndicators: false) { content }
                    .frame(width: size.width, height: size.height)
                    .background(.regularMaterial, in: shape)
                    .overlay(shape.strokeBorder(.white.opacity(0.1), lineWidth: 1))
                    .clipShape(shape)
            )

            if let hosting {
                hosting.rootView = root
            } else {
                let hosting = NSHostingView(rootView: root)
                let panel = HelpPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
                panel.identifier = NSUserInterfaceItemIdentifier("com.liangyu.airmirror.help")
                panel.title = L10n.tr("投屏教程")
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = true
                panel.isReleasedWhenClosed = false
                panel.isFloatingPanel = true
                panel.hidesOnDeactivate = true
                panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
                panel.appearance = NSAppearance(named: .darkAqua)
                panel.contentView = hosting
                panel.delegate = self
                self.hosting = hosting
                self.panel = panel
            }
            guard let panel else { return }
            let button = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let proposedX = L10n.language.isRightToLeft ? button.minX : button.maxX - size.width
            let x = min(max(proposedX, visible.minX + 16), visible.maxX - size.width - 16)
            let below = button.minY - 10 - size.height
            let proposedY = below >= visible.minY + 16 ? below : button.maxY + 10
            let y = min(max(proposedY, visible.minY + 16), visible.maxY - size.height - 16)
            panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
            guard !panel.isVisible else { return }

            parent.addChildWindow(panel, ordered: .above)
            panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
            panel.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.14
                panel.animator().alphaValue = 1
            }
            observeDismissal(in: parent)
        }

        func hide() {
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
            eventMonitor = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            guard let panel else { return }
            let restoreFocus = panel.isKeyWindow && NSApp.isActive
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            if restoreFocus, parent?.isVisible == true { parent?.makeKey() }
        }

        private func dismiss() {
            hide()
            presentation?.wrappedValue = false
        }

        private func observeDismissal(in parent: NSWindow) {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
                guard let self else { return event }
                if event.type == .keyDown, event.keyCode == 53 {
                    self.dismiss()
                    return nil
                }
                if event.type != .keyDown, event.window === self.parent {
                    // Let the question-mark button toggle the panel itself.
                    if let anchor = self.anchor {
                        let point = anchor.convert(event.locationInWindow, from: nil)
                        if anchor.bounds.contains(point) { return event }
                    }
                    self.dismiss()
                }
                return event
            }
            let center = NotificationCenter.default
            for name in [NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification,
                         NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                         NSWindow.willEnterFullScreenNotification, NSWindow.willExitFullScreenNotification] {
                observers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.dismiss() }
                })
            }
            observers.append(center.addObserver(forName: NSApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            })
        }

        func windowDidResignKey(_ notification: Notification) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.panel?.isVisible == true, let key = NSApp.keyWindow,
                      key !== self.panel, key.level.rawValue < NSWindow.Level.popUpMenu.rawValue else { return }
                self.dismiss()
            }
        }
    }
}

private final class HelpPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

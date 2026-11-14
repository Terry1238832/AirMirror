import SwiftUI

struct SoftButtonStyle: ButtonStyle {
    var hoverScale: CGFloat = 1

    func makeBody(configuration: Configuration) -> some View {
        SoftButtonContent(configuration: configuration, hoverScale: hoverScale)
    }
}

private struct SoftButtonContent: View {
    let configuration: ButtonStyleConfiguration
    let hoverScale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.65 : hovered ? 1 : 0.88) : 0.45)
            .scaleEffect(reduceMotion || !isEnabled ? 1 : configuration.isPressed ? 0.98 : hovered ? hoverScale : 1)
            .animation(.easeOut(duration: reduceMotion ? 0.08 : 0.16), value: hovered)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { hovered = $0 }
    }
}

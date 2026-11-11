import SwiftUI

/// Full-width dark pill pinned to the bottom of detail screens, like "Settle up".
struct PillButtonStyle: ButtonStyle {
    var fill: Color = .ink
    var text: Color = .canvas
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? 1 : 0.4)
            .font(AppFont.headline)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Capsule().fill(fill))
            .foregroundStyle(text)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

import SwiftUI

/// Send/Request style pills on the dark header: one filled white, one outlined.
struct HeaderPillButtonStyle: ButtonStyle {
    let filled: Bool
    var fill: Color = .onHeader
    var text: Color = .header

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.label)
            .padding(.horizontal, Spacing.l)
            .frame(minHeight: 44)
            .foregroundStyle(filled ? text : fill)
            .background(Capsule().fill(filled ? fill : Color.clear))
            .overlay(Capsule().stroke(fill.opacity(filled ? 0 : 0.35), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

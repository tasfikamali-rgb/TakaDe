import SwiftUI

/// A monochrome initial in a soft circle. The name itself is never altered; only its
/// first character is shown, which works for Bengali and Latin names alike.
struct Avatar: View {
    let name: String
    var size: CGFloat = 36
    var ring: Color = .surface
    var fill: Color = .surfaceRaised

    var body: some View {
        Text(verbatim: initial)
            .font(AppFont.text(size * 0.42, .semibold, relativeTo: .body))
            .foregroundStyle(Color.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(fill))
            .overlay(Circle().stroke(ring, lineWidth: 2))
            .accessibilityHidden(true)
    }

    private var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? "?"
    }
}

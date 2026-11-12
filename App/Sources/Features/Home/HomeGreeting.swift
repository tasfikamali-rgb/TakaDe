import SwiftUI

/// The Home headline before the first group: two short lines that end on an exclamation
/// mark whose dot blinks, like a cursor waiting for the first expense (Sabit, 2026-11-12).
/// The mark is drawn, not typed, so only its dot can blink. With Reduce Motion it holds still.
struct HomeGreeting: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The headline's point size, scaled with Dynamic Type so the drawn mark matches the text.
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Who owes who?")
            HStack(alignment: .lastTextBaseline, spacing: size * 0.08) {
                Text("We got receipts")
                BlinkingBang(size: size, blinks: !reduceMotion && !UserDefaults.standard.bool(forKey: "holdTexture"))
            }
        }
        .font(AppFont.display(32, relativeTo: .largeTitle))
        .foregroundStyle(Color.onHeader)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Who owes who? We got receipts!"))
        .accessibilityAddTraits(.isHeader)
    }
}

/// An exclamation mark sized to sit on the text baseline at cap height: a stem in the text
/// color and a dot in the accent that blinks on and off.
private struct BlinkingBang: View {
    let size: CGFloat
    let blinks: Bool

    var body: some View {
        VStack(spacing: size * 0.08) {
            Capsule(style: .continuous)
                .frame(width: size * 0.13, height: size * 0.48)
            Circle()
                .fill(Color.lime)
                .frame(width: size * 0.16, height: size * 0.16)
                .phaseAnimator([true, false]) { dot, isOn in
                    dot.opacity(isOn || !blinks ? 1 : 0)
                } animation: { isOn in
                    // On for most of a second, then a quick off, like a cursor.
                    isOn ? .easeIn(duration: 0.12).delay(0.3) : .easeOut(duration: 0.12).delay(0.8)
                }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    HomeGreeting().padding().background(Color.header)
}

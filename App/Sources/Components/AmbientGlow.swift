import SwiftUI

/// A soft band of light that drifts slowly behind the Home header, like light on folded
/// fabric. One color (`glow`) over the header color, heavily blurred, so it reads as
/// texture, never as content. Pale in light mode (no dark surfaces), deep blue in dark.
/// Holds still with Reduce Motion, and stops drawing while it's off screen.
struct AmbientGlow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    /// Seconds for one full drift. Slow enough to notice only when you look for it.
    private let period: Double = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { timeline in
            let phase = reduceMotion ? 0.15 : timeline.date.timeIntervalSinceReferenceDate / period * 2 * .pi
            Canvas { context, size in
                context.addFilter(.blur(radius: max(size.width, size.height) * 0.09))
                drawBand(in: &context, size: size, phase: phase)
                drawBloom(in: &context, size: size, phase: phase)
            }
            .opacity(colorScheme == .dark ? 1 : 0.8)
        }
        .background(Color.header)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }

    private var paused: Bool { reduceMotion || !isVisible || scenePhase != .active }

    /// A curved ribbon rising from bottom left to top right; its bend breathes with `phase`.
    private func drawBand(in context: inout GraphicsContext, size: CGSize, phase: Double) {
        let w = size.width, h = size.height
        let sway = CGFloat(sin(phase)) * h * 0.08
        let lift = CGFloat(cos(phase * 0.7)) * h * 0.05
        var edge = Path()
        edge.move(to: CGPoint(x: -w * 0.1, y: h * 0.95))
        edge.addCurve(to: CGPoint(x: w * 1.1, y: h * 0.25 + lift),
                      control1: CGPoint(x: w * 0.35, y: h * 0.55 + sway),
                      control2: CGPoint(x: w * 0.55, y: h * 0.2 - sway))
        // Thick ribbon: the same curve, offset down, closed into a shape.
        var band = edge
        band.addLine(to: CGPoint(x: w * 1.1, y: h * 0.45 + lift))
        band.addCurve(to: CGPoint(x: -w * 0.1, y: h * 1.15),
                      control1: CGPoint(x: w * 0.55, y: h * 0.4 - sway),
                      control2: CGPoint(x: w * 0.35, y: h * 0.75 + sway))
        band.closeSubpath()
        context.fill(band, with: .color(.glow.opacity(0.85)))
    }

    /// A wide, faint bloom above the ribbon that drifts side to side.
    private func drawBloom(in context: inout GraphicsContext, size: CGSize, phase: Double) {
        let w = size.width, h = size.height
        let cx = w * (0.5 + 0.12 * CGFloat(sin(phase * 0.5)))
        let cy = h * (0.35 + 0.06 * CGFloat(cos(phase * 0.8)))
        let rect = CGRect(x: cx - w * 0.45, y: cy - h * 0.25, width: w * 0.9, height: h * 0.5)
        context.fill(Path(ellipseIn: rect), with: .color(.glow.opacity(0.45)))
    }
}

#Preview {
    AmbientGlow().frame(height: 480).ignoresSafeArea()
}

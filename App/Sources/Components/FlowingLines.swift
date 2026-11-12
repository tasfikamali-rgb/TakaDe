import SwiftUI

/// Fine contour lines that ripple slowly behind the Home header, like the ruled lines of a
/// khata page lifting in a breeze. Crisp hairlines in one tint (`headerTexture`), no blur
/// or glow, so it reads as texture, not decoration. Holds still with Reduce Motion, and
/// stops drawing off screen and in the background.
struct FlowingLines: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @State private var isVisible = false

    /// Seconds for one full ripple cycle.
    private let period: Double = 18
    private let spacing: CGFloat = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate / period * 2 * .pi
            Canvas { context, size in
                let count = Int(size.height / spacing) + 2
                let step: CGFloat = 6
                for row in 0..<count {
                    let baseY = CGFloat(row) * spacing
                    // Each line bends a little more towards the bottom, and its crest drifts
                    // sideways, so the sheet seems to fold rather than scroll.
                    let depth = 0.35 + 0.65 * baseY / max(size.height, 1)
                    var path = Path()
                    var x: CGFloat = 0
                    while x <= size.width + step {
                        let u = x / max(size.width, 1)
                        let wave = sin(Double(u) * 2.2 * .pi + t + Double(row) * 0.18)
                            + 0.5 * sin(Double(u) * 4.1 * .pi - t * 0.6)
                        let y = baseY + CGFloat(wave) * 7 * depth
                        if x == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                        x += step
                    }
                    context.stroke(path, with: .color(.headerTexture), lineWidth: 1 / displayScale * 1.5)
                }
            }
            // Fade the lines out towards the balance so the numbers sit on clean colour.
            .mask(LinearGradient(colors: [.black.opacity(0.25), .black], startPoint: .top, endPoint: .bottom))
        }
        .background(Color.header)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }

    private var paused: Bool { reduceMotion || !isVisible || scenePhase != .active }
}

#Preview {
    FlowingLines().frame(height: 480).ignoresSafeArea()
}

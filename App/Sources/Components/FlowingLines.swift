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
    private let step: CGFloat = 6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { timeline in
            Canvas { context, size in
                draw(in: &context, size: size, phase: phase(at: timeline.date))
            }
            // Fade the lines out towards the top so the screen edge stays clean.
            .mask(LinearGradient(colors: [.black.opacity(0.25), .black], startPoint: .top, endPoint: .bottom))
        }
        .background(Color.header)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }

    private func phase(at date: Date) -> Double {
        guard !reduceMotion else { return 0 }
        return date.timeIntervalSinceReferenceDate / period * 2 * Double.pi
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, phase t: Double) {
        let count = Int(size.height / spacing) + 2
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let lineWidth: CGFloat = 1.5 / displayScale
        for row in 0..<count {
            let baseY = CGFloat(row) * spacing
            // Lines bend a little more towards the bottom, and the crest drifts sideways,
            // so the page seems to fold rather than scroll.
            let depth: CGFloat = 0.35 + 0.65 * baseY / height
            let rowShift = Double(row) * 0.18
            var path = Path()
            var x: CGFloat = 0
            while x <= width + step {
                let u = Double(x / width)
                let first: Double = sin(u * 2.2 * Double.pi + t + rowShift)
                let second: Double = 0.5 * sin(u * 4.1 * Double.pi - t * 0.6)
                let y: CGFloat = baseY + CGFloat(first + second) * 7 * depth
                let point = CGPoint(x: x, y: y)
                if x == 0 { path.move(to: point) } else { path.addLine(to: point) }
                x += step
            }
            context.stroke(path, with: .color(.headerTexture), lineWidth: lineWidth)
        }
    }

    private var paused: Bool { reduceMotion || !isVisible || scenePhase != .active }
}

#Preview {
    FlowingLines().frame(height: 480).ignoresSafeArea()
}

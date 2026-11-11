import SwiftUI

/// A capsule with a smooth dip cut into its top edge at `notchX`. Animating `notchX`
/// slides the dip between tabs.
struct NotchBarShape: Shape {
    var notchX: CGFloat
    var notchRadius: CGFloat = Self.defaultRadius
    var notchDepth: CGFloat = 22

    static let defaultRadius: CGFloat = 28

    /// The dip spans 1.6 radii either side of its center. Keeping the whole dip on the flat
    /// top edge stops it from running into the rounded ends (which drew a stray mark).
    static func clampedNotchX(_ x: CGFloat, width: CGFloat, height: CGFloat, radius: CGFloat = defaultRadius) -> CGFloat {
        let margin = height / 2 + radius * 1.6
        guard width > margin * 2 else { return width / 2 }
        return min(max(x, margin), width - margin)
    }

    var animatableData: CGFloat {
        get { notchX }
        set { notchX = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.height / 2
        let x = rect.minX + Self.clampedNotchX(notchX - rect.minX, width: rect.width, height: rect.height, radius: notchRadius)
        let left = x - notchRadius * 1.6
        let right = x + notchRadius * 1.6

        var p = Path()
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: left, y: rect.minY))
        // Liquid dip: two cubic curves meeting at the bottom of the notch.
        p.addCurve(to: CGPoint(x: x, y: rect.minY + notchDepth),
                   control1: CGPoint(x: left + notchRadius * 0.8, y: rect.minY),
                   control2: CGPoint(x: x - notchRadius * 0.9, y: rect.minY + notchDepth))
        p.addCurve(to: CGPoint(x: right, y: rect.minY),
                   control1: CGPoint(x: x + notchRadius * 0.9, y: rect.minY + notchDepth),
                   control2: CGPoint(x: right - notchRadius * 0.8, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.midY), radius: r, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.midY), radius: r, startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

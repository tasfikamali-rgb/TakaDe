import SwiftUI

/// A rounded card with a curved bite out of its top-right corner, where a round icon sits
/// apart from the card (DESIGN.md 1b, the stat-card cutout; the same liquid idea as the
/// nav notch). The bite is concentric with the icon, so the gap around it stays even.
struct CornerCutoutShape: Shape {
    var cornerRadius: CGFloat = Radius.card
    /// Diameter of the icon that sits in the bite.
    var iconDiameter: CGFloat = CornerCutoutShape.iconDiameter
    var gap: CGFloat = 6
    var fillet: CGFloat = 10

    static let iconDiameter: CGFloat = 40
    /// Width and height of the bite, for padding content away from it.
    static var biteSize: CGFloat { iconDiameter + 6 }

    func path(in rect: CGRect) -> Path {
        let bite = iconDiameter + gap
        // The inner corner's radius matches the icon plus the gap, centered on the icon.
        let inner = iconDiameter / 2 + gap
        let topLeft = CGPoint(x: rect.minX, y: rect.minY)
        let biteTop = CGPoint(x: rect.maxX - bite, y: rect.minY)
        let biteCorner = CGPoint(x: rect.maxX - bite, y: rect.minY + bite)
        let biteSide = CGPoint(x: rect.maxX, y: rect.minY + bite)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)

        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addArc(tangent1End: topLeft, tangent2End: biteTop, radius: cornerRadius)
        p.addArc(tangent1End: biteTop, tangent2End: biteCorner, radius: fillet)
        p.addArc(tangent1End: biteCorner, tangent2End: biteSide, radius: inner)
        p.addArc(tangent1End: biteSide, tangent2End: bottomRight, radius: fillet)
        p.addArc(tangent1End: bottomRight, tangent2End: bottomLeft, radius: cornerRadius)
        p.addArc(tangent1End: bottomLeft, tangent2End: topLeft, radius: cornerRadius)
        p.closeSubpath()
        return p
    }
}

/// The round icon that sits in a `CornerCutoutShape`'s bite.
struct CornerCutoutIcon: View {
    let systemImage: String
    var fill: Color = .surface

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.ink)
            .frame(width: CornerCutoutShape.iconDiameter, height: CornerCutoutShape.iconDiameter)
            .background(Circle().fill(fill))
            .accessibilityHidden(true)
    }
}

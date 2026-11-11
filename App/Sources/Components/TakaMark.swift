import SwiftUI

/// The TakaDe mark: the taka sign cut on a diagonal (docs/brand, ADR 17).
/// Each half is drawn in a unit square holding the whole sign, so the two halves fill the
/// same frame. `TakaMark` slides them apart along the cut by `split` (0 joined, 1 the logo).
/// Generated from Hind Siliguri SemiBold (OFL); regenerate with the brand script, don't edit.
enum TakaMarkHalf {
    case upper, lower
}

struct TakaMarkHalfShape: Shape {
    var half: TakaMarkHalf

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * side, y: origin.y + y * side) }
        switch half {
        case .upper:
            path.move(to: p(0.25061, 0.11000))
            path.addQuadCurve(to: p(0.38312, 0.16266), control: p(0.33509, 0.11000))
            path.addQuadCurve(to: p(0.43114, 0.30789), control: p(0.43114, 0.21531))
            path.addLine(to: p(0.43114, 0.35881))
            path.addLine(to: p(0.47859, 0.35881))
            path.addLine(to: p(0.47859, 0.47570))
            path.addLine(to: p(0.43114, 0.47570))
            path.addLine(to: p(0.43144, 0.53053))
            path.addLine(to: p(0.29806, 0.58991))
            path.addLine(to: p(0.29806, 0.47570))
            path.addLine(to: p(0.20200, 0.47570))
            path.addLine(to: p(0.20200, 0.35881))
            path.addLine(to: p(0.29806, 0.35881))
            path.addLine(to: p(0.29806, 0.32872))
            path.addQuadCurve(to: p(0.21705, 0.23499), control: p(0.29806, 0.23499))
            path.addQuadCurve(to: p(0.17539, 0.23614), control: p(0.18696, 0.23499))
            path.addLine(to: p(0.17539, 0.11694))
            path.addQuadCurve(to: p(0.25061, 0.11000), control: p(0.21936, 0.11000))
            path.closeSubpath()
            path.move(to: p(0.74210, 0.39221))
            path.addLine(to: p(0.55628, 0.47494))
            path.addQuadCurve(to: p(0.53645, 0.47801), control: p(0.54616, 0.47607))
            path.addLine(to: p(0.53645, 0.35997))
            path.addQuadCurve(to: p(0.60358, 0.35303), control: p(0.57117, 0.35303))
            path.addQuadCurve(to: p(0.74210, 0.39221), control: p(0.68880, 0.35303))
            path.closeSubpath()
        case .lower:
            path.move(to: p(0.55628, 0.47494))
            path.addLine(to: p(0.74210, 0.39221))
            path.addQuadCurve(to: p(0.76791, 0.41552), control: p(0.75610, 0.40251))
            path.addQuadCurve(to: p(0.82461, 0.58217), control: p(0.82461, 0.47801))
            path.addQuadCurve(to: p(0.74245, 0.79915), control: p(0.82461, 0.70831))
            path.addQuadCurve(to: p(0.52372, 0.89000), control: p(0.66028, 0.89000))
            path.addQuadCurve(to: p(0.36344, 0.83677), control: p(0.42883, 0.89000))
            path.addQuadCurve(to: p(0.29806, 0.68979), control: p(0.29806, 0.78353))
            path.addLine(to: p(0.29806, 0.58991))
            path.addLine(to: p(0.43144, 0.53053))
            path.addLine(to: p(0.43230, 0.68979))
            path.addQuadCurve(to: p(0.45834, 0.75228), control: p(0.43230, 0.73145))
            path.addQuadCurve(to: p(0.52372, 0.77312), control: p(0.48438, 0.77312))
            path.addQuadCurve(to: p(0.64350, 0.71699), control: p(0.59779, 0.77312))
            path.addQuadCurve(to: p(0.68921, 0.58217), control: p(0.68921, 0.66086))
            path.addQuadCurve(to: p(0.58506, 0.47338), control: p(0.68921, 0.47338))
            path.addQuadCurve(to: p(0.55628, 0.47494), control: p(0.57028, 0.47338))
            path.closeSubpath()
        }
        return path
    }
}

struct TakaMark: View {
    /// 0 draws the whole sign, 1 the logo with its halves apart. Animatable.
    var split: CGFloat = 1

    /// How far each half moves at `split == 1`, as a fraction of the frame's side.
    static let offset = CGSize(width: 0.05134, height: 0.00877)

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let dx = Self.offset.width * side * split
            let dy = Self.offset.height * side * split
            ZStack {
                TakaMarkHalfShape(half: .upper).offset(x: -dx, y: -dy)
                TakaMarkHalfShape(half: .lower).offset(x: dx, y: dy)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

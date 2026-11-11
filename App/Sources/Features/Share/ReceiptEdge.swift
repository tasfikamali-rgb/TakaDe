import SwiftUI

/// A rectangle whose bottom edge is a row of small scallops, like a torn bill.
/// TakaDe's one signature detail: it appears on shared summaries only.
struct ReceiptEdge: Shape {
    var toothWidth: CGFloat = 12
    var toothDepth: CGFloat = 6
    var cornerRadius: CGFloat = Radius.card

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let bottom = rect.maxY - toothDepth
        p.move(to: CGPoint(x: rect.minX, y: bottom))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        p.addQuadCurve(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: bottom))
        let count = max(Int(rect.width / toothWidth), 1)
        let step = rect.width / CGFloat(count)
        for i in (0..<count).reversed() {
            let x0 = rect.minX + CGFloat(i + 1) * step
            let x1 = rect.minX + CGFloat(i) * step
            p.addQuadCurve(to: CGPoint(x: x1, y: bottom), control: CGPoint(x: (x0 + x1) / 2, y: rect.maxY + toothDepth))
        }
        p.closeSubpath()
        return p
    }
}

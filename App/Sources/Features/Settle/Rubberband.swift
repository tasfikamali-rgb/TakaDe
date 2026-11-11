import CoreGraphics

/// Progressive resistance past a boundary (apple-design skill, section 9).
enum Rubberband {
    static func clamp(_ value: CGFloat, max: CGFloat, dimension: CGFloat = 120, constant: CGFloat = 0.55) -> CGFloat {
        if value < 0 { return 0 }
        if value <= max { return value }
        let over = value - max
        return max + (over * dimension * constant) / (dimension + constant * over)
    }
}

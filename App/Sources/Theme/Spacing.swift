import CoreGraphics

/// Spacing scale from DESIGN.md section 5, on a 4pt grid.
enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let huge: CGFloat = 48
    static let screenMargin: CGFloat = 20
    /// Width beyond which reading content stops growing on large screens.
    static let readableWidth: CGFloat = 680
}

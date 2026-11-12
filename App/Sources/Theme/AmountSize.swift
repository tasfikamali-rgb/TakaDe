import SwiftUI

/// Sizes for amounts. Large amounts drop the ৳ and the decimals to about 45% of the main
/// size (DESIGN.md section 3); small amounts keep them readable at 75%.
enum AmountSize {
    case keypad, balance, title, headline, bodyEmphasis, body, label, caption

    var points: CGFloat {
        switch self {
        case .keypad: 56
        case .balance: 48
        case .title: 28
        case .headline: 20
        case .bodyEmphasis, .body: 16
        case .label: 14
        case .caption: 12
        }
    }

    private var isDisplay: Bool { points >= 28 }
    private var style: Font.TextStyle {
        switch self {
        case .keypad, .balance: .largeTitle
        case .title: .title
        case .headline: .headline
        case .bodyEmphasis, .body: .body
        case .label: .subheadline
        case .caption: .caption
        }
    }

    /// The figure: Inter for 0-9, Anek Bangla for Bengali digits (ADR 23).
    func main(bengaliDigits: Bool) -> Font {
        AppFont.figures(points, isDisplay ? .semibold : (self == .body ? .regular : .medium), relativeTo: style, display: isDisplay, bengali: bengaliDigits)
    }

    /// The ৳ and the decimals. ৳ is a Bengali character, so it always comes from a face that has it.
    func minor(bengaliDigits: Bool) -> Font {
        // Below 16pt the minor part stays full size so it never drops under ~12pt.
        let ratio: CGFloat = isDisplay ? 0.45 : (points >= 16 ? 0.75 : 1)
        let size = (points * ratio).rounded()
        return AppFont.figures(size, isDisplay ? .semibold : .medium, relativeTo: style, display: isDisplay, bengali: bengaliDigits)
    }

    /// Tight negative tracking only on large display numbers, never on small text.
    var tracking: CGFloat {
        switch self {
        // Inter Display is already tightly spaced, so only a touch of negative tracking.
        case .keypad, .balance: -0.01 * points
        case .title: -0.005 * points
        default: 0
        }
    }
}

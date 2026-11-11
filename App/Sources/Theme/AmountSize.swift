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

    var main: Font {
        isDisplay ? AppFont.ranade(points, relativeTo: style)
            : AppFont.author(points, self == .body ? .regular : .medium, relativeTo: style)
    }

    var minor: Font {
        let size = (points * (isDisplay ? 0.45 : 0.75)).rounded()
        return isDisplay ? AppFont.ranade(size, relativeTo: style) : AppFont.author(size, .medium, relativeTo: style)
    }

    /// Tight negative tracking only on large display numbers, never on small text.
    var tracking: CGFloat {
        switch self {
        case .keypad, .balance: -0.03 * points
        case .title: -0.02 * points
        default: 0
        }
    }
}

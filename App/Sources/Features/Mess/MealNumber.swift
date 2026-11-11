import SwiftUI
import TakaDeCore

/// Half meals shown as meals: 3 becomes "1.5", 4 becomes "2", in the digits the person chose.
enum MealNumber {
    static func text(_ halfMeals: Int, digits: DigitStyle) -> String {
        let plain = halfMeals % 2 == 0 ? "\(halfMeals / 2)" : "\(halfMeals / 2).5"
        return digits == .bengali ? Digits.toBengali(plain) : plain
    }
}

/// A meal count in the person's digits, read aloud as "one and a half meals".
struct MealNumberText: View {
    let halfMeals: Int
    var font: Font = AppFont.bodyEmphasis

    @Environment(\.locale) private var locale

    var body: some View {
        Text(verbatim: MealNumber.text(halfMeals, digits: DigitPreference.style(for: locale)))
            .font(font)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(halfMeals)))
            .accessibilityLabel(Text("\(MealNumber.text(halfMeals, digits: .latin)) meals"))
    }
}

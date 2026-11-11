import SwiftUI
import TakaDeCore

struct KeypadDisplay: View {
    let expression: String
    let result: Money?

    var body: some View {
        VStack(spacing: Spacing.xs) {
            if AmountExpression.hasOperator(expression) {
                Text(verbatim: expression)
                    .font(AppFont.headline)
                    .foregroundStyle(Color.inkMuted)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            AmountText(money: result ?? .zero(), font: AppFont.keypad, color: result == nil ? .inkMuted : .ink)
                .animation(Motion.standard, value: result)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

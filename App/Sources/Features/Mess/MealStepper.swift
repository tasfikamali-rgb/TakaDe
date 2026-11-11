import SwiftUI

/// Minus and plus in half-meal steps around the count. Each button is a 44pt target, and
/// VoiceOver gets one adjustable element instead of three.
struct MealStepper: View {
    let halfMeals: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            stepButton("minus", to: halfMeals - 1).disabled(halfMeals == 0)
            MealNumberText(halfMeals: halfMeals)
                .foregroundStyle(halfMeals == 0 ? Color.inkMuted : Color.ink)
                .frame(minWidth: 36)
            stepButton("plus", to: halfMeals + 1).disabled(halfMeals >= 40)
        }
        .sensoryFeedback(.selection, trigger: halfMeals)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Meals"))
        .accessibilityValue(Text(verbatim: MealNumber.text(halfMeals, digits: .latin)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment where halfMeals < 40: onChange(halfMeals + 1)
            case .decrement where halfMeals > 0: onChange(halfMeals - 1)
            default: break
            }
        }
    }

    private func stepButton(_ symbol: String, to value: Int) -> some View {
        Button { onChange(value) } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.surfaceRaised).padding(Spacing.xxs))
        }
        .buttonStyle(PressScaleButtonStyle())
    }
}

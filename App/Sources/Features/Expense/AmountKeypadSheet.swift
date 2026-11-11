import SwiftUI
import TakaDeCore

/// Big amount, operator row and a 3×4 keypad (DESIGN.md section 4.4).
/// "1200 ÷ 4" works because splitting is the point.
struct AmountKeypadSheet: View {
    @Binding var expression: String
    let currency: Currency
    @Environment(\.dismiss) private var dismiss

    private var result: Money? { try? AmountExpression.evaluate(expression, currency: currency) }

    var body: some View {
        VStack(spacing: Spacing.l) {
            Spacer(minLength: Spacing.xl)
            KeypadDisplay(expression: expression, result: result)
            Spacer(minLength: Spacing.m)
            HStack(spacing: Spacing.s) {
                ForEach(KeypadKey.operators, id: \.self) { key in
                    KeypadButton(key: key, style: .operator, press: press)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.s), count: 3), spacing: Spacing.s) {
                ForEach(KeypadKey.grid, id: \.self) { key in
                    KeypadButton(key: key, style: .digit, press: press)
                }
            }
            Button("Done", action: done)
                .buttonStyle(PillButtonStyle())
                .disabled(result == nil)
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.bottom, Spacing.m)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .background(Color.canvas)
    }

    private func press(_ key: KeypadKey) {
        expression = KeypadText.applying(key, to: expression)
    }

    private func done() {
        // Collapse "1200÷4" to "300" so the form shows the result.
        if let result { expression = KeypadText.plain(result) }
        dismiss()
    }
}

#Preview {
    @Previewable @State var expression = "1200÷4"
    AmountKeypadSheet(expression: $expression, currency: .bdt)
}

import Foundation
import TakaDeCore

enum KeypadText {
    /// "1250.5" style text for a money value, suitable for the keypad.
    static func plain(_ money: Money) -> String {
        let digits = money.currency.minorUnitDigits
        guard money.minorPart != 0, digits > 0 else { return String(money.majorPart) }
        var fraction = String(money.minorPart)
        fraction = String(repeating: "0", count: digits - fraction.count) + fraction
        while fraction.hasSuffix("0") { fraction.removeLast() }
        return "\(money.majorPart).\(fraction)"
    }

    /// Applies one key press to the expression, refusing input that can't become valid.
    static func applying(_ key: KeypadKey, to text: String) -> String {
        switch key {
        case .delete:
            return String(text.dropLast())
        case .clear:
            return ""
        case .digit(let d):
            let candidate = text + String(d)
            // Allow at most two decimals in the number being typed.
            if let lastNumber = candidate.split(whereSeparator: { AmountExpression.operators.contains($0) }).last,
               let dot = lastNumber.firstIndex(of: ".") , lastNumber[lastNumber.index(after: dot)...].count > 2 {
                return text
            }
            return candidate.count > 24 ? text : candidate
        case .decimal:
            let lastNumber = text.split(omittingEmptySubsequences: false, whereSeparator: { AmountExpression.operators.contains($0) }).last ?? ""
            if lastNumber.contains(".") { return text }
            return text + (lastNumber.isEmpty ? "0." : ".")
        case .op(let symbol):
            guard let last = text.last else { return text }
            if AmountExpression.operators.contains(last) { return String(text.dropLast()) + String(symbol) }
            return text + String(symbol)
        }
    }
}

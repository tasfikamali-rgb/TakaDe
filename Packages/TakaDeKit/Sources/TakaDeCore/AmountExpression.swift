import Foundation

/// Evaluates what people type on the split keypad, like "1200 ÷ 4" or "450 + 120.50".
///
/// Arithmetic uses Foundation `Decimal` (base-10, not binary floating point). The result is
/// rounded once, at the end, to the currency's minor unit using half-up rounding, so
/// "100 ÷ 3" becomes 33.33. Supports + − × ÷ with the usual precedence, no parentheses.
public enum AmountExpression {
    public enum EvaluationError: Error, Equatable, Sendable {
        case empty
        case malformed
        case divisionByZero
        case negativeResult
        case tooLarge
    }

    public static let operators: Set<Character> = ["+", "−", "-", "×", "*", "÷", "/"]

    public static func evaluate(_ input: String, currency: Currency = .bdt) throws -> Money {
        let text = Digits.toLatin(input).replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")
        guard !text.isEmpty else { throw EvaluationError.empty }

        // Tokenize into alternating numbers and operators.
        var numbers: [Decimal] = []
        var ops: [Character] = []
        var current = ""
        for ch in text {
            if operators.contains(ch) {
                guard !current.isEmpty else { throw EvaluationError.malformed }
                numbers.append(try number(current))
                ops.append(normalize(ch))
                current = ""
            } else if ch.isASCIIDigit || ch == "." {
                current.append(ch)
            } else {
                throw EvaluationError.malformed
            }
        }
        // A trailing operator ("1200 ÷") is treated as still being typed: ignore it.
        if current.isEmpty {
            guard !ops.isEmpty else { throw EvaluationError.malformed }
            ops.removeLast()
        } else {
            numbers.append(try number(current))
        }

        // First pass: × and ÷.
        var terms: [Decimal] = [numbers[0]]
        var addOps: [Character] = []
        for (index, op) in ops.enumerated() {
            let rhs = numbers[index + 1]
            switch op {
            case "×": terms[terms.count - 1] *= rhs
            case "÷":
                guard rhs != 0 else { throw EvaluationError.divisionByZero }
                terms[terms.count - 1] /= rhs
            default:
                terms.append(rhs)
                addOps.append(op)
            }
        }
        // Second pass: + and −.
        var result = terms[0]
        for (index, op) in addOps.enumerated() {
            result = op == "+" ? result + terms[index + 1] : result - terms[index + 1] // op is "−"
        }

        guard result >= 0 else { throw EvaluationError.negativeResult }
        var scaled = result * Decimal(currency.minorUnitsPerMajor)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        guard rounded <= Decimal(Int64.max) else { throw EvaluationError.tooLarge }
        return Money(minorUnits: NSDecimalNumber(decimal: rounded).int64Value, currency: currency)
    }

    /// True if `input` contains an operator, so the UI can show "= ৳ 300.00" beneath it.
    public static func hasOperator(_ input: String) -> Bool {
        input.contains { operators.contains($0) }
    }

    private static func number(_ text: String) throws -> Decimal {
        guard text.filter({ $0 == "." }).count <= 1, text != ".",
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
        else { throw EvaluationError.malformed }
        return value
    }

    private static func normalize(_ op: Character) -> Character {
        switch op {
        case "-": "−"
        case "*": "×"
        case "/": "÷"
        default: op
        }
    }
}

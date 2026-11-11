import SwiftUI

enum KeypadKey: Hashable {
    case digit(Int)
    case decimal
    case delete
    case clear
    case op(Character)

    var label: String {
        switch self {
        case .digit(let d): String(d)
        case .decimal: "."
        case .delete: ""
        case .clear: "C"
        case .op(let c): String(c)
        }
    }

    var accessibilityLabel: LocalizedStringKey {
        switch self {
        case .digit(let d): "\(d)"
        case .decimal: "Decimal point"
        case .delete: "Delete"
        case .clear: "Clear"
        case .op("+"): "Plus"
        case .op("−"): "Minus"
        case .op("×"): "Times"
        case .op("÷"): "Divided by"
        case .op: "Operator"
        }
    }

    static let operators: [KeypadKey] = [.op("+"), .op("−"), .op("×"), .op("÷")]
    static let grid: [KeypadKey] = [
        .digit(1), .digit(2), .digit(3),
        .digit(4), .digit(5), .digit(6),
        .digit(7), .digit(8), .digit(9),
        .decimal, .digit(0), .delete,
    ]
}

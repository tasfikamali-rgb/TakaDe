import SwiftUI
import TakaDeCore

enum BalanceState {
    case owed, owes, settled

    init(_ net: Money) {
        self = net.isZero ? .settled : (net.minorUnits > 0 ? .owed : .owes)
    }

    var label: LocalizedStringKey {
        switch self {
        case .owed: "You are owed"
        case .owes: "You owe"
        case .settled: "Settled up"
        }
    }

    var color: Color {
        switch self {
        case .owed: .owed
        case .owes: .owe
        case .settled: .inkMuted
        }
    }

    var tint: Color {
        switch self {
        case .owed: .owedTint
        case .owes: .oweTint
        case .settled: .surfaceRaised
        }
    }
}

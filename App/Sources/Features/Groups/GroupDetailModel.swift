import Foundation
import Observation
import TakaDeCore

/// Loads everything one group screen shows.
@MainActor
@Observable
final class GroupDetailModel {
    private(set) var expenses: [Expense] = []
    private(set) var settlements: [Settlement] = []
    private(set) var balances: GroupBalances?

    func load(_ group: ExpenseGroup, from app: AppModel) async {
        expenses = (try? await app.repository.expenses(in: group.id, includeDeleted: false)) ?? []
        settlements = (try? await app.repository.settlements(in: group.id)) ?? []
        balances = try? await app.balances(for: group)
    }

    func myNet(in group: ExpenseGroup) -> Money? {
        guard let me = group.me, let balances else { return nil }
        return balances.net(for: me.id)
    }
}

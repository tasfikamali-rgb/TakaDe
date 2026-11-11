import Foundation
import TakaDeCore

/// The figures a group card shows.
struct GroupStats: Equatable {
    var myNet: Money
    var spent: Money
    var expenseCount: Int

    static let empty = GroupStats(myNet: .zero(), spent: .zero(), expenseCount: 0)

    @MainActor
    static func load(_ group: ExpenseGroup, from model: AppModel) async -> GroupStats {
        let expenses = (try? await model.repository.expenses(in: group.id, includeDeleted: false)) ?? []
        let spent = (try? expenses.map(\.total).sum(in: group.currency)) ?? .zero(group.currency)
        var net = Money.zero(group.currency)
        if let me = group.me, let balances = try? await model.balances(for: group) {
            net = balances.net(for: me.id)
        }
        return GroupStats(myNet: net, spent: spent, expenseCount: expenses.count)
    }
}

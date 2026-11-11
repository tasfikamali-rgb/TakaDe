import Foundation
import Observation
import TakaDeCore
import TakaDePersistence

/// App-wide state. Views read from here; all writes go through the repository.
@MainActor
@Observable
final class AppModel {
    private(set) var groups: [ExpenseGroup] = []
    private(set) var loadError: String?
    /// Bumped after every write so dependent views reload.
    private(set) var revision = 0
    let repository: LedgerRepository

    init(repository: LedgerRepository) {
        self.repository = repository
    }

    /// The on-device database, protected by iOS Data Protection until first unlock.
    static func live() -> AppModel {
        do {
            let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let url = dir.appendingPathComponent("ledger.sqlite")
            let repo = try SQLiteLedgerRepository(path: url.path)
            try? (url as NSURL).setResourceValue(URLFileProtection.completeUntilFirstUserAuthentication, forKey: .fileProtectionKey)
            return AppModel(repository: repo)
        } catch {
            let model = AppModel(repository: try! SQLiteLedgerRepository())
            model.loadError = String(localized: "Your saved data couldn't be opened, so changes made now won't be kept. Restart the app to try again.")
            return model
        }
    }

    static func preview() -> AppModel {
        AppModel(repository: try! SQLiteLedgerRepository())
    }

    func reload() async {
        do {
            groups = try await repository.groups()
            revision += 1
        } catch {
            loadError = String(localized: "Your groups couldn't be loaded. Restart the app to try again.")
        }
    }

    func group(_ id: GroupID) -> ExpenseGroup? {
        groups.first { $0.id == id }
    }

    func createGroup(name: String, myName: String, otherNames: [String]) async throws -> ExpenseGroup {
        let me = Member(displayName: myName, isMe: true)
        let others = otherNames.map { Member(displayName: $0) }
        let group = ExpenseGroup(name: name, members: [me] + others)
        try await repository.save(group, actor: me.id)
        await reload()
        return group
    }

    func addMember(named name: String, to group: ExpenseGroup) async throws {
        var updated = group
        updated.members.append(Member(displayName: name))
        try await repository.save(updated, actor: group.me?.id)
        await reload()
    }

    func save(_ expense: Expense, in group: ExpenseGroup) async throws {
        try await repository.save(expense, actor: group.me?.id)
        await reload()
    }

    func delete(_ expense: Expense, in group: ExpenseGroup) async throws {
        try await repository.delete(expense.id, actor: group.me?.id)
        await reload()
    }

    func record(_ settlement: Settlement, in group: ExpenseGroup) async throws {
        try await repository.save(settlement, actor: group.me?.id)
        await reload()
    }

    /// Net position of "me" across all groups. Assumes one currency (BDT) for now.
    func myTotal() async -> Money {
        var total: Int64 = 0
        for group in groups {
            guard let me = group.me, let balances = try? await balances(for: group) else { continue }
            total += balances.net(for: me.id).minorUnits
        }
        return Money(minorUnits: total)
    }

    func balances(for group: ExpenseGroup) async throws -> GroupBalances {
        let expenses = try await repository.expenses(in: group.id, includeDeleted: false)
        let settlements = try await repository.settlements(in: group.id)
        return try BalanceCalculator.balances(members: group.members.map(\.id), currency: group.currency, expenses: expenses, settlements: settlements)
    }

    /// Most recent expenses across every group, newest first.
    func recentActivity(limit: Int = 50) async -> [ActivityItem] {
        var items: [ActivityItem] = []
        for group in groups {
            let expenses = (try? await repository.expenses(in: group.id, includeDeleted: false)) ?? []
            items += expenses.map { ActivityItem(group: group, expense: $0) }
        }
        return Array(items.sorted { $0.expense.occurredAt > $1.expense.occurredAt }.prefix(limit))
    }
}

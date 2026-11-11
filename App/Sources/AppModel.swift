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
    /// The same database: the device owner's profile, export and erase.
    let profiles: ProfileRepository

    init(store: SQLiteLedgerRepository) {
        repository = store
        profiles = store
    }

    /// The on-device database, protected by iOS Data Protection until first unlock.
    static func live() -> AppModel {
        do {
            let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Ledger", isDirectory: true)
            // Protect the folder first, so the database and its journal files are created
            // encrypted (readable once the phone has been unlocked after a restart).
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            let url = dir.appendingPathComponent("ledger.sqlite")
            try Self.moveLegacyDatabase(to: url)
            let repo = try SQLiteLedgerRepository(path: url.path)
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
            return AppModel(store: repo)
        } catch {
            let model = AppModel(store: try! SQLiteLedgerRepository())
            model.loadError = String(localized: "Your saved data couldn't be opened, so changes made now won't be kept. Restart the app to try again.", bundle: .appLanguage)
            return model
        }
    }

    static func preview() -> AppModel {
        AppModel(store: try! SQLiteLedgerRepository())
    }

    /// Builds before 2026-11-11 kept the file directly in Application Support.
    private static func moveLegacyDatabase(to url: URL) throws {
        let legacy = url.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ledger.sqlite")
        let files = FileManager.default
        guard files.fileExists(atPath: legacy.path), !files.fileExists(atPath: url.path) else { return }
        try files.moveItem(at: legacy, to: url)
    }

    func reload() async {
        do {
            groups = try await repository.groups()
            revision += 1
        } catch {
            loadError = String(localized: "Your groups couldn't be loaded. Restart the app to try again.", bundle: .appLanguage)
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

    func setSimplifiesDebts(_ on: Bool, for group: ExpenseGroup) async throws {
        var updated = group
        updated.simplifiesDebts = on
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

    /// Brings back a soft-deleted expense (the undo after a delete).
    func restore(_ expense: Expense, in group: ExpenseGroup) async throws {
        var restored = expense
        restored.deletedAt = nil
        restored.version += 1
        try await repository.save(restored, actor: group.me?.id)
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

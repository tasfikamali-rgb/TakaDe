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
            model.loadError = "Your data couldn't be opened. Changes made now won't be saved. (\(error.localizedDescription))"
            return model
        }
    }

    static func preview() -> AppModel {
        AppModel(repository: try! SQLiteLedgerRepository())
    }

    func reload() async {
        do {
            groups = try await repository.groups()
        } catch {
            loadError = error.localizedDescription
        }
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
}

extension ExpenseGroup {
    var me: Member? { members.first(where: \.isMe) }
    func member(_ id: MemberID) -> Member? { members.first { $0.id == id } }
    func name(of id: MemberID) -> String { member(id)?.displayName ?? "?" }
}

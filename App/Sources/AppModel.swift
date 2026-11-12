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
    /// The same database: daily meal counts for mess groups.
    let mess: MessRepository
    /// The same database: which groups are shared and what still has to go up.
    let syncStore: SyncRepository
    /// Called after every change made on this phone, so a shared group syncs it.
    @ObservationIgnored var onLocalChange: ((GroupID) -> Void)?
    /// A group to open, e.g. right after joining one from a link.
    var requestedGroup: GroupID?

    init(store: SQLiteLedgerRepository) {
        repository = store
        profiles = store
        mess = store
        syncStore = store
    }

    private func changed(_ group: GroupID) {
        onLocalChange?(group)
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

    func createGroup(name: String, myName: String, otherNames: [String], kind: GroupKind = .standard, photo: Data? = nil) async throws -> ExpenseGroup {
        let me = Member(displayName: myName, isMe: true)
        let others = otherNames.map { Member(displayName: $0) }
        // In a mess, whoever sets it up on their phone keeps the books.
        var group = ExpenseGroup(name: name, members: [me] + others, kind: kind, managerID: kind == .mess ? me.id : nil)
        // A photo that can't be read is skipped; the group is still made.
        if let photo, let saved = try? await GroupPhotoFile.save(photo, for: group.id) {
            group.accentHex = saved.accentHex
        }
        try await repository.save(group, actor: me.id)
        await reload()
        return group
    }

    /// Sets the group's photo and takes the group's colour from it.
    func setGroupPhoto(_ data: Data, for group: ExpenseGroup) async throws {
        let saved = try await GroupPhotoFile.save(data, for: group.id)
        var updated = self.group(group.id) ?? group
        updated.accentHex = saved.accentHex
        try await repository.save(updated, actor: updated.me?.id)
        await reload()
    }

    /// Removes the photo; the group goes back to the standard colour.
    func removeGroupPhoto(for group: ExpenseGroup) async throws {
        GroupPhotoFile.remove(group.id)
        var updated = self.group(group.id) ?? group
        updated.accentHex = nil
        try await repository.save(updated, actor: updated.me?.id)
        await reload()
    }

    @discardableResult
    func addMember(named name: String, to group: ExpenseGroup) async throws -> Member? {
        try await addMembers(named: [name], to: group).first
    }

    /// Adds several people in one save, starting from the latest copy of the group so an
    /// earlier add isn't overwritten.
    @discardableResult
    func addMembers(named names: [String], to group: ExpenseGroup) async throws -> [Member] {
        guard !names.isEmpty else { return [] }
        var updated = self.group(group.id) ?? group
        let added = names.map { Member(displayName: $0) }
        updated.members.append(contentsOf: added)
        try await repository.save(updated, actor: group.me?.id)
        await reload()
        changed(group.id)
        return added
    }

    /// Takes someone out of a group, if nothing in it mentions them (see
    /// `LedgerRepository.removeMember`). Throws `MemberRemovalError` otherwise.
    func removeMember(_ member: Member, from group: ExpenseGroup) async throws {
        try await repository.removeMember(member.id, from: group.id, actor: group.me?.id)
        await reload()
        changed(group.id)
    }

    /// Sets or clears what this group calls someone. The person's name never changes.
    func setNickname(_ nickname: String?, for member: MemberID, in group: ExpenseGroup) async throws {
        var updated = self.group(group.id) ?? group
        guard let index = updated.members.firstIndex(where: { $0.id == member }) else { return }
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.members[index].nickname = trimmed?.isEmpty == false ? trimmed : nil
        try await repository.save(updated, actor: updated.me?.id)
        await reload()
        changed(group.id)
    }

    // MARK: Monthly repeats

    @ObservationIgnored private var addingRepeats = false

    /// Adds this month's copy of each repeating expense once its day has come. Safe to call
    /// often: months that already have a copy are skipped.
    func addDueRepeats() async {
        // Launch and coming back to the app can both call this; one run at a time, so a
        // month's copy is never added twice.
        guard !addingRepeats else { return }
        addingRepeats = true
        defer { addingRepeats = false }
        var added = false
        for group in groups where group.archivedAt == nil {
            guard let expenses = try? await repository.expenses(in: group.id, includeDeleted: true) else { continue }
            for copy in MonthlyRepeat.dueCopies(of: expenses) {
                if (try? await repository.save(copy, actor: nil)) != nil {
                    added = true
                    changed(group.id)
                }
            }
        }
        if added { await reload() }
    }

    // MARK: Mess

    func mealCounts(in group: ExpenseGroup, month: MessMonth) async -> [MealCount] {
        (try? await mess.mealCounts(in: group.id, month: month)) ?? []
    }

    func save(_ meal: MealCount, in group: ExpenseGroup) async throws {
        try await mess.save(meal, in: group.id, actor: group.me?.id)
        revision += 1
        changed(group.id)
    }

    func messSummary(for group: ExpenseGroup, month: MessMonth) async throws -> MessMonthSummary {
        let meals = await mealCounts(in: group, month: month)
        let expenses = try await repository.expenses(in: group.id, includeDeleted: false)
        return try MessMonthSummary(month: month, members: group.members.map(\.id), meals: meals, expenses: expenses, currency: group.currency)
    }

    /// Re-splits the month's bazar expenses by meals eaten. Each is an ordinary, audited edit.
    func applyMealSplit(_ summary: MessMonthSummary, in group: ExpenseGroup) async throws {
        guard let rule = summary.mealSplitRule else { return }
        for expense in summary.bazarExpenses where expense.splitRule != rule {
            let updated = try Expense(id: expense.id, groupID: expense.groupID, title: expense.title, total: expense.total,
                                      paidBy: expense.paidBy, splitRule: rule, occurredAt: expense.occurredAt,
                                      note: expense.note, category: expense.category, version: expense.version + 1,
                                      repeatsMonthly: expense.repeatsMonthly, repeatOf: expense.repeatOf,
                                      receiptID: expense.receiptID)
            try await repository.save(updated, actor: group.me?.id)
        }
        await reload()
        changed(group.id)
    }

    func setSimplifiesDebts(_ on: Bool, for group: ExpenseGroup) async throws {
        var updated = group
        updated.simplifiesDebts = on
        try await repository.save(updated, actor: group.me?.id)
        await reload()
        changed(group.id)
    }

    func save(_ expense: Expense, in group: ExpenseGroup) async throws {
        try await repository.save(expense, actor: group.me?.id)
        await reload()
        changed(group.id)
    }

    func delete(_ expense: Expense, in group: ExpenseGroup) async throws {
        try await repository.delete(expense.id, actor: group.me?.id)
        await reload()
        changed(group.id)
    }

    /// Brings back a soft-deleted expense (the undo after a delete).
    func restore(_ expense: Expense, in group: ExpenseGroup) async throws {
        var restored = expense
        restored.deletedAt = nil
        restored.version += 1
        try await repository.save(restored, actor: group.me?.id)
        await reload()
        changed(group.id)
    }

    func record(_ settlement: Settlement, in group: ExpenseGroup) async throws {
        try await repository.save(settlement, actor: group.me?.id)
        await reload()
        changed(group.id)
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

    /// Expenses and payments added, edited or deleted across every group, newest first,
    /// with who did it and what each edit changed.
    func recentActivity(limit: Int = 100, locale: Locale) async -> [ActivityItem] {
        var items: [ActivityItem] = []
        for group in groups {
            let events = (try? await repository.history(of: group.id)) ?? []
            items += ActivityFeed.items(for: events, in: group, entities: [.expense, .settlement], locale: locale)
        }
        return Array(items.sorted { $0.occurredAt > $1.occurredAt }.prefix(limit))
    }
}

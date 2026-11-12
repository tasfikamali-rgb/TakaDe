import SwiftUI
import TakaDeCore

/// One group: a lilac header with where you stand, and a sheet with balances, expenses
/// and payments sliding over it, the same two-layer structure as Home.
struct GroupDetailContent: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn
    @Environment(GroupSync.self) private var sync
    let group: ExpenseGroup

    @State private var model = GroupDetailModel()
    @State private var showingAddExpense = false
    @State private var showingSettle = false
    @State private var showingAddMember = false
    @State private var showingInvite = false
    @State private var pickingContacts = false
    @State private var newMemberName = ""
    @State private var duplicateMember: String?
    @State private var paymentMember: Member?
    @State private var removingMember: Member?
    @State private var recentlyDeleted: Expense?
    @State private var editing: Expense?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                GroupHeader(group: group, myNet: model.myNet(in: group), onAddExpense: addExpense) {
                    SyncStatusLabel(groupID: group.id)
                }
                GroupSheet(
                    group: group,
                    model: model,
                    errorMessage: errorMessage,
                    onOpen: open,
                    onDelete: delete,
                    onAddMember: askForMember,
                    onAddFromContacts: { pickingContacts = true },
                    onOpenMember: openMember,
                    onRemoveMember: { removingMember = $0 })
            }
            .frame(maxWidth: .infinity)
        }
        .background(alignment: .top) { Color.lilac.frame(height: 480).ignoresSafeArea() }
        .background(Color.canvas)
        .sheet(isPresented: $pickingContacts) { ContactSearchSheet(onPick: addContacts).rebuildsOnDynamicType() }
        .navigationTitle(Text(verbatim: group.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.lilac, for: .navigationBar)
        .toolbar {
            // The header already shows the name large; keep the title for Back and VoiceOver only.
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
            ToolbarItemGroup(placement: .primaryAction) {
                if sync.isAvailable {
                    Button("Invite people", systemImage: "person.crop.circle.badge.plus") { showingInvite = true }
                }
                if let balances = model.balances {
                    GroupShareButton(group: group, balances: balances)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let net = model.myNet(in: group), !net.isZero {
                Button("Settle up", action: settle)
                    .buttonStyle(PillButtonStyle())
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.top, Spacing.l)
                    .padding(.bottom, Spacing.xs)
                    .readableWidth()
                    .background {
                        // Rows pass under the pinned button; fade them out so the button reads cleanly.
                        LinearGradient(stops: [.init(color: Color.canvas.opacity(0), location: 0), .init(color: Color.canvas, location: 0.45)],
                                       startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }
            }
        }
        .overlay(alignment: .bottom) {
            if let recentlyDeleted {
                UndoBanner(message: String(localized: "Deleted \(recentlyDeleted.title)", bundle: .appLanguage), onUndo: undoDelete)
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.bottom, Spacing.huge + Spacing.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: recentlyDeleted.id) {
                        // With VoiceOver on, keep Undo until the next action instead of timing out.
                        guard !voiceOverOn else { return }
                        try? await Task.sleep(for: .seconds(8))
                        withAnimation(Motion.standard) { self.recentlyDeleted = nil }
                    }
            }
        }
        .sheet(isPresented: $showingInvite) {
            InviteSheet(group: group)
        }
        .refreshable { await sync.sync(group.id) }
        // While a shared group is open, others' changes show up within about 20 seconds.
        .task(id: group.id) {
            await sync.loadStates()
            while !Task.isCancelled {
                if sync.isShared(group.id) { await sync.sync(group.id) }
                try? await Task.sleep(for: .seconds(20))
            }
        }
        .sheet(isPresented: $showingAddExpense) {
            AddExpenseView(group: group)
        }
        .sheet(item: $editing) { expense in
            AddExpenseView(editing: expense, in: group, onDelete: delete)
        }
        .sheet(isPresented: $showingSettle) {
            if let balances = model.balances {
                SettleUpView(group: group, balances: balances, settlements: model.settlements)
            }
        }
        .sheet(item: $paymentMember) { member in
            // The sheet asks first, then closes itself.
            MemberPaymentSheet(group: group, member: member) { remove(member) }
        }
        .confirmationDialog(
            Text("Remove \(removingMember.map { group.displayName(of: $0.id) } ?? "") from this group?"),
            isPresented: Binding(get: { removingMember != nil }, set: { if !$0 { removingMember = nil } }),
            titleVisibility: .visible,
            presenting: removingMember
        ) { member in
            Button("Remove", role: .destructive) { remove(member) }
        }
        .alert("Add a person", isPresented: $showingAddMember) {
            TextField("Name", text: $newMemberName)
            Button("Add", action: checkNewMember)
            Button("Cancel", role: .cancel) { newMemberName = "" }
        }
        .confirmationDialog(
            Text("Someone here is already called \(duplicateMember ?? "")"),
            isPresented: Binding(get: { duplicateMember != nil }, set: { if !$0 { duplicateMember = nil } }),
            titleVisibility: .visible
        ) {
            Button("Add anyway", action: addMember)
            Button("Change the name") {
                duplicateMember = nil
                showingAddMember = true
            }
            Button("Cancel", role: .cancel) {
                duplicateMember = nil
                newMemberName = ""
            }
        } message: {
            Text("Add something to tell them apart, like an initial.")
        }
        .task(id: app.revision) { await model.load(group, from: app) }
    }

    private func addExpense() {
        recentlyDeleted = nil
        showingAddExpense = true
    }

    private func settle() {
        recentlyDeleted = nil
        showingSettle = true
    }

    private func open(_ expense: Expense) {
        recentlyDeleted = nil
        editing = expense
    }

    private func askForMember() { showingAddMember = true }

    /// Removes someone who isn't in any expense, payment or meal count. Otherwise says why
    /// they stay, so balances and history never change behind anyone's back.
    private func remove(_ member: Member) {
        removingMember = nil
        let name = group.displayName(of: member.id)
        Task {
            do {
                try await app.removeMember(member, from: group)
                errorMessage = nil
            } catch MemberRemovalError.hasEntries {
                errorMessage = String(localized: "\(name) is in expenses or payments in this group, so they stay. That keeps everyone's balance right.", bundle: .appLanguage)
            } catch MemberRemovalError.isManager {
                errorMessage = String(localized: "\(name) keeps this mess's books, so they stay.", bundle: .appLanguage)
            } catch {
                errorMessage = String(localized: "\(name) wasn't removed. Try again.", bundle: .appLanguage)
            }
        }
    }

    private func openMember(_ member: Member) {
        recentlyDeleted = nil
        paymentMember = member
    }

    /// Same check as a new group: a name already in the group, ignoring case and spaces,
    /// gets a warning. Both are allowed, and the name is never changed.
    private func checkNewMember() {
        let name = newMemberName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { newMemberName = ""; return }
        if let problem = NameRule.message(for: name) {
            errorMessage = problem
            newMemberName = ""
            return
        }
        let taken = group.members.contains {
            $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == name.lowercased()
        }
        if taken { duplicateMember = name } else { addMember() }
    }

    private func addMember() {
        let name = newMemberName.trimmingCharacters(in: .whitespacesAndNewlines)
        newMemberName = ""
        duplicateMember = nil
        guard !name.isEmpty else { return }
        Task {
            do {
                try await app.addMember(named: name, to: group)
                errorMessage = nil
            } catch {
                errorMessage = String(localized: "\(name) wasn't added. Try again.", bundle: .appLanguage)
            }
        }
    }

    /// Adds everyone picked. Someone already in the group, by the same name ignoring case
    /// and spaces, is left out and named in a note, so a double tap doesn't add them twice.
    private func addContacts(_ names: [String]) {
        let existing = Set(group.members.map { $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        var seen = existing
        var skipped: [String] = []
        var toAdd: [String] = []
        // Contact names with emoji or symbols are left out; they can be typed by hand.
        let notNames = names.filter { !PersonName.isValid($0) }
        for name in names where PersonName.isValid(name) {
            let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if seen.contains(key) { skipped.append(name) } else { seen.insert(key); toAdd.append(name) }
        }
        Task {
            do {
                try await app.addMembers(named: toAdd, to: group)
            } catch {
                errorMessage = String(localized: "\(toAdd.formatted(.list(type: .and))) wasn't added. Try again.", bundle: .appLanguage)
                return
            }
            if !skipped.isEmpty {
                errorMessage = String(localized: "\(skipped.formatted(.list(type: .and))) is already in this group.", bundle: .appLanguage)
            } else if !notNames.isEmpty {
                errorMessage = String(localized: "\(notNames.formatted(.list(type: .and))) wasn't added. Names can't have emoji, numbers or symbols. Add them with Type a name.", bundle: .appLanguage)
            } else {
                errorMessage = nil
            }
        }
    }

    private func delete(_ expense: Expense) {
        Task {
            do {
                try await app.delete(expense, in: group)
                errorMessage = nil
                withAnimation(Motion.standard) { recentlyDeleted = expense }
                AccessibilityNotification.Announcement(String(localized: "Expense deleted. Undo is available.", bundle: .appLanguage)).post()
            } catch {
                errorMessage = String(localized: "The expense wasn't deleted. Try again.", bundle: .appLanguage)
            }
        }
    }

    private func undoDelete() {
        guard let expense = recentlyDeleted else { return }
        withAnimation(Motion.standard) { recentlyDeleted = nil }
        Task {
            do {
                try await app.restore(expense, in: group)
            } catch {
                errorMessage = String(localized: "The expense couldn't be brought back. Add it again.", bundle: .appLanguage)
            }
        }
    }
}

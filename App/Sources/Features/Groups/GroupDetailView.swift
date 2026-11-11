import SwiftUI
import TakaDeCore

struct GroupDetailView: View {
    @Environment(AppModel.self) private var model
    let groupID: GroupID

    @State private var expenses: [Expense] = []
    @State private var settlements: [Settlement] = []
    @State private var balances: GroupBalances?
    @State private var showingAddExpense = false
    @State private var showingSettle = false
    @State private var showingAddMember = false
    @State private var newMemberName = ""

    private var group: ExpenseGroup? { model.groups.first { $0.id == groupID } }

    var body: some View {
        if let group {
            content(group)
        } else {
            ContentUnavailableView("Group not found", systemImage: "questionmark")
        }
    }

    private func content(_ group: ExpenseGroup) -> some View {
        List {
            if let balances {
                Section {
                    ForEach(group.members) { member in
                        HStack {
                            Text(member.isMe ? String(localized: "You") : member.displayName)
                                .font(AppFont.body)
                            Spacer()
                            BalancePill(net: balances.net(for: member.id))
                        }
                    }
                    if let me = group.me, let unverified = balances.unverifiedSettled[me.id], !unverified.isZero {
                        HStack(spacing: Spacing.xxs) {
                            Text("Includes payments reported in the app but not verified:")
                            AmountText(money: unverified, font: AppFont.caption, color: .inkMuted)
                        }
                        .font(AppFont.caption)
                        .foregroundStyle(Color.inkMuted)
                    }
                } header: {
                    Text("Balances")
                }
            }

            Section("Expenses") {
                if expenses.isEmpty {
                    Text("Nothing added yet.").foregroundStyle(Color.inkMuted)
                }
                ForEach(expenses) { expense in
                    ExpenseRow(expense: expense, group: group)
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                Task {
                                    try? await model.repository.delete(expense.id, actor: group.me?.id)
                                    await load(group)
                                }
                            }
                        }
                }
            }

            if !settlements.isEmpty {
                Section("Payments") {
                    ForEach(settlements) { s in
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            HStack {
                                Text("\(group.name(of: s.from)) paid \(group.name(of: s.to))")
                                    .font(AppFont.body)
                                Spacer()
                                AmountText(money: s.amount, font: AppFont.body)
                            }
                            Text(s.status.explanation)
                                .font(AppFont.caption)
                                .foregroundStyle(Color.inkMuted)
                        }
                    }
                }
            }

            Section {
                NavigationLink("History") { HistoryView(group: group) }
                Button("Add a person") { showingAddMember = true }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.canvas)
        .navigationTitle(group.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddExpense = true
                } label: {
                    Label("Add expense", systemImage: "plus")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let balances, let me = group.me, !balances.net(for: me.id).isZero {
                Button { showingSettle = true } label: {
                    Text("Settle up")
                        .font(AppFont.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Capsule().fill(Color.ink))
                        .foregroundStyle(Color.canvas)
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.bottom, Spacing.xs)
            }
        }
        .sheet(isPresented: $showingAddExpense, onDismiss: { Task { await load(group) } }) {
            AddExpenseView(group: group)
        }
        .sheet(isPresented: $showingSettle, onDismiss: { Task { await load(group) } }) {
            if let balances { SettleUpView(group: group, balances: balances) }
        }
        .alert("Add a person", isPresented: $showingAddMember) {
            TextField("Name", text: $newMemberName)
            Button("Add") {
                let name = newMemberName.trimmingCharacters(in: .whitespaces)
                newMemberName = ""
                guard !name.isEmpty else { return }
                Task { try? await model.addMember(named: name, to: group) }
            }
            Button("Cancel", role: .cancel) { newMemberName = "" }
        }
        .task(id: group) { await load(group) }
    }

    private func load(_ group: ExpenseGroup) async {
        expenses = (try? await model.repository.expenses(in: group.id, includeDeleted: false)) ?? []
        settlements = (try? await model.repository.settlements(in: group.id)) ?? []
        balances = try? await model.balances(for: group)
    }
}

private struct ExpenseRow: View {
    let expense: Expense
    let group: ExpenseGroup

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(expense.title).font(AppFont.body)
                Text(payerSummary)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.inkMuted)
            }
            Spacer()
            AmountText(money: expense.total, font: AppFont.body.weight(.semibold))
        }
    }

    private var payerSummary: String {
        let names = expense.paidBy.keys.map { group.member($0)?.isMe == true ? String(localized: "You") : group.name(of: $0) }
        return String(localized: "Paid by \(names.sorted().joined(separator: ", "))")
    }
}

extension SettlementStatus {
    /// Plain-language status. Never implies verification that didn't happen.
    var explanation: String {
        switch self {
        case .notStarted: String(localized: "Not started")
        case .handoffStarted: String(localized: "Opened the payment app. Not confirmed.")
        case .pending: String(localized: "Waiting for confirmation")
        case .reportedUnverified: String(localized: "Reported in TakaDe. Not verified with the provider.")
        case .confirmed: String(localized: "Confirmed by the provider")
        case .failed: String(localized: "Failed")
        case .reversed: String(localized: "Reversed")
        }
    }
}

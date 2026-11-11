import SwiftUI
import TakaDeCore

struct GroupDetailContent: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let group: ExpenseGroup

    @State private var model = GroupDetailModel()
    @State private var showingAddExpense = false
    @State private var showingSettle = false
    @State private var showingAddMember = false
    @State private var newMemberName = ""

    var body: some View {
        List {
            if let balances = model.balances {
                MemberBalancesSection(group: group, balances: balances)
            }
            ExpensesSection(group: group, expenses: model.expenses, onDelete: delete)
            if !model.settlements.isEmpty {
                PaymentsSection(group: group, settlements: model.settlements)
            }
            Section {
                NavigationLink("History") { HistoryView(group: group) }
                Button("Add a person", systemImage: "person.badge.plus", action: askForMember)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.canvas)
        .readableWidth()
        .navigationTitle(Text(verbatim: group.name))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add expense", systemImage: "plus", action: addExpense)
            }
            if let balances = model.balances {
                ToolbarItem(placement: .secondaryAction) {
                    GroupShareButton(group: group, balances: balances)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let net = model.myNet(in: group), !net.isZero {
                Button("Settle up", action: settle)
                    .buttonStyle(PillButtonStyle())
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.bottom, Spacing.xs)
                    .readableWidth()
            }
        }
        .sheet(isPresented: $showingAddExpense) {
            AddExpenseView(group: group)
        }
        .sheet(isPresented: $showingSettle) {
            if let balances = model.balances {
                SettleUpView(group: group, balances: balances)
            }
        }
        .alert("Add a person", isPresented: $showingAddMember) {
            TextField("Name", text: $newMemberName)
            Button("Add", action: addMember)
            Button("Cancel", role: .cancel) { newMemberName = "" }
        }
        .task(id: app.revision) { await model.load(group, from: app) }
    }

    private func addExpense() { showingAddExpense = true }
    private func settle() { showingSettle = true }
    private func askForMember() { showingAddMember = true }

    private func addMember() {
        let name = newMemberName.trimmingCharacters(in: .whitespaces)
        newMemberName = ""
        guard !name.isEmpty else { return }
        Task { try? await app.addMember(named: name, to: group) }
    }

    private func delete(_ expense: Expense) {
        Task { try? await app.delete(expense, in: group) }
    }
}

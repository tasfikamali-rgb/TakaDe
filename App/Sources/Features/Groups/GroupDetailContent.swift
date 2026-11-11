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
    @State private var recentlyDeleted: Expense?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section { Text(verbatim: errorMessage).foregroundStyle(Color.owe) }
            }
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
        .overlay(alignment: .bottom) {
            if let recentlyDeleted {
                UndoBanner(message: String(localized: "Deleted \(recentlyDeleted.title)", bundle: .appLanguage), onUndo: undoDelete)
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.bottom, Spacing.huge + Spacing.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: recentlyDeleted.id) {
                        try? await Task.sleep(for: .seconds(5))
                        withAnimation(Motion.standard) { self.recentlyDeleted = nil }
                    }
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
        Task {
            do {
                try await app.addMember(named: name, to: group)
                errorMessage = nil
            } catch {
                errorMessage = String(localized: "\(name) wasn't added. Try again.", bundle: .appLanguage)
            }
        }
    }

    private func delete(_ expense: Expense) {
        Task {
            do {
                try await app.delete(expense, in: group)
                errorMessage = nil
                withAnimation(Motion.standard) { recentlyDeleted = expense }
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

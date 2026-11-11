import SwiftUI
import TakaDeCore

/// One group: a lilac header with where you stand, and a sheet with balances, expenses
/// and payments sliding over it, the same two-layer structure as Home.
struct GroupDetailContent: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn
    let group: ExpenseGroup

    @State private var model = GroupDetailModel()
    @State private var showingAddExpense = false
    @State private var showingSettle = false
    @State private var showingAddMember = false
    @State private var newMemberName = ""
    @State private var recentlyDeleted: Expense?
    @State private var editing: Expense?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                GroupHeader(group: group, myNet: model.myNet(in: group), onAddExpense: addExpense)
                GroupSheet(
                    group: group,
                    model: model,
                    errorMessage: errorMessage,
                    onOpen: open,
                    onDelete: delete,
                    onAddMember: askForMember)
            }
            .frame(maxWidth: .infinity)
        }
        .background(alignment: .top) { Color.lilac.frame(height: 480).ignoresSafeArea() }
        .background(Color.canvas)
        .navigationTitle(Text(verbatim: group.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.lilac, for: .navigationBar)
        .toolbar {
            // The header already shows the name large; keep the title for Back and VoiceOver only.
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
            ToolbarItem(placement: .primaryAction) {
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
        .sheet(isPresented: $showingAddExpense) {
            AddExpenseView(group: group)
        }
        .sheet(item: $editing) { expense in
            AddExpenseView(editing: expense, in: group, onDelete: delete)
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

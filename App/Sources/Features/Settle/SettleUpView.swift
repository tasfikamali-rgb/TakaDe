import SwiftUI
import TakaDeCore

/// Records a payment made outside the app. TakaDe never moves money. If you paid, it's
/// saved as reported by you. If you were paid, you mark it received.
struct SettleUpView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let group: ExpenseGroup
    let balances: GroupBalances
    /// Earlier payments in this group, to catch a transaction id typed twice.
    var settlements: [Settlement] = []

    @State private var selected: SuggestedTransfer?
    @State private var method: SettlementMethod = .cash
    @State private var reference = ""
    @State private var saveError: String?
    @State private var recorded: SuggestedTransfer?
    @State private var payeeHandles: [PaymentHandle] = []
    @State private var myHandles: [PaymentHandle] = []
    @State private var simplifies: Bool?

    var body: some View {
        NavigationStack {
            LayeredForm {
                SettleUpHeader(group: group, transfer: selected, isSettled: myTransfers.isEmpty)
            } content: {
                TransferPickerSection(group: group, transfers: myTransfers, selected: $selected)
                Section {
                    Toggle("Fewest payments", isOn: Binding(get: { isSimplified }, set: setSimplified))
                } footer: {
                    Text(isSimplified
                         ? LocalizedStringKey("Debts are combined across the group, so fewer payments settle everyone. You may pay someone you didn't borrow from.")
                         : LocalizedStringKey("Each person pays the people they actually owe. This can mean more payments."))
                }
                if let selected, selected.from == group.me?.id, !payeeHandles.isEmpty {
                    Section {
                        ForEach(payeeHandles) { PaymentHandleRow(handle: $0) }
                        CopyRow(title: String(localized: "Amount", bundle: .appLanguage),
                                display: MoneyFormatter.format(selected.amount).plain,
                                value: KeypadText.plain(selected.amount))
                        ForEach(walletApps, id: \.self) { rail in
                            if let url = rail.walletAppURL {
                                Link(destination: url) {
                                    Label("Open \(rail.label)", systemImage: "arrow.up.forward.app")
                                        .font(AppFont.bodyEmphasis)
                                }
                                .accessibilityHint(Text("Opens the \(rail.label) app, or its App Store page if it isn't installed"))
                            }
                        }
                    } header: {
                        Text("Send to \(group.storedName(of: selected.to))")
                    } footer: {
                        Text("Copy the number and amount, pay in the app, then come back and record it. TakaDe doesn't send money or see the payment.")
                    }
                }
                if let selected, let me = group.me, selected.to == me.id {
                    Section {
                        ShareLink(item: ReminderText.make(to: group.storedName(of: selected.from), amount: selected.amount,
                                                          group: group.name, handles: myHandles)) {
                            Label("Remind \(group.storedName(of: selected.from))", systemImage: "bell")
                        }
                    } footer: {
                        Text("Sends a friendly message with the amount and your numbers through any chat app.")
                    }
                }
                if let selected {
                    PaymentDetailsSection(isMePaying: selected.from == group.me?.id, method: $method, reference: $reference,
                                          duplicateWarning: duplicateWarning)
                }
                if let saveError {
                    Section { Text(saveError).foregroundStyle(Color.owe) }
                }
            }
            .navigationTitle("Settle up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
            }
            .safeAreaInset(edge: .bottom) {
                if let selected {
                    SwipeToConfirm(title: swipeTitle(selected), onConfirm: record)
                        .id(selected)
                        .padding(.horizontal, Spacing.screenMargin)
                        .padding(.bottom, Spacing.xs)
                        .readableWidth()
                }
            }
        }
        // Settle up is a sheet, so an overlay here would stop below the sheet's top edge.
        // A full-screen cover reaches every edge (Sabit, 2026-11-12: "doesn't cover the full").
        .fullScreenCover(isPresented: showsSuccess) {
            if let recorded {
                SuccessOverlay(amount: recorded.amount, message: successMessage(recorded), onClose: cancel)
                    .presentationBackground(.clear)
            }
        }
        .onAppear(perform: preselect)
        .task(id: selected) { await loadPayeeHandles() }
    }

    private var myTransfers: [SuggestedTransfer] {
        guard let me = group.me else { return [] }
        return BalanceCalculator.transfers(balances, simplify: isSimplified).filter { $0.from == me.id || $0.to == me.id }
    }

    /// One "Open" button per wallet the person takes, in their order.
    private var walletApps: [PaymentHandle.Rail] {
        var seen: [PaymentHandle.Rail] = []
        for rail in payeeHandles.map(\.rail) where rail.walletAppURL != nil && !seen.contains(rail) { seen.append(rail) }
        return seen
    }

    private var isSimplified: Bool { simplifies ?? group.simplifiesDebts }

    private func setSimplified(_ on: Bool) {
        simplifies = on
        selected = nil
        preselect()
        Task { try? await app.setSimplifiesDebts(on, for: group) }
    }

    private func preselect() {
        if selected == nil, myTransfers.count == 1 { selected = myTransfers.first }
    }

    private func loadPayeeHandles() async {
        if let me = group.me, selected?.to == me.id {
            myHandles = (try? await app.profiles.paymentHandles(for: me.id)) ?? []
        }
        guard let selected, selected.from == group.me?.id else {
            payeeHandles = []
            return
        }
        payeeHandles = (try? await app.profiles.paymentHandles(for: selected.to)) ?? []
        // Start "Paid with" on how they like to be paid.
        if method == .cash, let first = payeeHandles.first { method = first.rail.settlementMethod }
    }

    /// Set when the typed transaction id was already used for a payment in this group.
    private var duplicateWarning: String? {
        guard method != .cash, Settlement.duplicate(ofReference: reference, in: settlements) != nil else { return nil }
        return String(localized: "This transaction ID is already recorded in this group. One payment can only settle one debt.", bundle: .appLanguage)
    }

    private func swipeTitle(_ t: SuggestedTransfer) -> String {
        let amount = MoneyFormatter.format(t.amount).plain
        return t.from == group.me?.id
            ? String(localized: "Swipe to record \(amount) paid", bundle: .appLanguage)
            : String(localized: "Swipe to mark \(amount) received", bundle: .appLanguage)
    }

    private func successMessage(_ t: SuggestedTransfer) -> String {
        t.from == group.me?.id
            ? String(localized: "Recorded as paid to \(group.storedName(of: t.to))", bundle: .appLanguage)
            : String(localized: "Marked received from \(group.storedName(of: t.from))", bundle: .appLanguage)
    }

    private func cancel() { dismiss() }

    private var showsSuccess: Binding<Bool> {
        Binding(get: { recorded != nil }, set: { if !$0 { recorded = nil } })
    }

    private func record() async -> Bool {
        guard let t = selected, let me = group.me else { return false }
        if duplicateWarning != nil {
            saveError = duplicateWarning
            return false
        }
        do {
                var settlement = try Settlement(
                    groupID: group.id, from: t.from, to: t.to, amount: t.amount, method: method,
                    userReference: reference.isEmpty ? nil : reference)
                if t.to == me.id {
                    try settlement.acknowledge(by: me.id)
                } else {
                    try settlement.transition(to: .reportedUnverified)
                }
                try await app.record(settlement, in: group)
                saveError = nil
                // The cover appears at once; SuccessOverlay animates its own entrance.
                var appear = Transaction()
                appear.disablesAnimations = true
                withTransaction(appear) { recorded = t }
                return true
        } catch {
            saveError = String(localized: "The payment wasn't recorded. Try again.", bundle: .appLanguage)
            return false
        }
    }
}

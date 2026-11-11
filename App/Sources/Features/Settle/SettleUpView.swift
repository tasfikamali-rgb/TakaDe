import SwiftUI
import TakaDeCore

/// Records a payment made outside the app. TakaDe never moves money. If you paid, it's
/// saved as reported by you. If you were paid, you mark it received.
struct SettleUpView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let group: ExpenseGroup
    let balances: GroupBalances

    @State private var selected: SuggestedTransfer?
    @State private var method: SettlementMethod = .cash
    @State private var reference = ""
    @State private var saveError: String?
    @State private var recorded: SuggestedTransfer?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("TakaDe doesn't send money. Pay with cash, bKash or your bank as usual, then record it here.")
                        .font(AppFont.body)
                        .foregroundStyle(Color.inkMuted)
                }
                TransferPickerSection(group: group, transfers: myTransfers, selected: $selected)
                if let selected {
                    PaymentDetailsSection(isMePaying: selected.from == group.me?.id, method: $method, reference: $reference)
                }
                if let saveError {
                    Section { Text(saveError).foregroundStyle(Color.owe) }
                }
            }
            .readableWidth()
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
        .overlay {
            if let recorded {
                SuccessOverlay(amount: recorded.amount, message: successMessage(recorded), onClose: cancel)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.2, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .onAppear(perform: preselect)
    }

    private var myTransfers: [SuggestedTransfer] {
        guard let me = group.me else { return [] }
        return BalanceCalculator.suggestedTransfers(balances).filter { $0.from == me.id || $0.to == me.id }
    }

    private func preselect() {
        if selected == nil, myTransfers.count == 1 { selected = myTransfers.first }
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

    private func record() async -> Bool {
        guard let t = selected, let me = group.me else { return false }
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
                withAnimation(Motion.standard(reduceMotion: reduceMotion)) { recorded = t }
                return true
        } catch {
            saveError = String(localized: "The payment wasn't recorded. Try again.", bundle: .appLanguage)
            return false
        }
    }
}

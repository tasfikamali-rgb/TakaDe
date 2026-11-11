import SwiftUI
import TakaDeCore

/// Records that a debt was paid outside the app. TakaDe does not move money, and
/// a recorded payment stays "reported, not verified" until a provider integration exists.
struct SettleUpView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let group: ExpenseGroup
    let balances: GroupBalances

    @State private var selected: SuggestedTransfer?
    @State private var method: SettlementMethod = .cash
    @State private var reference = ""
    @State private var saveError: String?

    private var myTransfers: [SuggestedTransfer] {
        guard let me = group.me else { return [] }
        return BalanceCalculator.suggestedTransfers(balances).filter { $0.from == me.id || $0.to == me.id }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("TakaDe doesn't send money. Pay with cash, bKash or your bank as usual, then record it here so the balance updates.")
                        .font(AppFont.body)
                        .foregroundStyle(Color.inkMuted)
                }

                Section("Suggested payments") {
                    if myTransfers.isEmpty {
                        Text("You're settled up in this group.")
                    }
                    ForEach(myTransfers, id: \.self) { t in
                        Button {
                            selected = t
                        } label: {
                            HStack {
                                Text(describe(t))
                                    .foregroundStyle(Color.ink)
                                Spacer()
                                AmountText(money: t.amount, font: AppFont.body.weight(.semibold))
                                if selected == t {
                                    Image(systemName: "checkmark").foregroundStyle(Color.ink)
                                        .accessibilityLabel("Selected")
                                }
                            }
                        }
                    }
                }

                if selected != nil {
                    Section {
                        Picker("Paid with", selection: $method) {
                            ForEach(SettlementMethod.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        if method != .cash {
                            TextField("Transaction ID (optional)", text: $reference)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                        }
                    } footer: {
                        Text("This is saved as reported by you. It isn't checked with bKash, upay or any bank.")
                    }
                }

                if let saveError {
                    Section { Text(saveError).foregroundStyle(Color.owe) }
                }
            }
            .navigationTitle("Settle up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                if let selected {
                    Button { record(selected) } label: {
                        Text(recordLabel(selected))
                            .font(AppFont.headline)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Capsule().fill(Color.ink))
                            .foregroundStyle(Color.canvas)
                    }
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.bottom, Spacing.xs)
                }
            }
        }
    }

    private func describe(_ t: SuggestedTransfer) -> String {
        if t.from == group.me?.id {
            return String(localized: "You pay \(group.name(of: t.to))")
        }
        return String(localized: "\(group.name(of: t.from)) pays you")
    }

    private func recordLabel(_ t: SuggestedTransfer) -> String {
        let amount = MoneyFormatter.format(t.amount).plain
        return String(localized: "Record \(amount) as paid")
    }

    private func record(_ t: SuggestedTransfer) {
        Task {
            do {
                var settlement = try Settlement(
                    groupID: group.id, from: t.from, to: t.to, amount: t.amount, method: method,
                    userReference: reference.isEmpty ? nil : reference)
                try settlement.transition(to: .reportedUnverified)
                try await model.repository.save(settlement, actor: group.me?.id)
                dismiss()
            } catch {
                saveError = String(localized: "The payment wasn't recorded. Try again.")
            }
        }
    }
}

extension SettlementMethod {
    var label: String {
        switch self {
        case .cash: String(localized: "Cash")
        case .bkash: "bKash"
        case .upay: "upay"
        case .bankTransfer: String(localized: "Bank transfer")
        case .other: String(localized: "Other")
        }
    }
}

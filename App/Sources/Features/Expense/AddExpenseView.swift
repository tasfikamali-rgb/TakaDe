import SwiftUI
import TakaDeCore

struct AddExpenseView: View {
    enum Method: String, CaseIterable, Identifiable {
        case equal, exact, percentage, shares
        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self {
            case .equal: "Equally"
            case .exact: "Exact amounts"
            case .percentage: "Percent"
            case .shares: "Shares"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let group: ExpenseGroup

    @State private var title = ""
    @State private var amountText = ""
    @State private var payer: MemberID
    @State private var method: Method = .equal
    @State private var included: Set<MemberID>
    @State private var exactText: [MemberID: String] = [:]
    @State private var percentText: [MemberID: String] = [:]
    @State private var shares: [MemberID: Int] = [:]
    @State private var saveError: String?

    init(group: ExpenseGroup) {
        self.group = group
        _payer = State(initialValue: group.me?.id ?? group.members[0].id)
        _included = State(initialValue: Set(group.members.map(\.id)))
    }

    private var total: Money? { try? Money.parse(amountText, currency: group.currency) }

    /// The rule as currently entered, or nil if it isn't complete yet.
    private var rule: SplitRule? {
        switch method {
        case .equal:
            let members = group.members.map(\.id).filter(included.contains)
            return members.isEmpty ? nil : .equal(members)
        case .exact:
            var amounts: [MemberID: Money] = [:]
            for m in group.members {
                let text = exactText[m.id, default: ""]
                if text.isEmpty { continue }
                guard let value = try? Money.parse(text, currency: group.currency) else { return nil }
                amounts[m.id] = value
            }
            return amounts.isEmpty ? nil : .exact(amounts)
        case .percentage:
            var bp: [MemberID: Int] = [:]
            for m in group.members {
                let text = percentText[m.id, default: ""]
                if text.isEmpty { continue }
                // Percent with up to two decimals, stored as basis points.
                guard let value = try? Money.parse(text, currency: Currency(code: "PCT", minorUnitDigits: 2)), value.minorUnits > 0 else { return nil }
                bp[m.id] = Int(value.minorUnits)
            }
            return bp.isEmpty ? nil : .percentage(bp)
        case .shares:
            let weights = shares.filter { $0.value > 0 }
            return weights.isEmpty ? nil : .shares(weights)
        }
    }

    private var preview: Result<Allocation, Error>? {
        guard let total, let rule else { return nil }
        return Result { try SplitCalculator.allocate(total, by: rule) }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && (try? preview?.get()) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What was it for?", text: $title)
                    TextField("Amount in taka", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(AppFont.title)
                        .monospacedDigit()
                }

                Section {
                    Picker("Paid by", selection: $payer) {
                        ForEach(group.members) { m in
                            Text(m.isMe ? String(localized: "You") : m.displayName).tag(m.id)
                        }
                    }
                }

                Section {
                    Picker("Split", selection: $method) {
                        ForEach(Method.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)

                    ForEach(group.members) { m in
                        row(for: m)
                    }
                } header: {
                    Text("Split")
                } footer: {
                    footer
                }

                if let saveError {
                    Section { Text(saveError).foregroundStyle(Color.owe) }
                }
            }
            .navigationTitle("Add expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for m: Member) -> some View {
        let name = m.isMe ? String(localized: "You") : m.displayName
        let share = try? preview?.get().shares[m.id]
        HStack {
            switch method {
            case .equal:
                Toggle(isOn: Binding(
                    get: { included.contains(m.id) },
                    set: { if $0 { included.insert(m.id) } else { included.remove(m.id) } }
                )) { Text(name) }
            case .exact:
                Text(name)
                Spacer()
                TextField("0", text: Binding(get: { exactText[m.id, default: ""] }, set: { exactText[m.id] = $0 }))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
            case .percentage:
                Text(name)
                Spacer()
                TextField("0", text: Binding(get: { percentText[m.id, default: ""] }, set: { percentText[m.id] = $0 }))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
                Text(verbatim: "%").foregroundStyle(Color.inkMuted)
            case .shares:
                Stepper(value: Binding(get: { shares[m.id, default: 1] }, set: { shares[m.id] = $0 }), in: 0...99) {
                    Text("\(name): \(shares[m.id, default: 1])")
                }
                .onAppear { if shares[m.id] == nil { shares[m.id] = 1 } }
            }
            if method != .exact, let share, !share.isZero {
                AmountText(money: share, font: AppFont.label, color: .inkMuted)
                    .frame(minWidth: 70, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch preview {
        case .some(.failure(let error as SplitError)):
            Text(Self.message(for: error)).foregroundStyle(Color.owe)
        case .some(.failure):
            Text("Check the amounts.").foregroundStyle(Color.owe)
        case .some(.success), .none:
            if method == .equal {
                Text("Leftover poisha go to the first people in the list, so the total always matches.")
            }
        }
    }

    static func message(for error: SplitError) -> String {
        switch error {
        case .exactAmountsDoNotMatchTotal(let expected, let actual):
            let diff = (try? expected.subtracting(actual)) ?? .zero()
            let f = MoneyFormatter.format(diff.magnitude).plain
            return diff.isNegative
                ? String(localized: "The amounts are \(f) more than the total.")
                : String(localized: "\(f) still needs to be assigned.")
        case .percentagesDoNotSumTo100:
            return String(localized: "Percentages need to add up to 100.")
        case .noParticipants:
            return String(localized: "Pick at least one person.")
        case .nonPositiveTotal:
            return String(localized: "Enter an amount above zero.")
        default:
            return String(localized: "Check the amounts.")
        }
    }

    private func save() {
        guard let total, let rule else { return }
        do {
            let expense = try Expense(
                groupID: group.id,
                title: title.trimmingCharacters(in: .whitespaces),
                total: total,
                paidBy: [payer: total],
                splitRule: rule)
            Task {
                do {
                    try await model.repository.save(expense, actor: group.me?.id)
                    dismiss()
                } catch {
                    saveError = String(localized: "The expense wasn't saved. Try again.")
                }
            }
        } catch {
            saveError = String(localized: "Check the amounts.")
        }
    }
}

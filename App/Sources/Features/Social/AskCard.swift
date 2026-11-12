import SwiftUI
import TakaDeCore

/// A payment request or proof request in a chat (docs/adr/0031-payment-asks-in-chat.md).
/// Its state comes from the group's own payments on this phone, so it changes from "Not paid
/// yet" to "Recorded as paid" to "Received" without any extra message. Paying still happens in
/// the wallet app; nothing here moves money or marks anything paid by itself.
struct AskCard: View {
    @Environment(AppModel.self) private var app
    @Environment(SocialModel.self) private var social
    let message: FriendMessage
    let ask: PaymentAsk
    let friend: Friend
    /// Sends a plain chat message back to the friend.
    let reply: (String) async -> Void

    @State private var settlements: [Settlement] = []
    @State private var balances: GroupBalances?
    @State private var settling = false
    @State private var addingProof = false

    private var isMine: Bool { message.direction == .outgoing }
    private var group: ExpenseGroup? {
        guard let group = app.group(ask.groupID), group.member(ask.from) != nil, group.member(ask.to) != nil else { return nil }
        return group
    }
    private var iAmPayer: Bool { group?.me?.id == ask.from }
    private var progress: PaymentAsk.Progress { ask.progress(sentAt: message.at, in: settlements) }

    /// True when this chat is the one this phone links to the person who asked, by their name
    /// in the group. Only then are the numbers they sent offered on the settle-up screen as
    /// that person's numbers.
    private var chatMatchesAsker: Bool {
        guard let group else { return false }
        return social.chat(forMemberNamed: group.storedName(of: ask.to))?.id == friend.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label { heading } icon: { Image(systemName: ask.kind == .pay ? "banknote" : "doc.text.magnifyingglass") }
                .font(AppFont.label)
                .foregroundStyle(Color.inkMuted)
            VStack(alignment: .leading, spacing: 2) {
                AmountText(money: ask.amount, size: .title)
                    .foregroundStyle(Color.ink)
                Text(verbatim: group?.name ?? ask.groupName)
                    .font(AppFont.label)
                    .foregroundStyle(Color.inkMuted)
            }
            statusLine
            actions
        }
        .padding(Spacing.m)
        .frame(maxWidth: 320, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.surface))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.ink.opacity(0.08), lineWidth: 1))
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        .accessibilityElement(children: .contain)
        .task(id: app.revision) { await load() }
        .sheet(isPresented: $settling) {
            if let group, let balances {
                SettleUpView(group: group, balances: balances, settlements: settlements, askedBy: ask.to,
                             sharedHandles: chatMatchesAsker ? ask.handles : [])
                    .rebuildsOnDynamicType()
            }
        }
        .sheet(isPresented: $addingProof) {
            ProofSheet(ask: ask, group: group, settlements: settlements, reply: reply)
                .rebuildsOnDynamicType()
        }
    }

    private var heading: Text {
        switch (ask.kind, isMine) {
        case (.pay, true): Text("You asked for payment")
        case (.pay, false): Text("\(friend.displayName) asks you to pay")
        case (.proof, true): Text("You asked for proof")
        case (.proof, false): Text("\(friend.displayName) asks for proof of payment")
        }
    }

    private var waitingText: LocalizedStringKey {
        switch (ask.kind, isMine) {
        case (.pay, true): "Waiting for payment"
        case (.pay, false): "Not paid yet"
        case (.proof, true): "Waiting for proof"
        case (.proof, false): "No transaction ID yet"
        }
    }

    /// The numbers they sent, checked and formatted like saved ones.
    private var sentHandles: [PaymentHandle] {
        ask.handles.compactMap { try? PaymentHandle(memberID: ask.to, rail: $0.rail, handle: $0.handle) }
    }

    @ViewBuilder private var statusLine: some View {
        if group == nil {
            Label("This group isn't on this phone", systemImage: "questionmark.folder")
                .font(AppFont.caption)
                .foregroundStyle(Color.inkMuted)
        } else {
            switch progress {
            case .waiting:
                Label(waitingText, systemImage: "clock")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.inkMuted)
            case .reportedPaid:
                Label("Recorded as paid, not confirmed yet", systemImage: "hourglass")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.ink)
            case .received:
                Label("Received", systemImage: "checkmark.circle")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.ink)
            case .reference(let reference):
                Label {
                    Text("Transaction ID \(reference)").textSelection(.enabled)
                } icon: {
                    Image(systemName: "number")
                }
                .font(AppFont.caption)
                .foregroundStyle(Color.ink)
            case .withdrawn:
                Label("This payment was withdrawn", systemImage: "arrow.uturn.backward")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.inkMuted)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        if !isMine {
            switch ask.kind {
            case .pay:
                if !sentHandles.isEmpty, progress == .waiting {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Numbers \(friend.displayName) sent")
                            .font(AppFont.caption)
                            .foregroundStyle(Color.inkMuted)
                        ForEach(sentHandles, id: \.handle) { PaymentHandleRow(handle: $0) }
                    }
                }
                if iAmPayer, progress == .waiting {
                    Button("Settle up", systemImage: "arrow.right.circle") { Task { await openSettleUp() } }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.lime)
                        .foregroundStyle(Color.onLime)
                        .accessibilityHint(Text("Opens settle up in the group, with this payment picked"))
                }
            case .proof:
                if iAmPayer, progress == .waiting {
                    Button("Send transaction ID", systemImage: "number") { addingProof = true }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.lime)
                        .foregroundStyle(Color.onLime)
                        .accessibilityHint(Text("Adds the ID to your payment in the group and sends it in this chat"))
                }
            }
        }
    }

    private func load() async {
        guard let group else { return }
        settlements = (try? await app.repository.settlements(in: group.id)) ?? []
    }

    private func openSettleUp() async {
        guard let group else { return }
        balances = try? await app.balances(for: group)
        settling = balances != nil
    }
}

/// The payer adds the transaction ID asked for. It's saved on their payment in the group (so it
/// syncs to everyone in it) and sent back in the chat. It's still their word, not a bKash check.
private struct ProofSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let ask: PaymentAsk
    let group: ExpenseGroup?
    let settlements: [Settlement]
    let reply: (String) async -> Void

    @State private var reference = ""
    @State private var error: String?
    @State private var saving = false
    @FocusState private var focused: Bool

    private var cleaned: String { reference.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var payment: Settlement? {
        guard let group, let me = group.me else { return nil }
        return settlements.first { $0.id == ask.settlementID && $0.from == me.id }
    }

    var body: some View {
        NavigationStack {
            AppForm {
                Section {
                    TextField("Transaction ID", text: $reference)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.send)
                        .onSubmit(save)
                } footer: {
                    Text("Find it in your bKash, Nagad or bank app's history. It's saved on your payment and sent in this chat. TakaDe can't check it with the wallet.")
                }
                if let error {
                    Section { Text(verbatim: error).foregroundStyle(Color.owe) }
                }
            }
            .navigationTitle("Send transaction ID")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send", action: save).disabled(cleaned.isEmpty || cleaned.count > 60 || saving)
                }
            }
            .onAppear { focused = true }
        }
    }

    private func save() {
        guard !cleaned.isEmpty, cleaned.count <= 60, !saving else { return }
        saving = true
        Task {
            defer { saving = false }
            if let group, var payment = payment {
                let others = settlements.filter { $0.id != payment.id }
                if Settlement.duplicate(ofReference: cleaned, in: others) != nil {
                    error = String(localized: "This transaction ID is already recorded in this group. One payment can only settle one debt.", bundle: .appLanguage)
                    return
                }
                do {
                    try payment.edit(amount: payment.amount, method: payment.method, userReference: cleaned, by: group.me?.id)
                    try await app.record(payment, in: group)
                } catch {
                    self.error = String(localized: "The transaction ID wasn't saved. Try again.", bundle: .appLanguage)
                    return
                }
            }
            await reply(AskWords.proofReply(reference: cleaned, amount: ask.amount, group: group?.name ?? ask.groupName))
            dismiss()
        }
    }
}

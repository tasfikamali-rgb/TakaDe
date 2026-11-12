import SwiftUI
import TakaDeCore

/// Sends a payment request or a proof request into a TakaDe chat
/// (docs/adr/0031-payment-asks-in-chat.md). It goes to the friend whose chat name matches the
/// person's name in the group; when none or several match, the person picks the chat. The
/// message is sealed like any other chat message, and nothing is sent until the button is tapped.
struct AskInChatButton: View {
    @Environment(SocialModel.self) private var social
    @Environment(AccountModel.self) private var account
    let title: Text
    /// The other person's name in the group, exactly as stored.
    let personName: String
    let ask: PaymentAsk
    let words: String

    @State private var picking = false
    @State private var state: SendState = .idle

    private enum SendState: Equatable {
        case idle
        case sending
        case sent(String)
        case failed(String)
    }

    var body: some View {
        if social.isAvailable, !social.chats.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Button(action: start) {
                    Label { title } icon: { Image(systemName: "bubble.left.and.text.bubble.right") }
                }
                .disabled(state == .sending)
                switch state {
                case .sent(let name):
                    Label("Sent to \(name) in Social", systemImage: "checkmark")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.inkMuted)
                case .failed(let message):
                    Text(verbatim: message)
                        .font(AppFont.caption)
                        .foregroundStyle(Color.owe)
                default:
                    EmptyView()
                }
            }
            .sheet(isPresented: $picking) {
                ChatPickerSheet(personName: personName) { friend in send(to: friend) }
                    .rebuildsOnDynamicType()
            }
        }
    }

    private func start() {
        if let friend = social.chat(forMemberNamed: personName) {
            send(to: friend)
        } else {
            picking = true
        }
    }

    private func send(to friend: Friend) {
        state = .sending
        Task {
            let sent = await social.send(words, to: friend, myName: account.profile?.displayName ?? "", ask: ask)
            state = sent ? .sent(friend.displayName)
                : .failed(social.sendProblem ?? String(localized: "It wasn't sent. Try again.", bundle: .appLanguage))
        }
    }
}

/// "Which chat is Rafi?": shown when no chat, or more than one, has the person's name.
private struct ChatPickerSheet: View {
    @Environment(SocialModel.self) private var social
    @Environment(\.dismiss) private var dismiss
    let personName: String
    let onPick: (Friend) -> Void

    var body: some View {
        NavigationStack {
            List(social.chats) { friend in
                Button {
                    dismiss()
                    onPick(friend)
                } label: {
                    HStack(spacing: Spacing.s) {
                        Avatar(name: friend.name, size: 36, photo: social.photo(for: friend.id))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: friend.displayName)
                                .font(AppFont.bodyEmphasis)
                                .foregroundStyle(Color.ink)
                            Text(verbatim: friend.code.description)
                                .font(AppFont.caption)
                                .monospaced()
                                .foregroundStyle(Color.inkMuted)
                        }
                    }
                }
                .accessibilityLabel(Text(verbatim: friend.displayName))
            }
            .scrollContentBackground(.hidden)
            .texturedBackground()
            .safeAreaInset(edge: .top, spacing: 0) {
                Text("Pick the chat that belongs to \(personName). Only they will see the message.")
                    .font(AppFont.label)
                    .foregroundStyle(Color.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.vertical, Spacing.xs)
            }
            .navigationTitle("Send in Social")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

/// The words that travel with each ask. Shown in the chat list and by older versions of
/// TakaDe, which don't know about payment cards.
enum AskWords {
    static func pay(to name: String, amount: Money, group: String, handles: [PaymentHandle]) -> String {
        let total = MoneyFormatter.format(amount).plain
        var lines = [String(localized: "Hi \(name), please pay me \(total) for \(group).", bundle: .appLanguage,
                            comment: "Payment request in chat: debtor name, amount, group name")]
        for handle in handles {
            lines.append("\(handle.rail.label): \(handle.displayHandle)")
        }
        return lines.joined(separator: "\n")
    }

    static func proof(to name: String, amount: Money, group: String) -> String {
        let total = MoneyFormatter.format(amount).plain
        return String(localized: "Hi \(name), I haven't seen the \(total) you recorded paying me in \(group) yet. Could you send the transaction ID?",
                      bundle: .appLanguage, comment: "Proof request in chat: payer name, amount, group name")
    }

    static func proofReply(reference: String, amount: Money, group: String) -> String {
        let total = MoneyFormatter.format(amount).plain
        return String(localized: "Transaction ID for the \(total) in \(group): \(reference)", bundle: .appLanguage,
                      comment: "Reply to a proof request: amount, group name, transaction ID")
    }
}

extension PaymentAsk {
    /// A request for the transfer `from` → `to` in the group, carrying the asker's numbers.
    static func pay(in group: ExpenseGroup, from: MemberID, to: MemberID, amount: Money, handles: [PaymentHandle]) -> PaymentAsk {
        PaymentAsk(kind: .pay, groupID: group.id, groupName: group.name, from: from, to: to, amount: amount,
                   handles: handles.map { Handle(rail: $0.rail, handle: $0.handle) })
    }

    static func proof(of settlement: Settlement, in group: ExpenseGroup) -> PaymentAsk {
        PaymentAsk(kind: .proof, groupID: group.id, groupName: group.name, from: settlement.from, to: settlement.to,
                   amount: settlement.amount, settlementID: settlement.id)
    }
}

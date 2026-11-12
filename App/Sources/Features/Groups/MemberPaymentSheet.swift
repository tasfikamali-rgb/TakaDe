import SwiftUI
import TakaDeCore

/// One person's bKash, Nagad, Rocket, upay or bank details, so others in the group can
/// copy them when settling. Only the number: never a PIN, password or OTP. Saved on this
/// phone only.
struct MemberPaymentSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let group: ExpenseGroup
    let member: Member
    /// Asks to take the person out of the group. Not offered for yourself.
    var onRemove: (() -> Void)?

    @State private var handles: [PaymentHandle] = []
    @State private var rail: PaymentHandle.Rail = .bkash
    @State private var number = ""
    @State private var errorMessage: String?
    @State private var nickname = ""
    @State private var savedNickname = ""
    @State private var confirmingRemove = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nickname", text: $nickname, prompt: Text("Nickname (optional)").foregroundStyle(Color.inkMuted))
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(saveNickname)
                } header: {
                    Text("Nickname in this group")
                        .foregroundStyle(Color.inkMuted)
                } footer: {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        if !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            NameRuleText(nickname)
                        }
                        Group {
                            if member.isMe {
                                Text("What this group calls you. Your name stays \(member.displayName).")
                            } else {
                                Text("What this group calls them. Their name stays \(member.displayName).")
                            }
                        }
                        .foregroundStyle(Color.inkMuted)
                    }
                }

                Section {
                    if handles.isEmpty {
                        Text("No numbers saved yet")
                            .foregroundStyle(Color.inkMuted)
                    }
                    ForEach(handles) { handle in
                        PaymentHandleRow(handle: handle)
                    }
                    .onDelete(perform: delete)
                } header: {
                    Text("How to pay \(name)")
                }

                Section {
                    Picker("Type", selection: $rail) {
                        ForEach(PaymentHandle.Rail.allCases, id: \.self) { option in
                            Text(verbatim: option.label).tag(option)
                        }
                    }
                    TextField(rail.isWallet ? "Mobile number, like 01712-345678" : "Bank, branch and account number", text: $number, axis: .vertical)
                        .keyboardType(rail.isWallet ? .phonePad : .default)
                        .textContentType(rail.isWallet ? .telephoneNumber : nil)
                        .returnMovesOn($number, perform: add)
                    Button("Save number", systemImage: "plus", action: add)
                        .disabled(number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let errorMessage {
                        Text(verbatim: errorMessage).foregroundStyle(Color.owe)
                    }
                } header: {
                    Text("Add a number")
                } footer: {
                    Text("Only the number people send money to. TakaDe never asks for a PIN, password or OTP. Saved on this phone only.")
                }

                if !member.isMe, let onRemove {
                    Section {
                        Button("Remove from group", systemImage: "person.badge.minus", role: .destructive) { confirmingRemove = true }
                            .foregroundStyle(Color.owe)
                            .confirmationDialog(Text("Remove \(name) from this group?"), isPresented: $confirmingRemove, titleVisibility: .visible) {
                                Button("Remove", role: .destructive) {
                                    dismiss()
                                    onRemove()
                                }
                            }
                    } footer: {
                        Text("Only people who aren't in any expense or payment can be removed.")
                    }
                }
            }
            .readableWidth()
            .navigationTitle(Text(verbatim: name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) }
            }
            .task {
                savedNickname = currentMember.nickname ?? ""
                nickname = savedNickname
                await load()
            }
        }
    }

    private var name: String { group.displayName(of: member.id) }
    private var currentMember: Member { app.group(group.id)?.member(member.id) ?? member }

    private func close() {
        saveNickname()
        dismiss()
    }

    /// Saves a changed nickname. Empty clears it; one that breaks the name rule isn't saved.
    private func saveNickname() {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != savedNickname, trimmed.isEmpty || PersonName.isValid(trimmed) else { return }
        savedNickname = trimmed
        Task { try? await app.setNickname(trimmed, for: member.id, in: group) }
    }

    private func load() async {
        handles = (try? await app.profiles.paymentHandles(for: member.id)) ?? []
    }

    private func add() {
        let text = number
        Task {
            do {
                let handle = try PaymentHandle(memberID: member.id, rail: rail, handle: text)
                try await app.profiles.save(handle)
                number = ""
                errorMessage = nil
                await load()
            } catch PaymentHandleError.invalidWalletNumber {
                errorMessage = String(localized: "That isn't an 11-digit Bangladeshi mobile number", bundle: .appLanguage)
            } catch PaymentHandleError.invalidBankDetails {
                errorMessage = String(localized: "Type the bank details, up to 80 characters", bundle: .appLanguage)
            } catch {
                errorMessage = String(localized: "The number wasn't saved. Try again.", bundle: .appLanguage)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let removed = offsets.map { handles[$0] }
        handles.remove(atOffsets: offsets)
        Task {
            for handle in removed { try? await app.profiles.deletePaymentHandle(handle.id) }
            await load()
        }
    }
}

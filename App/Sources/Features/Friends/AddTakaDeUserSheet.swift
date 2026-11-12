import SwiftUI
import TakaDeCore

/// "Add a TakaDe user": a friend's ID, typed or scanned from their QR code, adds them to
/// the group and sends them an invite they see the next time they open TakaDe.
struct AddTakaDeUserSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(GroupSync.self) private var sync
    @Environment(Friends.self) private var friends
    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    let group: ExpenseGroup

    @State private var idText = ""
    @State private var name = ""
    @State private var scanning = false
    @State private var working = false
    @State private var error: String?
    @State private var sentTo: String?
    /// Kept after the first try, so trying again doesn't add the person twice.
    @State private var added: Member?

    var body: some View {
        NavigationStack {
            AppForm {
                if let sentTo {
                    Section {
                        Label {
                            Text("Invite sent to \(sentTo)")
                        } icon: {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.owed)
                        }
                    } footer: {
                        Text("They'll see it the next time they open TakaDe, and join as \(sentTo) in this group.")
                    }
                } else if !friends.isAvailable {
                    Section {
                        Text("Sign in to your TakaDe account in the Account tab to add people by TakaDe ID.")
                    }
                } else {
                    form
                }
            }
            .readableWidth()
            .navigationTitle(Text("Add a TakaDe user"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if sentTo == nil { Button("Cancel") { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if sentTo != nil { Button("Done") { dismiss() } }
                }
            }
            .sheet(isPresented: $scanning) {
                QRScannerSheet { text in
                    if let code = FriendCode(scanned: text) {
                        idText = code.description
                        error = nil
                    } else {
                        error = String(localized: "That QR code isn't a TakaDe ID.", bundle: .appLanguage)
                    }
                }
            }
        }
    }

    @ViewBuilder private var form: some View {
        Section {
            TextField("TKD-XXXX-XXXX", text: $idText)
                .font(.body.monospaced())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .disabled(added != nil)
            if QRScanner.isAvailable, added == nil {
                Button("Scan their QR code", systemImage: "qrcode.viewfinder") { scanning = true }
            }
        } header: {
            Text("Their TakaDe ID")
        } footer: {
            Text("They can find it in their Account tab.")
        }
        Section {
            TextField("Name", text: $name)
                .textContentType(.name)
                .disabled(added != nil)
        } header: {
            Text("Their name in this group")
        } footer: {
            Text("TakaDe doesn't share names between accounts, so type how the group knows them.")
        }
        Section {
            Button(action: send) {
                HStack(spacing: Spacing.s) {
                    Text("Add and send invite")
                    if working { ProgressView() }
                }
            }
            .disabled(working || FriendCode(typed: idText) == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let error {
                Label {
                    Text(verbatim: error)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(Color.owe)
                .accessibilityElement(children: .combine)
            }
        } footer: {
            Text("Their invite is encrypted on this phone so only their phone can read it.")
        }
    }

    private func send() {
        guard let code = FriendCode(typed: idText) else {
            error = String(localized: "That's not a TakaDe ID. It looks like TKD-7F3K-9QXM.", bundle: .appLanguage)
            return
        }
        if code == friends.myCode {
            error = String(localized: "That's your own TakaDe ID.", bundle: .appLanguage)
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        working = true
        error = nil
        Task {
            defer { working = false }
            do {
                let key = try await friends.lookUp(code)
                let member: Member
                if let added {
                    member = added
                } else {
                    guard let new = try await app.addMember(named: trimmed, to: group) else { throw Friends.Failure.server }
                    member = new
                    added = new
                }
                let latest = app.group(group.id) ?? group
                let link = try await sync.inviteLink(for: latest)
                let payload = FriendInvitePayload(
                    link: link.absoluteString,
                    groupName: latest.name,
                    fromName: latest.me?.displayName ?? account.profile?.displayName ?? "",
                    memberID: member.id.rawValue)
                try await friends.send(payload, to: code, key: key)
                sentTo = member.displayName
                AccessibilityNotification.Announcement(String(localized: "Invite sent", bundle: .appLanguage)).post()
            } catch {
                self.error = Friends.Failure.message(for: error)
            }
        }
    }
}

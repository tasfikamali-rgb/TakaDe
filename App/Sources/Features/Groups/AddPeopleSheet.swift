import Contacts
import CryptoKit
import SwiftUI
import TakaDeCore

/// "Add a person" on a group's page: one search over your TakaDe friends and your contacts'
/// names (Sabit, 2026-11-12: no made-up people). Tapping someone adds them at once. A friend
/// also gets the group's invite, sealed to their key, so they can join on their phone.
struct AddPeopleSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(GroupSync.self) private var sync
    @Environment(Friends.self) private var friends
    @Environment(SocialModel.self) private var social
    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    let group: ExpenseGroup

    @State private var query = ""
    @State private var contactNames: [ContactSearchSheet.Entry] = []
    @State private var contactsStatus = CNContactStore.authorizationStatus(for: .contacts)
    /// Names added while the sheet is open, newest last.
    @State private var added: [String] = []
    @State private var working: String?
    @State private var error: String?
    @FocusState private var searching: Bool

    private struct Match: Identifiable {
        let id: String
        let name: String
        var photo: UIImage?
        var friend: Friend?
        var contactID: String?
    }

    var body: some View {
        NavigationStack {
            AppForm {
                Section {
                    HStack(spacing: Spacing.s) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Color.inkMuted).accessibilityHidden(true)
                        TextField("Search friends and contacts", text: $query,
                                  prompt: Text("Search friends and contacts").foregroundStyle(Color.inkMuted))
                            .focused($searching)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit { if matches.count == 1 { add(matches[0]) } }
                    }
                    ForEach(matches) { match in
                        Button { add(match) } label: {
                            HStack(spacing: Spacing.s) {
                                Avatar(name: match.name, size: 32, photo: match.photo)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: match.name).font(AppFont.body).foregroundStyle(Color.ink)
                                    Text(match.friend != nil ? LocalizedStringKey("TakaDe friend") : LocalizedStringKey("In your contacts"))
                                        .font(AppFont.caption).foregroundStyle(Color.inkMuted)
                                }
                                Spacer()
                                if working == match.id {
                                    ProgressView()
                                } else {
                                    Image(systemName: "plus.circle").font(.title3).foregroundStyle(Color.ink).accessibilityHidden(true)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(working != nil)
                        .accessibilityLabel(Text("Add \(match.name)"))
                    }
                    if !trimmedQuery.isEmpty && matches.isEmpty {
                        Text(contactsStatus == .notDetermined ? LocalizedStringKey("No friend matches that.") : LocalizedStringKey("No friend or contact matches that."))
                            .font(AppFont.label).foregroundStyle(Color.inkMuted)
                    }
                    if contactsStatus == .notDetermined {
                        Button("Search your contacts too", systemImage: "person.crop.circle") { Task { await allowContacts() } }
                    }
                } footer: {
                    Group {
                        if let error {
                            Text(verbatim: error).foregroundStyle(Color.owe)
                        } else if !friends.isAvailable {
                            Text("Sign in to your TakaDe account in the Account tab to add TakaDe friends, scan QR codes or invite by email.")
                        }
                    }
                    .foregroundStyle(Color.inkMuted)
                }
                if !added.isEmpty {
                    Section {
                        ForEach(added, id: \.self) { name in
                            Label {
                                Text(verbatim: name)
                            } icon: {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.owed)
                            }
                        }
                    } header: {
                        Text("Added").foregroundStyle(Color.inkMuted)
                    }
                }
            }
            .readableWidth()
            .navigationTitle(Text("Add a person"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task {
                await loadContactNames()
                searching = true
            }
        }
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var latest: ExpenseGroup { app.group(group.id) ?? group }

    private func isTaken(_ name: String) -> Bool {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return latest.members.contains { $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key }
    }

    /// Friends first, then contacts. People already in the group are left out.
    private var matches: [Match] {
        let text = trimmedQuery
        let friendMatches = social.chats
            .filter { PersonName.isValid($0.name.trimmingCharacters(in: .whitespacesAndNewlines)) && !isTaken($0.name) }
            .filter { text.isEmpty || $0.name.localizedStandardContains(text) }
            .prefix(text.isEmpty ? 8 : 20)
            .map { Match(id: "f-\($0.id)", name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                         photo: FriendPhotos.image(for: $0.id), friend: $0) }
        guard !text.isEmpty else { return Array(friendMatches) }
        let friendNames = Set(friendMatches.map { $0.name.lowercased() })
        let contactMatches = contactNames
            .filter { $0.name.localizedStandardContains(text) && !isTaken($0.name) && !friendNames.contains($0.name.lowercased()) }
            .prefix(20)
            .map { Match(id: "c-\($0.id)", name: $0.name, contactID: $0.id) }
        return Array(friendMatches) + contactMatches
    }

    private func add(_ match: Match) {
        guard working == nil else { return }
        working = match.id
        error = nil
        Task {
            defer { working = nil }
            if let friend = match.friend {
                await addFriend(friend, named: match.name)
            } else if let contactID = match.contactID {
                let details = await Task.detached(priority: .userInitiated) {
                    ContactSearchSheet.readDetails(of: [contactID], from: CNContactStore())
                }.value
                do {
                    try await app.addMembers([details[contactID] ?? PickedContact(name: match.name)], to: latest)
                    added.append(match.name)
                    query = ""
                } catch {
                    self.error = String(localized: "\(match.name) wasn't added. Try again.", bundle: .appLanguage)
                }
            }
        }
    }

    /// Adds the friend, then sends them the group's invite with who they are in it.
    private func addFriend(_ friend: Friend, named name: String) async {
        var photo: PickedContact?
        if let image = FriendPhotos.image(for: friend.id), let data = image.jpegData(compressionQuality: 0.8) {
            photo = PickedContact(name: name, photo: data)
        }
        let member: Member
        do {
            guard let new = try await app.addMembers([photo ?? PickedContact(name: name)], to: latest).first else { throw Friends.Failure.server }
            member = new
            added.append(name)
            query = ""
        } catch {
            self.error = String(localized: "\(name) wasn't added. Try again.", bundle: .appLanguage)
            return
        }
        do {
            let key: Curve25519.KeyAgreement.PublicKey
            if let raw = Data(base64URLEncoded: friend.publicKey), let known = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw) {
                key = known
            } else {
                key = try await friends.lookUp(friend.code)
            }
            let group = latest
            let link = try await sync.inviteLink(for: group)
            let payload = FriendInvitePayload(
                link: link.absoluteString,
                groupName: group.name,
                fromName: group.me?.displayName ?? account.profile?.displayName ?? "",
                memberID: member.id.rawValue)
            try await friends.send(payload, to: friend.code, key: key)
        } catch {
            self.error = String(localized: "\(name) is in the group, but their invite didn't go: \(Friends.Failure.message(for: error))", bundle: .appLanguage)
        }
    }

    private func allowContacts() async {
        let granted = (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
        contactsStatus = CNContactStore.authorizationStatus(for: .contacts)
        if granted { await loadContactNames() }
    }

    private func loadContactNames() async {
        guard contactNames.isEmpty, ContactAccess.canRead(contactsStatus) else { return }
        contactNames = await Task.detached(priority: .userInitiated) {
            ContactSearchSheet.readNames(from: CNContactStore())
        }.value
    }
}

enum ContactAccess {
    /// Full access, or iOS 18's limited access to some contacts.
    static func canRead(_ status: CNAuthorizationStatus) -> Bool {
        if status == .authorized { return true }
        if #available(iOS 18.0, *) { return status == .limited }
        return false
    }
}

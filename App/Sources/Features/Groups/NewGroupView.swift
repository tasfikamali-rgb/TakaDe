import Contacts
import CryptoKit
import SwiftUI
import TakaDeCore

/// Make a group. Everyone in it is a real person (Sabit, 2026-11-12): a TakaDe friend found by
/// search, someone from Contacts, a scanned TakaDe ID, or an email invite they join from
/// themselves. There is no free-text "add a name" here.
struct NewGroupView: View {
    @Environment(AppModel.self) private var model
    @Environment(GroupSync.self) private var sync
    @Environment(Friends.self) private var friends
    @Environment(SocialModel.self) private var social
    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let onCreated: (GroupID) -> Void

    @AppStorage(AccountModel.nameKey) private var myName = ""
    @State private var name = ""
    @State private var kind: GroupKind = .standard
    /// Everyone else, in the order added. Each shows as a row with a remove button.
    @State private var people: [DraftName] = []
    /// Email addresses to send the invite link to once the group is made. Kept only on this
    /// screen; the email goes from the person's own mail app.
    @State private var emails: [String] = []
    @State private var query = ""
    /// Names in Contacts, read on this phone once access is given, for the search box.
    @State private var contactNames: [ContactSearchSheet.Entry] = []
    @State private var contactsStatus = CNContactStore.authorizationStatus(for: .contacts)
    /// Why someone wasn't added, like "Rishan is already in it".
    @State private var note: String?
    @State private var error: String?
    @State private var pickingContacts = false
    @State private var scanning = false
    @State private var askingEmail = false
    @State private var emailText = ""
    /// A scanned TakaDe ID whose QR code didn't carry a name, waiting for one.
    @State private var scannedWithoutName: FriendCode?
    @State private var scannedName = ""
    @State private var working = false
    /// Set once the group is saved, so a failed invite step doesn't make it twice.
    @State private var made: ExpenseGroup?
    @State private var mail: MailDraft?
    /// An optional cover photo; its main colour becomes the group's colour.
    @State private var photoData: Data?
    @State private var photoPreview: UIImage?
    @FocusState private var focus: Field?

    private enum Field: Hashable { case group, search }

    private struct MailDraft: Identifiable {
        let id = UUID()
        let recipients: [String]
        let subject: String
        let body: String
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
            AppForm {
                coverSection
                kindSection
                nameSection
                if !people.isEmpty || !emails.isEmpty { peopleSection }
                addSection
                if let error {
                    Section { Text(verbatim: error).foregroundStyle(Color.owe) }
                }
            }
            .readableWidth()
            // The search box moves to the top while it's used, so its matches show above
            // the keyboard instead of under it.
            .onChange(of: focus) { _, field in
                if field == .search { scrollToSearch(scroller) }
            }
            // A "what's missing" note goes once it's been filled in.
            .onChange(of: missing) { _, now in
                if now == nil, made == nil { error = nil }
            }
            .onChange(of: query) { _, _ in
                if focus == .search { scrollToSearch(scroller) }
            }
            }
            .task { await loadContactNames() }
            .sheet(isPresented: $pickingContacts) { ContactSearchSheet(onPick: addContacts).rebuildsOnDynamicType() }
            .sheet(isPresented: $scanning) { QRScannerSheet(onScan: scanned) }
            .sheet(item: $mail) { draft in
                MailComposer(recipients: draft.recipients, subject: draft.subject, body: draft.body, onFinish: finish)
                    .ignoresSafeArea()
            }
            .alert("Invite by email", isPresented: $askingEmail) {
                TextField("Email address", text: $emailText)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Add", action: addEmail)
                Button("Cancel", role: .cancel) { emailText = "" }
            } message: {
                Text("When the group is made, your mail app opens with its invite link. They join with their own name.")
            }
            .alert("Their name in this group", isPresented: Binding(
                get: { scannedWithoutName != nil },
                set: { if !$0 { scannedWithoutName = nil } })) {
                TextField("Name", text: $scannedName).textContentType(.name)
                Button("Add") { addScanned(named: scannedName) }
                Button("Cancel", role: .cancel) { scannedName = "" }
            } message: {
                Text("Their QR code doesn't carry a name. Type how the group knows them.")
            }
            .navigationTitle("New group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if made == nil { Button("Cancel") { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if working {
                        ProgressView()
                    } else if made != nil {
                        Button("Done", action: finish)
                    } else {
                        // Always drawn enabled (a greyed-out Create fails contrast); a tap says what's missing.
                        Button("Create", action: create)
                    }
                }
            }
        }
    }

    // MARK: Sections

    /// The cover with the group's icon on it. The icon sits inside the cover's corner, on its
    /// own surface with a hairline edge, so it looks the same on every background and screen
    /// size (the old ring cut into the form's textured background, which showed on iPad).
    private var coverSection: some View {
        Section {
            GroupPhotoPicker(hasPhoto: photoPreview != nil, onPick: pickPhoto, onRemove: clearPhoto) {
                ZStack(alignment: .bottomLeading) {
                    Group {
                        if let photoPreview {
                            GroupCoverImage(photo: photoPreview, height: 132)
                        } else {
                            Color.lilac
                                .frame(maxWidth: .infinity)
                                .frame(height: 132)
                                .overlay(alignment: .topTrailing) {
                                    Label("Add cover photo", systemImage: "photo")
                                        .font(AppFont.label)
                                        .foregroundStyle(Color.ink)
                                        .padding(Spacing.s)
                                }
                        }
                    }
                    GroupIconBadge(name: name, size: 64, fill: .surface, ring: Color.ink.opacity(0.08))
                        .padding(Spacing.s)
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(photoPreview == nil ? Text("Add cover photo") : Text("Cover photo"))
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } footer: {
            Text("The icon comes from the group's name. The cover photo is optional; the group takes its colour from it.")
                .foregroundStyle(Color.inkMuted)
        }
    }

    /// Only two kinds, because only two work differently.
    private var kindSection: some View {
        Section {
            // Side by side, or stacked at the largest text sizes so the lines can wrap.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Spacing.s))
                : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.s))
            layout { kindCards }
                // Both cards as tall as the taller one.
                .fixedSize(horizontal: false, vertical: true)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } header: {
            Text("What's it for").foregroundStyle(Color.inkMuted)
        }
    }

    @ViewBuilder private var kindCards: some View {
        KindCard(title: "Hangout or trip", detail: "Split bills as they come: dinners, tours, rent.",
                 symbol: "figure.2", isOn: kind == .standard) { kind = .standard }
        KindCard(title: "Mess", detail: "Count meals each day. Bazar is shared by meals at month end.",
                 symbol: "fork.knife", isOn: kind == .mess) { kind = .mess }
    }

    private var nameSection: some View {
        Section {
            // Vertical so long names wrap at large text sizes; Return still moves on.
            TextField("Group name", text: $name, prompt: Text("Group name").foregroundStyle(Color.inkMuted), axis: .vertical)
                .focused($focus, equals: .group)
                .accessibilityIdentifier("newGroup.name")
                .submitLabel(.next)
                .returnMovesOn($name) { focus = .search }
                .disabled(made != nil)
        } footer: {
            Group {
                if kind == .mess {
                    Text("Like Mirpur mess or Hall room 212")
                } else {
                    Text("Like Cox's Bazar trip or Friday dinner")
                }
            }
            .foregroundStyle(Color.inkMuted)
        }
    }

    private var peopleSection: some View {
        Section {
            ForEach(people) { person in
                PersonRow(name: person.text, photo: person.preview, source: source(of: person)) {
                    if made == nil { remove(person) }
                }
            }
            ForEach(emails, id: \.self) { email in
                HStack(spacing: Spacing.s) {
                    Image(systemName: "envelope")
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.surfaceRaised))
                        .foregroundStyle(Color.ink)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: email).font(AppFont.body).foregroundStyle(Color.ink).lineLimit(1)
                        Text("Gets an invite by email").font(AppFont.caption).foregroundStyle(Color.inkMuted)
                    }
                    Spacer()
                    if made == nil {
                        RemoveButton(label: Text("Remove \(email)")) { emails.removeAll { $0 == email } }
                    }
                }
            }
        } header: {
            Text("Who's in it").foregroundStyle(Color.inkMuted)
        } footer: {
            if !trimmedMyName.isEmpty {
                Text("You're in it as \(trimmedMyName).").foregroundStyle(Color.inkMuted)
            }
        }
    }

    @ViewBuilder private var addSection: some View {
        Section {
            HStack(spacing: Spacing.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.inkMuted).accessibilityHidden(true)
                TextField("Search friends and contacts", text: $query,
                          prompt: Text("Search friends and contacts").foregroundStyle(Color.inkMuted))
                    .focused($focus, equals: .search)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .accessibilityIdentifier("newGroup.memberSearch")
                    .onSubmit { if results.count == 1 { add(results[0]) } }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color.inkMuted)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Clear search"))
                }
            }
            .disabled(made != nil)
            .id(Self.searchRow)
            ForEach(results) { result in
                Button { add(result) } label: {
                    HStack(spacing: Spacing.s) {
                        Avatar(name: result.name, size: 32, photo: result.photo)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: result.name).font(AppFont.body).foregroundStyle(Color.ink)
                            Text(result.friend != nil ? LocalizedStringKey("TakaDe friend") : LocalizedStringKey("In your contacts"))
                                .font(AppFont.caption).foregroundStyle(Color.inkMuted)
                        }
                        Spacer()
                        Image(systemName: "plus.circle").font(.title3).foregroundStyle(Color.ink).accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Add \(result.name)"))
            }
            if !trimmedQuery.isEmpty && results.isEmpty {
                Text(noMatchText).font(AppFont.label).foregroundStyle(Color.inkMuted)
            }
            if contactsStatus == .notDetermined && !trimmedQuery.isEmpty {
                Button("Search your contacts too", systemImage: "person.crop.circle") { Task { await allowContacts() } }
            }
        } header: {
            Text("Add people").foregroundStyle(Color.inkMuted)
        } footer: {
            Group {
                if let note { Text(verbatim: note) }
                if people.isEmpty && emails.isEmpty && !trimmedMyName.isEmpty {
                    Text("You're in it as \(trimmedMyName). Add at least one more person.")
                }
            }
            .foregroundStyle(Color.inkMuted)
        }
        if made == nil {
            Section {
                Button("Pick from contacts", systemImage: "person.crop.circle.badge.plus") { pickingContacts = true }
                if friends.isAvailable && QRScanner.isAvailable {
                    Button("Scan a TakaDe QR code", systemImage: "qrcode.viewfinder") { scanning = true }
                }
                if friends.isAvailable && sync.isAvailable {
                    Button("Invite by email", systemImage: "envelope") {
                        emailText = ""
                        askingEmail = true
                    }
                }
            } footer: {
                if !friends.isAvailable {
                    Text("Sign in to your TakaDe account in the Account tab to add TakaDe friends, scan QR codes or invite by email.")
                        .foregroundStyle(Color.inkMuted)
                }
            }
        }
    }

    // MARK: Search

    private static let searchRow = "newGroup.searchRow"

    private func scrollToSearch(_ scroller: ScrollViewProxy) {
        // After the keyboard has started to rise, so the list knows its new height.
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(Motion.standard) { scroller.scrollTo(Self.searchRow, anchor: .top) }
        }
    }

    private struct Match: Identifiable {
        let id: String
        let name: String
        var photo: UIImage?
        var friend: Friend?
        var contactID: String?
    }

    private var trimmedMyName: String { myName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// With an empty box: your TakaDe friends, as suggestions. While typing: friends, then
    /// contacts, whose names match. Anyone already in the group is left out.
    private var results: [Match] {
        guard made == nil else { return [] }
        let text = trimmedQuery
        let addedCodes = Set(people.compactMap(\.takaDe?.code))
        let friendResults = social.chats
            .filter { PersonName.isValid($0.name.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !addedCodes.contains($0.code) && !isTaken($0.name) }
            .filter { text.isEmpty || $0.name.localizedStandardContains(text) }
            .prefix(text.isEmpty ? 6 : 20)
            .map { Match(id: "f-\($0.id)", name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                          photo: FriendPhotos.image(for: $0.id), friend: $0) }
        guard !text.isEmpty else { return Array(friendResults) }
        let friendNames = Set(friendResults.map { $0.name.lowercased() })
        let contactResults = contactNames
            .filter { $0.name.localizedStandardContains(text) && !isTaken($0.name) && !friendNames.contains($0.name.lowercased()) }
            .prefix(20)
            .map { Match(id: "c-\($0.id)", name: $0.name, contactID: $0.id) }
        return Array(friendResults) + contactResults
    }

    private var noMatchText: String {
        contactsStatus == .notDetermined
            ? String(localized: "No friend matches that.", bundle: .appLanguage)
            : String(localized: "No friend or contact matches that.", bundle: .appLanguage)
    }

    private func source(of person: DraftName) -> LocalizedStringKey {
        if let takaDe = person.takaDe {
            return takaDe.isFriend ? "TakaDe friend" : "TakaDe ID"
        }
        return "From contacts"
    }

    // MARK: Adding

    /// Same name as you or someone already listed, ignoring case and extra spaces.
    private func isTaken(_ name: String) -> Bool {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmedMyName.lowercased() == key || people.contains { $0.text.lowercased() == key }
    }

    private func add(_ result: Match) {
        note = nil
        if let friend = result.friend {
            let photo = FriendPhotos.image(for: friend.id)
            people.append(DraftName(
                text: result.name,
                contact: photo.flatMap { $0.jpegData(compressionQuality: 0.8) }.map { PickedContact(name: result.name, photo: $0) },
                preview: photo,
                takaDe: .init(code: friend.code, publicKey: friend.publicKey, isFriend: true)))
            query = ""
        } else if let contactID = result.contactID {
            let name = result.name
            query = ""
            Task {
                let details = await Task.detached(priority: .userInitiated) {
                    ContactSearchSheet.readDetails(of: [contactID], from: CNContactStore())
                }.value
                addContacts([details[contactID] ?? PickedContact(name: name)])
            }
        }
    }

    /// Everyone picked shows up as a row right away, with their contact photo. Anyone
    /// already listed is skipped.
    private func addContacts(_ picked: [PickedContact]) {
        var skipped: [String] = []
        for contact in picked {
            let name = contact.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard PersonName.isValid(name) else { continue }
            if isTaken(name) {
                skipped.append(name)
            } else {
                people.append(DraftName(text: name, contact: contact, preview: contact.photo.flatMap(UIImage.init(data:))))
            }
        }
        note = skipped.isEmpty ? nil : String(localized: "\(skipped.formatted(.list(type: .and))) is already in it.", bundle: .appLanguage)
    }

    private func scanned(_ text: String) {
        guard let code = FriendCode(scanned: text) else {
            note = String(localized: "That QR code isn't a TakaDe ID.", bundle: .appLanguage)
            return
        }
        if code == friends.myCode {
            note = String(localized: "That's your own TakaDe ID.", bundle: .appLanguage)
            return
        }
        if people.contains(where: { $0.takaDe?.code == code }) {
            note = String(localized: "They're already in it.", bundle: .appLanguage)
            return
        }
        // Their QR code carries their own name; a friend you've named keeps your name for them.
        let friend = social.people.first { $0.code == code && $0.status == .friend }
        let known = friend.map(\.name).flatMap { PersonName.isValid($0) ? $0 : nil }
        if let shared = known ?? FriendCode.sharedName(inScanned: text) {
            addTakaDeUser(code, named: shared, friend: friend)
        } else {
            scannedName = ""
            // The camera sheet is still closing; the name alert waits for it.
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                scannedWithoutName = code
            }
        }
    }

    private func addScanned(named typed: String) {
        guard let code = scannedWithoutName else { return }
        scannedWithoutName = nil
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PersonName.isValid(name) else {
            note = String(localized: "Use letters only for their name.", bundle: .appLanguage)
            return
        }
        addTakaDeUser(code, named: name, friend: nil)
    }

    private func addTakaDeUser(_ code: FriendCode, named name: String, friend: Friend?) {
        guard !isTaken(name) else {
            note = String(localized: "\(name) is already in it.", bundle: .appLanguage)
            return
        }
        note = nil
        people.append(DraftName(text: name, preview: friend.flatMap { FriendPhotos.image(for: $0.id) },
                                takaDe: .init(code: code, publicKey: friend?.publicKey, isFriend: friend != nil)))
    }

    private func addEmail() {
        defer { emailText = "" }
        guard let email = EmailAddress.cleaned(emailText) else {
            note = String(localized: "That doesn't look like an email address.", bundle: .appLanguage)
            return
        }
        if emails.contains(email) {
            note = String(localized: "\(email) is already invited.", bundle: .appLanguage)
            return
        }
        note = nil
        emails.append(email)
    }

    private func remove(_ person: DraftName) {
        people.removeAll { $0.id == person.id }
    }

    private func allowContacts() async {
        let granted = (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
        contactsStatus = CNContactStore.authorizationStatus(for: .contacts)
        if granted { await loadContactNames() }
    }

    /// Only when Contacts access was already given: the search box never asks on its own.
    private func loadContactNames() async {
        guard contactNames.isEmpty, ContactAccess.canRead(contactsStatus) else { return }
        contactNames = await Task.detached(priority: .userInitiated) {
            ContactSearchSheet.readNames(from: CNContactStore())
        }.value
    }

    private func pickPhoto(_ data: Data) {
        photoData = data
        photoPreview = UIImage(data: data)
    }

    private func clearPhoto() {
        photoData = nil
        photoPreview = nil
    }

    // MARK: Create

    /// What still needs filling in before the group can be made, in words.
    private var missing: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(localized: "Give the group a name.", bundle: .appLanguage)
        }
        if people.isEmpty && emails.isEmpty {
            return String(localized: "Add at least one more person.", bundle: .appLanguage)
        }
        if trimmedMyName.isEmpty {
            return String(localized: "Add your name in the Account tab first.", bundle: .appLanguage)
        }
        return nil
    }

    /// Saves the group, then sends TakaDe users their sealed invites and opens Mail for email
    /// invites. If the invites can't go (offline, say), the group stays made and says so.
    private func create() {
        guard !working else { return }
        if let missing {
            error = missing
            AccessibilityNotification.Announcement(missing).post()
            return
        }
        working = true
        error = nil
        Task {
            defer { working = false }
            let group: ExpenseGroup
            do {
                if let made {
                    group = made
                } else {
                    group = try await model.createGroup(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        myName: trimmedMyName,
                        others: people.map(\.picked),
                        kind: kind,
                        photo: photoData)
                    made = group
                }
            } catch is AppModel.GroupLimitReached {
                self.error = GroupLimitText.message
                return
            } catch {
                self.error = String(localized: "The group wasn't saved. Try again.", bundle: .appLanguage)
                return
            }
            let takaDeUsers = people.enumerated().filter { $0.element.takaDe != nil }
            guard !takaDeUsers.isEmpty || !emails.isEmpty else { return finish() }
            do {
                let link = try await sync.inviteLink(for: group)
                let fromName = group.me?.displayName ?? account.profile?.displayName ?? trimmedMyName
                for (index, person) in takaDeUsers {
                    guard let user = person.takaDe else { continue }
                    // Members are saved in the order they were listed, after you.
                    let memberIndex = index + 1
                    guard group.members.indices.contains(memberIndex) else { continue }
                    let member = group.members[memberIndex]
                    let key = try await key(for: user)
                    let payload = FriendInvitePayload(link: link.absoluteString, groupName: group.name,
                                                      fromName: fromName, memberID: member.id.rawValue)
                    try await friends.send(payload, to: user.code, key: key)
                    // Someone added by a scanned ID also shows up in the Social tab.
                    if !user.isFriend { _ = try? await social.add(code: user.code, name: member.displayName, key: key) }
                }
                if !emails.isEmpty {
                    sendEmails(link: link, groupName: group.name)
                } else {
                    finish()
                }
            } catch {
                self.error = String(localized: "\(group.name) is made, but the invites didn't go: \(Friends.Failure.message(for: error)) Tap Done, then invite them from the group.", bundle: .appLanguage)
            }
        }
    }

    private func key(for user: DraftName.TakaDeUser) async throws -> Curve25519.KeyAgreement.PublicKey {
        if let text = user.publicKey, let raw = Data(base64URLEncoded: text),
           let key = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw) {
            return key
        }
        return try await friends.lookUp(user.code)
    }

    private func sendEmails(link: URL, groupName: String) {
        let subject = String(localized: "Join \(groupName) on TakaDe", bundle: .appLanguage)
        let body = InviteSheet.message(groupName: groupName, url: link)
        if MailComposer.canSend {
            mail = MailDraft(recipients: emails, subject: subject, body: body)
        } else if let url = MailComposer.mailtoURL(recipients: emails, subject: subject, body: body) {
            openURL(url) { opened in
                if opened {
                    finish()
                } else {
                    UIPasteboard.general.string = body
                    error = String(localized: "No mail app is set up, so the invite was copied. Paste it into an email or message to them.", bundle: .appLanguage)
                }
            }
        }
    }

    private func finish() {
        guard let made else { return dismiss() }
        dismiss()
        onCreated(made.id)
    }
}

/// A choice of group kind, as a card with a line on what it does differently.
private struct KindCard: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Image(systemName: symbol).font(.title3).accessibilityHidden(true)
                    Spacer()
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isOn ? Color.ink : Color.inkMuted)
                        .accessibilityHidden(true)
                }
                Text(title).font(AppFont.bodyEmphasis).foregroundStyle(Color.ink)
                Text(detail).font(AppFont.caption).foregroundStyle(Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.ink)
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Radius.key, style: .continuous).fill(Color.surface))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
                    .strokeBorder(isOn ? Color.ink : Color.ink.opacity(0.1), lineWidth: isOn ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Radius.key, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// Someone added to the new group, with where they came from and a remove button.
private struct PersonRow: View {
    let name: String
    let photo: UIImage?
    let source: LocalizedStringKey
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            Avatar(name: name, size: 32, photo: photo)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name).font(AppFont.body).foregroundStyle(Color.ink)
                Text(source).font(AppFont.caption).foregroundStyle(Color.inkMuted)
            }
            Spacer()
            RemoveButton(label: Text("Remove \(name)"), action: onRemove)
        }
    }
}

private struct RemoveButton: View {
    let label: Text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.inkMuted)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }
}

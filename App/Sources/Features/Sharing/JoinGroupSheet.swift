import SwiftUI
import TakaDeCore

/// Joins a shared group from a tapped link, or from a pasted one ("Join with a link"),
/// then asks which person in the group uses this phone.
struct JoinGroupSheet: View {
    @Environment(GroupSync.self) private var sync
    @Environment(AppModel.self) private var app
    @Environment(Friends.self) private var friends
    @Environment(\.dismiss) private var dismiss
    let invite: GroupInvite?
    /// Set when a friend sent the invite to this account by TakaDe ID.
    var from: Friends.Received? = nil
    let onJoined: (GroupID) -> Void

    private enum Stage: Equatable {
        case paste
        case confirm
        case joining
        case choose(GroupID)
        case failed(String)
    }

    @State private var stage: Stage = .paste
    @State private var pasted = ""
    /// Why the text in the field can't be used, until the text changes.
    @State private var linkError: (text: String, message: String)?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Form {
                switch stage {
                case .paste: pasteSection
                case .confirm: confirmSection
                case .joining:
                    Section {
                        HStack(spacing: Spacing.s) {
                            ProgressView()
                            Text("Joining the group…")
                        }
                    }
                case .choose(let id): chooseSections(id)
                case .failed(let reason):
                    Section {
                        Text(verbatim: reason).foregroundStyle(Color.owe)
                        if let invite {
                            Button("Try again") { start(invite) }
                        } else {
                            Button("Try again") { stage = .paste }
                        }
                    }
                }
            }
            .readableWidth()
            .navigationTitle(Text("Join a group"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if case .choose = stage {
                        EmptyView()
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .interactiveDismissDisabled(isChoosing)
            .task {
                guard let invite, stage == .paste else { return }
                // An invite from a person waits for a yes; a tapped link is the person's own yes.
                if from != nil { stage = .confirm } else { start(invite) }
            }
        }
    }

    private var isChoosing: Bool {
        if case .choose = stage { return true }
        return false
    }

    // MARK: From a friend

    @ViewBuilder private var confirmSection: some View {
        if let from, let invite {
            Section {
                Button("Join", action: { start(invite) })
                Button("Decline", role: .destructive) {
                    Task { await friends.remove(from.id) }
                    dismiss()
                }
            } header: {
                Text("\(from.payload.fromName) invited you to \(from.payload.groupName)")
            } footer: {
                Text("You'll see this group's expenses and payments and can add your own.")
            }
        }
    }

    // MARK: Paste

    @ViewBuilder private var pasteSection: some View {
        Section {
            TextField("Paste the link or the whole message", text: $pasted, axis: .vertical)
                .lineLimit(3...6)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if let linkError, linkError.text == pasted {
                Label {
                    Text(verbatim: linkError.message)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(Color.owe)
                .accessibilityElement(children: .combine)
            }
            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                pasted = text
                // A link from the Paste button joins straight away; anything else says why not.
                joinPasted()
            }
            Button("Join", action: joinPasted)
                .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } footer: {
            Text("Only invite links from TakaDe work here. Ask someone in the group to tap the invite button in the group and send you the link.")
        }
    }

    /// Joins only with a real TakaDe invite link. Anything else stays on this screen with a reason.
    private func joinPasted() {
        if let found = GroupInvite(text: pasted) {
            linkError = nil
            start(found)
        } else {
            let message = Self.reason(notJoining: pasted)
            linkError = (pasted, message)
            AccessibilityNotification.Announcement(message).post()
        }
    }

    /// A TakaDe link with a part missing (often cut off when copied) gets its own message.
    static func reason(notJoining text: String) -> String {
        let lowered = text.lowercased()
        if lowered.contains("takade://join") || lowered.contains("takadeapp.com/join") {
            return String(localized: "This invite link is incomplete. Copy the whole message again and paste it here.", bundle: .appLanguage)
        }
        return String(localized: "That's not a TakaDe invite link. Only links sent from a group's invite button work here.", bundle: .appLanguage)
    }

    private func start(_ invite: GroupInvite) {
        stage = .joining
        Task {
            do {
                let id = try await sync.join(invite)
                if let from {
                    await friends.remove(from.id)
                    // The friend already added this person to the group.
                    if let memberID = from.payload.memberID.map({ MemberID($0) }), app.group(id)?.members.contains(where: { $0.id == memberID }) == true,
                       app.group(id)?.me == nil {
                        try await sync.choose(memberID, in: id)
                    }
                }
                if app.group(id)?.me != nil {
                    finish(id)
                } else {
                    stage = .choose(id)
                }
            } catch {
                stage = .failed(SharingError.message(for: error))
            }
        }
    }

    // MARK: Which one are you

    @ViewBuilder private func chooseSections(_ id: GroupID) -> some View {
        if let group = app.group(id) {
            Section {
                ForEach(group.members) { member in
                    Button {
                        choose(member.id, in: id)
                    } label: {
                        Text(verbatim: member.displayName).foregroundStyle(Color.ink)
                    }
                }
            } header: {
                Text("Which one are you in \(group.name)?")
            } footer: {
                Text("So TakaDe can show what you owe and are owed. Only this phone knows.")
            }
            Section {
                TextField("Your name", text: $newName)
                    .textContentType(.name)
                    .returnMovesOn($newName) { addMe(to: group) }
                Button("Add me", systemImage: "plus") { addMe(to: group) }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Not on the list?")
            }
        } else {
            Section {
                Text("The group hasn't arrived yet. Check your connection and try again.")
                Button("Try again") { Task { await sync.sync(id) } }
            }
        }
    }

    private func choose(_ member: MemberID, in group: GroupID) {
        Task {
            do {
                try await sync.choose(member, in: group)
                finish(group)
            } catch {
                stage = .failed(SharingError.message(for: error))
            }
        }
    }

    private func addMe(to group: ExpenseGroup) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            do {
                try await sync.addMe(named: name, to: group)
                finish(group.id)
            } catch {
                stage = .failed(SharingError.message(for: error))
            }
        }
    }

    private func finish(_ id: GroupID) {
        dismiss()
        onJoined(id)
    }
}

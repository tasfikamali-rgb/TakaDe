import SwiftUI
import TakaDeCore

/// Joins a shared group from a tapped link, or from a pasted one ("Join with a link"),
/// then asks which person in the group uses this phone.
struct JoinGroupSheet: View {
    @Environment(GroupSync.self) private var sync
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let invite: GroupInvite?
    let onJoined: (GroupID) -> Void

    private enum Stage: Equatable {
        case paste
        case joining
        case choose(GroupID)
        case failed(String)
    }

    @State private var stage: Stage = .paste
    @State private var pasted = ""
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Form {
                switch stage {
                case .paste: pasteSection
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
            .task { if let invite, stage == .paste { start(invite) } }
        }
    }

    private var isChoosing: Bool {
        if case .choose = stage { return true }
        return false
    }

    // MARK: Paste

    @ViewBuilder private var pasteSection: some View {
        Section {
            TextField("Paste the link or the whole message", text: $pasted, axis: .vertical)
                .lineLimit(3...6)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            PasteButton(payloadType: String.self) { strings in
                if let text = strings.first { pasted = text }
            }
            Button("Join", action: joinPasted)
                .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } footer: {
            Text("Ask someone in the group to tap the invite button in the group and send you the link.")
        }
    }

    private func joinPasted() {
        guard let found = GroupInvite(text: pasted) else {
            stage = .failed(String(localized: "That doesn't look like a TakaDe group link. Copy the whole message and try again.", bundle: .appLanguage))
            return
        }
        start(found)
    }

    private func start(_ invite: GroupInvite) {
        stage = .joining
        Task {
            do {
                let id = try await sync.join(invite)
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

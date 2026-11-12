import SwiftUI
import TakaDeCore

struct NewGroupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onCreated: (GroupID) -> Void

    @AppStorage(AccountModel.nameKey) private var myName = ""
    @State private var name = ""
    @State private var kind: GroupKind = .standard
    /// Everyone else, in the order added. Each shows as a row with a remove button.
    @State private var people: [DraftName] = []
    @State private var newPerson = ""
    /// Why a name wasn't added, like "Rishan is already in it".
    @State private var note: String?
    @State private var error: String?
    @State private var pickingContacts = false
    /// An optional group photo; its main colour becomes the group's colour.
    @State private var photoData: Data?
    @State private var photoPreview: UIImage?
    @FocusState private var focus: Field?

    private enum Field: Hashable { case group, newPerson }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    GroupPhotoPicker(hasPhoto: photoPreview != nil, onPick: pickPhoto, onRemove: clearPhoto) {
                        VStack(spacing: Spacing.xs) {
                            Group {
                                if let photoPreview {
                                    Image(uiImage: photoPreview).resizable().scaledToFill()
                                } else {
                                    Image(systemName: "camera")
                                        .font(.title2)
                                        .foregroundStyle(Color.ink)
                                }
                            }
                            .frame(width: 88, height: 88)
                            .background(Circle().fill(Color.lilac))
                            .clipShape(Circle())
                            Text(photoPreview == nil ? LocalizedStringKey("Add a group photo") : LocalizedStringKey("Change photo"))
                                .font(AppFont.label)
                                .foregroundStyle(Color.ink)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Optional. The group takes its colour from the photo.")
                        .foregroundStyle(Color.inkMuted)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                Section {
                    Picker("Kind of group", selection: $kind) {
                        Text("Trip or flat").tag(GroupKind.standard)
                        Text("Mess").tag(GroupKind.mess)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Group {
                        if kind == .mess {
                            Text("Count everyone's meals each day. At the end of the month, bazar is shared by meals eaten. You keep the books.")
                        }
                    }
                    .foregroundStyle(Color.inkMuted)
                }
                Section {
                    // Vertical so long names wrap at large text sizes; Return still moves on.
                    TextField("Group name", text: $name, prompt: Text("Group name").foregroundStyle(Color.inkMuted), axis: .vertical)
                        .focused($focus, equals: .group)
                        .accessibilityIdentifier("newGroup.name")
                        .submitLabel(.next)
                        .returnMovesOn($name) { focus = .newPerson }
                } footer: {
                    Group {
                        if kind == .mess {
                            Text("Like Mirpur mess or Hall room 212")
                        } else {
                            Text("For a trip, a flat or a dinner, like Cox's Bazar trip")
                        }
                    }
                    .foregroundStyle(Color.inkMuted)
                }
                Section {
                    ForEach(people) { person in
                        HStack(spacing: Spacing.s) {
                            Avatar(name: person.text, size: 32)
                            Text(verbatim: person.text)
                                .font(AppFont.body)
                                .foregroundStyle(Color.ink)
                            Spacer()
                            Button { remove(person) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(Color.inkMuted)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text("Remove \(person.text)"))
                        }
                    }
                    .onDelete { people.remove(atOffsets: $0) }
                    HStack(spacing: Spacing.s) {
                        TextField("Add name", text: $newPerson, prompt: Text("Add name").foregroundStyle(Color.inkMuted))
                            .textContentType(.name)
                            .focused($focus, equals: .newPerson)
                            .accessibilityIdentifier("newGroup.memberName")
                            .submitLabel(.next)
                            .onSubmit(addTyped)
                        // Shown only when it can add, not greyed out (greyed text fails contrast).
                        if PersonName.isValid(trimmedNewPerson) {
                            Button("Add", action: addTyped)
                                .buttonStyle(.borderless)
                                .font(AppFont.bodyEmphasis)
                        }
                    }
                    Button("From contacts", systemImage: "person.crop.circle.badge.plus") { pickingContacts = true }
                } header: {
                    Text("Who else is in it")
                        .foregroundStyle(Color.inkMuted)
                } footer: {
                    Group {
                        // Your own name comes from your account; it's never asked for here.
                        if !trimmedMyName.isEmpty {
                            Text("You're in it as \(trimmedMyName). Anyone can add a nickname later.")
                        }
                        if !trimmedNewPerson.isEmpty {
                            NameRuleText(newPerson)
                        }
                        if let note {
                            Text(verbatim: note)
                        }
                    }
                    .foregroundStyle(Color.inkMuted)
                }
                if let error {
                    Section { Text(error).foregroundStyle(Color.owe) }
                }
            }
            .readableWidth()
            .sheet(isPresented: $pickingContacts) { ContactSearchSheet(onPick: addContacts).rebuildsOnDynamicType() }
            .navigationTitle("New group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create).disabled(!canSave)
                }
            }
        }
    }

    private var trimmedMyName: String { myName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedNewPerson: String { newPerson.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Everyone to add, including a name still in the field, so Create works without
    /// tapping Add first.
    private var allOthers: [String] {
        let listed = people.map(\.text)
        return PersonName.isValid(trimmedNewPerson) && !isTaken(trimmedNewPerson) ? listed + [trimmedNewPerson] : listed
    }

    /// Your name was checked when the account was made, so only the others are checked.
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !trimmedMyName.isEmpty
            && !allOthers.isEmpty
            && (trimmedNewPerson.isEmpty || PersonName.isValid(trimmedNewPerson))
    }

    /// Same name as you or someone already listed, ignoring case and extra spaces.
    private func isTaken(_ name: String) -> Bool {
        let key = name.lowercased()
        return trimmedMyName.lowercased() == key || people.contains { $0.text.lowercased() == key }
    }

    /// Adds the typed name as a row and clears the field for the next one.
    private func addTyped() {
        let typed = trimmedNewPerson
        guard PersonName.isValid(typed) else { return }
        if isTaken(typed) {
            note = String(localized: "\(typed) is already in it.", bundle: .appLanguage)
        } else {
            people.append(DraftName(text: typed))
            note = nil
        }
        newPerson = ""
        focus = .newPerson
    }

    private func remove(_ person: DraftName) {
        people.removeAll { $0.id == person.id }
    }

    /// Everyone picked shows up as a row right away. Anyone already listed is skipped.
    private func addContacts(_ names: [String]) {
        var skipped: [String] = []
        for picked in names {
            let name = picked.trimmingCharacters(in: .whitespacesAndNewlines)
            guard PersonName.isValid(name) else { continue }
            if isTaken(name) { skipped.append(name) } else { people.append(DraftName(text: name)) }
        }
        note = skipped.isEmpty ? nil : String(localized: "\(skipped.formatted(.list(type: .and))) is already in it.", bundle: .appLanguage)
    }

    private func pickPhoto(_ data: Data) {
        photoData = data
        photoPreview = UIImage(data: data)
    }

    private func clearPhoto() {
        photoData = nil
        photoPreview = nil
    }

    private func cancel() { dismiss() }

    private func create() {
        Task {
            do {
                let group = try await model.createGroup(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    myName: trimmedMyName,
                    otherNames: allOthers,
                    kind: kind,
                    photo: photoData)
                dismiss()
                onCreated(group.id)
            } catch is AppModel.GroupLimitReached {
                self.error = GroupLimitText.message
            } catch {
                self.error = String(localized: "The group wasn't saved. Try again.", bundle: .appLanguage)
            }
        }
    }
}

#Preview {
    NewGroupView(onCreated: { _ in }).environment(AppModel.preview())
}

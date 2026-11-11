import SwiftUI
import TakaDeCore

struct NewGroupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onCreated: (GroupID) -> Void

    @AppStorage(AccountModel.nameKey) private var myName = ""
    @State private var name = ""
    @State private var kind: GroupKind = .standard
    @State private var others: [DraftName] = [DraftName()]
    @State private var error: String?
    @State private var pickingContacts = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case group, me, other(UUID) }

    var body: some View {
        NavigationStack {
            Form {
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
                        .submitLabel(.next)
                        .returnMovesOn($name) { focus = .me }
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
                    TextField("Your name", text: $myName, prompt: Text("Your name").foregroundStyle(Color.inkMuted), axis: .vertical)
                        .textContentType(.name)
                        .focused($focus, equals: .me)
                        .submitLabel(.next)
                        .returnMovesOn($myName) { focus = others.first.map { Field.other($0.id) } }
                } footer: {
                    Text("Names are kept exactly as you type them")
                        .foregroundStyle(Color.inkMuted)
                }
                Section {
                    ForEach($others) { $person in
                        TextField("Name", text: $person.text, prompt: Text("Name").foregroundStyle(Color.inkMuted), axis: .vertical)
                            .focused($focus, equals: .other(person.id))
                            .submitLabel(.next)
                            .returnMovesOn($person.text) { focusAfter(person.id) }
                    }
                    Button("Add another person", systemImage: "plus", action: addRow)
                    Button("Choose from Contacts", systemImage: "person.crop.circle.badge.plus") { pickingContacts = true }
                        .background(ContactPicker(isPresented: $pickingContacts, onPick: addContacts))
                } header: {
                    Text("Who else is in it")
                        .foregroundStyle(Color.inkMuted)
                } footer: {
                    Group {
                        if let duplicate = duplicateName {
                            Text("Two people are called \(duplicate). Add something to tell them apart, like an initial.")
                        }
                    }
                    .foregroundStyle(Color.inkMuted)
                }
                if let error {
                    Section { Text(error).foregroundStyle(Color.owe) }
                }
            }
            .readableWidth()
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

    private var cleanedOthers: [String] {
        others.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// The first name used twice, compared without case or extra spaces. Names are never
    /// changed for the person; this only warns, because both are allowed.
    private var duplicateName: String? {
        var seen = Set<String>()
        for name in [myName.trimmingCharacters(in: .whitespacesAndNewlines)] + cleanedOthers where !name.isEmpty {
            let key = name.lowercased()
            if seen.contains(key) { return name }
            seen.insert(key)
        }
        return nil
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !myName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !cleanedOthers.isEmpty
    }

    private func addRow() { others.append(DraftName()) }

    /// Fills empty rows first, then adds rows. Names already typed are left alone.
    private func addContacts(_ names: [String]) {
        for name in names {
            if let empty = others.firstIndex(where: { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                others[empty].text = name
            } else {
                var row = DraftName()
                row.text = name
                others.append(row)
            }
        }
    }

    /// Return in the last filled name adds a row, so a group can be typed without the mouse
    /// or a tap; Return in an empty last row closes the keyboard.
    private func focusAfter(_ id: UUID) {
        guard let index = others.firstIndex(where: { $0.id == id }) else { return }
        if index + 1 < others.count {
            focus = .other(others[index + 1].id)
        } else if !others[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let row = DraftName()
            others.append(row)
            focus = .other(row.id)
        } else {
            focus = nil
        }
    }

    private func cancel() { dismiss() }

    private func create() {
        Task {
            do {
                let group = try await model.createGroup(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    myName: myName.trimmingCharacters(in: .whitespacesAndNewlines),
                    otherNames: cleanedOthers,
                    kind: kind)
                dismiss()
                onCreated(group.id)
            } catch {
                self.error = String(localized: "The group wasn't saved. Try again.", bundle: .appLanguage)
            }
        }
    }
}

#Preview {
    NewGroupView(onCreated: { _ in }).environment(AppModel.preview())
}

import SwiftUI
import TakaDeCore

struct NewGroupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onCreated: (GroupID) -> Void

    @AppStorage("myDisplayName") private var myName = ""
    @State private var name = ""
    @State private var others: [DraftName] = [DraftName()]
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Group name, like Cox's Bazar trip", text: $name)
                }
                Section {
                    TextField("Your name", text: $myName)
                        .textContentType(.name)
                } footer: {
                    Text("Names are kept exactly as you type them")
                }
                Section("Who else is in it") {
                    ForEach($others) { $person in
                        TextField("Name", text: $person.text)
                    }
                    Button("Add another person", systemImage: "plus", action: addRow)
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
        others.map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !myName.trimmingCharacters(in: .whitespaces).isEmpty
            && !cleanedOthers.isEmpty
    }

    private func addRow() { others.append(DraftName()) }

    private func cancel() { dismiss() }

    private func create() {
        Task {
            do {
                let group = try await model.createGroup(
                    name: name.trimmingCharacters(in: .whitespaces),
                    myName: myName.trimmingCharacters(in: .whitespaces),
                    otherNames: cleanedOthers)
                dismiss()
                onCreated(group.id)
            } catch {
                self.error = String(localized: "The group wasn't saved. Try again.")
            }
        }
    }
}

#Preview {
    NewGroupView(onCreated: { _ in }).environment(AppModel.preview())
}

import SwiftUI

struct NewGroupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("myDisplayName") private var myName = ""
    @State private var name = ""
    @State private var others: [String] = [""]
    @State private var error: String?

    private var cleanedOthers: [String] {
        others.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !myName.trimmingCharacters(in: .whitespaces).isEmpty
            && !cleanedOthers.isEmpty
    }

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
                    Text("Names are kept exactly as you type them.")
                }
                Section("Who else is in it") {
                    ForEach(others.indices, id: \.self) { index in
                        TextField("Name", text: $others[index])
                    }
                    Button("Add another person") { others.append("") }
                }
                if let error {
                    Section { Text(error).foregroundStyle(Color.owe) }
                }
            }
            .navigationTitle("New group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            do {
                                _ = try await model.createGroup(
                                    name: name.trimmingCharacters(in: .whitespaces),
                                    myName: myName.trimmingCharacters(in: .whitespaces),
                                    otherNames: cleanedOthers)
                                dismiss()
                            } catch {
                                self.error = String(localized: "The group wasn't saved. Try again.")
                            }
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

import SwiftUI
import TakaDeCore

/// "Add a friend" in the Social tab: their TakaDe ID, typed or scanned, and the name you
/// know them by. Their phone gets a request with your name, sealed so only it can read it.
struct AddFriendSheet: View {
    @Environment(SocialModel.self) private var social
    @Environment(Friends.self) private var friends
    @Environment(\.dismiss) private var dismiss
    let onAdded: (UUID) -> Void

    @State private var idText = ""
    @State private var name = ""
    @State private var scanning = false
    @State private var working = false
    @State private var error: String?
    /// The name their QR code carried, so an unchanged one counts as theirs, not yours.
    @State private var scannedName: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            AppForm {
                Section {
                    TextField("TKD-XXXX-XXXX", text: $idText)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    if QRScanner.isAvailable {
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
                } header: {
                    Text("Their name")
                } footer: {
                    Text("Filled in from their QR code. Leave it empty to use the name they set, once they accept.")
                }
                Section {
                    Button(action: add) {
                        HStack(spacing: Spacing.s) {
                            Text("Add friend")
                            if working { ProgressView() }
                        }
                    }
                    .disabled(working || FriendCode(typed: idText) == nil || !(trimmedName.isEmpty || PersonName.isValid(trimmedName)))
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
                    Text("They'll see your name and can message you back.")
                }
            }
            .readableWidth()
            .navigationTitle(Text("Add a friend"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $scanning) {
                QRScannerSheet { text in
                    if let code = FriendCode(scanned: text) {
                        idText = code.description
                        if let shared = FriendCode.sharedName(inScanned: text), trimmedName.isEmpty || trimmedName == scannedName {
                            name = shared
                            scannedName = shared
                        }
                        error = nil
                    } else {
                        error = String(localized: "That QR code isn't a TakaDe ID.", bundle: .appLanguage)
                    }
                }
            }
        }
    }

    private func add() {
        guard let code = FriendCode(typed: idText) else {
            error = String(localized: "That's not a TakaDe ID. It looks like TKD-7F3K-9QXM.", bundle: .appLanguage)
            return
        }
        if code == friends.myCode {
            error = String(localized: "That's your own TakaDe ID.", bundle: .appLanguage)
            return
        }
        working = true
        error = nil
        Task {
            defer { working = false }
            do {
                let friend = try await social.add(code: code, name: trimmedName.isEmpty ? nil : trimmedName,
                                                  namedByMe: trimmedName != scannedName)
                dismiss()
                onAdded(friend.id)
            } catch {
                self.error = Friends.Failure.message(for: error)
            }
        }
    }
}

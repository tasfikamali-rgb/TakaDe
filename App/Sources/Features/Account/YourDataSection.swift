import SwiftUI

/// Settings > Data and export: what's stored where, export everything, delete everything.
struct YourDataSection: View {
    @Environment(AccountModel.self) private var account
    @Environment(AppModel.self) private var app
    @State private var exportURL: URL?
    @State private var confirmingErase = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            Text("Your groups, expenses and payments stay on this phone, in an encrypted file that unlocks after you first unlock your phone. They're never uploaded.")
                .font(AppFont.body)
                .foregroundStyle(Color.inkMuted)
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Share the export file", systemImage: "square.and.arrow.up")
                }
            } else {
                Button("Export my data", systemImage: "doc.badge.arrow.up", action: export)
            }
            Button("Delete all my data", role: .destructive) { confirmingErase = true }
                .foregroundStyle(Color.owe)
            if let errorMessage {
                Text(verbatim: errorMessage).foregroundStyle(Color.owe)
            }
        } header: {
            Text("Your data")
                .foregroundStyle(Color.inkMuted)
        } footer: {
            Group {
                if exportURL != nil {
                    Text("The file holds all your groups, names and amounts. Once you share it, it's outside TakaDe's protection.")
                }
            }
            .foregroundStyle(Color.inkMuted)
        }
        .confirmationDialog("Delete all your data?", isPresented: $confirmingErase, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive, action: erase)
        } message: {
            Text("Every group, expense, payment and its history, your profile and your sign-in are removed from this phone. This can't be undone. Export first if you want a copy.")
        }
    }

    private func export() {
        Task {
            do {
                exportURL = try await account.exportFile()
                errorMessage = nil
            } catch {
                errorMessage = String(localized: "The export file couldn't be made. Try again.", bundle: .appLanguage)
            }
        }
    }

    private func erase() {
        Task {
            do {
                try await account.eraseEverything(app: app)
                exportURL = nil
            } catch {
                errorMessage = String(localized: "Your data wasn't deleted. Try again.", bundle: .appLanguage)
            }
        }
    }
}

import SwiftUI

/// Settings > Data and export: what's stored where, and export everything. Deleting lives
/// on the Settings screen itself (DeleteSection).
struct YourDataSection: View {
    @Environment(AccountModel.self) private var account
    @State private var exportURL: URL?
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
}

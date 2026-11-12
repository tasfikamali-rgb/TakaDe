import SwiftUI
import TakaDeCore

/// "Your TakaDe ID" in the Account tab: a QR code and an ID friends use to add you to a
/// group. Shown only when signed in to a TakaDe account.
struct FriendIDSection: View {
    @Environment(Friends.self) private var friends
    @Environment(AccountModel.self) private var account
    @State private var failure: String?
    @State private var copied = false
    @State private var confirmingReplace = false
    @State private var working = false

    var body: some View {
        Section {
            if let code = friends.myCode {
                VStack(spacing: Spacing.s) {
                    QRCodeImage(text: code.url(name: account.profile?.displayName).absoluteString)
                        .frame(maxWidth: 220)
                        .accessibilityLabel(Text("QR code for your TakaDe ID"))
                    Text(verbatim: code.description)
                        .font(.title3.monospaced().weight(.semibold))
                        .textSelection(.enabled)
                        .accessibilityLabel(Text(verbatim: code.description.map { String($0) }.joined(separator: " ")))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xs)
                Button(copied ? "Copied" : "Copy ID", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = code.description
                    copied = true
                    AccessibilityNotification.Announcement(String(localized: "ID copied", bundle: .appLanguage)).post()
                }
                ShareLink(item: String(localized: "Add me on TakaDe with my ID: \(code.description)", bundle: .appLanguage)) {
                    Label("Share ID", systemImage: "square.and.arrow.up")
                }
                Button("Get a new ID", systemImage: "arrow.triangle.2.circlepath") { confirmingReplace = true }
                    .disabled(working)
                if let failure {
                    Text(verbatim: failure).foregroundStyle(Color.owe)
                }
            } else if let failure {
                Text(verbatim: failure).foregroundStyle(Color.owe)
                Button("Try again") { Task { await load() } }
            } else {
                HStack(spacing: Spacing.s) {
                    ProgressView()
                    Text("Getting your ID…")
                }
            }
        } header: {
            Text("Your TakaDe ID")
        } footer: {
            Text("Friends with TakaDe add you by scanning this code or typing your ID. The code includes your name, so whoever scans it sees it. Your ID alone shows no name, email or phone number.")
        }
        .task { if friends.myCode == nil { await load() } }
        .confirmationDialog(Text("Get a new ID?"), isPresented: $confirmingReplace, titleVisibility: .visible) {
            Button("Get a new ID", role: .destructive, action: replace)
        } message: {
            Text("Your current ID and QR code stop working. Invites already sent to you still arrive.")
        }
    }

    private func load() async {
        failure = nil
        do {
            try await friends.ensureID()
        } catch {
            failure = Friends.Failure.message(for: error)
        }
    }

    private func replace() {
        working = true
        copied = false
        Task {
            defer { working = false }
            do {
                try await friends.replaceID()
            } catch {
                failure = Friends.Failure.message(for: error)
            }
        }
    }
}

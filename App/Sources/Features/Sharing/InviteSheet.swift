import SwiftUI
import TakaDeCore

/// Makes an invite link for a group. Whoever opens it joins the group on their own phone,
/// sees its expenses and can add their own.
struct InviteSheet: View {
    @Environment(GroupSync.self) private var sync
    @Environment(\.dismiss) private var dismiss
    let group: ExpenseGroup

    private enum Stage: Equatable {
        case making
        case ready(URL)
        case stopped
        case failed(String)
    }

    @State private var stage: Stage = .making
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                switch stage {
                case .making:
                    Section {
                        HStack(spacing: Spacing.s) {
                            ProgressView()
                            Text("Making a link…")
                        }
                    } footer: {
                        Text("The first time, the group is encrypted on this phone and sent so others can join.")
                    }
                case .ready(let url):
                    Section {
                        ShareLink(item: url, message: Text(verbatim: message(for: url))) {
                            Label("Share link", systemImage: "square.and.arrow.up")
                        }
                        Button(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "doc.on.doc") {
                            UIPasteboard.general.string = message(for: url)
                            copied = true
                            AccessibilityNotification.Announcement(String(localized: "Link copied", bundle: .appLanguage)).post()
                        }
                    } footer: {
                        Text("Anyone with this link can join for 7 days. They'll see this group's expenses and payments and can add their own. Names and amounts are encrypted on the phone before they're sent.")
                    }
                    Section {
                        Button("Stop this link", role: .destructive, action: stopLinks)
                    } footer: {
                        Text("Until TakaDe's website is ready, WhatsApp and Messenger may not open the link with a tap. Your friend can copy the message, open TakaDe and tap Join with a link.")
                    }
                case .stopped:
                    Section {
                        Text("Links to this group no longer work. People who already joined stay in the group.")
                        Button("Make a new link", action: make)
                    }
                case .failed(let reason):
                    Section {
                        Text(verbatim: reason).foregroundStyle(Color.owe)
                        Button("Try again", action: make)
                    }
                }
            }
            .readableWidth()
            .navigationTitle(Text("Invite to \(group.name)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { if stage == .making { await makeLink() } }
        }
    }

    /// The whole message is shared and copied, so a pasted message still carries the link.
    private func message(for url: URL) -> String {
        String(localized: "Join \(group.name) on TakaDe to see and add our shared expenses: \(url.absoluteString)\n\nIf the link doesn't open, copy this message, open TakaDe and tap Join with a link.", bundle: .appLanguage)
    }

    private func make() {
        stage = .making
        copied = false
        Task { await makeLink() }
    }

    private func makeLink() async {
        do {
            stage = .ready(try await sync.inviteLink(for: group))
        } catch {
            stage = .failed(SharingError.message(for: error))
        }
    }

    private func stopLinks() {
        Task {
            do {
                try await sync.stopLinks(for: group.id)
                stage = .stopped
            } catch {
                stage = .failed(SharingError.message(for: error))
            }
        }
    }
}

/// Plain-language messages for sharing problems. No internals.
enum SharingError {
    static func message(for error: Error) -> String {
        switch error {
        case RelayClient.Failure.offline:
            return String(localized: "You're offline. Connect to the internet and try again.", bundle: .appLanguage)
        case RelayClient.Failure.inviteNotValid, GroupSync.Failure.wrongGroup:
            return String(localized: "This link has expired or was stopped. Ask for a new one.", bundle: .appLanguage)
        case GroupSync.Failure.unavailable, RelayClient.Failure.guestSignInOff:
            return String(localized: "Sharing groups isn't available in this version of TakaDe yet.", bundle: .appLanguage)
        default:
            return String(localized: "Something went wrong. Try again in a moment.", bundle: .appLanguage)
        }
    }
}

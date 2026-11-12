import SwiftUI
import TakaDeCore

/// Asks about notifications where they matter: on a shared group, before iOS has asked.
/// Says what they're for first, then iOS shows its own question.
struct NotificationPromptCard: View {
    @Environment(GroupNotifications.self) private var notifications
    @Environment(GroupSync.self) private var sync
    let groupID: GroupID

    var body: some View {
        if sync.isShared(groupID) && notifications.offersPrompt {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Know when this group changes")
                    .font(AppFont.bodyEmphasis)
                    .foregroundStyle(Color.ink)
                Text("Get a notification when someone adds an expense you're in or pays you. Only your phone sees the names and amounts.")
                    .font(AppFont.label)
                    .foregroundStyle(Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Spacing.m) {
                    Button("Turn on") { Task { await notifications.turnOn() } }
                        .font(AppFont.bodyEmphasis)
                        .foregroundStyle(Color.accentColor)
                    Button("Not now") { notifications.dismissPrompt() }
                        .font(AppFont.body)
                        .foregroundStyle(Color.inkMuted)
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.surface))
            .task { await notifications.refreshPermission() }
        }
    }
}

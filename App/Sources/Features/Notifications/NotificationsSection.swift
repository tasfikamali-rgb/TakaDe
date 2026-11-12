import SwiftUI
import UIKit

/// Settings > Notifications: one switch for changes in shared groups.
struct NotificationsSection: View {
    @Environment(GroupNotifications.self) private var notifications
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { notifications.isDelivering }, set: { on in
                if on {
                    Task { await notifications.turnOn() }
                } else {
                    notifications.setOn(false)
                }
            })) {
                Text("Changes in shared groups")
            }
            .disabled(notifications.permission == .denied)
            if notifications.permission == .denied, let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                Button("Turn on in iPhone Settings") { openURL(url) }
            }
        } header: {
            Text("Notifications")
                .formHeader()
        } footer: {
            Text("When someone adds or changes an expense you're in, or pays you. Your phone writes these itself, so names and amounts aren't sent to any server for them.")
                .foregroundStyle(Color.inkMuted)
        }
        .task { await notifications.refreshPermission() }
    }
}

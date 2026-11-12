import Observation
import SwiftUI
import TakaDeCore
import UserNotifications

/// App notifications when someone else changes a shared group: an expense you're in, or a
/// payment to or from you (docs/adr/0025-group-change-notifications.md).
///
/// They are local notifications. The phone pulls the group's encrypted changes, opens them
/// with the group's key, and writes the notification itself, so names and amounts never
/// pass through Supabase or Apple in readable form. Without push (which needs a paid Apple
/// developer team) they arrive when TakaDe syncs: when it's open, when it comes back, and
/// when iOS gives it a background refresh.
@MainActor
@Observable
final class GroupNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let enabledKey = "groupNotificationsOn"
    static let promptDismissedKey = "groupNotificationsPromptDismissed"

    enum Permission { case notAsked, allowed, denied }

    private(set) var permission: Permission = .notAsked
    /// The person's own switch in Settings. On by default; iOS permission still decides.
    private(set) var isOn: Bool
    private(set) var promptDismissed: Bool
    /// The group on screen. Its changes already show there, so no banner for it.
    var visibleGroup: GroupID?
    /// The group of a tapped notification, for the root view to open.
    var tappedGroup: GroupID?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isOn = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        promptDismissed = defaults.bool(forKey: Self.promptDismissedKey)
        super.init()
    }

    /// Whether to show the "Get notified" card on a shared group: only before iOS has asked.
    var offersPrompt: Bool { permission == .notAsked && !promptDismissed }

    var isDelivering: Bool { isOn && permission == .allowed }

    func refreshPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: permission = .notAsked
        case .denied: permission = .denied
        default: permission = .allowed
        }
    }

    /// Asks iOS once, right after TakaDe has said what the notifications are for.
    func turnOn() async {
        setOn(true)
        if permission == .notAsked {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        }
        await refreshPermission()
    }

    func setOn(_ on: Bool) {
        isOn = on
        defaults.set(on, forKey: Self.enabledKey)
    }

    func dismissPrompt() {
        promptDismissed = true
        defaults.set(true, forKey: Self.promptDismissedKey)
    }

    // MARK: Posting

    /// Called after changes from other phones were applied to `groupID`.
    func changesArrived(_ changes: [AppliedChange], in groupID: GroupID, app: AppModel) async {
        guard isOn, !changes.isEmpty, let group = app.group(groupID) else { return }
        var balance: Money?
        if let me = group.me { balance = try? await app.balances(for: group).net(for: me.id) }
        guard let notice = GroupNotice.make(group: group, changes: changes, myBalance: balance) else { return }
        await refreshPermission()
        guard permission == .allowed else { return }

        let content = UNMutableNotificationContent()
        // With the app lock on, the notification doesn't show what the lock hides.
        if defaults.bool(forKey: AppLock.enabledKey) {
            content.title = "TakaDe"
            content.body = NotificationText.locked
        } else {
            content.title = group.name
            content.body = NotificationText.body(for: notice, in: group)
        }
        content.sound = .default
        content.threadIdentifier = group.id.description
        content.userInfo = ["group": group.id.description]
        // One notification per group: a newer one replaces the last.
        let request = UNNotificationRequest(identifier: "group-\(group.id.description)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: UNUserNotificationCenterDelegate

    // Completion-handler forms: iOS calls these on the main thread.

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let group = notification.request.content.userInfo["group"] as? String
        Task { @MainActor in
            completionHandler(group != nil && group == visibleGroup?.description ? [] : [.banner, .list, .sound])
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let raw = response.notification.request.content.userInfo["group"] as? String
        Task { @MainActor in
            if let raw, let id = UUID(uuidString: raw) { tappedGroup = GroupID(id) }
            completionHandler()
        }
    }
}

import Foundation
import Observation
import UserNotifications

/// How many changes other people made in shared groups since Activity was last open
/// (Sabit, 2026-11-12). It's the number on the Activity tab and on the app icon, and it
/// marks those entries "New" the next time Activity opens.
///
/// It counts changes as they arrive from the relay, after this phone has opened them, so it
/// works the same in the background refresh. Only the number is kept, on this phone.
/// A group's first download, when joining it, isn't counted (GroupSync skips announcing it).
@MainActor
@Observable
final class ActivityInbox {
    static let unreadKey = "activityUnread"

    /// Changes not yet seen. Shown as the tab badge.
    private(set) var unread: Int
    /// How many of the newest changes from others were unread when Activity was opened;
    /// those entries say "New" until Activity is opened again.
    private(set) var freshCount = 0
    /// True while Activity is on screen with the app open: arrivals then count as seen.
    var isViewing = false {
        didSet { if isViewing, !oldValue { open() } }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        unread = max(0, defaults.integer(forKey: Self.unreadKey))
    }

    /// `count` changes from other people were just applied.
    func record(_ count: Int) {
        guard count > 0 else { return }
        if isViewing {
            freshCount += count
        } else {
            unread += count
            save()
        }
    }

    private func open() {
        freshCount = unread
        guard unread > 0 else { return }
        unread = 0
        save()
    }

    private func save() {
        defaults.set(unread, forKey: Self.unreadKey)
        let count = unread
        // The icon number needs the notification permission; without it this does nothing.
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(count) }
    }
}

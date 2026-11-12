import SwiftUI
import TakaDeCore

/// One line under a shared group's header: is everything on the other phones yet?
/// Words and an icon, never color alone.
struct SyncStatusLabel: View {
    @Environment(GroupSync.self) private var sync
    let groupID: GroupID

    var body: some View {
        if let text {
            Label {
                Text(text)
            } icon: {
                Image(systemName: icon)
            }
            .font(AppFont.label)
            .foregroundStyle(Color.ink.opacity(0.72))
            .accessibilityElement(children: .combine)
        }
    }

    private var pending: Int { sync.states[groupID]?.pendingUploads ?? 0 }

    private var text: LocalizedStringKey? {
        switch sync.status[groupID] {
        case .ended: return "No longer shared after a year without changes. Invite people again to share it."
        case .offline: return pending > 0 ? "Offline. Your changes will be shared when you're back online." : "Offline. Showing what's on this phone."
        case .failed: return "Couldn't sync just now. Your changes are saved on this phone."
        case .syncing: return sync.isShared(groupID) ? "Syncing…" : nil
        case .upToDate, nil: return sync.isShared(groupID) ? "Shared. Up to date." : nil
        }
    }

    private var icon: String {
        switch sync.status[groupID] {
        case .offline, .failed: return "icloud.slash"
        case .ended: return "person.2.slash"
        case .syncing: return "arrow.triangle.2.circlepath"
        default: return "person.2"
        }
    }
}

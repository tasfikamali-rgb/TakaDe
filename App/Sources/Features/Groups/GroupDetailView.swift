import SwiftUI
import TakaDeCore

struct GroupDetailView: View {
    @Environment(AppModel.self) private var app
    let groupID: GroupID

    var body: some View {
        if let group = app.group(groupID) {
            GroupDetailContent(group: group)
        } else {
            ContentUnavailableView("This group is gone", systemImage: "questionmark.folder")
        }
    }
}

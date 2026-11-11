import SwiftUI
import TakaDeCore

/// Groups tab. Compact width: one column that pushes into a group. Regular width (iPad,
/// wide windows, an unfolded phone): groups on the left, the open group on the right.
/// The selection lives here, above the branch, so it survives a fold or resize.
struct HomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: GroupID?
    @State private var path: [GroupID] = []
    @State private var showingNewGroup = false

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    HomeOverview(selection: $selection, onNewGroup: showNewGroup)
                        .navigationSplitViewColumnWidth(min: 320, ideal: 380)
                } detail: {
                    NavigationStack {
                        if let selection {
                            GroupDetailView(groupID: selection)
                        } else {
                            ContentUnavailableView("Pick a group", systemImage: "person.3", description: Text("Or create one for a trip, a flat or a dinner"))
                        }
                    }
                }
            } else {
                NavigationStack(path: $path) {
                    HomeOverview(selection: $selection, onNewGroup: showNewGroup)
                        .navigationDestination(for: GroupID.self) { GroupDetailView(groupID: $0) }
                }
            }
        }
        .onChange(of: selection) { _, newValue in syncPath(newValue) }
        .onChange(of: path) { _, newValue in selection = newValue.last }
        .onChange(of: horizontalSizeClass) { syncPath(selection) }
        .sheet(isPresented: $showingNewGroup) { NewGroupView(onCreated: open) }
    }

    private func showNewGroup() { showingNewGroup = true }

    private func open(_ id: GroupID) { selection = id }

    private func syncPath(_ id: GroupID?) {
        guard horizontalSizeClass != .regular else { return }
        if let id, path.last != id { path = [id] }
        if id == nil, !path.isEmpty { path = [] }
    }
}

#Preview {
    HomeView().environment(AppModel.preview())
}

import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Profile", systemImage: "person") }
        }
        .tint(.ink)
        .overlay(alignment: .top) {
            if let error = model.loadError {
                Text(error)
                    .font(AppFont.caption)
                    .padding(Spacing.s)
                    .frame(maxWidth: .infinity)
                    .background(Color.oweTint)
                    .foregroundStyle(Color.owe)
            }
        }
    }
}

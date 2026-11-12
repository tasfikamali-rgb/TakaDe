import SwiftUI

/// The app's switch: the accent blue (`toggleOn`) when on. The app tint is ink, which is near-white in dark mode,
/// so a plain switch showed a white knob on a white track and on looked like off.
struct AppSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        // `.switch` here resets the style, so this doesn't call itself.
        Toggle(configuration)
            .toggleStyle(.switch)
            .tint(.toggleOn)
    }
}

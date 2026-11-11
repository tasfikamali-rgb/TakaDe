import SwiftUI
import UIKit

/// Light, dark, or whatever the phone uses. Applied to every window, so sheets and the
/// lock cover follow it too, with a short crossfade when it changes.
enum AppAppearance: String, CaseIterable, Identifiable {
    case automatic, light, dark

    static let storageKey = "appAppearance"
    var id: String { rawValue }

    static var stored: AppAppearance {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AppAppearance.init(rawValue:)) ?? .automatic
    }

    var label: LocalizedStringKey {
        switch self {
        case .automatic: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .automatic: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .automatic: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    @MainActor
    func apply(animated: Bool) {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        for window in windows where window.overrideUserInterfaceStyle != interfaceStyle {
            if animated {
                UIView.transition(with: window, duration: 0.3, options: [.transitionCrossDissolve, .allowAnimatedContent]) {
                    window.overrideUserInterfaceStyle = interfaceStyle
                }
            } else {
                window.overrideUserInterfaceStyle = interfaceStyle
            }
        }
    }
}

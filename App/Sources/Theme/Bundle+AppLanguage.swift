import Foundation

extension Bundle {
    /// The bundle for the language chosen in TakaDe, which may differ from the phone's.
    /// `String(localized:)` looks up the process language unless given this bundle;
    /// SwiftUI `Text("key")` follows the `\.locale` environment instead.
    static var appLanguage: Bundle {
        let raw = UserDefaults.standard.string(forKey: AppLanguage.storageKey) ?? AppLanguage.system.rawValue
        guard let language = AppLanguage(rawValue: raw), language != .system,
              let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }
}

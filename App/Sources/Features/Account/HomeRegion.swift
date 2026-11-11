import Foundation

/// "Where are you from?" in first launch. Kept on this phone only (UserDefaults); it picks
/// the suggested language now and the default currency once TakaDe supports more than taka.
enum HomeRegion {
    static let storageKey = "homeRegion"
    static let elsewhere = "other"

    /// Bangladesh first, then where most Bangladeshis abroad live.
    static let choices = ["BD", "IN", "AE", "SA", "MY", "GB", "US", "CA", elsewhere]

    /// The phone's region when it's on the list, otherwise Bangladesh.
    static var suggested: String {
        let phone = Locale.current.region?.identifier ?? ""
        return choices.contains(phone) && phone != elsewhere ? phone : "BD"
    }

    static func flag(_ code: String) -> String {
        guard code != elsewhere else { return "🌏" }
        return String(String.UnicodeScalarView(code.unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }))
    }
}

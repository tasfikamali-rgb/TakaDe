import SwiftUI
import TakaDeCore

/// What to tell someone when a name breaks the rule in PersonName (no emoji, symbols or
/// numbers). Empty names aren't errors here: the screens just keep Save disabled.
enum NameRule {
    static func message(for name: String) -> String? {
        switch PersonName.problem(with: name) {
        case .notAName:
            String(localized: "Names can only have letters, spaces, hyphens, apostrophes and dots. No emoji, numbers or symbols.", bundle: .appLanguage)
        case .tooLong:
            String(localized: "Keep names to \(PersonName.maxLength) characters or fewer.", bundle: .appLanguage)
        case .empty, nil:
            nil
        }
    }
}

/// The name rule's message under a field, in the error colour; nothing when the name is fine.
struct NameRuleText: View {
    let names: [String]

    init(_ names: String...) { self.names = names }
    init(names: [String]) { self.names = names }

    var body: some View {
        if let message = names.lazy.compactMap(NameRule.message(for:)).first {
            Text(verbatim: message)
                .foregroundStyle(Color.owe)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

import Foundation
import TakaDeCore

extension ExpenseGroup {
    var me: Member? { members.first(where: \.isMe) }

    func member(_ id: MemberID) -> Member? { members.first { $0.id == id } }

    /// "You" for the person using the phone, otherwise the nickname or name.
    func displayName(of id: MemberID) -> String {
        guard let member = member(id) else { return "?" }
        return member.isMe ? String(localized: "You", bundle: .appLanguage) : member.shownName
    }

    /// The name exactly as entered, even for "me". Used when sharing outside the app.
    func storedName(of id: MemberID) -> String {
        member(id)?.displayName ?? "?"
    }
}

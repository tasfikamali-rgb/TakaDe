import Foundation
import TakaDeCore
import UIKit

/// Someone in the new-group form, with a stable identity for `ForEach`. Everyone comes from
/// a real place (Sabit, 2026-11-12): a TakaDe friend, a scanned TakaDe ID, or Contacts.
/// Their photo and mobile number stay on this phone.
struct DraftName: Identifiable, Hashable {
    let id = UUID()
    var text = ""
    var contact: PickedContact?
    /// The person's photo, decoded once for the row's avatar.
    var preview: UIImage?
    /// Set for a TakaDe user: they get the group's invite, sealed to their key, once it's made.
    var takaDe: TakaDeUser?

    struct TakaDeUser: Hashable {
        let code: FriendCode
        /// Their X25519 public key, base64url, when already known (a friend, or a scanned ID
        /// that was looked up). Looked up again when missing.
        var publicKey: String?
        /// True when they're already in the Social tab, so they aren't added there again.
        var isFriend: Bool
    }

    /// What gets saved: the name, plus the photo and number when there are any.
    var picked: PickedContact {
        var person = PickedContact(name: text)
        person.photo = contact?.photo
        person.mobileNumber = contact?.mobileNumber
        return person
    }
}

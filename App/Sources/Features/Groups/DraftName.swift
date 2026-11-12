import Foundation
import UIKit

/// A name in a form list, with a stable identity for `ForEach`. Someone picked from
/// Contacts also carries their contact photo and mobile number until the group is made.
struct DraftName: Identifiable, Hashable {
    let id = UUID()
    var text = ""
    var contact: PickedContact?
    /// The contact photo, decoded once for the row's avatar.
    var preview: UIImage?

    /// What gets saved: the name, plus the contact's photo and number when picked.
    var picked: PickedContact {
        var person = PickedContact(name: text)
        person.photo = contact?.photo
        person.mobileNumber = contact?.mobileNumber
        return person
    }
}

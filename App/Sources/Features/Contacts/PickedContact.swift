import Contacts
import Foundation
import TakaDeCore

/// Someone picked from Contacts (Sabit, 2026-11-12): their name exactly as written there,
/// their contact photo and their Bangladeshi mobile number, if they have them. Only the
/// people tapped are read. All of it stays on this phone: the photo becomes their avatar and
/// the number is saved as their bKash number, and neither goes into a shared group's sync.
struct PickedContact: Hashable, Sendable {
    let name: String
    /// The contact's thumbnail, as Contacts stores it.
    var photo: Data?
    /// 01XXXXXXXXX, from the contact's first Bangladeshi mobile number.
    var mobileNumber: String?

    init(name: String, photo: Data? = nil, mobileNumber: String? = nil) {
        self.name = name
        self.photo = photo
        self.mobileNumber = mobileNumber
    }

    /// Nil for a contact without a usable name.
    init?(_ contact: CNContact) {
        guard let name = ContactName.of(contact) else { return nil }
        self.name = name
        if contact.isKeyAvailable(CNContactThumbnailImageDataKey) {
            photo = contact.thumbnailImageData
        }
        if contact.isKeyAvailable(CNContactPhoneNumbersKey) {
            mobileNumber = Self.mobileNumber(in: contact.phoneNumbers)
        }
    }

    /// The fields read for each picked person, on top of the name. Nothing else (no email,
    /// address, birthday or notes) is asked for.
    static var detailKeys: [CNKeyDescriptor] { [
        CNContactThumbnailImageDataKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
    ] }

    /// A number labelled mobile or iPhone first, then any other that's a BD mobile number.
    /// Numbers from other countries are skipped: wallets here need a BD number.
    static func mobileNumber(in numbers: [CNLabeledValue<CNPhoneNumber>]) -> String? {
        let mobileLabels: Set<String> = [CNLabelPhoneNumberMobile, CNLabelPhoneNumberiPhone, CNLabelPhoneNumberMain]
        let preferred = numbers.filter { $0.label.map(mobileLabels.contains) ?? false }
        let rest = numbers.filter { !($0.label.map(mobileLabels.contains) ?? false) }
        for labeled in preferred + rest {
            if let number = PaymentHandle.walletNumber(from: labeled.value.stringValue) { return number }
        }
        return nil
    }
}

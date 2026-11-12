import Contacts
import ContactsUI
import SwiftUI

/// Apple's contact picker. It runs outside the app, so TakaDe needs no Contacts permission
/// and never sees the address book: only the people tapped come back, and only their
/// names are kept, exactly as written in Contacts.
struct ContactPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: ([String]) -> Void

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard isPresented, host.presentedViewController == nil else { return }
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        host.present(picker, animated: true)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        var parent: ContactPicker

        init(parent: ContactPicker) { self.parent = parent }

        // Implementing the plural form turns on picking several people at once.
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            let picked = contacts.compactMap { PickedContact($0) }
            parent.isPresented = false
            parent.onPick(picked)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.isPresented = false
        }
    }
}

/// How a contact's name is read, shared by both pickers.
enum ContactName {
    /// The name as Contacts shows it, without any change of spelling or script.
    static func of(_ contact: CNContact) -> String? {
        let formatted: String?
        if contact.areKeysAvailable([CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]) {
            formatted = CNContactFormatter.string(from: contact, style: .fullName)
        } else {
            let parts = [CNContactGivenNameKey, CNContactFamilyNameKey].filter(contact.isKeyAvailable).map {
                $0 == CNContactGivenNameKey ? contact.givenName : contact.familyName
            }
            formatted = parts.filter { !$0.isEmpty }.joined(separator: " ")
        }
        if let name = formatted?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        if contact.isKeyAvailable(CNContactOrganizationNameKey), !contact.organizationName.isEmpty { return contact.organizationName }
        return nil
    }
}

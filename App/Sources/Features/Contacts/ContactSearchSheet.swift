import Contacts
import SwiftUI
import TakaDeCore
import UIKit

/// Pick several people from Contacts with a search box (Sabit, 2026-11-11). Apple's own
/// picker hides its search when several people can be picked, so this lists contacts in the
/// app instead. It needs Contacts access, asked for here with the reason; the list is read
/// on this phone and dropped when the sheet closes. The list holds names only; the photo and
/// mobile number are read just for the people picked, when Add is tapped. Names come back
/// exactly as written in Contacts, and nothing is uploaded. Without access it falls back to
/// Apple's picker (no search, no permission needed).
struct ContactSearchSheet: View {
    let onPick: ([PickedContact]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var state: LoadState = .loading
    @State private var contacts: [Entry] = []
    @State private var query = ""
    @State private var selected: [Entry] = []
    @State private var finishing = false
    @State private var usingSystemPicker = false

    private enum LoadState { case loading, ready, denied }

    struct Entry: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
    }

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .denied:
                    denied
                case .ready:
                    list
                }
            }
            .navigationTitle("From contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if state == .ready {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: finish) {
                            selected.isEmpty ? Text("Add") : Text("Add \(selected.count)")
                        }
                        .disabled(selected.isEmpty || finishing)
                    }
                }
            }
        }
        .task { await load() }
        .background(ContactPicker(isPresented: $usingSystemPicker) { picked in
            onPick(picked)
            dismiss()
        })
    }

    private var list: some View {
        List {
            if filtered.isEmpty {
                Text(query.isEmpty ? LocalizedStringKey("No contacts with a name") : LocalizedStringKey("No one matches that"))
                    .foregroundStyle(Color.inkMuted)
            }
            ForEach(filtered) { entry in
                let isOn = selected.contains(entry)
                Button { toggle(entry) } label: {
                    HStack(spacing: Spacing.s) {
                        Avatar(name: entry.name, size: 36)
                        Text(verbatim: entry.name)
                            .font(AppFont.body)
                            .foregroundStyle(Color.ink)
                        Spacer()
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isOn ? Color.ink : Color.inkMuted)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search contacts"))
        .autocorrectionDisabled()
        // While searching, iOS hides the navigation bar's buttons, so Add also sits at the
        // bottom, above the keyboard, whenever someone is picked (Sabit, 2026-11-12).
        .safeAreaInset(edge: .bottom) {
            if !selected.isEmpty {
                Button(action: finish) {
                    Text(selected.count == 1 ? LocalizedStringKey("Add \(selected[0].name)") : LocalizedStringKey("Add \(selected.count) people"))
                        .lineLimit(1)
                }
                .disabled(finishing)
                .buttonStyle(PillButtonStyle())
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.vertical, Spacing.xs)
                .background(Color.canvas)
            }
        }
    }

    private var denied: some View {
        ContentUnavailableView {
            Label("TakaDe can't see your contacts", systemImage: "person.crop.circle.badge.questionmark")
        } description: {
            Text("Allow Contacts in Settings to search them here, or pick people with Apple's picker.")
        } actions: {
            Button("Use Apple's picker") { usingSystemPicker = true }
                .buttonStyle(.borderedProminent)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
            }
        }
    }

    private var filtered: [Entry] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return contacts }
        return contacts.filter { $0.name.localizedStandardContains(query) }
    }

    /// Reads the photo and mobile number of only the people picked, then hands them back in
    /// the order they were picked. Anyone whose details can't be read comes back by name alone.
    private func finish() {
        guard !finishing else { return }
        finishing = true
        let picked = selected
        Task {
            let details = await Task.detached(priority: .userInitiated) {
                Self.readDetails(of: picked.map(\.id), from: CNContactStore())
            }.value
            onPick(picked.map { entry in
                var contact = PickedContact(name: entry.name)
                if let found = details[entry.id] {
                    contact.photo = found.photo
                    contact.mobileNumber = found.mobileNumber
                }
                return contact
            })
            dismiss()
        }
    }

    private func toggle(_ entry: Entry) {
        if let index = selected.firstIndex(of: entry) {
            selected.remove(at: index)
        } else {
            selected.append(entry)
        }
    }

    private func load() async {
        let store = CNContactStore()
        let granted = (try? await store.requestAccess(for: .contacts)) ?? false
        guard granted else {
            state = .denied
            return
        }
        contacts = await Task.detached(priority: .userInitiated) { Self.readNames(from: CNContactStore()) }.value
        state = .ready
    }

    /// The picked people's photos and numbers, by contact identifier.
    nonisolated private static func readDetails(of identifiers: [String], from store: CNContactStore) -> [String: PickedContact] {
        guard !identifiers.isEmpty else { return [:] }
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactOrganizationNameKey as CNKeyDescriptor,
        ] + PickedContact.detailKeys
        let predicate = CNContact.predicateForContacts(withIdentifiers: identifiers)
        guard let contacts = try? store.unifiedContacts(matching: predicate, keysToFetch: keys) else { return [:] }
        var found: [String: PickedContact] = [:]
        for contact in contacts {
            if let picked = PickedContact(contact) { found[contact.identifier] = picked }
        }
        return found
    }

    /// Names only for the list: no numbers, photos, emails or other fields are read. People whose names break the
    /// name rule (emoji, symbols) are left out, since they couldn't be added anyway.
    nonisolated private static func readNames(from store: CNContactStore) -> [Entry] {
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactOrganizationNameKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .userDefault
        var entries: [Entry] = []
        var seen = Set<String>()
        try? store.enumerateContacts(with: request) { contact, _ in
            guard let name = ContactName.of(contact), PersonName.isValid(name),
                  seen.insert(name).inserted else { return }
            entries.append(Entry(id: contact.identifier, name: name))
        }
        return entries
    }
}

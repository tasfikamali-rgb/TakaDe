import Contacts
import SwiftUI
import TakaDeCore
import UIKit

/// Pick several people from Contacts with a search box (Sabit, 2026-11-11). Apple's own
/// picker hides its search when several people can be picked, so this lists contacts in the
/// app instead. It needs Contacts access, asked for here with the reason; the list is read
/// on this phone and dropped when the sheet closes. Only the names picked come back, exactly
/// as written in Contacts, and nothing is uploaded. Without access it falls back to Apple's
/// picker (no search, no permission needed).
struct ContactSearchSheet: View {
    let onPick: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var state: LoadState = .loading
    @State private var contacts: [Entry] = []
    @State private var query = ""
    @State private var selected: [String] = []
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
            .navigationTitle("Choose from Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if state == .ready {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            onPick(selected)
                            dismiss()
                        } label: {
                            selected.isEmpty ? Text("Add") : Text("Add \(selected.count)")
                        }
                        .disabled(selected.isEmpty)
                    }
                }
            }
        }
        .task { await load() }
        .background(ContactPicker(isPresented: $usingSystemPicker) { names in
            onPick(names)
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
                let isOn = selected.contains(entry.name)
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

    private func toggle(_ entry: Entry) {
        if let index = selected.firstIndex(of: entry.name) {
            selected.remove(at: index)
        } else {
            selected.append(entry.name)
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

    /// Names only: no numbers, emails or other fields are read. People whose names break the
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

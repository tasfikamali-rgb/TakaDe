import SwiftUI
import TakaDeCore

/// "Share shop names" (ADR 0032): off until the person says yes, asked once after their first
/// reviewed scan and changeable in Settings > Data and export. When on, the shop name they
/// confirmed is counted on the service by month and home country, with no link to them.
enum StoreNameSharing {
    static let storageKey = "shareStoreNames"
    static let askedKey = "storeNamesAsked"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: storageKey) }

    /// True when there's a sign-in to count with, so asking makes sense.
    @MainActor
    static func canSend(_ account: AccountModel) -> Bool {
        account.supabase?.session != nil
    }

    /// Best effort and quiet: a failure (offline, daily limit) never touches the expense.
    @MainActor
    static func send(_ merchant: String?, account: AccountModel) {
        guard isOn, let name = StoreName.normalized(merchant), let supabase = account.supabase,
              supabase.session != nil else { return }
        let country = StoreName.countryCode(UserDefaults.standard.string(forKey: HomeRegion.storageKey))
        Task {
            _ = try? await supabase.rest("rpc/count_store_name", method: "POST",
                                         body: ["p_name": name, "p_country": country])
        }
    }
}

/// Settings > Data and export: the switch, with what it sends and what it doesn't.
struct StoreNamesSection: View {
    @AppStorage(StoreNameSharing.storageKey) private var sharing = false
    @AppStorage(StoreNameSharing.askedKey) private var asked = false

    var body: some View {
        Section {
            Toggle("Share shop names from receipts", isOn: $sharing)
                .onChange(of: sharing) { asked = true }
        } header: {
            Text("Shop names")
                .formHeader()
        } footer: {
            Text("When on, the shop name you confirm after scanning a receipt is counted with your country and the month, to learn which shops people use and plan ads in TakaDe. It isn't linked to you: your name, email, account, amounts, items and photo aren't sent.")
                .foregroundStyle(Color.inkMuted)
        }
    }
}

import Foundation
import TakaDeCore

/// Where "Open bKash" goes. bKash, Nagad and upay publish no link that opens their app with a
/// number and amount filled in (checked 2026-11-12, docs/adr/0030-wallet-handoff.md), and
/// their payment APIs are merchant checkout only. So TakaDe opens the wallet's App Store
/// page, which shows "Open" when the app is installed. No number, amount or name is in the
/// link, and nothing comes back: the person still records the payment themselves.
extension PaymentHandle.Rail {
    var walletAppURL: URL? {
        switch self {
        // App Store ids from apps.apple.com/app/bkash/id1351183172 and /nagad/id1471844924.
        case .bkash: URL(string: "https://apps.apple.com/app/id1351183172")
        case .nagad: URL(string: "https://apps.apple.com/app/id1471844924")
        // upay's and Rocket's App Store ids aren't confirmed yet, so they get copy buttons only.
        case .upay, .rocket, .bank: nil
        }
    }
}

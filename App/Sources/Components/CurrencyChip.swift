import SwiftUI
import TakaDeCore

/// The small currency chip that sits above a balance.
struct CurrencyChip: View {
    let currency: Currency
    var foreground: Color = .onHeader

    var body: some View {
        Text(verbatim: "৳ \(currency.code)")
            .font(AppFont.caption)
            .foregroundStyle(foreground.opacity(0.8))
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(Capsule().stroke(foreground.opacity(0.25), lineWidth: 1))
    }
}

import SwiftUI
import TakaDeCore

/// One line read from a receipt: the words as printed, and the amount. Discounts show
/// as a minus. The label and amount are the receipt's own English text and digits, so they aren't
/// translated; only the labels around them follow the app language.
struct ReceiptLineRow: View {
    let line: ReceiptLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: line.label.isEmpty ? "–" : line.label)
                    .font(AppFont.body)
                    .foregroundStyle(Color.ink)
                if let kind {
                    Text(kind).font(AppFont.caption).foregroundStyle(Color.inkMuted)
                }
            }
            Spacer(minLength: Spacing.s)
            // The receipt itself stays in English, digits too, so it matches the paper.
            AmountText(money: line.kind == .discount ? line.amount.negated : line.amount, size: .body)
                .environment(\.locale, Locale(identifier: "en"))
        }
        .accessibilityElement(children: .combine)
    }

    private var kind: LocalizedStringKey? {
        switch line.kind {
        case .item: nil
        case .subtotal: "Subtotal"
        case .tax: "VAT or tax"
        case .serviceCharge: "Service charge"
        case .discount: "Discount"
        }
    }
}

/// Whether the lines add up to the total the person picked. A mismatch usually means
/// a misread amount, so it says so in words, not only color.
struct ReceiptCheckRow: View {
    let computed: Money
    let total: Money

    var body: some View {
        if computed == total {
            Label("Lines add up to the total", systemImage: "checkmark.circle")
                .font(AppFont.label)
                .foregroundStyle(Color.inkMuted)
        } else {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label("Lines don't add up to the total", systemImage: "exclamationmark.triangle")
                    .font(AppFont.label)
                    .foregroundStyle(Color.ink)
                HStack(spacing: Spacing.xs) {
                    Text("The lines come to").font(AppFont.caption).foregroundStyle(Color.inkMuted)
                    AmountText(money: computed, size: .body)
                }
                Text("Check the total, or type the amount yourself.")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.inkMuted)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

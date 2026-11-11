import SwiftUI
import TakaDeCore

/// Renders money with the symbol and decimals smaller and muted (DESIGN.md section 3).
struct AmountText: View {
    let money: Money
    var font: Font = AppFont.balance
    var color: Color = .ink
    @AppStorage(DigitStyle.storageKey) private var digits: DigitStyle = .latin

    var body: some View {
        let f = MoneyFormatter.format(money, digits: digits)
        (Text(f.sign + f.symbol + " ").font(font).foregroundStyle(Color.inkMuted)
            + Text(f.whole).font(font).foregroundStyle(color)
            + Text(f.fraction).font(font).foregroundStyle(Color.inkMuted))
            .monospacedDigit()
            .contentTransition(.numericText())
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityLabel(Self.spoken(money))
    }

    /// e.g. "7854 taka 43 poisha", read naturally by VoiceOver in the current locale.
    static func spoken(_ money: Money) -> String {
        let taka = String(localized: "taka")
        let poisha = String(localized: "poisha")
        let sign = money.isNegative ? String(localized: "minus") + " " : ""
        let whole = abs(money.majorPart).formatted()
        return money.minorPart == 0 ? "\(sign)\(whole) \(taka)" : "\(sign)\(whole) \(taka) \(money.minorPart) \(poisha)"
    }
}

/// A balance pill that never relies on color alone: it always says owe/owed in words.
struct BalancePill: View {
    let net: Money

    var body: some View {
        let owed = net.minorUnits > 0
        let settled = net.isZero
        HStack(spacing: Spacing.xxs) {
            Text(settled ? LocalizedStringKey("Settled up") : owed ? LocalizedStringKey("You are owed") : LocalizedStringKey("You owe"))
            if !settled {
                AmountText(money: net.magnitude, font: AppFont.label, color: owed ? .owed : .owe)
            }
        }
        .font(AppFont.label)
        .foregroundStyle(settled ? Color.inkMuted : owed ? Color.owed : Color.owe)
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xxs + 2)
        .background(Capsule().fill(settled ? Color.surfaceRaised : owed ? Color.owedTint : Color.oweTint))
    }
}

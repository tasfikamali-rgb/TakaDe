import SwiftUI
import TakaDeCore

/// Renders money with the symbol and decimals smaller and muted (DESIGN.md section 3),
/// in the digit style the person chose.
struct AmountText: View {
    let money: Money
    var font: Font = AppFont.balance
    var color: Color = .ink
    var showsZeroFraction = true

    @AppStorage(DigitPreference.storageKey) private var digitPreference: DigitPreference = .automatic
    @Environment(\.locale) private var locale

    var body: some View {
        let f = MoneyFormatter.format(money, digits: digitPreference.resolved(for: locale), showsZeroFraction: showsZeroFraction)
        Text("\(Text(verbatim: f.sign + f.symbol + "\u{2009}").foregroundStyle(Color.inkMuted))\(Text(verbatim: f.whole).foregroundStyle(color))\(Text(verbatim: f.fraction).foregroundStyle(Color.inkMuted))")
            .font(font)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(money.minorUnits)))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityLabel(Text(SpokenAmount.text(for: money)))
    }
}

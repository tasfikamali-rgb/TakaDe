import SwiftUI
import TakaDeCore

/// Money with a small muted ৳ and decimals beside a large figure (DESIGN.md section 3),
/// baseline aligned, in the digits the person chose.
struct AmountText: View {
    let money: Money
    var size: AmountSize = .balance
    var color: Color = .ink
    var minorColor: Color = .inkMuted
    var showsZeroFraction = true

    @Environment(\.locale) private var locale

    var body: some View {
        let digits = DigitPreference.style(for: locale)
        let bengali = digits == .bengali
        let f = MoneyFormatter.format(money, digits: digits, showsZeroFraction: showsZeroFraction)
        let symbol = Text(verbatim: f.sign + f.symbol + "\u{2009}").font(size.minor(bengaliDigits: true)).foregroundStyle(minorColor)
        let whole = Text(verbatim: f.whole).font(size.main(bengaliDigits: bengali)).tracking(size.tracking).foregroundStyle(color)
        let fraction = Text(verbatim: f.fraction).font(size.minor(bengaliDigits: bengali)).foregroundStyle(minorColor)
        Text("\(symbol)\(whole)\(fraction)")
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(money.minorUnits)))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityLabel(Text(SpokenAmount.text(for: money)))
    }
}

import SwiftUI
import TakaDeCore

/// Money with a small muted ৳ and decimals beside a large figure (DESIGN.md section 3),
/// baseline aligned, in the digits the person chose.
struct AmountText: View {
    let money: Money
    var size: AmountSize = .balance
    var color: Color = .ink
    /// The decimals' colour. Left out, plain amounts get muted decimals, and coloured ones
    /// (owed, owe) keep their colour so the whole amount reads as one (Sabit, 2026-11-12).
    var minorColor: Color?
    var showsZeroFraction = true

    @Environment(\.locale) private var locale

    var body: some View {
        let digits = DigitPreference.style(for: locale)
        let bengali = digits == .bengali
        let f = MoneyFormatter.format(money, digits: digits, showsZeroFraction: showsZeroFraction)
        let fractionColor = minorColor ?? (color == .ink ? .inkMuted : color)
        let symbol = Text(verbatim: f.sign + f.symbol + "\u{2009}").font(size.minor(bengaliDigits: true)).foregroundStyle(minorColor ?? .inkMuted)
        let whole = Text(verbatim: f.whole).font(size.main(bengaliDigits: bengali)).tracking(size.tracking).foregroundStyle(color)
        let fraction = Text(verbatim: f.fraction).font(size.minor(bengaliDigits: bengali)).foregroundStyle(fractionColor)
        Text("\(symbol)\(whole)\(fraction)")
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(money.minorUnits)))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityLabel(Text(SpokenAmount.text(for: money)))
    }
}

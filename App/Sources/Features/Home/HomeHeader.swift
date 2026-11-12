import SwiftUI
import TakaDeCore

/// The wallet header (DESIGN.md section 4.2). One job: where you stand overall.
struct HomeHeader: View {
    let total: Money
    let hasGroups: Bool
    let onAddExpense: () -> Void
    let onNewGroup: () -> Void

    @Environment(ExchangeRateStore.self) private var exchange
    @AppStorage(CurrencyCatalog.codeKey) private var foreignCode = CurrencyCatalog.defaultCode
    @AppStorage(CurrencyCatalog.showsForeignKey) private var showsForeign = false
    @State private var choosingCurrency = false

    /// The balance in the other currency, when it's switched on and a rate is known.
    private var converted: Money? {
        guard showsForeign else { return nil }
        return exchange.rates?.convert(total.magnitude, to: CurrencyCatalog.currency(foreignCode))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Spacer()
                QuickSettingsMenu()
            }
            if hasGroups {
            HStack {
                Text(BalanceState(total).totalLabel)
                    .font(AppFont.label)
                    .foregroundStyle(Color.onHeader.opacity(0.72))
                Spacer()
                CurrencyToggle(foreignCode: foreignCode, showsForeign: $showsForeign) { choosingCurrency = true }
            }
            AmountText(money: converted ?? total.magnitude, size: .balance, color: .onHeader, minorColor: .onHeader.opacity(0.6))
            if showsForeign {
                RateCaption(foreignCode: foreignCode, converted: converted != nil)
            }
            HStack(spacing: Spacing.s) {
                Button("Add expense", systemImage: "plus", action: onAddExpense)
                    .buttonStyle(HeaderPillButtonStyle(filled: true))
                Button("New group", systemImage: "person.2", action: onNewGroup)
                    .buttonStyle(HeaderPillButtonStyle(filled: false))
            }
            .padding(.top, Spacing.xs)
            } else {
                HomeGreeting()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.xs)
        .padding(.bottom, Spacing.huge + Radius.sheet)
        .sheet(isPresented: $choosingCurrency) {
            CurrencyPickerSheet(selection: $foreignCode, available: availableCodes) { showsForeign = true }
        }
        // Each open (and each switch to another currency) asks for today's rates.
        .task(id: showsForeign) { if showsForeign { await exchange.refresh() } }
        // HomeOverview paints the header color (with its moving lines) behind this.
    }

    private var availableCodes: [String] {
        let fromRates = exchange.rates?.currencyCodes(knownISO: CurrencyCatalog.knownISO) ?? []
        return fromRates.isEmpty ? CurrencyCatalog.knownISO.filter { $0 != Currency.bdt.code }.sorted() : fromRates
    }
}

/// Under a converted balance: which rate it used and how old it is, so nobody mistakes
/// it for a live price. "£1 = ৳166.91 · rate from 11 Nov".
private struct RateCaption: View {
    let foreignCode: String
    let converted: Bool

    @Environment(ExchangeRateStore.self) private var exchange
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if converted, let rates = exchange.rates {
                let pair = pairText(rates)
                let day = dayText(rates.date)
                if exchange.lastRefreshFailed {
                    Text("\(pair) · rate from \(day) · offline")
                } else {
                    Text("\(pair) · rate from \(day)")
                }
            } else if exchange.rates == nil {
                Text("Connect to the internet to see \(foreignCode). Showing taka for now.")
            } else {
                Text("No rate for \(foreignCode) today. Showing taka.")
            }
        }
        .font(AppFont.caption)
        .foregroundStyle(Color.onHeader.opacity(0.72))
        .fixedSize(horizontal: false, vertical: true)
    }

    /// "£1 = ৳166.91", in the person's digits.
    private func pairText(_ rates: ExchangeRates) -> String {
        let foreign = CurrencyCatalog.currency(foreignCode)
        let one = Money(minorUnits: foreign.minorUnitsPerMajor, currency: foreign)
        let digits = DigitPreference.style(for: locale)
        let left = MoneyFormatter.format(one, digits: digits, grouping: .western, showsZeroFraction: false,
                                         symbol: CurrencyCatalog.symbol(foreignCode)).plain
        guard let taka = rates.convert(one, to: .bdt) else { return left }
        return left + " = " + MoneyFormatter.format(taka, digits: digits).plain
    }

    /// "11 Nov": the day the source published the rates.
    private func dayText(_ day: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: day) else { return day }
        var style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        style.locale = locale
        style.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return date.formatted(style)
    }
}

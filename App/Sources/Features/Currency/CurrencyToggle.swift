import SwiftUI
import TakaDeCore

/// The currency switch above the balance (Sabit, 2026-11-12): taka on one side, the
/// person's other currency (£ GBP) on the other. Tap a side to switch; tap the other
/// currency again, or long-press, to choose a different one.
struct CurrencyToggle: View {
    let foreignCode: String
    @Binding var showsForeign: Bool
    let onChooseCurrency: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            segment(code: Currency.bdt.code, selected: !showsForeign) {
                showsForeign = false
            }
            segment(code: foreignCode, selected: showsForeign, showsChevron: showsForeign) {
                if showsForeign { onChooseCurrency() } else { showsForeign = true }
            }
            .accessibilityHint(showsForeign ? Text("Double-tap to choose another currency") : Text(verbatim: ""))
        }
        .padding(3)
        .background(Capsule().fill(Color.onHeader.opacity(0.08)))
        .overlay(Capsule().stroke(Color.onHeader.opacity(0.18), lineWidth: 1))
        .animation(Motion.standard(reduceMotion: reduceMotion), value: showsForeign)
        .sensoryFeedback(.selection, trigger: showsForeign)
        .contextMenu {
            Button("Choose currency", systemImage: "dollarsign.arrow.circlepath", action: onChooseCurrency)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Show balance in"))
        .accessibilityAction(named: Text("Choose currency"), onChooseCurrency)
    }

    private func segment(code: String, selected: Bool, showsChevron: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.xxs) {
                Text(verbatim: CurrencyCatalog.symbol(code))
                    .font(code == Currency.bdt.code ? AppFont.figures(15, .semibold, relativeTo: .subheadline, bengali: true) : AppFont.label)
                Text(verbatim: code)
                    .font(AppFont.label)
                if showsChevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(selected ? Color.header : Color.onHeader.opacity(0.8))
            .padding(.horizontal, Spacing.s)
            .frame(minHeight: 36)
            .background {
                if selected { Capsule().fill(Color.onHeader) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: CurrencyCatalog.name(code, in: locale)))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

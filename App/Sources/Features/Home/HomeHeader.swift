import SwiftUI
import TakaDeCore

/// One job: where do I stand overall. The number is the memorable thing.
struct HomeHeader: View {
    let total: Money
    let onNewGroup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(total.minorUnits >= 0 ? LocalizedStringKey("You are owed in total") : LocalizedStringKey("You owe in total"))
                .font(AppFont.label)
                .foregroundStyle(Color.onHeader.opacity(0.72))
            AmountText(money: total.magnitude, color: .onHeader)
            Button("New group", systemImage: "plus", action: onNewGroup)
                .font(AppFont.label)
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.s)
                .background(Capsule().fill(Color.onHeader))
                .foregroundStyle(Color.header)
                .buttonStyle(PressScaleButtonStyle())
                .padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.xxl)
        .padding(.bottom, Spacing.huge + Radius.sheet)
        .background(Color.header)
    }
}

import SwiftUI

/// Floating dark pill with a liquid notch under the selected tab (DESIGN.md section 4.1).
struct NotchTabBar: View {
    @Binding var selection: AppTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var width: CGFloat = 0

    private let height: CGFloat = 64
    private let circle: CGFloat = 48

    var body: some View {
        let tabs = AppTab.allCases
        let slot = width / CGFloat(max(tabs.count, 1))
        let index = CGFloat(tabs.firstIndex(of: selection) ?? 0)
        let centerX = slot * (index + 0.5)

        ZStack(alignment: .topLeading) {
            NotchBarShape(notchX: centerX)
                .fill(Color.header)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.18), radius: 20, y: 8)
                .overlay(NotchBarShape(notchX: centerX).stroke(Color.onHeader.opacity(colorScheme == .dark ? 0.12 : 0), lineWidth: 1))

            Circle()
                .fill(Color.lime)
                .frame(width: circle, height: circle)
                .offset(x: centerX - circle / 2, y: 14 - circle / 2)
                .accessibilityHidden(true)

            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    NotchTabButton(tab: tab, isSelected: tab == selection, select: { select(tab) })
                }
            }
        }
        .frame(height: height)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func select(_ tab: AppTab) {
        withAnimation(Motion.momentum(reduceMotion: reduceMotion)) {
            selection = tab
        }
    }
}

#Preview {
    @Previewable @State var tab = AppTab.home
    NotchTabBar(selection: $tab).padding()
}

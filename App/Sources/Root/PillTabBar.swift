import SwiftUI

/// Compact floating pill with three tabs, each an icon over a short label. An accent capsule
/// sits behind the selected tab and springs across to the next one (DESIGN.md section 4.1).
/// Colors come only from the `tabBar…` tokens, so the palette can change without touching this.
struct PillTabBar: View {
    @Binding var selection: AppTab
    /// Unread counts by tab, shown as a small dot (Social's new messages).
    var unread: [AppTab: Int] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var slots
    /// Bumped for the tab that was just picked, so only its icon bounces.
    @State private var bounces: [AppTab: Int] = [:]
    /// True while a finger slides along the bar; the indicator lifts slightly.
    @State private var isDragging = false
    @State private var rowWidth: CGFloat = 0

    private static let barHeight: CGFloat = 58
    private static let inset: CGFloat = 5

    /// The bar plus its bottom gap, which pages leave free so nothing hides under it.
    static let reservedHeight: CGFloat = barHeight + Spacing.xs

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                PillTabButton(
                    tab: tab,
                    isSelected: tab == selection,
                    unread: unread[tab, default: 0],
                    bounce: bounces[tab, default: 0],
                    select: { select(tab) }
                )
                // Each tab marks its slot; the one indicator below follows the selected slot.
                .background(Color.clear.matchedGeometryEffect(id: tab, in: slots))
            }
        }
        .background {
            Capsule(style: .continuous)
                .fill(Color.tabBarIndicator)
                .matchedGeometryEffect(id: selection, in: slots, isSource: false)
                .scaleEffect(isDragging && !reduceMotion ? 1.06 : 1)
                .accessibilityHidden(true)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        // Slide a finger along the bar to move between tabs; taps still go to the buttons.
        .simultaneousGesture(slide)
        .padding(Self.inset)
        .frame(minHeight: Self.barHeight)
        // Its own height: grows with larger text instead of filling the space it's offered.
        .fixedSize(horizontal: false, vertical: true)
        .background {
            Capsule(style: .continuous)
                .fill(Color.tabBarBackground)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.12), radius: 18, y: 6)
                .overlay {
                    // Light mode: a hairline keeps the white pill distinct on a white page.
                    // Dark mode: a faint edge stands in for the shadow.
                    Capsule(style: .continuous)
                        .strokeBorder(Color.onHeader.opacity(colorScheme == .dark ? 0.12 : 0.06), lineWidth: 1)
                }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var slide: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if !isDragging {
                    withAnimation(Motion.press) { isDragging = true }
                }
                if let tab = tab(at: value.location.x) { select(tab) }
            }
            .onEnded { _ in
                withAnimation(Motion.tabSwitch(reduceMotion: reduceMotion)) { isDragging = false }
            }
    }

    /// The tab under a point along the row, clamped to the ends.
    private func tab(at x: CGFloat) -> AppTab? {
        let tabs = AppTab.allCases
        guard rowWidth > 0, !tabs.isEmpty else { return nil }
        let index = Int((x / rowWidth) * CGFloat(tabs.count))
        return tabs[min(max(index, 0), tabs.count - 1)]
    }

    private func select(_ tab: AppTab) {
        guard tab != selection else { return }
        if !reduceMotion { bounces[tab, default: 0] += 1 }
        withAnimation(Motion.tabSwitch(reduceMotion: reduceMotion)) {
            selection = tab
        }
    }
}

private struct PillTabButton: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let tab: AppTab
    let isSelected: Bool
    let unread: Int
    let bounce: Int
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 3) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolVariant(isSelected ? .fill : .none)
                    .symbolEffect(.bounce.down, value: bounce)
                    .frame(minHeight: 20)
                    .overlay(alignment: .topTrailing) {
                        if unread > 0 {
                            Circle()
                                .fill(isSelected ? Color.tabBarSelected : Color.tabBarIndicator)
                                .frame(width: 7, height: 7)
                                .offset(x: 5, y: -1)
                        }
                    }
                    .accessibilityHidden(true)
                // At accessibility text sizes the bar shows icons only, like the system tab
                // bar: touch and hold a tab for the large content viewer to read its name.
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(tab.title)
                        .font(AppFont.text(11, .semibold, relativeTo: .caption2))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(isSelected ? Color.tabBarSelected : Color.tabBarUnselected)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(minWidth: 60, minHeight: 48)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(tab.title)
        .accessibilityValue(unread > 0 ? Text("\(unread) unread") : Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Label(tab.title, systemImage: tab.systemImage)
        }
    }
}

#Preview {
    @Previewable @State var tab = AppTab.home
    ZStack(alignment: .bottom) {
        Color.canvas.ignoresSafeArea()
        PillTabBar(selection: $tab).padding()
    }
}

import SwiftUI

/// Pull to refresh with the TakaDe ৳ instead of the system spinner (Sabit, 2026-11-12).
/// Pulling down turns the mark with the pull; let go past the line and it keeps turning,
/// a full 360° each lap, until the refresh is done.
///
/// Usage: put `LogoRefreshHeader(state:)` first inside the scroll content, and
/// `.logoRefreshable(state:action:)` on the ScrollView. On iOS 17, which can't read the
/// pull, the system spinner does the pulling and the mark only turns while refreshing.
@MainActor
@Observable
final class LogoRefreshState {
    /// How far past the top the content is pulled, in points.
    fileprivate(set) var pull: CGFloat = 0
    private(set) var isRefreshing = false

    /// The pull that starts a refresh when let go.
    static let threshold: CGFloat = 72
    /// Room the mark keeps above the content while refreshing.
    static let height: CGFloat = 56

    /// Runs `action` once, with the mark turning; a second tap while it runs does nothing.
    func refresh(_ action: @escaping () async -> Void) async {
        guard !isRefreshing else { return }
        withAnimation(Motion.standard) { isRefreshing = true }
        await action()
        // Long enough to see one lap even when the check comes back at once.
        try? await Task.sleep(for: .milliseconds(450))
        withAnimation(Motion.standard) { isRefreshing = false }
    }
}

/// The turning ৳. `progress` (0...1) sets the angle while pulling; `spins` keeps it turning.
struct SpinningTakaMark: View {
    var progress: CGFloat = 1
    var spins: Bool
    var size: CGFloat = 26
    var color: Color = .lime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: !spins || reduceMotion)) { context in
            TakaMark(split: 1)
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .rotationEffect(angle(at: context.date))
        }
        .accessibilityHidden(true)
    }

    /// One lap every 0.9 s while spinning; with Reduce Motion the mark stays still.
    private func angle(at date: Date) -> Angle {
        if reduceMotion { return .zero }
        if spins {
            let lap = 0.9
            return .degrees(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: lap) / lap * 360)
        }
        return .degrees(Double(progress) * 360)
    }
}

/// Sits at the very top of the scroll content. While pulling it shows in the space opened
/// above the content; while refreshing it holds that space open.
struct LogoRefreshHeader: View {
    let state: LogoRefreshState
    /// Ink on a coloured group header, where the blue mark would be hard to see.
    var color: Color = .lime

    var body: some View {
        let progress = min(state.pull / LogoRefreshState.threshold, 1)
        Color.clear
            .frame(height: state.isRefreshing ? LogoRefreshState.height : 0)
            .frame(maxWidth: .infinity)
            .overlay(alignment: state.isRefreshing ? .center : .top) {
                SpinningTakaMark(progress: progress, spins: state.isRefreshing, color: color)
                    // Centred in the gap the pull opens above the content.
                    .offset(y: state.isRefreshing ? 0 : -state.pull / 2 - 13)
                    .opacity(state.isRefreshing ? 1 : Double(progress))
                    .scaleEffect(state.isRefreshing ? 1 : 0.6 + 0.4 * progress)
            }
            .accessibilityElement()
            .accessibilityLabel(state.isRefreshing ? Text("Refreshing") : Text(verbatim: ""))
            .accessibilityHidden(!state.isRefreshing)
    }
}

extension View {
    /// See `LogoRefreshState`. VoiceOver users get the same refresh through the screen's own
    /// refresh button, or the system "refresh" action on iOS 17.
    func logoRefreshable(state: LogoRefreshState, action: @escaping () async -> Void) -> some View {
        modifier(LogoRefreshModifier(state: state, action: action))
    }
}

private struct LogoRefreshModifier: ViewModifier {
    let state: LogoRefreshState
    let action: () async -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    max(0, -(geometry.contentOffset.y + geometry.contentInsets.top))
                } action: { _, pull in
                    state.pull = pull
                }
                // Starts when the finger lifts past the line, like the system control.
                .onScrollPhaseChange { old, new in
                    guard old == .interacting, new != .interacting,
                          state.pull >= LogoRefreshState.threshold, !state.isRefreshing else { return }
                    Task { await state.refresh(action) }
                }
                .sensoryFeedback(.impact(weight: .light), trigger: state.isRefreshing) { _, now in now }
        } else {
            content.refreshable { await state.refresh(action) }
        }
    }
}

/// A round refresh button for a screen's header: arrows at rest, the turning ৳ while busy.
struct LogoRefreshButton: View {
    let state: LogoRefreshState
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await state.refresh(action) }
        } label: {
            ZStack {
                if state.isRefreshing {
                    SpinningTakaMark(spins: true, size: 22)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.ink)
                }
            }
            .frame(width: 44, height: 44)
            .background(Circle().fill(Color.surface))
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(state.isRefreshing)
        .accessibilityLabel(state.isRefreshing ? Text("Refreshing") : Text("Refresh"))
    }
}

#Preview {
    VStack(spacing: 24) {
        SpinningTakaMark(spins: true, size: 40)
        SpinningTakaMark(progress: 0.4, spins: false, size: 40)
        LogoRefreshButton(state: LogoRefreshState()) { try? await Task.sleep(for: .seconds(2)) }
    }
    .padding()
    .background(Color.canvas)
}

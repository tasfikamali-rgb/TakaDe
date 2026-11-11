import SwiftUI

/// Plays on a cold launch and each time the app comes back from the background (TakaDeApp). It starts exactly like the static launch screen (the whole
/// taka sign on `launchBackground`, 96 pt, centred on the screen), cuts the sign in two with
/// a light tap, then fades away to the app. About 0.9 s; the app loads underneath meanwhile.
/// With Reduce Motion on, the cut is skipped and the screen just fades.
struct LaunchSplash: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var split: CGFloat = 0
    @State private var leaving = false

    /// Same size as the launch screen image (LaunchMark.imageset), so the hand-off doesn't jump.
    static let markSide: CGFloat = 96

    var body: some View {
        ZStack {
            Color("launchBackground")
            TakaMark(split: split)
                .foregroundStyle(Color("launchMark"))
                .frame(width: Self.markSide, height: Self.markSide)
                .scaleEffect(leaving && !reduceMotion ? 1.12 : 1)
        }
        .ignoresSafeArea()
        .opacity(leaving ? 0 : 1)
        .sensoryFeedback(.impact(weight: .light), trigger: split)
        .accessibilityHidden(true)
        // Never swallow a tap: the app underneath is already live.
        .allowsHitTesting(false)
        .task { await play() }
    }

    private func play() async {
        if reduceMotion {
            split = 1
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeInOut(duration: 0.25)) { leaving = true }
            try? await Task.sleep(for: .milliseconds(250))
        } else {
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) { split = 1 }
            try? await Task.sleep(for: .milliseconds(420))
            withAnimation(.easeOut(duration: 0.3)) { leaving = true }
            try? await Task.sleep(for: .milliseconds(300))
        }
        onFinished()
    }
}

#Preview {
    LaunchSplash {}
}

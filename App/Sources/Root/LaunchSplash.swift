import SwiftUI

/// The opening, on a cold launch and each time the app comes back from the background
/// (TakaDeApp). It starts exactly like the static launch screen (the whole taka sign on
/// `launchBackground`, 96 pt, centred on the screen), cuts the sign in two with a light
/// tap, then rises a little while the "takade" wordmark wipes in underneath it (Sabit,
/// 2026-11-11). After a short hold the whole thing fades to the app. About 1.5 s; the app
/// loads underneath meanwhile and taps go straight through. With Reduce Motion on, the cut,
/// rise and wipe are skipped and the lockup just fades in and out.
struct LaunchSplash: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var split: CGFloat = 0
    @State private var word: CGFloat = 0
    @State private var leaving = false

    /// Same size as the launch screen image (LaunchMark.imageset), so the hand-off doesn't jump.
    static let markSide: CGFloat = 96
    static let wordSize: CGFloat = 36
    static let gap: CGFloat = 12
    /// How far the mark rises so the finished lockup (mark over wordmark) sits centred.
    private static var rise: CGFloat { (gap + wordSize * 1.2) / 2 }

    var body: some View {
        ZStack {
            Color("launchBackground")
            TakaMark(split: split)
                .foregroundStyle(Color("launchMark"))
                .frame(width: Self.markSide, height: Self.markSide)
                .offset(y: -Self.rise * word)
            wordmark
                .offset(y: Self.markSide / 2 + Self.gap + Self.wordSize * 0.6 - Self.rise * word)
        }
        .scaleEffect(leaving && !reduceMotion ? 1.06 : 1)
        .ignoresSafeArea()
        .opacity(leaving ? 0 : 1)
        .sensoryFeedback(.impact(weight: .light), trigger: split)
        .accessibilityHidden(true)
        // Never swallow a tap: the app underneath is already live.
        .allowsHitTesting(false)
        .task { await play() }
    }

    /// The brand name stays in Latin letters in every language (docs/brand).
    private var wordmark: some View {
        Text(verbatim: "takade")
            .font(.custom("InterDisplay-SemiBold", fixedSize: Self.wordSize))
            .kerning(-0.5)
            .foregroundStyle(Color("launchMark"))
            .fixedSize()
            .opacity(reduceMotion ? word : min(1, word * 1.6))
            // Wipes in left to right, as if written.
            .mask {
                GeometryReader { proxy in
                    Rectangle().frame(width: proxy.size.width * (reduceMotion ? 1 : word))
                }
            }
            .offset(y: reduceMotion ? 0 : 6 * (1 - word))
    }

    private func play() async {
        if reduceMotion {
            split = 1
            withAnimation(.easeOut(duration: 0.25)) { word = 1 }
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.easeInOut(duration: 0.25)) { leaving = true }
            try? await Task.sleep(for: .milliseconds(250))
        } else {
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) { split = 1 }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeOut(duration: 0.45)) { word = 1 }
            try? await Task.sleep(for: .milliseconds(800))
            withAnimation(.easeOut(duration: 0.3)) { leaving = true }
            try? await Task.sleep(for: .milliseconds(300))
        }
        onFinished()
    }
}

#Preview {
    LaunchSplash {}
}

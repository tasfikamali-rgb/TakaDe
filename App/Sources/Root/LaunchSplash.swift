import SwiftUI

/// The opening, on a cold launch and each time the app comes back from the background
/// (TakaDeApp). It starts exactly like the static launch screen (the whole taka sign on
/// `launchBackground`, 96 pt, centred), cuts the sign in two with a light tap, then slides
/// it left while "akade" wipes in beside it, so it ends on the logo "৳akade" (Sabit,
/// 2026-11-11). After a short hold it fades to the app. About 1.7 s; the app loads
/// underneath meanwhile and taps go straight through. With Reduce Motion on, nothing moves:
/// the sign cross-fades to the logo, then the logo fades out.
struct LaunchSplash: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var split: CGFloat = 0
    /// 0 the sign alone in the centre, 1 the finished logo.
    @State private var slide: CGFloat = 0
    @State private var reveal: CGFloat = 0
    @State private var contentOpacity: Double = 1
    @State private var leaving = false

    /// Same size as the launch screen image (LaunchMark.imageset), so the hand-off doesn't jump.
    static let markSide: CGFloat = 96
    static let maxLogoWidth: CGFloat = 340

    var body: some View {
        GeometryReader { proxy in
            let width = min(Self.maxLogoWidth, proxy.size.width - 56)
            let side = interpolate(Self.markSide, TakaLockup.markSide * width)
            let wordWidth = TakaLockup.wordWidth * width
            ZStack {
                Color("launchBackground")
                TakaMark(split: split)
                    .foregroundStyle(Color("launchMark"))
                    .frame(width: side, height: side)
                    .offset(x: interpolate(0, TakaLockup.markCenter.x * width),
                            y: interpolate(0, TakaLockup.markCenter.y * width))
                TakaWordmarkShape()
                    .fill(Color("launchWord"))
                    .frame(width: wordWidth, height: wordWidth / TakaWordmarkShape.aspectRatio)
                    // Wipes in left to right, as if written.
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: wordWidth * reveal)
                    }
                    .offset(x: TakaLockup.wordCenter.x * width - 10 * (1 - slide),
                            y: TakaLockup.wordCenter.y * width)
            }
            .opacity(contentOpacity)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color("launchBackground"))
        .scaleEffect(leaving && !reduceMotion ? 1.05 : 1)
        .ignoresSafeArea()
        .opacity(leaving ? 0 : 1)
        .sensoryFeedback(.impact(weight: .light), trigger: split)
        .accessibilityHidden(true)
        // Never swallow a tap: the app underneath is already live.
        .allowsHitTesting(false)
        .task { await play() }
    }

    private func interpolate(_ from: CGFloat, _ to: CGFloat) -> CGFloat {
        from + (to - from) * slide
    }

    private func play() async {
        if reduceMotion {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeInOut(duration: 0.2)) { contentOpacity = 0 }
            try? await Task.sleep(for: .milliseconds(200))
            split = 1; slide = 1; reveal = 1
            withAnimation(.easeInOut(duration: 0.2)) { contentOpacity = 1 }
            try? await Task.sleep(for: .milliseconds(800))
            withAnimation(.easeInOut(duration: 0.25)) { leaving = true }
            try? await Task.sleep(for: .milliseconds(250))
        } else {
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) { split = 1 }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { slide = 1 }
            withAnimation(.easeOut(duration: 0.5).delay(0.12)) { reveal = 1 }
            try? await Task.sleep(for: .milliseconds(1_100))
            withAnimation(.easeOut(duration: 0.3)) { leaving = true }
            try? await Task.sleep(for: .milliseconds(300))
        }
        onFinished()
    }
}

#Preview {
    LaunchSplash {}
}

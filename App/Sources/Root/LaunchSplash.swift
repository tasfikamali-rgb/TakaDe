import SwiftUI

/// The opening, on a cold launch and each time the app comes back from the background
/// (TakaDeApp). It starts exactly like the static launch screen (the whole taka sign on
/// `launchBackground`, 64 pt, centred), cuts the sign in two with a light tap, then the
/// halves settle into a compact logo "৳akaDe" while the word comes into focus beside it.
/// After a short hold the logo lifts and blurs away into the app. About 1.1 s, and the
/// logo is at most 176 pt wide, so it no longer fills the screen (Sabit, 2026-11-14). On a
/// cold launch a short sound plays with it (OpeningSound). The app loads underneath and
/// taps go straight through. With Reduce Motion on, nothing moves: the sign cross-fades to
/// the logo, then the logo fades out.
struct LaunchSplash: View {
    /// True on a cold launch: the only time the opening sound plays.
    var playsSound = false
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var split: CGFloat = 0
    /// 0 the sign alone in the centre, 1 the finished logo.
    @State private var slide: CGFloat = 0
    /// 0 the word hidden and soft, 1 fully written and sharp.
    @State private var reveal: CGFloat = 0
    @State private var contentOpacity: Double = 1
    @State private var leaving = false

    /// Same size as the launch screen image (LaunchMark.imageset), so the hand-off doesn't jump.
    static let markSide: CGFloat = 64
    static let maxLogoWidth: CGFloat = 176

    var body: some View {
        GeometryReader { proxy in
            let width = min(Self.maxLogoWidth, proxy.size.width - 56)
            let side = interpolate(Self.markSide, TakaLockup.markSide * width)
            let wordWidth = TakaLockup.wordWidth * width
            ZStack {
                TakaMark(split: split)
                    .foregroundStyle(Color("launchMark"))
                    .frame(width: side, height: side)
                    .offset(x: interpolate(0, TakaLockup.markCenter.x * width),
                            y: interpolate(0, TakaLockup.markCenter.y * width))
                TakaWordmarkShape()
                    .fill(Color("launchWord"))
                    .frame(width: wordWidth, height: wordWidth / TakaWordmarkShape.aspectRatio)
                    // Written left to right behind a soft edge, coming into focus as it goes.
                    .mask(alignment: .leading) {
                        LinearGradient(stops: [.init(color: .black, location: 0.8),
                                               .init(color: .clear, location: 1)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: wordWidth * 1.25 * reveal)
                    }
                    .blur(radius: 5 * (1 - reveal))
                    .opacity(Double(reveal))
                    .offset(x: TakaLockup.wordCenter.x * width - 8 * (1 - reveal),
                            y: TakaLockup.wordCenter.y * width)
            }
            .opacity(contentOpacity)
            .blur(radius: leaving && !reduceMotion ? 6 : 0)
            .scaleEffect(leaving && !reduceMotion ? 0.94 : 1)
            .offset(y: leaving && !reduceMotion ? -6 : 0)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color("launchBackground"))
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
        if playsSound { OpeningSound.prepare() }
        defer { if playsSound { OpeningSound.release() } }
        if reduceMotion {
            try? await Task.sleep(for: .milliseconds(100))
            if playsSound { OpeningSound.play() }
            withAnimation(.easeInOut(duration: 0.2)) { contentOpacity = 0 }
            try? await Task.sleep(for: .milliseconds(200))
            split = 1; slide = 1; reveal = 1
            withAnimation(.easeInOut(duration: 0.2)) { contentOpacity = 1 }
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeInOut(duration: 0.25)) { leaving = true }
            try? await Task.sleep(for: .milliseconds(250))
        } else {
            try? await Task.sleep(for: .milliseconds(100))
            // The sound's tap lands on the split; its two notes land as the word appears.
            if playsSound { OpeningSound.play() }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) { split = 1 }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) { slide = 1 }
            withAnimation(.easeOut(duration: 0.38).delay(0.04)) { reveal = 1 }
            try? await Task.sleep(for: .milliseconds(620))
            withAnimation(.easeIn(duration: 0.22)) { leaving = true }
            try? await Task.sleep(for: .milliseconds(240))
        }
        onFinished()
    }
}

#Preview {
    LaunchSplash {}
}

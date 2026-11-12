import SwiftUI

/// The top layer of onboarding: the app name, what this step is for, and progress.
struct OnboardingHeader: View {
    let step: OnboardingView.Step
    let mode: OnboardingView.Mode

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.xxs) {
                ForEach(0..<3) { index in
                    Capsule()
                        .fill(index <= progress ? Color.lime : Color.onHeader.opacity(0.18))
                        .frame(width: index == progress ? 24 : 8, height: 8)
                }
            }
            // Decorative: the step is read with the title instead, so there's no tiny
            // element for VoiceOver to land on.
            .accessibilityHidden(true)
            Text(verbatim: "TakaDe")
                .font(AppFont.label)
                .foregroundStyle(Color.onHeader.opacity(0.72))
                .padding(.top, Spacing.m)
            Text(title)
                .font(AppFont.title)
                .tracking(-0.005 * 28)
                .foregroundStyle(Color.onHeader)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityValue(Text("Step \(progress + 1) of 3"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.xl)
        .padding(.bottom, Spacing.xl)
        .readableWidth()
    }

    /// Language, then the welcome choice, then the details (name or sign-in method).
    private var progress: Int {
        switch step {
        case .language: 0
        case .welcome: 1
        case .name, .method: 2
        }
    }

    private var title: LocalizedStringKey {
        switch (step, mode) {
        case (.language, _): "Choose your language"
        case (.welcome, _): "Split bills with friends & family, settle up in taka"
        case (.name, _): "What should your friends call you?"
        case (.method, .signIn): "Sign in to your account"
        case (.method, _): "How do you want to sign in?"
        }
    }
}

import SwiftUI

/// The top layer of onboarding: the app name, what this step is for, and progress.
struct OnboardingHeader: View {
    let step: OnboardingView.Step
    let mode: OnboardingView.Mode

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.xxs) {
                ForEach(0..<Self.stepCount) { index in
                    Capsule()
                        .fill(index <= progress ? Color.lime : Color.onHeader.opacity(0.18))
                        .frame(width: index == progress ? 24 : 8, height: 8)
                }
            }
            // Decorative: the step is read with the title instead, so there's no tiny
            // element for VoiceOver to land on.
            .accessibilityHidden(true)
            TakaLogo(width: 104, mark: Color.onHeader, word: Color.onHeader)
                .padding(.top, Spacing.m)
            Text(title)
                .font(AppFont.title)
                .tracking(-0.005 * 28)
                .foregroundStyle(Color.onHeader)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityValue(Text("Step \(progress + 1) of \(Self.stepCount)"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.xl)
        .padding(.bottom, Spacing.xl)
        .readableWidth()
    }

    static let stepCount = 4

    /// Where you're from, language, the account choice, then the details (name or
    /// sign-in method). The welcome screen comes before and has no header.
    private var progress: Int {
        switch step {
        case .welcome, .region: 0
        case .language: 1
        case .account: 2
        case .name, .method: 3
        }
    }

    private var title: LocalizedStringKey {
        switch (step, mode) {
        case (.welcome, _), (.region, _): "Where are you from?"
        case (.language, _): "Choose your language"
        case (.account, _): "Set up your account"
        case (.name, _): "What should your friends call you?"
        case (.method, .signIn): "Sign in to your account"
        case (.method, _): "How do you want to sign in?"
        }
    }
}

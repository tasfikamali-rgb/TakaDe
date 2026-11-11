import SwiftUI

/// The top layer of onboarding: the app name, what this step is for, and progress.
struct OnboardingHeader: View {
    let step: OnboardingView.Step

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.xxs) {
                ForEach(0..<3) { index in
                    Capsule()
                        .fill(index <= step.rawValue ? Color.lime : Color.onHeader.opacity(0.18))
                        .frame(width: index == step.rawValue ? 24 : 8, height: 8)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Step \(step.rawValue + 1) of 3"))
            Text(verbatim: "TakaDe")
                .font(AppFont.label)
                .foregroundStyle(Color.onHeader.opacity(0.72))
                .padding(.top, Spacing.m)
            Text(title)
                .font(AppFont.title)
                .tracking(-0.005 * 28)
                .foregroundStyle(Color.onHeader)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.xl)
        .padding(.bottom, Spacing.xl)
        .readableWidth()
    }

    private var title: LocalizedStringKey {
        switch step {
        case .language: "Choose your language"
        case .signIn: "Sign in, or skip it"
        case .name: "What should your friends call you?"
        }
    }
}

import SwiftUI
import TakaDeCore

/// First launch: language, then an optional Apple or Google sign-in, then your name.
/// Nothing here creates a server account; it all stays on this phone.
struct OnboardingView: View {
    enum Step: Int { case language, signIn, name }

    @Environment(AccountModel.self) private var account
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    // Survives the rebuild that a language change triggers.
    @AppStorage("onboardingStep") private var stepRaw = Step.language.rawValue
    @AppStorage(AccountModel.nameKey) private var savedName = ""
    @State private var name = ""
    @State private var linked: LinkedAccount?
    @State private var errorMessage: String?
    @State private var saving = false

    private var step: Step { Step(rawValue: stepRaw) ?? .language }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingHeader(step: step)
            VStack(alignment: .leading, spacing: Spacing.l) {
                SheetGrabber()
                switch step {
                case .language: languageStep
                case .signIn: signInStep
                case .name: nameStep
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .readableWidth()
            .background(
                UnevenRoundedRectangle(topLeadingRadius: Radius.sheet, topTrailingRadius: Radius.sheet, style: .continuous)
                    .fill(Color.canvas)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .background(Color.header.ignoresSafeArea())
        .animation(Motion.standard, value: stepRaw)
        .onAppear {
            if name.isEmpty { name = savedName }
            preselectPhoneLanguage()
        }
    }

    /// Starts on the phone's own language, so most people just tap Continue.
    private func preselectPhoneLanguage() {
        guard language == .system, step == .language else { return }
        let phoneUsesBengali = Locale.preferredLanguages.first?.hasPrefix("bn") == true
        language = phoneUsesBengali ? .bengali : .english
    }

    // MARK: Steps

    private var languageStep: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            ForEach([AppLanguage.bengali, .english]) { option in
                Button { language = option } label: {
                    HStack {
                        Text(verbatim: option.nativeName).font(AppFont.headline)
                        Spacer()
                        Image(systemName: language == option ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Color.ink)
                    .padding(Spacing.m)
                    .frame(minHeight: 60)
                    .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.surface))
                    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .stroke(Color.ink, lineWidth: language == option ? 2 : 0))
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityAddTraits(language == option ? .isSelected : [])
            }
            Text("You can change this any time in Profile")
                .font(AppFont.caption)
                .foregroundStyle(Color.inkMuted)
            Spacer(minLength: Spacing.l)
            Button("Continue") { go(to: .signIn) }
                .buttonStyle(PillButtonStyle())
        }
    }

    private var signInStep: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Signing in keeps your name and email with your groups. It all stays on this phone: TakaDe has no server and can't see your groups.")
                .font(AppFont.body)
                .foregroundStyle(Color.inkMuted)
            SignInOptions { account, providedName in
                linked = account
                if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let providedName { name = providedName }
                go(to: .name)
            }
            Button("Continue without account") { go(to: .name) }
                .font(AppFont.bodyEmphasis)
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, minHeight: 48)
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            TextField("Your name", text: $name)
                .font(AppFont.headline)
                .textContentType(.name)
                .submitLabel(.done)
                .onSubmit(finish)
                .padding(Spacing.m)
                .frame(minHeight: 56)
                .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.surface))
            Text("This is how you appear in groups, exactly as you type it")
                .font(AppFont.caption)
                .foregroundStyle(Color.inkMuted)
            if let linked {
                Label(linked.provider == .apple ? LocalizedStringKey("Signed in with Apple") : LocalizedStringKey("Signed in with Google"), systemImage: "checkmark.seal")
                    .font(AppFont.label)
                    .foregroundStyle(Color.owed)
            }
            if let errorMessage {
                Text(verbatim: errorMessage).font(AppFont.caption).foregroundStyle(Color.owe)
            }
            Spacer(minLength: Spacing.l)
            Button("Start splitting", action: finish)
                .buttonStyle(PillButtonStyle())
                .disabled(trimmedName.isEmpty || saving)
            Button("Back") { go(to: .signIn) }
                .font(AppFont.label)
                .foregroundStyle(Color.inkMuted)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    // MARK: Actions

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func go(to next: Step) { stepRaw = next.rawValue }

    private func finish() {
        guard !trimmedName.isEmpty, !saving else { return }
        saving = true
        Task {
            do {
                try await account.completeOnboarding(name: trimmedName, account: linked)
                stepRaw = Step.language.rawValue
            } catch {
                errorMessage = String(localized: "Your profile wasn't saved. Try again.", bundle: .appLanguage)
            }
            saving = false
        }
    }
}

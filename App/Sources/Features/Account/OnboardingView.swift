import SwiftUI
import TakaDeCore

/// First launch (Sabit, 2026-11-11, order changed 2026-11-12): a welcome screen with the
/// logo, where you're from, language, then Continue with Apple, Continue with Google or
/// Continue without account, and only then your name (and photo). Apple's name, when it
/// sends one, fills the name in; it stays on this phone. Groups and expenses always stay on
/// this phone.
struct OnboardingView: View {
    /// `method` is no longer shown; it's kept so a step saved by an older version maps back.
    enum Step: Int { case welcome, region, language, account, name, method }
    enum Mode: String { case create, signIn, guest }

    @Environment(AccountModel.self) private var account
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    // Survive the rebuild that a language change triggers.
    @AppStorage("onboardingStep") private var stepRaw = Step.welcome.rawValue
    @AppStorage(HomeRegion.storageKey) private var region = HomeRegion.suggested
    @State private var regionQuery = ""
    @Environment(\.locale) private var locale
    @AppStorage("onboardingMode") private var modeRaw = Mode.guest.rawValue
    @AppStorage(AccountModel.nameKey) private var savedName = ""
    @State private var name = ""
    /// A sign-in happened, so the name step finishes instead of asking for a method.
    @State private var signedIn = false
    /// Shown above the name when the person picked the other door, e.g. Sign in with a
    /// sign-in that had no account yet.
    @State private var notice: LocalizedStringKey?
    @State private var errorMessage: String?
    @State private var saving = false

    private var step: Step { Step(rawValue: stepRaw) ?? .welcome }
    private var mode: Mode { Mode(rawValue: modeRaw) ?? .guest }

    var body: some View {
        Group {
            if step == .welcome { welcomeScreen } else { stepScreen }
        }
        .animation(Motion.standard, value: stepRaw)
        .googlePhotoOffer(when: account.needsOnboarding)
        .onAppear {
            if name.isEmpty { name = savedName }
            // A sign-in isn't kept across launches until the profile exists, so start over.
            if step == .method || step == .name && mode != .guest { stepRaw = Step.account.rawValue }
        }
    }

    /// The first thing anyone sees: the logo on the brand colour, and one way forward.
    private var welcomeScreen: some View {
        GeometryReader { proxy in
            VStack(spacing: Spacing.l) {
                Spacer()
                TakaLogo(width: min(300, proxy.size.width - Spacing.screenMargin * 2))
                Text("Split bills with friends & family. Settle up in taka.")
                    .font(AppFont.title)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color("launchWord"))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Get started") { go(to: .region) }
                    .buttonStyle(PillButtonStyle(fill: Color("launchWord"), text: Color("launchBackground")))
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.bottom, Spacing.l)
            .frame(maxWidth: .infinity)
            .readableWidth()
        }
        .background(Color("launchBackground").ignoresSafeArea())
    }

    private var stepScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingHeader(step: step, mode: mode)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    SheetGrabber()
                    switch step {
                    case .welcome, .region: regionStep
                    case .language: languageStep
                    case .account: accountStep
                    case .name: nameStep
                    case .method: accountStep
                    }
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.top, Spacing.s)
                .padding(.bottom, Spacing.m)
                .frame(maxWidth: .infinity, alignment: .top)
                .readableWidth()
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(
                TexturedBackground()
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: Radius.sheet, topTrailingRadius: Radius.sheet, style: .continuous))
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .background(TexturedBackground(base: .header).ignoresSafeArea())
    }

    /// Suggests Bangla for Bangladesh, otherwise the phone's own language, so most people
    /// just tap Continue. Only while the language still follows the phone.
    private func suggestLanguage() {
        guard language == .system else { return }
        let phoneUsesBengali = Locale.preferredLanguages.first?.hasPrefix("bn") == true
        language = region == "BD" || phoneUsesBengali ? .bengali : .english
    }

    // MARK: Steps

    /// The chosen country sits at the top with Continue, so Continue never scrolls away;
    /// every UN member is listed below with a search box. Tapping one moves it to the top.
    private var regionStep: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            regionRow(region, selected: true)
            Text("This suggests your language. It stays on this phone.")
                .font(AppFont.caption)
                .foregroundStyle(Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button("Continue") {
                suggestLanguage()
                go(to: .language)
            }
            .buttonStyle(PillButtonStyle())
            .padding(.top, Spacing.xs)
            HStack(spacing: Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.inkMuted)
                    .accessibilityHidden(true)
                TextField("Search countries", text: $regionQuery,
                          prompt: Text("Search countries").foregroundStyle(Color.inkMuted))
                    .font(AppFont.body)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
            }
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.surface))
            .padding(.top, Spacing.m)
            LazyVStack(spacing: Spacing.xs) {
                ForEach(regionList, id: \.self) { code in
                    regionRow(code, selected: false)
                }
            }
            if regionList.isEmpty {
                Text("No country matches that")
                    .font(AppFont.body)
                    .foregroundStyle(Color.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            Button("Back") { go(to: .welcome) }
                .font(AppFont.label)
                .foregroundStyle(Color.inkMuted)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private var regionList: [String] {
        HomeRegion.ordered(in: locale).filter { $0 != region && HomeRegion.matches($0, query: regionQuery, in: locale) }
    }

    private func regionRow(_ code: String, selected: Bool) -> some View {
        Button {
            region = code
            regionQuery = ""
        } label: {
            HStack(spacing: Spacing.s) {
                Text(verbatim: HomeRegion.flag(code))
                    .font(.title2)
                    .accessibilityHidden(true)
                regionName(code)
                    .font(selected ? AppFont.headline : AppFont.bodyEmphasis)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.xs)
            .frame(minHeight: selected ? 60 : 52)
            // One element named by the country, so the flag emoji isn't read or audited
            // as separate text.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(regionName(code))
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.surface))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.ink, lineWidth: selected ? 2 : 0))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func regionName(_ code: String) -> Text {
        if code == HomeRegion.elsewhere { return Text("Somewhere else") }
        return Text(verbatim: HomeRegion.name(code, in: locale))
    }

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
            Text("You can change this any time in Settings")
                .font(AppFont.caption)
                .foregroundStyle(Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.l)
            Button("Continue") { go(to: .account) }
                .buttonStyle(PillButtonStyle())
            Button("Back") { go(to: .region) }
                .font(AppFont.label)
                .foregroundStyle(Color.inkMuted)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private var accountStep: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(account.usesAccountService
                 ? LocalizedStringKey("Sign in to use TakaDe on a new phone later. New here or coming back, it's the same button. Your groups and expenses stay on this phone either way.")
                 : LocalizedStringKey("Signing in keeps your email with your groups. It all stays on this phone."))
                .font(AppFont.body)
                .foregroundStyle(Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            // Creates the account if there isn't one yet, or signs in to it.
            SignInMethods(mode: .create, name: nil, onFinished: handleSignIn)
            // A quiet text button, not a third big pill, so Apple and Google stay the
            // main choices (Sabit, 2026-11-12). Still 44 pt tall to tap.
            Button { start(.guest) } label: {
                Text("Continue without account")
                    .font(AppFont.label)
                    .underline()
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleButtonStyle())
            Text("You can sign in later from Account.")
                .font(AppFont.caption)
                .foregroundStyle(Color.inkMuted)
            Button("Back") { go(to: .language) }
                .font(AppFont.label)
                .foregroundStyle(Color.inkMuted)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let notice {
                Label(notice, systemImage: "info.circle")
                    .font(AppFont.label)
                    .foregroundStyle(Color.ink)
                    .padding(Spacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.lilac))
            }
            ProfilePhotoPicker(name: name, size: 104)
                .frame(maxWidth: .infinity)
                .padding(.bottom, Spacing.xs)
            Text("Add a photo so friends spot you quickly. It stays on this phone.")
                .font(AppFont.caption)
                .foregroundStyle(Color.inkMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Spacing.s)
            TextField("Your name", text: $name, prompt: Text("Your name").foregroundStyle(Color.inkMuted))
                .font(AppFont.headline)
                .textContentType(.name)
                .submitLabel(.done)
                .onSubmit(nameDone)
                .padding(Spacing.m)
                .frame(minHeight: 56)
                .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.surface))
            NameRuleText(name)
                .font(AppFont.caption)
            Text("This is how you appear in groups, exactly as you type it. You can't change it later, so use your real name.")
                .font(AppFont.caption)
                .foregroundStyle(Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            if let errorMessage {
                Text(verbatim: errorMessage).font(AppFont.caption).foregroundStyle(Color.owe)
            }
            Spacer(minLength: Spacing.l)
            Button("Start splitting", action: nameDone)
                .buttonStyle(PillButtonStyle())
                .disabled(!PersonName.isValid(trimmedName) || saving)
            Button("Back", action: backToWelcome)
                .font(AppFont.label)
                .foregroundStyle(Color.inkMuted)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    // MARK: Actions

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func go(to next: Step) { stepRaw = next.rawValue }

    /// Without an account: straight to the name.
    private func start(_ mode: Mode) {
        modeRaw = mode.rawValue
        notice = nil
        signedIn = false
        go(to: .name)
    }

    private func nameDone() {
        guard PersonName.isValid(trimmedName) else { return }
        finish()
    }

    private func backToWelcome() {
        if signedIn {
            Task { await account.discardPendingSignIn() }
            signedIn = false
        }
        notice = nil
        go(to: .account)
    }

    /// After Apple or Google, new account or not, the name comes next. Apple's name, sent
    /// only the first time someone uses Apple with TakaDe, fills it in; names never come from
    /// or go to the server, so someone coming back types theirs again.
    private func handleSignIn(_ outcome: AccountModel.SignInOutcome) {
        modeRaw = outcome.isNew ? Mode.create.rawValue : Mode.signIn.rawValue
        signedIn = true
        if let given = outcome.name?.trimmingCharacters(in: .whitespacesAndNewlines), !given.isEmpty, trimmedName.isEmpty {
            name = given
        }
        if !outcome.isNew && account.usesAccountService {
            notice = "Welcome back. Your name lives on your phone, so add it here."
        } else {
            notice = nil
        }
        go(to: .name)
        account.offerGooglePhotoIfNeeded()
    }

    private func finish() {
        guard PersonName.isValid(trimmedName), !saving else { return }
        saving = true
        Task {
            do {
                try await account.completeOnboarding(name: trimmedName)
                stepRaw = Step.welcome.rawValue
                modeRaw = Mode.guest.rawValue
            } catch {
                errorMessage = String(localized: "Your profile wasn't saved. Try again.", bundle: .appLanguage)
            }
            saving = false
        }
    }
}

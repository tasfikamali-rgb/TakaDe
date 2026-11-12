import SwiftUI
import TakaDeCore

/// First launch (Sabit, 2026-11-11): a welcome screen with the logo, where you're from,
/// language, then Create an account, Sign in, or Continue without account, then a name
/// (and photo) and a sign-in method as needed. Groups and expenses always stay on this phone.
struct OnboardingView: View {
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
        .onAppear {
            if name.isEmpty { name = savedName }
            // A sign-in isn't kept across launches until the profile exists, so start over.
            if step == .method || step == .name && mode == .signIn { stepRaw = Step.account.rawValue }
        }
    }

    /// The first thing anyone sees: the logo on the brand colour, and one way forward.
    private var welcomeScreen: some View {
        GeometryReader { proxy in
            VStack(spacing: Spacing.l) {
                Spacer()
                TakaLogo(width: min(300, proxy.size.width - Spacing.screenMargin * 2))
                Text("Split bills with friends. Settle up in taka.")
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
                    case .method: methodStep
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
                UnevenRoundedRectangle(topLeadingRadius: Radius.sheet, topTrailingRadius: Radius.sheet, style: .continuous)
                    .fill(Color.canvas)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .background(Color.header.ignoresSafeArea())
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
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(account.usesAccountService
                 ? LocalizedStringKey("An account lets you sign in on a new phone. Your groups and expenses stay on this phone either way.")
                 : LocalizedStringKey("Signing in keeps your name and email with your groups. It all stays on this phone."))
                .font(AppFont.body)
                .foregroundStyle(Color.inkMuted)
                .padding(.bottom, Spacing.s)
            Button("Create an account") { start(.create, at: .name) }
                .buttonStyle(PillButtonStyle())
            Button { start(.signIn, at: .method) } label: {
                Text("Sign in")
                    .font(AppFont.bodyEmphasis)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(Color.ink)
                    .background(Capsule().fill(Color.surface))
                    .overlay(Capsule().stroke(Color.ink.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(PressScaleButtonStyle())
            Button("Continue without account") { start(.guest, at: .name) }
                .font(AppFont.bodyEmphasis)
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, minHeight: 48)
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
                .submitLabel(asksForMethod ? .next : .done)
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
            Button(asksForMethod ? LocalizedStringKey("Continue") : LocalizedStringKey("Start splitting"), action: nameDone)
                .buttonStyle(PillButtonStyle())
                .disabled(!PersonName.isValid(trimmedName) || saving)
            Button("Back", action: backToWelcome)
                .font(AppFont.label)
                .foregroundStyle(Color.inkMuted)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private var methodStep: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SignInMethods(mode: mode == .signIn ? .signIn : .create, name: mode == .create ? trimmedName : nil, onFinished: handleSignIn)
            if mode == .signIn {
                Text("New to TakaDe? Go back and choose Create an account.")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.inkMuted)
            }
            Button("Back") { go(to: mode == .create ? .name : .account) }
                .font(AppFont.label)
                .foregroundStyle(Color.inkMuted)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    // MARK: Actions

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var asksForMethod: Bool { mode == .create && !signedIn }

    private func go(to next: Step) { stepRaw = next.rawValue }

    private func start(_ mode: Mode, at step: Step) {
        modeRaw = mode.rawValue
        notice = nil
        signedIn = false
        go(to: step)
    }

    private func nameDone() {
        guard PersonName.isValid(trimmedName) else { return }
        if asksForMethod { go(to: .method) } else { finish() }
    }

    private func backToWelcome() {
        if signedIn {
            Task { await account.discardPendingSignIn() }
            signedIn = false
        }
        notice = nil
        go(to: .account)
    }

    /// Picking the other door is fine: a sign-in that made a new account becomes Create,
    /// and Create with an existing account just signs in.
    private func handleSignIn(_ outcome: AccountModel.SignInOutcome) {
        signedIn = true
        let serverName = outcome.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .signIn where outcome.isNew && account.usesAccountService:
            notice = "We didn't find an account for that sign-in, so we made a new one. What should we call you?"
            if trimmedName.isEmpty, let serverName { name = serverName }
            go(to: .name)
        case .create where !outcome.isNew && account.usesAccountService:
            notice = "You already had a TakaDe account, so we signed you in."
            if let serverName, !serverName.isEmpty { name = serverName }
            go(to: .name)
        case .signIn:
            if let serverName, !serverName.isEmpty {
                name = serverName
                finish()
            } else {
                notice = nil
                go(to: .name)
            }
        case .create, .guest:
            finish()
        }
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

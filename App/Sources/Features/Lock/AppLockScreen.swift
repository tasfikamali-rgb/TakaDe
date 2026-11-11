import SwiftUI

/// What shows over TakaDe when it's locked or in the app switcher: the name and, when
/// locked, an Unlock button. No balances, names or amounts.
struct AppLockScreen: View {
    let lock: AppLock
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system

    var body: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Color.ink)
                .frame(width: 72, height: 72)
                .background(Circle().fill(Color.surface))
                .accessibilityHidden(true)
            Text(verbatim: "TakaDe")
                .font(AppFont.title)
                .foregroundStyle(Color.ink)
            Spacer()
            if lock.isLocked {
                Button("Unlock") { Task { await lock.unlock() } }
                    .buttonStyle(PillButtonStyle())
                    .disabled(lock.isAuthenticating)
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.bottom, Spacing.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.lilac.ignoresSafeArea())
        .environment(\.locale, language.locale ?? .autoupdatingCurrent)
        .accessibilityAddTraits(.isModal)
    }
}

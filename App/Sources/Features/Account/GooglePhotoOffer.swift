import AuthenticationServices
import SwiftUI

/// "Use your Google photo?" after signing in with Google (Sabit, 2026-11-12). Yes opens
/// Google's own sheet, which asks once for permission to share the profile photo; the photo
/// is then saved on this phone like a picked one and sent, sealed, to friends. The sign-in
/// itself never asks Google for the profile, so TakaDe's account server gets no name or photo.
private struct GooglePhotoOffer: ViewModifier {
    @Environment(AccountModel.self) private var account
    /// Only one place in the app shows the question at a time: onboarding while it's up,
    /// the tabs otherwise.
    let isActive: Bool

    @State private var fetching = false
    @State private var failed = false

    func body(content: Content) -> some View {
        content
            .alert(Text("Use your Google photo?"),
                   isPresented: Binding(get: { isActive && account.offersGooglePhoto && !fetching },
                                        set: { if !$0 { account.answeredGooglePhotoOffer() } })) {
                Button("Use Google photo", action: useGooglePhoto)
                Button("Not now", role: .cancel) {}
            } message: {
                Text("Google will ask you to share your profile photo. It's saved on this phone and shown to friends you add on TakaDe, never kept on our servers.")
            }
            .alert(Text("Your Google photo couldn't be added. Tap your photo in Account to try again."), isPresented: $failed) {}
            .overlay {
                if fetching {
                    ProgressView()
                        .padding(Spacing.l)
                        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.surface))
                }
            }
    }

    private func useGooglePhoto() {
        fetching = true
        Task {
            defer { fetching = false }
            // Let the question finish closing before Google's sheet slides up.
            try? await Task.sleep(for: .milliseconds(450))
            do {
                try await account.useGooglePhoto()
            } catch is CancellationError {
                // Closed Google's sheet.
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            } catch {
                failed = true
            }
        }
    }
}

extension View {
    func googlePhotoOffer(when isActive: Bool) -> some View {
        modifier(GooglePhotoOffer(isActive: isActive))
    }
}

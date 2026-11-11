import LocalAuthentication
import Observation
import SwiftUI
import UIKit

/// Optional Face ID, Touch ID or passcode lock (Settings > Lock). Off by default.
///
/// When it's on, the ledger is covered whenever TakaDe isn't in front, so the app
/// switcher shows the cover instead of balances, and it locks once TakaDe goes to the
/// background. The cover lives in its own window above everything, so open sheets are
/// covered too. TakaDe never sees or stores the passcode or face data: iOS checks them.
@Observable @MainActor
final class AppLock {
    static let enabledKey = "appLockEnabled"

    private(set) var isEnabled: Bool
    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    @ObservationIgnored private var promptsWhenActive: Bool
    @ObservationIgnored private var cover: UIWindow?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let enabled = defaults.bool(forKey: Self.enabledKey)
        isEnabled = enabled
        isLocked = enabled
        promptsWhenActive = enabled
    }

    /// False when the phone has no passcode, so the lock can't be turned on.
    var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    var method: Method {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .passcode
        }
    }

    enum Method { case faceID, touchID, opticID, passcode }

    /// Turning the lock on asks for Face ID or the passcode first, so nobody locks
    /// themselves out with a check that doesn't work.
    func setEnabled(_ enabled: Bool) async {
        if enabled {
            guard await authenticate() else { return }
        }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        if !enabled { isLocked = false }
    }

    func scenePhaseChanged(to phase: ScenePhase) {
        guard isEnabled else {
            hideCover()
            return
        }
        switch phase {
        case .background:
            isLocked = true
            promptsWhenActive = true
            showCover()
        case .inactive:
            // The app switcher snapshot is taken here.
            showCover()
        case .active:
            if isLocked {
                showCover()
                if promptsWhenActive, !isAuthenticating {
                    promptsWhenActive = false
                    Task { await unlock() }
                }
            } else {
                hideCover()
            }
        @unknown default:
            showCover()
        }
    }

    func unlock() async {
        guard isLocked else { return }
        if await authenticate() {
            isLocked = false
            hideCover()
        }
    }

    private func authenticate() async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        let reason = String(localized: "Unlock TakaDe to see your groups", bundle: .appLanguage)
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    // MARK: Cover window

    private func showCover() {
        if let cover {
            cover.makeKeyAndVisible()
            return
        }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState != .unattached })
        else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = AppAppearance.stored.interfaceStyle
        let host = UIHostingController(rootView: AppLockScreen(lock: self))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        // Key, so VoiceOver and the keyboard go to the cover, not the ledger under it.
        window.makeKeyAndVisible()
        cover = window
    }

    private func hideCover() {
        guard let cover else { return }
        cover.isHidden = true
        cover.windowScene?.windows.first { $0 !== cover && !$0.isHidden }?.makeKey()
        self.cover = nil
    }
}

import AuthenticationServices
import Foundation
import LocalAuthentication
import TakaDeCore
import UIKit

/// The website passkeys belong to (docs/adr/0035-passkeys.md). iOS only makes a passkey for
/// a domain whose `apple-app-site-association` file lists this app under `webcredentials`,
/// and the app needs the matching Associated Domains entitlement, which a free Apple ID
/// team can't sign. So passkeys stay hidden until `TAKADE_PASSKEY_DOMAIN` is set
/// (Config/TakaDe.xcconfig), once the domain, that file, a paid team and Supabase's passkey
/// settings are all in place.
enum PasskeyConfig {
    static var domain: String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "TakaDePasskeyDomain") as? String)?
            .trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        // A bare host name only, e.g. takadeapp.com.
        guard !value.isEmpty, !value.contains("/"), !value.contains(":"), value.contains(".") else { return nil }
        return value
    }

    static var isEnabled: Bool { domain != nil }

    /// "Face ID", "Touch ID" or "Optic ID" for this device, for the words around passkeys.
    static var unlockName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Face ID"
        }
    }
}

/// Runs iOS's passkey sheet: make a passkey for the account, or sign in with one. Only the
/// public key and a signature leave the phone; the private key stays in iCloud Keychain.
@MainActor
final class PasskeyCeremony: NSObject {
    enum Failure: Error {
        /// The service's options name a different website than this build, so iOS would
        /// refuse, or the service would reject what iOS signs.
        case wrongDomain
        /// iOS returned something other than a passkey.
        case unexpectedCredential
    }

    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    private var controller: ASAuthorizationController?

    func register(_ options: PasskeyWire.CreationOptions, domain: String) async throws -> [String: Any] {
        guard options.relyingPartyID.lowercased() == domain else { throw Failure.wrongDomain }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: domain)
        let request = provider.createCredentialRegistrationRequest(
            challenge: options.challenge, name: options.userName.isEmpty ? "TakaDe" : options.userName, userID: options.userID)
        if #available(iOS 17.4, *) {
            request.excludedCredentials = options.excludedCredentialIDs.map {
                ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
            }
        }
        let authorization = try await perform(request)
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
              let attestation = credential.rawAttestationObject else { throw Failure.unexpectedCredential }
        return PasskeyWire.registrationCredential(
            credentialID: credential.credentialID, clientDataJSON: credential.rawClientDataJSON,
            attestationObject: attestation, attachment: Self.attachment(credential.attachment))
    }

    func signIn(_ options: PasskeyWire.RequestOptions, domain: String) async throws -> [String: Any] {
        if let rpID = options.relyingPartyID, rpID.lowercased() != domain { throw Failure.wrongDomain }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: domain)
        let request = provider.createCredentialAssertionRequest(challenge: options.challenge)
        request.allowedCredentials = options.allowedCredentialIDs.map {
            ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
        }
        let authorization = try await perform(request)
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            throw Failure.unexpectedCredential
        }
        return PasskeyWire.assertionCredential(
            credentialID: credential.credentialID, clientDataJSON: credential.rawClientDataJSON,
            authenticatorData: credential.rawAuthenticatorData, signature: credential.signature,
            userHandle: credential.userID, attachment: Self.attachment(credential.attachment))
    }

    private static func attachment(_ value: ASAuthorizationPublicKeyCredentialAttachment) -> String {
        value == .crossPlatform ? "cross-platform" : "platform"
    }

    private func perform(_ request: ASAuthorizationRequest) async throws -> ASAuthorization {
        // One sheet at a time: a second tap while the first is open is ignored.
        guard continuation == nil else { throw CancellationError() }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<ASAuthorization, Error>) {
        let continuation = continuation
        self.continuation = nil
        controller = nil
        switch result {
        case .success(let authorization):
            continuation?.resume(returning: authorization)
        case .failure(let error as ASAuthorizationError) where error.code == .canceled:
            // Closed the sheet, or iOS had no passkey to offer and the person dismissed it.
            continuation?.resume(throwing: CancellationError())
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }
}

extension PasskeyCeremony: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        MainActor.assumeIsolated { finish(.success(authorization)) }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated { finish(.failure(error)) }
    }
}

extension PasskeyCeremony: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}

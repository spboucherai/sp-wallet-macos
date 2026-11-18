// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Core/Authentication/PasskeyPresenter.swift
// Description: The system passkey sheet (Touch ID, iCloud Keychain, nearby device, security key) for a WebAuthn challenge of the wallet. The assertion it returns is the approval; nothing biometric leaves the Mac and no local check replaces the signature.
import AppKit
import AuthenticationServices
import SPWalletCore

/// `PasskeyAuthenticator` of the app. One request at a time: a second call while a sheet is open is refused, never queued behind it.
final class SystemPasskeyAuthenticator: PasskeyAuthenticator {
    func assert(_ options: PasskeyRequestOptions, rpId: String) async throws -> PasskeyAssertion {
        guard let challenge = options.challengeData, !challenge.isEmpty else { throw PasskeyError.failed("challenge illisible") }
        guard options.rpId == nil || options.rpId == rpId else { throw PasskeyError.failed("domaine inattendu") }
        let allowed = (options.allowCredentials ?? []).compactMap(\.idData)
        return try await PasskeySheet.shared.assert(challenge: challenge, rpId: rpId, allowed: allowed)
    }
    func register(_ options: PasskeyCreationOptions, rpId: String) async throws -> PasskeyRegistration {
        guard let challenge = options.challengeData, let userId = options.userIdData else { throw PasskeyError.failed("options illisibles") }
        guard options.rp.id == nil || options.rp.id == rpId else { throw PasskeyError.failed("domaine inattendu") }
        return try await PasskeySheet.shared.register(challenge: challenge, rpId: rpId, userName: options.user.name, userId: userId)
    }
}

@MainActor final class PasskeySheet: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    static let shared = PasskeySheet()
    private enum Pending { case assertion(CheckedContinuation<PasskeyAssertion, Error>), registration(CheckedContinuation<PasskeyRegistration, Error>) }
    private var pending: Pending?
    private var controller: ASAuthorizationController?

    func assert(challenge: Data, rpId: String, allowed: [Data]) async throws -> PasskeyAssertion {
        guard pending == nil else { throw PasskeyError.failed("une autre demande de passkey est déjà affichée") }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        request.userVerificationPreference = .required
        request.allowedCredentials = allowed.map { ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0) }
        return try await withCheckedThrowingContinuation { cont in pending = .assertion(cont); start([request]) }
    }

    func register(challenge: Data, rpId: String, userName: String, userId: Data) async throws -> PasskeyRegistration {
        guard pending == nil else { throw PasskeyError.failed("une autre demande de passkey est déjà affichée") }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
        let request = provider.createCredentialRegistrationRequest(challenge: challenge, name: userName, userID: userId)
        request.userVerificationPreference = .required
        return try await withCheckedThrowingContinuation { cont in pending = .registration(cont); start([request]) }
    }

    private func start(_ requests: [ASAuthorizationRequest]) {
        let c = ASAuthorizationController(authorizationRequests: requests)
        c.delegate = self; c.presentationContextProvider = self; controller = c
        c.performRequests()
    }
    private func finish(_ error: Error) {
        switch pending { case .assertion(let c): c.resume(throwing: error); case .registration(let c): c.resume(throwing: error); case nil: break }
        pending = nil; controller = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first ?? ASPresentationAnchor() }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        switch (pending, authorization.credential) {
        case (.assertion(let cont), let a as ASAuthorizationPlatformPublicKeyCredentialAssertion):
            cont.resume(returning: PasskeyAssertion(credentialId: a.credentialID, clientDataJSON: a.rawClientDataJSON, authenticatorData: a.rawAuthenticatorData, signature: a.signature, userHandle: a.userID))
            pending = nil; self.controller = nil
        case (.registration(let cont), let r as ASAuthorizationPlatformPublicKeyCredentialRegistration):
            guard let att = r.rawAttestationObject else { finish(PasskeyError.failed("attestation absente")); return }
            cont.resume(returning: PasskeyRegistration(credentialId: r.credentialID, clientDataJSON: r.rawClientDataJSON, attestationObject: att))
            pending = nil; self.controller = nil
        default: finish(PasskeyError.failed("réponse de passkey inattendue"))
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let ns = error as NSError
        guard ns.domain == ASAuthorizationError.errorDomain else { finish(PasskeyError.failed(ns.localizedDescription)); return }
        switch ASAuthorizationError.Code(rawValue: ns.code) {
        case .canceled: finish(PasskeyError.cancelled)
        case .notInteractive, .notHandled: finish(PasskeyError.noCredential)
        default:
            // 1004 = the association between this app and the domain could not be verified (see docs/TROUBLESHOOTING.md)
            finish(ns.code == 1004 ? PasskeyError.notAvailable(ns.localizedDescription) : PasskeyError.failed("\(ns.localizedDescription) (\(ns.code))"))
        }
    }
}

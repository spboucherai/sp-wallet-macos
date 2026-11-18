// Author: Simon-Pierre Boucher — contact@spboucher.ai
// File: Core/Authentication/DevPasskey.swift
// Description: DEVELOPMENT VARIANT ONLY (not compiled in Release): a software WebAuthn authenticator (P-256, CryptoKit) for the local throwaway stack, whose relying party is 'localhost' and cannot use system passkeys. It produces real assertions that the real API and signer verify.
#if SPW_DEV
import CryptoKit
import Foundation
import SPWalletCore

final class DevPasskey: PasskeyAuthenticator, @unchecked Sendable {
    private let key: P256.Signing.PrivateKey
    private let origin: String
    private let lock = NSLock()
    private var counter: UInt32 = 0
    /// Set by tests to simulate the owner dismissing the sheet.
    nonisolated(unsafe) static var refuse = false

    init(origin: String) {
        self.origin = origin
        let file = AppEnvironment.supportDirectory.appendingPathComponent("dev-passkey.key")
        if let d = try? Data(contentsOf: file), let k = try? P256.Signing.PrivateKey(rawRepresentation: d) { key = k }
        else { key = P256.Signing.PrivateKey(); try? key.rawRepresentation.write(to: file, options: [.atomic, .completeFileProtection]) }
    }
    static func reset() { try? FileManager.default.removeItem(at: AppEnvironment.supportDirectory.appendingPathComponent("dev-passkey.key")) }

    private var xy: (Data, Data) { let raw = key.publicKey.rawRepresentation; return (raw.prefix(32), raw.suffix(32)) }
    private var cose: Data { let (x, y) = xy; return Data([0xa5, 0x01, 0x02, 0x03, 0x26, 0x20, 0x01, 0x21, 0x58, 0x20]) + x + Data([0x22, 0x58, 0x20]) + y }
    var credentialId: Data { Data(SHA256.hash(data: xy.0)).prefix(20) }

    private func clientData(_ type: String, _ challenge: String) -> Data {
        Data(#"{"type":"\#(type)","challenge":"\#(challenge)","origin":"\#(origin)","crossOrigin":false}"#.utf8)
    }

    func assert(_ options: PasskeyRequestOptions, rpId: String) async throws -> PasskeyAssertion {
        if Self.refuse { throw PasskeyError.cancelled }
        if let allowed = options.allowCredentials, !allowed.isEmpty, !allowed.contains(where: { $0.idData == credentialId }) { throw PasskeyError.noCredential }
        let n: UInt32 = lock.withLock { counter += 1; return counter + UInt32(Date().timeIntervalSince1970) - 1_700_000_000 }
        let cd = clientData("webauthn.get", options.challenge)
        var auth = Data(SHA256.hash(data: Data(rpId.utf8))); auth.append(0x05); withUnsafeBytes(of: n.bigEndian) { auth.append(contentsOf: $0) }
        let sig = try key.signature(for: auth + Data(SHA256.hash(data: cd)))
        return PasskeyAssertion(credentialId: credentialId, clientDataJSON: cd, authenticatorData: auth, signature: sig.derRepresentation, userHandle: nil)
    }

    func register(_ options: PasskeyCreationOptions, rpId: String) async throws -> PasskeyRegistration {
        let cd = clientData("webauthn.create", options.challenge), id = credentialId
        var auth = Data(SHA256.hash(data: Data(rpId.utf8))); auth.append(0x45); auth.append(Data(count: 4)); auth.append(Data(count: 16))
        auth.append(contentsOf: [UInt8(id.count >> 8), UInt8(id.count & 0xff)]); auth.append(id); auth.append(cose)
        // attestation "none": {fmt: "none", attStmt: {}, authData: bstr}
        var att = Data([0xa3, 0x63, 0x66, 0x6d, 0x74, 0x64, 0x6e, 0x6f, 0x6e, 0x65, 0x67, 0x61, 0x74, 0x74, 0x53, 0x74, 0x6d, 0x74, 0xa0, 0x68, 0x61, 0x75, 0x74, 0x68, 0x44, 0x61, 0x74, 0x61])
        att.append(contentsOf: [0x58, UInt8(auth.count)]); att.append(auth)
        return PasskeyRegistration(credentialId: id, clientDataJSON: cd, attestationObject: att, transports: ["internal"])
    }
}
#endif

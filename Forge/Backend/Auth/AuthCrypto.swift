import CryptoKit
import Foundation
import Security

/// The two pieces of arithmetic that make signing in safe to do over a URL
/// scheme.
///
/// Both exist for the same reason: something leaves this process, travels
/// through software Forge does not control — a browser, another app that has
/// claimed the same scheme, Apple's own servers — and comes back. Neither the
/// thing that leaves nor the thing that returns is worth anything on its own.
enum AuthCrypto {

    // MARK: - PKCE

    /// A verifier and the challenge derived from it.
    ///
    /// The verifier stays here. The challenge goes to Google via Supabase, and
    /// the authorization code that comes back can only be exchanged by whoever
    /// can produce a string that hashes to it. An app that intercepts the
    /// callback gets a code it cannot spend.
    struct PKCE: Equatable, Sendable {
        let verifier: String
        let challenge: String
    }

    static func makePKCE() -> PKCE {
        // 64 bytes → 86 base64url characters, comfortably inside RFC 7636's
        // 43…128 and well past the 256 bits of entropy it asks for.
        let verifier = base64URL(randomBytes(64))
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return PKCE(verifier: verifier, challenge: base64URL(Data(digest)))
    }

    // MARK: - Apple's nonce

    /// A fresh value for one sign-in.
    ///
    /// The raw string is sent to Supabase; its SHA-256 is what goes to Apple,
    /// so the identity token Apple signs commits to a value only this process
    /// has seen. Replaying a captured token against our project fails, because
    /// the nonce inside it will not match the one we hand over with it.
    static func makeNonce() -> String {
        base64URL(randomBytes(32))
    }

    /// Hex rather than base64: this goes into the `nonce` field of an
    /// `ASAuthorizationAppleIDRequest`, and Apple hashes and compares it as the
    /// exact string we provide. Hex is the spelling every Apple sample uses and
    /// the one their servers are known to round-trip cleanly.
    static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    // MARK: - Bytes

    /// The system CSPRNG, with Swift's as a fallback.
    ///
    /// `SecRandomCopyBytes` can in principle fail. Swift's default generator is
    /// also seeded from the system CSPRNG on this platform, so the fallback is
    /// not a downgrade — it is the same entropy reached by a different door,
    /// and it means a sign-in cannot be broken by an error nobody can
    /// reproduce.
    static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        if SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess {
            return Data(bytes)
            
        }
        return Data((0..<count).map { _ in UInt8.random(in: UInt8.min...UInt8.max) })
    }

    /// base64, in the alphabet a URL can carry, with the padding dropped —
    /// which is what both RFC 7636 and every OAuth server expect.
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

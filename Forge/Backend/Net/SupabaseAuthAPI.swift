import Foundation

/// GoTrue, spelled out.
///
/// Five calls, and they are the entire relationship Forge has with an identity
/// provider. Nothing above this file constructs a URL or knows that a session
/// arrives as `expires_in` rather than a date.
struct SupabaseAuthAPI: Sendable {

    let client: HTTPClient

    private var base: URL { client.config.authURL }

    // MARK: - The wire

    /// What GoTrue hands back for every one of the grants below.
    struct SessionResponse: Decodable, Sendable {
        let accessToken: String
        let refreshToken: String
        /// Seconds. Turned into a date at the moment of receipt, because a
        /// duration is only meaningful next to the instant it was measured
        /// from and that instant is not on the wire.
        let expiresIn: TimeInterval
        let user: UserResponse

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case user
        }
    }

    struct UserResponse: Decodable, Sendable {
        let id: String
        let email: String?
        let appMetadata: AppMetadata?

        struct AppMetadata: Decodable, Sendable {
            let provider: String?
        }

        enum CodingKeys: String, CodingKey {
            case id
            case email
            case appMetadata = "app_metadata"
        }
    }

    // MARK: - Sign in with Apple

    /// Exchange the identity token Apple just signed for a Forge session.
    ///
    /// The nonce goes up alongside it and is the whole of the replay defence:
    /// Apple signed a token containing the SHA-256 of a value we invented a
    /// moment ago, and GoTrue checks that the raw value we send hashes to the
    /// one inside. A token captured from someone else's sign-in carries
    /// somebody else's nonce and is refused.
    func signInWithApple(idToken: String, nonce: String) async throws -> SessionResponse {
        struct Body: Encodable {
            let provider = "apple"
            let idToken: String
            let nonce: String

            enum CodingKeys: String, CodingKey {
                case provider
                case idToken = "id_token"
                case nonce
            }
        }
        return try await token(
            grant: "id_token",
            body: Body(idToken: idToken, nonce: nonce)
        )
    }

    // MARK: - Google

    /// Where to send the browser.
    ///
    /// PKCE rather than the implicit flow, and not as a formality: the callback
    /// comes back through a URL scheme that any app on the phone may also claim,
    /// so the authorization code has to be worthless to whoever intercepts it.
    /// It is, without the verifier — which never leaves this process.
    func googleAuthorizeURL(challenge: String) -> URL? {
        var components = URLComponents(
            url: base.appendingPathComponent("authorize"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: SupabaseConfig.callbackURL),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
        ]
        return components?.url
    }

    /// Trade the code the browser came back with for a session.
    func exchange(code: String, verifier: String) async throws -> SessionResponse {
        struct Body: Encodable {
            let authCode: String
            let codeVerifier: String

            enum CodingKeys: String, CodingKey {
                case authCode = "auth_code"
                case codeVerifier = "code_verifier"
            }
        }
        return try await token(
            grant: "pkce",
            body: Body(authCode: code, codeVerifier: verifier)
        )
    }

    // MARK: - Anonymous

    /// A new anonymous user: a random id with no email, phone, password or
    /// provider behind it, and a session for it.
    ///
    /// This is what `supabase-js` and `supabase-swift` call `signInAnonymously`
    /// — a `POST /auth/v1/signup` with no credentials in the body — and it only
    /// works while **Anonymous sign-ins** is enabled for the project
    /// (Authentication → Sign In / Providers). Nothing is asked of the person
    /// and nothing is shown to them; see `AnonymousIdentity`.
    func signInAnonymously() async throws -> SessionResponse {
        try await client.send(
            SessionResponse.self,
            .post,
            url: base.appendingPathComponent("signup"),
            body: Data("{}".utf8)
        )
    }

    // MARK: - Keeping it alive

    func refresh(refreshToken: String) async throws -> SessionResponse {
        struct Body: Encodable {
            let refreshToken: String

            enum CodingKeys: String, CodingKey {
                case refreshToken = "refresh_token"
            }
        }
        return try await token(grant: "refresh_token", body: Body(refreshToken: refreshToken))
    }

    /// Ends the session on the server too.
    ///
    /// `scope=local` on purpose: signing out of Forge on this phone should not
    /// sign somebody out of the iPad they left at home. Signing every device
    /// out is a different, rarer intention and would need to be asked for.
    func signOut(accessToken: String) async throws {
        try await client.send(
            .post,
            url: base.appendingPathComponent("logout"),
            query: [URLQueryItem(name: "scope", value: "local")],
            accessToken: accessToken
        )
    }

    /// Who the server thinks this token belongs to. Used to check a restored
    /// session is still real before anything is uploaded under it.
    func user(accessToken: String) async throws -> UserResponse {
        try await client.send(
            UserResponse.self,
            .get,
            url: base.appendingPathComponent("user"),
            accessToken: accessToken
        )
    }

    // MARK: - Shared

    private func token(grant: String, body: some Encodable) async throws -> SessionResponse {
        let encoded: Data
        do {
            encoded = try BackendJSON.encoder.encode(body)
        } catch {
            throw BackendError.decoding
        }
        return try await client.send(
            SessionResponse.self,
            .post,
            url: base.appendingPathComponent("token"),
            query: [URLQueryItem(name: "grant_type", value: grant)],
            body: encoded
        )
    }
}

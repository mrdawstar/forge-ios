import AuthenticationServices
import Foundation

/// Everything Forge knows about who somebody is.
///
/// Two ways in, one way out, and a state that starts — and is perfectly happy
/// to stay — at `.anonymous`. Nothing in this class is on the path of a
/// day: the app never waits for it, never asks it a question before drawing
/// a screen, and works exactly the same if every method here fails forever.
///
/// It owns the session and the refreshing of it, and nothing else. It does not
/// know what a day is, it does not decide when to sync, and it does not
/// touch a row of user data. That belongs to the services above it, which is
/// what keeps "signed in" from quietly becoming a requirement for anything.
@MainActor
@Observable
final class AuthService {

    // MARK: - State

    private(set) var state: AuthState = .anonymous

    /// Set only when something went wrong in a way a person should hear about.
    /// A cancelled sign-in is not one of those things, and neither is being on
    /// a train.
    private(set) var failure: String?

    /// Whether there is a backend at all. False in a build with no project
    /// configured, and every method below becomes a no-op.
    var isConfigured: Bool { api != nil }

    var isSignedIn: Bool { state.isSignedIn }
    var userID: String? { state.session?.userID }

    // MARK: - Collaborators

    private let api: SupabaseAuthAPI?

    private enum Key {
        static let session = "forge.auth.session.v1"
    }

    /// Guards against two callers refreshing the same expired token at once.
    ///
    /// Measured against the live project rather than assumed: reusing a spent
    /// refresh token there answers 200 with a fresh session rather than
    /// revoking the family, so losing this race would not actually sign anybody
    /// out. The guard stays because that is a server setting somebody could
    /// tighten without telling us, and because two devices' worth of refreshes
    /// for one stale token is a request nobody needed to make.
    private var refreshInFlight: Task<String, Error>?

    init(api: SupabaseAuthAPI?) {
        self.api = api
        restore()
        observeAppleRevocation()
    }

    /// Pick up where the last launch left off.
    ///
    /// The token is not checked against the server here. Doing so would put a
    /// network round trip on the launch path for a fact nothing needs at launch
    /// — the first request that actually matters will find out, and it will
    /// find out at a moment when being wrong costs nothing.
    private func restore() {
        guard isConfigured,
              let session = Keychain.value(AuthSession.self, for: Key.session)
        else { return }
        state = .signedIn(session)
    }

    // MARK: - Sign in with Apple

    /// Configure the request the button is about to make.
    ///
    /// The nonce is generated here and kept until the answer comes back. Apple
    /// receives its hash and signs it into the identity token; Supabase
    /// receives the original and checks the two agree.
    private var pendingNonce: String?

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AuthCrypto.makeNonce()
        pendingNonce = nonce
        // The name is asked for and never stored. Apple only offers it on the
        // very first authorization, and Forge has nowhere to put a name and
        // nothing it would do with one — the email is kept solely so Settings
        // can show which account is signed in.
        request.requestedScopes = [.email]
        request.nonce = AuthCrypto.sha256Hex(nonce)
        state = .signingIn
        failure = nil
    }

    @discardableResult
    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async -> AuthSession? {
        guard let api else { return nil }
        let nonce = pendingNonce
        pendingNonce = nil

        switch result {
        case .failure(let error):
            // The system sheet's own cancel. Nothing to say.
            let cancelled = (error as? ASAuthorizationError)?.code == .canceled
            settle(cancelled ? nil : "That sign-in didn't complete.")
            return nil

        case .success(let authorization):
            guard let credential = authorization.credential
                    as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce
            else {
                settle("That sign-in didn't complete.")
                return nil
            }

            do {
                let response = try await api.signInWithApple(idToken: idToken, nonce: nonce)
                return adopt(response, provider: .apple, appleUserID: credential.user)
            } catch {
                settle(message(for: error))
                return nil
            }
        }
    }

    // MARK: - When Apple takes it back

    /// Somebody revoked Forge under Settings → their name → Sign in with Apple.
    ///
    /// This has to be handled here, because nothing else will notice. Supabase
    /// does not re-check with Apple when it refreshes a token, so a revoked
    /// authorization leaves a session that goes on working — and on syncing —
    /// for as long as the refresh token keeps being renewed, which is forever.
    /// Somebody who has explicitly told their phone that this app may no longer
    /// use their Apple Account would still be signed into it a year later.
    ///
    /// Two ways in, because one is not enough. The notification fires while the
    /// app is running, which covers revoking in Settings and coming back; the
    /// check on the way to the foreground covers everything else, which is most
    /// of it, because revoking is something people do with the app closed.
    private func observeAppleRevocation() {
        // Not removed in a `deinit`. One of these is built at launch and lives
        // as long as the process, and the closure holds `self` weakly, so a
        // teardown path would only add a hop for a case that never happens.
        NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.appleCredentialWithdrawn() }
        }
    }

    private func appleCredentialWithdrawn() {
        guard state.session?.provider == .apple else { return }
        expire()
    }

    /// Ask Apple whether the authorization behind this session still stands.
    ///
    /// Cheap, local, and answered from a cache on the device — there is no
    /// network here and nothing to wait for, which is why it is safe to run on
    /// every foreground alongside the sync.
    ///
    /// Only `.revoked` and `.notFound` end the session. `.transferred` means
    /// the app has moved to another development team and the account is still
    /// perfectly good, and an error means the question could not be asked,
    /// which is not an answer — signing somebody out because a system service
    /// was busy would be the same rudeness as signing them out for being in a
    /// tunnel.
    func refreshAppleCredentialState() async {
        guard let session = state.session,
              session.provider == .apple,
              let appleUserID = session.appleUserID
        else { return }

        let provider = ASAuthorizationAppleIDProvider()
        guard let credential = try? await provider.credentialState(forUserID: appleUserID) else {
            return
        }
        switch credential {
        case .revoked, .notFound:
            expire()
        case .authorized, .transferred:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Google

    @discardableResult
    func signInWithGoogle() async -> AuthSession? {
        guard let api else { return nil }
        state = .signingIn
        failure = nil

        let pkce = AuthCrypto.makePKCE()
        guard let authorizeURL = api.googleAuthorizeURL(challenge: pkce.challenge) else {
            settle("That sign-in didn't complete.")
            return nil
        }

        do {
            let callback = try await WebAuthFlow.start(
                url: authorizeURL,
                callbackScheme: SupabaseConfig.callbackScheme
            )
            let answer = OAuthCallback(url: callback)
            guard let code = answer.code else {
                // A provider that answered with an error rather than a code.
                // Its own words are not shown — they are written for a
                // developer reading a console, not for somebody standing in a
                // kitchen at six in the morning.
                settle(answer.error == nil ? nil : "That sign-in didn't complete.")
                return nil
            }
            let response = try await api.exchange(code: code, verifier: pkce.verifier)
            return adopt(response, provider: .google)
        } catch BackendError.signInCancelled {
            settle(nil)
            return nil
        } catch {
            settle(message(for: error))
            return nil
        }
    }

    // MARK: - Signing out

    /// Ends the session on this device, and asks the server to end it too.
    ///
    /// Nothing local is deleted. The history, the blades and the arrangement of
    /// the day stay exactly where they are, because they were never the
    /// account's — they are the practice, and the account was only ever a way
    /// of keeping a copy of it somewhere safe. An app that empties itself when
    /// you sign out has told you what it thinks it owns.
    func signOut() async {
        guard let api, let session = state.session else {
            state = .anonymous
            return
        }
        // Cleared first. A logout that fails to reach the server must still
        // sign somebody out of their own phone.
        Keychain.remove(Key.session)
        refreshInFlight?.cancel()
        refreshInFlight = nil
        state = .anonymous
        failure = nil

        try? await api.signOut(accessToken: session.accessToken)
    }

    // MARK: - Tokens

    /// A token good enough to send, refreshed if it is not.
    ///
    /// The one door to an access token. Everything that talks to the backend
    /// comes through here, so there is exactly one place that can decide a
    /// session is finished — and it is the same place that would have renewed
    /// it if renewing were possible.
    func validAccessToken() async throws -> String {
        guard let api else { throw BackendError.notConfigured }
        guard let session = state.session else { throw BackendError.unauthorized }
        guard session.needsRefresh() else { return session.accessToken }

        if let refreshInFlight { return try await refreshInFlight.value }

        let task = Task<String, Error> { [weak self] in
            guard let self else { throw BackendError.cancelled }
            do {
                let response = try await api.refresh(refreshToken: session.refreshToken)
                guard let renewed = self.adopt(response, provider: session.provider) else {
                    throw BackendError.unauthorized
                }
                return renewed.accessToken
            } catch let error as BackendError where error.isRetryable {
                // The network, not the session. The stored token is untouched
                // and the next attempt gets to try again — signing somebody out
                // because their train went into a tunnel would be the single
                // rudest thing this file could do.
                throw error
            } catch {
                self.expire()
                throw BackendError.unauthorized
            }
        }
        refreshInFlight = task
        defer { refreshInFlight = nil }
        return try await task.value
    }

    /// The server has stopped honouring this session. Kept as a state of its
    /// own rather than folded into `.anonymous`, so Settings can say "signed
    /// out" to somebody who did not ask to be.
    private func expire() {
        Keychain.remove(Key.session)
        state = .expired
    }

    // MARK: - Plumbing

    @discardableResult
    private func adopt(
        _ response: SupabaseAuthAPI.SessionResponse,
        provider: AuthProvider,
        appleUserID: String? = nil
    ) -> AuthSession? {
        let session = AuthSession(
            userID: response.user.id,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            // Measured from now, because `expires_in` is a duration and the
            // instant it was measured from is not on the wire.
            expiresAt: Date().addingTimeInterval(response.expiresIn),
            // The server's own word for the provider outranks ours: it is what
            // the account is actually federated to.
            provider: response.user.appMetadata?.provider.map(AuthProvider.init) ?? provider,
            // Carried across a refresh rather than dropped: a renewed session is
            // the same authorization, and losing the identifier here would stop
            // it ever being checked again.
            appleUserID: appleUserID ?? state.session?.appleUserID,
            email: response.user.email
        )
        Keychain.set(session, for: Key.session)
        state = .signedIn(session)
        failure = nil
        return session
    }

    /// Back to wherever we were, with or without something to say.
    private func settle(_ message: String?) {
        state = Keychain.value(AuthSession.self, for: Key.session)
            .map { AuthState.signedIn($0) } ?? .anonymous
        failure = message
    }

    /// One sentence, in Forge's voice, and never the server's.
    ///
    /// Nothing here blames the user, and nothing here is an exclamation. A
    /// person who could not sign in wants to know whether to try again, which
    /// is the only thing any of these say.
    private func message(for error: Error) -> String? {
        guard let backend = error as? BackendError else { return "That didn't work." }
        switch backend {
        case .offline, .timedOut:
            return "You're offline. Forge works either way — try again when you're back."
        case .signInCancelled, .cancelled:
            return nil
        case .rateLimited, .server:
            return "The server is busy. Try again in a minute."
        case .notConfigured:
            return nil
        default:
            return "That didn't work."
        }
    }
}

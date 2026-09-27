import Foundation

/// The identity Forge's AI requests are made under, which nobody ever sees.
///
/// # Why there is one at all
///
/// `forge-ai` requires a Supabase JWT, and that is not negotiable: an endpoint
/// that spends money on a model must know *some* stable caller to rate limit,
/// and an unauthenticated one would be callable by anybody who reads the app's
/// binary. But Forge has no account (`FORGE_CONTEXT.md` §2n) and is not getting
/// one back. So the app signs in **anonymously**: GoTrue mints a random user
/// with no email, no password, no provider and no name, and hands back a
/// session for it.
///
/// # What makes it invisible
///
/// - It has no UI, no state any view observes, and no word on any screen.
///   `AuthService` — the visible account, which is dormant — never sees it.
/// - It is created lazily, the first time a Premium request actually reaches
///   the model (`RemoteForgeAI.connect`), and never for somebody without a
///   purchase: the proof of purchase is checked first.
/// - It lives in the Keychain on this device only
///   (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). A new phone mints a
///   new one; nothing needs to carry over, because the spend cap is keyed on
///   the purchase rather than on this id (migration `0008`).
///
/// # Failure is always "answer locally"
///
/// Every path that cannot produce a token returns nil, and nil makes
/// `RemoteForgeAI` use `LocalForgeAI` — the same honest fallback as a phone in
/// a tunnel. The one distinction drawn is between the network failing (keep
/// the session, try again next time) and the server refusing the refresh token
/// (the identity is gone; mint a new one).
actor AnonymousIdentity {

    static let keychainAccount = "forge.auth.anonymous.v1"

    private let api: SupabaseAuthAPI?
    private let store: AnonymousSessionStore
    private let now: @Sendable () -> Date

    private var session: AuthSession?
    private var inFlight: Task<AuthSession?, Never>?

    init(
        api: SupabaseAuthAPI?,
        store: AnonymousSessionStore = KeychainAnonymousSessionStore(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.api = api
        self.store = store
        self.now = now
    }

    /// A current access token, minting or refreshing as needed. Nil with no
    /// project configured, offline, or when the server will not issue one.
    ///
    /// Concurrent callers share one attempt: two requests arriving together
    /// must not mint two identities.
    func accessToken() async -> String? {
        guard api != nil else { return nil }
        if let inFlight { return await inFlight.value?.accessToken }
        let attempt = Task { await self.resolve() }
        inFlight = attempt
        let resolved = await attempt.value
        inFlight = nil
        return resolved?.accessToken
    }

    private func resolve() async -> AuthSession? {
        guard let api else { return nil }

        if let current = session ?? store.load() {
            session = current
            guard current.needsRefresh(now: now()) else { return current }
            do {
                return adopt(try await api.refresh(refreshToken: current.refreshToken))
            } catch let error as BackendError where error.isRetryable {
                // The network, not the identity. Keep it for next time.
                return nil
            } catch {
                // Refused: revoked, expired past its refresh window, or the
                // project was reset. That identity is gone; start another.
                forget()
            }
        }

        do {
            return adopt(try await api.signInAnonymously())
        } catch {
            // Offline, or anonymous sign-ins are off for the project.
            return nil
        }
    }

    private func adopt(_ response: SupabaseAuthAPI.SessionResponse) -> AuthSession {
        let renewed = AuthSession(
            userID: response.user.id,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: now().addingTimeInterval(response.expiresIn),
            provider: .anonymous,
            email: nil
        )
        session = renewed
        store.save(renewed)
        return renewed
    }

    private func forget() {
        session = nil
        store.clear()
    }
}

// MARK: - Where it is kept

protocol AnonymousSessionStore: Sendable {
    func load() -> AuthSession?
    func save(_ session: AuthSession)
    func clear()
}

/// The Keychain, under its own account — never `AuthService`'s.
struct KeychainAnonymousSessionStore: AnonymousSessionStore {
    var account = AnonymousIdentity.keychainAccount

    func load() -> AuthSession? { Keychain.value(AuthSession.self, for: account) }
    func save(_ session: AuthSession) { Keychain.set(session, for: account) }
    func clear() { Keychain.remove(account) }
}

import AuthenticationServices
import Foundation

/// Where the backend is assembled, and the only part of it the app can see.
///
/// Four services with one job each, built here and wired to each other here.
/// `ContentView` holds this and nothing else; no screen has a reference to an
/// `HTTPClient`, and no view model has heard of Supabase.
///
/// The whole object is optional in effect: with no project configured, `api` is
/// nil, every service is inert, `isConfigured` is false, and the Account screen
/// says nothing at all. Forge in that state is Forge as it was before any of
/// this — which is the point, and is why it is worth building this way rather
/// than sprinkling `if let backend` through the app.
@MainActor
@Observable
final class ForgeBackend {

    // MARK: - The services

    let auth: AuthService
    let sync: SyncService
    let users: UserService
    let premium: PremiumService

    private let config: SupabaseConfig?
    private let ledger: SyncLedger

    var isConfigured: Bool { config != nil }

    /// What Settings shows. Derived rather than stored, so there is one answer
    /// and no way for the screen to hold an old one.
    var isSignedIn: Bool { auth.isSignedIn }
    var accountLabel: String? { auth.state.session?.email }
    var provider: AuthProvider? { auth.state.session?.provider }

    // MARK: - Building it

    /// `isPremium` is a closure into `ForgeStore` rather than the store itself.
    /// The entitlement belongs to StoreKit and this object has no business
    /// owning the thing that produces it — see `PremiumService` for the longer
    /// version of why that matters.
    init(
        bridge: PracticeBridge,
        isPremium: @escaping () -> Bool,
        config: SupabaseConfig? = SupabaseConfig.fromBundle()
    ) {
        self.config = config
        let ledger = SyncLedger()
        self.ledger = ledger

        let client = config.map { HTTPClient(config: $0) }
        let authAPI = client.map { SupabaseAuthAPI(client: $0) }
        let dataAPI = client.map { SupabaseDataAPI(client: $0) }

        let auth = AuthService(api: authAPI)
        self.auth = auth
        self.users = UserService(api: dataAPI, auth: auth)
        self.premium = PremiumService(api: dataAPI, auth: auth)
        self.sync = SyncService(
            api: dataAPI, auth: auth, bridge: bridge, ledger: ledger, isPremium: isPremium
        )
    }

    // MARK: - Signing in

    /// Configure the request the native button is about to make.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        auth.prepareAppleRequest(request)
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        guard await auth.completeAppleSignIn(result) != nil else { return }
        await settleSignIn()
    }

    func signInWithGoogle() async {
        guard await auth.signInWithGoogle() != nil else { return }
        await settleSignIn()
    }

    /// Everything that follows a successful sign-in, in the order it has to
    /// happen.
    ///
    /// Registering the device first, because that is the one thing worth doing
    /// for a free account too. Then the first sync — which, for somebody who
    /// has been keeping days on this phone for a year, *is* the migration:
    /// the ledger has no watermark yet, so every local record counts as unsent
    /// and goes up in one pass. There is no separate migration routine, and
    /// there is deliberately nothing to get wrong about running it twice —
    /// every row upserts onto its own primary key, so a second attempt writes
    /// the same rows to the same places and changes nothing.
    private func settleSignIn() async {
        await users.registerDevice()
        sync.syncNow()
    }

    // MARK: - Signing out

    /// Ends the session, and leaves the practice exactly where it is.
    func signOut() async {
        sync.forgetAccount()
        await auth.signOut()
    }

    // MARK: - Ending the account

    /// Delete the account, and everything the server holds for it.
    ///
    /// Required of any app that lets somebody make an account, and it deletes
    /// the account rather than merely disowning it: one call, and the cascade
    /// in `0003` takes the profile, the devices, the activities, the rituals,
    /// the days, the blades and the premium row with it.
    ///
    /// What it does not touch is this phone. The days stay, for the same
    /// reason signing out leaves them: they are the practice, not the account,
    /// and they were never the server's to begin with. Somebody who deletes
    /// their account has said they want no copy kept somewhere else — which is
    /// a different sentence from wanting their own history destroyed, and an
    /// app that hears the second when it was told the first is an app that
    /// takes a year of somebody's days on a misreading.
    ///
    /// The ledger is wound all the way back rather than merely cleared, so a
    /// later sign-in to a new account is a first sign-in and the practice on
    /// this phone goes up with it.
    ///
    /// Returns false when the account is still there, so the screen can say so
    /// rather than claim a deletion that did not happen.
    func deleteAccount() async -> Bool {
        guard isConfigured, auth.isSignedIn else { return false }
        do {
            try await users.deleteAccount()
        } catch {
            return false
        }
        sync.forgetAccount()
        ledger.forgetAccount()
        // The account no longer exists, so the server has nothing left to be
        // told. `signOut` tries anyway and swallows the refusal, which is the
        // right shape: the local session must be gone either way.
        await auth.signOut()
        return true
    }

    // MARK: - Living

    /// The app came forward, or a day was earned. Both mean the same thing
    /// here: this is a good moment, and a bad one to be made to wait.
    func syncNow() { sync.syncNow() }
    func syncSoon() { sync.syncSoon() }

    /// Check the app is still allowed to be signed in as who it thinks it is.
    ///
    /// Only Apple answers this, and only for accounts federated to it. Local,
    /// cached and instant — nothing about this is on the network, and nothing
    /// anywhere waits for it.
    func refreshCredentialState() async {
        await auth.refreshAppleCredentialState()
    }

    /// StoreKit changed its mind — a purchase, a renewal, a refund, a plan
    /// bought on another device. The row is updated, and sync is started or
    /// stopped by the same fact.
    func premiumChanged(to entitlement: PremiumEntitlement) {
        Task {
            await premium.record(entitlement)
            sync.syncNow()
        }
    }

    // MARK: - Lending the account to the model

    /// A token for the signed-in account, or nil.
    ///
    /// The one door `ClaudeForgeAI` reaches the account through, and it is a
    /// door rather than a reference on purpose: the AI holds a closure onto
    /// this method and never an `AuthService`, so the model layer cannot read
    /// an email, a provider, a user id or a session — only the fact that this
    /// request is allowed to be made.
    ///
    /// Nil is the ordinary case rather than a failure. Nobody signed in, no
    /// project configured, a refresh that could not reach the network: all of
    /// them mean the model is unavailable this minute, and every method on the
    /// AI answers that by falling back to the arithmetic.
    func currentAccessToken() async -> String? {
        guard isConfigured, auth.isSignedIn else { return nil }
        return try? await auth.validAccessToken()
    }

    // MARK: - What Settings says

    /// Whether this account's practice has ever been uploaded from this phone.
    ///
    /// Read only to word one line: somebody who has just turned Premium on
    /// should be told their history is on its way up rather than shown a bare
    /// "not synced".
    var hasEverSynced: Bool { ledger.pushedThrough != nil }
}

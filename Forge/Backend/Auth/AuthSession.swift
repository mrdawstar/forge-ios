import Foundation

/// Who somebody signed in as, and what proves it.
///
/// A value, and a plain one. It knows when it goes stale and nothing else — the
/// refreshing is `AuthService`'s job, and keeping that decision out of here is
/// what lets every rule below be checked against a clock somebody made up.
struct AuthSession: Codable, Equatable, Sendable {

    /// The uuid the server assigned. Never sent as an identifier in a request
    /// body that the server then trusts — every policy reads the id out of the
    /// signed token instead. It is here so the app can tell one account's local
    /// cache from another's.
    let userID: String
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let provider: AuthProvider
    /// The identifier Apple gave this account, kept for one question only:
    /// whether that authorization still stands.
    ///
    /// Not the same thing as `userID` and not interchangeable with it — this is
    /// Apple's name for the person, scoped to this app, and it is the only key
    /// `ASAuthorizationAppleIDProvider` will answer to. Optional because a
    /// session stored before this field existed does not have one; those keep
    /// working and are simply not checked until the next sign-in.
    let appleUserID: String?
    /// Only ever shown back to the user in Settings, so they can see which
    /// account they are on. Nothing is keyed by it.
    let email: String?

    /// Spelled out rather than synthesised, for one reason: `appleUserID`
    /// carries a default. Every session that is not Apple's has nothing to put
    /// there, and a memberwise initialiser would make all of them say so.
    init(
        userID: String,
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        provider: AuthProvider,
        appleUserID: String? = nil,
        email: String?
    ) {
        self.userID = userID
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.provider = provider
        self.appleUserID = appleUserID
        self.email = email
    }

    /// How long before expiry a token counts as spent.
    ///
    /// Ninety seconds because a token that is valid when the request is built
    /// and expired when it arrives produces a 401 that looks exactly like a
    /// revoked session, and re-authenticating somebody over a slow connection
    /// is a rotten way to fail.
    static let refreshMargin: TimeInterval = 90

    func isExpired(now: Date = .now) -> Bool {
        expiresAt <= now
    }

    func needsRefresh(now: Date = .now) -> Bool {
        expiresAt.addingTimeInterval(-Self.refreshMargin) <= now
    }
}

enum AuthProvider: String, Codable, Equatable, Sendable {
    case apple
    case google
    /// An invisible anonymous identity — no provider, nobody signed in. Only
    /// ever held by `AnonymousIdentity`, never by `AuthService`, and never
    /// shown anywhere.
    case anonymous
    /// A session restored from a build that predates this enum, or a provider
    /// added on the server before the app knew about it. Signing in still
    /// works; only the label in Settings is vaguer.
    case unknown

    init(rawValue: String) {
        switch rawValue.lowercased() {
        case "apple": self = .apple
        case "google": self = .google
        case "anonymous": self = .anonymous
        default: self = .unknown
        }
    }

    var label: String {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        case .anonymous: "no account"
        case .unknown: "your account"
        }
    }
}

/// Where the app is with respect to an account.
///
/// `.anonymous` is a first-class state and the one Forge launches in. It is not
/// "signed out" and it is not an error — it is somebody using the app, which is
/// the thing the app is for. Every screen has to read correctly here, forever,
/// for somebody who never signs in at all.
enum AuthState: Equatable, Sendable {
    /// No account, and none needed.
    case anonymous
    case signingIn
    case signedIn(AuthSession)
    /// There is a stored session but the server has stopped honouring it —
    /// revoked, or password changed elsewhere. The local practice is untouched;
    /// only the cloud half has gone quiet.
    case expired

    var session: AuthSession? {
        guard case .signedIn(let session) = self else { return nil }
        return session
    }

    var isSignedIn: Bool { session != nil }
}

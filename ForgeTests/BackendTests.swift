import Foundation
import Testing
@testable import Forge

/// The plumbing under the merge: what goes on the wire, what a failure means,
/// and how long to wait before trying again.
///
/// None of it needs a network. All three are the kind of thing that is obvious
/// until the day a timestamp comes back with six digits of fraction and a whole
/// history stops decoding.
@Suite("Backend")
struct BackendTests {

    // MARK: - Configuration

    /// A build with nothing filled in has to be inert rather than broken. This
    /// is the guarantee that the entire backend can do nothing at all.
    @Test("An unconfigured build produces no config")
    func emptyConfigurationIsNil() {
        #expect(SupabaseConfig.make(url: "", anonKey: "abc") == nil)
        #expect(SupabaseConfig.make(url: "https://x.supabase.co", anonKey: "  ") == nil)
    }

    /// An unsubstituted build setting reaches Info.plist verbatim, and would
    /// otherwise be treated as a host.
    @Test("An unsubstituted build setting is not a URL")
    func placeholdersAreRejected() {
        #expect(SupabaseConfig.make(
            url: "$(FORGE_SUPABASE_URL)", anonKey: "$(FORGE_SUPABASE_ANON_KEY)"
        ) == nil)
    }

    @Test("Only https is accepted")
    func plaintextIsRejected() {
        #expect(SupabaseConfig.make(url: "http://x.supabase.co", anonKey: "k") == nil)
        #expect(SupabaseConfig.make(url: "https://x.supabase.co", anonKey: "k") != nil)
    }

    /// Supabase replaced the anon JWT with `sb_publishable_…` keys, which are
    /// not JWTs and do not decode as one. Nothing in Forge parses the key — it
    /// is copied into two headers verbatim — and this is the check that it
    /// stays that way, because the day something starts inspecting it is the
    /// day the shipped configuration stops working.
    @Test("A publishable key is carried verbatim, like the JWT before it")
    func publishableKeyIsOpaque() throws {
        let key = "sb_publishable_Go9fLji8ndvLoeD2jfB1yg_ZTHecWEo"
        let config = try #require(
            SupabaseConfig.make(url: "https://eslaeueyeuaejdnqfasv.supabase.co", anonKey: key)
        )
        #expect(config.anonKey == key)

        let legacy = try #require(
            SupabaseConfig.make(url: "https://eslaeueyeuaejdnqfasv.supabase.co", anonKey: "eyJhbGciOi.J9.x")
        )
        #expect(legacy.anonKey == "eyJhbGciOi.J9.x")
    }

    @Test("The endpoints hang off the project URL")
    func endpoints() throws {
        let config = try #require(
            SupabaseConfig.make(url: "https://abc.supabase.co", anonKey: "k")
        )
        #expect(config.authURL.absoluteString == "https://abc.supabase.co/auth/v1")
        #expect(config.restURL.absoluteString == "https://abc.supabase.co/rest/v1")
    }

    // MARK: - Timestamps

    /// Postgres renders `timestamptz` with microseconds when it has them and
    /// with no fraction at all when it does not. Both are the same instant, and
    /// a parser that only accepts what it emits works right up until the first
    /// row written on a whole second.
    @Test("Every spelling Postgres uses parses")
    func timestampsParse() throws {
        let whole = try #require(BackendDate.date(from: "2026-08-04T05:12:33+00:00"))
        let milli = try #require(BackendDate.date(from: "2026-08-04T05:12:33.123+00:00"))
        let micro = try #require(BackendDate.date(from: "2026-08-04T05:12:33.123456+00:00"))
        let zulu = try #require(BackendDate.date(from: "2026-08-04T05:12:33Z"))

        #expect(whole == zulu)
        #expect(abs(milli.timeIntervalSince(whole) - 0.123) < 0.001)
        #expect(abs(micro.timeIntervalSince(whole) - 0.123) < 0.001)
    }

    @Test("A timestamp survives the round trip")
    func timestampRoundTrip() throws {
        let original = Date(timeIntervalSince1970: 1_800_000_000.25)
        let parsed = try #require(BackendDate.date(from: BackendDate.string(from: original)))
        #expect(abs(parsed.timeIntervalSince(original)) < 0.001)
    }

    @Test("Nonsense is nil rather than a date in 1970")
    func rubbishIsRejected() {
        #expect(BackendDate.date(from: "") == nil)
        #expect(BackendDate.date(from: "yesterday") == nil)
    }

    // MARK: - Days on the wire

    /// A Postgres `date` is exactly what `ForgeDay` is: a civil date with no
    /// timezone in it, which is the whole reason a streak survives a flight.
    @Test("A day round-trips through its date column")
    func dayRoundTrip() throws {
        let day = ForgeDay(year: 2026, month: 8, day: 4)
        #expect(day.isoString == "2026-08-04")
        #expect(ForgeDay(isoString: "2026-08-04") == day)
        // Postgres may render the column with a time appended.
        #expect(ForgeDay(isoString: "2026-08-04T00:00:00+00:00") == day)
    }

    @Test("A year is not grouped with a comma")
    func yearIsNotFormatted() {
        #expect(ForgeDay(year: 2026, month: 1, day: 9).isoString == "2026-01-09")
    }

    @Test("An unreadable day is nil rather than a guess")
    func badDaysAreRejected() {
        #expect(ForgeDay(isoString: "not-a-date") == nil)
        #expect(ForgeDay(isoString: "2026-13-04") == nil)
        #expect(ForgeDay(isoString: "2026-08") == nil)
    }

    // MARK: - Rows

    /// The server owns `synced_at` and the client must never send it: the
    /// column is `not null`, and a client-authored value would corrupt the
    /// cursor every device pages through history with.
    @Test("An upload never carries synced_at")
    func syncedAtIsNeverSent() throws {
        let row = DayRow(
            userID: "u",
            record: DayRecord(
                day: ForgeDay(year: 2026, month: 8, day: 4),
                completions: [],
                plannedIDs: ["push"],
                extractedAt: nil,
                updatedAt: Date()
            )
        )
        let encoded = try BackendJSON.encoder.encode(row)
        let object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        #expect(object["synced_at"] == nil)
        #expect(object["user_id"] as? String == "u")
        #expect(object["day"] as? String == "2026-08-04")
    }

    @Test("A day survives the wire")
    func morningRoundTrip() throws {
        let original = DayRecord(
            day: ForgeDay(year: 2026, month: 8, day: 4),
            completions: [
                DayRecord.Completion(
                    ritualID: "push", method: .honor,
                    at: Date(timeIntervalSince1970: 1_800_000_100)
                ),
            ],
            plannedIDs: ["push", "read"],
            extractedAt: Date(timeIntervalSince1970: 1_800_000_200),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_300)
        )

        let encoded = try BackendJSON.encoder.encode(DayRow(userID: "u", record: original))
        // The server echoes synced_at back; decoding has to accept it.
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["synced_at"] = "2026-08-04T06:00:00.000+00:00"
        let withCursor = try JSONSerialization.data(withJSONObject: object)

        let decoded = try BackendJSON.decoder.decode(DayRow.self, from: withCursor)
        let record = try #require(decoded.record)

        #expect(record.day == original.day)
        #expect(record.plannedIDs == original.plannedIDs)
        #expect(record.completions.map(\.ritualID) == ["push"])
        #expect(record.completions.first?.method == .honor)
        #expect(decoded.syncedAt != nil)
    }

    /// A verification mode written by an older build must not throw, because
    /// one throw fails the whole array and takes the pull with it.
    @Test("An unknown verification mode decodes as honor")
    func unknownVerificationIsTolerated() throws {
        let json = """
        {"user_id":"u","id":"custom.a","label":"Pray","verification":"aiVerified",
         "is_custom":true,"is_deleted":false,"updated_at":"2026-08-04T05:00:00Z"}
        """
        let row = try BackendJSON.decoder.decode(ActivityRow.self, from: Data(json.utf8))
        #expect(row.verification == .honor)
    }

    // MARK: - Failures

    /// Offline-first is a decision about which failures are worth waiting out.
    /// Made once, here, rather than differently at each call site.
    @Test("Only the failures worth waiting out are retried")
    func retryClassification() {
        #expect(BackendError.offline.isRetryable)
        #expect(BackendError.timedOut.isRetryable)
        #expect(BackendError.server(status: 503).isRetryable)
        #expect(BackendError.rateLimited(retryAfter: 30).isRetryable)

        // A 403 means we asked for somebody else's rows, which is a bug here
        // rather than a condition to wait out.
        #expect(!BackendError.forbidden.isRetryable)
        #expect(!BackendError.unauthorized.isRetryable)
        #expect(!BackendError.decoding.isRetryable)
        #expect(!BackendError.notConfigured.isRetryable)
        #expect(!BackendError.signInCancelled.isRetryable)
    }

    @Test("A rate limit hands back the server's own wait")
    func retryHint() {
        #expect(BackendError.rateLimited(retryAfter: 90).retryHint == 90)
        #expect(BackendError.offline.retryHint == nil)
    }

    // MARK: - Backoff

    @Test("Backoff doubles and then stops")
    func backoffSchedule() {
        #expect(SyncBackoff.delay(afterFailures: 0) == 0)
        #expect(SyncBackoff.delay(afterFailures: 1) == 30)
        #expect(SyncBackoff.delay(afterFailures: 2) == 60)
        #expect(SyncBackoff.delay(afterFailures: 3) == 120)
        #expect(SyncBackoff.delay(afterFailures: 6) == 960)
    }

    /// A phone that comes back into signal should find its way to the server
    /// within one window, not one nap.
    @Test("Backoff never exceeds half an hour")
    func backoffIsCapped() {
        for failures in 7...200 {
            #expect(SyncBackoff.delay(afterFailures: failures) == SyncBackoff.ceiling)
        }
    }

    // MARK: - Batching

    /// Postgres will take a very large insert and the network will not, and a
    /// day lost to a request that was too big to send is a poor way to find
    /// that out.
    @Test("Uploads are chunked without losing or duplicating a row")
    func chunking() {
        let rows = Array(1...1201)
        let chunks = rows.chunked(into: 500)

        #expect(chunks.count == 3)
        #expect(chunks.map(\.count) == [500, 500, 201])
        #expect(chunks.flatMap { $0 } == rows)
        #expect([Int]().chunked(into: 500).isEmpty)
    }

    // MARK: - PKCE

    /// The verifier never leaves the process, and the challenge is worthless
    /// without it. Both have to be the shape RFC 7636 asks for or the exchange
    /// is simply refused.
    @Test("A PKCE pair is URL-safe and long enough")
    func pkceShape() {
        let pkce = AuthCrypto.makePKCE()
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

        #expect((43...128).contains(pkce.verifier.count))
        #expect(pkce.verifier.unicodeScalars.allSatisfy(allowed.contains))
        #expect(pkce.challenge.unicodeScalars.allSatisfy(allowed.contains))
        #expect(!pkce.challenge.contains("="))
        #expect(pkce.challenge != pkce.verifier)
    }

    @Test("Every sign-in gets its own verifier and nonce")
    func secretsAreFresh() {
        #expect(AuthCrypto.makePKCE().verifier != AuthCrypto.makePKCE().verifier)
        #expect(AuthCrypto.makeNonce() != AuthCrypto.makeNonce())
    }

    /// Apple hashes and compares the exact string we hand it, so this has to be
    /// lowercase hex of the raw nonce and nothing else.
    @Test("The nonce hash is lowercase hex")
    func nonceHash() {
        let hashed = AuthCrypto.sha256Hex("forge")
        #expect(hashed.count == 64)
        #expect(hashed.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        #expect(AuthCrypto.sha256Hex("forge") == hashed)
        #expect(AuthCrypto.sha256Hex("forgе") != hashed)
    }

    // MARK: - The callback

    @Test("An authorization code is read off the callback")
    func callbackCode() throws {
        let url = try #require(URL(string: "forge://auth-callback?code=abc123"))
        #expect(OAuthCallback(url: url).code == "abc123")
    }

    /// A provider that answered with an error instead of a code must not be
    /// mistaken for a successful sign-in with an empty code.
    @Test("A refusal is not a code")
    func callbackError() throws {
        let url = try #require(
            URL(string: "forge://auth-callback?error=access_denied&error_description=No")
        )
        let callback = OAuthCallback(url: url)
        #expect(callback.code == nil)
        #expect(callback.error == "No")
    }

    @Test("An implicit-flow answer in the fragment is still read")
    func callbackFragment() throws {
        let url = try #require(URL(string: "forge://auth-callback#error=server_error"))
        #expect(OAuthCallback(url: url).error == "server_error")
    }

    // MARK: - Session expiry

    /// A token that is valid when the request is built and expired when it
    /// arrives produces a 401 that looks exactly like a revoked session.
    @Test("A token is spent before it actually expires")
    func refreshMargin() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let session = AuthSession(
            userID: "u", accessToken: "a", refreshToken: "r",
            expiresAt: now.addingTimeInterval(60),
            provider: .apple, email: nil
        )

        #expect(!session.isExpired(now: now))
        #expect(session.needsRefresh(now: now), "inside the margin")
    }

    @Test("A fresh token is left alone")
    func freshTokenIsKept() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let session = AuthSession(
            userID: "u", accessToken: "a", refreshToken: "r",
            expiresAt: now.addingTimeInterval(3600),
            provider: .google, email: "a@b.c"
        )

        #expect(!session.needsRefresh(now: now))
    }

    /// A provider the app has not heard of must still sign somebody in; only
    /// the label in Settings is vaguer.
    @Test("An unknown provider is a label, not a failure")
    func unknownProvider() {
        #expect(AuthProvider(rawValue: "apple") == .apple)
        #expect(AuthProvider(rawValue: "Google") == .google)
        #expect(AuthProvider(rawValue: "azure") == .unknown)
    }
}

// MARK: - AI without an account (§2q)

/// The invisible anonymous identity, the proof of purchase, and the header the
/// function reads it from — against a scripted transport, so nothing here
/// touches a network.
@Suite("AI without an account")
struct AnonymousAITests {

    private let config = SupabaseConfig(
        url: URL(string: "https://example.supabase.co")!,
        anonKey: "sb_publishable_test"
    )

    private func session(_ access: String, refresh: String) -> String {
        """
        {"access_token":"\(access)","refresh_token":"\(refresh)","expires_in":3600,\
        "user":{"id":"8f7c0e2a-0000-4000-8000-00000000000a","app_metadata":{"provider":"anonymous"}}}
        """
    }

    private func identity(
        _ transport: ScriptedTransport,
        store: InMemorySessionStore = InMemorySessionStore(),
        clock: TestClock = TestClock()
    ) -> AnonymousIdentity {
        AnonymousIdentity(
            api: SupabaseAuthAPI(client: HTTPClient(config: config, transport: transport)),
            store: store,
            now: { clock.now }
        )
    }

    @Test("With no project configured there is no identity and no request")
    func unconfiguredIsInert() async {
        let store = InMemorySessionStore()
        let identity = AnonymousIdentity(api: nil, store: store)
        #expect(await identity.accessToken() == nil)
        #expect(store.load() == nil)
    }

    @Test("The first token signs up anonymously — no email, no password — and is kept")
    func firstTokenSignsUpAnonymously() async throws {
        let transport = ScriptedTransport([.json(200, session("a1", refresh: "r1"))])
        let store = InMemorySessionStore()
        let identity = identity(transport, store: store)

        #expect(await identity.accessToken() == "a1")

        let sent = try #require(transport.requests.first)
        #expect(sent.httpMethod == "POST")
        #expect(sent.url?.path.hasSuffix("/auth/v1/signup") == true)
        #expect(sent.httpBody.flatMap { String(data: $0, encoding: .utf8) } == "{}")

        let kept = try #require(store.load())
        #expect(kept.provider == .anonymous)
        #expect(kept.email == nil)
        #expect(kept.accessToken == "a1")

        // Cached: no second request while it is fresh.
        #expect(await identity.accessToken() == "a1")
        #expect(transport.requests.count == 1)
    }

    @Test("A stale token is refreshed, not replaced")
    func staleTokenRefreshes() async throws {
        let transport = ScriptedTransport([
            .json(200, session("a1", refresh: "r1")),
            .json(200, session("a2", refresh: "r2")),
        ])
        let clock = TestClock()
        let identity = identity(transport, clock: clock)

        #expect(await identity.accessToken() == "a1")
        clock.advance(by: 3600)
        #expect(await identity.accessToken() == "a2")

        let refresh = try #require(transport.requests.last?.url)
        #expect(refresh.path.hasSuffix("/auth/v1/token"))
        #expect(refresh.query?.contains("grant_type=refresh_token") == true)
    }

    @Test("A refused refresh mints a new identity; an offline one keeps the old")
    func refreshFailures() async throws {
        let clock = TestClock()

        let refused = ScriptedTransport([
            .json(200, session("a1", refresh: "r1")),
            .json(400, #"{"error_description":"Invalid Refresh Token"}"#),
            .json(200, session("b1", refresh: "s1")),
        ])
        let fresh = identity(refused, clock: clock)
        #expect(await fresh.accessToken() == "a1")
        clock.advance(by: 3600)
        #expect(await fresh.accessToken() == "b1")
        #expect(refused.requests.last?.url?.path.hasSuffix("/auth/v1/signup") == true)

        let store = InMemorySessionStore()
        let offline = ScriptedTransport([.json(200, session("a1", refresh: "r1")), .offline])
        let kept = identity(offline, store: store, clock: clock)
        #expect(await kept.accessToken() == "a1")
        clock.advance(by: 3600)
        #expect(await kept.accessToken() == nil)
        #expect(store.load()?.refreshToken == "r1")
    }

    @Test("Anonymous sign-ins switched off on the server is simply no token")
    func signUpRefused() async {
        let transport = ScriptedTransport([.json(422, #"{"msg":"Anonymous sign-ins are disabled"}"#)])
        #expect(await identity(transport).accessToken() == nil)
    }

    @Test("Two requests at once mint one identity")
    func concurrentCallersShareOneSignUp() async {
        let transport = ScriptedTransport([.json(200, session("a1", refresh: "r1"))], delay: .milliseconds(50))
        let identity = identity(transport)
        async let first = identity.accessToken()
        async let second = identity.accessToken()
        let tokens = await [first, second]
        #expect(tokens == ["a1", "a1"])
        #expect(transport.requests.count == 1)
    }

    @Test("The anonymous provider is its own case")
    func anonymousProvider() {
        #expect(AuthProvider(rawValue: "anonymous") == .anonymous)
    }

    // MARK: The proof of purchase

    private func candidate(
        _ product: PremiumProduct?, expires: TimeInterval? = nil, revoked: Bool = false, jws: String
    ) -> EntitlementCandidate {
        EntitlementCandidate(
            productID: product?.rawValue ?? "com.dawid.forge.tip",
            expirationDate: expires.map { Date(timeIntervalSince1970: 1_000_000 + $0) },
            revocationDate: revoked ? Date(timeIntervalSince1970: 1) : nil,
            jws: jws
        )
    }

    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("No Premium, no proof")
    func noPremiumNoProof() {
        #expect(ForgeStore.bestProof(among: [], now: now) == nil)
        #expect(ForgeStore.bestProof(among: [candidate(nil, jws: "tip")], now: now) == nil)
    }

    @Test("Lifetime is preferred; revoked and expired are never sent")
    func proofChoice() {
        let annual = candidate(.annual, expires: 86_400, jws: "annual")
        let lifetime = candidate(.lifetime, jws: "lifetime")
        #expect(ForgeStore.bestProof(among: [annual, lifetime], now: now) == "lifetime")
        #expect(ForgeStore.bestProof(among: [annual], now: now) == "annual")
        #expect(ForgeStore.bestProof(among: [candidate(.annual, expires: -1, jws: "old")], now: now) == nil)
        #expect(ForgeStore.bestProof(among: [candidate(.lifetime, revoked: true, jws: "refunded")], now: now) == nil)
        #expect(ForgeStore.bestProof(
            among: [candidate(.annual, expires: 10, jws: "short"), candidate(.annual, expires: 99, jws: "long")],
            now: now
        ) == "long")
    }

    // MARK: The request

    /// What goes up: the anonymous JWT as the bearer, the transaction in its
    /// own header, and a body that says nothing about who is asking.
    @Test("A model request carries the JWT and X-Forge-Transaction, and the body names nobody")
    func requestShape() async throws {
        let transport = ScriptedTransport([.json(200, #"{"observation":"Four of five Mondays."}"#)])
        let endpoint = AIEndpoint(config: config, client: HTTPClient(config: config, transport: transport))
        var brief = AIBrief()
        brief.week = ReviewFacts(kept: 4, asked: 5)

        let reading = try await endpoint.reading(
            AIRequest(task: .reading, brief: AIWireBrief(brief)),
            credentials: AICredentials(token: "anon-jwt", transaction: "signed.jws.value")
        )
        #expect(reading.observation == "Four of five Mondays.")

        let sent = try #require(transport.requests.first)
        #expect(sent.url?.path.hasSuffix("/functions/v1/forge-ai") == true)
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer anon-jwt")
        #expect(sent.value(forHTTPHeaderField: "X-Forge-Transaction") == "signed.jws.value")
        let body = try #require(sent.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(body.contains("\"task\":\"reading\""))
        #expect(!body.contains("originalTransactionId"))
        #expect(!body.contains("signed.jws.value"))
        #expect(!body.contains("challenge"))
    }
}

/// Answers in order, and writes down what it was asked.
final class ScriptedTransport: BackendTransport, @unchecked Sendable {
    enum Reply {
        case json(Int, String)
        case offline
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private var sent: [URLRequest] = []
    private let delay: Duration?

    init(_ replies: [Reply], delay: Duration? = nil) {
        self.replies = replies
        self.delay = delay
    }

    var requests: [URLRequest] { lock.withLock { sent } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply = lock.withLock {
            sent.append(request)
            return replies.isEmpty ? .offline : replies.removeFirst()
        }
        if let delay { try await Task.sleep(for: delay) }
        switch reply {
        case .offline:
            throw BackendError.offline
        case .json(let status, let body):
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (Data(body.utf8), response)
        }
    }
}

final class InMemorySessionStore: AnonymousSessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var session: AuthSession?

    func load() -> AuthSession? { lock.withLock { session } }
    func save(_ session: AuthSession) { lock.withLock { self.session = session } }
    func clear() { lock.withLock { session = nil } }
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 2_000_000_000)

    var now: Date { lock.withLock { current } }
    func advance(by seconds: TimeInterval) { lock.withLock { current += seconds } }
}

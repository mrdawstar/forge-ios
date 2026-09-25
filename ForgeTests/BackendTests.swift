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

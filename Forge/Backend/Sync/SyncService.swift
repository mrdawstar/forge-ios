import Foundation

/// Keeps a practice in two places without ever making the day wait.
///
/// Everything here is arranged around one rule: the network is never on the
/// path of anything a person is doing. Local writes happen first and are never
/// conditional on a request; a sync that fails leaves the phone exactly as
/// correct as it was; and there is no code path anywhere in the app that awaits
/// this class before drawing something.
///
/// The order of operations is the other half of that promise. Pull, merge,
/// **apply locally**, then push — with the cursors only moving once all of it
/// worked. A push that fails halfway leaves a device that has already taken on
/// everything the server told it, and a watermark that still describes the
/// upload as outstanding, so the next attempt sends it again. Upserts make
/// sending it again free.
@MainActor
@Observable
final class SyncService {

    // MARK: - What it is doing

    enum Status: Equatable {
        /// Signed out, free, or a build with no backend. The ordinary state for
        /// most people, and not a problem.
        case unavailable
        case idle
        case syncing
        case succeeded(at: Date)
        /// A retryable failure. Nothing to do and nothing to say — it will go
        /// again by itself.
        case waiting(until: Date)
        /// Something that retrying cannot fix.
        case failed(String)
    }

    private(set) var status: Status = .unavailable
    private(set) var lastSyncedAt: Date?

    /// Whether there is anything to sync at all.
    ///
    /// Signing in is free; keeping a copy in the cloud is what Premium buys. A
    /// free account still exists on the server — that is what makes upgrading
    /// later work — it just holds nothing but the account.
    var isEnabled: Bool { api != nil && auth.isSignedIn && isPremium() }

    // MARK: - Collaborators

    private let api: SupabaseDataAPI?
    private let auth: AuthService
    private let ledger: SyncLedger
    private let bridge: PracticeBridge
    /// A closure rather than the store itself. The entitlement is StoreKit's
    /// answer and this class has no business holding the thing that produces
    /// it — and a closure is what lets the whole engine be tested without a
    /// sandbox account.
    private let isPremium: () -> Bool

    private var runInFlight: Task<Void, Never>?
    private var debounce: Task<Void, Never>?
    private var failures = 0
    private var retryNotBefore: Date?

    init(
        api: SupabaseDataAPI?,
        auth: AuthService,
        bridge: PracticeBridge,
        ledger: SyncLedger = SyncLedger(),
        isPremium: @escaping () -> Bool
    ) {
        self.api = api
        self.auth = auth
        self.bridge = bridge
        self.ledger = ledger
        self.isPremium = isPremium
    }

    // MARK: - Asking for a sync

    /// Go now, if there is anything to go for.
    ///
    /// Fire and forget by design: every caller of this — the app coming
    /// forward, a blade coming free, a purchase landing — is somewhere that
    /// must not be made to wait, and none of them has anything useful to do
    /// with the answer.
    func syncNow() {
        guard isEnabled else {
            status = .unavailable
            return
        }
        guard runInFlight == nil else { return }
        if let retryNotBefore, Date() < retryNotBefore { return }

        runInFlight = Task { [weak self] in
            await self?.run()
            self?.runInFlight = nil
        }
    }

    /// Go shortly, and only once however many times this is called.
    ///
    /// For the small changes that arrive in bursts — reordering a day,
    /// ticking three activities off in twenty seconds. Uploading each one would
    /// be a request per tap for a value that is going to change again before
    /// anybody looks at it on another device.
    func syncSoon(after delay: TimeInterval = 8) {
        guard isEnabled else { return }
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.syncNow()
        }
    }

    /// Everything a sign-out should forget.
    ///
    /// The cursors and the watermark only. The practice itself is untouched,
    /// because it was never the account's.
    func forgetAccount() {
        debounce?.cancel()
        runInFlight?.cancel()
        runInFlight = nil
        failures = 0
        retryNotBefore = nil
        status = .unavailable
    }

    // MARK: - The pass

    private func run() async {
        guard let api, let userID = auth.userID else {
            status = .unavailable
            return
        }
        status = .syncing

        do {
            let token = try await auth.validAccessToken()

            // A first sign-in or a different account on the same phone. Either
            // way there is no delta to ask for — the whole history has to come
            // down before anything sensible can be said about it. What the two
            // cases differ on is whether the practice already on this phone
            // counts as unsent, and `adopt` is where that is decided.
            let adoption = ledger.adopt(userID: userID)
            let since = adoption == .unchanged ? ledger.pullCursor : nil

            let pulled = try await pull(api, since: since, token: token)

            // Taken before the snapshot, not after. Anything the user changes
            // while this pass is in the air has a stamp later than this and
            // stays dirty for the next one.
            let watermark = Date()
            let local = bridge.snapshot()

            let merge = SyncMerge.merge(
                local: local,
                remote: pulled.practice,
                pushedThrough: ledger.pushedThrough,
                // A different account on a phone that has already handed its
                // practice to another one. The watermark alone cannot express
                // that: it stops untouched local rows being *offered*, but two
                // people's versions of the same Tuesday would still be merged
                // into one and sent up, because a merge that beats the server
                // always is.
                localIsForeign: adoption == .switched
            )

            // Local first, and before the upload. If the network dies on the
            // next line, this device has still gained everything the server
            // knew, and the upload is still outstanding — which is the correct
            // way round to fail.
            if merge.practice != local {
                bridge.apply(merge.practice)
                restamp(merge.practice)
            }

            try await push(api, merge.upload, userID: userID, token: token)

            // Only now. A cursor moved before the work it describes is how a
            // sync engine forgets a day it never actually sent.
            if let cursor = pulled.cursor { ledger.pullCursor = cursor }
            ledger.pushedThrough = watermark
            if ledger.migratedUserID == nil { ledger.migratedUserID = userID }

            failures = 0
            retryNotBefore = nil
            lastSyncedAt = .now
            status = .succeeded(at: .now)

        } catch let error as BackendError where error.isRetryable {
            failures += 1
            let delay = error.retryHint ?? SyncBackoff.delay(afterFailures: failures)
            let until = Date().addingTimeInterval(delay)
            retryNotBefore = until
            status = .waiting(until: until)
            scheduleRetry(after: delay)

        } catch BackendError.unauthorized {
            // The session is gone. `AuthService` has already recorded that;
            // there is nothing here to retry and nothing to alarm anybody with,
            // because the practice on this phone is untouched.
            status = .unavailable

        } catch {
            failures += 1
            status = .failed("Your practice is safe on this phone. Syncing will try again later.")
            scheduleRetry(after: SyncBackoff.delay(afterFailures: failures))
        }
    }

    /// A timer for the case where the app stays open.
    ///
    /// Not the main mechanism, and deliberately not something the app depends
    /// on: a backgrounded phone runs no timers, and the retry that actually
    /// matters is the one on the next foreground.
    private func scheduleRetry(after delay: TimeInterval) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            // Cleared rather than waited past. Sleeping for exactly the backoff
            // and then testing `now >= retryNotBefore` is a coin flip on the
            // last microsecond, and losing it means this retry silently does
            // nothing and the next one is a foreground away.
            self?.clearRetryGate()
            self?.syncNow()
        }
    }

    private func clearRetryGate() { retryNotBefore = nil }

    // MARK: - Pull

    private struct Pulled {
        var practice: RemotePractice
        /// The newest arrival time seen, across every table. Nil when nothing
        /// came back, which leaves the cursor where it was.
        ///
        /// Note what that means for the pass that uploads a whole history: the
        /// server's arrival time for those rows is not in any response, because
        /// the upload asks for `return=minimal`, so the cursor does not move
        /// and the *next* sync downloads the history it just sent. That is one
        /// redundant download of a few hundred kilobytes, once, and it settles
        /// to nothing — the merge finds every row identical and uploads
        /// nothing. Avoiding it would mean either a probe request per table or
        /// trusting our own clock against the server's, and neither is worth
        /// buying a saving that only ever applies once per phone.
        var cursor: Date?
    }

    private func pull(
        _ api: SupabaseDataAPI,
        since: Date?,
        token: String
    ) async throws -> Pulled {
        var practice = RemotePractice()
        var cursor: Date?

        func advance(_ rows: [some SyncedRow]) {
            for row in rows {
                guard let at = row.syncedAt else { continue }
                cursor = max(cursor ?? at, at)
            }
        }

        let profiles = try await api.pullAll(
            ProfileRow.self, from: .profiles, since: since, accessToken: token
        )
        advance(profiles)
        // A placeholder is not an answer about anybody's settings — see
        // `ProfileRow.isPlaceholder`. Dropped here rather than in the merge, so
        // that "the server has nothing to say about this" has exactly one
        // spelling downstream: nil.
        practice.settings = profiles.last.flatMap { $0.isPlaceholder ? nil : $0.settings }

        let rituals = try await api.pullAll(
            RitualRow.self, from: .rituals, since: since, accessToken: token
        )
        advance(rituals)
        practice.arrangement = rituals
            .first { $0.id == RitualRow.dayRitualID }?
            .arrangement

        let blades = try await api.pullAll(
            BladeRow.self, from: .blades, since: since, accessToken: token
        )
        advance(blades)
        practice.blades = blades.last?.blades

        let activities = try await api.pullAll(
            ActivityRow.self, from: .activities, since: since, accessToken: token
        )
        advance(activities)
        practice.activities = activities.map(\.definition)

        let identities = try await api.pullAll(
            IdentityRow.self, from: .identities, since: since, accessToken: token
        )
        advance(identities)
        practice.identities = identities.map(\.definition)

        let chapters = try await api.pullAll(
            ChapterRow.self, from: .chapters, since: since, accessToken: token
        )
        advance(chapters)
        practice.chapters = chapters.map(\.chapter)

        let reviews = try await api.pullAll(
            ReviewRow.self, from: .reviews, since: since, accessToken: token
        )
        advance(reviews)
        // A row whose week will not parse is dropped rather than thrown on, the
        // same rule the days follow below.
        practice.reviews = reviews.compactMap(\.review)

        let days = try await api.pullAll(
            DayRow.self, from: .days, since: since, accessToken: token
        )
        advance(days)
        // A row whose date will not parse is dropped rather than thrown on. One
        // unreadable day must not cost somebody the other nine hundred.
        practice.days = days.compactMap(\.record)

        return Pulled(practice: practice, cursor: cursor)
    }

    // MARK: - Push

    private func push(
        _ api: SupabaseDataAPI,
        _ upload: UploadSet,
        userID: String,
        token: String
    ) async throws {
        guard !upload.isEmpty else { return }

        if let settings = upload.settings {
            try await api.upsert(
                [ProfileRow(userID: userID, settings: settings)],
                into: .profiles, accessToken: token
            )
        }
        if !upload.activities.isEmpty {
            try await api.upsert(
                upload.activities.map { ActivityRow(userID: userID, definition: $0) },
                into: .activities, accessToken: token
            )
        }
        if let arrangement = upload.arrangement {
            try await api.upsert(
                [RitualRow(userID: userID, arrangement: arrangement)],
                into: .rituals, accessToken: token
            )
        }
        // Before the days, deliberately. A day can refer to an activity tagged
        // to an identity, so the identity should exist server-side first —
        // nothing enforces that with a foreign key, and it costs nothing to
        // send them in the order that would survive one being added.
        if !upload.identities.isEmpty {
            try await api.upsert(
                upload.identities.map { IdentityRow(userID: userID, definition: $0) },
                into: .identities, accessToken: token
            )
        }
        if !upload.chapters.isEmpty {
            try await api.upsert(
                upload.chapters.map { ChapterRow(userID: userID, chapter: $0) },
                into: .chapters, accessToken: token
            )
        }
        if !upload.reviews.isEmpty {
            try await api.upsert(
                upload.reviews.map { ReviewRow(userID: userID, review: $0) },
                into: .reviews, accessToken: token
            )
        }
        if !upload.days.isEmpty {
            try await api.upsert(
                upload.days.map { DayRow(userID: userID, record: $0) },
                into: .days, accessToken: token
            )
        }
        if let blades = upload.blades {
            try await api.upsert(
                [BladeRow(userID: userID, blades: blades)],
                into: .blades, accessToken: token
            )
        }
    }

    // MARK: - After applying

    /// Tell the ledger that the values it is about to see are as old as the
    /// merge said they were.
    ///
    /// Without this the engine never settles. `apply` changes the content of
    /// three small values, the ledger notices content it has not seen before,
    /// stamps it *now*, and the next pass finds three dirty values it has just
    /// this second received from the server — which it dutifully sends back.
    /// Two phones would then push the same three rows at each other for as long
    /// as they both had signal.
    private func restamp(_ practice: LocalPractice) {
        ledger.setStamp(
            for: SyncLedger.StampKey.settings,
            fingerprint: practice.settings.fingerprint,
            at: practice.settings.updatedAt
        )
        ledger.setStamp(
            for: SyncLedger.StampKey.arrangement,
            fingerprint: practice.arrangement.fingerprint,
            at: practice.arrangement.updatedAt
        )
        ledger.setStamp(
            for: SyncLedger.StampKey.blades,
            fingerprint: practice.blades.fingerprint,
            at: practice.blades.updatedAt
        )
        for definition in practice.activities {
            ledger.setStamp(
                for: SyncLedger.StampKey.activity(definition.id),
                fingerprint: definition.fingerprint,
                at: definition.updatedAt
            )
        }
        for definition in practice.identities {
            ledger.setStamp(
                for: SyncLedger.StampKey.identity(definition.id),
                fingerprint: definition.fingerprint,
                at: definition.updatedAt
            )
        }
    }
}

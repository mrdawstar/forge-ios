import Foundation
import Testing
@testable import Forge

/// The findings from the pre-TestFlight audit, each one held down by a test.
///
/// Every case here failed before its fix and passes after it. They are kept
/// together because they have one thing in common: all of them are invisible
/// from inside the app. Nothing here can be checked by using Forge — the cases
/// need two phones, two accounts, a fortnight, or a brand-new server row — which
/// is exactly why they survived to be found by an audit.
@Suite("Backend regressions")
struct BackendRegressionTests {

    private func ledger(_ name: String) -> SyncLedger {
        SyncLedger(
            defaults: UserDefaults(suiteName: "forge.regress.\(name).\(UUID().uuidString)")
                ?? .standard
        )
    }

    private func day(_ d: Int) -> ForgeDay { ForgeDay(year: 2026, month: 8, day: d) }

    private func record(
        _ d: Int, done: [String] = [], planned: [String] = [],
        at when: Date, updatedAt: Date
    ) -> DayRecord {
        DayRecord(
            day: day(d),
            completions: done.map { DayRecord.Completion(ritualID: $0, method: .honor, at: when) },
            plannedIDs: planned,
            extractedAt: nil,
            updatedAt: updatedAt
        )
    }

    // MARK: - The names that may never change

    /// Identifiers that look like labels and are not.
    ///
    /// Each one is written down somewhere this app does not control — a
    /// deployed Postgres table, a row id in somebody else's database. Renaming
    /// either of them during the move from mornings to days would have been
    /// silent, and would have broken a stranger's phone rather than a build.
    @Test("The persisted identifiers still spell what is actually deployed")
    func persistedIdentifiersArePinned() {
        #expect(SupabaseDataAPI.Table.days.rawValue == "mornings", "the deployed table")
        #expect(RitualRow.dayRitualID == "morning", "the deployed ritual row id")
    }

    /// The third name on that list used to be a notification identifier, and it
    /// was pinned for a good reason: iOS keeps pending requests across an
    /// update, and a build that cancelled by name could never cancel one it had
    /// never heard of. Two reminders a day, forever, on every phone that
    /// upgraded.
    ///
    /// It is not pinned any more because the mechanism changed rather than the
    /// hazard being forgotten: a scheduling pass now clears **everything**
    /// pending before it writes — see `ForgeNotifications.cancelAll` — so a
    /// request from any older build is swept on the first refresh. What has to
    /// stay true is the other half: those old identifiers must not be mistaken
    /// for something this build understands.
    @Test("Identifiers from older builds are unrecognised rather than misread")
    func retiredIdentifiersAreNotMisread() {
        for retired in [
            "forge.notification.morning.v1",
            "forge.notification.nudge.v1",
            "forge.notification.evening.v1",
        ] {
            #expect(ForgeNotification(identifier: retired) == nil)
        }
    }

    // MARK: - C1: arriving on a new phone

    /// A fresh install signing into an account with a year behind it.
    ///
    /// The install's factory defaults used to be dated the moment the ledger
    /// first looked at them, which is always newer than a choice made last
    /// spring — so they won the merge and were then uploaded, resetting the
    /// account on every device.
    @Test("A new phone takes the account's settings rather than overwriting them")
    func newPhoneRestores() {
        let ledger = ledger(#function)
        #expect(ledger.adopt(userID: "alice") == .first)

        var settings = LocalPractice.Settings(
            dayStartHour: 4, restWeekdays: [], firstRunCompleted: false,
            verificationMemory: .empty, updatedAt: .distantPast
        )
        settings.updatedAt = ledger.stamp(
            for: SyncLedger.StampKey.settings, fingerprint: settings.fingerprint
        )
        #expect(settings.updatedAt == .distantPast, "a first look is not an edit")

        var arrangement = LocalPractice.Arrangement(
            activityIDs: ["water", "move", "read"], updatedAt: .distantPast
        )
        arrangement.updatedAt = ledger.stamp(
            for: SyncLedger.StampKey.arrangement, fingerprint: arrangement.fingerprint
        )
        var blades = LocalPractice.Blades(
            equippedID: 1, acknowledgedIDs: [], celebratedIDs: [], updatedAt: .distantPast
        )
        blades.updatedAt = ledger.stamp(
            for: SyncLedger.StampKey.blades, fingerprint: blades.fingerprint
        )

        let months = Date.now.addingTimeInterval(-90 * 86_400)
        let merged = SyncMerge.merge(
            local: LocalPractice(
                settings: settings, activities: [], arrangement: arrangement,
                days: [], blades: blades
            ),
            remote: RemotePractice(
                settings: LocalPractice.Settings(
                    dayStartHour: 6, restWeekdays: [1, 7], firstRunCompleted: true,
                    verificationMemory: .empty, updatedAt: months
                ),
                activities: [],
                arrangement: LocalPractice.Arrangement(
                    activityIDs: ["cold-shower", "pages"], updatedAt: months
                ),
                days: [],
                blades: LocalPractice.Blades(
                    equippedID: 6, acknowledgedIDs: [1, 2, 3], celebratedIDs: [1],
                    updatedAt: months
                )
            ),
            pushedThrough: ledger.pushedThrough
        )

        #expect(merged.practice.settings.dayStartHour == 6)
        #expect(merged.practice.settings.restWeekdays == [1, 7])
        #expect(merged.practice.arrangement.activityIDs == ["cold-shower", "pages"])
        #expect(merged.practice.blades.equippedID == 6)
        #expect(merged.practice.settings.firstRunCompleted, "onboarding must not replay")
        #expect(merged.upload.settings == nil, "the account was overwritten from a new phone")
        #expect(merged.upload.arrangement == nil)
    }

    /// The other half, which the fix above could have broken: somebody who has
    /// kept days on this phone for a year, signing in for the first time.
    @Test("A local-only practice still migrates into a brand-new account")
    func localOnlyPracticeStillMigrates() {
        let ledger = ledger(#function)
        ledger.adopt(userID: "alice")

        var settings = LocalPractice.Settings(
            dayStartHour: 6, restWeekdays: [1, 7], firstRunCompleted: true,
            verificationMemory: .empty, updatedAt: .distantPast
        )
        settings.updatedAt = ledger.stamp(
            for: SyncLedger.StampKey.settings, fingerprint: settings.fingerprint
        )

        // A brand-new account: the signup trigger's placeholder row is read as
        // an absence, so there is nothing on the server to lose to.
        let merged = SyncMerge.merge(
            local: LocalPractice(
                settings: settings, activities: [],
                arrangement: LocalPractice.Arrangement(
                    activityIDs: ["water"], updatedAt: .distantPast
                ),
                days: [],
                blades: LocalPractice.Blades(
                    equippedID: 1, acknowledgedIDs: [], celebratedIDs: [],
                    updatedAt: .distantPast
                )
            ),
            remote: RemotePractice(),
            pushedThrough: ledger.pushedThrough
        )
        #expect(merged.practice.settings.dayStartHour == 6, "their day start was reset")
        #expect(merged.upload.settings?.dayStartHour == 6, "their settings never went up")
    }

    /// The row the signup trigger writes, exactly as it writes it.
    ///
    /// `verification_memory` defaults to `'{}'`, and a synthesised decoder does
    /// not fall back to property defaults — so this threw, the throw was a
    /// schema error, schema errors are permanent, and no new account could ever
    /// sync. The pull throws before anything is pushed, so it could not recover.
    @Test("A profile row as the signup trigger creates it decodes")
    func triggerCreatedProfileDecodes() throws {
        let json = """
        [{"id":"11111111-2222-3333-4444-555555555555","day_start_hour":4,
          "rest_weekdays":[],"first_run_completed":false,"verification_memory":{},
          "updated_at":"1970-01-01T00:00:00+00:00",
          "synced_at":"2026-08-04T06:00:00.123456+00:00"}]
        """
        let rows = try BackendJSON.decoder.decode([ProfileRow].self, from: Data(json.utf8))
        #expect(rows.count == 1)
        #expect(rows[0].verificationMemory == .empty)
        #expect(rows[0].isPlaceholder, "the trigger's row must read as an absence")
    }

    @Test("Only the signup placeholder reads as an absence")
    func placeholderIsExact() throws {
        func row(_ updatedAt: String) throws -> ProfileRow {
            let json = """
            {"id":"u","day_start_hour":4,"rest_weekdays":[],"first_run_completed":false,
             "verification_memory":{},"updated_at":"\(updatedAt)",
             "synced_at":"2026-08-04T06:00:00Z"}
            """
            return try BackendJSON.decoder.decode(ProfileRow.self, from: Data(json.utf8))
        }
        #expect(try row("1970-01-01T00:00:00+00:00").isPlaceholder)
        #expect(try !row("2026-08-04T06:00:00Z").isPlaceholder)
        #expect(
            try !row(BackendDate.string(from: .distantPast)).isPlaceholder,
            "a real row dated from the beginning of time was read as absent"
        )
    }

    // MARK: - H1: a second person on the same phone

    /// Two accounts on one phone, both with history on the same calendar day.
    /// Nothing of the first person's may reach the second's account, and the
    /// second must not be shown the first's days.
    @Test("Switching accounts moves nothing in either direction")
    func switchingAccountsLeaksNothing() {
        let ledger = ledger(#function)
        ledger.adopt(userID: "alice")
        ledger.migratedUserID = "alice"
        let adoption = ledger.adopt(userID: "bob")
        #expect(adoption == .switched)

        let then = Date(timeIntervalSince1970: 1_754_000_000)
        let merged = SyncMerge.merge(
            local: LocalPractice(
                settings: LocalPractice.Settings(
                    dayStartHour: 5, restWeekdays: [3], firstRunCompleted: true,
                    verificationMemory: .empty, updatedAt: then
                ),
                activities: [
                    LocalPractice.ActivityDefinition(
                        id: "custom.alice", label: "Alice's plunge", symbol: nil, goal: nil,
                        verification: .honor, isCustom: true, isDeleted: false, updatedAt: then
                    )
                ],
                arrangement: LocalPractice.Arrangement(
                    activityIDs: ["custom.alice"], updatedAt: then
                ),
                days: [record(4, done: ["alice-pushups"], at: then, updatedAt: then)],
                blades: LocalPractice.Blades(
                    equippedID: 7, acknowledgedIDs: [1, 2, 3, 4, 5, 6, 7],
                    celebratedIDs: [1, 2, 3], updatedAt: then
                )
            ),
            remote: RemotePractice(
                settings: LocalPractice.Settings(
                    dayStartHour: 6, restWeekdays: [], firstRunCompleted: true,
                    verificationMemory: .empty, updatedAt: then
                ),
                activities: [],
                arrangement: LocalPractice.Arrangement(
                    activityIDs: ["water"], updatedAt: then
                ),
                days: [record(4, done: ["bob-reading"], at: then, updatedAt: then)],
                blades: LocalPractice.Blades(
                    equippedID: 1, acknowledgedIDs: [1], celebratedIDs: [], updatedAt: then
                )
            ),
            pushedThrough: ledger.pushedThrough,
            localIsForeign: adoption == .switched
        )

        #expect(merged.upload.isEmpty, "something of alice's was offered to bob's account")
        #expect(
            Set(merged.practice.days.flatMap(\.completedIDs)) == ["bob-reading"],
            "bob was shown alice's day"
        )
        #expect(!merged.practice.activities.contains { $0.id == "custom.alice" })
        #expect(merged.practice.blades.acknowledgedIDs == [1], "blades bob never earned")
    }

    // MARK: - H2: two activities banked in the same millisecond

    /// The wire keeps milliseconds, and a health sweep banks several activities
    /// in one pass, so ties are ordinary. Under an unstable sort over a
    /// dictionary the merged row differed from the row that produced it — on
    /// every device and every launch — so it uploaded forever.
    @Test("A day with tied completion times settles instead of ping-ponging")
    func tiedCompletionsConverge() {
        let instant = Date(timeIntervalSince1970: 1_754_000_000)
        let watermark = instant.addingTimeInterval(60)
        var server = record(4, done: ["steps", "distance"], at: instant, updatedAt: instant)
        var phoneA = record(4, done: ["steps", "distance"], at: instant, updatedAt: instant)
        var phoneB = record(4, done: ["distance", "steps"], at: instant, updatedAt: instant)

        func pass(_ local: inout DayRecord) -> Bool {
            let outcome = SyncMerge.days(
                local: [local], remote: [server], pushedThrough: watermark
            )
            local = outcome.merged[0]
            if let sent = outcome.upload.first { server = sent }
            return !outcome.upload.isEmpty
        }

        _ = pass(&phoneA)
        _ = pass(&phoneB)
        // Nothing has happened in between, so neither may have anything to say.
        #expect(!pass(&phoneA) && !pass(&phoneB), "the two phones are still trading the day")
        #expect(phoneA == phoneB, "the two phones disagree about the day")
        #expect(phoneA == server)
    }

    @Test("Merging a tied day reaches a fixed point")
    func tiedMergeIsIdempotent() {
        let instant = Date(timeIntervalSince1970: 1_754_000_000)
        let row = record(4, done: ["steps", "distance"], at: instant, updatedAt: instant)
        let once = SyncMerge.day(local: row, remote: row)
        #expect(SyncMerge.day(local: once, remote: once) == once)
    }

    // MARK: - C2: deleting the account

    @Test("After deleting an account the next sign-in is a first sign-in")
    func deletionRewindsTheLedger() {
        let ledger = ledger(#function)
        ledger.adopt(userID: "alice")
        ledger.migratedUserID = "alice"
        ledger.pullCursor = Date()
        ledger.pushedThrough = Date()

        ledger.forgetAccount()

        #expect(ledger.adopt(userID: "bob") == .first, "the kept practice could never go up")
        #expect(ledger.pushedThrough == nil)
        #expect(ledger.pullCursor == nil)
    }

    @Test("Signing out still resumes rather than re-uploading")
    func signOutStillResumes() {
        let ledger = ledger(#function)
        ledger.adopt(userID: "alice")
        ledger.migratedUserID = "alice"
        ledger.pushedThrough = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(ledger.adopt(userID: "alice") == .unchanged)
        #expect(ledger.pushedThrough != nil)
    }

    // MARK: - H4: Apple revocation

    @Test("A session round-trips the identifier revocation is checked against")
    func appleUserIDSurvivesTheKeychain() throws {
        let session = AuthSession(
            userID: "u", accessToken: "a", refreshToken: "r",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            provider: .apple, appleUserID: "001234.abcdef.5678", email: nil
        )
        let back = try JSONDecoder().decode(
            AuthSession.self, from: try JSONEncoder().encode(session)
        )
        #expect(back.appleUserID == "001234.abcdef.5678")
        #expect(back == session)
    }

    /// A session written before the field existed must still decode, or an
    /// update signs everybody out.
    @Test("A session stored before the Apple identifier existed still decodes")
    func olderSessionsStillDecode() throws {
        let json = """
        {"userID":"u","accessToken":"a","refreshToken":"r",
         "expiresAt":768000000,"provider":"apple","email":null}
        """
        let back = try JSONDecoder().decode(AuthSession.self, from: Data(json.utf8))
        #expect(back.appleUserID == nil)
        #expect(back.provider == .apple)
    }

    // MARK: - H3: the legal links

    @Test("A legal link is either a real https URL or absent")
    func legalLinksAreNeverBroken() {
        for link in [ForgeLinks.privacy, ForgeLinks.terms, ForgeLinks.support] {
            if let link { #expect(link.scheme == "https") }
        }
        #expect(
            ForgeLinks.areConfigured
                == (ForgeLinks.privacy != nil && ForgeLinks.terms != nil && ForgeLinks.support != nil)
        )
    }

    /// The submission blocker, held as a test rather than as a `#warning`.
    ///
    /// A `#warning` fires on every build and is therefore read on none of them.
    /// This fails the run instead, and it names the three live pages — so
    /// reverting one to a placeholder is caught here rather than by a reviewer.
    @Test("The three production URLs are set and point at the live site")
    func productionLinksAreConfigured() {
        #expect(ForgeLinks.areConfigured)
        #expect(ForgeLinks.privacy?.absoluteString == "https://forgebetter.app/privacy")
        #expect(ForgeLinks.terms?.absoluteString == "https://forgebetter.app/terms")
        #expect(ForgeLinks.support?.absoluteString == "https://forgebetter.app/support")
    }

    // MARK: - H4: there is no account

    /// **The tripwire under the accountless build, and the reason this file is
    /// still here at all.**
    ///
    /// 1.0 ships with no sign-in: `AccountSection` is deleted, nothing in the
    /// running app constructs a `ForgeBackend`, the Sign in with Apple
    /// entitlement is gone, and `PrivacyInfo.xcprivacy` declares nothing linked
    /// to anybody (its only rows are §2p's anonymous usage, which needs no
    /// account). All four of those are true because of one
    /// mechanical fact — there is no Supabase project in `Info.plist` — and this
    /// is the assertion that keeps that fact from being undone by somebody
    /// pasting a URL back in to try something.
    ///
    /// It is a test rather than a comment for the reason
    /// `productionLinksAreConfigured` is: a comment is read once, by the person
    /// who wrote it. Putting the project back means deleting this test, which is
    /// a deliberate act — and the privacy manifest, the nutrition labels and the
    /// App Review notes all have to move with it.
    @Test("The shipped build has no account: no project, and nothing configured")
    func theAppShipsWithNoAccount() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "ForgeSupabaseURL") == nil)
        #expect(Bundle.main.object(forInfoDictionaryKey: "ForgeSupabaseAnonKey") == nil)
        #expect(SupabaseConfig.fromBundle() == nil)
    }

    /// **The second lock on the same door, and it is a list of one.**
    ///
    /// Anonymous usage (§2p) put exactly one third-party host into the app:
    /// TelemetryDeck's ingest. That is deliberate and it is the whole of it. A
    /// Supabase project — this one, or any — is not on the list, so even a
    /// project pasted back into `Info.plist` could not open a connection from
    /// `URLSessionTransport`: it is refused before a socket exists. Turning sync
    /// back on therefore means changing this test, `NoNetworkTests`, the
    /// privacy manifest and the labels in one commit.
    @Test("The only host the app may reach is TelemetryDeck's; the backend's is refused")
    func onlyTelemetryIsAllowed() async {
        #expect(ForgeNetwork.allowedHosts == [ForgeTelemetry.host])
        #expect(ForgeNetwork.allowedHosts.count == 1)

        let project = SupabaseConfig(
            url: URL(string: "https://abcdefgh.supabase.co")!,
            anonKey: "sb_publishable_test"
        )
        #expect(!ForgeNetwork.permits(project.url))

        let marker = UUID().uuidString
        let client = HTTPClient(
            config: project,
            transport: URLSessionTransport(session: NetworkTripwire.session())
        )
        await #expect(throws: BackendError.notConfigured) {
            try await client.send(.get, url: project.url.appendingPathComponent(marker))
        }
        #expect(NetworkTripwire.requests(containing: marker).isEmpty)
    }

    /// The severance itself, checked rather than assumed.
    ///
    /// Even if something did construct an auth service, an unconfigured one can
    /// do nothing: it reports unconfigured, it refuses to read the keychain, and
    /// it never reaches `.signedIn` — so a returning user who signed in to an
    /// earlier build is signed out by the absence of the project alone, with no
    /// migration to run. That is the guarantee `SupabaseConfig`'s own doc comment
    /// makes, and it is the reason leaving `Backend/` in the target is safe.
    @MainActor
    @Test("An unconfigured auth service cannot reach a session")
    func anUnconfiguredAuthServiceIsInert() {
        let auth = AuthService(api: nil)
        #expect(auth.isConfigured == false)
        #expect(auth.isSignedIn == false)
        #expect(auth.userID == nil)
    }
}

import Foundation
import Testing
@testable import Forge

/// The part of the backend that is genuinely hard to get right.
///
/// Every interesting case here needs two phones, a flight and a fortnight to
/// reproduce by hand, which is exactly why the rules were written as functions
/// over values. None of these tests touches a network, a store, a clock or a
/// simulator.
@Suite("Sync merge")
struct SyncMergeTests {

    // MARK: - Helpers

    private let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        epoch.addingTimeInterval(seconds)
    }

    private func day(_ d: Int) -> ForgeDay {
        ForgeDay(year: 2026, month: 8, day: d)
    }

    private func record(
        _ d: Int,
        done: [String] = [],
        planned: [String] = [],
        extractedAt: Date? = nil,
        updatedAt: Date? = nil,
        completedAt: Date? = nil
    ) -> DayRecord {
        DayRecord(
            day: day(d),
            completions: done.map {
                DayRecord.Completion(
                    ritualID: $0, method: .honor, at: completedAt ?? at(0)
                )
            },
            plannedIDs: planned,
            extractedAt: extractedAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - One day, two phones

    /// The case the whole design turns on: work done offline on two devices in
    /// the same day. Neither piece may be lost.
    @Test("Completions from both devices survive")
    func completionsAreUnioned() {
        let phone = record(4, done: ["push"], planned: ["push", "read"], updatedAt: at(100))
        let pad = record(4, done: ["read"], planned: ["push", "read"], updatedAt: at(200))

        let merged = SyncMerge.day(local: phone, remote: pad)

        #expect(merged.completedIDs == ["push", "read"])
    }

    /// A completion recorded twice is one completion, dated from the earlier
    /// record of it.
    @Test("A duplicate completion keeps the earliest time")
    func duplicateCompletionKeepsEarliest() {
        let early = record(4, done: ["push"], updatedAt: at(100), completedAt: at(10))
        let late = record(4, done: ["push"], updatedAt: at(200), completedAt: at(90))

        let merged = SyncMerge.day(local: early, remote: late)

        #expect(merged.completions.count == 1)
        #expect(merged.completions.first?.at == at(10))
    }

    /// The list shows finished activities in the order they were finished, so
    /// the merge has to hand them back in that order too.
    @Test("Completions come back in the order they happened")
    func completionsAreOrdered() {
        let phone = record(4, done: ["push"], updatedAt: at(100), completedAt: at(50))
        let pad = record(4, done: ["read"], updatedAt: at(200), completedAt: at(20))

        let merged = SyncMerge.day(local: phone, remote: pad)

        #expect(merged.completions.map(\.ritualID) == ["read", "push"])
    }

    @Test("A day earned on both devices was earned at the earlier time")
    func earnedTakesTheEarlierExtraction() {
        let phone = record(4, extractedAt: at(60), updatedAt: at(100))
        let pad = record(4, extractedAt: at(30), updatedAt: at(200))

        #expect(SyncMerge.day(local: phone, remote: pad).extractedAt == at(30))
    }

    /// Putting the blade back is a deliberate act, and the most recent
    /// deliberate act wins.
    @Test("A newer undo of the pull is honoured")
    func newerUndoWins() {
        let earned = record(4, extractedAt: at(60), updatedAt: at(100))
        let undone = record(4, extractedAt: nil, updatedAt: at(200))

        #expect(SyncMerge.day(local: earned, remote: undone).extractedAt == nil)
        #expect(SyncMerge.day(local: undone, remote: earned).extractedAt == nil)
    }

    @Test("What the day was planned as comes from the newer side")
    func plannedFollowsTheNewerSide() {
        let old = record(4, planned: ["push"], updatedAt: at(100))
        let new = record(4, planned: ["push", "read", "water"], updatedAt: at(200))

        #expect(SyncMerge.day(local: old, remote: new).plannedIDs == ["push", "read", "water"])
        #expect(SyncMerge.day(local: new, remote: old).plannedIDs == ["push", "read", "water"])
    }

    /// Two devices must reach the same answer without talking to each other,
    /// and on an exact tie the only value they both hold is the server's.
    @Test("An exact tie goes to the server, on both devices")
    func tiesGoToTheServer() {
        let mine = record(4, planned: ["push"], updatedAt: at(100))
        let theirs = record(4, planned: ["read"], updatedAt: at(100))

        #expect(SyncMerge.day(local: mine, remote: theirs).plannedIDs == ["read"])
    }

    /// Re-merging a merge has to be a no-op, or two phones trade the same
    /// day back and forth for as long as they both have signal.
    @Test("Merging is idempotent")
    func mergeIsIdempotent() {
        let phone = record(4, done: ["push"], planned: ["push", "read"], updatedAt: at(100))
        let pad = record(4, done: ["read"], planned: ["push", "read"], updatedAt: at(200))

        let once = SyncMerge.day(local: phone, remote: pad)
        let twice = SyncMerge.day(local: once, remote: once)

        #expect(once == twice)
    }

    /// The merged record must not look newer than the newest thing that went
    /// into it, or every pass would find work to do.
    @Test("A merge does not invent a newer timestamp")
    func mergeKeepsTheNewestStamp() {
        let phone = record(4, done: ["push"], updatedAt: at(100))
        let pad = record(4, done: ["read"], updatedAt: at(200))

        #expect(SyncMerge.day(local: phone, remote: pad).updatedAt == at(200))
    }

    // MARK: - A pull is a delta, not a picture

    /// The single most dangerous misreading available to a sync engine: a day
    /// absent from an incremental pull has not been deleted, it is unchanged.
    @Test("Local days the pull did not mention are kept")
    func absentDaysSurvive() {
        let history = [record(1, done: ["push"], updatedAt: at(10)),
                       record(2, done: ["push"], updatedAt: at(20))]
        let incoming = [record(3, done: ["read"], updatedAt: at(30))]

        let outcome = SyncMerge.days(
            local: history, remote: incoming, pushedThrough: at(50)
        )

        #expect(outcome.merged.count == 3)
        #expect(outcome.merged.map(\.day) == [day(1), day(2), day(3)])
    }

    @Test("A day only the server has is taken on, and not echoed back")
    func newRemoteDaysAreNotEchoed() {
        let outcome = SyncMerge.days(
            local: [], remote: [record(3, done: ["read"], updatedAt: at(30))],
            pushedThrough: at(50)
        )

        #expect(outcome.merged.count == 1)
        #expect(outcome.upload.isEmpty)
    }

    @Test("A day changed since the last push goes up")
    func dirtyDaysAreUploaded() {
        let outcome = SyncMerge.days(
            local: [record(1, done: ["push"], updatedAt: at(10)),
                    record(2, done: ["push"], updatedAt: at(90))],
            remote: [],
            pushedThrough: at(50)
        )

        #expect(outcome.upload.map(\.day) == [day(2)])
    }

    /// A merge that produced something the server does not have has to go back
    /// up, or the other device never learns about it.
    @Test("A merged day the server lacks is sent back")
    func mergedDaysAreSentBack() {
        let outcome = SyncMerge.days(
            local: [record(4, done: ["push"], updatedAt: at(10))],
            remote: [record(4, done: ["read"], updatedAt: at(20))],
            pushedThrough: at(50)
        )

        #expect(outcome.upload.count == 1)
        #expect(outcome.upload.first?.completedIDs == ["push", "read"])
    }

    // MARK: - Migration

    /// The first sign-in is not a special code path. It is this function with
    /// no watermark, and everything local is therefore unsent.
    @Test("With no watermark, the whole history is unsent")
    func migrationSendsEverything() {
        let history = (1...5).map { record($0, done: ["push"], updatedAt: at(Double($0))) }

        let outcome = SyncMerge.days(local: history, remote: [], pushedThrough: nil)

        #expect(outcome.upload.count == 5)
    }

    /// Running it again after the watermark moved must send nothing — which is
    /// what "migration happens once" actually means.
    @Test("A second pass after migrating sends nothing")
    func migrationDoesNotRepeat() {
        let history = (1...5).map { record($0, done: ["push"], updatedAt: at(Double($0))) }

        let outcome = SyncMerge.days(local: history, remote: [], pushedThrough: at(100))

        #expect(outcome.upload.isEmpty)
    }

    /// A record written before the cloud existed has no stamp, and has to date
    /// itself from its own contents rather than losing every conflict.
    @Test("An undated record dates itself")
    func undatedRecordsFallBack() {
        let pulled = record(4, extractedAt: at(500), updatedAt: nil)
        #expect(pulled.stamp == at(500))

        let ticked = record(4, done: ["push"], updatedAt: nil, completedAt: at(300))
        #expect(ticked.stamp == at(300))

        let bare = record(4, planned: ["push"], updatedAt: nil)
        #expect(bare.stamp == day(4).startOfDay())
    }

    // MARK: - Whose data is it

    private func ledger(_ name: String) -> SyncLedger {
        SyncLedger(
            defaults: UserDefaults(suiteName: "forge.tests.\(name).\(UUID().uuidString)")
                ?? .standard
        )
    }

    @Test("The first sign-in treats the whole phone as unsent")
    func firstSignInMigrates() {
        let ledger = ledger(#function)
        #expect(ledger.adopt(userID: "alice") == .first)
        #expect(ledger.pushedThrough == nil, "everything local is outstanding")
    }

    @Test("Signing back in as yourself resumes where it left off")
    func sameAccountResumes() {
        let ledger = ledger(#function)
        ledger.adopt(userID: "alice")
        ledger.pullCursor = at(500)
        ledger.pushedThrough = at(400)

        #expect(ledger.adopt(userID: "alice") == .unchanged)
        #expect(ledger.pullCursor == at(500), "no reason to re-pull a whole history")
        #expect(ledger.pushedThrough == at(400))
    }

    /// The one that would be permanent and invisible if it went wrong: a second
    /// person signing in on a phone whose days belong to the first.
    @Test("A different account does not inherit the phone's practice")
    func switchingAccountsUploadsNothingExisting() {
        let ledger = ledger(#function)
        ledger.adopt(userID: "alice")
        ledger.migratedUserID = "alice"
        ledger.pushedThrough = at(400)

        #expect(ledger.adopt(userID: "bob", now: at(900)) == .switched)
        #expect(ledger.pullCursor == nil, "bob's history has to come down whole")
        #expect(ledger.pushedThrough == at(900), "alice's days are not bob's to receive")

        // And the watermark actually does the work: nothing older than the
        // switch is offered up to the new account.
        let outcome = SyncMerge.days(
            local: [record(1, done: ["push"], updatedAt: at(100))],
            remote: [],
            pushedThrough: ledger.pushedThrough
        )
        #expect(outcome.upload.isEmpty)
    }

    /// The one that is easy to get wrong: coming back to the first account on a
    /// phone that has since held a second one. The local pile now contains both
    /// people's days, and treating it as unsent would file the second
    /// person's practice under the first person's name, permanently.
    @Test("Returning to an earlier account still does not re-upload the phone")
    func returningToAnEarlierAccountIsStillASwitch() {
        let ledger = ledger(#function)
        ledger.adopt(userID: "alice")
        ledger.migratedUserID = "alice"
        ledger.adopt(userID: "bob", now: at(900))

        #expect(ledger.adopt(userID: "alice", now: at(1000)) == .switched)
        #expect(ledger.pushedThrough == at(1000))
    }

    // MARK: - Activities

    @Test("A deletion travels and is not undone by the other device")
    func tombstonesWin() {
        let alive = LocalPractice.ActivityDefinition(
            id: "custom.a", label: "Cold plunge", symbol: nil, goal: nil,
            verification: .honor, isCustom: true, isDeleted: false, updatedAt: at(100)
        )
        var deleted = alive
        deleted.isDeleted = true
        deleted.updatedAt = at(200)

        let outcome = SyncMerge.activities(
            local: [alive], remote: [deleted], pushedThrough: at(300)
        )

        #expect(outcome.merged.first?.isDeleted == true)
    }

    @Test("An activity remade after a deletion survives the tombstone")
    func newerRecreationBeatsTombstone() {
        let deleted = LocalPractice.ActivityDefinition(
            id: "custom.a", label: nil, symbol: nil, goal: nil,
            verification: nil, isCustom: true, isDeleted: true, updatedAt: at(100)
        )
        let remade = LocalPractice.ActivityDefinition(
            id: "custom.a", label: "Cold plunge", symbol: nil, goal: nil,
            verification: .honor, isCustom: true, isDeleted: false, updatedAt: at(200)
        )

        let outcome = SyncMerge.activities(
            local: [remade], remote: [deleted], pushedThrough: at(300)
        )

        #expect(outcome.merged.first?.isDeleted == false)
        #expect(outcome.upload.count == 1, "the server still thinks it is deleted")
    }

    // MARK: - Settings

    /// Somebody with a year behind them arriving on a new phone must never be
    /// shown onboarding, whichever row happens to be newer.
    @Test("First run completed never goes back to false")
    func firstRunIsMonotonic() {
        let done = settings(firstRun: true, at: at(100))
        let fresh = settings(firstRun: false, at: at(200))

        #expect(SyncMerge.settings(local: done, remote: fresh).firstRunCompleted)
        #expect(SyncMerge.settings(local: fresh, remote: done).firstRunCompleted)
    }

    /// Corrections made on either phone are experience the classifier should
    /// keep, so the tally takes the higher count rather than the newer one.
    @Test("What the classifier learned on both devices is kept")
    func tallyTakesTheHigherCount() {
        var mine = settings(firstRun: true, at: at(100))
        mine.verificationMemory.overrideTally = ["honor": 5, "health": 1]
        var theirs = settings(firstRun: true, at: at(200))
        theirs.verificationMemory.overrideTally = ["honor": 2, "health": 4]

        let merged = SyncMerge.settings(local: mine, remote: theirs)

        #expect(merged.verificationMemory.overrideTally == ["honor": 5, "health": 4])
    }

    @Test("The day's start comes from the newer side")
    func dayStartFollowsTheNewerSide() {
        var early = settings(firstRun: true, at: at(100))
        early.dayStartHour = 4
        var late = settings(firstRun: true, at: at(200))
        late.dayStartHour = 6

        #expect(SyncMerge.settings(local: early, remote: late).dayStartHour == 6)
        #expect(SyncMerge.settings(local: late, remote: early).dayStartHour == 6)
    }

    private func settings(firstRun: Bool, at instant: Date) -> LocalPractice.Settings {
        LocalPractice.Settings(
            dayStartHour: 4,
            restWeekdays: [],
            firstRunCompleted: firstRun,
            verificationMemory: .empty,
            updatedAt: instant
        )
    }

    // MARK: - Blades

    /// Seeing a blade and being shown its celebration are things that have
    /// happened. Unioning them is what stops a fortnight of unlock overlays
    /// replaying on the phone that syncs second.
    @Test("Blades seen and celebrated are unioned")
    func bladeSetsAreUnioned() {
        let mine = LocalPractice.Blades(
            equippedID: 3, acknowledgedIDs: [2, 3], celebratedIDs: [2], updatedAt: at(100)
        )
        let theirs = LocalPractice.Blades(
            equippedID: 4, acknowledgedIDs: [4], celebratedIDs: [3, 4], updatedAt: at(200)
        )

        let merged = SyncMerge.blades(local: mine, remote: theirs)

        #expect(merged.acknowledgedIDs == [2, 3, 4])
        #expect(merged.celebratedIDs == [2, 3, 4])
        #expect(merged.equippedID == 4)
    }

    // MARK: - Arrangement

    /// The order is the data. There is no sensible interleaving of two
    /// arrangements that is not a third one nobody asked for.
    @Test("The newer arrangement is taken whole")
    func arrangementIsTakenWhole() {
        let mine = LocalPractice.Arrangement(
            activityIDs: ["water", "bed"], updatedAt: at(200)
        )
        let theirs = LocalPractice.Arrangement(
            activityIDs: ["read", "push", "teeth"], updatedAt: at(100)
        )

        #expect(SyncMerge.arrangement(local: mine, remote: theirs).activityIDs == ["water", "bed"])
    }

    // MARK: - The whole thing

    /// A pull that changed nothing must produce nothing to upload and nothing
    /// to apply. If this fails, two synced phones talk forever.
    @Test("A settled pair has nothing to say to each other")
    func settledStateIsQuiet() {
        var practice = LocalPractice.empty(at: at(0))
        practice.days = [record(1, done: ["push"], updatedAt: at(10))]
        practice.settings.updatedAt = at(10)
        practice.arrangement = LocalPractice.Arrangement(
            activityIDs: ["push"], updatedAt: at(10)
        )
        practice.blades.updatedAt = at(10)

        let remote = RemotePractice(
            settings: practice.settings,
            activities: [],
            arrangement: practice.arrangement,
            days: practice.days,
            blades: practice.blades
        )

        let merge = SyncMerge.merge(local: practice, remote: remote, pushedThrough: at(50))

        #expect(merge.upload.isEmpty)
        #expect(merge.practice == practice)
    }
}

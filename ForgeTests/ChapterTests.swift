import Foundation
import Testing
@testable import Forge

/// Chapters, and the promises they make.
///
/// **Nothing is stored that can be derived.** Every figure a chapter reports is
/// read out of `ProgressStore` at the moment it is asked for, which is why a
/// chapter cannot develop a count that disagrees with the days behind it. Half
/// of what is here exists to hold that line.
///
/// **A chapter cannot be failed.** No target, no completion, and closing one
/// early costs nothing — so there is nothing here about succeeding, and if a
/// test ever appears that asserts one, something has gone wrong upstream of it.
///
/// `@MainActor` because `ChapterStore` is, and the Xcode 26 toolchain enforces
/// actor isolation on `#expect` where earlier ones did not.
@MainActor
@Suite("Chapters")
struct ChapterTests {

    private func makeStore() -> ChapterStore {
        ChapterStore(
            defaults: UserDefaults(suiteName: "forge.chapters.\(UUID().uuidString)") ?? .standard
        )
    }

    private func makeProgress() -> ProgressStore {
        ProgressStore(
            defaults: UserDefaults(suiteName: "forge.tests.\(UUID().uuidString)") ?? .standard
        )
    }

    /// Midday, `back` days ago.
    ///
    /// Midday rather than `startOfDay()`, and the difference is not fussiness:
    /// **Forge's day starts at four in the morning**, so midnight belongs to the
    /// day before it. A chapter opened at `startOfDay()` genuinely opens a day
    /// earlier than the fixture intends — which is `Chapter.firstDay` behaving
    /// exactly as documented, and a trap worth writing down here rather than
    /// rediscovering in every test that seeds one.
    private func instant(_ store: ProgressStore, daysAgo back: Int) -> Date {
        store.currentDay.adding(days: -back).startOfDay()
            .addingTimeInterval(12 * 60 * 60)
    }

    /// One earned day, `back` days ago, made of the activities given.
    private func earn(
        _ store: ProgressStore, daysAgo back: Int, activities: [String] = ["water"]
    ) {
        let day = store.currentDay.adding(days: -back)
        store.record(
            DayRecord(
                day: day,
                completions: activities.map {
                    DayRecord.Completion(ritualID: $0, method: .honor, at: day.startOfDay())
                },
                plannedIDs: activities,
                extractedAt: day.startOfDay()
            )
        )
    }

    // MARK: - Opening and closing

    @Test("A fresh install is in no chapter, and the app works")
    func defaultsToNone() {
        let store = makeStore()
        #expect(store.current == nil)
        #expect(store.isEmpty)
        #expect(store.closed.isEmpty)
    }

    @Test("Opening one makes it the one being lived in")
    func opening() throws {
        let store = makeStore()
        let opened = try #require(store.open(name: "Winter"))
        #expect(store.current?.id == opened.id)
        #expect(opened.isOpen)
        #expect(opened.name == "Winter")
    }

    /// A chapter is the answer to "what am I in the middle of", and two answers
    /// to that is no answer. Opening closes whatever was open, in one call, so a
    /// caller cannot forget the step.
    @Test("Only one chapter is ever open")
    func onlyOneOpen() {
        let store = makeStore()
        store.open(name: "First")
        store.open(name: "Second")

        #expect(store.all.count == 2)
        #expect(store.all.count { $0.isOpen } == 1)
        #expect(store.current?.name == "Second")
        #expect(store.closed.first?.name == "First")
    }

    /// The name is the whole handle somebody has on a stretch of their life. One
    /// the app wrote would be Forge naming it for them.
    @Test("A chapter will not open without a name")
    func blankNameIsRefused() {
        let store = makeStore()
        #expect(store.open(name: "   ") == nil)
        #expect(store.open(name: "") == nil)
        #expect(store.isEmpty)
    }

    @Test("Closing is not destructive and is idempotent")
    func closing() {
        let store = makeStore()
        store.open(name: "Winter")

        #expect(store.close() != nil)
        #expect(store.current == nil)
        #expect(store.all.count == 1, "closing threw the chapter away")
        #expect(store.close() == nil, "closing twice closed something else")
    }

    /// Opened at the end of the first run, and never again for anybody who has
    /// ever had one — including somebody who deliberately closed their last.
    @Test("The first chapter opens once, ever")
    func firstChapterOpensOnce() {
        let store = makeStore()
        #expect(store.openFirst() != nil)
        #expect(store.openFirst() == nil, "a second first chapter was opened")

        store.close()
        #expect(store.openFirst() == nil,
                "somebody who closed their last chapter was put back in one")
    }

    @Test("A chapter survives a new store on the same defaults")
    func persistence() throws {
        let suite = try #require(UserDefaults(suiteName: "forge.chapters.\(UUID().uuidString)"))
        let first = ChapterStore(defaults: suite)
        first.open(name: "Winter", identityIDs: ["identity.a"], intention: "Get up early.")

        let second = ChapterStore(defaults: suite)
        #expect(second.current?.name == "Winter")
        #expect(second.current?.identityIDs == ["identity.a"])
        #expect(second.current?.intention == "Get up early.")
    }

    /// Hand-written and tolerant, for the reason every decoder in this app is:
    /// one throw fails the whole array, and the failure mode is somebody opening
    /// Forge to find the six weeks they are in the middle of gone.
    @Test("A chapter row missing everything but its id still decodes")
    func tolerantDecoding() throws {
        let json = Data(#"[{"id":"chapter.1"}]"#.utf8)
        let decoded = try JSONDecoder().decode([Chapter].self, from: json)

        #expect(decoded.count == 1)
        #expect(decoded[0].id == "chapter.1")
        #expect(decoded[0].name.isEmpty)
        #expect(decoded[0].identityIDs.isEmpty)
        #expect(decoded[0].isOpen)
    }

    @Test("Names and intentions are clamped rather than rejected")
    func clamping() throws {
        let store = makeStore()
        let long = String(repeating: "a", count: 500)
        let opened = try #require(store.open(name: long, intention: long))

        #expect(opened.name.count == Chapter.nameLimit)
        #expect(opened.intention.count == Chapter.intentionLimit)
    }

    // MARK: - Derived, never stored

    /// Every figure read at the moment it is asked for. A chapter opened over
    /// days that already happened reports them immediately, which is the same
    /// rule `firstEvidence` follows: naming a stretch of practice is not the
    /// same as starting it.
    @Test("A chapter counts the days inside its own window")
    func readingCountsTheWindow() {
        let progress = makeProgress()
        // Six days kept, spread over the last eight.
        for back in [1, 2, 3, 5, 6, 7] { earn(progress, daysAgo: back) }
        // And one well before the chapter opens.
        earn(progress, daysAgo: 40)

        let store = makeStore()
        let opened = store.open(
            name: "The last week",
            at: instant(progress, daysAgo: 7)
        )!

        let reading = opened.reading(from: progress)
        #expect(progress.daysKept == 7, "the store still counts everything")
        #expect(reading.daysKept == 6, "the chapter counted a day outside its window")
        #expect(reading.daysElapsed == 8)
        #expect(reading.completionRate > 0)
    }

    /// Nothing about a chapter is written down, so the same chapter read twice
    /// against a changed history gives the new answer both times.
    @Test("A chapter's reading follows the record rather than a stored copy")
    func readingIsDerived() {
        let progress = makeProgress()
        let store = makeStore()
        let opened = store.open(
            name: "Now", at: instant(progress, daysAgo: 3)
        )!

        #expect(opened.reading(from: progress).daysKept == 0)
        earn(progress, daysAgo: 1)
        earn(progress, daysAgo: 2)
        #expect(opened.reading(from: progress).daysKept == 2,
                "the chapter is holding a count of its own")
    }

    /// Cumulative by construction: a chapter's kept-days can only ever rise
    /// while it is open, and is fixed the moment it closes.
    @Test("A closed chapter stops counting and never changes again")
    func closedChapterIsFixed() {
        let progress = makeProgress()
        let store = makeStore()
        store.open(name: "Done", at: instant(progress, daysAgo: 10))
        earn(progress, daysAgo: 8)
        earn(progress, daysAgo: 7)

        // Closed five days ago, so "after it" is a real region of time rather
        // than the same day the close happened on.
        let closed = store.close(at: instant(progress, daysAgo: 5))!
        let atClose = closed.reading(from: progress).daysKept
        #expect(atClose == 2)

        // A day earned afterwards belongs to the record, not to the chapter.
        earn(progress, daysAgo: 1)
        #expect(progress.daysKept == 3)
        #expect(closed.reading(from: progress).daysKept == atClose,
                "a closed chapter picked up a day that happened after it")
    }

    /// Six weeks, and it is a suggestion rather than a deadline — nothing
    /// happens at day forty-three except that the bar stops moving.
    @Test("A chapter cannot overrun, because there is nothing it was late for")
    func progressClamps() {
        let progress = makeProgress()
        let store = makeStore()
        let long = store.open(
            name: "Old", at: instant(progress, daysAgo: 200)
        )!

        let value = long.progress(
            dayStartHour: progress.dayStartHour, today: progress.currentDay
        )
        #expect(value == 1)
        #expect(long.placeLabel(
            dayStartHour: progress.dayStartHour, today: progress.currentDay
        ) == "Week \(Chapter.defaultWeeks) of \(Chapter.defaultWeeks)")
    }

    @Test("Where you are in a chapter is said in weeks")
    func placeReadsInWeeks() {
        let progress = makeProgress()
        let store = makeStore()

        let fresh = store.open(name: "New", at: instant(progress, daysAgo: 0))!
        #expect(fresh.placeLabel(
            dayStartHour: progress.dayStartHour, today: progress.currentDay
        ) == "Week 1 of 6")

        let older = store.open(
            name: "Older", at: instant(progress, daysAgo: 15)
        )!
        #expect(older.placeLabel(
            dayStartHour: progress.dayStartHour, today: progress.currentDay
        ) == "Week 3 of 6")
    }

    // MARK: - Evidence inside a chapter

    /// Days, not completions — the unit of this whole app is a day, and a figure
    /// that rewarded stacking activities would turn an identity into a score.
    @Test("Evidence inside a chapter counts days and stays in its window")
    func evidenceInsideAChapter() {
        let progress = makeProgress()
        // Two activities tagged to the same identity, finished on one day.
        earn(progress, daysAgo: 2, activities: ["run", "read"])
        earn(progress, daysAgo: 3, activities: ["run"])
        // Outside the window.
        earn(progress, daysAgo: 30, activities: ["run"])

        let store = makeStore()
        let opened = store.open(
            name: "This one", at: instant(progress, daysAgo: 7)
        )!

        let tagged: Set<String> = ["run", "read"]
        #expect(opened.evidence(taggedTo: tagged, from: progress) == 2,
                "two activities on one day is one day of evidence")
        #expect(progress.daysOfEvidence(taggedTo: tagged) == 3,
                "the whole record still counts the day outside the chapter")
    }

    /// Most installs have no identities at all, and a chapter has to be correct
    /// for that rather than merely not crash.
    @Test("A chapter about nobody in particular still reads correctly")
    func zeroIdentities() throws {
        let progress = makeProgress()
        earn(progress, daysAgo: 1)

        let store = makeStore()
        let opened = try #require(store.open(name: "Just six weeks"))

        #expect(opened.identityIDs.isEmpty)
        #expect(opened.evidence(taggedTo: [], from: progress) == 0,
                "nothing tagged is zero evidence, not a crash and not a guess")
        #expect(opened.reading(from: progress).daysKept >= 0)
        #expect(store.openFirst() == nil)
    }

    /// An identity id that resolves to nothing reads as untagged, the same rule
    /// an activity's `identityID` follows — see `IdentityStore.delete(_:)`.
    @Test("A chapter naming a deleted identity is not broken by it")
    func deletedIdentityIsHarmless() {
        let progress = makeProgress()
        let store = makeStore()
        let opened = store.open(name: "Winter", identityIDs: ["identity.gone"])!

        #expect(opened.identityIDs == ["identity.gone"])
        #expect(opened.evidence(taggedTo: [], from: progress) == 0)
    }

    // MARK: - Nothing replays on upgrade

    /// Somebody with seven blades and four hundred days opens the update and is
    /// congratulated for nothing.
    ///
    /// `SwordStore` solved this once by seeding `celebratedIDs` from what is
    /// already unlocked when the key has never been written, and the merged
    /// ladder does not change that: the blades are the same seven at the same
    /// thresholds, so an install that predates all of this still queues nothing.
    /// If this ever fails, the update itself throws a fortnight of parties.
    @Test("A long practice upgrading sees no celebration replay")
    func noCelebrationReplayOnUpgrade() {
        let progress = makeProgress()
        for back in 1...120 { earn(progress, daysAgo: back) }

        // A suite with no celebration key ever written: the state an install
        // from before the split arrives in.
        let suite = UserDefaults(suiteName: "forge.swords.\(UUID().uuidString)") ?? .standard
        let swords = SwordStore(progress: progress, defaults: suite)

        #expect(progress.daysKept == 120)
        // Evaluated outside the macro: `allSatisfy` is rethrowing, and `#expect`
        // cannot swallow that. Same trap `PathTests` hit with `contains(where:)`.
        let whole = swords.swords.allSatisfy(\.isUnlocked)
        #expect(whole, "the whole collection is earned")
        #expect(swords.claimBlades() == false, "the upgrade replayed a celebration")
        #expect(swords.pendingUnlock == nil)

        // And the ladder agrees about where they are standing, without having
        // celebrated anything on the way.
        #expect(Ladder.current(daysKept: 120).id == "hundred")
        #expect(Ladder.state(daysKept: 120) == .tempered)
    }

    /// The next blade earned after an upgrade still gets its moment. Seeding
    /// must not mean "nothing ever celebrates again".
    @Test("A blade earned after the upgrade still celebrates")
    func newBladesStillCelebrate() {
        let progress = makeProgress()
        for back in 1...6 { earn(progress, daysAgo: back) }

        let suite = UserDefaults(suiteName: "forge.swords.\(UUID().uuidString)") ?? .standard
        let swords = SwordStore(progress: progress, defaults: suite)
        #expect(swords.claimBlades() == false, "six days queued something on load")

        earn(progress, daysAgo: 0)
        #expect(progress.daysKept == 7)
        #expect(swords.claimBlades() == true, "the seventh day earned nothing")
        #expect(swords.pendingUnlock?.id == 4, "the Knight Sword is what seven days earns")
    }
}

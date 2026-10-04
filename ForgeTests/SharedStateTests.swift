import Foundation
import Testing
@testable import Forge

/// The App Group move is the one change in Forge that can lose somebody's
/// history, and it runs exactly once on a device nobody is watching. It gets
/// tested harder than anything it enables.
@Suite("Shared state")
struct SharedStateTests {

    // MARK: - Helpers

    /// Two scratch suites standing in for the app's own defaults and the group.
    private func suites(_ name: String) -> (local: UserDefaults, shared: UserDefaults) {
        let local = UserDefaults(suiteName: "forge.test.local.\(name)")!
        let shared = UserDefaults(suiteName: "forge.test.shared.\(name)")!
        local.removePersistentDomain(forName: "forge.test.local.\(name)")
        shared.removePersistentDomain(forName: "forge.test.shared.\(name)")
        return (local, shared)
    }

    // MARK: - Migration

    @Test("An existing install's keys are carried into the group")
    func migrationCarriesData() {
        let (local, shared) = suites(#function)
        local.set(42, forKey: "forge.dayStartHour.v1")
        local.set(["water", "bed"], forKey: "forge.activeRituals.v1")
        local.set(true, forKey: "forge.hasCompletedFirstRun.v1")

        let moved = ForgeShared.migrateIfNeeded(from: local, into: shared)

        #expect(moved == 3)
        #expect(shared.integer(forKey: "forge.dayStartHour.v1") == 42)
        #expect(shared.stringArray(forKey: "forge.activeRituals.v1") == ["water", "bed"])
        #expect(shared.bool(forKey: "forge.hasCompletedFirstRun.v1"))
    }

    /// The originals stay put. They are the only copy if this ever has to be
    /// walked back, and they cost a few kilobytes.
    @Test("Migration copies rather than moves")
    func migrationLeavesOriginals() {
        let (local, shared) = suites(#function)
        local.set(9, forKey: "forge.dayStartHour.v1")

        ForgeShared.migrateIfNeeded(from: local, into: shared)

        #expect(local.integer(forKey: "forge.dayStartHour.v1") == 9)
    }

    /// The guarantee that matters most: a second run cannot undo a day
    /// earned after the first one.
    @Test("Migration runs once and never overwrites")
    func migrationIsOnce() {
        let (local, shared) = suites(#function)
        local.set(4, forKey: "forge.dayStartHour.v1")
        ForgeShared.migrateIfNeeded(from: local, into: shared)

        // The user carries on using the app, and the old suite goes stale.
        shared.set(6, forKey: "forge.dayStartHour.v1")
        local.set(99, forKey: "forge.dayStartHour.v1")

        #expect(ForgeShared.migrateIfNeeded(from: local, into: shared) == 0)
        #expect(shared.integer(forKey: "forge.dayStartHour.v1") == 6)
    }

    /// Belt and braces for the case above: even with the flag cleared, a key
    /// already in the group wins.
    @Test("A key already in the group is never replaced")
    func migrationNeverClobbers() {
        let (local, shared) = suites(#function)
        shared.set(6, forKey: "forge.dayStartHour.v1")
        local.set(4, forKey: "forge.dayStartHour.v1")
        local.set(true, forKey: "forge.hasCompletedFirstRun.v1")

        #expect(ForgeShared.migrateIfNeeded(from: local, into: shared) == 1)
        #expect(shared.integer(forKey: "forge.dayStartHour.v1") == 6)
        #expect(shared.bool(forKey: "forge.hasCompletedFirstRun.v1"))
    }

    /// Only what Forge wrote. `dictionaryRepresentation` on the app's own suite
    /// hands back everything iOS keeps there too, and copying that into a
    /// shared container would be moving somebody else's furniture.
    @Test("Nothing outside Forge's own keys is carried across")
    func migrationIgnoresForeignKeys() {
        let (local, shared) = suites(#function)
        local.set("secret", forKey: "AppleLanguages.something")
        local.set("nope", forKey: "forge.notAKeyWeOwn")

        #expect(ForgeShared.migrateIfNeeded(from: local, into: shared) == 0)
        #expect(shared.object(forKey: "AppleLanguages.something") == nil)
        #expect(shared.object(forKey: "forge.notAKeyWeOwn") == nil)
    }

    /// Without the group entitlement the two suites are the same object, and
    /// copying a suite onto itself should be a no-op rather than a flag that
    /// blocks the real migration later.
    @Test("Migrating into the same suite does nothing")
    func migrationNoOpsWithoutAGroup() {
        let (local, _) = suites(#function)
        local.set(4, forKey: "forge.dayStartHour.v1")
        #expect(ForgeShared.migrateIfNeeded(from: local, into: local) == 0)
    }

    /// Every key the app writes has to be in the list, or it stays behind in a
    /// suite nothing reads any more.
    @Test("The owned-key list covers everything Forge persists")
    func ownedKeysAreComplete() {
        let known = Set(ForgeShared.ownedKeys)
        for key in [
            "forge.history.v1", "forge.dayStartHour.v1", "forge.restDays.v1",
            "forge.hasCompletedFirstRun.v1", "forge.activeRituals.v1",
            "forge.customRituals.v1", "forge.verificationMemory.v1",
            "forge.libraryEdits.v1", "forge.equippedSword.v1",
            "forge.acknowledgedSwords.v1", "forge.notifications.enabled.v1",
            "forge.notifications.wake.v1", "forge.notifications.asked.v1",
            "forge.notifications.lastOpened.v1", "forge.healthAsked.v1",
            // Two that were being written and never carried across, so an
            // update stranded them: a fortnight of unlock overlays replayed,
            // and the once-ever Premium invitation came back a second time.
            "forge.celebratedSwords.v1", "forge.premiumInvited.v1",
            // Forge Pro (1.1). Stranding the founder record would put a 1.0
            // install behind the paywall; the exit offer would come back, the
            // trial reminder would forget it was turned off, and the rating
            // prompt would ask a third time. (The three doors' key went with
            // the doors, §6.)
            "forge.founder.v1", "forge.exitOffer.v1",
            "forge.trialReminder.v1", "forge.ratingAsked.v1",
            // The cloud's bookkeeping. Leaving these behind is not data loss,
            // but it does mean re-uploading a whole history to say nothing.
            "forge.sync.owner.v1", "forge.sync.pullCursor.v1",
            "forge.sync.pushedThrough.v1", "forge.sync.migratedForUser.v1",
            "forge.sync.stamps.v1", "forge.sync.tombstones.v1",
        ] {
            #expect(known.contains(key), "\(key) would be left behind")
        }
        #expect(known.count == ForgeShared.ownedKeys.count, "the list has a duplicate")
    }

    // MARK: - Snapshot

    private func snapshot(
        done: Int,
        total: Int,
        isEarned: Bool = false,
        day: ForgeDay = ForgeDay(year: 2026, month: 8, day: 3),
        daysKept: Int = 5
    ) -> ForgeSnapshot {
        ForgeSnapshot(
            day: day,
            dayStartHour: 4,
            daysKept: daysKept,
            isEarned: isEarned,
            activities: (0..<total).map {
                ForgeSnapshot.Activity(id: "a\($0)", name: "Activity \($0)", isDone: $0 < done)
            }
        )
    }

    @Test("A snapshot counts what it holds")
    func snapshotCounts() {
        let day = snapshot(done: 1, total: 3)
        #expect(day.total == 3)
        #expect(day.done == 1)
        #expect(day.remaining == 2)
        #expect(abs(day.fraction - 1.0 / 3) < 0.0001)
    }

    /// The first pull is granted with the list unfinished, so a gauge that read
    /// a third under a freed blade would be arguing with the blade.
    @Test("An earned day is whole whatever the list says")
    func earnedIsWhole() {
        #expect(snapshot(done: 1, total: 3, isEarned: true).fraction == 1)
    }

    @Test("A day with nothing in it is not a divide by zero")
    func emptyMorning() {
        let day = snapshot(done: 0, total: 0)
        #expect(day.fraction == 0)
        #expect(day.remaining == 0)
    }

    @Test("A snapshot knows which day it belongs to")
    func snapshotCurrency() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt

        func instant(_ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(
                year: 2026, month: 8, day: day, hour: hour
            )) ?? .distantPast
        }

        let day = snapshot(done: 1, total: 3)
        #expect(day.isCurrent(now: instant(3, 9), calendar: calendar))
        // Two in the morning is still the day before, so it is still current.
        #expect(day.isCurrent(now: instant(4, 2), calendar: calendar))
        // Past the four o'clock start it is not.
        #expect(!day.isCurrent(now: instant(4, 5), calendar: calendar))
    }

    @Test("A snapshot survives a round trip")
    func snapshotRoundTrips() {
        let defaults = UserDefaults(suiteName: "forge.test.snapshot")!
        defaults.removePersistentDomain(forName: "forge.test.snapshot")

        let now = Date.now
        var written = snapshot(done: 2, total: 3)
        written.day = ForgeDay.containing(now, dayStartHour: 4)
        written.write(to: defaults)

        let read = ForgeSnapshot.read(from: defaults, now: now)
        #expect(read == written)
        #expect(read.done == 2)
    }

    /// The worst thing a Forge widget could do is show yesterday's finished
    /// day on today's Lock Screen.
    @Test("A stale snapshot comes back as a day not yet begun")
    func staleSnapshotResets() {
        let defaults = UserDefaults(suiteName: "forge.test.stale")!
        defaults.removePersistentDomain(forName: "forge.test.stale")

        var yesterday = snapshot(done: 3, total: 3, isEarned: true, daysKept: 11)
        yesterday.day = ForgeDay.containing(
            Date.now.addingTimeInterval(-2 * 86_400), dayStartHour: 4
        )
        yesterday.write(to: defaults)

        let read = ForgeSnapshot.read(from: defaults)
        #expect(!read.isEarned)
        #expect(read.done == 0)
        // The count and the shape of the day outlive the rollover.
        #expect(read.daysKept == 11)
        #expect(read.total == 3)
    }

    @Test("Nothing stored reads as a day not yet begun")
    func missingSnapshot() {
        let defaults = UserDefaults(suiteName: "forge.test.missing")!
        defaults.removePersistentDomain(forName: "forge.test.missing")
        let read = ForgeSnapshot.read(from: defaults)
        #expect(read.total == 0)
        #expect(!read.isEarned)
        #expect(read.isCurrent())
    }

    // MARK: - The record behind today

    /// The trail is the only new thing the widgets are allowed to read, and it
    /// is the one thing on this boundary that describes days nobody can check by
    /// looking at their phone. Every reading of it goes through
    /// `ForgeSnapshot.mark(on:)`, so that is what these hold.

    private func day(_ y: Int, _ m: Int, _ d: Int) -> ForgeDay {
        ForgeDay(year: y, month: m, day: d)
    }

    /// A day with a trail behind it: yesterday kept whole, the day before half
    /// done, the one before that nothing, and anything earlier than that outside
    /// the record.
    private func trailed(isEarned: Bool = false, done: Int = 1, total: Int = 3) -> ForgeSnapshot {
        let today = day(2026, 9, 3)
        return ForgeSnapshot(
            day: today,
            dayStartHour: 4,
            daysKept: 40,
            isEarned: isEarned,
            activities: (0..<total).map {
                ForgeSnapshot.Activity(id: "a\($0)", name: "Activity \($0)", isDone: $0 < done)
            },
            history: [
                ForgeHeatMark.beforeRecord,
                ForgeHeatMark(level: .none, wasKept: false).raw,
                ForgeHeatMark(level: .some, wasKept: false).raw,
                ForgeHeatMark(level: .full, wasKept: true).raw,
            ],
            historyStart: today.adding(days: -4)
        )
    }

    @Test("A square is read off the trail by its own date")
    func trailReadsByDate() {
        let snap = trailed()
        #expect(snap.mark(on: day(2026, 9, 2))?.level == .full)
        #expect(snap.mark(on: day(2026, 9, 2))?.wasKept == true)
        #expect(snap.mark(on: day(2026, 9, 1))?.level == .some)
        // `ForgeHeatLevel.none`, spelled out: a bare `.none` against an
        // optional resolves to `Optional.none`, which is nil.
        #expect(snap.mark(on: day(2026, 8, 31))?.level == ForgeHeatLevel.none)
    }

    /// A day before somebody installed Forge is not a day they failed. It has to
    /// come back as nothing at all, so the grid can leave the square empty.
    @Test("A day before the record began has no mark")
    func beforeTheRecord() {
        let snap = trailed()
        #expect(snap.mark(on: day(2026, 8, 30)) == nil)
        #expect(snap.mark(on: day(2026, 8, 1)) == nil)
    }

    @Test("A day in the future has no mark")
    func aheadOfToday() {
        #expect(trailed().mark(on: day(2026, 9, 4)) == nil)
    }

    /// Today is deliberately not in the trail — it is the one day that can
    /// change after the trail is written. It comes off the live fields instead,
    /// including the rule that an earned day is whole whatever the list says.
    @Test("Today is read from today, not from the trail")
    func todayIsLive() {
        #expect(trailed(done: 2, total: 3).mark(on: day(2026, 9, 3))?.level == .some)
        #expect(trailed(done: 3, total: 3).mark(on: day(2026, 9, 3))?.level == .full)
        let earned = trailed(isEarned: true, done: 1, total: 3)
        #expect(earned.mark(on: day(2026, 9, 3))?.level == .full)
        #expect(earned.mark(on: day(2026, 9, 3))?.wasKept == true)
    }

    /// A phone that has not opened Forge for a week leaves a hole between the
    /// end of the trail and today. Nothing can be recorded without the app, so
    /// an empty day is the true reading — and it must not be a crash or a nil,
    /// either of which would put a gap in the middle of the grid.
    @Test("A day past the end of the trail reads as an empty day")
    func gapAfterTheTrail() {
        var snap = trailed()
        snap.historyStart = day(2026, 8, 1)
        #expect(snap.mark(on: day(2026, 8, 20))?.level == ForgeHeatLevel.none)
        #expect(snap.mark(on: day(2026, 8, 20))?.wasKept == false)
    }

    /// The counts under the large widget's grid are read off the same trail the
    /// grid is drawn from, so the picture and the number cannot disagree.
    @Test("Days kept over a window counts the trail and today together")
    func keptOverAWindow() {
        // One kept day in the trail (yesterday), and today unearned.
        #expect(trailed().daysKept(inLast: 7) == 1)
        // Today earned makes two.
        #expect(trailed(isEarned: true).daysKept(inLast: 7) == 2)
        // A window of one is today alone.
        #expect(trailed().daysKept(inLast: 1) == 0)
        #expect(trailed(isEarned: true).daysKept(inLast: 1) == 1)
        #expect(trailed().daysKept(inLast: 0) == 0)
    }

    /// A finished list and a kept day are one deliberate act apart, and the
    /// widget must never quietly treat them as the same fact.
    @Test("Full and kept are carried separately across the wire")
    func fullIsNotKept() {
        let finishedButNotPulled = ForgeHeatMark(level: .full, wasKept: false)
        let keptWithTheListOpen = ForgeHeatMark(level: .some, wasKept: true)

        #expect(ForgeHeatMark(raw: finishedButNotPulled.raw) == finishedButNotPulled)
        #expect(ForgeHeatMark(raw: keptWithTheListOpen.raw) == keptWithTheListOpen)
        #expect(finishedButNotPulled.raw != keptWithTheListOpen.raw)
        // And the one raw value that is not a mark at all.
        #expect(ForgeHeatMark(raw: ForgeHeatMark.beforeRecord) == nil)
    }

    /// Tolerant, like every other decoder here: a value from a build that knows
    /// something this one does not reads as the day that claims least.
    @Test("An unrecognised mark reads as a day that was not kept")
    func unknownMark() {
        let mark = ForgeHeatMark(raw: 7)
        #expect(mark?.level == ForgeHeatLevel.none)
        #expect(mark?.wasKept == false)
    }

    /// The trail is the largest thing on this boundary, and the decoder that
    /// carries it is hand-written. A snapshot from the build before it existed
    /// has to decode rather than throw — a throw here empties every widget on
    /// the phone until the app is next opened.
    @Test("A snapshot written before the trail existed still decodes")
    func trailIsOptionalOnTheWire() throws {
        let json = """
        {"day":{"year":2026,"month":9,"day":3},"dayStartHour":4,"daysKept":7,
         "isEarned":false,"activities":[],"accent":"moss"}
        """
        let decoded = try JSONDecoder().decode(ForgeSnapshot.self, from: Data(json.utf8))
        #expect(decoded.history.isEmpty)
        #expect(decoded.historyStart == nil)
        #expect(decoded.daysKept == 7)
        // And nothing reading it falls over.
        #expect(decoded.mark(on: day(2026, 9, 2)) == nil)
        #expect(decoded.daysKept(inLast: 30) == 0)
    }

    /// A rollover keeps the record. Dropping it would empty the large widget
    /// every night at four in the morning, which is the one time of day nobody
    /// opens the app to put it back.
    @Test("The trail outlives the rollover")
    func trailSurvivesRollover() {
        let defaults = UserDefaults(suiteName: "forge.test.trail")!
        defaults.removePersistentDomain(forName: "forge.test.trail")

        var yesterday = trailed(isEarned: true, done: 3, total: 3)
        yesterday.day = ForgeDay.containing(
            Date.now.addingTimeInterval(-2 * 86_400), dayStartHour: 4
        )
        yesterday.historyStart = yesterday.day.adding(days: -4)
        yesterday.write(to: defaults)

        let read = ForgeSnapshot.read(from: defaults)
        #expect(!read.isEarned)
        #expect(read.history == yesterday.history)
        #expect(read.historyStart == yesterday.historyStart)
    }

    // MARK: - New days, locked (1.1 release pass)

    /// Walked after a free week ended (§17.7): the Forge tab said "New days
    /// need Forge Pro." and the widgets still listed the day's activities.
    /// The snapshot carries the lock, older snapshots read as unlocked, and it
    /// survives the night.
    @Test("A locked phone's snapshot says so, old snapshots read unlocked, and the lock outlives the rollover")
    func lockedSnapshot() throws {
        let old = """
        {"day":{"year":2026,"month":9,"day":3},"dayStartHour":4,"daysKept":7,
         "isEarned":false,"activities":[],"accent":"moss"}
        """
        #expect(try JSONDecoder().decode(ForgeSnapshot.self, from: Data(old.utf8)).isLocked == false)

        var locked = snapshot(done: 1, total: 3, daysKept: 61)
        locked.isLocked = true
        let trip = try JSONDecoder().decode(ForgeSnapshot.self, from: JSONEncoder().encode(locked))
        #expect(trip.isLocked)
        #expect(trip == locked)

        let defaults = UserDefaults(suiteName: "forge.test.locked")!
        defaults.removePersistentDomain(forName: "forge.test.locked")
        locked.day = ForgeDay.containing(Date.now.addingTimeInterval(-2 * 86_400), dayStartHour: 4)
        locked.write(to: defaults)
        let morning = ForgeSnapshot.read(from: defaults)
        #expect(morning.day != locked.day)
        #expect(morning.isLocked)
        #expect(morning.daysKept == 61)

        // One sentence, said by the app and by every widget family.
        #expect(PremiumCopy.lockedTitle == ForgeSnapshot.lockedHeadline + ".")
    }

    @Test("No Live Activity for a locked day, an earned one, or one not begun")
    func liveActivityRule() {
        #expect(ForgePresence.wantsActivity(snapshot(done: 1, total: 3)))
        #expect(!ForgePresence.wantsActivity(snapshot(done: 0, total: 3)))
        #expect(!ForgePresence.wantsActivity(snapshot(done: 3, total: 3, isEarned: true)))
        var locked = snapshot(done: 1, total: 3)
        locked.isLocked = true
        #expect(!ForgePresence.wantsActivity(locked))
    }

    /// The flag is only as good as what the root hands it, and when: the same
    /// lock the notifications read, re-synced whenever access changes.
    @Test("The root publishes the lock the notifications read, and re-syncs on every change of access")
    func rootPublishesTheLock() throws {
        let root = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Forge/ContentView.swift"),
            encoding: .utf8
        )
        #expect(root.contains("isLocked: isPracticeLocked"))
        #expect(root.contains("store: store, consent: aiConsent, notifications: notifications\n            ) { syncAmbient() }"))
        let task = try #require(root.range(of: ".task(id: store.access) {"))
        #expect(root[task.upperBound...].prefix(900).contains("onAccessChange()"))
    }

    // MARK: - Live Activity content

    @Test("The Live Activity says the same thing the snapshot does")
    func activityState() {
        let state = ForgeActivityAttributes.ContentState(done: 1, total: 3, isEarned: false)
        #expect(state.remaining == 2)
        #expect(state.summary == "2 left")

        let one = ForgeActivityAttributes.ContentState(done: 2, total: 3, isEarned: false)
        #expect(one.summary == "One left")

        let earned = ForgeActivityAttributes.ContentState(done: 1, total: 3, isEarned: true)
        #expect(earned.fraction == 1)
        #expect(earned.summary == "The blade is free")
    }

    // MARK: - Deep link

    @Test("Every surface links to the same place, and only ours is accepted")
    func deepLink() {
        #expect(ForgeLink.today.scheme == "forge")
        #expect(ForgeLink.isForge(ForgeLink.today))
        #expect(!ForgeLink.isForge(URL(string: "https://example.com")!))
    }
}

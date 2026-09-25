import Foundation
import Testing
@testable import Forge

/// Markers somebody set for themselves.
///
/// The store holds definitions and nothing else — every number about one is
/// read back out of the history — so most of what is worth checking here is
/// that it *stays* that way, plus the one piece of state it does keep and why:
/// whether the app has already said congratulations.
@Suite("Custom milestones")
struct CustomMilestoneTests {

    private func makeStore() -> (MilestoneStore, ProgressStore) {
        let suite = UserDefaults(suiteName: "forge.tests.\(UUID().uuidString)") ?? .standard
        return (MilestoneStore(defaults: suite), ProgressStore(defaults: suite))
    }

    private func draft(
        name: String = "Read thirty days",
        subject: MilestoneSubject = .activity("read"),
        unit: MilestoneUnit = .days,
        target: Int = 30
    ) -> MilestoneDraft {
        MilestoneDraft(name: name, symbol: "book.fill", subject: subject, unit: unit, target: target)
    }

    /// Records `count` days on which `id` was finished.
    private func done(_ progress: ProgressStore, _ id: String, count: Int) {
        for back in 1...max(1, count) {
            let day = progress.currentDay.adding(days: -back)
            progress.record(
                DayRecord(
                    day: day,
                    completions: [DayRecord.Completion(ritualID: id, method: .honor, at: day.startOfDay())],
                    plannedIDs: [id],
                    extractedAt: day.startOfDay()
                )
            )
        }
    }

    // MARK: - Making one

    @Test("A milestone is kept as a definition and measured from the history")
    func progressComesFromTheRecord() {
        let (store, progress) = makeStore()
        store.add(draft())
        done(progress, "read", count: 12)

        let measured = store.measured(in: progress) { _ in "Read" }
        #expect(measured.count == 1)
        #expect(measured[0].current == 12)
        #expect(measured[0].target == 30)
        #expect(measured[0].remaining == 18)
        #expect(measured[0].percent == 40)
        #expect(!measured[0].isReached)
    }

    @Test("One counting days kept follows the blade rather than an activity")
    func daysKeptSubject() {
        let (store, progress) = makeStore()
        store.add(draft(name: "A hundred", subject: .daysKept, target: 100))
        done(progress, "water", count: 6)
        #expect(store.current(.daysKept, in: progress) == progress.daysKept)
        #expect(store.measured(in: progress) { _ in nil }[0].current == 6)
    }

    @Test("Nothing may be set past the ceiling, or below one")
    func targetIsClamped() {
        let (store, _) = makeStore()
        store.add(draft(target: 99_999))
        #expect(store.custom[0].target == CustomMilestone.targetRange.upperBound)
        store.add(draft(target: -4))
        #expect(store.custom[1].target == CustomMilestone.targetRange.lowerBound)
    }

    @Test("The list is capped")
    func limit() {
        let (store, _) = makeStore()
        for index in 0..<(MilestoneStore.limit + 4) { store.add(draft(name: "One \(index)")) }
        #expect(store.custom.count == MilestoneStore.limit)
        #expect(!store.canAddMore)
    }

    /// A blank row would be worse than an opinionated one.
    @Test("An empty name falls back to a true description")
    func namesAreNeverEmpty() {
        let (store, _) = makeStore()
        store.add(draft(name: "   "))
        #expect(!store.custom[0].name.isEmpty)
    }

    // MARK: - Percentages

    /// A bar at ninety-nine and a half beside the word "100%" is the app
    /// telling somebody they are finished when they are not.
    @Test("Percent rounds down, so nothing says a hundred until it is")
    func percentNeverRoundsUpToFull() {
        let milestone = Milestone(
            id: "x", name: "x", note: "x", target: 200, current: 199, unit: .days
        )
        #expect(milestone.percent == 99)
        #expect(!milestone.isReached)

        let reached = Milestone(
            id: "y", name: "y", note: "y", target: 200, current: 200, unit: .days
        )
        #expect(reached.percent == 100)
        #expect(reached.isReached)
        #expect(reached.remaining == 0)
    }

    @Test("Overshooting does not push the bar or the count past the target")
    func overshootIsClamped() {
        let milestone = Milestone(
            id: "x", name: "x", note: "x", target: 30, current: 44, unit: .days
        )
        #expect(milestone.progress == 1)
        #expect(milestone.remaining == 0)
        #expect(milestone.countLabel == "30/30")
    }

    @Test("The three units are wording and nothing else")
    func unitsAreWordingOnly() {
        #expect(MilestoneUnit.days.phrase(30) == "30 days")
        #expect(MilestoneUnit.times.phrase(100) == "100 times")
        #expect(MilestoneUnit.sessions.phrase(50) == "50 sessions")
        #expect(MilestoneUnit.days.phrase(1) == "1 day")
        #expect(MilestoneUnit.days.remaining(18) == "18 days to go")
        #expect(MilestoneUnit.times.remaining(1) == "One more time")
    }

    // MARK: - Celebration

    @Test("Reaching one queues its congratulation, once and only once")
    func celebrationFiresOnce() {
        let (store, progress) = makeStore()
        store.add(draft(target: 5))
        done(progress, "read", count: 5)

        #expect(store.refresh(against: progress))
        #expect(store.pendingCelebration?.name == "Read thirty days")

        // A second pass has nothing new to say, and the launch after that must
        // not replay it either.
        #expect(!store.refresh(against: progress))
        store.dismissCelebration()
        #expect(store.pendingCelebration == nil)
        #expect(!store.refresh(against: progress))
    }

    @Test("Two reached at once are both congratulated, in turn")
    func celebrationsQueue() {
        let (store, progress) = makeStore()
        store.add(draft(name: "First", target: 2))
        store.add(draft(name: "Second", target: 3))
        done(progress, "read", count: 4)

        store.refresh(against: progress)
        #expect(store.pendingCelebration?.name == "First")
        store.dismissCelebration()
        #expect(store.pendingCelebration?.name == "Second")
        store.dismissCelebration()
        #expect(store.pendingCelebration == nil)
    }

    /// Somebody who reaches thirty and then raises the bar to a hundred has not
    /// reached a hundred, and the row must stop wearing its tick.
    @Test("Raising the target puts a reached milestone back in play")
    func raisingTheTargetReopensIt() {
        let (store, progress) = makeStore()
        store.add(draft(target: 3))
        done(progress, "read", count: 3)
        store.refresh(against: progress)
        #expect(store.custom[0].reachedAt != nil)
        store.dismissCelebration()

        store.update(store.custom[0].id, to: draft(target: 50))
        #expect(store.custom[0].reachedAt == nil)
        #expect(!store.measured(in: progress) { _ in "Read" }[0].isReached)
        #expect(!store.refresh(against: progress))
    }

    @Test("Lowering the target below what is already done reaches it")
    func loweringTheTargetCanCompleteIt() {
        let (store, progress) = makeStore()
        store.add(draft(target: 50))
        done(progress, "read", count: 6)
        #expect(!store.refresh(against: progress))

        store.update(store.custom[0].id, to: draft(target: 5))
        #expect(store.refresh(against: progress))
        #expect(store.custom[0].reachedAt != nil)
    }

    @Test("Deleting one takes its pending congratulation with it")
    func deletingClearsTheQueue() {
        let (store, progress) = makeStore()
        store.add(draft(target: 2))
        done(progress, "read", count: 2)
        store.refresh(against: progress)
        #expect(store.pendingCelebration != nil)

        store.delete(store.custom[0].id)
        #expect(store.custom.isEmpty)
        #expect(store.pendingCelebration == nil)
    }

    // MARK: - Ordering and storage

    @Test("Unreached ones sit above reached ones")
    func reachedSinkToTheBottom() {
        let (store, progress) = makeStore()
        store.add(draft(name: "Done already", target: 2))
        store.add(draft(name: "Still going", target: 90))
        done(progress, "read", count: 3)

        let measured = store.measured(in: progress) { _ in "Read" }
        #expect(measured.map(\.name) == ["Still going", "Done already"])
    }

    @Test("A milestone survives being written down and read back")
    func roundTrips() throws {
        let suite = UserDefaults(suiteName: "forge.tests.\(UUID().uuidString)") ?? .standard
        let store = MilestoneStore(defaults: suite)
        store.add(draft(name: "Meditate a hundred times", unit: .times, target: 100))

        let reopened = MilestoneStore(defaults: suite)
        #expect(reopened.custom.count == 1)
        #expect(reopened.custom[0].name == "Meditate a hundred times")
        #expect(reopened.custom[0].unit == .times)
        #expect(reopened.custom[0].subject == .activity("read"))
        #expect(reopened.custom[0].target == 100)
    }

    /// The lesson `Ritual` learned the hard way: one throw fails the whole
    /// array, and the failure mode is somebody's own milestones disappearing on
    /// update. Only `id` is genuinely required.
    @Test("A record written by a future build still decodes")
    func decodingIsTolerant() throws {
        let json = #"[{"id":"milestone.1"},{"id":"milestone.2","target":40,"unit":"fortnights"}]"#
        let decoded = try JSONDecoder().decode([CustomMilestone].self, from: Data(json.utf8))
        #expect(decoded.count == 2)
        #expect(decoded[0].target == 1)
        #expect(decoded[0].subject == .daysKept)
        // An unrecognised unit is wording we cannot interpret, and days is the
        // one that claims nothing beyond what is actually counted.
        #expect(decoded[1].unit == .days)
        #expect(decoded[1].target == 40)
    }

    @Test("Suggested names are the sentence somebody would have typed")
    func suggestedNames() {
        #expect(
            CustomMilestone.suggestedName(target: 30, unit: .days, activityName: "Read")
                == "Read 30 days"
        )
        #expect(
            CustomMilestone.suggestedName(target: 100, unit: .times, activityName: "Meditate")
                == "Meditate 100 times"
        )
        #expect(
            CustomMilestone.suggestedName(target: 50, unit: .sessions, activityName: "Workout")
                == "Workout 50 sessions"
        )
    }
}

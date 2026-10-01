import Foundation
import Testing
import UIKit
@testable import Forge

// MARK: - Helpers

/// A day of record, kept or not, holding these activities.
private func record(
    _ day: ForgeDay, done ids: [String] = ["read"], planned: [String]? = nil, kept: Bool = true
) -> DayRecord {
    DayRecord(
        day: day,
        completions: ids.map { DayRecord.Completion(ritualID: $0, method: .honor, at: day.startOfDay()) },
        plannedIDs: planned ?? ids,
        extractedAt: kept ? day.startOfDay() : nil
    )
}

private func history(_ records: [DayRecord]) -> [ForgeDay: DayRecord] {
    Dictionary(uniqueKeysWithValues: records.map { ($0.day, $0) })
}

private func reading(
    _ enrollment: ArcEnrollment,
    _ byDay: [ForgeDay: DayRecord] = [:],
    today: ForgeDay,
    rest: Set<Int> = [],
    challenges: Set<ForgeDay> = [],
    resolved: [String: String] = [:]
) -> ArcReading {
    ArcReading.read(
        enrollment, byDay: byDay, today: today, restWeekdays: rest,
        challengeDays: challenges, resolved: resolved
    )
}

/// A store, a day's view model and a history, all in a scratch suite — the
/// view model's own keys are the shared App Group's, so the week it starts
/// from is set through its properties on the way in (`OnboardingDayTests`).
@MainActor
private func world(week: [String] = ["water", "read"]) -> (ArcStore, ForgeViewModel, ProgressStore) {
    let suite = UserDefaults(suiteName: "forge.tests.arcs.\(UUID().uuidString)")!
    let progress = ProgressStore(defaults: suite)
    let vm = ForgeViewModel(progress: progress)
    vm.customRituals = []
    vm.libraryEdits = [:]
    vm.activeRitualIDs = week
    let arcs = ArcStore(
        progress: progress,
        defaults: suite,
        week: { vm.activeRituals },
        find: { vm.ritual($0) },
        write: { vm.apply($0) },
        takeOff: { vm.removeRituals($0) }
    )
    return (arcs, vm, progress)
}

// MARK: - The catalogue

@Suite("Arcs: the catalogue")
struct ArcCatalogTests {

    @Test("Four Arcs, at the lengths the direction gives them")
    func four() {
        let lengths = Dictionary(uniqueKeysWithValues: ArcCatalog.all.map { ($0.id, $0.length) })
        #expect(lengths == [.lockIn: 7, .monk: 30, .discipline: 66, .winter: 90])
        #expect(ArcCatalog.all.map(\.name) == ["Lock In 7", "Monk Mode 30", "Discipline 66", "Winter Arc"])
    }

    @Test("A trial for every week, the last one cut at the end")
    func aTrialAWeek() {
        for program in ArcCatalog.all {
            let weeks = (program.length + 6) / 7
            #expect(program.trials.count == weeks, Comment(rawValue: program.name))
            #expect(program.trialDays(weeks - 1).upperBound == program.length)
            for trial in program.trials { #expect(trial.count.target > 0) }
        }
        #expect(ArcCatalog.winter.trials.count == 13)
        #expect(ArcCatalog.winter.trialDays(12) == 85...90)
    }

    @Test("Phases run end to end, from day one to the last")
    func phasesCover() {
        for program in ArcCatalog.all {
            #expect(program.phases.first?.firstDay == 1)
            #expect(program.phases.last?.lastDay == program.length)
            for (before, after) in zip(program.phases, program.phases.dropFirst()) {
                #expect(after.firstDay == before.lastDay + 1, Comment(rawValue: program.name))
            }
            for activity in program.activities {
                #expect(activity.standards.count <= program.phases.count)
            }
        }
        let winter = ArcCatalog.winter.phases.map { "\($0.name) \($0.firstDay)-\($0.lastDay)" }
        #expect(winter == ["Foundation 1-14", "Build 15-42", "Harden 43-70", "Finish 71-90"])
        let monk = ArcCatalog.monk.phases.map { "\($0.firstDay)-\($0.lastDay)" }
        #expect(monk == ["1-10", "11-20", "21-30"])
        #expect(ArcCatalog.winter.phases[1].week == 3)
    }

    /// Only concrete, countable things, taken from the library, each filed
    /// under one of the six — and the first phase's standard is the library's
    /// own, so joining adds exactly the activity somebody would find there.
    @Test("Every activity an Arc asks for is a filed library activity")
    func libraryOnly() throws {
        for program in ArcCatalog.all {
            for activity in program.activities {
                let ritual = try #require(Ritual.find(activity.ritualID), Comment(rawValue: activity.ritualID))
                #expect(Ritual.categories[ritual.id] != nil)
                #expect(RitualCategory.dimensions.contains(ritual.category))
                if let goal = activity.standard(inPhase: 0).goal {
                    #expect(goal == ritual.tail, Comment(rawValue: "\(ritual.id) starts at its library standard"))
                }
                for other in activity.alsoCounts { #expect(Ritual.find(other) != nil) }
                for standard in activity.standards { #expect(!standard.weekdays.isEmpty) }
            }
        }
    }

    @Test("The ramps are the ones the direction wrote")
    func ramps() throws {
        let winter = ArcCatalog.winter
        let train = try #require(winter.activities.first { $0.ritualID == "workout" })
        #expect((0..<4).map { train.standard(inPhase: $0).minutes } == [30, 45, 60, 60])
        #expect(train.standard(inPhase: 0).weekdays.count == 4)
        #expect(train.standard(inPhase: 1).weekdays.count == 5)
        let steps = try #require(winter.activities.first { $0.ritualID == "steps" })
        #expect(steps.standard(inPhase: 0).target == 8_000)
        #expect(steps.standard(inPhase: 1).target == 10_000)
        let pages = try #require(winter.activities.first { $0.ritualID == "pages" })
        #expect((0..<4).map { pages.standard(inPhase: $0).goal } == ["10 pages", "10 pages", "20 pages", "20 pages"])
        let deep = try #require(winter.activities.first { $0.ritualID == "focus" })
        #expect((0..<4).map { deep.standard(inPhase: $0).minutes } == [60, 90, 120, 120])

        let monk = try #require(ArcCatalog.monk.activities.first { $0.ritualID == "focus" })
        #expect((0..<3).map { monk.standard(inPhase: $0).minutes } == [90, 120, 150])
    }

    /// Plain, adult, direct: no exclamation marks, nothing that congratulates,
    /// and only the papers DIRECTION_1_1 allows.
    @Test("Every word on an Arc is in Forge's voice")
    func voice() {
        let allowed = ["Lally", "Gollwitzer", "Harkin", "Dai"]
        for program in ArcCatalog.all {
            var words = [program.name, program.summary, program.why, program.reward ?? ""]
            words += program.phases.flatMap { [$0.name, $0.line] }
            words += program.trials.flatMap { [$0.title, $0.detail] }
            for line in words {
                #expect(!line.contains("!"), Comment(rawValue: line))
                for banned in ["Congratulations", "Well done", "Great job", "lose your", "don't break"] {
                    #expect(!line.localizedCaseInsensitiveContains(banned), Comment(rawValue: line))
                }
            }
            if let source = program.source {
                #expect(allowed.contains { source.hasPrefix($0) }, Comment(rawValue: source))
            }
        }
        #expect(ArcCatalog.discipline.source?.hasPrefix("Lally") == true)
        #expect(ArcCatalog.winter.source?.hasPrefix("Dai") == true)
    }

    /// The four covers ship in the catalogue; a missing one would fall back
    /// to the typographic plate rather than to a blank card.
    @Test("Every Arc has its cover in the asset catalogue")
    func covers() {
        #expect(ArcCatalog.all.map(\.cover) == ["arc-lockin", "arc-monk", "arc-66", "arc-winter"])
        for program in ArcCatalog.all {
            #expect(UIImage(named: program.cover) != nil, Comment(rawValue: program.cover))
        }
    }
}

// MARK: - Day maths

@Suite("Arcs: the day count")
struct ArcDayTests {

    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func instant(_ calendar: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// Day N of M is a count of civil days, not of twenty-four-hour stretches,
    /// so the morning the clocks go back is one day on and the morning they go
    /// forward is one day on.
    @Test("Each morning is one day on, across both clock changes")
    func acrossDST() {
        let newYork = calendar("America/New_York")
        // On November 1 2026 the clocks go back; on March 8 2026 they go forward.
        for (start, nights) in [((2026, 10, 30), 5), ((2026, 3, 6), 5)] {
            let first = ForgeDay(year: start.0, month: start.1, day: start.2)
            let enrollment = ArcEnrollment(arc: .winter, startDay: first, isApplied: true)
            for offset in 0..<nights {
                let morning = newYork.date(
                    byAdding: .day, value: offset,
                    to: instant(newYork, start.0, start.1, start.2, 7)
                )!
                let day = ForgeDay.containing(morning, calendar: newYork, dayStartHour: 4)
                #expect(reading(enrollment, today: day).day == offset + 1)
            }
        }
    }

    /// Half past one on the second night is still the first day: the day
    /// starts at four (`dayStartHour`), here and everywhere.
    @Test("Before four in the morning it is still the day before")
    func fourInTheMorning() {
        let chicago = calendar("America/Chicago")
        let first = ForgeDay(year: 2026, month: 10, day: 31)
        let enrollment = ArcEnrollment(arc: .monk, startDay: first, isApplied: true)

        // The night the clocks go back, at half past one — which happens twice.
        let late = ForgeDay.containing(instant(chicago, 2026, 11, 1, 1, 30), calendar: chicago, dayStartHour: 4)
        #expect(reading(enrollment, today: late).day == 1)
        let morning = ForgeDay.containing(instant(chicago, 2026, 11, 1, 4, 30), calendar: chicago, dayStartHour: 4)
        #expect(reading(enrollment, today: morning).day == 2)
    }

    @Test("Upcoming, running, finished: the day says which")
    func states() {
        let start = ForgeDay(year: 2026, month: 10, day: 5)
        let enrollment = ArcEnrollment(arc: .monk, startDay: start, isApplied: true)
        #expect(reading(enrollment, today: start.adding(days: -2)).status == .upcoming)
        #expect(reading(enrollment, today: start.adding(days: -2)).day == 0)
        #expect(reading(enrollment, today: start).status == .active)
        #expect(reading(enrollment, today: start.adding(days: 29)).status == .active)
        #expect(reading(enrollment, today: start.adding(days: 29)).counter == "Day 30 of 30")
        #expect(reading(enrollment, today: start.adding(days: 30)).status == .finished)
        #expect(enrollment.endDay == start.adding(days: 29))
    }

    @Test("The phase follows the day")
    func phaseFollowsDay() {
        let start = ForgeDay(year: 2026, month: 10, day: 1)
        let enrollment = ArcEnrollment(arc: .winter, startDay: start, isApplied: true)
        let phases = [1, 14, 15, 42, 43, 70, 71, 90].map {
            reading(enrollment, today: start.adding(days: $0 - 1)).phase
        }
        #expect(phases == [0, 0, 1, 1, 2, 2, 3, 3])
    }
}

// MARK: - On track, and finished

@Suite("Arcs: on track and finished")
struct ArcReadingTests {

    private let start = ForgeDay(year: 2026, month: 10, day: 5)

    @Test("On track is the Arc's own goal: four of five, five of seven for Lock In 7")
    func pace() {
        let winter = ArcEnrollment(arc: .winter, startDay: start, isApplied: true)
        let today = start.adding(days: 5)
        let four = history((0..<5).map { record(start.adding(days: $0), kept: $0 < 4) })
        let three = history((0..<5).map { record(start.adding(days: $0), kept: $0 < 3) })

        let onPace = reading(winter, four, today: today)
        #expect(onPace.kept == 4)
        #expect(onPace.counted == 5)
        #expect(onPace.isOnTrack)
        #expect(onPace.paceLine == "On track. 4 of 5 days kept.")

        let behind = reading(winter, three, today: today)
        #expect(!behind.isOnTrack)
        #expect(behind.paceLine == "Not on track yet. 3 of 5 days kept; four of every five is the pace.")
        #expect(!behind.paceLine.localizedCaseInsensitiveContains("fail"))

        let lockIn = ArcEnrollment(arc: .lockIn, startDay: start, isApplied: true)
        let week = start.adding(days: 7)
        let five = history((0..<7).map { record(start.adding(days: $0), kept: $0 < 5) })
        let fourOfSeven = history((0..<7).map { record(start.adding(days: $0), kept: $0 < 4) })
        #expect(reading(lockIn, five, today: week).isOnTrack)
        #expect(reading(lockIn, fourOfSeven, today: week).paceLine.hasSuffix("five of every seven is the pace."))
    }

    /// Found in the Simulator: the pace line said five of every seven for
    /// every Arc, so a Winter Arc kept at 72 per cent read "On track" all the
    /// way to "Finished". On track and Completed are one line now.
    @Test("On track to the last day ends Completed")
    func onTrackMeansCompleted() {
        for program in ArcCatalog.all {
            let enrollment = ArcEnrollment(arc: program.id, startDay: start, isApplied: true)
            for keptDays in 0...program.length {
                // The last day is among the kept, so it counts on the last
                // day itself as well as after it: today joins only once kept.
                let days = (0..<program.length).map {
                    record(start.adding(days: $0),
                           kept: $0 < keptDays - 1 || (keptDays > 0 && $0 == program.length - 1))
                }
                let last = reading(enrollment, history(days), today: start.adding(days: program.length - 1))
                let after = reading(enrollment, history(days), today: start.adding(days: program.length))
                #expect(last.isOnTrack == after.isCompleted,
                        Comment(rawValue: "\(program.name), \(keptDays) kept"))
            }
        }
    }

    /// A day in progress is never a miss.
    @Test("Today joins the count only once it is kept")
    func todayIsNotAMiss() {
        let enrollment = ArcEnrollment(arc: .monk, startDay: start, isApplied: true)
        let open = reading(enrollment, history([record(start, kept: false)]), today: start)
        #expect(open.counted == 0)
        #expect(open.isOnTrack)
        let kept = reading(enrollment, history([record(start)]), today: start)
        #expect(kept.counted == 1)
        #expect(kept.kept == 1)
    }

    /// §5 #11: a weekday set aside in Settings is no part of either number.
    @Test("A rest day is neither a miss nor credit")
    func restDays() {
        let enrollment = ArcEnrollment(arc: .winter, startDay: start, isApplied: true)
        let rest: Set<Int> = [start.adding(days: 2).weekday]
        // Day three is the rest day, kept anyway; day four is missed.
        let days = (0..<5).map { record(start.adding(days: $0), kept: $0 != 3) }
        let read = reading(enrollment, history(days), today: start.adding(days: 5), rest: rest)
        #expect(read.counted == 4)
        #expect(read.kept == 3)
    }

    @Test("Eighty per cent at the end is Completed, below it is Finished")
    func outcomes() {
        let enrollment = ArcEnrollment(arc: .winter, startDay: start, isApplied: true)
        let after = start.adding(days: 100)

        let seventyTwo = history((0..<90).map { record(start.adding(days: $0), kept: $0 < 72) })
        let completed = reading(enrollment, seventyTwo, today: after)
        #expect(completed.status == .finished)
        #expect(completed.isCompleted)
        #expect(completed.outcome == "Completed, 72 of 90 days")

        let sixtyOne = history((0..<90).map { record(start.adding(days: $0), kept: $0 < 61) })
        let finished = reading(enrollment, sixtyOne, today: after)
        #expect(!finished.isCompleted)
        #expect(finished.outcome == "Finished, 61 of 90 days")
        #expect(finished.day == 90)
    }

    @Test("Lock In 7 is Completed at five of its seven")
    func lockInGoal() {
        let enrollment = ArcEnrollment(arc: .lockIn, startDay: start, isApplied: true)
        let after = start.adding(days: 8)
        let five = history((0..<7).map { record(start.adding(days: $0), kept: $0 < 5) })
        #expect(reading(enrollment, five, today: after).isCompleted)
        let four = history((0..<7).map { record(start.adding(days: $0), kept: $0 < 4) })
        #expect(!reading(enrollment, four, today: after).isCompleted)
    }

    @Test("A left Arc reads as far as it was taken")
    func left() {
        var enrollment = ArcEnrollment(arc: .monk, startDay: start, isApplied: true)
        enrollment.leftOn = start.adding(days: 9)
        let days = history((0..<20).map { record(start.adding(days: $0)) })
        let read = reading(enrollment, days, today: start.adding(days: 15))
        #expect(read.status == .left)
        #expect(read.day == 10)
        #expect(read.counted == 10)
    }

    /// The counts come from the record and the person's own tallies; a trial
    /// that counts an activity reads the one the week actually holds.
    @Test("Each kind of trial counts what it says")
    func trials() {
        var winter = ArcEnrollment(arc: .winter, startDay: start, isApplied: true)
        // Week one: seven wake-ups, five of them done.
        let wakes = history((0..<7).map { record(start.adding(days: $0), done: $0 < 5 ? ["wake"] : ["read"]) })
        let first = reading(winter, wakes, today: start.adding(days: 6))
        #expect(first.trial?.index == 0)
        #expect(first.trial?.count == 5)
        #expect(first.trial?.target == 7)
        #expect(first.trial?.line == "Trial 5 of 7")

        // Week three: two cold showers, counted by hand.
        winter.tallies[2] = 1
        let third = reading(winter, today: start.adding(days: 15))
        #expect(third.trial?.index == 2)
        #expect(third.trial?.isTally == true)
        #expect(third.trial?.count == 1)

        // Week nine counts "Read on paper" — or "Read", for somebody who keeps that.
        let read = history((56..<63).map { record(start.adding(days: $0), done: ["read"]) })
        let ninth = reading(winter, read, today: start.adding(days: 62), resolved: ["pages": "read"])
        #expect(ninth.trial?.index == 8)
        #expect(ninth.trial?.count == 6)

        // Lock In 7 counts finished daily challenges.
        let lockIn = ArcEnrollment(arc: .lockIn, startDay: start, isApplied: true)
        let challenges = Set((0..<3).map { start.adding(days: $0) })
        #expect(reading(lockIn, today: start.adding(days: 4), challenges: challenges).trial?.count == 3)
    }
}

// MARK: - Joining, phases, leaving

@MainActor
@Suite("Arcs: joining, phases and leaving")
struct ArcStoreTests {

    /// §5 #7: an Arc appends. Everything that was in the week is still there,
    /// exactly as it was, and what is new goes on the end.
    @Test("Joining only appends")
    func joiningAppends() throws {
        let (arcs, vm, _) = world(week: ["water", "read", "workout"])
        vm.setDuration("workout", minutes: 20)
        vm.setWeekday("workout", 3, on: false)
        let before = vm.activeRituals
        let preview = arcs.preview(.winter)

        #expect(preview.changes.allSatisfy { if case .adopt = $0 { true } else { false } })
        #expect(Set(preview.alreadyKept) == ["Read", "Work out"])
        #expect(preview.headline == "Adds six activities to your week.")

        try #require(arcs.start(.winter, on: vm.progress.currentDay) != nil)

        // Nothing removed, nothing already there changed.
        #expect(Array(vm.activeRitualIDs.prefix(3)) == ["water", "read", "workout"])
        for ritual in before {
            #expect(vm.ritual(ritual.id) == ritual)
            #expect(vm.ritual(ritual.id)?.minutes == ritual.minutes)
            #expect(vm.ritual(ritual.id)?.repeats == ritual.repeats)
        }
        let added = Set(vm.activeRitualIDs.dropFirst(3))
        #expect(added == ["wake", "firstthirty", "steps", "focus", "bedroom", "listen"])
        #expect(Set(try #require(arcs.current).added) == added)
        // "Read" already does the reading, so "Read on paper" is not added too.
        #expect(!vm.activeRitualIDs.contains("pages"))
    }

    /// What an Arc adds arrives on its own days, at its own hour, at its own
    /// length — and a target that only said the length moves with it.
    @Test("An added activity arrives at the Arc's standard")
    func additionsArriveAtStandard() throws {
        let (arcs, vm, _) = world(week: ["water"])
        arcs.start(.winter, on: vm.progress.currentDay, wake: 6 * 60)
        let workout = try #require(vm.ritual("workout"))
        #expect(workout.minutes == 30)
        #expect(workout.tail == "30 min")
        #expect(workout.repeats.weekdays == [2, 3, 5, 6])
        #expect(workout.startMinute == 6 * 60 + 30)
        #expect(vm.ritual("wake")?.startMinute == 6 * 60)
        #expect(vm.ritual("steps")?.startMinute == nil)
        #expect(vm.ritual("steps")?.measure == ActivityMeasure(metric: .steps, target: 8_000))
        #expect(vm.ritual("bedroom")?.startMinute == 22 * 60 + 30)
        #expect(vm.ritual("listen")?.repeats.weekdays == [1])
    }

    @Test("One Arc at a time")
    func oneAtATime() throws {
        let (arcs, vm, _) = world()
        try #require(arcs.start(.monk, on: vm.progress.currentDay) != nil)
        #expect(!arcs.canStart)
        #expect(arcs.start(.winter, on: vm.progress.currentDay) == nil)
        #expect(arcs.current?.arc == .monk)
        arcs.leave(takingOff: false)
        #expect(arcs.canStart)
        #expect(arcs.start(.winter, on: vm.progress.currentDay) != nil)
    }

    /// A "Start Monday" pressed on a Thursday does not change Thursday.
    @Test("A start ahead writes nothing until its day")
    func startMonday() throws {
        let (arcs, vm, progress) = world(week: ["water"])
        let ahead = progress.currentDay.adding(days: 3)
        try #require(arcs.start(.monk, on: ahead) != nil)
        #expect(vm.activeRitualIDs == ["water"])
        #expect(arcs.current?.isApplied == false)
        #expect(arcs.currentReading?.status == .upcoming)

        progress.debugDayOffset = 3
        arcs.applyIfDue()
        #expect(arcs.current?.isApplied == true)
        #expect(vm.activeRitualIDs.contains("focus"))
        #expect(arcs.currentReading?.day == 1)
    }

    /// The phase's changes, computed against the week as it is, offered on the
    /// card and applied only on the tap.
    @Test("A phase change is a reviewable diff, applied on one tap")
    func phaseDiff() throws {
        let (arcs, vm, progress) = world(week: ["water"])
        arcs.debugStart(.winter, daysAgo: 14)
        #expect(arcs.currentReading?.day == 15)

        let offer = try #require(arcs.phaseOffer())
        #expect(offer.title == "Week 3: Build")
        let lines = offer.changes.compactMap(\.diffLine)
        #expect(lines.contains("Work out 30 \u{2192} 45 min"))
        #expect(lines.contains("Hit your steps 8,000 \u{2192} 10,000"))
        #expect(lines.contains("Deep work 60 \u{2192} 90 min"))
        #expect(lines.contains("Work out Mon, Tue, Thu, Fri \u{2192} Weekdays"))
        // Nothing has moved yet.
        #expect(vm.ritual("workout")?.minutes == 30)

        let applied = arcs.applyPhase(offer)
        #expect(applied == offer.changes.count)
        #expect(vm.ritual("workout")?.minutes == 45)
        #expect(vm.ritual("workout")?.tail == "45 min")
        #expect(vm.ritual("workout")?.repeats.weekdays == ArcStandard.weekdays)
        #expect(vm.ritual("steps")?.tail == "10,000")
        #expect(vm.ritual("steps")?.measure?.target == 10_000)
        #expect(vm.ritual("focus")?.minutes == 90)
        #expect(arcs.phaseOffer() == nil, "answered, and not offered again")
        _ = progress
    }

    @Test("Keep mine answers the phase and moves nothing")
    func keepMine() throws {
        let (arcs, vm, _) = world(week: ["water"])
        arcs.debugStart(.winter, daysAgo: 42)
        let offer = try #require(arcs.phaseOffer())
        #expect(offer.title == "Week 7: Harden")
        let before = vm.activeRituals
        arcs.keepPhase(offer)
        #expect(arcs.phaseOffer() == nil)
        #expect(vm.activeRituals.map(\.minutes) == before.map(\.minutes))
        #expect(arcs.current?.phaseAnswers[2] == false)
    }

    /// Somebody who already trains for an hour is not offered "45 → 60".
    @Test("The diff is against the week as it is")
    func diffAgainstTheWeek() throws {
        let (arcs, vm, _) = world(week: ["water"])
        arcs.debugStart(.winter, daysAgo: 42)
        vm.setDuration("workout", minutes: 60)
        vm.setWeekday("workout", 4, on: true)
        let offer = try #require(arcs.phaseOffer())
        #expect(!offer.changes.contains { $0.id == "duration.workout" })
        #expect(!offer.changes.contains { $0.id == "days.workout" })
        #expect(offer.changes.contains { $0.id == "goal.pages" })
    }

    @Test("Leaving can keep everything the Arc added")
    func leaveKeeping() throws {
        let (arcs, vm, progress) = world(week: ["water", "read"])
        arcs.start(.monk, on: progress.currentDay)
        let week = vm.activeRitualIDs
        arcs.leave(takingOff: false)
        #expect(vm.activeRitualIDs == week)
        #expect(arcs.current == nil)
        #expect(arcs.enrollments.last?.leftOn == progress.currentDay)
    }

    @Test("Leaving can take off exactly what it added, and nothing else")
    func leaveTakingOff() throws {
        let (arcs, vm, progress) = world(week: ["water", "workout"])
        arcs.start(.monk, on: progress.currentDay)
        #expect(vm.activeRitualIDs.contains("focus"))
        arcs.leave(takingOff: true)
        // Work out was theirs before the Arc; it stays.
        #expect(vm.activeRitualIDs == ["water", "workout"])
        #expect(arcs.enrollments.count == 1, "left, and still on the record")
    }

    @Test("An Arc not yet begun is withdrawn, not left")
    func withdraw() {
        let (arcs, vm, progress) = world(week: ["water"])
        arcs.start(.monk, on: progress.currentDay.adding(days: 4))
        arcs.leave(takingOff: true)
        #expect(arcs.enrollments.isEmpty)
        #expect(vm.activeRitualIDs == ["water"])
    }

    @Test("A tally counts by hand and stays inside the trial")
    func tally() throws {
        let (arcs, _, _) = world()
        arcs.debugStart(.winter, daysAgo: 14)
        // Week three's trial is "Two cold showers".
        #expect(arcs.currentReading?.trial?.isTally == true)
        arcs.tally(1, trial: 2)
        arcs.tally(1, trial: 2)
        arcs.tally(1, trial: 2)
        #expect(arcs.currentReading?.trial?.count == 2)
        #expect(arcs.currentReading?.trial?.isMet == true)
        arcs.tally(-5, trial: 2)
        #expect(arcs.currentReading?.trial?.count == 0)
        // A trial the record counts cannot be counted by hand.
        arcs.tally(1, trial: 0)
        #expect(arcs.current?.tallies[0] == nil)
    }

    /// The first run writes the plan itself; the Arc only records that this
    /// is its week. A first run walked twice records the second answer.
    @Test("The first run starts the Arc it showed")
    func firstRun() throws {
        let (arcs, _, _) = world()
        arcs.startFromFirstRun(.winter, wake: 390, picks: [], added: ["wake", "steps"])
        #expect(arcs.current?.arc == .winter)
        #expect(arcs.current?.added == ["wake", "steps"])
        arcs.startFromFirstRun(.lockIn, wake: nil, picks: [], added: ["water"])
        #expect(arcs.enrollments.count == 1)
        #expect(arcs.current?.arc == .lockIn)
        // Lock In 7 adds nothing of its own: leaving never offers to take the
        // plan away.
        #expect(arcs.current?.added == [])
    }

    @Test("Finished Arcs stay on the record, and a winter is cut into the blade")
    func finished() {
        let (arcs, _, _) = world()
        arcs.debugStart(.winter, daysAgo: 95)
        #expect(arcs.current == nil)
        #expect(arcs.finished.count == 1)
        #expect(arcs.winterMarks.count == 1)
        #expect(arcs.finished.first.map(arcs.reading)?.status == .finished)
    }

    @Test("The first run's Arc rows are the Arc's activities, Discipline 66's three the plan's own")
    func firstRunRows() {
        let plan = [
            PlanEntry(dimension: .intellect, ritualID: "read", minute: 19 * 60),
            PlanEntry(dimension: .physical, ritualID: "walk", minute: 7 * 60),
            PlanEntry(dimension: .mental, ritualID: "breathe", minute: 7 * 60 + 15),
            PlanEntry(dimension: .discipline, ritualID: "wake", minute: 6 * 60 + 30),
        ]
        let winter = ArcPlan.firstRun(ArcCatalog.winter, plan: plan, find: Ritual.find)
        #expect(Set(winter.additions.map(\.id)) == Set(ArcCatalog.winter.activities.map(\.ritualID)))
        #expect(winter.picks.isEmpty)

        let sixtySix = ArcPlan.firstRun(ArcCatalog.discipline, plan: plan, find: Ritual.find)
        #expect(sixtySix.picks == ["read", "walk", "breathe"])
        #expect(Set(sixtySix.additions.map(\.id)) == ["wake", "read", "walk", "breathe"])
        #expect(sixtySix.additions.allSatisfy { $0.weekdays == ArcStandard.everyDay })
        #expect(sixtySix.additions.first { $0.id == "read" }?.minute == 19 * 60)
    }
}

// MARK: - The season

@Suite("Arcs: the winter")
struct ArcSeasonTests {

    @Test("The winter is the first of October to the last of January")
    func window() {
        #expect(ArcCatalog.isWinterSeason(ForgeDay(year: 2026, month: 10, day: 1)))
        #expect(ArcCatalog.isWinterSeason(ForgeDay(year: 2026, month: 12, day: 25)))
        #expect(ArcCatalog.isWinterSeason(ForgeDay(year: 2027, month: 1, day: 31)))
        #expect(!ArcCatalog.isWinterSeason(ForgeDay(year: 2027, month: 2, day: 1)))
        #expect(!ArcCatalog.isWinterSeason(ForgeDay(year: 2026, month: 9, day: 30)))
    }

    @Test("In the winter, Winter Arc is offered first")
    func order() {
        let october = ArcCatalog.offered(on: ForgeDay(year: 2026, month: 10, day: 1)).map(\.id)
        #expect(october == [.winter, .lockIn, .monk, .discipline])
        let june = ArcCatalog.offered(on: ForgeDay(year: 2026, month: 6, day: 1)).map(\.id)
        #expect(june == [.lockIn, .monk, .discipline, .winter])
    }

    @Test("A winter is named for the year it began")
    func recordName() {
        let october = ArcEnrollment(arc: .winter, startDay: ForgeDay(year: 2026, month: 10, day: 1))
        #expect(october.recordName == "Winter Arc 2026")
        let january = ArcEnrollment(arc: .winter, startDay: ForgeDay(year: 2027, month: 1, day: 12))
        #expect(january.recordName == "Winter Arc 2026")
        let monk = ArcEnrollment(arc: .monk, startDay: ForgeDay(year: 2027, month: 1, day: 12))
        #expect(monk.recordName == "Monk Mode 30")
    }
}

// MARK: - What is stored

@Suite("Arcs: what is stored")
struct ArcStorageTests {

    @Test("An enrollment round-trips")
    func roundTrip() throws {
        let enrollment = ArcEnrollment(
            arc: .discipline, startDay: ForgeDay(year: 2026, month: 10, day: 1),
            wakeMinute: 360, picks: ["read", "walk", "breathe"], added: ["wake", "walk"],
            isApplied: true, phaseAnswers: [0: true], tallies: [3: 2],
            leftOn: nil, joinedAt: Date(timeIntervalSinceReferenceDate: 800_000_000)
        )
        let data = try JSONEncoder().encode([enrollment])
        #expect(ArcEnrollment.decodeAll(data) == [enrollment])
    }

    /// One unreadable row must not cost somebody the Arcs they have finished.
    @Test("The decoder keeps what it can read and drops the rest")
    func tolerant() {
        let json = #"""
        [
          {"id": "a", "arc": "winter90", "startDay": {"year": 2026, "month": 10, "day": 1}},
          {"id": "b", "arc": "sprint5", "startDay": {"year": 2026, "month": 10, "day": 1}},
          {"id": "c", "arc": "monk30"},
          {"id": "d", "arc": "lockin7", "startDay": {"year": 2026, "month": 9, "day": 1},
           "phaseAnswers": {"0": true, "x": false}, "tallies": {"1": 3, "bad": 2, "2": -1},
           "picks": 7, "leftOn": "yesterday"}
        ]
        """#
        let decoded = ArcEnrollment.decodeAll(Data(json.utf8))
        #expect(decoded.map(\.id) == ["a", "d"])
        let winter = decoded[0]
        #expect(winter.isApplied)
        #expect(winter.added.isEmpty)
        #expect(winter.phaseAnswers.isEmpty)
        let lockIn = decoded[1]
        #expect(lockIn.phaseAnswers == [0: true])
        #expect(lockIn.tallies == [1: 3])
        #expect(lockIn.picks.isEmpty)
        #expect(lockIn.leftOn == nil)
    }

    @Test("Nothing that can be read off the record is stored")
    func storesNoCounts() throws {
        let enrollment = ArcEnrollment(arc: .winter, startDay: ForgeDay(year: 2026, month: 10, day: 1))
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(enrollment)) as? [String: Any]
        let keys = Set(object?.keys.map { $0 } ?? [])
        #expect(keys == ["id", "arc", "startDay", "picks", "added", "isApplied", "phaseAnswers", "tallies", "joinedAt"])
    }

    @Test("The store reads back what it wrote, under its versioned key")
    func store() throws {
        let suite = UserDefaults(suiteName: "forge.tests.arcs.\(UUID().uuidString)")!
        let progress = ProgressStore(defaults: suite)
        let first = ArcStore(progress: progress, defaults: suite)
        first.start(.lockIn, on: progress.currentDay)
        #expect(suite.data(forKey: "forge.arcs.v1") != nil)
        let second = ArcStore(progress: progress, defaults: suite)
        #expect(second.current?.arc == .lockIn)
    }
}

// MARK: - The tabs

@Suite("The tabs")
struct TabOrderTests {

    @Test("Forge, Arcs, Becoming, Blade")
    func order() {
        #expect(AppTab.allCases == [.forge, .arcs, .becoming, .blade])
        #expect(AppTab.allCases.map(\.label) == ["Forge", "Arcs", "Becoming", "Blade"])
        #expect(AppTab.settingsHosts == [.becoming, .blade])
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Forge")
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Settings stopped being a tab; it has to still be one tap from two of
    /// them, and a notification landing on Forge has to put it away.
    @Test("Settings is reachable from Becoming and Blade, and closes on a landing")
    func settingsReachable() throws {
        #expect(try source("Views/Becoming/BecomingTabView.swift").contains("SettingsButton(action: onSettings)"))
        #expect(try source("Views/Blade/BladeTabView.swift").contains("SettingsButton(action: onSettings)"))
        let root = try source("ContentView.swift")
        #expect(root.contains(".sheet(isPresented: $showSettings) { settingsTab }"))
        #expect(root.contains("onSettings: { showSettings = true }"))
        let landing = try #require(root.range(of: "private func landOnHome()"))
        let body = root[landing.upperBound...].prefix(300)
        #expect(body.contains("selectedTab = .forge"))
        #expect(body.contains("showSettings = false"))
    }
}

// MARK: - The morning

@Suite("Arcs: the morning")
struct ArcNotificationTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private let today = ForgeDay(year: 2026, month: 11, day: 10)

    private func state(arc: ArcNotice?) -> ForgeNotificationState {
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 5))!
        return ForgeNotificationState(
            now: now,
            currentDay: today,
            dayStartHour: 4,
            wakeMinutes: 6 * 60 + 30,
            completedToday: 0,
            plannedToday: 2,
            isTodayEarned: false,
            streak: 3,
            daysKept: 12,
            schedule: [
                ScheduledActivity(id: "wake", name: "Wake up", startMinute: 6 * 60 + 30, minutes: 0, weekdays: []),
                ScheduledActivity(id: "steps", name: "Hit your steps", startMinute: nil, minutes: 0, weekdays: []),
            ],
            arc: arc,
            calendar: calendar
        )
    }

    private func winter(startedDaysAgo days: Int) -> ArcNotice {
        ArcNotice(
            name: "Winter Arc",
            startDay: today.adding(days: -days),
            length: 90,
            phases: ArcCatalog.winter.phases.dropFirst().map { ArcNotice.Phase(name: $0.name, firstDay: $0.firstDay) }
        )
    }

    @Test("A running Arc puts its day in each morning, dated, a week ahead")
    func dayInTheMorning() {
        let plan = ForgeNotificationPlan.make(for: state(arc: winter(startedDaysAgo: 3)))
        let mornings = plan.filter { $0.kind == .morning }
        #expect(mornings.count == ForgeNotificationPlan.arcHorizon)
        #expect(mornings.allSatisfy { if case .once = $0.when { true } else { false } })
        #expect(mornings.first?.body.hasPrefix("Day 4 of 90.") == true)
        #expect(mornings.last?.body.hasPrefix("Day 10 of 90.") == true)
        #expect(Set(mornings.map(\.identifier)).count == mornings.count)
        for morning in mornings {
            #expect(!morning.body.localizedCaseInsensitiveContains("streak"))
            #expect(!morning.title.contains("!"))
        }
    }

    @Test("Without an Arc the mornings repeat, as they always have")
    func noArc() {
        let mornings = ForgeNotificationPlan.make(for: state(arc: nil)).filter { $0.kind == .morning }
        #expect(mornings.count == 1)
        #expect(mornings.allSatisfy { if case .once = $0.when { false } else { true } })
        #expect(mornings.allSatisfy { !$0.body.contains(" of 90") })
    }

    /// One notification on a phase change and one on the last day — each in
    /// place of that morning, never beside it.
    @Test("A phase change and the last day are said once, in place of the morning")
    func phaseAndLastDay() {
        let build = ForgeNotificationPlan.make(for: state(arc: winter(startedDaysAgo: 12)))
            .filter { $0.kind == .morning }
        // Day 13 today, so day 15 — Build — is two mornings out.
        let third = build[2]
        #expect(third.title == "Build starts today.")
        #expect(third.body.contains("day 15 of 90"))
        #expect(build.filter { $0.title.contains("starts today") }.count == 1)

        let end = ForgeNotificationPlan.make(for: state(arc: winter(startedDaysAgo: 86)))
            .filter { $0.kind == .morning }
        // Days 87 to 90, then three ordinary mornings after the end.
        #expect(end[3].title == "The last day of Winter Arc.")
        #expect(end[3].body.hasPrefix("Day 90 of 90."))
        #expect(end[4].body.contains("of 90") == false)
        #expect(end.count == ForgeNotificationPlan.arcHorizon)
    }

    @Test("A morning already past is not scheduled")
    func pastMorning() {
        var late = state(arc: winter(startedDaysAgo: 3))
        late.now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 9))!
        let mornings = ForgeNotificationPlan.make(for: late).filter { $0.kind == .morning }
        #expect(mornings.count == ForgeNotificationPlan.arcHorizon - 1)
        #expect(mornings.first?.body.hasPrefix("Day 5 of 90.") == true)
    }
}

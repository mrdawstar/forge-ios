import Foundation
import Testing
@testable import Forge

/// The numbers behind the analytics sheet.
///
/// Every one of these is a denominator argument rather than an arithmetic one —
/// the sums are trivial and the question is always *out of what*. A rate with
/// the wrong denominator is the easiest way an app like this lies to somebody,
/// and the three that matter are all here: a day that has not happened yet, a
/// weekday deliberately set aside, and an activity that did not exist yet.
@Suite("Analytics")
struct AnalyticsTests {

    private func makeStore() -> ProgressStore {
        let suite = UserDefaults(suiteName: "forge.tests.\(UUID().uuidString)") ?? .standard
        return ProgressStore(defaults: suite)
    }

    /// A day, written straight into history `back` days before today.
    @discardableResult
    private func day(
        _ store: ProgressStore,
        back: Int,
        planned: [String],
        done: [String],
        earned: Bool
    ) -> ForgeDay {
        let day = store.currentDay.adding(days: -back)
        store.record(
            DayRecord(
                day: day,
                completions: done.map {
                    DayRecord.Completion(ritualID: $0, method: .honor, at: day.startOfDay())
                },
                plannedIDs: planned,
                extractedAt: earned ? day.startOfDay() : nil
            )
        )
        return day
    }

    // MARK: - Completion rate

    @Test("Completion counts activities finished out of activities asked for")
    func completionRate() {
        let store = makeStore()
        day(store, back: 2, planned: ["water", "bed"], done: ["water", "bed"], earned: true)
        day(store, back: 1, planned: ["water", "bed"], done: ["water"], earned: false)

        let summary = store.analyticsSummary()
        #expect(summary.activitiesPlanned == 4)
        #expect(summary.activitiesCompleted == 3)
        #expect(summary.completionPercent == 75)
    }

    @Test("An empty history reads as empty rather than as nought percent")
    func emptyIsEmpty() {
        let summary = makeStore().analyticsSummary()
        #expect(summary.isEmpty)
        #expect(summary.completionRate == 0)
    }

    /// The bug this guards is the one that would make every rate on the sheet
    /// sag at midnight and recover by evening.
    @Test("Today is not counted against the day rate — it is not over")
    func todayIsNotAMiss() {
        let store = makeStore()
        day(store, back: 1, planned: ["water"], done: ["water"], earned: true)
        // Today, started and not finished.
        day(store, back: 0, planned: ["water"], done: [], earned: false)

        let summary = store.analyticsSummary()
        #expect(summary.daysPossible == 1)
        #expect(summary.daysKept == 1)
        #expect(summary.dayPercent == 100)
    }

    /// Somebody who rests on purpose must not be shown a permanent shortfall
    /// for doing exactly what they decided to do.
    @Test("A weekday set aside in Settings is not a day that could have been kept")
    func restWeekdaysAreNotADenominator() {
        let store = makeStore()
        for back in 1...7 { day(store, back: back, planned: ["water"], done: ["water"], earned: true) }
        let bare = store.analyticsSummary().daysPossible

        store.restWeekdays = [store.currentDay.adding(days: -1).weekday]
        #expect(store.analyticsSummary().daysPossible == bare - 1)
    }

    /// The bug: `daysKept` counted every earned day and `daysPossible` left the
    /// rest weekdays out, so the two came from different sets. Somebody who
    /// keeps their rest days read over a hundred per cent.
    @Test("The day rate's numerator and denominator come from the same days")
    func dayRateIsInternallyConsistent() {
        let store = makeStore()
        for back in 1...14 { day(store, back: back, planned: ["water"], done: ["water"], earned: true) }
        store.restWeekdays = [
            store.currentDay.adding(days: -1).weekday,
            store.currentDay.adding(days: -2).weekday,
        ]

        let summary = store.analyticsSummary()
        #expect(summary.daysKept <= summary.daysPossible)
        #expect(summary.dayPercent <= 100)
    }

    /// The other half of the same bug, and the one a brand-new user saw: the
    /// only day kept was today, today was not in the denominator, and the card
    /// read "1 of 0 days" at nought per cent.
    @Test("A first day that has been earned is counted, not divided by zero")
    func theFirstEarnedDayCounts() {
        let store = makeStore()
        day(store, back: 0, planned: ["water"], done: ["water"], earned: true)

        let summary = store.analyticsSummary()
        #expect(summary.daysPossible == 1)
        #expect(summary.daysKept == 1)
        #expect(summary.dayPercent == 100)
    }

    /// The completion rate used to run over every record, today's included, so
    /// it counted an unfinished morning as a shortfall — the exact failure the
    /// day rate beside it is written to avoid.
    @Test("An unfinished today does not drag the completion rate down")
    func todayDoesNotDragCompletion() {
        let store = makeStore()
        day(store, back: 1, planned: ["water", "bed"], done: ["water", "bed"], earned: true)
        day(store, back: 0, planned: ["water", "bed"], done: [], earned: false)

        let summary = store.analyticsSummary()
        #expect(summary.activitiesPlanned == 2)
        #expect(summary.activitiesCompleted == 2)
        #expect(summary.completionPercent == 100)
    }

    // MARK: - The year, as a timeline

    /// Months lived through before Forge existed for this person are not part of
    /// their record and are not drawn.
    @Test("The year starts at the month the record starts in")
    func theYearStartsWhereTheRecordDoes() {
        let store = makeStore()
        let today = store.currentDay
        day(store, back: 1, planned: ["water"], done: ["water"], earned: true)

        let reading = store.year(today.year)
        guard let first = reading.months.first else {
            Issue.record("no months")
            return
        }
        // Nothing before the month the history begins in.
        #expect(first.start.month >= store.currentDay.adding(days: -1).month)
        // And nothing is lost from the totals by trimming, because what is
        // trimmed is zeros.
        #expect(reading.kept == reading.months.reduce(0) { $0 + $1.kept })
    }

    /// The months ahead are the half of the year worth keeping: not recorded and
    /// not yet reached are different facts.
    @Test("Months after today are kept, and marked as ahead")
    func theYearKeepsWhatIsAhead() {
        let store = makeStore()
        day(store, back: 1, planned: ["water"], done: ["water"], earned: true)

        let reading = store.year(store.currentDay.year)
        let ahead = reading.months.filter { $0.isFuture }
        let aheadAreAllEmpty = ahead.filter { !$0.isEmpty }.isEmpty
        // December is always ahead unless the history starts in it.
        if store.currentDay.month < 12 {
            #expect(!ahead.isEmpty)
            #expect(aheadAreAllEmpty)
        }
        #expect(!reading.months.filter { !$0.isFuture }.isEmpty)
    }

    /// The same trim on the grid: thirty-five blank columns in front of
    /// somebody's first September is not their year.
    @Test("The year grid starts at the week the record starts in")
    func theGridStartsWhereTheRecordDoes() {
        let store = makeStore()
        day(store, back: 1, planned: ["water"], done: ["water"], earned: true)

        let grid = store.yearHeatmap(store.currentDay.year)
        #expect(grid.start <= store.currentDay)
        // Every column is still a whole week.
        let ragged = grid.columns.filter { $0.count != 7 }
        #expect(ragged.isEmpty)
        #expect(grid.columns.count == grid.restColumns.count)
    }

    /// The trends card's six-month window is clipped to the record for the same
    /// reason the year is: an empty bar reads as a month somebody let slide.
    @Test("The six-month trend window starts at the record, not six months ago")
    func trendsStartAtTheRecord() {
        let store = makeStore()
        day(store, back: 1, planned: ["water"], done: ["water"], earned: true)

        let months = store.trends().months
        #expect(months.count <= 6)
        #expect(months.count >= 1)
        // The current month is always the last one.
        #expect(months.last != nil)
        // Nothing before the month the record starts in.
        let startMonth = store.currentDay.adding(days: -1).month
        let stray = months.filter { Int($0.label) != nil }
        #expect(stray.isEmpty)
        if store.currentDay.adding(days: -1).year == store.currentDay.year {
            #expect(months.count == store.currentDay.month - startMonth + 1)
        }
        // An empty history is untrimmed — there is no record to clip to, and
        // the sheet draws its empty state rather than this card anyway.
        #expect(makeStore().trends().months.count == 6)
    }

    // MARK: - Habits

    @Test("A habit is rated over the days it was actually planned for")
    func habitDenominatorIsPlannedDays() {
        let store = makeStore()
        // Water every day; bed only on the last two.
        for back in 1...6 {
            let planned = back <= 2 ? ["water", "bed"] : ["water"]
            let done = back <= 2 ? ["water", "bed"] : ["water"]
            day(store, back: back, planned: planned, done: done, earned: true)
        }

        let rates = Dictionary(uniqueKeysWithValues: store.habitRates().map { ($0.id, $0) })
        #expect(rates["water"]?.planned == 6)
        #expect(rates["bed"]?.planned == 2)
        // Both were kept every time they were asked for, so neither is punished
        // for the days it did not exist.
        #expect(rates["water"]?.percent == 100)
        #expect(rates["bed"]?.percent == 100)
    }

    @Test("A habit with too little behind it is not worth reading")
    func shortSamplesAreWithheld() {
        let store = makeStore()
        for back in 1...3 { day(store, back: back, planned: ["water"], done: ["water"], earned: true) }
        #expect(store.habitRates().count == 1)
        #expect(store.readableHabitRates().isEmpty)
    }

    @Test("Habits come out best first")
    func habitsAreRanked() {
        let store = makeStore()
        for back in 1...8 {
            // Water always, bed half the time.
            day(
                store, back: back,
                planned: ["water", "bed"],
                done: back.isMultiple(of: 2) ? ["water", "bed"] : ["water"],
                earned: true
            )
        }
        let rates = store.readableHabitRates()
        #expect(rates.first?.id == "water")
        #expect(rates.last?.id == "bed")
        #expect(rates.first?.percent == 100)
        #expect(rates.last?.percent == 50)
    }

    // MARK: - The chain

    @Test("Every run is reported, longest first")
    func streakRunsAreListed() {
        let store = makeStore()
        // A run of three, a miss, then a run of two ending yesterday.
        for back in [7, 6, 5] { day(store, back: back, planned: ["water"], done: ["water"], earned: true) }
        day(store, back: 4, planned: ["water"], done: [], earned: false)
        for back in [2, 1] { day(store, back: back, planned: ["water"], done: ["water"], earned: true) }

        let runs = store.streakRuns()
        #expect(runs.count == 2)
        #expect(runs.map(\.length) == [3, 2])
        // The run that reaches yesterday is still going: today is not over.
        #expect(runs.first { $0.length == 2 }?.isCurrent == true)
        #expect(runs.first { $0.length == 3 }?.isCurrent == false)
    }

    @Test("The run in progress agrees with the chain the card shows")
    func runsAgreeWithTheStreak() {
        let store = makeStore()
        for back in 1...5 { day(store, back: back, planned: ["water"], done: ["water"], earned: true) }
        #expect(store.streakRuns().first?.length == store.currentStreak)
        #expect(store.streakRuns().first?.isCurrent == true)
        #expect(store.currentStreak == 5)
    }

    @Test("No history is no runs")
    func noRuns() {
        #expect(makeStore().streakRuns().isEmpty)
    }

    // MARK: - Consistency

    @Test("Weekly consistency returns the window asked for, oldest first")
    func weeklyWindow() {
        let store = makeStore()
        day(store, back: 1, planned: ["water"], done: ["water"], earned: true)
        let weeks = store.weeklyConsistency(weeks: 12)
        #expect(weeks.count == 12)
        #expect(weeks.map(\.start) == weeks.map(\.start).sorted())
    }

    /// A week before anything was recorded is *absent*, not nought — drawn as a
    /// gap rather than as a failure.
    /// **This test used to fail every Monday, and the store was never wrong.**
    ///
    /// It asserted `weeks.last?.isEmpty == false` after recording *yesterday*.
    /// On six days in seven, yesterday and today share a week, so the last
    /// bucket held the day and it passed. On a Monday — with this machine's
    /// `firstWeekday` of 2 — yesterday is Sunday and belongs to the *previous*
    /// bucket, so the current one was correctly empty and the assertion
    /// correctly failed.
    ///
    /// Two fixes were available and only one of them is honest.
    ///
    /// Recording *today* instead does not work, and the reason is worth
    /// keeping: `countsTowardRate` excludes today from every rate on purpose —
    /// "a day is not missed until it is over" — so a history whose only entry
    /// is today has nothing in any bucket at all. Reaching into `ProgressStore`
    /// to change that would break the rule the whole analytics sheet rests on
    /// in order to satisfy a test.
    ///
    /// So the test asserts against the bucket the day **actually lands in**,
    /// which is what it always meant. That is locale-independent, weekday-
    /// independent, and says the true thing: weeks before the history began are
    /// empty, and the week containing a kept day is not.
    @Test("A period before the history began is empty rather than zero")
    func untrackedPeriodsAreEmpty() {
        let store = makeStore()
        let kept = day(store, back: 1, planned: ["water"], done: ["water"], earned: true)
        let weeks = store.weeklyConsistency(weeks: 12)

        #expect(weeks.first?.isEmpty == true)
        #expect(weeks.first?.rate == 0)

        let bucket = weeks.last { $0.start <= kept }
        #expect(bucket != nil)
        #expect(bucket?.isEmpty == false)
    }

    @Test("Monthly consistency returns whole calendar months")
    func monthlyWindow() {
        let store = makeStore()
        day(store, back: 1, planned: ["water"], done: ["water"], earned: true)
        #expect(store.monthlyConsistency(months: 6).count == 6)
    }

    // MARK: - Years

    /// It used to be all twelve. It is the record's own months now — from the
    /// one it starts in to December — because the months before somebody
    /// installed Forge are not part of their year. See `ProgressStore.year(_:)`.
    @Test("A year runs from the month the record starts in to December")
    func yearBreakdown() {
        let store = makeStore()
        for back in 1...3 { day(store, back: back, planned: ["water"], done: ["water"], earned: true) }

        let reading = store.year(store.currentDay.year)
        let expected = max(1, 12 - store.currentDay.adding(days: -3).month + 1)
        #expect(reading.months.count <= 12)
        #expect(reading.months.count >= 1)
        // Trimming may only remove months that end before the history begins,
        // so the count is exactly December minus the starting month.
        if store.currentDay.adding(days: -3).year == store.currentDay.year {
            #expect(reading.months.count == expected)
        }
        // Days seeded within the last three could straddle a new year, so the
        // assertion is that the year holds what fell inside it rather than all
        // three — which is the property that would break if the month walk
        // leaked into a neighbouring year.
        let inYear = (1...3)
            .map { store.currentDay.adding(days: -$0) }
            .count { $0.year == store.currentDay.year }
        #expect(reading.kept == inYear)
    }

    @Test("Only years with something in them are offered")
    func availableYears() {
        let store = makeStore()
        #expect(store.availableYears().isEmpty)
        day(store, back: 1, planned: ["water"], done: ["water"], earned: true)
        #expect(store.availableYears().contains(store.currentDay.adding(days: -1).year))
    }

    /// Whole weeks, always — and it no longer starts in January for a history
    /// that does not. The leading blank columns are dropped and the year ahead
    /// is kept, so the grid is at most fifty-three columns and never ragged.
    @Test("The year grid is whole weeks, starting where the record does")
    func yearGridShape() {
        let store = makeStore()
        day(store, back: 1, planned: ["water"], done: ["water"], earned: true)
        let grid = store.yearHeatmap(store.currentDay.year)
        #expect(grid.columns.count <= 53)
        #expect(grid.columns.count >= 1)
        let ragged = grid.columns.filter { $0.count != 7 }
        #expect(ragged.isEmpty)
        #expect(grid.restColumns.count == grid.columns.count)
        // A year nobody has any record in is untouched: nothing to trim to.
        let older = store.yearHeatmap(store.currentDay.year - 1)
        #expect(older.columns.count == 53)
    }

    // MARK: - Subjects for milestones

    @Test("Every activity the history has asked for can be a milestone's subject")
    func knownActivities() {
        let store = makeStore()
        day(store, back: 2, planned: ["water", "bed"], done: ["water"], earned: false)
        day(store, back: 1, planned: ["water", "read"], done: ["water"], earned: false)
        #expect(Set(store.knownActivityIDs) == ["water", "bed", "read"])
    }

    @Test("An activity is counted once a day, however the day went")
    func timesCompleted() {
        let store = makeStore()
        for back in 1...4 { day(store, back: back, planned: ["read"], done: ["read"], earned: back < 3) }
        // Four days it was done, only two of which were earned — a milestone
        // about reading counts the reading, not the blade.
        #expect(store.timesCompleted("read") == 4)
        #expect(store.timesCompleted("water") == 0)
    }

    // MARK: - Heat levels

    @Test("The grid buckets a fraction into five filled steps")
    func heatLevels() {
        #expect(HeatLevel.of(0, isRest: false) == .none)
        #expect(HeatLevel.of(0.2, isRest: false) == .light)
        #expect(HeatLevel.of(0.5, isRest: false) == .some)
        #expect(HeatLevel.of(0.8, isRest: false) == .most)
        #expect(HeatLevel.of(1, isRest: false) == .full)
    }

    /// Somebody who rested and then did the day anyway did the day.
    @Test("Rest only shows where nothing was earned")
    func restLosesToWork() {
        #expect(HeatLevel.of(0, isRest: true) == .rest)
        #expect(HeatLevel.of(0.5, isRest: true) == .some)
    }

    // MARK: - The trail the widgets draw

    @Test("The trail is one mark a day, oldest first, ending yesterday")
    func trailShape() {
        let store = makeStore()
        let trail = store.heatTrail(days: 30)

        #expect(trail.marks.count == 30)
        #expect(trail.start == store.currentDay.adding(days: -30))
        // The last entry is yesterday. Today is the one day that can change
        // after this is written, and the snapshot carries it separately.
        #expect(trail.start.adding(days: trail.marks.count - 1) == store.currentDay.adding(days: -1))
    }

    @Test("A day's square and whether it was kept both survive the trip")
    func trailCarriesBothFacts() {
        let store = makeStore()
        day(store, back: 1, planned: ["water", "bed"], done: ["water", "bed"], earned: true)
        day(store, back: 2, planned: ["water", "bed"], done: ["water"], earned: false)

        let trail = store.heatTrail(days: 5)
        let yesterday = ForgeHeatMark(raw: trail.marks[4])
        let before = ForgeHeatMark(raw: trail.marks[3])

        #expect(yesterday?.level == .full)
        #expect(yesterday?.wasKept == true)
        #expect(before?.level == .some)
        #expect(before?.wasKept == false)
    }

    /// The one thing this file exists to prevent, applied to a picture: a grid
    /// that drew the weeks before somebody installed Forge as empty days would
    /// be telling them they failed days the app was not there for.
    @Test("Days before the record began are not days that were missed")
    func trailLeavesTheUnlivedAlone() {
        let store = makeStore()
        day(store, back: 2, planned: ["water"], done: ["water"], earned: true)

        let trail = store.heatTrail(days: 10)
        // Everything up to the first tracked day is outside the record.
        #expect(trail.marks[0] == ForgeHeatMark.beforeRecord)
        #expect(trail.marks[7] == ForgeHeatMark.beforeRecord)
        // The first tracked day, and everything after it, is inside it.
        #expect(trail.marks[8] != ForgeHeatMark.beforeRecord)
        #expect(trail.marks[9] != ForgeHeatMark.beforeRecord)
    }

    /// A day inside somebody's record that they simply did not keep is a real
    /// day and reads as one — the empty step of the ramp, not an absence.
    @Test("A missed day inside the record is an empty square, not a hole")
    func trailDrawsMissedDays() {
        let store = makeStore()
        day(store, back: 4, planned: ["water"], done: ["water"], earned: true)
        day(store, back: 1, planned: ["water"], done: [], earned: false)

        let trail = store.heatTrail(days: 6)
        // Three days in the middle with nothing written at all.
        let middle = ForgeHeatMark(raw: trail.marks[3])
        #expect(middle?.level == ForgeHeatLevel.none)
        #expect(middle?.wasKept == false)
    }
}

// MARK: - Where the days go

// MARK: - The Forge Shape

@Suite("Forge Shape")
struct ForgeShapeTests {

    private func makeStore() -> ProgressStore {
        let suite = UserDefaults(suiteName: "forge.tests.\(UUID().uuidString)") ?? .standard
        return ProgressStore(defaults: suite)
    }

    /// A day `back` days ago that asked for `planned` and got `done`.
    private func day(_ store: ProgressStore, back: Int, planned: [String], done: [String]) {
        let day = store.currentDay.adding(days: -back)
        store.record(DayRecord(
            day: day,
            completions: done.map {
                DayRecord.Completion(ritualID: $0, method: .honor, at: day.startOfDay())
            },
            plannedIDs: planned
        ))
    }

    private func activity(_ id: String) -> Ritual { Ritual.library.first { $0.id == id }! }
    /// run is physical, read is intellect, help is relationship.
    private var kept: [Ritual] { ["run", "read", "help"].map(activity) }

    private func dimension(
        _ store: ProgressStore, _ category: RitualCategory, of activities: [Ritual]? = nil
    ) -> ForgeShape.Dimension {
        store.forgeShape(of: activities ?? kept).dimensions.first { $0.category == category }!
    }

    // MARK: The arithmetic

    @Test("A dimension kept every day it was asked for, often enough, reads a hundred")
    func perfectAndPresentScoresFull() {
        let store = makeStore()
        for back in 1...14 { day(store, back: back, planned: ["run"], done: ["run"]) }

        #expect(dimension(store, .physical).score == 100)
    }

    @Test("Half the days kept is half the score")
    func halfKeptScoresHalf() {
        let store = makeStore()
        for back in 1...14 {
            day(store, back: back, planned: ["run"], done: back.isMultiple(of: 2) ? ["run"] : [])
        }

        #expect(dimension(store, .physical).score == 50)
    }

    @Test("Planning one easy thing once cannot buy a perfect score")
    func presenceFloorDefeatsTheObviousExploit() {
        let store = makeStore()
        day(store, back: 1, planned: ["run"], done: ["run"])

        let physical = dimension(store, .physical)
        // One day of eight is an eighth of the way to being present, so a
        // flawless record over one day reads as what it is.
        #expect(physical.score == 13)
        #expect(physical.score < 100)
    }

    @Test("Stacking activities into one dimension cannot inflate it")
    func scoreCountsDaysNotCompletions() {
        let store = makeStore()
        let many = ["run", "push", "lift", "walk", "workout"].map(activity)
        for back in 1...10 {
            day(store, back: back, planned: ["run"], done: ["run"])
        }
        let alone = ForgeShape.score(kept: 10, asked: 10)

        // The same ten days, with five physical activities kept instead of one.
        let store2 = makeStore()
        for back in 1...10 {
            day(store2, back: back,
                planned: ["run", "push", "lift", "walk", "workout"],
                done: ["run", "push", "lift", "walk", "workout"])
        }

        #expect(dimension(store2, .physical, of: many).score == alone,
                "five activities on one day is still one day")
    }

    @Test("A dimension is never answerable for days before it existed")
    func askedIsTheDenominator() {
        let store = makeStore()
        // Twenty-eight days of history, but reading was only ever asked for on
        // ten of them — and kept on all ten.
        for back in 1...28 {
            day(store, back: back,
                planned: back <= 10 ? ["run", "read"] : ["run"],
                done: back <= 10 ? ["run", "read"] : ["run"])
        }

        #expect(dimension(store, .intellect).asked == 10)
        #expect(dimension(store, .intellect).score == 100)
    }

    @Test("Nothing filed under a dimension leaves it unmeasured rather than zero")
    func untouchedDimensionsAreNotFailures() {
        let store = makeStore()
        for back in 1...14 { day(store, back: back, planned: ["run"], done: ["run"]) }

        let relationship = dimension(store, .relationship)
        #expect(relationship.hasActivities, "help is kept, so it is filed here")
        #expect(relationship.isMeasured == false, "but it was never planned")
        #expect(relationship.score == 0)
    }

    @Test("All six are always present, so the polygon never changes its number of sides")
    func alwaysSixDimensions() {
        let store = makeStore()
        #expect(store.forgeShape(of: kept).dimensions.count == 6)
        #expect(store.forgeShape(of: []).dimensions.count == 6)
    }

    // MARK: Direction

    @Test("A fortnight better than the one before it is rising")
    func directionRises() {
        let store = makeStore()
        for back in 15...28 { day(store, back: back, planned: ["run"], done: []) }
        for back in 1...14 { day(store, back: back, planned: ["run"], done: ["run"]) }

        #expect(dimension(store, .physical).direction == .rising)
    }

    @Test("A fortnight worse than the one before it is slipping")
    func directionSlips() {
        let store = makeStore()
        for back in 15...28 { day(store, back: back, planned: ["run"], done: ["run"]) }
        for back in 1...14 { day(store, back: back, planned: ["run"], done: []) }

        #expect(dimension(store, .physical).direction == .slipping)
    }

    @Test("A dimension taken up this week is not reported as progress")
    func directionNeedsBothHalves() {
        let store = makeStore()
        for back in 1...6 { day(store, back: back, planned: ["run"], done: ["run"]) }

        #expect(dimension(store, .physical).direction == .unknown,
                "an empty first half cannot be improved on")
    }

    @Test("One missed day is not a trend")
    func smallWobblesReadAsSteady() {
        let store = makeStore()
        for back in 15...28 { day(store, back: back, planned: ["run"], done: ["run"]) }
        for back in 1...14 {
            day(store, back: back, planned: ["run"], done: back == 3 ? [] : ["run"])
        }

        #expect(dimension(store, .physical).direction == .steady)
    }

    // MARK: The whole shape

    @Test("Overall averages all six, so breadth is what it measures")
    func overallCountsEverySide() {
        let store = makeStore()
        for back in 1...14 { day(store, back: back, planned: ["run"], done: ["run"]) }

        // Physical is full at a hundred. Running also feeds Mental and
        // Discipline as secondaries, and both reach 61 — a perfect rate, scaled
        // by what a secondary is worth. The three dimensions nothing was ever
        // planned for stay at zero. (100 + 61 + 61) / 6 = 37.
        #expect(store.forgeShape(of: kept).overall == 37)
    }

    @Test("Nothing is drawn until the record can say something")
    func shapeHidesItselfEarly() {
        let store = makeStore()
        day(store, back: 1, planned: ["run"], done: ["run"])
        #expect(store.forgeShape(of: kept).isReadable == false)

        for back in 1...6 {
            day(store, back: back, planned: ["run", "read"], done: ["run", "read"])
        }
        #expect(store.forgeShape(of: kept).isReadable)
    }

    @Test("A dimension nothing is filed under is never called neglected")
    func needsAttentionOnlyNamesAKeptDimension() {
        let store = makeStore()
        for back in 1...14 {
            day(store, back: back, planned: ["run", "read"], done: back <= 3 ? ["run", "read"] : ["run"])
        }

        let shape = store.forgeShape(of: kept)
        // Relationship scores zero but nothing was ever planned for it, so it is
        // not a weakness — intellect, which is kept and lagging, is.
        #expect(shape.needsAttention?.category == .intellect)
    }

    @Test("A level shape is not given a manufactured weakest link")
    func needsAttentionStaysQuietWhenEverythingIsEven() {
        let store = makeStore()
        for back in 1...14 {
            day(store, back: back, planned: ["run", "read"], done: ["run", "read"])
        }

        #expect(store.forgeShape(of: kept).needsAttention == nil)
    }

    @Test("Scores fall as well as rise")
    func theShapeCanShrink() {
        let store = makeStore()
        for back in 15...28 { day(store, back: back, planned: ["run"], done: ["run"]) }
        let before = store.forgeShape(of: kept).overall

        for back in 1...14 { day(store, back: back, planned: ["run"], done: []) }
        let after = store.forgeShape(of: kept).overall

        #expect(after < before, "a window that only ever rose would be a trophy, not a mirror")
    }
}

// MARK: - Filing an activity

@Suite("Dimensions")
struct DimensionTests {

    @Test("Every shipped activity is filed under a dimension")
    func libraryIsCompletelyFiled() {
        for ritual in Ritual.library {
            #expect(
                Ritual.categories[ritual.id] != nil,
                Comment(rawValue: "\(ritual.id) has no dimension")
            )
        }
    }

    @Test("Old stored categories migrate rather than vanishing")
    func storedValuesMigrate() {
        #expect(RitualCategory(migrating: "body") == .physical)
        #expect(RitualCategory(migrating: "fuel") == .physical)
        #expect(RitualCategory(migrating: "mind") == .intellect)
        #expect(RitualCategory(migrating: "home") == .discipline)
        #expect(RitualCategory(migrating: "focus") == .ambition)
        // And the new ones still read as themselves.
        #expect(RitualCategory(migrating: "mental") == .mental)
        #expect(RitualCategory(migrating: "nonsense") == nil)
    }

    @Test("The name suggests a dimension on the words people actually type")
    func suggestionReadsOrdinaryNames() {
        #expect(Ritual.suggestedCategory(for: "Morning run") == .physical)
        #expect(Ritual.suggestedCategory(for: "Read 20 pages") == .intellect)
        #expect(Ritual.suggestedCategory(for: "Call my mum") == .relationship)
        #expect(Ritual.suggestedCategory(for: "Deep work block") == .ambition)
        #expect(Ritual.suggestedCategory(for: "Meditate") == .mental)
        #expect(Ritual.suggestedCategory(for: "Make the bed") == .discipline)
    }

    @Test("A name it cannot read gets no guess rather than a wrong one")
    func suggestionShrugsRatherThanGuessing() {
        #expect(Ritual.suggestedCategory(for: "Zbrudge the wickets") == nil)
        #expect(Ritual.suggestedCategory(for: "") == nil)
        // Matched on whole words, so this is not a run.
        #expect(Ritual.suggestedCategory(for: "Runner beans") == nil)
    }

    @Test("Skipping the onboarding choice offers exactly what it always did")
    func emptyFocusFallsBackToTheShippedEight() {
        let offered = IdentityActivities.offered(forDimensions: [])
        #expect(offered == Array(IdentityActivities.unaimed.prefix(IdentityActivities.offerCount)))
    }

    @Test("What is offered looks like the answer that was given")
    func offerSpreadsAcrossChosenDimensions() {
        let offered = IdentityActivities.offeredRituals(
            forDimensions: [.physical, .relationship]
        )
        let categories = Set(offered.map(\.category))
        #expect(categories.contains(.physical))
        #expect(categories.contains(.relationship))
        #expect(offered.count == IdentityActivities.offerCount)
    }
}

// MARK: - More than one dimension

@Suite("Weighted dimensions")
struct WeightedDimensionTests {

    private func makeStore() -> ProgressStore {
        let suite = UserDefaults(suiteName: "forge.tests.\(UUID().uuidString)") ?? .standard
        return ProgressStore(defaults: suite)
    }

    private func day(_ store: ProgressStore, back: Int, planned: [String], done: [String]) {
        let day = store.currentDay.adding(days: -back)
        store.record(DayRecord(
            day: day,
            completions: done.map {
                DayRecord.Completion(ritualID: $0, method: .honor, at: day.startOfDay())
            },
            plannedIDs: planned
        ))
    }

    private func activity(_ id: String) -> Ritual { Ritual.library.first { $0.id == id }! }

    private func dimension(
        _ store: ProgressStore, _ category: RitualCategory, of activities: [Ritual]
    ) -> ForgeShape.Dimension {
        store.forgeShape(of: activities).dimensions.first { $0.category == category }!
    }

    @Test("An activity feeds the dimensions it genuinely touches")
    func aRunAlsoBuildsMental() {
        let run = activity("run")
        let weights = run.dimensionWeights

        #expect(weights[.physical] == 1, "what it is filed under is a whole day")
        #expect(weights[.mental] == Ritual.secondaryWeight)
        #expect(weights[.discipline] == Ritual.secondaryWeight)
        #expect(weights[.intellect] == nil, "a run is not reading")
    }

    @Test("A secondary contribution is worth less than the thing it is secondary to")
    func secondariesScoreLowerThanPrimaries() {
        let store = makeStore()
        for back in 1...14 { day(store, back: back, planned: ["run"], done: ["run"]) }
        let shape = store.forgeShape(of: [activity("run")])

        let physical = shape.dimensions.first { $0.category == .physical }!
        let mental = shape.dimensions.first { $0.category == .mental }!

        #expect(physical.score == 100)
        #expect(mental.isMeasured, "running does feed it")
        #expect(mental.score < physical.score, "but not as much as running feeds Physical")
    }

    @Test("Collecting many-tagged activities cannot fill the shape")
    func taggingCannotBeFarmed() {
        let store = makeStore()
        // Three activities that all carry secondaries, kept flawlessly for a
        // fortnight. All three are filed under Physical, so Mental and
        // Discipline are reached *only* as secondaries — which is the case this
        // test exists for. (`cold` is deliberately not used here: it is filed
        // under Mental outright, so it would feed that dimension in full and
        // prove nothing.)
        let farmed = ["run", "push", "workout"].map(activity)
        let ids = farmed.map(\.id)
        for back in 1...14 { day(store, back: back, planned: ids, done: ids) }

        let shape = store.forgeShape(of: farmed)
        // The dimensions those activities are actually filed under are full.
        #expect(shape.dimensions.first { $0.category == .physical }!.score == 100)
        // The ones they merely touch are not, and the shape as a whole is not.
        #expect(shape.dimensions.first { $0.category == .mental }!.score < 100)
        #expect(shape.overall < 70, "three activities cannot be a whole person")
        #expect(shape.dimensions.first { $0.category == .relationship }!.score == 0)
    }

    @Test("A day is worth at most one day, however many activities are on it")
    func creditIsCappedPerDay() {
        let store = makeStore()
        let many = ["run", "push", "lift", "walk", "workout"].map(activity)
        let ids = many.map(\.id)
        for back in 1...14 { day(store, back: back, planned: ids, done: ids) }

        let physical = dimension(store, .physical, of: many)
        #expect(physical.kept == 14, "fourteen days, not seventy completions")
        #expect(physical.score == 100)
    }

    @Test("A dimension fed only by secondaries is not punished for it")
    func secondaryOnlyDimensionsAreScoredFairly() {
        let store = makeStore()
        // Running is the only thing feeding Mental, and it never misses.
        for back in 1...28 { day(store, back: back, planned: ["run"], done: ["run"]) }

        let mental = dimension(store, .mental, of: [activity("run")])
        // The rate is perfect, so the score is limited only by how much a
        // secondary is worth — not driven to nothing.
        #expect(mental.score > 0)
        #expect(mental.kept == mental.asked, "kept every day it was asked for")
    }

    @Test("A custom activity's extra dimensions come from its own name")
    func customActivitiesInferTheirSecondaries() {
        var made = Ritual(id: "custom.x", label: "Cold water swim", iconKey: "drop", sub: "", tail: "")
        made.isCustom = true
        made.categoryOverride = .mental

        let weights = made.dimensionWeights
        #expect(weights[.mental] == 1)
        #expect(weights[.physical] == Ritual.secondaryWeight, "swim and cold are both physical signals")
    }

    @Test("A library activity with no listed secondaries feeds only its own dimension")
    func mostActivitiesStaySingle() {
        #expect(activity("teeth").dimensionWeights.count == 1)
    }

    /// The projection test that found this compared two reads of the same
    /// plan and got 21.75 against 21.750000000000004: the days had been added
    /// up in each dictionary's own order. Weights of a tenth, two tenths and
    /// three tenths are the kind whose sum depends on the order.
    @Test("The same record adds up to the same number, however its dictionary was built")
    func creditIsSummedInDayOrder() {
        let last = ForgeDay(year: 2026, month: 10, day: 1)
        let weights: ForgeShape.Weights = ["a": 0.1, "b": 0.2, "c": 0.3, "d": 0.7]
        let ids = ["a", "b", "c", "d"]
        let records = (0..<28).map { back -> DayRecord in
            let day = last.adding(days: -back)
            let id = ids[back % ids.count]
            return DayRecord(
                day: day,
                completions: [DayRecord.Completion(ritualID: id, method: .honor, at: day.startOfDay())],
                plannedIDs: [id]
            )
        }

        var forwards: [ForgeDay: DayRecord] = [:]
        for record in records { forwards[record.day] = record }
        var backwards: [ForgeDay: DayRecord] = [:]
        backwards.reserveCapacity(4096)
        for record in records.reversed() { backwards[record.day] = record }

        // Oldest day first, by hand.
        var expected = 0.0
        for record in records.sorted(by: { $0.day < $1.day }) {
            expected += weights[record.plannedIDs[0]] ?? 0
        }

        let first = last.adding(days: -27)
        for byDay in [forwards, backwards] {
            for planned in [true, false] {
                let total = ForgeShape.creditedDays(byDay, weights, from: first, to: last, planned: planned)
                #expect(total.bitPattern == expected.bitPattern, Comment(rawValue: "\(total) against \(expected)"))
            }
        }
    }
}

// MARK: - What to add

@Suite("Suggestions")
struct SuggestionTests {

    @Test("Every dimension has real things to suggest")
    func everyDimensionCanBeStrengthened() {
        for dimension in RitualCategory.dimensions {
            let offered = ForgeShape.suggestions(for: dimension, avoiding: [])
            #expect(
                offered.count == 3,
                Comment(rawValue: "\(dimension.label) offers only \(offered.count)")
            )
        }
    }

    @Test("Nothing already kept is suggested")
    func suggestionsSkipWhatIsHeld() {
        let all = Set(Ritual.library.filter { $0.category == .relationship }.map(\.id))
        #expect(ForgeShape.suggestions(for: .relationship, avoiding: all).isEmpty)
    }

    @Test("The smallest thing is offered first")
    func suggestionsLeadWithTheEasiest() {
        let offered = ForgeShape.suggestions(for: .ambition, avoiding: [])
        let efforts = offered.map { IdentityActivities.effort(of: $0.id) }
        #expect(efforts == efforts.sorted())
    }

    @Test("Everything suggested is filed under the dimension it was asked for")
    func suggestionsAreOnTopic() {
        for dimension in RitualCategory.dimensions {
            for ritual in ForgeShape.suggestions(for: dimension, avoiding: []) {
                #expect(
                    ritual.category == dimension,
                    Comment(rawValue: "\(ritual.id) is not \(dimension.label)")
                )
            }
        }
    }
}

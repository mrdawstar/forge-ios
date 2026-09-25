import Foundation
import Testing
@testable import Forge

/// Earned rest days are the one mechanic in Forge that decides whether somebody
/// who missed a Tuesday is still here in March. Every rule of it is checked
/// here: what earns one, what spends one, what the ceiling does, and what
/// happens when it meets the four-in-the-day day boundary.
@Suite("Rest days")
struct RestDayTests {

    private func makeStore() -> ProgressStore {
        let suite = UserDefaults(suiteName: "forge.tests.\(UUID().uuidString)") ?? .standard
        return ProgressStore(defaults: suite)
    }

    /// A finished day, `back` days before today.
    private func earn(_ store: ProgressStore, daysAgo back: Int) {
        let day = store.currentDay.adding(days: -back)
        store.record(
            DayRecord(
                day: day,
                completions: [
                    DayRecord.Completion(ritualID: "water", method: .honor, at: day.startOfDay())
                ],
                plannedIDs: ["water"],
                extractedAt: day.startOfDay()
            )
        )
    }

    /// An unbroken run ending `endingDaysAgo` days back.
    private func earn(_ store: ProgressStore, days: Int, endingDaysAgo: Int = 0) {
        for offset in 0..<days {
            earn(store, daysAgo: endingDaysAgo + offset)
        }
    }

    // MARK: - Accrual

    @Test("Six days earn nothing")
    func sixEarnsNothing() {
        let store = makeStore()
        earn(store, days: 6)
        #expect(store.currentStreak == 6)
        #expect(store.bankedRest == 0)
    }

    @Test("Seven days earn one rest day")
    func sevenEarnsOne() {
        let store = makeStore()
        earn(store, days: 7)
        #expect(store.currentStreak == 7)
        #expect(store.bankedRest == 1)
    }

    @Test("Fourteen days earn two")
    func fourteenEarnsTwo() {
        let store = makeStore()
        earn(store, days: 14)
        #expect(store.bankedRest == 2)
    }

    /// The ceiling. Rest is for the week you are ill, not a balance to build.
    @Test("The bank stops at two, however long the run", arguments: [21, 28, 60])
    func bankIsCapped(days: Int) {
        let store = makeStore()
        earn(store, days: days)
        #expect(store.bankedRest == ProgressStore.maxBankedRest)
        #expect(store.currentStreak == days)
    }

    /// Reaching the ceiling still resets progress toward the next one, so
    /// spending a rest day does not hand back a replacement the same day.
    @Test("A run past the ceiling does not refill instantly when one is spent")
    func ceilingDoesNotRefillInstantly() {
        let store = makeStore()
        // Twenty-one days, then a miss, and today is untouched.
        earn(store, days: 21, endingDaysAgo: 2)
        // Day 1 back is missed; the run is 21 with one rest spent from two.
        #expect(store.currentStreak == 21)
        #expect(store.bankedRest == 1)
    }

    // MARK: - Consumption

    @Test("A missed day spends a rest day and the chain carries on")
    func missSpendsRest() {
        let store = makeStore()
        earn(store, days: 7, endingDaysAgo: 2)   // days 8…2 back
        earn(store, daysAgo: 0)                       // today earned; day 1 missed

        #expect(store.currentStreak == 8)
        #expect(store.bankedRest == 0)
        #expect(store.lastRestDay == store.currentDay.adding(days: -1))
    }

    @Test("Two misses spend both, and the third breaks the chain")
    func restRunsOut() {
        let store = makeStore()
        earn(store, days: 14, endingDaysAgo: 4)   // days 17…4 back
        // Days 3, 2 and 1 back are all missed.
        earn(store, daysAgo: 0)

        #expect(store.bankedRest == 0)
        // The chain died on the third miss, so only today is left standing.
        #expect(store.currentStreak == 1)
    }

    @Test("With nothing banked a miss breaks the chain")
    func missWithoutRestBreaks() {
        let store = makeStore()
        earn(store, days: 3, endingDaysAgo: 2)
        earn(store, daysAgo: 0)
        #expect(store.currentStreak == 1)
        #expect(store.bankedRest == 0)
    }

    /// A rest day is not a day. It keeps the chain alive without pretending
    /// something was done.
    @Test("Rest keeps the chain but does not lengthen it")
    func restDoesNotCount() {
        let store = makeStore()
        earn(store, days: 7, endingDaysAgo: 2)
        earn(store, daysAgo: 0)
        // Seven days plus today, with the missed day merely survived.
        #expect(store.currentStreak == 8)
    }

    @Test("A broken chain forgets the rest it took")
    func breakClearsTheNote() {
        let store = makeStore()
        earn(store, days: 7, endingDaysAgo: 5)   // days 11…5 back
        // Day 4 back is covered by the banked rest. Days 3, 2, 1 are not.
        earn(store, daysAgo: 0)
        #expect(store.currentStreak == 1)
        #expect(store.lastRestDay == nil)
    }

    // MARK: - Today

    /// The rule that makes the whole thing bearable: a day is not missed
    /// until it is over, so nothing is spent on today at nine in the morning.
    @Test("Today does not spend a rest day while it is still today")
    func todayIsNotAMiss() {
        let store = makeStore()
        earn(store, days: 7, endingDaysAgo: 1)   // days 7…1 back, today blank
        #expect(store.currentStreak == 7)
        #expect(store.bankedRest == 1)
        #expect(store.lastRestDay == nil)
    }

    // MARK: - Configured rest days

    /// A weekday somebody set aside in Settings was never a day. It costs
    /// nothing, because there was nothing to miss.
    @Test("A configured rest weekday does not spend a banked rest day")
    func configuredRestIsFree() {
        let store = makeStore()
        // Set aside the weekday two days back, then leave that day empty.
        let skipped = store.currentDay.adding(days: -2)
        store.restWeekdays = [skipped.weekday]

        earn(store, daysAgo: 4)
        earn(store, daysAgo: 3)
        earn(store, daysAgo: 1)
        earn(store, daysAgo: 0)

        #expect(store.currentStreak == 4)
        #expect(store.bankedRest == 0)
        #expect(store.lastRestDay == nil)
    }

    // MARK: - Day boundary

    /// Rest accrual is counted in `ForgeDay`s, so it inherits the four o'clock
    /// boundary for free — a day finished at 01:50 belongs to the day before
    /// and cannot leave a hole for a rest day to fill.
    @Test("A day finished after midnight does not cost a rest day")
    func afterMidnightIsNotAMiss() throws {
        let store = makeStore()
        store.dayStartHour = 4

        // Six days, the last of them earned at 01:50 by the clock — which
        // is still the day before, so it leaves no hole behind it.
        earn(store, days: 6, endingDaysAgo: 1)
        let late = store.currentDay.adding(days: -1)
        let afterMidnight = Calendar.current.date(
            bySettingHour: 1, minute: 50, second: 0, of: late.adding(days: 1).startOfDay()
        )
        #expect(ForgeDay.containing(try #require(afterMidnight), dayStartHour: 4) == late)

        #expect(store.currentStreak == 6)
        #expect(store.bankedRest == 0)
    }

    /// Changing the day-start does not invent or destroy rest days: the history
    /// is already labelled, and the labels do not move.
    @Test("Moving the day-start hour leaves banked rest alone")
    func dayStartDoesNotRewriteHistory() {
        let store = makeStore()
        earn(store, days: 7, endingDaysAgo: 1)
        #expect(store.bankedRest == 1)

        store.dayStartHour = 6
        #expect(store.bankedRest == 1)
        #expect(store.currentStreak == 7)
    }

    // MARK: - A rested chain is one chain

    /// The property this has always been about: a covered day does not split a
    /// run in two. Read off `streakRuns()` now that no longest-streak figure
    /// exists anywhere in the app — see `ProgressStore.StreakState`.
    @Test("A rested chain is recorded as one unbroken run")
    func restDoesNotSplitARun() {
        let store = makeStore()
        earn(store, days: 7, endingDaysAgo: 2)
        earn(store, daysAgo: 0)
        #expect(store.streakRuns().map(\.length) == [8])
    }

    // MARK: - The grid

    @Test("A rested day is marked in the heatmap rather than left blank")
    func heatmapMarksRest() {
        let store = makeStore()
        earn(store, days: 7, endingDaysAgo: 2)
        earn(store, daysAgo: 0)

        let map = store.heatmap()
        let rested = store.currentDay.adding(days: -1)
        let marked: Set<ForgeDay> = Set(
            map.restColumns.enumerated().flatMap { week, column in
                column.enumerated().compactMap { row, isRest in
                    isRest ? map.start.adding(days: week * 7 + row) : nil
                }
            }
        )
        #expect(marked == [rested])
    }

    // MARK: - Nothing is sold

    /// Forge has no way to acquire a rest day except by earning one. This is a
    /// product promise, and it is cheapest to keep by making it impossible to
    /// break: there is no setter, anywhere.
    @Test("Rest days are read-only from outside the history")
    func restIsDerivedOnly() {
        let store = makeStore()
        earn(store, days: 7)
        #expect(store.bankedRest == 1)
        // Wiping the history wipes the rest that came from it. Nothing survives
        // that the days did not pay for.
        store.clearHistory()
        #expect(store.bankedRest == 0)
        #expect(store.currentStreak == 0)
    }
}

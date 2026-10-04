import Foundation
import Testing
@testable import Forge

/// The two pieces of arithmetic the 1.1 release pass was asked to measure on
/// the main thread (FORGE_CONTEXT §17.7): the onboarding's projection, worked
/// out in the tap that leaves the build beat and immediately before the
/// drawing animates, and what the Becoming tab's grid reads every time its
/// body is drawn.
///
/// **The budget is one frame at 120 Hz — 8.3 ms — for each**, as the fastest
/// of fifteen runs, with the heaviest realistic input: all six dimensions in
/// the plan, and two years of a record with a challenge most days. Measured
/// in the Simulator on the build machine, which is a different CPU from an
/// iPhone's; the numbers are printed so §17.7 can say what they were, and the
/// budget leaves room for a slower phone. Nothing here may grow into a hitch
/// unnoticed.
@Suite("Budgets: one frame on the main thread")
struct BudgetTests {

    static let frame: Duration = .microseconds(8_333)

    /// The fastest of fifteen runs: suites run side by side, and the
    /// fastest is the one that had the processor to itself — the work's own
    /// cost, which is what the budget is about.
    private func measured(_ runs: Int = 15, _ work: () -> Void) -> Duration {
        let clock = ContinuousClock()
        work() // warm
        let times = (0..<runs).map { _ in clock.measure(work) }.sorted()
        print("Budget: fastest \(times[0]), median \(times[runs / 2])")
        return times[0]
    }

    private let today = ForgeDay(year: 2026, month: 10, day: 4)

    /// Every question answered, from the middle of each scale.
    private var assessment: Assessment {
        Assessment(
            day: today.adding(days: -30),
            answers: Dictionary(uniqueKeysWithValues: Assessment.Question.allCases.map { ($0, 1) })
        )
    }

    /// Two years of a week of eight, kept on four days in five, and a daily
    /// challenge on most of them.
    private var twoYears: (byDay: [ForgeDay: DayRecord], activities: [Ritual], challenges: [ForgeDay: RitualCategory]) {
        let ids = ["walk", "read", "wake", "breathe", "call", "deep", "steps", "workout"]
        let activities = ids.compactMap(Ritual.find)
        var byDay: [ForgeDay: DayRecord] = [:]
        var challenges: [ForgeDay: RitualCategory] = [:]
        for back in 0..<730 {
            let day = today.adding(days: -back)
            let at = day.startOfDay().addingTimeInterval(9 * 3_600)
            let kept = back % 5 != 0
            byDay[day] = DayRecord(
                day: day,
                completions: activities.prefix(kept ? 8 : 3).map {
                    DayRecord.Completion(ritualID: $0.id, method: .honor, at: at)
                },
                plannedIDs: activities.map(\.id),
                extractedAt: kept ? at : nil
            )
            if back % 3 != 0 { challenges[day] = RitualCategory.dimensions[back % 6] }
        }
        return (byDay, activities, challenges)
    }

    /// The cheap step is only worth having if it is the calendar's step.
    @Test("The day after is the calendar's day after, every day from 1970 to 2200, and odd days fall back")
    func nextIsTheCalendarsNext() {
        var day = ForgeDay(year: 1970, month: 1, day: 1)
        var walked = 0
        while day.year < 2201 {
            let next = day.next
            #expect(next == day.adding(days: 1), Comment(rawValue: "\(day)"))
            day = next
            walked += 1
        }
        #expect(walked > 84_000)
        for odd in [
            ForgeDay(year: 2026, month: 2, day: 30), ForgeDay(year: 2026, month: 13, day: 1),
            ForgeDay(year: 1_000_000, month: 1, day: 1), ForgeDay(year: Int.max, month: 12, day: 31),
        ] {
            #expect(odd.next == odd.adding(days: 1), Comment(rawValue: "\(odd)"))
        }
    }

    @Test("The onboarding projection, all six in the plan, fits in one frame")
    func projection() {
        let assessment = assessment
        let plan = OnboardingPlan.propose(focus: Set(RitualCategory.dimensions), assessment: assessment)
            .compactMap(\.ritual)
        #expect(plan.count == 6)
        let time = measured { _ = Transformation.frames(plan: plan, assessment: assessment) }
        print("Budget: Transformation.frames, six activities: \(time)")
        #expect(time < Self.frame, Comment(rawValue: "\(time)"))
    }

    @Test("Becoming's grid — the six now and a week ago, on two years — fits in one frame")
    func becomingGrid() {
        let (byDay, activities, challenges) = twoYears
        let assessment = assessment
        let time = measured {
            let now = BlendedShape.read(
                byDay, today: today, activities: activities, assessment: assessment, challenges: challenges
            )
            let weekAgo = StatGlance.weekAgo(
                byDay, today: today, activities: activities, assessment: assessment, challenges: challenges
            )
            _ = StatGlance.tiles(now: now, weekAgo: weekAgo, focus: [.discipline])
        }
        print("Budget: Becoming grid, two years: \(time)")
        #expect(time < Self.frame, Comment(rawValue: "\(time)"))
    }

    @Test("The record's own counts on two years fit in one frame")
    func record() throws {
        let suite = "forge.budget.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let (byDay, _, _) = twoYears
        defaults.set(try JSONEncoder().encode(Array(byDay.values)), forKey: "forge.history.v1")
        let progress = ProgressStore(defaults: defaults)
        let time = measured {
            _ = progress.daysKept
            _ = progress.currentStreak
        }
        print("Budget: days kept and streak, two years: \(time)")
        #expect(time < Self.frame, Comment(rawValue: "\(time)"))
        defaults.removePersistentDomain(forName: suite)
    }
}

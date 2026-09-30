import Foundation
import Testing
@testable import Forge

/// The six and OVR as every screen shows them: answers handing over to the
/// record.
///
/// Every test here runs the pure readings (`ForgeShape.read`,
/// `BlendedShape.read`) over records built in memory on fixed days, so none of
/// them depends on the day they are run on — the trap `AnalyticsTests` has on
/// Mondays cannot happen here.
@Suite("Blended shape")
struct BlendedShapeTests {

    /// The assessment day every test counts from.
    private let start = ForgeDay(year: 2026, month: 10, day: 1)

    private func activity(_ id: String) -> Ritual { Ritual.find(id)! }

    /// Everything answered at `index`, sleep six to seven hours (no change).
    /// Index 1 is Physical 30, Discipline 30, Mental 25, Intellect 30,
    /// Relationship 30, Ambition 30.
    private func assessment(_ index: Int = 1, _ overrides: [Assessment.Question: Int] = [:]) -> Assessment {
        var picks = Dictionary(uniqueKeysWithValues: Assessment.Question.allCases.map { ($0, index) })
        picks[.sleep] = 1
        for (question, value) in overrides { picks[question] = value }
        return Assessment(day: start, answers: picks)
    }

    private func record(_ day: ForgeDay, planned: [String], done: [String]) -> DayRecord {
        DayRecord(
            day: day,
            completions: done.map {
                DayRecord.Completion(ritualID: $0, method: .honor, at: day.startOfDay())
            },
            plannedIDs: planned,
            extractedAt: done.isEmpty ? nil : day.startOfDay()
        )
    }

    /// `water` planned on each of `days` days from `first`, kept where `kept`
    /// says so. Water is Physical and touches nothing else, so these tests are
    /// about one dimension at a time.
    private func history(
        _ id: String = "water", from first: ForgeDay, days: Int, kept: (Int) -> Bool = { _ in true }
    ) -> [ForgeDay: DayRecord] {
        var records: [ForgeDay: DayRecord] = [:]
        for index in 0..<days {
            let day = first.adding(days: index)
            records[day] = record(day, planned: [id], done: kept(index) ? [id] : [])
        }
        return records
    }

    private func physical(
        _ records: [ForgeDay: DayRecord], today: ForgeDay, _ answers: Assessment?, activities: [String] = ["water"]
    ) -> BlendedShape.Dimension {
        BlendedShape.read(
            records, today: today, activities: activities.map(activity), assessment: answers
        ).dimension(.physical)!
    }

    // MARK: - No assessment

    @Test("With no assessment the six, OVR and the word are exactly today's ForgeShape")
    func noAssessmentIsTheRecord() {
        let today = start.adding(days: 30)
        let kept = ["run", "read", "help"]
        var mixed: [ForgeDay: DayRecord] = [:]
        for back in 1...28 {
            let day = today.adding(days: -back)
            mixed[day] = record(
                day, planned: ["run", "read"],
                done: (back.isMultiple(of: 2) ? ["run"] : []) + (back <= 10 ? ["read"] : [])
            )
        }
        var settled = mixed
        settled[today] = record(today, planned: ["run", "read"], done: ["run"])

        let histories: [[ForgeDay: DayRecord]] = [
            [:],
            history("run", from: today.adding(days: -14), days: 14),
            mixed,
            settled,
        ]
        for records in histories {
            let shape = ForgeShape.read(records, today: today, activities: kept.map(activity))
            let blended = BlendedShape.read(
                records, today: today, activities: kept.map(activity), assessment: nil
            )
            #expect(blended.dimensions.map(\.score) == shape.dimensions.map(\.score))
            #expect(blended.dimensions.map(\.hasScore) == shape.dimensions.map(\.isMeasured))
            #expect(blended.dimensions.map(\.direction) == shape.dimensions.map(\.direction))
            #expect(blended.dimensions.allSatisfy { $0.source == .record })
            #expect(blended.overall == shape.overall)
            #expect(blended.state == shape.state)
            #expect(blended.isReadable == shape.isReadable)
            #expect(blended.needsAttention == shape.needsAttention)
            #expect(!blended.hasAssessment)
        }
    }

    @Test("The store's reading is the pure one")
    func theStoreReadsThePureFunction() {
        let suite = UserDefaults(suiteName: "forge.tests.\(UUID().uuidString)") ?? .standard
        let store = ProgressStore(defaults: suite)
        for back in 1...9 {
            store.record(record(store.currentDay.adding(days: -back), planned: ["run"], done: ["run"]))
        }
        let activities = [activity("run")]
        #expect(store.forgeShape(of: activities)
                == ForgeShape.read(store.byDay, today: store.currentDay, activities: activities))
    }

    // MARK: - The blend

    @Test("At nought days the answers are the whole of it")
    func blendAtNought() {
        // Planned today, nothing kept yet.
        let records = [start: record(start, planned: ["water"], done: [])]
        let dimension = physical(records, today: start, assessment())
        #expect(dimension.source == .answers)
        #expect(dimension.score == 30)
        #expect(dimension.direction == .unknown)

        // Never planned at all: the same number, the same source.
        let untouched = BlendedShape.read([:], today: start, activities: [], assessment: assessment())
        #expect(untouched.dimensions.allSatisfy { $0.source == .answers })
        #expect(untouched.dimension(.mental)?.score == 25)
    }

    @Test("At fourteen days the record carries half")
    func blendAtFourteen() {
        let today = start.adding(days: 14)
        var records = history(from: start, days: 14)
        records[today] = record(today, planned: ["water"], done: [])

        let full = physical(records, today: today, assessment())
        #expect(full.source == .blend(days: 14))
        #expect(full.score == 65, "½ × 100 + ½ × 30")
        #expect(full.answersWeight == 0.5)

        // Kept on half the days it was asked for: ½ × 50 + ½ × 30.
        let half = physical(
            history(from: start, days: 14) { $0.isMultiple(of: 2) }, today: today, assessment()
        )
        #expect(half.score == 40)

        // The same fourteen days, counted with today kept rather than over.
        let lastDay = start.adding(days: 13)
        var settled = history(from: start, days: 13)
        settled[lastDay] = record(lastDay, planned: ["water"], done: ["water"])
        #expect(physical(settled, today: lastDay, assessment()).score == 65)
    }

    @Test("From twenty-eight days on it is exactly the record")
    func blendAtTwentyEight() {
        for days in [28, 29, 40] {
            let today = start.adding(days: days)
            // Kept on two days of three, so the record is not a round hundred.
            let records = history(from: start, days: days) { $0 % 3 != 0 }
            let dimension = physical(records, today: today, assessment())
            let shape = ForgeShape.read(records, today: today, activities: [activity("water")])
            #expect(dimension.source == .record)
            #expect(dimension.score == shape.dimensions.first { $0.category == .physical }!.score)
        }
    }

    @Test("The hand-over at twenty-eight days does not jump")
    func theHandOverIsContinuous() {
        // Kept on two days of three: the last blended morning and the first
        // record morning are one ordinary day apart, not a jump.
        let pattern: (Int) -> Bool = { $0 % 3 != 0 }
        let before = physical(history(from: start, days: 27, kept: pattern),
                              today: start.adding(days: 27), assessment())
        let after = physical(history(from: start, days: 28, kept: pattern),
                             today: start.adding(days: 28), assessment())
        #expect(before.source == .blend(days: 27))
        #expect(after.source == .record)
        #expect(abs(before.score - after.score) <= 2)
    }

    // MARK: - Sixty days

    @Test("An untouched dimension is carried by its answer for sixty days, then by the record")
    func untouchedExpires() {
        let onDay60 = BlendedShape.read([:], today: start.adding(days: 60), activities: [], assessment: assessment())
        #expect(onDay60.dimension(.intellect)?.source == .answers)
        #expect(onDay60.dimension(.intellect)?.score == 30)

        let onDay61 = BlendedShape.read([:], today: start.adding(days: 61), activities: [], assessment: assessment())
        #expect(onDay61.dimensions.allSatisfy { $0.source == .record })
        #expect(onDay61.dimensions.allSatisfy { !$0.hasScore }, "nothing measured is a dash")
        #expect(onDay61.overall == 0, "a dash counts nought")
    }

    @Test("A dimension first planned more than sixty days in reads the record from its first day")
    func lateStartsReadTheRecord() {
        let first = start.adding(days: 61)
        let today = first.adding(days: 4)
        let records = history(from: first, days: 4)
        let late = physical(records, today: today, assessment())
        let shape = ForgeShape.read(records, today: today, activities: [activity("water")])
        #expect(late.source == .record)
        #expect(late.score == shape.dimensions.first { $0.category == .physical }!.score)

        // Sixty days in is still inside.
        let onTime = physical(history(from: start.adding(days: 60), days: 2),
                              today: start.adding(days: 62), assessment())
        #expect(onTime.source == .blend(days: 2))
    }

    // MARK: - Today

    @Test("A day in progress is never a miss")
    func todayIsNeverAMiss() {
        let today = start.adding(days: 5)
        let past = history(from: start, days: 5)
        var planned = past
        planned[today] = record(today, planned: ["water"], done: [])
        var kept = past
        kept[today] = record(today, planned: ["water"], done: ["water"])

        // The record alone: five of five, and today planned is not a sixth
        // asked day until something is kept or the day is over.
        let water = [activity("water")]
        let without = ForgeShape.read(past, today: today, activities: water).dimensions.first { $0.category == .physical }!
        let inProgress = ForgeShape.read(planned, today: today, activities: water).dimensions.first { $0.category == .physical }!
        let settled = ForgeShape.read(kept, today: today, activities: water).dimensions.first { $0.category == .physical }!
        #expect(without.score == 63, "five days of eight")
        #expect(inProgress.score == without.score)
        #expect(inProgress.asked == 5)
        #expect(settled.asked == 6)
        #expect(settled.score == 75, "and keeping today raises it at once")

        // The blend reads the same way.
        #expect(physical(planned, today: today, assessment()).score
                == physical(past, today: today, assessment()).score)
        #expect(physical(kept, today: today, assessment()).score
                > physical(planned, today: today, assessment()).score)
    }

    @Test("Keeping only part of a dimension today never lowers it")
    func aPartialTodayNeverLowers() {
        // Mental is fed by Sit still in full and by a run as a secondary.
        let today = start.adding(days: 6)
        var records: [ForgeDay: DayRecord] = [:]
        for index in 0..<6 {
            let day = start.adding(days: index)
            records[day] = record(day, planned: ["meditate", "run"], done: ["meditate", "run"])
        }
        records[today] = record(today, planned: ["meditate", "run"], done: [])
        let activities = ["meditate", "run"].map(activity)
        let morning = BlendedShape.read(records, today: today, activities: activities, assessment: assessment())
        records[today] = record(today, planned: ["meditate", "run"], done: ["run"])
        let afterRun = BlendedShape.read(records, today: today, activities: activities, assessment: assessment())

        #expect(afterRun.dimension(.mental)!.score >= morning.dimension(.mental)!.score)
        let recordMorning = ForgeShape.read(records, today: today, activities: activities)
        #expect(recordMorning.dimensions.first { $0.category == .mental }!.score > 0)
    }

    // MARK: - What somebody who keeps a daily activity sees

    /// Morning (planned, nothing kept) and evening (kept) of day `n`, for
    /// somebody who has kept water every day since the assessment.
    private func dailyKeeper(day n: Int, _ answers: Assessment) -> (morning: Int, evening: Int) {
        let today = start.adding(days: n)
        var records = history(from: start, days: n)
        records[today] = record(today, planned: ["water"], done: [])
        let morning = physical(records, today: today, answers).score
        records[today] = record(today, planned: ["water"], done: ["water"])
        let evening = physical(records, today: today, answers).score
        return (morning, evening)
    }

    @Test("Keeping a daily activity raises a low start three to four points a day, from day one")
    func threeToFourADay() {
        // "None": Physical starts at 10.
        let answers = assessment(1, [.training: 0])
        var yesterday: Int?
        for n in 0..<BlendedShape.blendDays {
            let (morning, evening) = dailyKeeper(day: n, answers)
            if n == 0 { #expect(morning == 10, "the answer, before anything is kept") }
            #expect(
                (3...4).contains(evening - morning),
                Comment(rawValue: "day \(n + 1): \(morning) → \(evening)")
            )
            if let yesterday {
                #expect(morning == yesterday, Comment(rawValue: "day \(n + 1) opened lower than it closed"))
            }
            yesterday = evening
        }
    }

    @Test("For somebody who keeps it, the blend never makes a score drop", arguments: [0, 1, 2, 3])
    func theBlendNeverDrops(training: Int) {
        let answers = assessment(1, [.training: training])
        var readings: [Int] = []
        for n in 0..<70 {
            let (morning, evening) = dailyKeeper(day: n, answers)
            readings += [morning, evening]
        }
        for index in readings.indices.dropFirst() {
            #expect(
                readings[index] >= readings[index - 1],
                Comment(rawValue: "training answer \(training): step \(index) fell from \(readings[index - 1]) to \(readings[index])")
            )
        }
        #expect(readings.last == 100)
    }

    @Test("Planning one thing once cannot climb towards a hundred")
    func oneDayCannotClimb() {
        let records = [start: record(start, planned: ["water"], done: ["water"])]
        var readings: [Int] = []
        for n in 1...40 {
            readings.append(physical(records, today: start.adding(days: n), assessment()).score)
        }
        #expect(readings.max()! < 40, "one kept day is not a record to climb on")
        let recordReading = ForgeShape.read(records, today: start.adding(days: 28), activities: [activity("water")])
            .dimensions.first { $0.category == .physical }!.score
        #expect(readings[27] == recordReading, "day twenty-eight is the record's own reading")
        #expect(abs(readings[26] - readings[27]) <= 1)
    }

    // MARK: - OVR, the word, and what is named

    @Test("OVR is the mean of the six shown, a dash counting nought")
    func overallOnTheBlend() {
        let fresh = BlendedShape.read([:], today: start, activities: [], assessment: assessment())
        #expect(fresh.overall == 29, "(30 + 30 + 25 + 30 + 30 + 30) / 6")

        let today = start.adding(days: 14)
        let records = history(from: start, days: 14)
        let blended = BlendedShape.read(records, today: today, activities: [activity("water")], assessment: assessment())
        let expected = Int((Double(blended.dimensions.reduce(0) { $0 + ($1.hasScore ? $1.score : 0) }) / 6).rounded())
        #expect(blended.overall == expected)
        #expect(blended.dimension(.physical)?.score == 65)
        #expect(blended.overall == Int((Double(65 + 30 + 25 + 30 + 30 + 30) / 6).rounded()))

        // An unanswered dimension with nothing in the record is a dash.
        var partial = Dictionary(uniqueKeysWithValues: Assessment.Question.allCases.map { ($0, 1) })
        partial[.reading] = nil
        let gap = BlendedShape.read([:], today: start, activities: [],
                                    assessment: Assessment(day: start, answers: partial))
        #expect(gap.dimension(.intellect)?.source == .record)
        #expect(gap.dimension(.intellect)?.hasScore == false)
        #expect(gap.overall == Int((Double(30 + 30 + 25 + 0 + 30 + 30) / 6).rounded()))
    }

    @Test("The hexagon is readable from day one with answers, and only with them")
    func readableFromDayOne() {
        #expect(BlendedShape.read([:], today: start, activities: [], assessment: assessment()).isReadable)
        #expect(!BlendedShape.read([:], today: start, activities: [], assessment: nil).isReadable)
    }

    @Test("A blended dimension has no direction for its first week, then reads against its answer")
    func blendDirection() {
        let early = physical(history(from: start, days: 3), today: start.adding(days: 3), assessment())
        #expect(early.direction == .unknown)

        let later = physical(history(from: start, days: 14), today: start.adding(days: 14), assessment())
        #expect(later.direction == .rising, "30 to 65")

        let dropping = physical(history(from: start, days: 14) { _ in false },
                                today: start.adding(days: 14), assessment(3, [.training: 3]))
        #expect(dropping.direction == .slipping, "an answer of 75 and nothing kept")
    }

    @Test("Only a dimension the record alone speaks for is named as needing attention")
    func needsAttentionIsAboutTheRecord() {
        // Physical and intellect have both been planned for forty days, so both
        // read the record; intellect is kept a third as often.
        let today = start.adding(days: 40)
        var records: [ForgeDay: DayRecord] = [:]
        for index in 0..<40 {
            let day = start.adding(days: index)
            records[day] = record(day, planned: ["water", "lookup"],
                                  done: index % 3 == 0 ? ["water", "lookup"] : ["water"])
        }
        let activities = ["water", "lookup"].map(activity)
        let shape = BlendedShape.read(records, today: today, activities: activities, assessment: assessment())
        #expect(shape.needsAttention?.category == .intellect)

        // Ten days in, the same gap is still partly answers: nothing is named.
        let early = BlendedShape.read(
            records.filter { $0.key < start.adding(days: 10) },
            today: start.adding(days: 10), activities: activities, assessment: assessment()
        )
        #expect(early.needsAttention == nil)
    }

    @Test("An install that takes the assessment late keeps its record where it has one")
    func lateAssessment() {
        // Forty days of water before the questions were answered.
        let first = start.adding(days: -40)
        let records = history(from: first, days: 40)
        let shape = BlendedShape.read(records, today: start, activities: [activity("water")], assessment: assessment())
        #expect(shape.dimension(.physical)?.source == .record)
        #expect(shape.dimension(.physical)?.score == 100)
        #expect(shape.dimension(.intellect)?.source == .answers)
    }
}

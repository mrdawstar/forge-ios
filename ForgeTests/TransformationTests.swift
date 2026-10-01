import Foundation
import Testing
@testable import Forge

/// The four stops and the plan they project.
///
/// Every number the transformation screen shows is `BlendedShape.read` over
/// days held in memory, floored at the starting numbers, so what is tested
/// here is that the days are the ones the screen says they are — each
/// activity on its own days, five of every seven of them kept — and that the
/// arithmetic over them behaves the way the screen implies.
@Suite("Transformation")
struct TransformationTests {

    private let start = ForgeDay(year: 2026, month: 10, day: 1)

    /// Seven starts, one on each weekday: a projection must not depend on the
    /// day somebody installs on.
    private var starts: [ForgeDay] { (0..<7).map { start.adding(days: $0) } }

    private func assessment(_ picks: [Assessment.Question: Int]) -> Assessment {
        Assessment(day: start, answers: picks)
    }

    /// Everything answered at `index`, sleep six to seven hours.
    private func uniform(_ index: Int, sleep: Int = 1) -> Assessment {
        var picks = Dictionary(uniqueKeysWithValues: Assessment.Question.allCases.map { ($0, index) })
        picks[.sleep] = sleep
        return assessment(picks)
    }

    private func frames(_ answers: Assessment, focus: Set<RitualCategory>) -> [Transformation.Frame] {
        let plan = OnboardingPlan.propose(focus: focus, assessment: answers)
        return Transformation.frames(plan: plan.compactMap(\.ritual), assessment: answers)
    }

    /// Whether anything on the plan feeds a dimension at all.
    private func isPlanned(_ dimension: RitualCategory, in plan: [PlanEntry]) -> Bool {
        plan.compactMap(\.ritual).contains { $0.dimensionWeights[dimension] != nil }
    }

    // MARK: - The days behind the stops

    @Test("Five of seven, twenty-one of thirty, and the last before a stop is kept")
    func keptDays() {
        #expect(Transformation.keptDays(in: 0) == 0)
        #expect(Transformation.keptDays(in: 1) == 1)
        #expect(Transformation.keptDays(in: 7) == 5)
        #expect(Transformation.keptDays(in: 14) == 10)
        #expect(Transformation.keptDays(in: 30) == 21)
        #expect(Transformation.isKept(occurrence: 0))
        #expect((0..<7).count(where: Transformation.isKept(occurrence:)) == 5)
        #expect((0..<30).count(where: Transformation.isKept(occurrence:)) == 21)
    }

    @Test("Each stop has the blade its days have earned")
    func blades() {
        let all = frames(uniform(1), focus: [.physical])
        #expect(all.map(\.stop) == Transformation.Stop.allCases)
        #expect(all[0].blade.name == "Rough")
        #expect(all[0].daysKept == 0)
        #expect(all[1].daysKept == 5)
        #expect(all[1].blade.name == "Shaped")
        #expect(all[2].daysKept == 21)
        #expect(all[2].blade.name == "Quenched")
        #expect(all[3].blade == Sword.collection.last, "full potential is the last blade there is")
    }

    @Test("Every blade has its days under it, in words")
    func daysLines() {
        let all = frames(uniform(1), focus: [.physical])
        #expect(all.map(\.daysLine) == [
            "No days kept yet", "Five days kept", "Twenty-one days kept", "Sixty days kept",
        ])
    }

    @Test("The projection is deterministic")
    func deterministic() {
        let answers = uniform(2, sleep: 0)
        #expect(frames(answers, focus: [.mental, .ambition]) == frames(answers, focus: [.mental, .ambition]))
    }

    @Test("Now is the answers, and full potential is a hundred in all six")
    func theEnds() {
        let answers = uniform(1)
        let all = frames(answers, focus: [])
        for dimension in all[0].shape.dimensions {
            #expect(dimension.source == .answers)
            #expect(dimension.score == answers.baseline(for: dimension.category))
        }
        #expect(all[0].shape.state == .unknown, "nothing has happened yet")
        #expect(all[3].shape.dimensions.allSatisfy { $0.score == 100 })
        #expect(all[3].shape.overall == 100)
    }

    @Test("Thirty days at five a week reads what five of seven reads")
    func thirtyDaysIsTheRate() {
        let answers = uniform(1)
        let plan = OnboardingPlan.propose(focus: [.physical], assessment: answers)
        let month = Transformation.frame(.month, plan: plan.compactMap(\.ritual), assessment: answers)
        let physical = month.shape.dimension(.physical)!
        #expect(physical.source == .record)
        #expect(physical.score == 71, "twenty of the last twenty-eight days")

        let week = Transformation.frame(.week, plan: plan.compactMap(\.ritual), assessment: answers)
        #expect(week.shape.dimension(.physical)?.score == 40, "¼ × 71.4 + ¾ × 30")
    }

    // MARK: - What moves and what does not

    /// It used to skip every baseline above seventy-one, because the plan kept
    /// five days in seven settles there and the projection followed it down.
    /// With the floor there is nothing to skip: from any answer, on any start
    /// day, no dimension and no OVR goes down from one stop to the next.
    @Test("Nothing goes down across the stops, from any answer, on any start day")
    func monotonicForPlanned() {
        let focuses: [Set<RitualCategory>] = [
            [], [.physical], [.mental, .relationship, .ambition], [.relationship, .ambition, .discipline],
            Set(RitualCategory.dimensions),
        ]
        for start in starts {
            for index in 0..<4 {
                for sleep in 0..<4 {
                    var picks = Dictionary(uniqueKeysWithValues: Assessment.Question.allCases.map { ($0, index) })
                    picks[.sleep] = sleep
                    let answers = Assessment(day: start, answers: picks)
                    for focus in focuses {
                        let plan = OnboardingPlan.propose(focus: focus, assessment: answers)
                        let all = Transformation.frames(plan: plan.compactMap(\.ritual), assessment: answers)
                        for dimension in RitualCategory.dimensions {
                            let scores = all.map { $0.shape.dimension(dimension)!.score }
                            #expect(
                                scores == scores.sorted(),
                                Comment(rawValue: "\(dimension.label) from \(answers.baseline(for: dimension) ?? 0), starting \(start): \(scores)")
                            )
                        }
                        let overall = all.map(\.shape.overall)
                        #expect(overall == overall.sorted(), Comment(rawValue: "OVR \(overall), starting \(start)"))
                        #expect(!all.contains { $0.shape.state == .slipping }, "a projection never reads Slipping")
                    }
                }
            }
        }
    }

    @Test("An unplanned dimension is never raised")
    func unplannedStays() {
        for index in 0..<4 {
            let answers = uniform(index)
            let plan = OnboardingPlan.propose(focus: [.physical], assessment: answers)
            let all = Transformation.frames(plan: plan.compactMap(\.ritual), assessment: answers)
            for dimension in RitualCategory.dimensions where !isPlanned(dimension, in: plan) {
                for frame in all.prefix(3) {
                    let shown = frame.shape.dimension(dimension)!
                    #expect(shown.source == .answers)
                    #expect(shown.score == answers.baseline(for: dimension))
                }
            }
        }
    }

    // MARK: - The floor (the 75 → 71 regression)

    /// **The regression, as it was found on a phone.** Every question answered
    /// with its strongest option: Intellect 65, Relationship 70, the other four
    /// 75. The suggestion is the two lowest, and the plan takes the next lowest
    /// — Discipline, by the app's order — so it is Read, Call someone and Wake
    /// up. Five days in seven reads seventy-one, and "In 30 days" showed
    /// Discipline and Mental at 71 under a starting 75, and OVR 72 under a
    /// starting 73: the screen that shows what the plan does, going down for
    /// keeping the plan.
    @Test("The strongest answers are never projected below themselves")
    func seventyFiveIsTheFloor() {
        var picks = Dictionary(uniqueKeysWithValues: Assessment.Question.allCases.map { ($0, 3) })
        picks[.sleep] = 2
        for start in starts {
            let answers = Assessment(day: start, answers: picks)
            #expect(answers.baseline(for: .discipline) == 75)
            #expect(answers.baseline(for: .mental) == 75)
            let plan = OnboardingPlan.propose(focus: Set(answers.suggestedFocus), assessment: answers)
            #expect(Set(plan.map(\.ritualID)) == ["read", "call", "wake"])

            let all = Transformation.frames(plan: plan.compactMap(\.ritual), assessment: answers)
            for dimension in RitualCategory.dimensions {
                let baseline = answers.baseline(for: dimension) ?? 0
                for frame in all {
                    #expect(
                        frame.shape.dimension(dimension)!.score >= baseline,
                        Comment(rawValue: "\(dimension.label) \(frame.stop.title): \(frame.shape.dimension(dimension)!.score) under \(baseline)")
                    )
                }
            }
            let month = all[2].shape
            #expect(month.dimension(.discipline)?.score == 75, "held, not 71")
            #expect(month.dimension(.mental)?.score == 75, "held, not 71")
            #expect(month.overall >= all[0].shape.overall, "OVR does not go down either")
            #expect(all[3].shape.overall == 100)
        }
    }

    /// The floor is a rule about a projection, and nothing else: the model
    /// underneath still reads what the record would read, and the Becoming
    /// tab reads the model.
    @Test("The floor lives in the projection, not in the Shape")
    func theModelIsUntouched() {
        let answers = uniform(3, sleep: 1)
        let plan = OnboardingPlan.propose(focus: [.physical], assessment: answers)
        let rituals = plan.compactMap(\.ritual)
        let records = Transformation.simulate(rituals, from: start, days: 30, kept: Transformation.isKept(occurrence:))
        let model = BlendedShape.read(records, today: start.adding(days: 30), activities: rituals, assessment: answers)
        #expect(model.dimension(.physical)?.score == 71, "what five kept days in seven reads, as it always did")

        let projected = Transformation.frame(.month, plan: rituals, assessment: answers)
        #expect(projected.shape.dimension(.physical)?.score == 75)
        #expect(Transformation.floored(model, at: answers).dimension(.physical)?.score == 75)
    }

    /// Lifted to the start and no further, and an unplanned dimension — at its
    /// start already — not at all.
    @Test("The floor never raises anything past where it started")
    func theFloorOnlyHolds() {
        for index in 0..<4 {
            let answers = uniform(index)
            let plan = OnboardingPlan.propose(focus: [.physical], assessment: answers)
            let rituals = plan.compactMap(\.ritual)
            for days in [7, 30] {
                let records = Transformation.simulate(rituals, from: start, days: days, kept: Transformation.isKept(occurrence:))
                let model = BlendedShape.read(records, today: start.adding(days: days), activities: rituals, assessment: answers)
                let floored = Transformation.floored(model, at: answers)
                for (before, after) in zip(model.dimensions, floored.dimensions) {
                    let baseline = answers.baseline(for: before.category) ?? 0
                    #expect(after.score == max(before.score, baseline))
                }
            }
        }
    }

    // MARK: - The plan's own days

    @Test("Every activity is proposed on the days it would be kept on")
    func cadences() {
        for id in ["workout", "run", "lift"] {
            #expect(OnboardingPlan.cadence(for: id) == RitualRepeat(weekdays: [2, 4, 6]), "training, Mon Wed Fri")
        }
        for id in ["hardest", "focus", "study"] {
            #expect(OnboardingPlan.cadence(for: id) == .weekdays5, "the work block, weekdays")
        }
        for id in ["read", "walk", "wake", "breathe", "water", "journal"] {
            #expect(OnboardingPlan.cadence(for: id).isDaily, "a daily thing, daily")
        }
        #expect(OnboardingPlan.cadence(for: "call").weekdays.count == 2)
        #expect(OnboardingPlan.cadence(for: "meal") == .weekends)
        #expect(OnboardingPlan.cadence(for: "letter").weekdays.count == 1, "occasional things once a week")
        for ritual in Ritual.library {
            #expect(!OnboardingPlan.cadence(for: ritual.id).weekdays.isEmpty)
        }
        #expect(Set(OnboardingPlan.cadences.keys).isSubset(of: Set(Ritual.library.map(\.id))),
                "no cadence for an activity that does not exist")
    }

    /// The Shape counts a dimension fully present from about twice a week, and
    /// anything less made the first weeks of the blend read higher than the
    /// record later does. See `OnboardingPlan.cadences`.
    @Test("Nothing a proposal can hold is less than twice a week")
    func proposalsAreAtLeastTwiceAWeek() {
        for dimension in RitualCategory.dimensions {
            guard let first = OnboardingPlan.starter(for: dimension) else {
                Issue.record("no starter for \(dimension)")
                continue
            }
            #expect(OnboardingPlan.cadence(for: first.id).weekdays.count >= 2, Comment(rawValue: first.id))
        }
    }

    /// The first run's "do one now" is today's, and a day with nothing on it
    /// can be neither kept nor counted. Every proposal has something on every
    /// day of the week, whatever was answered and chosen.
    @Test("Every proposed week has something on every day, today included")
    func everyDayHasSomething() {
        let focuses: [Set<RitualCategory>] = [
            [], [.relationship], [.ambition], [.relationship, .ambition], [.relationship, .ambition, .physical],
            Set(RitualCategory.dimensions),
        ]
        for index in 0..<4 {
            for sleep in 0..<4 {
                for focus in focuses {
                    let plan = OnboardingPlan.propose(focus: focus, assessment: uniform(index, sleep: sleep))
                    for weekday in 1...7 {
                        #expect(plan.contains { $0.happens(on: weekday) },
                                Comment(rawValue: "nothing on weekday \(weekday) for \(plan.map(\.ritualID))"))
                    }
                }
            }
        }
    }

    @Test("A day an activity is not on plans nothing of it, and is not a miss")
    func restDaysAreNotMisses() {
        // Monday 5 October 2026.
        let monday = ForgeDay(year: 2026, month: 10, day: 5)
        var workout = Ritual.find("workout")!
        workout.repeats = RitualRepeat(weekdays: [2, 4, 6])
        let read = Ritual.find("read")!
        let records = Transformation.simulate([workout, read], from: monday, days: 30, kept: Transformation.isKept(occurrence:))

        for (day, record) in records {
            #expect(record.plannedIDs.contains("workout") == [2, 4, 6].contains(day.weekday))
            #expect(record.plannedIDs.contains("read"))
        }
        // Read over its own days, training asks for its twelve in the window
        // and not for twenty-eight — the other sixteen were never asked.
        let shape = ForgeShape.read(records, today: monday.adding(days: 30), activities: [workout, read])
        let physical = shape.dimensions.first { $0.category == .physical }!
        #expect(physical.asked == 12)
        #expect(physical.kept == Double(Transformation.keptDays(in: 12)))
    }

    /// Twenty-eight days hold four of every weekday, and the kept pattern is
    /// laid back from the end of the stop, so the record under the thirty-day
    /// stop reads each activity the same whichever day the plan starts on: the
    /// work block five of seven over its twenty weekdays, the call over its
    /// eight, reading over its twenty-eight.
    ///
    /// Read off the record rather than off the stop, because the stop is a
    /// blend: an activity first planned on day three still carries a
    /// twenty-eighth of its answer at day thirty, which is the blend being
    /// right, not the pattern depending on the calendar.
    @Test("The record under thirty days is the same from any start day")
    func sameFromAnyDay() {
        var picks = Dictionary(uniqueKeysWithValues: Assessment.Question.allCases.map { ($0, 0) })
        picks[.sleep] = 1
        let planned: [RitualCategory] = [.relationship, .ambition, .intellect]
        let readings = starts.map { start -> [Int] in
            let answers = Assessment(day: start, answers: picks)
            let plan = OnboardingPlan.propose(focus: Set(planned), assessment: answers)
            #expect(Set(plan.map(\.ritualID)) == ["call", "hardest", "read"])
            let rituals = plan.compactMap(\.ritual)
            let records = Transformation.simulate(rituals, from: start, days: 30, kept: Transformation.isKept(occurrence:))
            let shape = ForgeShape.read(records, today: start.adding(days: 30), activities: rituals)
            return planned.map { dimension in shape.dimensions.first { $0.category == dimension }!.score }
        }
        #expect(Set(readings.map(\.description)).count == 1, Comment(rawValue: "\(readings)"))
        #expect(readings.first == [75, 70, 71], "six of eight calls, fourteen of twenty weekdays, twenty of twenty-eight days")
    }

    /// The first week can round a dimension a point above where thirty days
    /// settle it — an activity missed on a day another one feeding it was kept
    /// — and the seven-day stop is held to the thirty-day one rather than
    /// showing a number that then goes down.
    @Test("Seven days never reads above thirty")
    func theFirstWeekIsCapped() {
        var picks = Dictionary(uniqueKeysWithValues: Assessment.Question.allCases.map { ($0, 3) })
        picks[.sleep] = 2
        for start in starts {
            let answers = Assessment(day: start, answers: picks)
            for focus in [Set<RitualCategory>(), [.ambition], [.relationship, .ambition, .discipline]] {
                let rituals = OnboardingPlan.propose(focus: focus, assessment: answers).compactMap(\.ritual)
                let week = Transformation.frame(.week, plan: rituals, assessment: answers).shape
                let month = Transformation.frame(.month, plan: rituals, assessment: answers).shape
                for (early, late) in zip(week.dimensions, month.dimensions) {
                    #expect(early.score <= late.score, Comment(rawValue: "\(early.category.label) starting \(start)"))
                }
            }
        }
    }

    /// The blade counts days the plan asks for anything on, and only those.
    @Test("Days kept are five of every seven days the plan asks for anything on")
    func daysKeptFollowThePlan() {
        let monday = ForgeDay(year: 2026, month: 10, day: 5)
        var workout = Ritual.find("workout")!
        workout.repeats = RitualRepeat(weekdays: [2, 4, 6])
        #expect(Transformation.daysKept([workout], from: monday, days: 7) == Transformation.keptDays(in: 3))
        #expect(Transformation.daysKept([workout, Ritual.find("read")!], from: monday, days: 7) == 5)
        #expect(Transformation.daysKept([workout, Ritual.find("read")!], from: monday, days: 30) == 21)
    }

    // MARK: - The plan

    @Test("Three at least, one per dimension, the chosen first and then the lowest")
    func planCoversTheRightDimensions() {
        // Physical 10, Mental 25 (screen 4–6 and sleep 6–7), the rest 30.
        var picks = Dictionary(uniqueKeysWithValues: Assessment.Question.allCases.map { ($0, 1) })
        picks[.training] = 0
        let answers = assessment(picks)

        #expect(OnboardingPlan.dimensions(focus: [], assessment: answers) == [.physical, .mental, .intellect])
        #expect(OnboardingPlan.dimensions(focus: [.ambition], assessment: answers) == [.ambition, .physical, .mental])

        let four: Set<RitualCategory> = [.intellect, .relationship, .discipline, .ambition]
        #expect(Set(OnboardingPlan.dimensions(focus: four, assessment: answers)) == four)
        #expect(OnboardingPlan.dimensions(focus: Set(RitualCategory.dimensions), assessment: answers).count == 6)

        for focus in [Set<RitualCategory>(), [.ambition], four, Set(RitualCategory.dimensions)] {
            let plan = OnboardingPlan.propose(focus: focus, assessment: answers)
            #expect((OnboardingPlan.minimum...OnboardingPlan.maximum).contains(plan.count))
            #expect(Set(plan.map(\.dimension)).count == plan.count, "one per dimension")
            #expect(Set(plan.map(\.ritualID)).count == plan.count, "no activity twice")
            for entry in plan {
                let ritual = entry.ritual
                #expect(ritual != nil)
                #expect(ritual?.category == entry.dimension)
                #expect(IdentityActivities.starters[entry.dimension]?.first == entry.ritualID,
                        "the most representative starter")
            }
        }
    }

    @Test("Every activity has a time, mornings and evenings apart, and none overlap")
    func planTimes() {
        let answers = uniform(1)
        let plan = OnboardingPlan.propose(focus: Set(RitualCategory.dimensions), assessment: answers)
        #expect(plan.map(\.minute) == plan.map(\.minute).sorted(), "the plan reads as a day")

        for entry in plan {
            guard let ritual = entry.ritual else { continue }
            if OnboardingPlan.isEvening(ritual) {
                #expect(entry.minute >= OnboardingPlan.eveningStart)
            } else {
                #expect(entry.minute >= OnboardingPlan.morningStart)
                #expect(entry.minute < 12 * 60)
            }
            #expect(entry.minute % 5 == 0)
        }
        for (earlier, later) in zip(plan, plan.dropFirst()) {
            let length = max(earlier.ritual?.minutes ?? 0, 10)
            #expect(earlier.minute + length <= later.minute,
                    Comment(rawValue: "\(earlier.ritualID) runs into \(later.ritualID)"))
        }

        // Getting up opens the morning, and relationships go in the evening.
        let discipline = OnboardingPlan.propose(focus: [.discipline, .relationship], assessment: answers)
        #expect(discipline.first { $0.ritualID == "wake" }?.minute == OnboardingPlan.morningStart)
        #expect((discipline.first { $0.dimension == .relationship }?.minute ?? 0) >= OnboardingPlan.eveningStart)
    }

    @Test("A row swaps only within its own dimension")
    func alternativesStayInTheDimension() {
        for dimension in RitualCategory.dimensions {
            let alternatives = OnboardingPlan.alternatives(for: dimension)
            #expect(!alternatives.isEmpty)
            #expect(alternatives.allSatisfy { $0.category == dimension })
            #expect(alternatives.map(\.id) == (IdentityActivities.starters[dimension] ?? []))
        }
    }
}

import Foundation
import Testing
@testable import Forge

/// The four stops and the plan they project.
///
/// Every number the transformation screen shows is `BlendedShape.read` over
/// days held in memory, so what is tested here is that the days are the ones
/// the screen says they are — five of seven, spread evenly, starting today —
/// and that the arithmetic over them behaves the way the screen implies.
@Suite("Transformation")
struct TransformationTests {

    private let start = ForgeDay(year: 2026, month: 10, day: 1)

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

    @Test("Five of seven, twenty-one of thirty, and today is kept")
    func keptDays() {
        #expect(Transformation.keptDays(in: 0) == 0)
        #expect(Transformation.keptDays(in: 1) == 1)
        #expect(Transformation.keptDays(in: 7) == 5)
        #expect(Transformation.keptDays(in: 14) == 10)
        #expect(Transformation.keptDays(in: 30) == 21)
        #expect(Transformation.isKept(day: 0), "the first run keeps today")
        #expect((0..<7).count(where: Transformation.isKept(day:)) == 5)
        #expect((0..<30).count(where: Transformation.isKept(day:)) == 21)
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

    @Test("A planned dimension never goes down across the stops, from any answer the plan can lift")
    func monotonicForPlanned() {
        let focuses: [Set<RitualCategory>] = [[], [.physical], [.mental, .relationship, .ambition], Set(RitualCategory.dimensions)]
        for index in 0..<4 {
            for sleep in 0..<4 {
                let answers = uniform(index, sleep: sleep)
                for focus in focuses {
                    let plan = OnboardingPlan.propose(focus: focus, assessment: answers)
                    let all = Transformation.frames(plan: plan.compactMap(\.ritual), assessment: answers)
                    for dimension in RitualCategory.dimensions where isPlanned(dimension, in: plan) {
                        let baseline = answers.baseline(for: dimension) ?? 0
                        // Five days of seven reads 71. An answer already above
                        // that is left to settle where the plan would put it —
                        // see `seventyFiveSettles`.
                        guard Double(baseline) <= 100.0 * 5 / 7 else { continue }
                        let scores = all.map { $0.shape.dimension(dimension)!.score }
                        #expect(
                            scores == scores.sorted(),
                            Comment(rawValue: "\(dimension.label) from \(baseline): \(scores)")
                        )
                    }
                    let overall = all.map(\.shape.overall)
                    if index < 3 {
                        #expect(overall == overall.sorted(), Comment(rawValue: "OVR \(overall)"))
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

    /// The one place the projection is allowed to show a number going down,
    /// and why: an answer of seventy-five is above what five days a week reads,
    /// so the plan kept five days a week settles it at seventy-one. The
    /// projection says what the record would say.
    @Test("A top answer settles at the rate the plan is kept at")
    func seventyFiveSettles() {
        let answers = uniform(3, sleep: 1)
        let plan = OnboardingPlan.propose(focus: [.physical], assessment: answers)
        let all = Transformation.frames(plan: plan.compactMap(\.ritual), assessment: answers)
        let physical = all.map { $0.shape.dimension(.physical)!.score }
        #expect(physical[0] == 75)
        #expect(physical[2] == 71)
        #expect(physical[3] == 100)
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

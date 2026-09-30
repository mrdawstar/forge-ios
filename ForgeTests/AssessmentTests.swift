import Foundation
import Testing
@testable import Forge

/// The seven questions: what each answer is worth, and what survives being
/// stored.
///
/// **Only the answers are stored.** Every baseline here is read off the table
/// in `Assessment.Question.options`, so these tests are the table, checked
/// answer by answer — and the decoder half is the tolerance §9 asks of every
/// stored value: one bad answer costs that answer and nothing else.
@Suite("Assessment")
struct AssessmentTests {

    private let day = ForgeDay(year: 2026, month: 10, day: 1)

    private func answered(_ picks: [Assessment.Question: Int]) -> Assessment {
        Assessment(day: day, answers: picks)
    }

    /// The baseline table, least first, as the direction set it.
    private static let table: [(Assessment.Question, RitualCategory, [Int])] = [
        (.training, .physical, [10, 30, 55, 75]),
        (.planning, .discipline, [10, 30, 55, 75]),
        (.screenTime, .mental, [10, 25, 45, 70]),
        (.reading, .intellect, [10, 30, 55, 65]),
        (.friends, .relationship, [10, 30, 55, 70]),
        (.building, .ambition, [10, 30, 55, 75]),
    ]

    // MARK: - Baselines

    @Test("Every answer maps to its baseline")
    func everyAnswerMaps() {
        for (question, dimension, values) in Self.table {
            #expect(question.dimension == dimension)
            #expect(question.options.count == 4)
            for (index, expected) in values.enumerated() {
                let baseline = answered([question: index]).baseline(for: dimension)
                #expect(
                    baseline == expected,
                    Comment(rawValue: "\(question.rawValue) answer \(index) gave \(String(describing: baseline))")
                )
            }
        }
    }

    @Test("Sleep moves Mental and nothing else", arguments: [(0, -10), (1, 0), (2, 10), (3, 5)])
    func sleepAdjustsMental(sleep: Int, adjustment: Int) {
        // Two to four hours of screen time: 45, with room either way.
        let assessment = answered([.screenTime: 2, .sleep: sleep, .training: 1])
        #expect(assessment.baseline(for: .mental) == 45 + adjustment)
        #expect(assessment.baseline(for: .physical) == 30, "sleep is not physical here")
    }

    @Test("Every baseline is clamped to five to seventy-five")
    func baselinesAreClamped() {
        // The two ends the table can reach past.
        #expect(answered([.screenTime: 0, .sleep: 0]).baseline(for: .mental) == 5, "10 − 10 is 0, clamped")
        #expect(answered([.screenTime: 3, .sleep: 2]).baseline(for: .mental) == 75, "70 + 10 is 80, clamped")
        #expect(answered([.screenTime: 3, .sleep: 3]).baseline(for: .mental) == 75)

        // And every combination the questions allow stays inside.
        for screen in 0..<4 {
            for sleep in 0..<4 {
                let mental = answered([.screenTime: screen, .sleep: sleep]).baseline(for: .mental)
                #expect(mental.map { Assessment.range.contains($0) } == true)
            }
        }
        for (question, dimension, _) in Self.table {
            for index in 0..<4 {
                let value = answered([question: index]).baseline(for: dimension)
                #expect(value.map { Assessment.range.contains($0) } == true)
            }
        }
    }

    @Test("An unanswered question gives its dimension no starting number")
    func unansweredIsAbsent() {
        let assessment = answered([.training: 2])
        #expect(assessment.baseline(for: .physical) == 55)
        #expect(assessment.baseline(for: .intellect) == nil)
        // Sleep adjusts; on its own there is nothing for it to adjust.
        #expect(answered([.sleep: 2]).baseline(for: .mental) == nil)
        #expect(!assessment.isComplete)
    }

    @Test("An answer nobody could have given is not kept")
    func outOfRangeIsDropped() {
        let assessment = answered([.training: 7, .planning: -1, .reading: 1])
        #expect(assessment.answers[.training] == nil)
        #expect(assessment.answers[.planning] == nil)
        #expect(assessment.answers[.reading] == 1)
    }

    @Test("The suggestion is the two lowest, ties in the app's own order")
    func suggestion() {
        // Physical 10, everything else 30 except Mental 25.
        var picks = Dictionary(uniqueKeysWithValues: Assessment.Question.allCases.map { ($0, 1) })
        picks[.training] = 0
        #expect(answered(picks).suggestedFocus == [.physical, .mental])

        // All level: the first two in `RitualCategory.dimensions`.
        let level = answered([.training: 1, .planning: 1, .reading: 1, .friends: 1, .building: 1,
                              .screenTime: 0, .sleep: 3])
        // Mental is 10 + 5 = 15, lowest; then the first of the thirties.
        #expect(level.suggestedFocus == [.mental, .intellect])
    }

    @Test("The time line is a gain, and silent under two hours")
    func gainLines() {
        #expect(answered([.screenTime: 0]).gainLine == "Two hours a day back is a month a year.")
        #expect(answered([.screenTime: 1]).gainLine == "One hour a day back is fifteen days a year.")
        #expect(answered([.screenTime: 2]).gainLine == "Thirty minutes a day back is a week a year.")
        #expect(answered([.screenTime: 3]).gainLine == nil)
        #expect(answered([:]).gainLine == nil)
    }

    // MARK: - Stored

    private func decode(_ json: String) -> Assessment? {
        try? JSONDecoder().decode(Assessment.self, from: Data(json.utf8))
    }

    @Test("It survives the trip, as ids rather than labels")
    func roundTrip() throws {
        let all = Dictionary(uniqueKeysWithValues: Assessment.Question.allCases.map { ($0, 2) })
        let assessment = answered(all)
        let data = try JSONEncoder().encode(assessment)
        let json = String(decoding: data, as: UTF8.self)

        #expect(json.contains("\"three_four\""), "the stored value is the id")
        #expect(!json.contains("3–4"), "never the label, which is copy")
        #expect(try JSONDecoder().decode(Assessment.self, from: data) == assessment)
    }

    @Test("A missing answer costs that answer and nothing else")
    func missingKeysAreTolerated() {
        let decoded = decode(#"{"day":{"year":2026,"month":10,"day":1},"answers":{"training":"none"}}"#)
        #expect(decoded?.answers == [.training: 0])
        #expect(decoded?.baseline(for: .physical) == 10)

        let noAnswers = decode(#"{"day":{"year":2026,"month":10,"day":1}}"#)
        #expect(noAnswers != nil)
        #expect(noAnswers?.answers.isEmpty == true)
    }

    @Test("An unknown value, question or type is dropped on its own")
    func unknownValuesAreTolerated() {
        let decoded = decode("""
        {"day":{"year":2026,"month":10,"day":1},
         "answers":{"training":"every_day","planning":"mostly","mood":"fine","reading":3,"friends":"most_days"},
         "extra":true}
        """)
        #expect(decoded != nil)
        #expect(decoded?.answers[.training] == nil, "a value this version does not know")
        #expect(decoded?.answers[.planning] == 2)
        #expect(decoded?.answers[.reading] == nil, "a value of the wrong type")
        #expect(decoded?.answers[.friends] == 3)
        #expect(decoded?.answers.count == 2)
    }

    @Test("Without a day there is no assessment, and garbage is nothing")
    func theDayIsRequired() {
        #expect(decode(#"{"answers":{"training":"none"}}"#) == nil)
        #expect(decode(#"{"day":"yesterday","answers":{}}"#) == nil)
        #expect(decode("not json") == nil)
    }

    @Test("It is kept under its own key, and removed with nil")
    func storedUnderItsKey() {
        let suite = UserDefaults(suiteName: "forge.tests.\(UUID().uuidString)") ?? .standard
        #expect(Assessment.read(from: suite) == nil)

        let assessment = answered([.training: 3, .sleep: 0])
        Assessment.write(assessment, to: suite)
        #expect(suite.data(forKey: "forge.assessment.v1") != nil)
        #expect(Assessment.read(from: suite) == assessment)

        Assessment.write(nil, to: suite)
        #expect(Assessment.read(from: suite) == nil)
    }
}

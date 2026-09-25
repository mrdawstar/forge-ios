import Foundation
import Testing

@testable import Forge

/// What stands between a model and somebody's belief about their own life.
///
/// Every other test file in this project checks that Forge computes the right
/// thing. This one checks that Forge **refuses to repeat the wrong thing** — a
/// different property, and the only one that matters once a model is in the
/// loop. The app can survive a bad plan; a user declines it and moves on. It
/// cannot survive telling somebody they kept four of five Mondays when they
/// kept one, because that is a claim they have no way to check and every
/// reason to believe.
@Suite("Model trust")
struct ModelTrustTests {

    /// A plain week: five days asked, three kept, two habits, two identities.
    private var facts: ReviewFacts {
        ReviewFacts(
            kept: 3,
            asked: 5,
            windowWeeks: 4,
            weekdays: [
                .init(weekday: 2, kept: 4, asked: 4),
                .init(weekday: 6, kept: 1, asked: 4),
            ],
            habits: [
                .init(id: "read", name: "Reading", planned: 5, completed: 5),
                .init(id: "run", name: "The run", planned: 5, completed: 1),
            ],
            identities: [
                .init(id: "a", statement: "Someone who reads", days: 5, asked: 5),
                .init(id: "b", statement: "Someone who trains", days: 0, asked: 4),
            ]
        )
    }

    // MARK: - Numbers

    @Test("A sentence whose numbers are all in the record survives")
    func supportedNumbersPass() {
        let text = "You kept four of four Mondays and one of four Fridays."
        #expect(ReviewObservation.validate(text, against: facts) == text)
    }

    /// The failure this whole file exists for. Every number is plausible, the
    /// grammar is perfect, the register is right — and the week did not happen.
    @Test("A sentence with a number the record does not contain is thrown away")
    func inventedNumbersFail() {
        #expect(
            ReviewObservation.validate(
                "You kept six of seven Mondays.", against: facts
            ) == nil
        )
        #expect(
            ReviewObservation.validate(
                "You kept 6 of 7 Mondays.", against: facts
            ) == nil
        )
    }

    /// Spelled and digit forms are the same claim and are checked the same way.
    @Test("Digits and words are held to the same record")
    func digitsAndWordsAgree() {
        #expect(ReviewObservation.validate("Three days were kept.", against: facts) != nil)
        #expect(ReviewObservation.validate("Nine days were kept.", against: facts) == nil)
    }

    /// `ForgeCount.spelled(21)` is "twenty-one", and splitting on the hyphen
    /// would turn one true claim into two false ones.
    @Test("A hyphenated count is one number, not two")
    func hyphenatedCounts() {
        var wide = facts
        wide.kept = 21
        #expect(
            ReviewObservation.validate(
                "Twenty-one days were kept.", against: wide
            ) != nil
        )
        // Twenty and one are each unsupported on their own, which is what the
        // naive split would have tested and wrongly rejected above.
        #expect(!ReviewObservation.supportedNumbers(in: wide).contains(20))
    }

    // MARK: - Names

    @Test("An activity the record does not hold cannot be named")
    func inventedActivitiesFail() {
        #expect(
            ReviewObservation.validate(
                "Reading held every day it was asked for.", against: facts
            ) != nil
        )
        // Swimming is not in this week, in this app, or in this person's life.
        #expect(
            ReviewObservation.validate(
                "Swimming held every day it was asked for.", against: facts
            ) == nil
        )
    }

    @Test("A weekday is always a name the record can support")
    func weekdaysAreVocabulary() {
        #expect(ReviewObservation.namesExist("You kept four Mondays.", in: facts))
    }

    // MARK: - Register

    /// The voice is the product. A true sentence in the wrong register is still
    /// rejected, because an app that congratulates once has changed what it is.
    @Test("Congratulation, diagnosis and exclamation are all refused")
    func registerIsHeld() {
        for line in [
            "Three days were kept. Great work!",
            "Three days were kept. Amazing progress.",
            "You struggle on Fridays.",
            "You should try harder on Fridays.",
            "Three days kept — keep it up.",
        ] {
            #expect(
                ReviewObservation.validate(line, against: facts) == nil,
                Comment(rawValue: "should have been refused: \(line)")
            )
        }
    }

    @Test("Three sentences is a report, and a report is refused")
    func lengthIsHeld() {
        let long = "Three days were kept. Reading held. The run did not."
        #expect(ReviewObservation.validate(long, against: facts) == nil)
    }

    /// The rules' own output is the floor: whatever `ReviewObservation.make`
    /// writes must itself pass the validator, or the fallback would be a
    /// sentence the app would refuse from a model.
    @Test("Everything the rules write passes the check they impose on a model")
    func rulesPassTheirOwnBar() {
        let cases: [ReviewFacts] = [
            facts,
            ReviewFacts(kept: 0, asked: 4, windowWeeks: 4),
            ReviewFacts(kept: 6, asked: 6, windowWeeks: 4),
            ReviewFacts(
                kept: 2, asked: 4, windowWeeks: 4,
                habits: [
                    .init(id: "a", name: "Reading", planned: 4, completed: 4),
                    .init(id: "b", name: "The run", planned: 4, completed: 0),
                ]
            ),
        ]
        for week in cases {
            guard let written = ReviewObservation.make(from: week) else { continue }
            let survived = ReviewObservation.validate(written, against: week) != nil
            #expect(survived, Comment(rawValue: "rules wrote a refusable line: \(written)"))
        }
    }

    // MARK: - Plans

    /// The plan's version of the same doctrine. A change naming an activity
    /// that does not exist would be applied against an id nothing owns.
    @Test("A change naming an activity that does not exist is dropped")
    func planChangesAreCheckedAgainstTheBrief() throws {
        let brief = AIBrief(
            activities: [
                ScheduledActivity(id: "real", name: "Reading", startMinute: 9 * 60, minutes: 20, weekdays: [])
            ]
        )
        let ghost = try decodeChange(#"{"kind":"time","id":"ghost","minute":420}"#)
        #expect(ghost.resolved(against: brief) == nil)

        let real = try decodeChange(#"{"kind":"time","id":"real","minute":420}"#)
        #expect(real.resolved(against: brief) != nil)
    }

    @Test("A clock time outside a day is dropped")
    func planTimesAreClamped() throws {
        let brief = AIBrief(
            activities: [
                ScheduledActivity(id: "real", name: "Reading", startMinute: nil, minutes: 20, weekdays: [])
            ]
        )
        #expect(try decodeChange(#"{"kind":"time","id":"real","minute":2000}"#).resolved(against: brief) == nil)
        #expect(try decodeChange(#"{"kind":"time","id":"real","minute":-1}"#).resolved(against: brief) == nil)
        #expect(try decodeChange(#"{"kind":"days","id":"real","weekdays":[0,9]}"#).resolved(against: brief) == nil)
    }

    /// A model may rearrange what somebody keeps and may not add to it.
    @Test("Nothing from the network can create an activity")
    func planCannotCreate() throws {
        let brief = AIBrief(
            activities: [
                ScheduledActivity(id: "real", name: "Reading", startMinute: nil, minutes: 20, weekdays: [])
            ]
        )
        #expect(try decodeChange(#"{"kind":"create","id":"real"}"#).resolved(against: brief) == nil)
    }

    private func decodeChange(_ json: String) throws -> AIWirePlan.Change {
        try JSONDecoder().decode(AIWirePlan.Change.self, from: Data(json.utf8))
    }

    // MARK: - Provenance

    /// The one rule stated in `ForgeAI`'s own doc comment: no screen may imply
    /// a model wrote something it did not.
    @Test("A reading defaults to not being model-written")
    func provenanceIsNeverAssumed() {
        #expect(PracticeReading(observation: "x").isModelWritten == false)
        #expect(SchedulePlan(summary: "x", changes: []).isModelWritten == false)
    }

    @Test("The arithmetic never claims to be a model")
    func localIsHonest() async throws {
        let local = LocalForgeAI()
        #expect(local.isConnected == false)

        var brief = AIBrief()
        brief.week = facts
        let reading = try await local.reading(brief: brief)
        #expect(reading.isModelWritten == false)
        #expect(!reading.observation.isEmpty)
    }

    @Test("A reading with no week to read throws rather than inventing one")
    func readingNeedsAWeek() async {
        await #expect(throws: ForgeAIError.nothingToRead) {
            _ = try await LocalForgeAI().reading(brief: AIBrief())
        }
    }
}

// MARK: - The generated archetype

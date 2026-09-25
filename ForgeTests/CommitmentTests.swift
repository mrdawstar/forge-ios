import Foundation
import Testing
@testable import Forge

/// The evening window and the sentence the day earns.
///
/// Both are pure functions of a clock and a count, which is the point: neither
/// can be checked by waiting for six in the evening, and the summary has to be
/// right on the day after a miss as well as on the day after a run.
@Suite("Commitment and summary")
struct CommitmentTests {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: hour, minute: minute))!
    }

    private func isOpen(at hour: Int, dayStartHour: Int = 4) -> Bool {
        EveningCommitment.isOpen(now: at(hour), dayStartHour: dayStartHour, calendar: calendar)
    }

    // MARK: - The window

    @Test("The evening is shut during the day")
    func shutInTheDay() {
        #expect(isOpen(at: 7) == false)
        #expect(isOpen(at: 12) == false)
        #expect(isOpen(at: 17) == false)
    }

    @Test("The evening opens at six and stays open")
    func opensAtSix() {
        #expect(isOpen(at: 18))
        #expect(isOpen(at: 21))
        #expect(isOpen(at: 23))
    }

    /// Forge's day ends at `dayStartHour`, not at midnight, so the small hours
    /// still belong to the evening of the day before.
    @Test("The window runs past midnight, up to the day's own start")
    func runsPastMidnight() {
        #expect(isOpen(at: 0))
        #expect(isOpen(at: 3))
        #expect(isOpen(at: 4) == false, "the new day has begun")
        #expect(isOpen(at: 5) == false)
    }

    /// Nothing ships with a day starting this late, but the debug stepper
    /// reaches it, and the window has to stay a window: two hours long, not the
    /// whole day, and certainly not open at nine in the morning.
    @Test("A day that starts after the evening opens narrows the window rather than breaking it")
    func lateDayStart() {
        #expect(isOpen(at: 18, dayStartHour: 20))
        #expect(isOpen(at: 19, dayStartHour: 20))
        #expect(isOpen(at: 20, dayStartHour: 20) == false, "the new day has begun")
        #expect(isOpen(at: 9, dayStartHour: 20) == false)
        #expect(isOpen(at: 2, dayStartHour: 20) == false)
    }

    @Test("A day starting exactly when the evening opens leaves no window at all")
    func zeroLengthWindow() {
        for hour in 0..<24 {
            #expect(isOpen(at: hour, dayStartHour: EveningCommitment.opensAtHour) == false)
        }
    }

    // MARK: - What was committed to

    @Test("A commitment is only for the day it names")
    func commitmentIsDated() {
        let today = ForgeDay(year: 2026, month: 8, day: 4)
        let commitment = DayCommitment(day: today.adding(days: 1), at: at(20))

        #expect(commitment.day == today.adding(days: 1))
        #expect(commitment.day != today, "tonight's yes is not today's")
    }

    @Test("A commitment survives a round trip through storage")
    func commitmentCodes() throws {
        let original = DayCommitment(day: ForgeDay(year: 2026, month: 8, day: 5), at: at(20))
        let decoded = try JSONDecoder().decode(
            DayCommitment.self,
            from: try JSONEncoder().encode(original)
        )
        #expect(decoded == original)
    }

    // MARK: - The summary

    @Test("The count is spelled out up to a hundred and set in figures beyond it")
    func spelling() {
        #expect(ForgeCount.spelled(1) == "One")
        #expect(ForgeCount.spelled(30) == "Thirty")
        #expect(ForgeCount.spelled(100) == "One hundred")
        #expect(ForgeCount.spelled(128) == "128")
        #expect(ForgeCount.spelled(365) == "365")
    }

    @Test("The first day gets its own sentence")
    func firstMorning() {
        let summary = DaySummary.make(daysKept: 1)
        #expect(summary.headline == "One day.")
        #expect(summary.line == "You have done it once.")
    }

    @Test("The sentence changes as the practice does, and never before")
    func linesMoveWithTheCount() {
        #expect(DaySummary.make(daysKept: 6).line == DaySummary.make(daysKept: 2).line)
        #expect(DaySummary.make(daysKept: 7).line != DaySummary.make(daysKept: 6).line)
        #expect(DaySummary.make(daysKept: 30).line != DaySummary.make(daysKept: 29).line)
        #expect(DaySummary.make(daysKept: 100).line != DaySummary.make(daysKept: 99).line)
    }

    @Test("Thirty days reads as the phase asked it to")
    func thirty() {
        let summary = DaySummary.make(daysKept: 30)
        #expect(summary.headline == "Thirty days.")
        #expect(summary.line == "This is just what you do now.")
    }

    /// Nothing in the summary can shame anybody, because nothing in it knows
    /// whether yesterday happened.
    @Test("The summary says nothing about what was missed")
    func neverMentionsAMiss() {
        for kept in [1, 5, 20, 60, 400] {
            let summary = DaySummary.make(daysKept: kept)
            let text = (summary.headline + " " + summary.line).lowercased()
            for word in ["miss", "broke", "broken", "lost", "fail", "streak", "again"] {
                #expect(text.contains(word) == false, "\(kept) days said: \(text)")
            }
        }
    }
}

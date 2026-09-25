import Foundation

/// Tomorrow, settled tonight.
///
/// Deliberately not a copy of tomorrow's list. The day somebody arranges in
/// the evening *is* `activeRitualIDs` — reordering it there reorders the real
/// thing — so all that is written down here is the fact that they looked at it
/// and said yes. A second stored list would be a second answer to "what is my
/// day", and the first time the two disagreed there would be no way to tell
/// which one the user had meant.
struct DayCommitment: Codable, Equatable, Sendable {
    /// The day this was set for.
    let day: ForgeDay
    let at: Date
}

/// When tomorrow is a thing you can settle.
///
/// Pure arithmetic on a clock, so the window can be checked without waiting for
/// six in the evening to come round.
enum EveningCommitment {

    /// The hour the evening opens. Late enough that today is behind you, early
    /// enough to be before the part of the night nobody makes decisions in.
    static let opensAtHour = 18

    /// Whether the evening of `currentDay` is running.
    ///
    /// Runs past midnight on purpose. Forge's day does not end at twelve — it
    /// ends at `dayStartHour` — so 1am with a four o'clock start is still the
    /// evening of the day before, and somebody up at that hour setting
    /// tomorrow means the day that is about to begin.
    /// Measured as a distance around the clock face rather than as a pair of
    /// comparisons. The window normally wraps midnight — 18:00 to 04:00 — and
    /// the version of this written as `hour >= opens || hour < starts` quietly
    /// became *always true* for any day starting at or after six in the evening,
    /// which the debug stepper can reach. Arithmetic on a twenty-four hour ring
    /// has no such seam: a window of zero length is shut, and every other one is
    /// exactly as long as it looks.
    static func isOpen(now: Date, dayStartHour: Int, calendar: Calendar = .current) -> Bool {
        let closes = ((dayStartHour % 24) + 24) % 24
        let span = (closes - opensAtHour + 24) % 24
        guard span > 0 else { return false }
        let hour = calendar.component(.hour, from: now)
        return (hour - opensAtHour + 24) % 24 < span
    }
}

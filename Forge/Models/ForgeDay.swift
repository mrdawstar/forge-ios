import Foundation

/// A calendar day in the user's own reckoning — the unit a streak is counted in.
///
/// Deliberately a civil date (2026-08-02) and not an instant. A day finished
/// in Los Angeles is still Sunday's day after you land in Tokyo, and a
/// stored `Date` is not: re-deriving its start of day in a new timezone moves
/// it, which is how a streak quietly gains or loses a day in transit. Labelling
/// an instant is timezone-dependent and happens exactly once, when something is
/// written down; everything afterwards is arithmetic on labels.
struct ForgeDay: Codable, Hashable, Comparable, Identifiable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    var id: Self { self }

    // MARK: - Labelling an instant

    /// Which day an instant belongs to.
    ///
    /// `dayStartHour` is what makes 2am still last night: anything earlier than
    /// it is filed under the day before, so finishing at 01:50 does not cost a
    /// streak the user was still awake for.
    static func containing(
        _ instant: Date,
        calendar: Calendar = .current,
        dayStartHour: Int
    ) -> ForgeDay {
        var midnight = calendar.startOfDay(for: instant)
        if calendar.component(.hour, from: instant) < dayStartHour,
           let previous = calendar.date(byAdding: .day, value: -1, to: midnight) {
            // Re-normalised rather than trusted: across a DST boundary,
            // "midnight minus one day" lands at 23:00 on the day before.
            midnight = calendar.startOfDay(for: previous)
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: midnight)
        return ForgeDay(
            year: parts.year ?? 1,
            month: parts.month ?? 1,
            day: parts.day ?? 1
        )
    }

    /// Midnight on this day where the user currently is. For formatting only —
    /// never feed this back into day arithmetic.
    func startOfDay(in calendar: Calendar = .current) -> Date {
        calendar.date(from: components) ?? .distantPast
    }

    // MARK: - Arithmetic
    //
    // Done in a fixed UTC Gregorian calendar, never the user's. These are
    // labels, not instants: the gap between the 1st and the 2nd is one day in
    // every timezone and on both sides of a clock change, and measuring it in a
    // calendar that moves would reintroduce exactly the drift this type exists
    // to prevent.

    private static let arithmetic: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    private var components: DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    private var anchor: Date? { ForgeDay.arithmetic.date(from: components) }

    func adding(days: Int) -> ForgeDay {
        guard let anchor,
              let moved = ForgeDay.arithmetic.date(byAdding: .day, value: days, to: anchor)
        else { return self }
        let parts = ForgeDay.arithmetic.dateComponents([.year, .month, .day], from: moved)
        return ForgeDay(
            year: parts.year ?? year,
            month: parts.month ?? month,
            day: parts.day ?? day
        )
    }

    /// A day that could be on somebody's record: inside a span any phone's
    /// clock could have put it in, and one the calendar can step on from.
    ///
    /// Everything Forge writes is one. A day read from somewhere else — a
    /// backup file somebody edited, a damaged store — need not be, and walking
    /// the days to or from one does not end: `adding` cannot move a date the
    /// calendar cannot make (the year 1,000,000 has none), so a loop waiting
    /// for the cursor to pass it spins for ever, and the year 1 is seven
    /// hundred thousand steps from today (FORGE_CONTEXT §17.7). What reads
    /// days from outside checks this first.
    var isPlausible: Bool {
        (1970...2200).contains(year) && (1...12).contains(month) && (1...31).contains(day)
            && adding(days: 1) > self
    }

    /// The day after, by the Gregorian calendar's own rules rather than by
    /// asking a `Calendar`: exactly `adding(days: 1)` for every real date (a
    /// test walks every day from 1970 to 2200 against it), and that, for
    /// anything else. A hundred times cheaper, which matters to a reading that
    /// steps through four weeks thirty-six times on every draw of Becoming
    /// (`ForgeShape.creditedDays`, §17.7).
    var next: ForgeDay {
        guard (1...9_999).contains(year), (1...12).contains(month),
              day >= 1, day <= ForgeDay.length(of: month, in: year)
        else { return adding(days: 1) }
        if day < ForgeDay.length(of: month, in: year) { return ForgeDay(year: year, month: month, day: day + 1) }
        if month < 12 { return ForgeDay(year: year, month: month + 1, day: 1) }
        return ForgeDay(year: year + 1, month: 1, day: 1)
    }

    /// Days in a month of the Gregorian calendar.
    static func length(of month: Int, in year: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// Days from `other` up to this one. Negative when this one is earlier.
    func days(since other: ForgeDay) -> Int {
        guard let from = other.anchor, let to = anchor else { return 0 }
        return ForgeDay.arithmetic.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// 1 = Sunday, matching `Calendar.component(.weekday:)`. A civil date falls
    /// on the same weekday everywhere, so this is settled in UTC too.
    var weekday: Int {
        guard let anchor else { return 1 }
        return ForgeDay.arithmetic.component(.weekday, from: anchor)
    }

    static func < (lhs: ForgeDay, rhs: ForgeDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

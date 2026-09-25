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

import Foundation
import Testing
@testable import Forge

/// The day boundary is the highest-risk logic in the app: everything a streak
/// claims rests on agreeing which day an instant belonged to, and every way
/// of getting that wrong is silent.
@Suite("Day boundaries")
struct ForgeDayTests {

    // MARK: - Helpers

    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier) ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    /// An instant, spelled out in a named timezone.
    private func instant(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int, _ minute: Int,
        zone: String
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(identifier: zone)
        return Calendar(identifier: .gregorian).date(from: components) ?? .distantPast
    }

    // MARK: - The day-start hour

    @Test("3:59am still belongs to the day before")
    func lateNightBelongsToYesterday() {
        let zone = "America/Los_Angeles"
        let late = instant(2026, 3, 10, 3, 59, zone: zone)
        let day = ForgeDay.containing(late, calendar: calendar(zone), dayStartHour: 4)
        #expect(day == ForgeDay(year: 2026, month: 3, day: 9))
    }

    @Test("4:01am starts the new day")
    func afterDayStartIsToday() {
        let zone = "America/Los_Angeles"
        let early = instant(2026, 3, 10, 4, 1, zone: zone)
        let day = ForgeDay.containing(early, calendar: calendar(zone), dayStartHour: 4)
        #expect(day == ForgeDay(year: 2026, month: 3, day: 10))
    }

    @Test("Exactly 4:00am is already the new day")
    func dayStartIsInclusive() {
        let zone = "America/Los_Angeles"
        let onTheHour = instant(2026, 3, 10, 4, 0, zone: zone)
        let day = ForgeDay.containing(onTheHour, calendar: calendar(zone), dayStartHour: 4)
        #expect(day == ForgeDay(year: 2026, month: 3, day: 10))
    }

    @Test("Midnight belongs to the day before when the day starts at 4")
    func midnightRollsBack() {
        let zone = "Europe/Warsaw"
        let midnight = instant(2026, 6, 15, 0, 0, zone: zone)
        let day = ForgeDay.containing(midnight, calendar: calendar(zone), dayStartHour: 4)
        #expect(day == ForgeDay(year: 2026, month: 6, day: 14))
    }

    @Test("A day-start of zero puts midnight in the new day")
    func zeroDayStart() {
        let zone = "Europe/Warsaw"
        let midnight = instant(2026, 6, 15, 0, 0, zone: zone)
        let day = ForgeDay.containing(midnight, calendar: calendar(zone), dayStartHour: 0)
        #expect(day == ForgeDay(year: 2026, month: 6, day: 15))
    }

    // MARK: - Daylight saving

    /// US spring forward 2026: 2am jumps to 3am on 8 March, so 8 March is a
    /// 23-hour day. `TimeInterval` arithmetic loses an hour here and silently
    /// files the following night under the wrong date.
    @Test("Spring forward: the short day still labels correctly")
    func springForward() {
        let zone = "America/Los_Angeles"
        let cal = calendar(zone)

        // 3:30am on the short day is before the 4am start, so it is still the 7th.
        let duringGap = instant(2026, 3, 8, 3, 30, zone: zone)
        #expect(ForgeDay.containing(duringGap, calendar: cal, dayStartHour: 4)
                == ForgeDay(year: 2026, month: 3, day: 7))

        // And 5am the same day is the 8th.
        let after = instant(2026, 3, 8, 5, 0, zone: zone)
        #expect(ForgeDay.containing(after, calendar: cal, dayStartHour: 4)
                == ForgeDay(year: 2026, month: 3, day: 8))
    }

    /// US fall back 2026: 1 November is a 25-hour day.
    @Test("Fall back: the long day still labels correctly")
    func fallBack() {
        let zone = "America/Los_Angeles"
        let cal = calendar(zone)

        let earlyHours = instant(2026, 11, 1, 1, 30, zone: zone)
        #expect(ForgeDay.containing(earlyHours, calendar: cal, dayStartHour: 4)
                == ForgeDay(year: 2026, month: 10, day: 31))

        let day = instant(2026, 11, 1, 9, 0, zone: zone)
        #expect(ForgeDay.containing(day, calendar: cal, dayStartHour: 4)
                == ForgeDay(year: 2026, month: 11, day: 1))
    }

    @Test("Consecutive days across a DST change are one day apart")
    func dstDoesNotDistortSpacing() {
        // Both directions: the label arithmetic must not care that one of these
        // days was 23 hours long and another 25.
        let spring = ForgeDay(year: 2026, month: 3, day: 8)
        #expect(spring.days(since: ForgeDay(year: 2026, month: 3, day: 7)) == 1)
        #expect(spring.adding(days: -1) == ForgeDay(year: 2026, month: 3, day: 7))

        let fall = ForgeDay(year: 2026, month: 11, day: 1)
        #expect(fall.days(since: ForgeDay(year: 2026, month: 10, day: 31)) == 1)
        #expect(fall.adding(days: 1) == ForgeDay(year: 2026, month: 11, day: 2))
    }

    // MARK: - Timezone travel

    @Test("Flying east does not renumber a day already recorded")
    func travelEast() {
        // Finished at 08:00 in Los Angeles on 12 June, then flew to Tokyo.
        let finished = instant(2026, 6, 12, 8, 0, zone: "America/Los_Angeles")

        let atHome = ForgeDay.containing(
            finished, calendar: calendar("America/Los_Angeles"), dayStartHour: 4
        )
        #expect(atHome == ForgeDay(year: 2026, month: 6, day: 12))

        // The label was written on the day, and nothing re-derives it later —
        // that is the whole point of storing a civil date. What must hold is
        // that the *next* day in Tokyo is still one day on.
        let nextMorningInTokyo = instant(2026, 6, 13, 7, 0, zone: "Asia/Tokyo")
        let abroad = ForgeDay.containing(
            nextMorningInTokyo, calendar: calendar("Asia/Tokyo"), dayStartHour: 4
        )
        #expect(abroad.days(since: atHome) == 1)
    }

    @Test("Flying west does not hand out a free day")
    func travelWest() {
        // Finished at 09:00 in Tokyo on 12 June, then flew to Los Angeles and
        // finished the next day there.
        let inTokyo = ForgeDay.containing(
            instant(2026, 6, 12, 9, 0, zone: "Asia/Tokyo"),
            calendar: calendar("Asia/Tokyo"),
            dayStartHour: 4
        )
        let inLA = ForgeDay.containing(
            instant(2026, 6, 13, 9, 0, zone: "America/Los_Angeles"),
            calendar: calendar("America/Los_Angeles"),
            dayStartHour: 4
        )
        #expect(inTokyo == ForgeDay(year: 2026, month: 6, day: 12))
        #expect(inLA == ForgeDay(year: 2026, month: 6, day: 13))
        // Exactly one day, not two — a westward flight must not gift a day.
        #expect(inLA.days(since: inTokyo) == 1)
    }

    @Test("The same instant read in two timezones can differ, but only once")
    func sameInstantDifferentZones() {
        // 23:00 in Warsaw is 14:00 in Los Angeles on the same date, so both
        // agree; the point is that whichever label is written is then stable.
        let moment = instant(2026, 6, 12, 23, 0, zone: "Europe/Warsaw")
        let warsaw = ForgeDay.containing(moment, calendar: calendar("Europe/Warsaw"), dayStartHour: 4)
        let la = ForgeDay.containing(moment, calendar: calendar("America/Los_Angeles"), dayStartHour: 4)
        #expect(warsaw == ForgeDay(year: 2026, month: 6, day: 12))
        #expect(la == ForgeDay(year: 2026, month: 6, day: 12))
    }

    // MARK: - Arithmetic

    @Test("Adding days crosses month and year ends")
    func arithmeticAcrossBoundaries() {
        #expect(ForgeDay(year: 2026, month: 1, day: 31).adding(days: 1)
                == ForgeDay(year: 2026, month: 2, day: 1))
        #expect(ForgeDay(year: 2026, month: 12, day: 31).adding(days: 1)
                == ForgeDay(year: 2027, month: 1, day: 1))
        #expect(ForgeDay(year: 2028, month: 2, day: 28).adding(days: 1)
                == ForgeDay(year: 2028, month: 2, day: 29), "2028 is a leap year")
    }

    @Test("Distance is signed and symmetric")
    func distance() {
        let earlier = ForgeDay(year: 2026, month: 6, day: 1)
        let later = ForgeDay(year: 2026, month: 7, day: 1)
        #expect(later.days(since: earlier) == 30)
        #expect(earlier.days(since: later) == -30)
        #expect(earlier.days(since: earlier) == 0)
    }

    @Test("Ordering follows the calendar")
    func ordering() {
        #expect(ForgeDay(year: 2026, month: 6, day: 1) < ForgeDay(year: 2026, month: 6, day: 2))
        #expect(ForgeDay(year: 2026, month: 6, day: 30) < ForgeDay(year: 2026, month: 7, day: 1))
        #expect(ForgeDay(year: 2026, month: 12, day: 31) < ForgeDay(year: 2027, month: 1, day: 1))
    }

    @Test("Weekday is the same everywhere")
    func weekday() {
        // 2026-06-14 is a Sunday.
        #expect(ForgeDay(year: 2026, month: 6, day: 14).weekday == 1)
        #expect(ForgeDay(year: 2026, month: 6, day: 15).weekday == 2)
        #expect(ForgeDay(year: 2026, month: 6, day: 20).weekday == 7)
    }

    @Test("A day survives a round trip through JSON")
    func codable() throws {
        let day = ForgeDay(year: 2026, month: 8, day: 2)
        let data = try JSONEncoder().encode(day)
        #expect(try JSONDecoder().decode(ForgeDay.self, from: data) == day)
    }
}

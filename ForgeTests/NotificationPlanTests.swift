import Foundation
import Testing
@testable import Forge

/// The notification rules are the only part of Forge that acts while nobody is
/// looking, and every way of getting them wrong is a notification somebody did
/// not want — or, worse, one that never came. They are a pure function of a week
/// precisely so that all of it can be checked here rather than by waiting until
/// six o'clock.
@Suite("Notification rules")
struct NotificationPlanTests {

    // MARK: - Helpers

    /// March 2026, on the American west coast — the clocks go forward on the
    /// 8th, which one test below stands directly on top of.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func instant(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 3
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        return calendar.date(from: parts) ?? .distantPast
    }

    private func day(_ day: Int) -> ForgeDay {
        ForgeDay(year: 2026, month: 3, day: day)
    }

    /// The weekday the tests treat as "today", read off the date rather than
    /// written down, so nothing here depends on which day of the week the 10th
    /// of March happens to be.
    private var today: Int { day(10).weekday }
    private var tomorrow: Int { day(11).weekday }

    private func activity(
        _ id: String,
        _ name: String,
        at startMinute: Int? = nil,
        minutes: Int = 0,
        on weekdays: Set<Int>
    ) -> ScheduledActivity {
        ScheduledActivity(
            id: id,
            name: name,
            startMinute: startMinute,
            minutes: minutes,
            weekdays: weekdays
        )
    }

    /// Seven in the morning on the 10th, a six-thirty start-of-day setting, and
    /// whatever week the test hands in. Each test varies one thing from here.
    private func state(
        now: Date? = nil,
        currentDay: ForgeDay? = nil,
        wakeMinutes: Int = 6 * 60 + 30,
        completedToday: Int = 0,
        plannedToday: Int = 3,
        isTodayEarned: Bool = false,
        streak: Int = 5,
        dayStartHour: Int = 4,
        schedule: [ScheduledActivity] = [],
        completedIDs: Set<String> = []
    ) -> ForgeNotificationState {
        ForgeNotificationState(
            now: now ?? instant(10, 7, 0),
            currentDay: currentDay ?? day(10),
            dayStartHour: dayStartHour,
            wakeMinutes: wakeMinutes,
            completedToday: completedToday,
            plannedToday: plannedToday,
            isTodayEarned: isTodayEarned,
            streak: streak,
            schedule: schedule,
            completedIDs: completedIDs,
            calendar: calendar
        )
    }

    private func plan(_ state: ForgeNotificationState) -> [PlannedNotification] {
        ForgeNotificationPlan.make(for: state)
    }

    /// A day with a shape: work at nine, the gym at six, reading at nine —
    /// the example from the brief, on today only.
    private var aFullDay: [ScheduledActivity] {
        [
            activity("focus", "Deep work", at: 9 * 60, minutes: 45, on: [today]),
            activity("workout", "Work out", at: 18 * 60, minutes: 20, on: [today]),
            activity("read", "Read", at: 21 * 60, minutes: 15, on: [today]),
        ]
    }

    // MARK: - The morning

    @Test("A day opens once, named after the first thing on it")
    func morningNamesTheFirstActivity() throws {
        let plan = plan(state(schedule: aFullDay))
        let mornings = plan.filter { $0.kind == .morning }

        #expect(mornings.count == 1, "one opening, on the one day that has anything")
        let morning = try #require(mornings.first)
        #expect(morning.when == .weekly(weekday: today, hour: 6, minute: 30))
        // The count, spelled — what somebody who has named no identity sees.
        // See `ForgeNotificationPlan.standing`.
        #expect(morning.title == "The first one.")
        #expect(morning.body.contains("Deep work"))
    }

    /// The morning names the one thing the app is certain of about a person who
    /// has named nobody: what they have already kept. It is the count and never
    /// the chain — see `ForgeNotificationPlan.standing`.
    @Test("A day opens on the count, not on a slogan")
    func morningNamesTheCount() throws {
        var kept = state(schedule: aFullDay)
        kept.daysKept = 91
        let morning = try #require(plan(kept).first { $0.kind == .morning })
        #expect(morning.title == "Ninety-one days kept.")
    }

    /// Both readings of "when does my day start" are true for somebody, so the
    /// opening takes whichever comes first — and is therefore never an
    /// announcement of something that has already begun.
    @Test("A day that begins before the set hour opens with its first activity")
    func morningFollowsAnEarlyFirstActivity() throws {
        let early = [activity("run", "Go for a run", at: 5 * 60 + 45, on: [today])]
        let morning = try #require(plan(state(schedule: early)).first { $0.kind == .morning })
        #expect(morning.when == .weekly(weekday: today, hour: 5, minute: 45))
    }

    /// The reason the Settings time still exists: a day straight out of
    /// onboarding carries no hours at all.
    @Test("A day with no hours on it opens at the time in Settings")
    func morningFallsBackToTheSetHour() throws {
        let untimed = [
            activity("water", "Drink water", on: [today]),
            activity("bed", "Make your bed", on: [today]),
        ]
        let morning = try #require(plan(state(schedule: untimed)).first { $0.kind == .morning })
        #expect(morning.when == .weekly(weekday: today, hour: 6, minute: 30))
        #expect(morning.body == "First: Drink water.")
    }

    /// Two notifications arriving in the same second is the one thing that would
    /// make either of them feel automated.
    @Test("The opening and the first activity never speak at the same minute")
    func openingAbsorbsAnActivityAtTheSameTime() {
        let early = [
            activity("run", "Go for a run", at: 5 * 60, on: [today]),
            activity("read", "Read", at: 21 * 60, on: [today]),
        ]
        let plan = plan(state(schedule: early))
        let atFive = plan.filter { $0.when.minuteOfDay == 5 * 60 }
        #expect(atFive.count == 1)
        #expect(atFive.first?.kind == .morning)
        // The later one still gets its own.
        #expect(plan.contains { $0.kind == .activity && $0.title == "Read" })
    }

    // MARK: - The primer says what the app sends

    /// **The bug this locks in.** The permission primer used to carry its own
    /// three sentences, written out as string literals: "Your day starts now.",
    /// "Time to begin." and "Keep the promise you made to yourself." When the
    /// notification copy was rewritten they were left behind, so the one screen
    /// in Forge whose whole job is *showing somebody what they are agreeing to*
    /// was showing three notifications the app no longer sends.
    ///
    /// It reads the plan's own functions now. This holds them together.
    @MainActor
    @Test("The permission primer shows the notifications Forge actually sends")
    func primerQuotesTheRealNotifications() throws {
        var day = state(completedToday: 2, plannedToday: 5, schedule: aFullDay)
        day.daysKept = 41

        let rows = NotificationPrimerView.examples(
            firstActivity: aFullDay.first,
            openingMinute: 6 * 60 + 30,
            state: day
        )
        #expect(rows.count == 3)

        // Each row is the plan's own sentence, not a copy of one.
        #expect(rows[0].title == ForgeNotificationPlan.standing(daysKept: 41))
        #expect(rows[1].body == ForgeNotificationPlan.begin(nil, minutes: 45))
        #expect(rows[2].body == ForgeNotificationPlan.waiting(nil, done: 2, planned: 5))

        // And none of the three retired sentences can come back.
        let retired = [
            "Your day starts now.",
            "Time to begin.",
            "Keep the promise you made to yourself.",
        ]
        for row in rows {
            for line in retired {
                #expect(row.title != line && row.body != line,
                        Comment(rawValue: "the primer is still promising “\(line)”"))
            }
        }
    }

    // MARK: - Activities

    @Test("Every activity with an hour is spoken for at that hour")
    func activitiesSpeakAtTheirOwnTime() throws {
        let plan = plan(state(schedule: aFullDay))
        let gym = try #require(plan.first { $0.kind == .activity && $0.title == "Work out" })

        #expect(gym.when == .weekly(weekday: today, hour: 18, minute: 0))
        // The duration the user set, quoted back — see
        // `ForgeNotificationPlan.begin`. "Time to begin" was an alarm clock.
        #expect(gym.body == "20 min. Then it is behind you.")
        #expect(plan.contains { $0.kind == .activity && $0.title == "Read" })
    }

    /// An activity with no hour is not an appointment, and Forge has never
    /// pretended otherwise. It is named by the opening and left alone.
    @Test("An activity with no hour gets no notification of its own")
    func untimedActivitiesAreNotAppointments() {
        let mixed = [
            activity("water", "Drink water", on: [today]),
            activity("workout", "Work out", at: 18 * 60, on: [today]),
        ]
        let plan = plan(state(schedule: mixed))
        #expect(!plan.contains { $0.kind == .activity && $0.title == "Drink water" })
        #expect(plan.contains { $0.kind == .activity && $0.title == "Work out" })
    }

    // MARK: - One-time and recurring

    /// "One-time" in Forge means one day of the week — see `RitualRepeat` — and
    /// the notification has to mean exactly the same thing.
    @Test("An activity on one day is only spoken for on that day")
    func oneDayActivityStaysOnItsDay() {
        let plan = plan(state(schedule: [
            activity("workout", "Work out", at: 18 * 60, on: [today])
        ]))
        let weekdays = plan.compactMap { planned -> Int? in
            if case .weekly(let weekday, _, _) = planned.when { return weekday }
            return nil
        }
        #expect(Set(weekdays) == [today])
    }

    @Test("An activity on two days is spoken for on both, and only both")
    func twoDayActivityGetsTwo() {
        let plan = plan(state(schedule: [
            activity("workout", "Work out", at: 18 * 60, on: [today, tomorrow])
        ]))
        let gym = plan.filter { $0.kind == .activity && $0.title == "Work out" }
        let weekdays = gym.compactMap { planned -> Int? in
            if case .weekly(let weekday, _, _) = planned.when { return weekday }
            return nil
        }
        #expect(Set(weekdays) == [today, tomorrow])
        #expect(gym.count == 2)
    }

    /// The difference between a full week costing seven of the sixty-odd
    /// requests iOS will hold and costing one.
    @Test("An activity that happens every day is one repeating request, not seven")
    func dailyActivityCollapses() throws {
        let plan = plan(state(schedule: [
            activity("workout", "Work out", at: 18 * 60, on: Set(1...7))
        ]))
        let gym = plan.filter { $0.kind == .activity && $0.title == "Work out" }
        #expect(gym.count == 1)
        #expect(try #require(gym.first).when == .daily(hour: 18, minute: 0))
        // And the opening it shares the week with collapses the same way.
        #expect(plan.filter { $0.kind == .morning }.count == 1)
    }

    /// The empty weekday set means "every day" everywhere else in the app, and
    /// it has to mean it here too.
    @Test("An activity with no days chosen happens every day")
    func emptyWeekdaySetIsDaily() throws {
        let plan = plan(state(schedule: [
            activity("workout", "Work out", at: 18 * 60, on: [])
        ]))
        let gym = try #require(plan.first { $0.kind == .activity })
        #expect(gym.when == .daily(hour: 18, minute: 0))
    }

    // MARK: - Empty days

    /// An unplanned Thursday is not a day to be reminded about. It is a day that
    /// has not been planned, and the app has a screen that says so.
    @Test("A day with nothing on it is never spoken about")
    func emptyDaysAreSilent() {
        let plan = plan(state(schedule: [
            activity("workout", "Work out", at: 18 * 60, on: [today])
        ]))
        for planned in plan {
            if case .weekly(let weekday, _, _) = planned.when {
                #expect(weekday == today, "weekday \(weekday) has nothing on it")
            }
        }
    }

    @Test("A week with nothing in it is nothing at all")
    func emptyWeekIsSilent() {
        #expect(plan(state(schedule: [])).isEmpty)
    }

    // MARK: - Changing the schedule

    /// Item 4 of the brief, and the whole reason the plan is rebuilt rather than
    /// patched: what is pending is a function of the week, so it cannot lag it.
    @Test("Moving an activity's hour moves its notification")
    func editingTheTimeMovesTheNotification() throws {
        var week = [activity("workout", "Work out", at: 18 * 60, on: [today])]
        let before = try #require(plan(state(schedule: week)).first { $0.kind == .activity })
        #expect(before.when == .weekly(weekday: today, hour: 18, minute: 0))

        week[0].startMinute = 7 * 60 + 15
        let after = try #require(plan(state(schedule: week)).first { $0.kind == .activity })
        #expect(after.when == .weekly(weekday: today, hour: 7, minute: 15))
        #expect(after.identifier == before.identifier, "the same occurrence, rewritten")
    }

    @Test("Moving an activity to another day moves its notification")
    func editingTheDayMovesTheNotification() throws {
        var week = [activity("workout", "Work out", at: 18 * 60, on: [today])]
        week[0].weekdays = [tomorrow]

        let moved = try #require(plan(state(schedule: week)).first { $0.kind == .activity })
        #expect(moved.when == .weekly(weekday: tomorrow, hour: 18, minute: 0))
        #expect(!plan(state(schedule: week)).contains { $0.when.minuteOfDay == 18 * 60 && {
            if case .weekly(let weekday, _, _) = $0.when { return weekday == today }
            return false
        }($0) })
    }

    @Test("A deleted activity takes its notifications with it")
    func deletingAnActivitySilencesIt() {
        let week = aFullDay
        #expect(plan(state(schedule: week)).contains { $0.title == "Work out" })

        let without = week.filter { $0.id != "workout" }
        let after = plan(state(schedule: without))
        #expect(!after.contains { $0.title == "Work out" })
        #expect(after.contains { $0.title == "Read" }, "the rest of the day is untouched")
    }

    /// Copying a day is expressed as an activity gaining a weekday, so the
    /// notifications for it are the same fact read twice.
    @Test("A day copied onto another is spoken for on both")
    func copyingADayCopiesItsNotifications() {
        let copied = aFullDay.map {
            activity($0.id, $0.name, at: $0.startMinute, minutes: $0.minutes,
                     on: [today, tomorrow])
        }
        let plan = plan(state(schedule: copied))
        let onTomorrow = plan.filter {
            if case .weekly(let weekday, _, _) = $0.when { return weekday == tomorrow }
            return false
        }
        // The opening at half past six, and the three hours the day carries.
        #expect(onTomorrow.count == 4)
        #expect(onTomorrow.contains { $0.kind == .morning })
        #expect(onTomorrow.filter { $0.kind == .activity }.count == 3)
    }

    // MARK: - The follow-up

    @Test("One activity is followed up, and only one")
    func oneFollowUpOnly() throws {
        let plan = plan(state(schedule: aFullDay))
        let missed = plan.filter { $0.kind == .missed }
        #expect(missed.count == 1)

        let follow = try #require(missed.first)
        #expect(follow.title == "Deep work")
        // Rewritten with the rest of the copy. "Still on today's list" is a
        // fact about a list; the line it replaces was a sentence about
        // somebody's character, delivered by a phone about a workout they may
        // have skipped for an excellent reason. See `ForgeNotificationPlan.waiting`.
        #expect(follow.body == "Still on today's list.")
        // Forty-five minutes of deep work, asked about once it is over.
        #expect(follow.when == .once(instant(10, 9, 45)))
    }

    /// The floor. A twenty-minute workout is asked about at half past rather
    /// than twenty past.
    @Test("A short activity is still given half an hour")
    func followUpHasAFloor() throws {
        let quick = [activity("workout", "Work out", at: 18 * 60, minutes: 20, on: [today])]
        let follow = try #require(plan(state(schedule: quick)).first { $0.kind == .missed })
        #expect(follow.when == .once(instant(10, 18, 30)))
    }

    @Test("Finishing something moves the follow-up on to the next thing")
    func followUpSkipsWhatIsDone() throws {
        let done = state(schedule: aFullDay, completedIDs: ["focus"])
        let follow = try #require(plan(done).first { $0.kind == .missed })
        #expect(follow.title == "Work out")
    }

    @Test("A day with everything done has nothing to follow up")
    func followUpStopsWhenTheDayIsDone() {
        let finished = state(schedule: aFullDay, completedIDs: ["focus", "workout", "read"])
        #expect(!plan(finished).contains { $0.kind == .missed })
    }

    @Test("A blade already out is not chased")
    func followUpStopsOnAnEarnedDay() {
        let earned = state(isTodayEarned: true, schedule: aFullDay)
        #expect(!plan(earned).contains { $0.kind == .missed })
    }

    /// Nothing is said about a moment that has already gone by — the follow-up
    /// for the nine o'clock block cannot be scheduled at half past ten.
    @Test("A follow-up whose moment has passed is skipped, not backdated")
    func followUpDoesNotLookBackwards() throws {
        let late = state(now: instant(10, 10, 30), schedule: aFullDay)
        let follow = try #require(plan(late).first { $0.kind == .missed })
        #expect(follow.title == "Work out")
    }

    @Test("A day whose every hour has passed has no follow-up")
    func followUpEndsWithTheDay() {
        let night = state(now: instant(10, 23, 30), schedule: aFullDay)
        #expect(!plan(night).contains { $0.kind == .missed })
    }

    /// Completion is only knowable for today, so a follow-up is only ever about
    /// today. Tomorrow's activities are not chased on tomorrow's behalf.
    @Test("The follow-up only ever concerns today")
    func followUpIsTodayOnly() {
        let tomorrowOnly = [activity("workout", "Work out", at: 18 * 60, on: [tomorrow])]
        #expect(!plan(state(schedule: tomorrowOnly)).contains { $0.kind == .missed })
    }

    // MARK: - Evening

    @Test("Nothing started is nothing to come back to")
    func eveningNeedsAStart() {
        #expect(!plan(state(schedule: aFullDay)).contains { $0.kind == .evening })
    }

    @Test("An unfinished day is worth one evening")
    func eveningOnAnUnfinishedDay() throws {
        let partial = state(completedToday: 2, plannedToday: 5, schedule: aFullDay)
        let evening = try #require(plan(partial).first { $0.kind == .evening })
        #expect(evening.when == .once(instant(10, 20, 0)))
        // The count is the headline now; the body names what is left, because
        // "three left" is a number without an object.
        #expect(evening.title == "2 of 5 done.")
        #expect(evening.body == "Deep work is still open.")
    }

    @Test("A day already earned says nothing in the evening")
    func eveningStopsOnceEarned() {
        let earned = state(completedToday: 3, isTodayEarned: true, schedule: aFullDay)
        #expect(!plan(earned).contains { $0.kind == .evening })
    }

    @Test("A day finished but not pulled is told so")
    func eveningWhenEverythingIsDone() throws {
        let ready = state(completedToday: 5, plannedToday: 5, schedule: aFullDay)
        let evening = try #require(plan(ready).first { $0.kind == .evening })
        #expect(evening.title == "Everything is done.")
        #expect(evening.body == "The blade is loose. It still has to be pulled.")
    }

    @Test("An evening that has already been is not scheduled")
    func eveningDoesNotLookBackwards() {
        let night = state(now: instant(10, 22, 0), completedToday: 1, schedule: aFullDay)
        #expect(!plan(night).contains { $0.kind == .evening })
    }

    // MARK: - Identity

    /// Every request has to be addressable, or re-planning would leave
    /// duplicates behind rather than replacing them.
    @Test("Every notification in a plan has its own identifier")
    func identifiersAreUnique() {
        let busy = aFullDay + [
            activity("stretch", "Stretch", at: 7 * 60, on: [today, tomorrow]),
            activity("walk", "Walk outside", at: 12 * 60, on: Set(1...7)),
        ]
        let plan = plan(state(completedToday: 1, schedule: busy))
        let identifiers = plan.map(\.identifier)
        #expect(Set(identifiers).count == identifiers.count)
    }

    /// The tap handler reads the kind back off the identifier, so the two have
    /// to agree — including about the fixed identifiers older builds wrote,
    /// which mean nothing now and must not be mistaken for something.
    @Test("A kind survives the round trip through its identifier")
    func identifiersRoundTrip() {
        for kind in ForgeNotification.allCases {
            #expect(ForgeNotification(identifier: kind.identifier("2.read")) == kind)
        }
        #expect(ForgeNotification(identifier: "forge.notification.morning.v1") == nil)
        #expect(ForgeNotification(identifier: "something.else") == nil)
    }

    /// iOS holds 64 pending requests and silently drops the rest, so a plan that
    /// could exceed it decides which ones survive rather than leaving it to the
    /// system.
    @Test("A very full week is cut to something the system will hold")
    func planIsBounded() {
        let crowded = (0..<40).map {
            activity("a\($0)", "Thing \($0)", at: 6 * 60 + $0 * 20, on: [today, tomorrow])
        }
        let plan = plan(state(completedToday: 1, schedule: crowded))
        #expect(plan.count <= ForgeNotificationPlan.limit + 2)
    }
}

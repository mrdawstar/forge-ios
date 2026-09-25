import Foundation
import Testing
@testable import Forge

/// The weekly review, the observation, and coming back.
///
/// Three subjects in one file because they are one feature: the app's only
/// output. Half of what is here holds the promise that **every one of them is
/// skippable and none of them blocks a day** — the half that would fail
/// silently.
///
/// `@MainActor` because `ReviewStore` is, and the Xcode 26 toolchain enforces
/// actor isolation on `#expect` where earlier ones did not.
@MainActor
@Suite("The weekly review")
struct ReviewTests {

    private func makeStore() -> ReviewStore {
        ReviewStore(
            defaults: UserDefaults(suiteName: "forge.reviews.\(UUID().uuidString)") ?? .standard
        )
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> ForgeDay {
        ForgeDay(year: y, month: m, day: d)
    }

    // MARK: - Which week

    /// The window ends on the review weekday and runs back seven days.
    ///
    /// Defined against the *review* weekday rather than `Calendar.firstWeekday`,
    /// which is the whole of why "Sunday evening reviews the week that just
    /// ended" is true in every region rather than in half of them.
    @Test("The week under review ends on the review day")
    func windowEndsOnTheReviewDay() {
        let store = makeStore()
        store.reviewWeekday = 1 // Sunday

        // 2026-08-09 is a Sunday. Asked on that Sunday: that Sunday.
        let sunday = day(2026, 8, 9)
        #expect(sunday.weekday == 1, "fixture is not a Sunday")
        var window = store.currentWindow(on: sunday)
        #expect(window.end == sunday)
        #expect(window.start == day(2026, 8, 3))

        // Asked on the following Wednesday: still that Sunday's week, because
        // it is the most recent one that has closed.
        window = store.currentWindow(on: day(2026, 8, 12))
        #expect(window.end == sunday)
        #expect(window.start == day(2026, 8, 3))
    }

    /// Somebody whose week ends on a Thursday is asked on a Thursday.
    @Test("Changing the review day moves the window with it")
    func windowFollowsTheSetting() {
        let store = makeStore()
        store.reviewWeekday = 5 // Thursday
        let window = store.currentWindow(on: day(2026, 8, 9))
        #expect(window.end == day(2026, 8, 6))
        #expect(window.end.weekday == 5)
        #expect(window.start == day(2026, 7, 31))
    }

    /// The day boundary is Forge's, not midnight's.
    ///
    /// Somebody answering at one in the morning on Monday is still inside
    /// Sunday — `ForgeDay` has already resolved that — so they get Sunday's
    /// review rather than next week's. This is the same four-in-the-morning rule
    /// every other reading in the app follows, and it arrives here for free
    /// precisely because the window is defined on `ForgeDay`.
    @Test("A late Sunday night is still Sunday's review")
    func windowUsesTheDayClock() {
        let store = makeStore()
        store.reviewWeekday = 1

        let lateSunday = Calendar.current.date(
            from: DateComponents(year: 2026, month: 8, day: 10, hour: 1, minute: 30)
        )!
        let asForge = ForgeDay.containing(lateSunday, dayStartHour: 4)
        #expect(asForge == day(2026, 8, 9), "one a.m. Monday is still Sunday")
        #expect(store.currentWindow(on: asForge).end == day(2026, 8, 9))

        // And with a day that starts at midnight it is genuinely Monday, which
        // is the correct answer for somebody who set it that way.
        let asMidnight = ForgeDay.containing(lateSunday, dayStartHour: 0)
        #expect(asMidnight == day(2026, 8, 10))
    }

    // MARK: - When it is offered

    @Test("Not before the evening of the review day")
    func notUntilEvening() {
        let store = makeStore()
        store.reviewWeekday = 1
        let sunday = day(2026, 8, 9)
        let start = day(2026, 1, 1)

        #expect(!store.isDue(on: sunday, hour: 9, askedDays: 5, firstTracked: start))
        #expect(!store.isDue(on: sunday, hour: ReviewStore.hour - 1, askedDays: 5, firstTracked: start))
        #expect(store.isDue(on: sunday, hour: ReviewStore.hour, askedDays: 5, firstTracked: start))
        // And on any later day of the week, at any hour: the window has closed,
        // so there is nothing left to wait for.
        #expect(store.isDue(on: day(2026, 8, 11), hour: 7, askedDays: 5, firstTracked: start))
    }

    /// Dismissed is dealt with. A review declined on Sunday does not come back
    /// on Monday, and nothing anywhere counts that it was declined.
    @Test("Dismissing a week ends it")
    func dismissingIsFinal() {
        let store = makeStore()
        store.reviewWeekday = 1
        let sunday = day(2026, 8, 9)
        let window = store.currentWindow(on: sunday)

        #expect(store.isDue(on: sunday, hour: 20, askedDays: 5, firstTracked: day(2026, 1, 1)))
        store.dismiss(week: window.start)
        #expect(!store.isDue(on: sunday, hour: 20, askedDays: 5, firstTracked: day(2026, 1, 1)))
        // Declining leaves nothing to read back: it is not an answer.
        #expect(store.answered.isEmpty)
    }

    @Test("Answering a week ends it, and keeps what was written")
    func answeringIsKept() throws {
        let store = makeStore()
        let window = store.currentWindow(on: day(2026, 8, 9))
        store.answer(week: window.start, whatHappened: "Two hard days.", whatNext: "Sleep.")

        let saved = try #require(store.review(for: window.start))
        #expect(saved.whatHappened == "Two hard days.")
        #expect(saved.whatNext == "Sleep.")
        #expect(saved.isAnswered)
        #expect(store.isDealtWith(week: window.start))
        #expect(store.answered.count == 1)
    }

    /// A week that asked for nothing has nothing to review, and an install two
    /// days old is not a week.
    @Test("Nothing to review means nothing is offered")
    func nothingToReview() {
        let store = makeStore()
        store.reviewWeekday = 1
        let sunday = day(2026, 8, 9)

        #expect(!store.isDue(on: sunday, hour: 20, askedDays: 0, firstTracked: day(2026, 1, 1)))
        #expect(!store.isDue(on: sunday, hour: 20, askedDays: 5, firstTracked: nil))
        #expect(!store.isDue(
            on: sunday, hour: 20, askedDays: 5, firstTracked: day(2026, 8, 14)
        ), "an install that started after the window is not reviewing it")
    }

    /// The one that would be quietly wrong for half the world.
    ///
    /// A window built from `Calendar.firstWeekday` reviews a week that has
    /// barely started for every user in a region that begins the week on
    /// Sunday. This checks the answer does not move when the calendar's own
    /// first weekday does.
    @Test("The window does not depend on the calendar's first weekday")
    func windowIgnoresLocale() {
        let store = makeStore()
        store.reviewWeekday = 1
        let expected = store.currentWindow(on: day(2026, 8, 12))

        for first in 1...7 {
            var calendar = Calendar(identifier: .gregorian)
            calendar.firstWeekday = first
            // The window is arithmetic on `ForgeDay.weekday`, which is a fact
            // about the date rather than about the region reading it.
            #expect(store.currentWindow(on: day(2026, 8, 12)) == expected)
        }
    }

    @Test("Reviews survive a new store on the same defaults")
    func persistence() throws {
        let suite = try #require(UserDefaults(suiteName: "forge.reviews.\(UUID().uuidString)"))
        let first = ReviewStore(defaults: suite)
        first.reviewWeekday = 4
        first.answer(week: day(2026, 8, 3), whatHappened: "Kept it.", whatNext: "Again.")

        let second = ReviewStore(defaults: suite)
        #expect(second.reviewWeekday == 4)
        #expect(second.review(for: day(2026, 8, 3))?.whatHappened == "Kept it.")
    }

    @Test("A review row missing everything but its week still decodes")
    func tolerantDecoding() throws {
        let json = Data(#"[{"weekStart":{"year":2026,"month":8,"day":3}}]"#.utf8)
        let decoded = try JSONDecoder().decode([WeeklyReview].self, from: json)
        #expect(decoded.count == 1)
        #expect(decoded[0].whatHappened.isEmpty)
        #expect(!decoded[0].isAnswered)
        #expect(decoded[0].completedAt == nil)
    }

    // MARK: - What the app notices

    private func facts(
        kept: Int = 0,
        asked: Int = 0,
        weekdays: [ReviewFacts.Weekday] = [],
        habits: [ReviewFacts.Habit] = [],
        identities: [ReviewFacts.Identity] = []
    ) -> ReviewFacts {
        ReviewFacts(
            kept: kept, asked: asked, windowWeeks: 5,
            weekdays: weekdays, habits: habits, identities: identities
        )
    }

    /// The observation somebody could not have made themselves.
    @Test("A real weekday split is named, with both counts")
    func weekdaySplitIsNamed() throws {
        let observation = try #require(ReviewObservation.make(from: facts(
            kept: 3, asked: 5,
            weekdays: [
                ReviewFacts.Weekday(weekday: 2, kept: 4, asked: 5),
                ReviewFacts.Weekday(weekday: 6, kept: 1, asked: 5),
            ]
        )))
        #expect(observation.contains("four of five"))
        #expect(observation.contains("one of five"))
        #expect(!observation.contains("!"), "nothing in this app exclaims")
    }

    /// Nothing invented from a tie — the rule that makes the loud cases worth
    /// reading. Two weekdays at the same rate is not a finding.
    @Test("A tie produces no weekday observation")
    func tiesAreNotFindings() {
        let tied = facts(
            kept: 4, asked: 8,
            weekdays: [
                ReviewFacts.Weekday(weekday: 2, kept: 2, asked: 4),
                ReviewFacts.Weekday(weekday: 6, kept: 2, asked: 4),
            ]
        )
        #expect(ReviewObservation.weekdaySplit(tied) == nil)
        // It still says something — the floor rule — but not that.
        let said = ReviewObservation.make(from: tied)
        #expect(said != nil)
        #expect(said?.contains("Mondays") != true)
    }

    /// Too few samples is not a pattern. A fortnight of bad luck must not read
    /// as one.
    @Test("A weekday needs enough behind it to be worth saying")
    func weekdayNeedsASample() {
        let thin = facts(
            kept: 1, asked: 3,
            weekdays: [
                ReviewFacts.Weekday(weekday: 2, kept: 2, asked: 2),
                ReviewFacts.Weekday(weekday: 6, kept: 0, asked: 2),
            ]
        )
        #expect(ReviewObservation.weekdaySplit(thin) == nil)
    }

    @Test("Two habits far enough apart are both named, and neither is judged")
    func habitSplitIsNamed() throws {
        let observation = try #require(ReviewObservation.habitSplit(facts(
            habits: [
                ReviewFacts.Habit(id: "read", name: "Read", planned: 5, completed: 5),
                ReviewFacts.Habit(id: "run", name: "Go for a run", planned: 4, completed: 0),
            ]
        )))
        #expect(observation.hasPrefix("Read held every day it was asked for."))
        #expect(observation.contains("Go for a run did not."))
    }

    @Test("Two habits at the same rate produce nothing")
    func habitTiesAreNotFindings() {
        #expect(ReviewObservation.habitSplit(facts(
            habits: [
                ReviewFacts.Habit(id: "read", name: "Read", planned: 4, completed: 3),
                ReviewFacts.Habit(id: "run", name: "Run", planned: 4, completed: 3),
            ]
        )) == nil)
    }

    /// An identity is only ever called neglected when another one was not, and
    /// never when it was simply not on the list.
    @Test("A neglected identity is named against one that was not")
    func neglectIsRelative() throws {
        let observation = try #require(ReviewObservation.neglectedIdentity(facts(
            identities: [
                ReviewFacts.Identity(id: "a", statement: "Someone who trains", days: 0, asked: 4),
                ReviewFacts.Identity(id: "b", statement: "Someone who reads", days: 4, asked: 5),
            ]
        )))
        #expect(observation.hasPrefix("Someone who trains had no day this week."))
        #expect(observation.contains("Someone who reads had four."))

        // Never asked for is not neglected.
        #expect(ReviewObservation.neglectedIdentity(facts(
            identities: [
                ReviewFacts.Identity(id: "a", statement: "Someone who trains", days: 0, asked: 0),
                ReviewFacts.Identity(id: "b", statement: "Someone who reads", days: 4, asked: 5),
            ]
        )) == nil)

        // And a single identity is never compared with itself.
        #expect(ReviewObservation.neglectedIdentity(facts(
            identities: [
                ReviewFacts.Identity(id: "a", statement: "Someone who trains", days: 0, asked: 4),
            ]
        )) == nil)
    }

    /// The empty week says nothing at all. A first week has no pattern in it and
    /// an app that produced one anyway teaches somebody the observations are
    /// decoration.
    @Test("An empty week produces no observation")
    func emptyWeekIsSilent() {
        #expect(ReviewObservation.make(from: ReviewFacts()) == nil)
        #expect(ReviewObservation.make(from: facts(kept: 0, asked: 0)) == nil)
    }

    /// The floor. Something true, with no verdict on it.
    @Test("A week with days in it always gets a plain count")
    func plainCountIsTheFloor() throws {
        let said = try #require(ReviewObservation.make(from: facts(kept: 3, asked: 6)))
        #expect(said.contains("Three"))
        let none = try #require(ReviewObservation.make(from: facts(kept: 0, asked: 4)))
        #expect(none == "No day was finished this week. The record simply says so.")
    }

    /// **The sentence agrees with its own numbers.** A first week — one day on
    /// the record, and the commonest week there is — read "One of the one days
    /// that asked for something *were* kept": three mistakes in the one sentence
    /// Forge writes about somebody's week.
    @Test("The plain count agrees in number")
    func plainCountAgreesInNumber() throws {
        let oneOfOne = try #require(ReviewObservation.make(from: facts(kept: 1, asked: 1)))
        #expect(oneOfOne == "The one day that asked for something was kept.")

        let noneOfOne = try #require(ReviewObservation.make(from: facts(kept: 0, asked: 1)))
        #expect(noneOfOne
                == "The one day that asked for something was not finished. The record simply says so.")

        let oneOfFour = try #require(ReviewObservation.make(from: facts(kept: 1, asked: 4)))
        #expect(oneOfFour == "One of the four days that asked for something was kept.")

        let twoOfFour = try #require(ReviewObservation.make(from: facts(kept: 2, asked: 4)))
        #expect(twoOfFour == "Two of the four days that asked for something were kept.")

        // And nothing anywhere says "one days".
        for week in [facts(kept: 1, asked: 1), facts(kept: 0, asked: 1)] {
            let said = try #require(ReviewObservation.make(from: week))
            #expect(!said.contains("one days"))
        }
    }

    /// Nothing in any of them congratulates or scolds.
    @Test("No observation praises, blames or exclaims")
    func registerHolds() {
        let cases: [ReviewFacts] = [
            facts(kept: 7, asked: 7),
            facts(kept: 0, asked: 5),
            facts(kept: 3, asked: 6, weekdays: [
                ReviewFacts.Weekday(weekday: 2, kept: 4, asked: 5),
                ReviewFacts.Weekday(weekday: 6, kept: 1, asked: 5),
            ]),
            facts(habits: [
                ReviewFacts.Habit(id: "read", name: "Read", planned: 5, completed: 5),
                ReviewFacts.Habit(id: "run", name: "Run", planned: 4, completed: 0),
            ]),
        ]
        let banned = ["!", "great", "amazing", "well done", "keep it up",
                      "unfortunately", "failed", "should", "try harder"]
        for facts in cases {
            guard let said = ReviewObservation.make(from: facts)?.lowercased() else { continue }
            for word in banned {
                #expect(!said.contains(word), Comment(rawValue: "'\(word)' in: \(said)"))
            }
        }
    }

    // MARK: - Coming back

    /// Three days, and the threshold is a judgement about what a gap means.
    @Test("A gap of three days or more is a return")
    func returnThreshold() {
        #expect(!ReEntry.isReturning(gap: 0, daysKept: 40, isTodayEarned: false))
        #expect(!ReEntry.isReturning(gap: 1, daysKept: 40, isTodayEarned: false))
        #expect(!ReEntry.isReturning(gap: 2, daysKept: 40, isTodayEarned: false))
        #expect(ReEntry.isReturning(gap: 3, daysKept: 40, isTodayEarned: false))
        #expect(ReEntry.isReturning(gap: 90, daysKept: 206, isTodayEarned: false))
    }

    /// Never to a stranger, and never to somebody who has already kept today.
    @Test("There is nothing to return from without a record")
    func returnNeedsARecord() {
        #expect(!ReEntry.isReturning(gap: nil, daysKept: 0, isTodayEarned: false))
        #expect(!ReEntry.isReturning(gap: 10, daysKept: 0, isTodayEarned: false))
        #expect(!ReEntry.isReturning(gap: 10, daysKept: 40, isTodayEarned: true),
                "a day finished today ends the absence")
    }

    /// **No number that can go down appears on this screen.** The absence is
    /// named as a length and never characterised, and the count is the only
    /// figure — cumulative by construction.
    @Test("The return screen names the gap and never judges it")
    func returnRegister() {
        let banned = ["streak", "chain", "lost", "broke", "back on track",
                      "welcome", "missed", "sorry", "!"]
        for gap in [3, 5, 8, 20, 60, 400] {
            let said = ReEntry.absence(days: gap).lowercased()
            for word in banned {
                #expect(!said.contains(word), Comment(rawValue: "'\(word)' in: \(said)"))
            }
        }
        for kept in [1, 12, 206] {
            let said = ReEntry.reassurance(daysKept: kept).lowercased()
            for word in banned {
                #expect(!said.contains(word), Comment(rawValue: "'\(word)' in: \(said)"))
            }
        }
    }

    // MARK: - The weekly notification

    /// One repeating request, silent, on the day the review is offered.
    @Test("The plan carries one weekly review notification")
    func reviewNotificationIsPlanned() throws {
        var state = ForgeNotificationState(
            now: .now,
            currentDay: day(2026, 8, 12),
            dayStartHour: 4,
            wakeMinutes: 7 * 60,
            completedToday: 0,
            plannedToday: 0,
            isTodayEarned: false,
            streak: 0
        )
        state.reviewWeekday = 1

        let planned = try #require(ForgeNotificationPlan.review(for: state))
        #expect(planned.kind == .review)
        #expect(planned.when == .weekly(weekday: 1, hour: ReviewStore.hour, minute: 0))
        #expect(!planned.body.isEmpty)

        // Off, for somebody with nothing to review yet.
        state.reviewWeekday = nil
        #expect(ForgeNotificationPlan.review(for: state) == nil)
    }

    /// The rewrite: what a notification says when the day is evidence for
    /// something, and what it says when it is not.
    @Test("Notifications name the identity where there is one")
    func notificationsSpeakInTheIdentityVoice() {
        #expect(ForgeNotificationPlan.begin("Someone who trains")
                == "Evidence for someone who trains.")
        #expect(ForgeNotificationPlan.waiting("Someone who reads", done: 0, planned: 0)
                == "Still on today's list. Evidence for someone who reads.")
        // A name inside somebody's own sentence is not flattened.
        #expect(ForgeNotificationPlan.begin("Someone who shows up for Maya")
                .contains("Maya"))
    }

    /// And what it says when there is no identity, which after the first run was
    /// rebuilt is almost everybody. Nothing here is a slogan: it is either what
    /// the person set, or where their day has got to.
    @Test("Without an identity, notifications quote the user's own numbers")
    func notificationsQuoteTheRecord() {
        // The duration they chose, not an estimate.
        #expect(ForgeNotificationPlan.begin(nil, minutes: 20) == "20 min. Then it is behind you.")
        // An activity with no duration set has nothing to quote.
        #expect(ForgeNotificationPlan.begin(nil) == "It is on today's list.")

        #expect(ForgeNotificationPlan.waiting(nil, done: 0, planned: 0)
                == "Still on today's list.")
        #expect(ForgeNotificationPlan.waiting(nil, done: 2, planned: 5)
                == "Still on today's list. 2 of 5 done.")

        // The morning's fallback: the count, spelled, and never the streak.
        #expect(ForgeNotificationPlan.standing(daysKept: 0) == "The first one.")
        // One, because this is the first standing line anybody ever reads and it
        // said "One days kept." until 2026-09-15. Zero, forty-one and
        // ninety-one were covered; the only value with a grammar of its own was
        // not.
        #expect(ForgeNotificationPlan.standing(daysKept: 1) == "One day kept.")
        #expect(ForgeNotificationPlan.standing(daysKept: 2) == "Two days kept.")
        #expect(ForgeNotificationPlan.standing(daysKept: 41) == "Forty-one days kept.")
    }

    // MARK: - The challenge, rebound

    /// The aim moved from what the day already holds to what is being
    /// neglected. A day of running used to get a physical challenge on top of
    /// the run; now it gets one aimed at whatever is not happening.
    @Test("The challenge is aimed at the neglected identity")
    func challengeFollowsTheNeglectedIdentity() {
        let day = ChallengeContext(
            activities: ["Go for a run", "Push-ups"],
            categories: [],
            neglected: "Someone who reads"
        )
        #expect(day.leanings.contains(.intellect))
        #expect(!day.leanings.contains(.physical),
                "the challenge is still pointing at what the day already holds")

        // Nothing named: the day's own reading, exactly as before.
        let unaimed = ChallengeContext(activities: ["Go for a run"], categories: [])
        #expect(unaimed.leanings == [.physical])

        // A sentence no signal reaches falls back rather than aiming at nothing.
        let unmatched = ChallengeContext(
            activities: ["Go for a run"], categories: [], neglected: "Someone who yodels"
        )
        #expect(unmatched.leanings == [.physical])
    }

    /// The selection is still arithmetic on the date. Rebinding the aim must not
    /// have made the daily challenge random.
    @Test("The same day still yields the same challenge")
    func selectionIsStillDeterministic() {
        let context = ChallengeContext(
            activities: ["Read"], categories: [], neglected: "Someone who trains"
        )
        for d in 1...28 {
            let a = ChallengeCatalog.challenge(for: day(2026, 8, d), context: context)
            let b = ChallengeCatalog.challenge(for: day(2026, 8, d), context: context)
            #expect(a == b)
        }
    }
}

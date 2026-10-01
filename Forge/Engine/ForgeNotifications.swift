import Foundation
import UserNotifications

// MARK: - The three

/// Everything Forge is ever allowed to say.
///
/// Six cases, and a seventh is a product decision rather than a code change:
/// these identifiers are the whole of "at most one pending notification of each
/// type", so anything that wants to speak has to already be one of them or it
/// cannot be scheduled at all. The sixth, `trial`, was that decision
/// (DIRECTION_1_1 §1).
enum ForgeNotification: String, CaseIterable, Sendable {
    /// The day opening, named after the first thing on it.
    case morning
    /// An activity, at the time it was put on the day.
    case activity
    /// One follow-up, for something that should have happened by now.
    case missed
    /// A day that was started and left.
    case evening
    /// Once a week, the review. The only one here that is not about a day.
    ///
    /// It is a single repeating request — one per week, forever — which is the
    /// cheapest thing in the whole plan and the only one that speaks about
    /// something other than what is outstanding. See `ReviewStore`.
    case review
    /// Two days before a free week ends, because the paywall promised it
    /// ("Day 5: we remind you"). Not part of the day's plan and not behind the
    /// day's switch: somebody who asked for this reminder gets it whether or
    /// not they want to hear about their activities. See `TrialReminder`.
    case trial

    /// Stable across launches, and unique per occurrence.
    ///
    /// The suffix is what makes a plan of thirty requests addressable: one
    /// activity on one weekday is one identifier, and re-planning writes the
    /// same string for the same occurrence. The kind is the second component so
    /// a tap can be read back — see `init?(identifier:)`.
    func identifier(_ key: String) -> String { "forge.\(rawValue).\(key)" }

    /// Which kind a delivered notification was, read back off its identifier.
    ///
    /// Prefix matching rather than equality, because the identifier now carries
    /// the occasion as well as the kind. Anything unrecognised — including the
    /// three fixed identifiers older builds registered — comes back nil, which
    /// is the right answer: it means "Forge no longer knows what this was", and
    /// the only thing that reads it is the tap handler.
    init?(identifier: String) {
        guard let match = Self.allCases.first(where: {
            identifier.hasPrefix("forge.\($0.rawValue).")
        }) else { return nil }
        self = match
    }
}

// MARK: - What the decision depends on

/// One reading of the day, taken once and handed to the rules.
///
/// A value rather than the stores it came from, so scheduling is a pure function
/// of a day and can be checked without a phone, a clock or a permission prompt.
struct ForgeNotificationState: Equatable {
    var now: Date
    /// The day the app believes it is in — not the date on the clock. At two
    /// in the morning those are different, and every rule here means the former.
    var currentDay: ForgeDay
    var dayStartHour: Int
    /// Minutes past midnight. The time the user set, and now a *fallback* — a
    /// day whose activities all carry their own hour opens on the first of
    /// them instead. See `morning(_:for:)`.
    var wakeMinutes: Int
    var completedToday: Int
    /// What today's day was made of when it was planned.
    var plannedToday: Int
    var isTodayEarned: Bool
    var streak: Int
    /// Days kept, ever.
    ///
    /// **The count, never the chain.** The morning names it and the streak is
    /// deliberately not what it names: a streak is a number whose only property
    /// is that it can be lost, and a notification built on it is a notification
    /// that works by making somebody afraid — which is the register this app has
    /// spent every other decision refusing (see the widget's note on why the
    /// mark is not a flame). Days kept only ever goes up, so naming it is a fact
    /// about somebody rather than a lever on them.
    ///
    /// It is baked into a repeating request, so it can be a few days behind for
    /// a phone that has not opened Forge. That is the safe direction and the only
    /// one available: a day is not kept without the app, so this can undercount
    /// and can never overstate.
    var daysKept: Int = 0
    /// The week as the planner holds it: every activity, its hour, and the days
    /// it belongs to. The whole input to items 1, 2, 5 and 6 of the brief.
    var schedule: [ScheduledActivity] = []
    /// Which of today's activities are already done. Only today's — a follow-up
    /// can only be judged against a day whose completions are knowable, which is
    /// the reason `missed` never looks past it.
    var completedIDs: Set<String> = []
    /// Identity id to the sentence somebody wrote, for the copy that names one.
    ///
    /// A map rather than a field on `ScheduledActivity`, deliberately: that type
    /// is also what `AIBrief` is built from, and it carries an opaque id
    /// precisely so a statement about who somebody is cannot leave the phone by
    /// accident. A notification is drawn on the user's own lock screen by the
    /// user's own device, which is a different disclosure entirely — so the
    /// statement is joined here, at the one point that needs it.
    var identities: [String: String] = [:]
    /// Which weekday the review is offered on, or nil when there is nothing to
    /// review yet. See `ForgeNotificationPlan.review(for:)`.
    var reviewWeekday: Int?
    /// The Arc being run, or nil. See `ForgeNotificationPlan.arcMornings`.
    var arc: ArcNotice? = nil
    var calendar: Calendar = .current

    /// The sentence an activity is evidence for, if any.
    func identity(of activity: ScheduledActivity) -> String? {
        activity.identityID.flatMap { identities[$0] }
    }

    var wakeHour: Int { normalizedWake / 60 }
    var wakeMinute: Int { normalizedWake % 60 }

    private var normalizedWake: Int { ((wakeMinutes % 1440) + 1440) % 1440 }

    /// What a given weekday holds, in the order the day happens in.
    ///
    /// Everything with an hour, in clock order, then everything else in the
    /// order the user arranged it — the same rule the day list itself uses, and
    /// for the same reason. See `Ritual.chronological`.
    ///
    /// The tiebreak is the arranged position rather than the id, and that is not
    /// cosmetic: a day of untimed activities has nothing but the tiebreak to go
    /// on, so sorting by id would have the morning notification name whichever
    /// activity happened to sort first alphabetically instead of the one the
    /// user put at the top of their day.
    func activities(on weekday: Int) -> [ScheduledActivity] {
        schedule.enumerated()
            .filter { $0.element.happens(on: weekday) }
            .sorted {
                ($0.element.startMinute ?? .max, $0.offset)
                    < ($1.element.startMinute ?? .max, $1.offset)
            }
            .map(\.element)
    }
}

/// What the morning needs to know about a running Arc: its name, its first
/// day and length, and the days its phases begin. Values, so the plan stays a
/// pure function of the day.
struct ArcNotice: Equatable, Sendable {
    struct Phase: Equatable, Sendable {
        let name: String
        let firstDay: Int
    }

    let name: String
    let startDay: ForgeDay
    let length: Int
    /// Every phase after the first — the first begins on day one, and day one
    /// is not a change of anything.
    let phases: [Phase]

    /// Which day of the Arc a day is, or nil outside it.
    func number(of day: ForgeDay) -> Int? {
        let number = day.days(since: startDay) + 1
        return (1...length).contains(number) ? number : nil
    }
}

/// One notification, and when it should land.
struct PlannedNotification: Equatable {
    enum When: Equatable {
        /// Every day at this time. One pending request for an activity that
        /// happens every day, rather than seven.
        case daily(hour: Int, minute: Int)
        /// Every week on this weekday. The shape the activity model is already
        /// in — an activity is a set of weekdays — so a repeat rule becomes one
        /// request per weekday and keeps working through a month of the app
        /// never being opened.
        case weekly(weekday: Int, hour: Int, minute: Int)
        /// One instant, because the reason for it is true today and may not be
        /// true tomorrow.
        case once(Date)
    }

    let kind: ForgeNotification
    /// What makes this request unique among its kind — an activity and a day.
    let key: String
    let when: When
    let title: String
    let body: String

    var identifier: String { kind.identifier(key) }
}

// MARK: - The rules

/// When Forge is allowed to speak, and about what.
///
/// No side effects and no notification centre: everything here is arithmetic on
/// a `ForgeNotificationState`, which is what makes every path testable.
enum ForgeNotificationPlan {

    /// When the evening reminder lands. Not configurable, deliberately —
    /// Settings gets one switch and one time, and this is not that time.
    static let eveningHour = 20

    /// How long after something was due before Forge says anything about it.
    ///
    /// The floor, not the rule: the follow-up lands a whole activity's length
    /// after it started, or half an hour, whichever is later. A twenty-minute
    /// workout is asked about at half past; a forty-five minute block of deep
    /// work is not interrupted a quarter of the way through it.
    static let missedGrace = 30

    /// A ceiling on how much Forge will ever have pending.
    ///
    /// iOS keeps 64 pending requests per app and silently drops the rest, so a
    /// plan that could exceed it has to decide *which* ones survive rather than
    /// letting the system decide. In practice this never binds — a daily
    /// activity costs one request, not seven — and it is here so that the day
    /// somebody builds a fifteen-activity week ends in a short plan rather than
    /// an arbitrary one.
    static let limit = 60

    /// Every notification the schedule justifies, in the order the week happens.
    ///
    /// The whole plan is rebuilt on every pass and everything pending is thrown
    /// away first — see `ForgeNotifications.apply` — which is the only reliable
    /// answer to "what happens when the user changes the time, moves the day,
    /// deletes the activity or copies a day onto another". Nothing is patched,
    /// so nothing can be left behind.
    static func make(for state: ForgeNotificationState) -> [PlannedNotification] {
        var plan: [PlannedNotification] = []
        // While an Arc runs the mornings are dated rather than repeating — see
        // `arcMornings` — and the week's own repeating ones stand aside, or a
        // morning would arrive twice.
        let datedMornings = state.arc != nil
        if let uniform = uniformWeekday(for: state) {
            // Every day of the week holds the same day, so it is scheduled once
            // and repeats daily — see `at(_:on:for:)`. Seven identical copies
            // would be seven of the sixty-odd requests iOS will hold, spent on
            // saying the same thing.
            plan = day(uniform, for: state, morning: !datedMornings)
        } else {
            // Monday first, so a plan that has to be cut keeps a recognisable
            // week rather than a fortnight of Sundays.
            for weekday in [2, 3, 4, 5, 6, 7, 1] {
                plan += day(weekday, for: state, morning: !datedMornings)
            }
        }
        plan = Array(plan.prefix(limit))
        // Outside the cap, like the two below: a week of them is seven
        // requests, and they replace the week's own mornings rather than
        // joining them.
        if datedMornings { plan += arcMornings(for: state) }

        // The two that are about *today* specifically, and are therefore single
        // instants rather than repeats. They go on the end so the cap above can
        // never be what removes them.
        if let missed = missed(for: state) { plan.append(missed) }
        if let evening = evening(for: state) { plan.append(evening) }
        // Last, and outside the cap for the same reason the two above are: a
        // weekly request costs one slot of sixty and is the only thing Forge
        // says that is not about something outstanding.
        if let review = review(for: state) { plan.append(review) }
        return plan
    }

    // MARK: One day of the week

    /// What a single weekday is worth saying, or nothing at all.
    ///
    /// **A day with nothing on it gets nothing.** That is the first line of this
    /// function and the whole of item 6: an unplanned Thursday is not a day to
    /// be reminded about, it is a day that has not been planned, and the app has
    /// a screen that says so — see the planner's empty state.
    private static func day(
        _ weekday: Int,
        for state: ForgeNotificationState,
        morning includesMorning: Bool = true
    ) -> [PlannedNotification] {
        let activities = state.activities(on: weekday)
        guard !activities.isEmpty else { return [] }

        let timed = activities.filter { $0.startMinute != nil }
        let opening = morning(weekday, first: activities.first, firstTimed: timed.first, for: state)
        var plan = includesMorning ? [opening] : []

        // Each activity at the hour it was given, and only those that have one.
        // An activity with no time is not an appointment — Forge has never
        // pretended otherwise — so it is named by the morning and left alone.
        for activity in timed {
            guard let minute = activity.startMinute else { continue }
            // The morning already speaks at this minute — a dated one as much
            // as a repeating one. Two notifications arriving together is the
            // one thing that would make either of them feel automated.
            guard minute != opening.when.minuteOfDay else { continue }
            plan.append(
                PlannedNotification(
                    kind: .activity,
                    key: "\(weekday).\(activity.id)",
                    when: at(minute, on: weekday, for: state),
                    title: activity.name,
                    body: begin(state.identity(of: activity), minutes: activity.minutes)
                )
            )
        }
        return plan
    }

    /// The day's opening, named after the first thing on it.
    ///
    /// It fires at whichever comes first: the hour the user set in Settings, or
    /// the first activity that carries one. Both readings of "when does my day
    /// start" are true for somebody, and taking the earlier of the two means the
    /// opening is never an announcement of something that has already begun.
    ///
    /// A day of untimed activities — which is every day somebody keeps straight
    /// out of onboarding — falls back to the Settings time, and is the reason
    /// that setting still exists.
    private static func morning(
        _ weekday: Int,
        first: ScheduledActivity?,
        firstTimed: ScheduledActivity?,
        for state: ForgeNotificationState
    ) -> PlannedNotification {
        let wake = state.wakeHour * 60 + state.wakeMinute
        let minute = min(wake, firstTimed?.startMinute ?? wake)
        return PlannedNotification(
            kind: .morning,
            key: "\(weekday)",
            when: at(minute, on: weekday, for: state),
            // The identity the day's first thing is for, where there is one —
            // otherwise the one fact about this person the app is certain of.
            //
            // This is the whole of the rewrite: a notification that says
            // "Someone who trains" is a reminder of what the next twenty minutes
            // are in aid of, and "Your day starts now" is an alarm clock. It is
            // their own sentence, on their own lock screen, and Forge never adds
            // a word to it — no "Time to be", no "Remember: you are".
            title: first.flatMap(state.identity) ?? standing(daysKept: state.daysKept),
            body: opening(first: first, firstTimed: firstTimed, at: minute)
        )
    }

    // MARK: A running Arc

    /// How far ahead the dated mornings reach.
    static let arcHorizon = 7

    /// The mornings of a running Arc: "Day 12 of 90" in each (DIRECTION_1_1
    /// §5), and on the two days that are different, what is different.
    ///
    /// # Why they are dated, and why only a week of them
    ///
    /// The day number changes every morning, and a repeating request is one
    /// sentence forever — "Day 12 of 90" would still be arriving on day forty.
    /// So while an Arc runs the mornings are single instants, one per day for
    /// the next seven, each carrying its own number; every open of the app
    /// lays the next seven down again. A week of the app unopened ends in a
    /// quiet phone rather than a wrong number, which is the honest failure.
    ///
    /// # The phase and the last day
    ///
    /// The morning a phase begins says so — "Build starts today." — and the
    /// last day says it is the last. **They replace that morning rather than
    /// join it**, so each is one notification, never a second one at the same
    /// minute. A day past the end inside the week gets an ordinary morning.
    /// Nothing here counts what has not been done: no streak, nothing that
    /// can be lost.
    static func arcMornings(for state: ForgeNotificationState) -> [PlannedNotification] {
        guard let arc = state.arc else { return [] }
        var plan: [PlannedNotification] = []
        for offset in 0..<arcHorizon {
            let date = state.currentDay.adding(days: offset)
            let activities = state.activities(on: date.weekday)
            let number = arc.number(of: date)
            let phase = number.flatMap { day in arc.phases.first { $0.firstDay == day } }
            let isLast = number == arc.length
            guard !activities.isEmpty || phase != nil || isLast else { continue }

            let timed = activities.filter { $0.startMinute != nil }
            let wake = state.wakeHour * 60 + state.wakeMinute
            let minute = min(wake, timed.first?.startMinute ?? wake)
            let midnight = date.startOfDay(in: state.calendar)
            guard let at = state.calendar.date(
                bySettingHour: minute / 60, minute: minute % 60, second: 0, of: midnight
            ), at > state.now else { continue }

            let first = opening(first: activities.first, firstTimed: timed.first, at: minute)
            let title: String
            let body: String
            if let number, let phase {
                title = "\(phase.name) starts today."
                body = "\(arc.name), day \(number) of \(arc.length). What changes is on the Arcs tab."
            } else if let number, isLast {
                title = "The last day of \(arc.name)."
                body = "Day \(number) of \(arc.length). \(first)"
            } else if let number {
                title = activities.first.flatMap(state.identity) ?? standing(daysKept: state.daysKept)
                body = "Day \(number) of \(arc.length). \(first)"
            } else {
                title = activities.first.flatMap(state.identity) ?? standing(daysKept: state.daysKept)
                body = first
            }

            plan.append(
                PlannedNotification(
                    kind: .morning,
                    key: "arc.\(date.year)-\(date.month)-\(date.day)",
                    when: .once(at),
                    title: title,
                    body: body
                )
            )
        }
        return plan
    }

    /// What the app can say about somebody who has named nobody.
    ///
    /// **Their own count, spelled.** The identity spine is history-only now — a
    /// new install never names one — so the fallback is what almost everybody
    /// actually sees, and it was "Your day starts now.", which is the same
    /// sentence on day one and day four hundred and could have been written by
    /// any app on the phone.
    ///
    /// A number they earned cannot be generic and cannot go stale, because it is
    /// theirs and it moves. It is stated flatly, with no verdict: "Ninety-one
    /// days kept." is a fact; "91 days — amazing streak!" is three things this
    /// app does not do.
    /// Takes the count rather than the whole state, so the notification primer
    /// can render the real sentence without assembling a scheduler's worth of
    /// facts — see `NotificationPrimerView`, which used to carry its own copy of
    /// these three strings and had drifted out of step with all of them.
    static func standing(daysKept: Int) -> String {
        guard daysKept > 0 else { return "The first one." }
        // Singular at one, and it is worth the branch: the very first standing
        // notification anybody ever gets is the one for a single day, so
        // "One days kept." was the first sentence a new user read — and it was
        // also on the notification primer, which is drawn from this same
        // function during the first run. The tests covered 0, 41 and 91.
        return "\(ForgeCount.spelled(daysKept)) \(daysKept == 1 ? "day" : "days") kept."
    }

    /// "First: Work out, 18:00." — or just the name, when the day carries no
    /// clock, or when the clock would only repeat the minute it arrived at.
    /// Internal, not private: the primer draws this same line.
    static func opening(
        first: ScheduledActivity?,
        firstTimed: ScheduledActivity?,
        at minute: Int
    ) -> String {
        guard let first else { return "Keep your word to yourself." }
        guard let firstTimed, let start = firstTimed.startMinute, start != minute else {
            return "First: \(first.name)."
        }
        return "First: \(firstTimed.name), \(ClockMinute.label(start))."
    }

    // MARK: The one follow-up

    /// One activity, once, and only ever about today.
    ///
    /// # Why there is exactly one
    ///
    /// Because the alternative is a phone that buzzes at every activity twice.
    /// The plan carries a single follow-up, for the earliest thing today that is
    /// not done yet, and it is re-decided from scratch every time anything
    /// happens — the app opening, an activity being ticked, the day turning
    /// over. Finish the thing and the follow-up is cancelled before it lands;
    /// finish nothing and exactly one arrives.
    ///
    /// # Why it can be scheduled before the activity is late
    ///
    /// Nothing runs while the phone is in a pocket, so a notification about
    /// 18:00 has to be registered well before 18:30. That is safe here because
    /// an activity can only be completed *inside* Forge, and every completion
    /// re-runs this — so the follow-up is cancelled by the only event that could
    /// make it untrue. It is worded to be true either way: something still
    /// waiting is a fact, not an accusation.
    private static func missed(for state: ForgeNotificationState) -> PlannedNotification? {
        // A day already earned has nothing outstanding worth mentioning.
        guard !state.isTodayEarned else { return nil }

        let midnight = state.currentDay.startOfDay(in: state.calendar)
        for activity in state.activities(on: state.currentDay.weekday) {
            guard let start = activity.startMinute else { continue }
            guard !state.completedIDs.contains(activity.id) else { continue }
            // After the thing should have been over, never during it.
            let due = start + max(activity.minutes, missedGrace)
            guard let at = state.calendar.date(byAdding: .minute, value: due, to: midnight),
                  at > state.now
            else { continue }

            return PlannedNotification(
                kind: .missed,
                key: activity.id,
                when: .once(at),
                title: activity.name,
                body: waiting(
                    state.identity(of: activity),
                    done: state.completedToday,
                    planned: state.plannedToday
                )
            )
        }
        return nil
    }

    // MARK: Evening

    /// A day that was started and never closed.
    ///
    /// "Partially completed" and "at least one activity is complete" are the
    /// same condition once the blade is accounted for: something done and no
    /// blade out is unfinished whether that is one of three or three of three.
    /// The three-of-three case is the most worth saying — one drag away — so it
    /// is not excluded, it gets its own sentence.
    private static func evening(for state: ForgeNotificationState) -> PlannedNotification? {
        guard state.completedToday > 0, !state.isTodayEarned else { return nil }

        // Anchored to the day's own date rather than to the clock's, and
        // only ever today: the evening of a day that is already over is
        // nothing, and tomorrow evening is not what this notification means.
        let midnight = state.currentDay.startOfDay(in: state.calendar)
        guard let at = state.calendar.date(
            bySettingHour: eveningHour, minute: 0, second: 0, of: midnight
        ), at > state.now else { return nil }

        return PlannedNotification(
            kind: .evening,
            key: "today",
            when: .once(at),
            title: eveningTitle(for: state),
            body: eveningBody(for: state)
        )
    }

    /// The state of the day, as the headline.
    ///
    /// It was the word "Your day" on every evening of every day, with the count
    /// buried in the body — so the one glance somebody gives a Lock Screen at
    /// eight in the evening bought them the app's name for its own feature. The
    /// count is the news; it goes first.
    private static func eveningTitle(for state: ForgeNotificationState) -> String {
        guard state.completedToday < state.plannedToday else {
            return "Everything is done."
        }
        return "\(state.completedToday) of \(state.plannedToday) done."
    }

    /// What is left, named.
    ///
    /// No "still", no "you can catch up", nothing that reads as a deadline being
    /// missed — a day left at two of five is a fact, and the sentence is over
    /// once it has said so. What it adds is the **name of the next thing**,
    /// because "three left" is a number without an object and the one question
    /// somebody has at that hour is which three.
    private static func eveningBody(for state: ForgeNotificationState) -> String {
        guard state.completedToday < state.plannedToday else {
            return "The blade is loose. It still has to be pulled."
        }
        guard let next = state.activities(on: state.currentDay.weekday)
            .first(where: { !state.completedIDs.contains($0.id) })
        else {
            return "There is still an evening in it."
        }
        return "\(next.name) is still open."
    }

    // MARK: What they say

    /// The line under an activity at the hour it was put on the day.
    ///
    /// **"Evidence for someone who trains" rather than "Time to begin."** The
    /// second is an alarm; the first is the only thing in the app that says out
    /// loud, at the moment of doing it, what the twenty minutes are actually
    /// for. That connection is the entire product and it was being made nowhere
    /// outside a settings screen.
    ///
    /// Their sentence, unadorned and lower-cased into the middle of Forge's. No
    /// exhortation is added to it — "Be someone who trains" would be the app
    /// telling somebody who to be, and they already said.
    static func begin(_ identity: String?, minutes: Int = 0) -> String {
        if let identity, !identity.isEmpty { return "Evidence for \(identity.lowercasedFirst)." }
        // How long it takes, where the user has said. "Twenty minutes" is the
        // single most useful thing a phone can put in front of somebody who is
        // deciding whether to start now or later, and it is a number they set
        // themselves — the app is quoting them, not estimating.
        guard let length = ClockMinute.duration(minutes) else { return "It is on today's list." }
        return "\(length). Then it is behind you."
    }

    /// The one follow-up, worded to be true either way.
    ///
    /// "Still on today's list" is a fact about a list. "Keep the promise you
    /// made to yourself" — which this replaces — is a sentence about somebody's
    /// character, delivered by a phone, about a workout they may have skipped
    /// for an excellent reason.
    static func waiting(_ identity: String?, done: Int, planned: Int) -> String {
        if let identity, !identity.isEmpty {
            return "Still on today's list. Evidence for \(identity.lowercasedFirst)."
        }
        // Where the day has got to, which is the thing this sentence was
        // missing. It is honest at the moment it is sent because the whole plan
        // is rebuilt on every completion — the follow-up is cancelled and
        // rewritten by the only event that could change the number in it.
        guard done > 0, planned > 0 else { return "Still on today's list." }
        return "Still on today's list. \(done) of \(planned) done."
    }

    // MARK: The week

    /// The review, once a week, forever.
    ///
    /// A single `weekly` request rather than one scheduled each Sunday, so it
    /// keeps arriving through a month of the app never being opened — which is
    /// exactly the month somebody most needs to be asked.
    ///
    /// Nil when there is no review weekday, which is how "off" is expressed:
    /// the caller passes nil for somebody with nothing to review yet, and the
    /// whole request disappears from the plan rather than being scheduled and
    /// suppressed. Nothing here checks whether last week's was answered — a
    /// notification that stops arriving because somebody skipped one is a
    /// punishment, and the review is an offer.
    static func review(for state: ForgeNotificationState) -> PlannedNotification? {
        guard let weekday = state.reviewWeekday, (1...7).contains(weekday) else { return nil }
        return PlannedNotification(
            kind: .review,
            key: "week",
            when: .weekly(weekday: weekday, hour: ReviewStore.hour, minute: 0),
            title: "The week",
            // Names the cost, because the cost is the reason people do it. "Take
            // a moment to reflect on your week" is a request for an unbounded
            // amount of time from somebody on a sofa.
            body: "Ninety seconds, when you have them."
        )
    }

    // MARK: Clock

    /// A minute of a weekday, as a repeat the system can hold on its own.
    ///
    /// An activity that happens every day becomes **one** daily request rather
    /// than seven weekly ones. That is not tidiness — it is the difference
    /// between a full week costing seven of the sixty-odd requests iOS will hold
    /// and costing one, and it is why the cap above never binds in practice.
    private static func at(
        _ minute: Int,
        on weekday: Int,
        for state: ForgeNotificationState
    ) -> PlannedNotification.When {
        let clamped = ((minute % 1440) + 1440) % 1440
        let hour = clamped / 60
        let past = clamped % 60
        guard isEveryDay(weekday, for: state) else {
            return .weekly(weekday: weekday, hour: hour, minute: past)
        }
        return .daily(hour: hour, minute: past)
    }

    /// One weekday standing for all seven, when every day of the week holds
    /// exactly the same day — and nil when they do not.
    ///
    /// Compared by what each day actually holds rather than by the repeat rules
    /// of the activities on it, so a week somebody built out of seven separate
    /// one-day activities collapses too, and a week with one thing on Tuesday
    /// does not.
    private static func uniformWeekday(for state: ForgeNotificationState) -> Int? {
        let monday = state.activities(on: 2).map(\.id)
        guard !monday.isEmpty else { return nil }
        return (1...7).allSatisfy { state.activities(on: $0).map(\.id) == monday } ? 2 : nil
    }

    private static func isEveryDay(_ weekday: Int, for state: ForgeNotificationState) -> Bool {
        uniformWeekday(for: state) != nil
    }
}

extension PlannedNotification.When {
    /// The minute of the day this lands on, for a repeat. Nil for a one-shot,
    /// whose instant is a date rather than a time of day.
    var minuteOfDay: Int? {
        switch self {
        case .daily(let hour, let minute): hour * 60 + minute
        case .weekly(_, let hour, let minute): hour * 60 + minute
        case .once: nil
        }
    }
}

// MARK: - The scheduler

/// The only thing in Forge that talks to the notification centre.
///
/// A singleton, unlike everything else in the app, because the centre needs its
/// delegate before any view exists: a tap that launches Forge from cold is
/// delivered while the app is still starting, and a view that has not been made
/// yet cannot catch it.
///
/// It holds the two settings and nothing about the day. State arrives on every
/// call, so this class has no way to form a second opinion about what has been
/// done — the same reason `ProgressStore` banks no totals.
@MainActor
@Observable
final class ForgeNotifications: NSObject, UNUserNotificationCenterDelegate {

    static let shared = ForgeNotifications()

    // MARK: Settings
    //
    // Two, and there is deliberately no third: no per-notification switches, no
    // quiet hours, no second time picker. Every one of those would be a way to
    // make the wrong thing happen quietly.

    /// The master switch. Off until somebody says otherwise, so nothing is
    /// scheduled and nothing is asked before the offer at the end of the first
    /// run.
    var isEnabled: Bool = false { didSet { persist() } }

    /// Minutes past midnight.
    var wakeMinutes: Int = 6 * 60 + 30 { didSet { persist() } }

    /// Whether the one offer has been made.
    ///
    /// The whole of "never ask again". Nothing in the app raises a permission
    /// prompt on its own initiative twice, and this is how it knows it has had
    /// its turn — whether the answer was yes, no, or the system's own refusal.
    private(set) var hasAsked: Bool = false

    /// Last read from the system.
    ///
    /// iOS is the authority and the user can change their mind in Settings
    /// without telling us, so this is re-read on every refresh rather than
    /// remembered from the answer to the prompt.
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    /// The notification the user just tapped, waiting for somebody to act on it.
    /// Cleared by whoever does.
    var opened: ForgeNotification?

    private let defaults: UserDefaults
    /// Suppresses the `didSet` writes that loading would otherwise trigger.
    private var isLoaded = false

    private var center: UNUserNotificationCenter { .current() }

    private enum Key {
        static let enabled = "forge.notifications.enabled.v1"
        static let wake = "forge.notifications.wake.v1"
        static let asked = "forge.notifications.asked.v1"
    }

    private init(defaults: UserDefaults = ForgeShared.defaults) {
        self.defaults = defaults
        super.init()
        load()
    }

    // MARK: Storage

    private func load() {
        defer { isLoaded = true }
        isEnabled = defaults.bool(forKey: Key.enabled)
        if defaults.object(forKey: Key.wake) != nil {
            wakeMinutes = defaults.integer(forKey: Key.wake)
        }
        hasAsked = defaults.bool(forKey: Key.asked)
    }

    private func persist() {
        guard isLoaded else { return }
        defaults.set(isEnabled, forKey: Key.enabled)
        defaults.set(wakeMinutes, forKey: Key.wake)
        defaults.set(hasAsked, forKey: Key.asked)
    }

    // MARK: Reading

    /// The wake time as an instant, for the native picker. Only the hour and the
    /// minute survive the round trip, which is all the picker shows.
    var wakeTime: Date {
        get {
            Calendar.current.date(
                bySettingHour: wakeMinutes / 60,
                minute: wakeMinutes % 60,
                second: 0,
                of: Date()
            ) ?? Date()
        }
        set {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            wakeMinutes = (parts.hour ?? 6) * 60 + (parts.minute ?? 30)
        }
    }

    /// The system has been told no.
    ///
    /// Nothing can be delivered while this is true, whatever the switch says, so
    /// Settings shows the switch off and hands the decision back to iOS rather
    /// than pretending it is still ours to make. Forge still never asks again.
    var isBlocked: Bool { authorization == .denied }

    // MARK: Scheduling

    /// Put the notification centre in step with the day.
    ///
    /// The single entry point, called on launch, on every return to the
    /// foreground, when the wake time changes, when the day turns over and
    /// whenever today's completion state moves. Every one of those runs with
    /// Forge open in front of somebody, which is what marks today as engaged —
    /// and therefore what makes it impossible for opening Forge from a
    /// notification to schedule another one for the same day.
    func refresh(for state: ForgeNotificationState) async {
        await readAuthorization()

        guard isEnabled else {
            await cancelAll()
            return
        }
        // Only ever after the offer has been made, so a prompt cannot appear at
        // launch or during onboarding. Reached when somebody who turned the
        // offer down later turns the switch on themselves, which is a request
        // rather than a question.
        if authorization == .notDetermined, hasAsked {
            await requestAuthorization()
        }
        guard authorization == .authorized else {
            await cancelAll()
            return
        }

        await apply(ForgeNotificationPlan.make(for: state))
    }

    /// Obsolete before new, always. Everything Forge has pending goes, and only
    /// what the schedule justifies comes back.
    ///
    /// This is the whole answer to staleness. There is no code anywhere that
    /// adjusts one pending request when an activity moves, because there is no
    /// such code to get wrong: changing a time, moving a day, deleting an
    /// activity, copying a day onto another and changing a repeat rule all end
    /// in the same place, which is this function throwing the lot away and
    /// asking the plan what the week looks like now.
    private func apply(_ plan: [PlannedNotification]) async {
        await cancelAll()
        for planned in plan {
            try? await center.add(request(for: planned))
        }
    }

    /// Everything, by sweep — except the trial reminder.
    ///
    /// A sweep rather than a list of identifiers, because the list is not
    /// knowable: an earlier build of Forge registered three fixed identifiers
    /// that this one has never heard of, and a phone that upgraded mid-week is
    /// holding them. Anything Forge scheduled and no longer plans to, whatever
    /// version wrote it, goes here.
    ///
    /// **The trial reminder is the one thing it leaves.** It is not part of the
    /// day's plan, it is not behind the day's switch, and it has its own owner
    /// (`syncTrialReminder`) — sweeping it away every time an activity moved
    /// would break the promise the paywall made.
    private func cancelAll() async {
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let swept = pending.filter { ForgeNotification(identifier: $0) != .trial }
        center.removePendingNotificationRequests(withIdentifiers: swept)
    }

    // MARK: The trial reminder

    /// The one identifier the reminder ever has, so scheduling it again replaces
    /// it rather than adding a second.
    nonisolated static let trialReminderIdentifier = ForgeNotification.trial.identifier("end")

    /// Put the reminder where `TrialReminder.fireDate` says, or take it away.
    ///
    /// Called by `ContentView` whenever the answer could have changed — the
    /// trial starting, ending, being cancelled or converting, or permission
    /// being given — and never decides anything itself.
    func syncTrialReminder(at date: Date?) async {
        await readAuthorization()
        center.removePendingNotificationRequests(withIdentifiers: [Self.trialReminderIdentifier])
        guard let date, authorization == .authorized || authorization == .provisional else { return }
        let planned = PlannedNotification(
            kind: .trial, key: "end", when: .once(date), title: "", body: TrialReminder.body
        )
        try? await center.add(request(for: planned))
    }

    /// The free week has started with "Remind me before the trial ends" on.
    ///
    /// The person asked for a reminder, so iOS is asked — once, and only if it
    /// never has been. A refusal is final, the same as everywhere else in
    /// Forge; nothing here touches the day's own switch.
    func allowTrialReminder() async {
        await readAuthorization()
        guard authorization == .notDetermined else { return }
        await requestAuthorization()
    }

    private func request(for planned: PlannedNotification) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = planned.title
        content.body = planned.body
        // The two that land at a time the user chose are allowed to make a
        // sound. The follow-up and the evening are things Forge noticed rather
        // than appointments, and they should be waiting when the phone is next
        // picked up rather than announce themselves.
        // The review is silent for the same reason the follow-up is: it is an
        // offer waiting to be found rather than an appointment, and a phone that
        // chimes on a Sunday evening about reflection is a phone somebody turns
        // notifications off on.
        // The trial reminder was asked for by name, so it may be heard.
        content.sound = switch planned.kind {
        case .morning, .activity, .trial: .default
        case .missed, .evening, .review: nil
        }

        let trigger: UNCalendarNotificationTrigger
        switch planned.when {
        case .daily(let hour, let minute):
            trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: hour, minute: minute),
                repeats: true
            )
        case .weekly(let weekday, let hour, let minute):
            // The activity model *is* a set of weekdays, so one repeating
            // request per weekday is a direct translation of it — no horizon to
            // roll forward, and nothing that quietly runs out if the app is not
            // opened for a month.
            trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: hour, minute: minute, weekday: weekday),
                repeats: true
            )
        case .once(let instant):
            // Calendar rather than a time interval, so a phone that spends the
            // night asleep still fires it at the time on the clock.
            trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: instant
                ),
                repeats: false
            )
        }

        return UNNotificationRequest(
            identifier: planned.identifier,
            content: content,
            trigger: trigger
        )
    }

    // MARK: Permission

    /// The one time Forge ever asks.
    ///
    /// Called from the closing beat of the first run and from nowhere else. By
    /// then the user has pulled a blade, so a reminder is something they
    /// understand rather than something an unknown app wants. A refusal is
    /// answered once and never revisited.
    @discardableResult
    func offerReminders() async -> Bool {
        hasAsked = true
        persist()
        let granted = await requestAuthorization()
        isEnabled = granted
        return granted
    }

    /// The offer was turned down without the system ever being asked. Nothing
    /// mentions it again.
    func declineReminders() {
        hasAsked = true
        isEnabled = false
        persist()
    }

    @discardableResult
    private func requestAuthorization() async -> Bool {
        // Two options, and only the two that are used. Forge never sets a badge
        // and should not be asking for permission to.
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        await readAuthorization()
        return granted
    }

    private func readAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    // MARK: - Opening from a notification

    /// Claim the centre's delegate. Called from `ForgeApp.init`, because a cold
    /// launch delivers the tap before there is a view to hand it to.
    ///
    /// `nonisolated` so it can be called from wherever the app happens to start;
    /// assigning a delegate is the whole of it.
    nonisolated func register() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// A notification was tapped.
    ///
    /// The hop to the main actor is one assignment: landing the user in the
    /// right place is the job of the view that owns the tab, and it is watching
    /// `opened`.
    ///
    /// `willPresent` is deliberately not implemented. Without it the system
    /// shows nothing while Forge is in the foreground, which is exactly the rule
    /// that somebody already looking at the app does not need reminding.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let kind = ForgeNotification(identifier: response.notification.request.identifier)
        Task { @MainActor in opened = kind }
        completionHandler()
    }

    // MARK: - Debug

    #if DEBUG
    /// What is actually pending, read back out of the system.
    ///
    /// The only honest way to check that cancelling worked: anything the app
    /// says about its own pending notifications is a guess.
    func pendingDescriptions() async -> [String] {
        let format = DateFormatter()
        format.dateFormat = "EEE d MMM HH:mm"

        return await center.pendingNotificationRequests().compactMap { request in
            guard let kind = ForgeNotification(identifier: request.identifier) else { return nil }
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger else {
                return kind.rawValue
            }
            let when = trigger.nextTriggerDate().map(format.string(from:)) ?? "never"
            // Weekly and daily are both `repeats`, and the difference between
            // them is the whole of how a repeat rule is expressed — a readout
            // that called them all daily would hide the one thing worth
            // checking here.
            let repeating = trigger.repeats
                ? (trigger.dateComponents.weekday == nil ? " · daily" : " · weekly")
                : ""
            return "\(kind.rawValue) · \(when)\(repeating)"
        }
    }
    #endif
}

// MARK: -

private extension String {
    /// The sentence, lower-cased only at its first letter.
    ///
    /// `lowercased()` on the whole string would flatten a name somebody put in
    /// their own statement — "Someone who shows up for Maya" is not "someone who
    /// shows up for maya", and mangling a child's name in a notification is
    /// exactly the kind of small carelessness that makes an app feel automated.
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}

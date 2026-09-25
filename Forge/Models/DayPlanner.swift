import Foundation

/// What Forge would change about somebody's week, and why it thinks so.
///
/// # What this is, and what it deliberately is not
///
/// It is not a model, it does not pretend to be one, and it is not the empty
/// text field that used to sit behind the sparkle. It is a small number of
/// **moves** — each one a real `SchedulePlan`, reviewable line by line and
/// applied by the same `ForgeViewModel.apply` every other plan goes through —
/// derived from things Forge already knows about a person and nobody else does:
///
/// - the week they actually keep (`ScheduledActivity`),
/// - which of the six parts each activity feeds (`RitualCategory`),
/// - the parts they *said* they wanted to build (`ForgeViewModel.focus`),
/// - the parts their record says are actually getting stronger (`ForgeShape`),
/// - and what has been asked for and not done lately (`habitCounts`).
///
/// The old screen asked a stranger to type a sentence, then answered "the model
/// is not connected" to most of what they typed. That is the worst version of
/// this feature: it puts the work on the user *and* fails. Everything here
/// arrives already computed, already specific, and already correct — "Ask for
/// Read three days instead of every day, because it is kept on four of the
/// eleven days it is asked for" is not a suggestion a template could produce,
/// and it needs no network to be true.
///
/// # Why every move states its arithmetic
///
/// Because the register of this app does not allow it to be mysterious. A card
/// that says "we recommend adding Call someone" is an app with an opinion; a
/// card that says "Relationship is the lowest of your six at 18, and it is one
/// of the three you chose" is an app reading somebody their own record. The
/// second is checkable, and being checkable is the whole difference — the same
/// rule `ReviewObservation` follows, and for the same reason.
///
/// # The seam a model plugs into
///
/// This produces the same `SchedulePlan` a model would, so nothing downstream
/// knows or cares which wrote one. When a model is connected, the honest
/// division of labour is: this keeps deciding *what is worth changing*, because
/// it can see the record; the model widens *what a person can ask for in their
/// own words*, which is the one thing arithmetic genuinely cannot do. Both go
/// through the same review screen and the same `isModelWritten` flag.
enum DayPlanner {

    // MARK: - What it is given

    /// Everything a move is allowed to read, taken once.
    ///
    /// A value rather than the stores it came from, for the reason `AIBrief` is
    /// one: the whole of this file has to be checkable without a view model, a
    /// history store or a `UserDefaults` suite anywhere near it, and a pure
    /// function of a value is the only shape that gets you that.
    struct Facts: Equatable, Sendable {
        /// The week as it stands.
        var activities: [ScheduledActivity] = []
        /// Which dimension each of those feeds. Primary filing only — the
        /// secondary weights matter to the Shape's arithmetic and would only
        /// blur a recommendation.
        var categories: [String: RitualCategory] = [:]
        /// The six, read off the record. Nil before there is enough to read.
        var shape: ForgeShape?
        /// What they said they wanted to build. Empty is ordinary.
        var focus: Set<RitualCategory> = []
        /// Days set aside in Settings. Nothing is ever *moved onto* one.
        var restWeekdays: Set<Int> = []
        /// When the phone is set to wake them.
        var wakeMinutes: Int?
        /// Asked and kept per activity over the last four weeks.
        var recent: [Habit] = []
        /// Ids of library activities not currently in the week, in effort order
        /// — what a move is allowed to recommend taking up.
        var available: [Available] = []

        struct Habit: Equatable, Sendable {
            let id: String
            let planned: Int
            let completed: Int
            var rate: Double { planned > 0 ? Double(completed) / Double(planned) : 0 }
        }

        struct Available: Equatable, Sendable {
            let id: String
            let name: String
            let minutes: Int
            let category: RitualCategory
        }
    }

    // MARK: - What it produces

    /// One move Forge would make, and the sentence that justifies it.
    struct Move: Identifiable, Equatable, Sendable {

        /// What kind of move it is. Decides the glyph and the order they are
        /// offered in, and nothing else — the copy is always written from the
        /// facts rather than from the case.
        enum Kind: String, Equatable, Sendable, CaseIterable {
            /// Two things booked at the same time, or something before waking.
            case untangle
            /// Activities with no hour on them.
            case order
            /// A part of them that is getting nothing.
            case strengthen
            /// Something asked for far more often than it is kept.
            case ease
            /// One day carrying most of the week.
            case balance

            var symbol: String {
                switch self {
                case .untangle: "arrow.triangle.branch"
                case .order: "clock.badge.checkmark"
                case .strengthen: "chart.line.uptrend.xyaxis"
                case .ease: "arrow.down.right.circle"
                case .balance: "scalemass"
                }
            }
        }

        let kind: Kind
        /// What it would do, as an instruction. Never a question.
        let title: String
        /// Why, in the user's own numbers. This is the load-bearing half.
        let reason: String
        let plan: SchedulePlan

        var id: String { kind.rawValue }
    }

    /// Every move worth offering, best first.
    ///
    /// **Nothing is invented to fill the screen.** A week with no clash, no
    /// untimed activity, a level shape and nothing slipping produces an empty
    /// array, and the screen says so — an app that always has advice is an app
    /// whose advice means nothing.
    static func moves(_ facts: Facts) -> [Move] {
        [untangle(facts), order(facts), strengthen(facts), ease(facts), balance(facts)]
            .compactMap { $0 }
    }

    // MARK: - 1. Two things at once

    /// Something booked over something else, or before the day starts.
    ///
    /// First, because it is the only move here that fixes something that is
    /// actually *wrong* rather than something that could be better. A week with
    /// a double booking in it is a week somebody will not follow, and no amount
    /// of balancing matters until it is gone.
    static func untangle(_ facts: Facts) -> Move? {
        var changes: [ScheduleChange] = []
        var reasons: [String] = []

        // Before waking. Checked first because it is the more surprising of the
        // two — an activity at 06:00 for somebody who gets up at 07:30 was
        // almost always set once and then forgotten about.
        if let wake = facts.wakeMinutes {
            for activity in facts.activities {
                guard let start = activity.startMinute, start < wake else { continue }
                let moved = Slotting.round(wake + 15)
                changes.append(
                    .time(id: activity.id, name: activity.name, minute: moved, was: start)
                )
                reasons.append(
                    "\(activity.name) starts at \(ClockMinute.label(start)), before your day opens at \(ClockMinute.label(wake))."
                )
            }
        }

        // Overlaps, one weekday at a time. Two activities that share no weekday
        // cannot collide however close their clock times are, which is exactly
        // the kind of false positive that makes a warning screen worth
        // dismissing unread.
        let moving = Set(changes.map(\.id))
        for weekday in Weekdays.all {
            let onDay = facts.activities
                .filter { $0.happens(on: weekday) && $0.startMinute != nil }
                .filter { !moving.contains("time.\($0.id)") }
                .sorted { ($0.startMinute ?? 0) < ($1.startMinute ?? 0) }

            for (first, second) in zip(onDay, onDay.dropFirst()) {
                guard let firstStart = first.startMinute,
                      let secondStart = second.startMinute,
                      firstStart + first.reserved > secondStart
                else { continue }
                guard !changes.contains(where: { $0.id == "time.\(second.id)" }) else { continue }
                let moved = Slotting.round(firstStart + first.reserved + Slotting.gap)
                changes.append(
                    .time(id: second.id, name: second.name, minute: moved, was: secondStart)
                )
                reasons.append(
                    "\(second.name) starts while \(first.name) is still running on \(Weekdays.name(weekday))."
                )
            }
        }

        guard !changes.isEmpty else { return nil }
        return Move(
            kind: .untangle,
            title: changes.count == 1 ? "Untangle one clash" : "Untangle \(changes.count) clashes",
            // At most two reasons. A list of six is a bug report, and the
            // changes underneath already name every one of them.
            reason: reasons.prefix(2).joined(separator: " "),
            plan: SchedulePlan(
                summary: changes.count == 1
                    ? "One thing moves. Nothing else about your week changes."
                    : "\(changes.count) things move. Nothing else about your week changes.",
                changes: changes
            )
        )
    }

    // MARK: - 2. An hour for everything

    /// Give the untimed activities a place in the day.
    ///
    /// The arithmetic is `LocalForgeAI.layOut`, reused rather than rewritten —
    /// it already does the part that is hard to get right (keeping a good hour
    /// alone, stepping over what is already booked, rounding to the fives so a
    /// generated day does not read as generated), and a second implementation
    /// here would be a second opinion about where somebody's morning goes.
    static func order(_ facts: Facts) -> Move? {
        let untimed = facts.activities.filter { $0.startMinute == nil }
        guard untimed.count >= 2 else { return nil }

        var brief = AIBrief()
        brief.activities = facts.activities
        brief.wakeMinutes = facts.wakeMinutes
        guard let plan = try? LocalForgeAI.layOut(brief: brief, request: "", busy: nil),
              !plan.isEmpty
        else { return nil }

        let opening = facts.wakeMinutes.map(ClockMinute.label) ?? "the morning"
        return Move(
            kind: .order,
            title: "Give your week an order",
            reason: "\(ForgeCount.spelled(untimed.count).capitalizedFirst) of your activities have no hour on them. Forge places them from \(opening), around the ones you have already set, and leaves those alone.",
            plan: SchedulePlan(summary: plan.summary, changes: plan.changes)
        )
    }

    // MARK: - 3. The part that is getting nothing

    /// Put something concrete into the weakest part of somebody's life.
    ///
    /// **This is the move the feature exists for**, and the decision it makes is
    /// the one no template could. In order:
    ///
    /// 1. If they said what they wanted to build, the target is the weakest of
    ///    *those*, whether or not it is the weakest overall. Somebody who chose
    ///    Relationship and Physical does not want to be told about Discipline,
    ///    however low it is — they did not ask for Discipline.
    /// 2. Otherwise it is a dimension nothing is filed under, which is a whole
    ///    part of a life the practice does not touch.
    /// 3. Otherwise it is the weakest measured one, and only when it is
    ///    genuinely behind — see `ForgeShape.needsAttention`, which refuses to
    ///    name a weakest link on a level shape.
    ///
    /// What it proposes is the **smallest** thing in that dimension the library
    /// has and they do not already keep, on the two lightest non-rest days. Not
    /// the most impressive thing: somebody who is weak in an area is the last
    /// person who should be handed the hardest activity in it.
    static func strengthen(_ facts: Facts) -> Move? {
        guard let target = weakest(facts) else { return nil }
        guard let option = facts.available.first(where: { $0.category == target.category })
        else { return nil }

        let days = lightestDays(facts, count: target.isUntouched ? 2 : 3)
        guard !days.isEmpty else { return nil }
        let hour = Slotting.hour(for: option.category, facts: facts)

        return Move(
            kind: .strengthen,
            // The activity's own name, in its own case **and in quotation
            // marks**. Lowercasing it read as a broken sentence the moment the
            // library grew labels that are themselves sentences ("Put say the
            // thing into your week"); leaving it bare broke the other way, on
            // every label that opens with a verb — "Add Set tomorrow's one
            // thing to your week", which is what shipped. Quoting it makes the
            // name a noun whatever is inside it, which is the only version that
            // is right for all fifty-two.
            title: "Add \u{201C}\(option.name)\u{201D} to your week",
            reason: target.reason,
            plan: SchedulePlan(
                summary: "\(option.name), \(RitualRepeat(weekdays: days).label.lowercased()). Nothing you already keep is touched.",
                changes: [
                    .adopt(
                        id: option.id, name: option.name, minutes: option.minutes,
                        weekdays: days, minute: hour
                    )
                ]
            )
        )
    }

    /// The dimension to aim at, and the sentence that says why.
    private static func weakest(_ facts: Facts) -> (category: RitualCategory, reason: String, isUntouched: Bool)? {
        guard let shape = facts.shape else {
            // No shape yet. A chosen dimension with nothing filed under it is
            // still a fact, and it is the only thing that can honestly be said
            // in somebody's first fortnight.
            guard let chosen = facts.focus.first(where: { category in
                !facts.activities.contains { facts.categories[$0.id] == category }
            }) else { return nil }
            return (
                chosen,
                "You said \(chosen.label.lowercased()) mattered, and nothing in your week is filed under it yet. \(chosen.meaning)",
                true
            )
        }

        let byCategory = Dictionary(uniqueKeysWithValues: shape.dimensions.map { ($0.category, $0) })

        // 1. The weakest of the ones they chose.
        if !facts.focus.isEmpty {
            let chosen = shape.dimensions.filter { facts.focus.contains($0.category) }
            if let weakest = chosen.min(by: { $0.score < $1.score }),
               let best = shape.dimensions.filter(\.isMeasured).max(by: { $0.score < $1.score }),
               weakest.category != best.category,
               // Only when there is a real gap. Naming the lowest of three
               // scores that are all within noise of each other is the app
               // manufacturing a problem — the same bar `needsAttention` sets.
               best.score - weakest.score >= 15 || !weakest.hasActivities
            {
                let reason: String
                if !weakest.hasActivities {
                    reason = "You chose \(weakest.category.label.lowercased()), and nothing in your week is filed under it. \(weakest.category.meaning)"
                } else {
                    reason = "You chose \(weakest.category.label.lowercased()). It reads \(weakest.score) against \(best.category.label.lowercased()) at \(best.score), over the last four weeks."
                }
                return (weakest.category, reason, !weakest.hasActivities)
            }
        }

        // 2. A whole part nothing points at.
        if let untouched = shape.untouched, let dimension = byCategory[untouched.category] {
            return (
                dimension.category,
                "Nothing in your week builds \(dimension.category.label.lowercased()). \(dimension.category.meaning)",
                true
            )
        }

        // 3. The weakest measured one, and only when it is properly behind.
        if let weak = shape.needsAttention,
           let best = shape.dimensions.filter(\.isMeasured).max(by: { $0.score < $1.score }) {
            return (
                weak.category,
                "\(weak.category.label) reads \(weak.score) against \(best.category.label.lowercased()) at \(best.score), over the last four weeks.",
                false
            )
        }
        return nil
    }

    // MARK: - 4. What keeps slipping

    /// Ask for less of the thing that is not being kept.
    ///
    /// The counter-intuitive move, and the one that most makes this feel like
    /// something read a record rather than something ran a template. Every other
    /// app in this category responds to a missed habit by asking for it harder.
    /// A thing planned eleven times and done four is not a discipline problem,
    /// it is a **frequency that was set optimistically** — and the honest fix is
    /// to ask for it three days and keep all three, which is more evidence than
    /// seven days and four.
    ///
    /// It only ever proposes reducing to three spread days, and only for
    /// something currently asked for on four days or more, so it can never talk
    /// somebody down to nothing.
    static func ease(_ facts: Facts) -> Move? {
        let candidates = facts.recent
            .filter { $0.planned >= 6 && $0.rate < 0.5 }
            .sorted { $0.rate < $1.rate }

        for habit in candidates {
            guard let activity = facts.activities.first(where: { $0.id == habit.id }) else { continue }
            let currently = activity.weekdays.isEmpty ? 7 : activity.weekdays.count
            guard currently >= 4 else { continue }

            let days = LocalForgeAI.spread(3)
            guard days != activity.weekdays else { continue }

            return Move(
                kind: .ease,
                title: "\(activity.name), three days instead of \(currently == 7 ? "every day" : ForgeCount.spelled(currently).lowercased())",
                reason: "It was kept on \(habit.completed) of the \(habit.planned) days it was asked for in the last four weeks. Three days you keep is more evidence than \(currently == 7 ? "seven" : ForgeCount.spelled(currently)) you do not.",
                plan: SchedulePlan(
                    summary: "\(activity.name) moves to \(RitualRepeat(weekdays: days).label.lowercased()). Nothing is removed.",
                    changes: [
                        .days(
                            id: activity.id, name: activity.name,
                            weekdays: days, was: activity.weekdays
                        )
                    ]
                )
            )
        }
        return nil
    }

    // MARK: - 5. One day carrying the week

    /// Move one thing off the heaviest day onto the lightest.
    ///
    /// Deliberately **one** thing. A planner that rebalances a whole week in a
    /// single tap is a planner that hands somebody back a week they no longer
    /// recognise, and the only honest way to offer that is one change at a time,
    /// each of which is obviously reversible.
    ///
    /// Rest days are never a destination. Somebody who set Sunday aside did not
    /// set it aside so that Forge could put a run on it.
    static func balance(_ facts: Facts) -> Move? {
        let load = Weekdays.all.reduce(into: [Int: Int]()) { total, weekday in
            total[weekday] = facts.activities
                .filter { $0.happens(on: weekday) }
                .reduce(0) { $0 + max($1.minutes, 10) }
        }
        guard let heaviest = load.max(by: { $0.value < $1.value })?.key,
              let lightest = load
                .filter({ !facts.restWeekdays.contains($0.key) })
                .min(by: { $0.value < $1.value })?.key,
              heaviest != lightest,
              (load[heaviest] ?? 0) - (load[lightest] ?? 0) >= 45
        else { return nil }

        // Only something that is already on particular days. Widening a daily
        // activity to "everything except Tuesday" is a much bigger edit than the
        // card describes, and nobody reading "move one thing" is agreeing to it.
        let movable = facts.activities
            .filter { !$0.weekdays.isEmpty }
            .filter { $0.weekdays.contains(heaviest) && !$0.weekdays.contains(lightest) }
            .max { $0.minutes < $1.minutes }
        guard let activity = movable else { return nil }

        var days = activity.weekdays
        days.remove(heaviest)
        days.insert(lightest)

        return Move(
            kind: .balance,
            title: "Move \(activity.name) to \(Weekdays.name(lightest))",
            reason: "\(Weekdays.name(heaviest)) asks for \(ClockMinute.duration(load[heaviest] ?? 0) ?? "more") and \(Weekdays.name(lightest)) asks for \(ClockMinute.duration(load[lightest] ?? 0) ?? "less").",
            plan: SchedulePlan(
                summary: "\(activity.name) moves from \(Weekdays.name(heaviest)) to \(Weekdays.name(lightest)).",
                changes: [
                    .days(id: activity.id, name: activity.name, weekdays: days, was: activity.weekdays)
                ]
            )
        )
    }

    // MARK: - Shared arithmetic

    /// The days with least on them, lightest first, never a rest day.
    private static func lightestDays(_ facts: Facts, count: Int) -> Set<Int> {
        let load = Weekdays.all
            .filter { !facts.restWeekdays.contains($0) }
            .map { weekday in
                (
                    weekday,
                    facts.activities.filter { $0.happens(on: weekday) }.count
                )
            }
        // Ties break by the week's own order rather than arbitrarily, so the
        // same week always produces the same proposal — a planner that suggests
        // Tuesday and then Thursday for the same input reads as a coin toss.
        let sorted = load.sorted { ($0.1, Weekdays.order($0.0)) < ($1.1, Weekdays.order($1.0)) }
        return Set(sorted.prefix(count).map(\.0))
    }

    /// Where in the day a dimension belongs, and it is a *default* rather than a
    /// claim. Everything here is one drag away from being changed, and the only
    /// job of these numbers is to be a plausible thing to be dragging away from.
    enum Slotting {
        static let gap = 15

        static func round(_ minute: Int) -> Int { (minute + 4) / 5 * 5 }

        static func hour(for category: RitualCategory, facts: Facts) -> Int {
            let wake = facts.wakeMinutes ?? 7 * 60
            switch category {
            // The body and the day's own discipline go early, because both are
            // things people stop doing once the day gets hold of them.
            case .physical, .discipline: return round(wake + 45)
            case .mental: return round(wake + 20)
            // The three that need other people, or a clear head, or both.
            case .relationship: return 18 * 60 + 30
            case .intellect: return 20 * 60
            case .ambition: return round(wake + 90)
            case .all: return round(wake + 60)
            }
        }
    }

    /// Monday first, matching every other week in the app.
    enum Weekdays {
        static let all = [2, 3, 4, 5, 6, 7, 1]

        static func order(_ weekday: Int) -> Int {
            all.firstIndex(of: weekday) ?? 7
        }

        static func name(_ weekday: Int) -> String {
            let symbols = Calendar.current.weekdaySymbols
            guard symbols.indices.contains(weekday - 1) else { return "" }
            return symbols[weekday - 1]
        }
    }
}

private extension ScheduledActivity {
    /// How long to reserve for it. Half an hour for anything that has never
    /// been given a length — the same number `LocalForgeAI` reserves, and
    /// deliberately: two planners disagreeing about how long an untimed
    /// activity takes would lay out the same week two different ways.
    var reserved: Int { minutes > 0 ? minutes : 30 }
}

private extension String {
    /// "three" → "Three". Only the first character, so "Push-ups" survives.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

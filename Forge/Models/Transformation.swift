import Foundation

// MARK: - The proposed plan

/// One activity on the first run's plan, the days it is proposed for, and the
/// hour.
///
/// One per dimension, which is why the dimension is the identity: the plan is
/// "something for each part you are building", and swapping a row swaps the
/// activity inside its dimension rather than adding a second one.
struct PlanEntry: Identifiable, Equatable, Sendable {
    let dimension: RitualCategory
    var ritualID: String
    /// Minutes since midnight.
    var minute: Int
    /// The days of the week, as the repeat picker writes them. See
    /// `OnboardingPlan.cadence(for:)` for what each activity is proposed on.
    var repeats: RitualRepeat = .daily

    var id: RitualCategory { dimension }

    /// The library activity, carrying this row's days and time — so the
    /// projection and the rows read the same arrangement the day is written
    /// with, rather than the library's every-day default.
    var ritual: Ritual? {
        guard var ritual = Ritual.find(ritualID) else { return nil }
        ritual.repeats = repeats
        ritual.startMinute = minute
        return ritual
    }

    func happens(on weekday: Int) -> Bool { repeats.includes(weekday) }

    /// "Mon · Wed · Fri · 18:00", "Daily · 21:30".
    var schedule: String {
        "\(repeats.compactLabel) \u{00B7} \(ClockMinute.label(minute))"
    }
}

/// What the first run proposes somebody actually does, before they have done
/// anything.
///
/// # What goes on it
///
/// **Three to six activities, one per dimension**: every dimension somebody
/// said they wanted to build, and then — if that is fewer than three — the
/// lowest of their baselines. Each is the first of that dimension's
/// `IdentityActivities.starters`, which are ordered by how much they *are* the
/// thing; the effort ladder still decides which of them the first run asks for
/// first (`ForgeViewModel.firstRunActivity`).
///
/// # When
///
/// Each gets **the days it would actually be kept on** — see `cadence(for:)` —
/// and a proposed hour, morning or evening by what it is — see
/// `isEvening(_:)` — laid out one after another so two activities never start
/// on top of each other and Plan's `untangle` has nothing to say on day one.
/// The days and the hour are proposals: the row is one tap from the repeat
/// picker and a time wheel.
///
/// This is the whole of an if-then plan, which is the second of the three
/// findings the first run cites: deciding *when* is most of what makes a thing
/// happen.
enum OnboardingPlan {

    static let minimum = 3
    static let maximum = 6

    /// Where the morning starts and the evening starts, before anybody has said
    /// when they get up. Both are proposals and both are one tap from changing.
    static let morningStart = 7 * 60
    static let eveningStart = 19 * 60

    /// Which dimensions the plan covers, in the order they are chosen: what
    /// somebody said they are building first, then the weakest baselines.
    static func dimensions(focus: Set<RitualCategory>, assessment: Assessment?) -> [RitualCategory] {
        var chosen = RitualCategory.dimensions.filter(focus.contains)
        let ranked = assessment?.ranked ?? RitualCategory.dimensions
        for dimension in ranked where chosen.count < minimum && !chosen.contains(dimension) {
            chosen.append(dimension)
        }
        return Array(chosen.prefix(maximum))
    }

    /// The first starter of a dimension that exists and is not already used.
    static func starter(for dimension: RitualCategory, avoiding used: Set<String> = []) -> Ritual? {
        alternatives(for: dimension).first { !used.contains($0.id) }
    }

    /// Everything a row can be swapped for: the dimension's starters, in their
    /// curated order.
    static func alternatives(for dimension: RitualCategory) -> [Ritual] {
        (IdentityActivities.starters[dimension] ?? []).compactMap(Ritual.find)
    }

    /// The plan, proposed.
    static func propose(focus: Set<RitualCategory>, assessment: Assessment?) -> [PlanEntry] {
        var used: Set<String> = []
        let rituals = dimensions(focus: focus, assessment: assessment).compactMap { dimension -> Ritual? in
            guard let ritual = starter(for: dimension, avoiding: used) else { return nil }
            used.insert(ritual.id)
            return ritual
        }
        let minutes = proposedMinutes(for: rituals)
        return rituals
            .map {
                PlanEntry(
                    dimension: $0.category, ritualID: $0.id,
                    minute: minutes[$0.id] ?? morningStart,
                    repeats: cadence(for: $0.id)
                )
            }
            .sorted { $0.minute < $1.minute }
    }

    // MARK: - How often

    /// The days an activity is proposed for.
    ///
    /// # Why the plan is no longer everything every day
    ///
    /// It was, and it was not a plan anybody keeps: nobody trains seven days a
    /// week, does deep work on a Sunday by default, or calls the same person
    /// every night. A plan that asks for those is abandoned in its first week
    /// by somebody who was told it was *the* plan. So each activity is proposed
    /// on the week it would actually be kept in:
    ///
    /// - **Training** — Monday, Wednesday, Friday. A body gets stronger on the
    ///   days between.
    /// - **Practice that is not daily** — learning, writing, explaining it out
    ///   loud, the craft — Tuesday, Thursday, Saturday, off the training days.
    /// - **The work block** — hardest thing first, deep work, study — weekdays.
    /// - **Time with people** — a call, twice a week, Wednesday and Sunday; a
    ///   meal or an hour without the phone, at weekends, when people are free.
    /// - **Once a week**, and only ever by a swap in the plan's editor — a
    ///   letter, helping someone, making the plan, the numbers, the avoided
    ///   message, asking for something, shipping — one day, the one it most
    ///   belongs to.
    /// - **Everything else** — the small things a day is made of, and reading —
    ///   every day. So is anything this table does not name.
    ///
    /// # Nothing proposed is less than twice a week
    ///
    /// The six first starters — the only activities a proposal is made of —
    /// are daily, weekdays, or twice a week. The Shape counts a dimension as
    /// fully present from eight days in twenty-eight (`ForgeShape.presenceFloor`,
    /// "roughly twice a week — the least that can honestly be called a part of
    /// somebody's life"), so a once-a-week call would cap Relationship at half
    /// of what it was kept at, and `BlendedShape`'s first weeks, which scale
    /// that floor, would read a lone kept call as more than the record later
    /// does: the projection read higher at seven days than at thirty.
    /// Proposed at twice a week, the plan is what the Shape can read in full.
    ///
    /// # Nothing new is stored
    ///
    /// These are `RitualRepeat` values, the weekday set every activity in Forge
    /// already has (§5 #12), and `ForgeViewModel.adoptPlan` writes them through
    /// the same `RitualEdit.repeats` the repeat picker writes. A day the plan
    /// has nothing on is not a miss — nothing is planned on it (§5 #11).
    ///
    /// # Every proposal has something on every day
    ///
    /// Four of the six dimensions' first starters are daily and a plan covers at
    /// least three dimensions, so every proposed week has something on each day
    /// — and so on today, which the first run's "do one now" needs.
    /// `TransformationTests` holds it for every weekday and every answer.
    static let cadences: [String: RitualRepeat] = [
        "workout": training, "run": training, "lift": training,
        "learn": practice, "write": practice, "teach": practice, "craft": practice,
        "hardest": .weekdays5, "focus": .weekdays5, "study": .weekdays5,
        "call": RitualRepeat(weekdays: [4, 1]),
        "meal": .weekends, "present": .weekends,
        "letter": weekly(1), "help": weekly(7), "arrange": weekly(5),
        "numbers": weekly(2), "reach": weekly(2), "askfor": weekly(4), "ship": weekly(6),
        // Before they ask twice.
        "plants": RitualRepeat(weekdays: [4, 1]),
    ]

    /// Monday, Wednesday, Friday.
    private static let training = RitualRepeat(weekdays: [2, 4, 6])
    /// Tuesday, Thursday, Saturday.
    private static let practice = RitualRepeat(weekdays: [3, 5, 7])

    private static func weekly(_ weekday: Int) -> RitualRepeat {
        RitualRepeat(weekdays: [weekday])
    }

    static func cadence(for ritualID: String) -> RitualRepeat {
        cadences[ritualID] ?? .daily
    }

    /// Activities whose nature is the end of a day, whatever they are filed
    /// under: setting tomorrow's one thing, laying it out the night before,
    /// writing the day down, putting a worry on paper.
    static let eveningActivities: Set<String> = ["plan", "prep", "journal", "worry", "letter"]

    /// Morning or evening, by what the activity is.
    ///
    /// The body, the day's own discipline, a steady head and the work that is
    /// yours go early, because all four are what a day takes away first — the
    /// same reasoning `DayPlanner.Slotting` uses. People and reading go in the
    /// evening, when the people are home and the head is clear.
    static func isEvening(_ ritual: Ritual) -> Bool {
        if eveningActivities.contains(ritual.id) { return true }
        if ritual.id == "wake" { return false }
        switch ritual.category {
        case .relationship, .intellect: return true
        default: return false
        }
    }

    /// An hour for each, laid out one after another from the start of its half
    /// of the day.
    ///
    /// Getting up opens the morning when it is there. In the evening the
    /// people go first and anything about tomorrow goes last. Each next
    /// activity starts when the one before it would end, with five minutes
    /// between them, on a five-minute mark.
    static func proposedMinutes(for rituals: [Ritual]) -> [String: Int] {
        let morning = rituals.filter { !isEvening($0) }.sorted { lhs, rhs in
            if (lhs.id == "wake") != (rhs.id == "wake") { return lhs.id == "wake" }
            return IdentityActivities.effort(of: lhs.id) < IdentityActivities.effort(of: rhs.id)
        }
        let evening = rituals.filter(isEvening).sorted { lhs, rhs in
            let l = eveningOrder(lhs), r = eveningOrder(rhs)
            if l != r { return l < r }
            return IdentityActivities.effort(of: lhs.id) < IdentityActivities.effort(of: rhs.id)
        }

        var minutes: [String: Int] = [:]
        for (sequence, start) in [(morning, morningStart), (evening, eveningStart)] {
            var cursor = start
            for ritual in sequence {
                minutes[ritual.id] = cursor
                cursor = roundUp(cursor + max(ritual.minutes, 10) + 5)
            }
        }
        return minutes
    }

    private static func eveningOrder(_ ritual: Ritual) -> Int {
        if ritual.category == .relationship { return 0 }
        if ["plan", "prep"].contains(ritual.id) { return 2 }
        return 1
    }

    private static func roundUp(_ minute: Int) -> Int { (minute + 4) / 5 * 5 }
}

// MARK: - The transformation

/// Where somebody is, and where the same arithmetic says they would be.
///
/// # Four stops, one model
///
/// Every number on the transformation screen is `BlendedShape.read` — the
/// function the Becoming tab draws from — run over `DayRecord`s held in memory
/// for days that have not happened. Nothing is scaled, curved or rounded up for
/// the screen: if the model would not show it on day thirty, the projection
/// does not show it now.
///
/// - **Where you are now:** no record. The six baselines.
/// - **In 7 days** and **in 30 days:** the proposed plan **on its own days** —
///   training on its three, reading on its seven — with five of every seven of
///   each activity's planned days kept, spread evenly and laid back from the
///   end of the stop (`isKept(occurrence:)`). A day an activity is not planned
///   on is neither kept nor missed (§5 #11). The assumption is printed under both, word for word; no
///   dimension is projected below its starting number (`floored`), and none
///   reads higher at seven days than at thirty (`capped`), so nothing on the
///   screen goes down for keeping the plan.
/// - **Full potential:** every dimension planned every day and kept for
///   twenty-eight days — a hundred in each, which is the edge of the instrument
///   rather than a target (see `ForgeShapeView`), and said as "all six built
///   and kept". It is not the plan, so it does not take the plan's days.
///
/// These are projections and never promises (§5 #4): nothing on the screen says
/// "will".
enum Transformation {

    /// Days kept per week under the printed assumption.
    static let keptPerWeek = 5

    enum Stop: Int, CaseIterable, Identifiable, Sendable {
        case now, week, month, potential

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .now: "Where you are now"
            case .week: "In 7 days"
            case .month: "In 30 days"
            case .potential: "Full potential"
            }
        }

        /// The segment's own short label. The title above carries it in full.
        var segment: String {
            switch self {
            case .now: "Now"
            case .week: "7 days"
            case .month: "30 days"
            case .potential: "Full"
            }
        }

        /// The assumption, printed under the stop. Never "will".
        ///
        /// "Days on the plan" rather than "days a week": the plan has its own
        /// days now, and a rest day is not a day anybody failed to keep.
        var footnote: String {
            switch self {
            case .now: "From your answers."
            case .week, .month: "Projected if you keep five of every seven days on the plan you're about to see."
            case .potential: "All six built and kept."
            }
        }

        /// How many days of record the stop is read after.
        var days: Int {
            switch self {
            case .now: 0
            case .week: 7
            case .month: 30
            case .potential: BlendedShape.blendDays
            }
        }
    }

    /// One stop: the six, the blade that stage earns, and the days behind it.
    struct Frame: Identifiable, Equatable, Sendable {
        let stop: Stop
        let shape: BlendedShape
        let daysKept: Int
        let blade: Sword

        var id: Stop { stop }

        /// The line under the blade's name, in words (prose, so counts up to
        /// a hundred are spelled).
        ///
        /// The days the stop is read after, except at full potential, where
        /// the blade is simply the last one there is and the line says what
        /// that blade takes — "Sixty days kept" for Proven today, and whatever
        /// the last rung asks once the ladder grows.
        var daysLine: String {
            let days = stop == .potential ? blade.requirement : daysKept
            let words = FirstWeek.days(days)
            let line = words.prefix(1).uppercased() + words.dropFirst() + " kept"
            return stop == .now ? line + " yet" : line
        }
    }

    /// Whether an activity's planned day is kept under the printed assumption,
    /// by `index`: how many of its planned days come after it before the stop
    /// (nought is its last).
    ///
    /// **Counted per activity, over the days it is planned on**, never over the
    /// calendar: training on three days a week is projected over its three,
    /// reading over its seven, and a day an activity is not on is not a day it
    /// could miss. Spread as evenly as the pattern allows, so any run of
    /// planned days holds `keptDays(in:)` of them: five of seven, twenty-one of
    /// thirty.
    ///
    /// **Counted back from the end of the stop**, because a stop is read over
    /// its last twenty-eight days (`ForgeShape.window`) and twenty-eight days
    /// hold exactly four of every weekday. Laid from the end, the window holds
    /// the same kept count whatever weekday the plan started on; laid from the
    /// start, the days that fell before the window decided it — a weekday
    /// block read 75 from a Monday install and 70 from a Friday one.
    ///
    /// It used to be counted over calendar days, which was the same thing
    /// while every activity was planned every day. With a weekly plan it is
    /// not: which three days training fell on decided whether it was kept two
    /// times in three or three in three.
    static func isKept(occurrence index: Int) -> Bool {
        keptDays(in: index + 1) > keptDays(in: index)
    }

    static func keptDays(in days: Int) -> Int {
        guard days > 0 else { return 0 }
        return (keptPerWeek * days + 2) / 7
    }

    /// Days kept by the end of a stop: five of every seven days the plan asks
    /// for anything on. A day it asks for nothing on can be neither kept nor
    /// missed, so it counts neither way. With something every day — which is
    /// every proposal — it is five of seven calendar days, as it always was.
    static func daysKept(_ plan: [Ritual], from start: ForgeDay, days: Int) -> Int {
        let asking = (0..<max(0, days)).count { index in
            let weekday = start.adding(days: index).weekday
            return plan.contains { $0.happens(on: weekday) }
        }
        return keptDays(in: asking)
    }

    /// The blade a count of days kept has earned. Full potential is the last
    /// one there is, whatever that is when the ladder grows.
    static func blade(forDaysKept kept: Int) -> Sword {
        Sword.collection.last { $0.requirement <= kept } ?? Sword.collection[0]
    }

    /// Every stop, in order.
    static func frames(plan: [Ritual], assessment: Assessment) -> [Frame] {
        Stop.allCases.map { frame($0, plan: plan, assessment: assessment) }
    }

    static func frame(_ stop: Stop, plan: [Ritual], assessment: Assessment) -> Frame {
        let start = assessment.day
        switch stop {
        case .now:
            return Frame(
                stop: stop,
                shape: BlendedShape.read([:], today: start, activities: plan, assessment: assessment),
                daysKept: 0,
                blade: blade(forDaysKept: 0)
            )

        case .week, .month:
            let kept = daysKept(plan, from: start, days: stop.days)
            let shape = projected(stop, plan: plan, assessment: assessment)
            return Frame(
                stop: stop,
                shape: stop == .week
                    ? capped(shape, by: projected(.month, plan: plan, assessment: assessment))
                    : shape,
                daysKept: kept,
                blade: blade(forDaysKept: kept)
            )

        case .potential:
            let everything = RitualCategory.dimensions.compactMap { OnboardingPlan.starter(for: $0) }
            let records = simulate(everything, from: start, days: stop.days) { _ in true }
            return Frame(
                stop: stop,
                shape: BlendedShape.read(
                    records, today: start.adding(days: stop.days),
                    activities: everything, assessment: assessment
                ),
                daysKept: stop.days,
                blade: Sword.collection[Sword.collection.count - 1]
            )
        }
    }

    /// Days that have not happened, written the way `ProgressStore` would have
    /// written them.
    ///
    /// Each day plans what the plan has **on that weekday** — the same
    /// `RitualRepeat.includes` the day list filters by, so a Tuesday asks for
    /// nothing that is only on Mondays — and each activity is done on the
    /// planned days `kept` says, counted for that activity alone and back from
    /// the end of the stop (see `isKept(occurrence:)`). A day with all of it
    /// done is earned; a day with nothing planned is not written, the way an
    /// empty day never is.
    static func simulate(
        _ plan: [Ritual], from start: ForgeDay, days: Int, kept: (Int) -> Bool
    ) -> [ForgeDay: DayRecord] {
        let span = (0..<max(0, days)).map { start.adding(days: $0) }
        // How many of each activity's planned days are still to come.
        var remaining: [String: Int] = [:]
        for day in span {
            for ritual in plan where ritual.happens(on: day.weekday) {
                remaining[ritual.id, default: 0] += 1
            }
        }
        var records: [ForgeDay: DayRecord] = [:]
        for day in span {
            let asked = plan.filter { $0.happens(on: day.weekday) }
            guard !asked.isEmpty else { continue }
            let at = day.startOfDay().addingTimeInterval(12 * 3600)
            var done: [Ritual] = []
            for ritual in asked {
                let after = remaining[ritual.id, default: 1] - 1
                remaining[ritual.id] = after
                if kept(after) { done.append(ritual) }
            }
            records[day] = DayRecord(
                day: day,
                completions: done.map { DayRecord.Completion(ritualID: $0.id, method: .honor, at: at) },
                plannedIDs: asked.map(\.id),
                extractedAt: done.count == asked.count ? at : nil
            )
        }
        return records
    }

    // MARK: - The floor under a projection, and the ceiling on the first week

    /// A stop's six as the model reads them over days that have not happened,
    /// floored at where the answers put them.
    private static func projected(_ stop: Stop, plan: [Ritual], assessment: Assessment) -> BlendedShape {
        let records = simulate(plan, from: assessment.day, days: stop.days, kept: isKept(occurrence:))
        let read = BlendedShape.read(
            records, today: assessment.day.adding(days: stop.days),
            activities: plan, assessment: assessment
        )
        return floored(read, at: assessment)
    }

    /// No dimension reads higher at seven days than at thirty.
    ///
    /// # Why
    ///
    /// Each activity is kept on its own days, five of every seven of them, so
    /// in a first week the days one activity is missed can happen to be days
    /// another — feeding the same dimension a third of a day — is kept. Over
    /// seven days that rounds a dimension a point or two above where thirty
    /// days settle it, and the screen showed 77 at seven days and 76 at
    /// thirty: a number going down for keeping the plan, the same wrong picture
    /// `floored` fixes, from a different rounding. The projection holds one
    /// rate throughout, so the earlier stop is held to the later one — never
    /// the later lifted to the earlier, which would show thirty days of the
    /// plan reading more than they do.
    static func capped(_ shape: BlendedShape, by later: BlendedShape) -> BlendedShape {
        BlendedShape(
            dimensions: zip(shape.dimensions, later.dimensions).map { dimension, then in
                guard dimension.hasScore, then.hasScore, dimension.score > then.score else { return dimension }
                return BlendedShape.Dimension(
                    record: dimension.record,
                    baseline: dimension.baseline,
                    source: dimension.source,
                    score: then.score,
                    direction: dimension.direction
                )
            },
            record: shape.record,
            hasAssessment: shape.hasAssessment
        )
    }

    /// No dimension is projected below where the answers put it:
    /// `shown = max(baseline, projected)`, each of the six, at the seven- and
    /// thirty-day stops.
    ///
    /// # Why
    ///
    /// Five kept days in seven reads seventy-one, and an answer can start a
    /// dimension at seventy-five. So the strongest answer, projected over the
    /// plan kept exactly as the footnote assumes, came out at 71 on the
    /// thirty-day stop — a number going down on the screen that shows what the
    /// plan does, for keeping the plan. Nothing anybody did produced it: it was
    /// the printed assumption sitting below a starting number, and a projection
    /// has no record in it for the number to be honest about. A dimension that
    /// is already strong now stays where it is while the weaker ones rise,
    /// which is the true picture of that plan.
    ///
    /// # What it does not do
    ///
    /// - **It never raises anything past its start.** A dimension below its
    ///   baseline is lifted *to* the baseline; an unplanned one is at its
    ///   baseline already, so it cannot move.
    /// - **It does not touch `BlendedShape` or `ForgeShape`.** This is a rule
    ///   about days that have not happened. The Becoming tab still reads the
    ///   record, and somebody who answered 75 and keeps five days in seven
    ///   sees about 71 once the record speaks for them — because that is what
    ///   they did.
    /// - **A floored dimension is not slipping.** It is held at its start, so
    ///   whatever its two simulated fortnights rounded to, it reads as steady.
    ///
    /// OVR follows by itself: it is the mean of the six shown.
    static func floored(_ shape: BlendedShape, at assessment: Assessment) -> BlendedShape {
        BlendedShape(
            dimensions: shape.dimensions.map { dimension in
                guard dimension.hasScore,
                      let baseline = assessment.baseline(for: dimension.category),
                      dimension.score < baseline
                else { return dimension }
                return BlendedShape.Dimension(
                    record: dimension.record,
                    baseline: dimension.baseline,
                    source: dimension.source,
                    score: baseline,
                    direction: dimension.direction == .slipping ? .steady : dimension.direction
                )
            },
            record: shape.record,
            hasAssessment: shape.hasAssessment
        )
    }
}

import Foundation

// MARK: - The proposed plan

/// One activity on the first run's plan, and the hour it is proposed for.
///
/// One per dimension, which is why the dimension is the identity: the plan is
/// "something for each part you are building", and swapping a row swaps the
/// activity inside its dimension rather than adding a second one.
struct PlanEntry: Identifiable, Equatable, Sendable {
    let dimension: RitualCategory
    var ritualID: String
    /// Minutes since midnight.
    var minute: Int

    var id: RitualCategory { dimension }
    var ritual: Ritual? { Ritual.find(ritualID) }
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
/// Each gets a proposed hour, morning or evening by what it is — see
/// `isEvening(_:)` — laid out one after another so two activities never start
/// on top of each other and Plan's `untangle` has nothing to say on day one.
/// Every hour is a proposal: the row is one tap from a time picker.
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
            .map { PlanEntry(dimension: $0.category, ritualID: $0.id, minute: minutes[$0.id] ?? morningStart) }
            .sorted { $0.minute < $1.minute }
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
/// - **In 7 days** and **in 30 days:** the proposed plan, planned every day and
///   kept five days of seven, spread evenly and starting with today. The
///   assumption is printed under both, word for word.
/// - **Full potential:** every dimension planned every day and kept for
///   twenty-eight days — a hundred in each, which is the edge of the instrument
///   rather than a target (see `ForgeShapeView`), and said as "all six built
///   and kept".
///
/// These are projections and never promises (§5 #4): nothing on the screen says
/// "will".
///
/// # One honest wrinkle
///
/// Five days of seven is a reading of seventy-one. A planned dimension whose
/// baseline is already above that — the top answer, 75 — is projected to settle
/// at the rate the plan is kept at, a few points lower, because that is what
/// the record would show. It is left true rather than smoothed over.
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
        var footnote: String {
            switch self {
            case .now: "From your answers."
            case .week, .month: "Projected if you keep five days a week of the plan you're about to see."
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

    /// Whether day `index` (nought is today) of a five-a-week projection is
    /// kept.
    ///
    /// Spread as evenly as the week allows and starting with a kept day —
    /// today is the day somebody keeps their first thing in the first run —
    /// so the count over any number of days is `keptDays(in:)`: five of seven,
    /// twenty-one of thirty.
    static func isKept(day index: Int) -> Bool {
        keptDays(in: index + 1) > keptDays(in: index)
    }

    static func keptDays(in days: Int) -> Int {
        guard days > 0 else { return 0 }
        return (keptPerWeek * days + 2) / 7
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
            let records = simulate(plan, from: start, days: stop.days, kept: isKept(day:))
            return Frame(
                stop: stop,
                shape: BlendedShape.read(
                    records, today: start.adding(days: stop.days),
                    activities: plan, assessment: assessment
                ),
                daysKept: keptDays(in: stop.days),
                blade: blade(forDaysKept: keptDays(in: stop.days))
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
    /// written them: the plan planned every day, all of it done and the blade
    /// pulled on a kept day, nothing done on the others.
    static func simulate(
        _ plan: [Ritual], from start: ForgeDay, days: Int, kept: (Int) -> Bool
    ) -> [ForgeDay: DayRecord] {
        let ids = plan.map(\.id)
        var records: [ForgeDay: DayRecord] = [:]
        for index in 0..<max(0, days) {
            let day = start.adding(days: index)
            let isKept = kept(index)
            let at = day.startOfDay().addingTimeInterval(12 * 3600)
            records[day] = DayRecord(
                day: day,
                completions: isKept
                    ? ids.map { DayRecord.Completion(ritualID: $0, method: .honor, at: at) }
                    : [],
                plannedIDs: ids,
                extractedAt: isKept ? at : nil
            )
        }
        return records
    }
}

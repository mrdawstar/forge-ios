import Foundation

// MARK: - What somebody said

/// Somebody joining an Arc: which one, from which day, and what they chose.
///
/// # Stated, never derived
///
/// Everything here is something a person said or Forge did at their say-so:
/// the Arc, the start day, the wake time and the three picks, what joining
/// wrote into their week, how they answered each phase's changes, the counts
/// only they can keep, and the day they left. **Nothing here is a count of
/// days.** Day 12 of 90, the days kept inside the Arc, the phase, whether it is
/// on track and whether it was completed are all read out of the `DayRecord`s
/// every time somebody looks (`ArcReading`, §5 #2), so an Arc cannot develop a
/// number that disagrees with the history behind it.
///
/// Stored as a list under `forge.arcs.v1`, every finished and left one kept:
/// a finished Arc is a permanent mark on the record.
struct ArcEnrollment: Identifiable, Equatable, Sendable {
    /// Minted, never derived from the Arc — the same Arc can be run twice.
    let id: String
    let arc: ArcID
    /// The first day of it, on Forge's own day clock.
    let startDay: ForgeDay
    /// Minutes past midnight, for an Arc that asks for one.
    var wakeMinute: Int?
    /// The activities somebody chose for it, by id (Discipline 66's three).
    var picks: [String]
    /// What joining added to the week, by id — and the only activities "take
    /// them off" may ever remove. Anything that was already in the week when
    /// they joined is theirs, Arc or no Arc.
    var added: [String]
    /// Whether joining has been written into the week. False only between a
    /// "Start Monday" and that Monday: nothing is added to a week before the
    /// Arc it is for begins.
    var isApplied: Bool
    /// Each phase's changes, once answered: true applied, false kept as it
    /// was. By phase index. An unanswered phase is still offered on the card.
    var phaseAnswers: [Int: Bool]
    /// The counts only the person can keep — two cold showers, one book — by
    /// trial index. Their word, like every other promise kept in Forge.
    var tallies: [Int: Int]
    /// The day somebody left, if they did.
    var leftOn: ForgeDay?
    var joinedAt: Date

    init(
        id: String = "arc.\(UUID().uuidString)",
        arc: ArcID,
        startDay: ForgeDay,
        wakeMinute: Int? = nil,
        picks: [String] = [],
        added: [String] = [],
        isApplied: Bool = false,
        phaseAnswers: [Int: Bool] = [:],
        tallies: [Int: Int] = [:],
        leftOn: ForgeDay? = nil,
        joinedAt: Date = .now
    ) {
        self.id = id
        self.arc = arc
        self.startDay = startDay
        self.wakeMinute = wakeMinute
        self.picks = picks
        self.added = added
        self.isApplied = isApplied
        self.phaseAnswers = phaseAnswers
        self.tallies = tallies
        self.leftOn = leftOn
        self.joinedAt = joinedAt
    }

    var program: ArcProgram { ArcCatalog.program(arc) }

    /// The last day of it.
    var endDay: ForgeDay { startDay.adding(days: program.length - 1) }

    /// The wake time this Arc's clock times are laid from.
    var wake: Int { wakeMinute ?? ArcProgram.defaultWake }

    /// "Winter Arc 2026" — the name the record keeps it under. The winter is
    /// named for the year it began; every other Arc is its own name.
    var recordName: String {
        guard arc == .winter else { return program.name }
        return "\(program.name) \(ArcCatalog.winterYear(startingOn: startDay))"
    }
}

// MARK: - Reading what is on disk

extension ArcEnrollment: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, arc, startDay, wakeMinute, picks, added, isApplied
        case phaseAnswers, tallies, leftOn, joinedAt
    }

    /// Hand-written and tolerant, for the reason every decoder here is. Only
    /// the id, the Arc and the start day are required — without them there is
    /// no enrollment to speak of — and an Arc this build has never heard of
    /// throws here so the list can drop it (`decodeAll`) rather than lose the
    /// rest. Everything else falls back to the state a fresh join has.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        arc = try c.decode(ArcID.self, forKey: .arc)
        startDay = try c.decode(ForgeDay.self, forKey: .startDay)
        wakeMinute = try? c.decodeIfPresent(Int.self, forKey: .wakeMinute)
        picks = (try? c.decodeIfPresent([String].self, forKey: .picks)) ?? []
        added = (try? c.decodeIfPresent([String].self, forKey: .added)) ?? []
        // A join written before `isApplied` existed cannot exist — the key is
        // as old as the type — so a missing one means "written".
        isApplied = (try? c.decodeIfPresent(Bool.self, forKey: .isApplied)) ?? true
        phaseAnswers = Self.intKeyed((try? c.decodeIfPresent([String: Bool].self, forKey: .phaseAnswers)) ?? [:])
        tallies = Self.intKeyed((try? c.decodeIfPresent([String: Int].self, forKey: .tallies)) ?? [:])
            .filter { $0.value > 0 }
        leftOn = try? c.decodeIfPresent(ForgeDay.self, forKey: .leftOn)
        joinedAt = (try? c.decodeIfPresent(Date.self, forKey: .joinedAt)) ?? startDay.startOfDay()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(arc, forKey: .arc)
        try c.encode(startDay, forKey: .startDay)
        try c.encodeIfPresent(wakeMinute, forKey: .wakeMinute)
        try c.encode(picks, forKey: .picks)
        try c.encode(added, forKey: .added)
        try c.encode(isApplied, forKey: .isApplied)
        // String keys, written out: what an `[Int: _]` becomes in JSON is the
        // encoder's business, and a stored format should not be.
        try c.encode(Dictionary(uniqueKeysWithValues: phaseAnswers.map { (String($0.key), $0.value) }), forKey: .phaseAnswers)
        try c.encode(Dictionary(uniqueKeysWithValues: tallies.map { (String($0.key), $0.value) }), forKey: .tallies)
        try c.encodeIfPresent(leftOn, forKey: .leftOn)
        try c.encode(joinedAt, forKey: .joinedAt)
    }

    private static func intKeyed<Value>(_ dictionary: [String: Value]) -> [Int: Value] {
        Dictionary(
            dictionary.compactMap { key, value in Int(key).map { ($0, value) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// The whole list, keeping every entry that reads. One unreadable row must
    /// not cost somebody the Arcs they have finished.
    static func decodeAll(_ data: Data) -> [ArcEnrollment] {
        struct Lossy: Decodable {
            let value: ArcEnrollment?
            init(from decoder: Decoder) throws { value = try? ArcEnrollment(from: decoder) }
        }
        return ((try? JSONDecoder().decode([Lossy].self, from: data)) ?? []).compactMap(\.value)
    }
}

// MARK: - What the record says

/// An Arc measured against the record. **Derived, never stored** (§5 #2).
///
/// # The count
///
/// `counted` is the days of the Arc that could have been kept so far and
/// `kept` the ones that were. **A rest day is neither** (§5 #11): a weekday set
/// aside in Settings is no part of either number, kept or not. **Today joins
/// both only once it is kept** — a day in progress is never a miss, the same
/// rule as every rate in Forge (`ProgressStore.ratedDays`).
///
/// # On track, and finished
///
/// On track is at least five of every seven days kept since the start. Once
/// the end day has passed the Arc is finished, and it is **Completed** at its
/// goal — eighty per cent, five of seven for Lock In 7 — and otherwise simply
/// **Finished, 61 of 90 days**. Nothing here is a failure, and nothing says so.
struct ArcReading: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        /// Joined for a start day that has not come.
        case upcoming
        case active
        /// The end day has passed.
        case finished
        /// Somebody left before the end.
        case left
    }

    let arc: ArcID
    let status: Status
    let startDay: ForgeDay
    let endDay: ForgeDay
    let length: Int
    /// Which day of the Arc today is, 1…length while it runs. Nought before it
    /// starts; the length once finished; the day somebody left, once left.
    let day: Int
    let kept: Int
    let counted: Int
    /// The phase `day` falls in.
    let phase: Int
    /// This week's trial and how far it has got. Nil before the start.
    let trial: ArcTrialProgress?
    /// Finished, and at its goal.
    let isCompleted: Bool

    /// At least five of every seven days kept since the start. True while
    /// nothing has been counted yet: an Arc cannot be behind on its first
    /// morning.
    var isOnTrack: Bool { counted == 0 || kept * 7 >= counted * 5 }

    var isRunning: Bool { status == .active }

    /// "Day 12 of 90". Digits: an Arc day counter (DIRECTION_1_1 §3).
    var counter: String { "Day \(day) of \(length)" }

    /// What a finished Arc says about itself, and the only two ways it can:
    /// "Completed, 84 of 90 days" or "Finished, 61 of 90 days". The counts are
    /// of days that could be kept, so a set rest day is in neither.
    var outcome: String {
        "\(isCompleted ? "Completed" : "Finished"), \(kept) of \(counted) days"
    }

    /// The one line about pace while it runs, in plain words.
    var paceLine: String {
        guard counted > 0 else { return "Nothing counted yet. Today counts once it is kept." }
        let days = "\(kept) of \(counted) \(counted == 1 ? "day" : "days") kept"
        return isOnTrack ? "On track. \(days)." : "Not on track yet. \(days); five of every seven is the pace."
    }

    /// Read one enrollment against the record, as of `today`.
    ///
    /// `kept` is which ids in the week do each Arc activity's job — its own,
    /// or one it also counts (`ArcPlan.resolve`) — and is what a trial that
    /// counts an activity looks for in the record.
    static func read(
        _ enrollment: ArcEnrollment,
        byDay: [ForgeDay: DayRecord],
        today: ForgeDay,
        restWeekdays: Set<Int>,
        challengeDays: Set<ForgeDay>,
        resolved: [String: String]
    ) -> ArcReading {
        let program = enrollment.program
        let start = enrollment.startDay
        let end = enrollment.endDay

        let status: Status
        let through: ForgeDay
        if let left = enrollment.leftOn {
            status = .left
            through = min(left, end, today)
        } else if today < start {
            status = .upcoming
            through = start.adding(days: -1)
        } else if today > end {
            status = .finished
            through = end
        } else {
            status = .active
            through = today
        }

        let tally = count(from: start, to: through, byDay: byDay, today: today, rest: restWeekdays)

        let day: Int
        switch status {
        case .upcoming: day = 0
        case .finished: day = program.length
        case .active: day = today.days(since: start) + 1
        case .left: day = max(1, min(program.length, through.days(since: start) + 1))
        }

        let trial: ArcTrialProgress? = status == .upcoming ? nil : trialProgress(
            program.trialIndex(onDay: day),
            of: enrollment, byDay: byDay, today: min(today, through),
            rest: restWeekdays, challengeDays: challengeDays, resolved: resolved
        )

        return ArcReading(
            arc: enrollment.arc,
            status: status,
            startDay: start,
            endDay: end,
            length: program.length,
            day: day,
            kept: tally.kept,
            counted: tally.counted,
            phase: program.phaseIndex(onDay: max(1, day)),
            trial: trial,
            isCompleted: status == .finished
                && program.completesAt.isMet(kept: tally.kept, counted: tally.counted)
        )
    }

    /// Days kept and days that could have been, between two days, by the
    /// rules above.
    static func count(
        from first: ForgeDay, to last: ForgeDay,
        byDay: [ForgeDay: DayRecord], today: ForgeDay, rest: Set<Int>
    ) -> (kept: Int, counted: Int) {
        guard first <= last else { return (0, 0) }
        var kept = 0
        var counted = 0
        var cursor = first
        while cursor <= last {
            defer { cursor = cursor.adding(days: 1) }
            if rest.contains(cursor.weekday) { continue }
            let earned = byDay[cursor]?.isEarned == true
            // Not a miss until it is over.
            if cursor == today, !earned { continue }
            if cursor > today { continue }
            counted += 1
            if earned { kept += 1 }
        }
        return (kept, counted)
    }

    /// How far one week's trial has got, read off the record and the tallies.
    static func trialProgress(
        _ index: Int,
        of enrollment: ArcEnrollment,
        byDay: [ForgeDay: DayRecord],
        today: ForgeDay,
        rest: Set<Int>,
        challengeDays: Set<ForgeDay>,
        resolved: [String: String]
    ) -> ArcTrialProgress? {
        let program = enrollment.program
        guard program.trials.indices.contains(index) else { return nil }
        let trial = program.trials[index]
        let span = program.trialDays(index)
        let first = enrollment.startDay.adding(days: span.lowerBound - 1)
        let last = min(enrollment.startDay.adding(days: span.upperBound - 1), today)
        let days: [ForgeDay] = first <= last
            ? (0...last.days(since: first)).map { first.adding(days: $0) }
            : []

        var target = trial.count.target
        let count: Int
        switch trial.count {
        case .activity(let ritualID, _):
            let id = resolved[ritualID] ?? ritualID
            count = days.count { byDay[$0]?.completedIDs.contains(id) == true }
        case .everything:
            let ids = Set(resolved.values)
            count = days.count { day in
                guard let record = byDay[day] else { return false }
                let asked = Set(record.plannedIDs).intersection(ids)
                return !asked.isEmpty && asked.isSubset(of: record.completedIDs)
            }
        case .kept:
            // A week holding a set rest day cannot be asked for more days than
            // it has left in it.
            let window = program.trialDays(index).count
            let restDays = (0..<window).count {
                rest.contains(enrollment.startDay.adding(days: span.lowerBound - 1 + $0).weekday)
            }
            target = max(1, min(target, window - restDays))
            count = days.count { !rest.contains($0.weekday) && byDay[$0]?.isEarned == true }
        case .challenges:
            count = days.count(where: challengeDays.contains)
        case .tally:
            count = enrollment.tallies[index] ?? 0
        }

        return ArcTrialProgress(
            index: index,
            count: min(count, target),
            target: target,
            isTally: trial.count.isTally
        )
    }
}

/// One week's trial and where it stands.
struct ArcTrialProgress: Equatable, Sendable {
    let index: Int
    let count: Int
    let target: Int
    let isTally: Bool

    var isMet: Bool { count >= target }

    /// "Trial 3 of 7" — the line on the Forge tab. A count, in digits.
    var line: String { "Trial \(count) of \(target)" }
}

// MARK: - What joining and each phase would change

/// What joining an Arc adds to the week, as a list somebody reads before
/// anything is written (§5 #9).
struct ArcJoin: Equatable, Sendable {
    /// One activity joining would add, on its days and at its hour.
    struct Addition: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let symbol: String
        let weekdays: Set<Int>
        let minute: Int?
        let minutes: Int
        let goal: String

        var change: ScheduleChange {
            .adopt(id: id, name: name, minutes: minutes, weekdays: weekdays, minute: minute)
        }

        /// "6:30 AM · Every day", "Weekdays · 45 min".
        var schedule: String {
            var parts: [String] = []
            if let minute { parts.append(ClockMinute.label(minute)) }
            parts.append(RitualRepeat(weekdays: weekdays).label)
            if let length = ClockMinute.duration(minutes) {
                parts.append(length)
            } else if !goal.isEmpty {
                parts.append(goal)
            }
            return parts.joined(separator: " \u{00B7} ")
        }
    }

    let additions: [Addition]
    /// The Arc's activities somebody already keeps, by name. Counted as theirs
    /// and left exactly as they are.
    let alreadyKept: [String]

    /// Only ever additions. **Joining appends** (§5 #7): it never removes an
    /// activity and never changes one that was already in the week — a phase's
    /// own changes are offered afterwards, on the Arc's card, one tap at a time.
    var changes: [ScheduleChange] { additions.map(\.change) }

    /// "Adds five activities to your week."
    var headline: String {
        switch additions.count {
        case 0: "Adds nothing to your week."
        case 1: "Adds one activity to your week."
        default: "Adds \(ForgeCount.spelled(additions.count).lowercased()) activities to your week."
        }
    }
}

/// The arithmetic between an Arc's definition and somebody's week. Pure:
/// everything it needs is handed in, so it is a fact that can be tested
/// without a phone.
enum ArcPlan {

    /// Everything an enrollment asks for: the Arc's own activities and, for an
    /// Arc that asks for picks, the ones somebody chose — every day, the same
    /// thing, for every phase.
    static func activities(of program: ArcProgram, picks: [String]) -> [ArcActivity] {
        program.activities + picks.prefix(program.picks).map {
            ArcActivity(ritualID: $0, standards: [ArcStandard(weekdays: ArcStandard.everyDay)])
        }
    }

    /// Which id in the week does an Arc activity's job: its own, or one it
    /// also counts. Nil when neither is kept.
    static func resolve(_ activity: ArcActivity, in week: Set<String>) -> String? {
        if week.contains(activity.ritualID) { return activity.ritualID }
        return activity.alsoCounts.first(where: week.contains)
    }

    /// Every Arc activity's id in the week, for counting. An activity that is
    /// not in the week keeps its own id, so a trial reads nothing for it.
    static func resolved(_ program: ArcProgram, picks: [String], week: Set<String>) -> [String: String] {
        Dictionary(
            activities(of: program, picks: picks).map { ($0.ritualID, resolve($0, in: week) ?? $0.ritualID) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// What joining would add.
    ///
    /// Everything the Arc asks for that the week does not already hold, on
    /// the first phase's days, at its hour (laid from `wake`), at its length.
    /// What is already held is listed and left alone.
    static func join(
        _ program: ArcProgram,
        wake: Int,
        picks: [String],
        week: [Ritual],
        find: (String) -> Ritual?
    ) -> ArcJoin {
        let held = Set(week.map(\.id))
        var additions: [ArcJoin.Addition] = []
        var already: [String] = []
        for activity in activities(of: program, picks: picks) {
            if let kept = resolve(activity, in: held) {
                if let name = week.first(where: { $0.id == kept })?.label { already.append(name) }
                continue
            }
            guard let ritual = find(activity.ritualID),
                  !additions.contains(where: { $0.id == ritual.id })
            else { continue }
            let standard = activity.standard(inPhase: 0)
            additions.append(
                ArcJoin.Addition(
                    id: ritual.id,
                    name: ritual.label,
                    symbol: ritual.symbolName ?? ForgeIcons.symbol(for: ritual.iconKey),
                    weekdays: standard.weekdays,
                    minute: activity.time.minute(wake: wake),
                    minutes: standard.minutes ?? ritual.minutes,
                    goal: standard.goal ?? ritual.tail
                )
            )
        }
        return ArcJoin(additions: additions, alreadyKept: already)
    }

    /// What a phase asks for that the week does not already have, as the
    /// changes that would close the gap — for activities somebody keeps. One
    /// they have taken out of their week is not put back: that was a decision.
    ///
    /// Computed against the week **as it is**, not against the phase before,
    /// so somebody who already trains for an hour is not offered "45 → 60".
    static func changes(
        for program: ArcProgram, picks: [String], phase: Int, week: [Ritual]
    ) -> [ScheduleChange] {
        let held = Set(week.map(\.id))
        var changes: [ScheduleChange] = []
        for activity in activities(of: program, picks: picks) {
            guard let id = resolve(activity, in: held),
                  let current = week.first(where: { $0.id == id })
            else { continue }
            let standard = activity.standard(inPhase: phase)
            let days = current.repeats.weekdays.isEmpty ? ArcStandard.everyDay : current.repeats.weekdays
            if standard.weekdays != days {
                changes.append(.days(id: id, name: current.label, weekdays: standard.weekdays, was: days))
            }
            if let minutes = standard.minutes, minutes != current.minutes {
                changes.append(.duration(id: id, name: current.label, minutes: minutes, was: current.minutes))
            }
            if let goal = standard.goal, goal != current.tail {
                changes.append(.goal(id: id, name: current.label, goal: goal, target: standard.target, was: current.tail))
            }
        }
        return changes
    }

    /// The first run's plan when somebody starts with an Arc: what the plan
    /// beat shows and what becomes the day.
    ///
    /// A new install keeps nothing yet, so every activity the Arc asks for is
    /// on it, on the first phase's days, at its hour from the default wake
    /// time. Discipline 66's three are the plan's own first three, on every
    /// day and at the hours the plan gave them — the same things somebody was
    /// just shown, now sixty-six times. Lock In 7 is the plan as it is, so it
    /// has no rows of its own.
    static func firstRun(
        _ program: ArcProgram, plan: [PlanEntry], find: (String) -> Ritual?
    ) -> (additions: [ArcJoin.Addition], picks: [String]) {
        let picks = Array(plan.map(\.ritualID).filter { $0 != "wake" }.prefix(program.picks))
        let own = join(program, wake: ArcProgram.defaultWake, picks: [], week: [], find: find).additions
        let chosen: [ArcJoin.Addition] = picks.compactMap { id in
            guard let ritual = find(id), !own.contains(where: { $0.id == id }) else { return nil }
            return ArcJoin.Addition(
                id: id,
                name: ritual.label,
                symbol: ritual.symbolName ?? ForgeIcons.symbol(for: ritual.iconKey),
                weekdays: ArcStandard.everyDay,
                minute: plan.first { $0.ritualID == id }?.minute,
                minutes: ritual.minutes,
                goal: ritual.tail
            )
        }
        return ((own + chosen).sorted { ($0.minute ?? .max) < ($1.minute ?? .max) }, picks)
    }

    /// What one phase changes from the one before, as the Arc defines it —
    /// for the Arc's own screen and the preview of the next phase, where
    /// nobody's week is involved. Names come from `find`.
    static func steps(
        for program: ArcProgram, picks: [String] = [], from previous: Int, to next: Int,
        find: (String) -> Ritual?
    ) -> [ScheduleChange] {
        var changes: [ScheduleChange] = []
        for activity in activities(of: program, picks: picks) {
            guard let ritual = find(activity.ritualID) else { continue }
            let before = activity.standard(inPhase: previous)
            let after = activity.standard(inPhase: next)
            if before.weekdays != after.weekdays {
                changes.append(.days(id: ritual.id, name: ritual.label, weekdays: after.weekdays, was: before.weekdays))
            }
            if let minutes = after.minutes, minutes != (before.minutes ?? ritual.minutes) {
                changes.append(.duration(id: ritual.id, name: ritual.label, minutes: minutes, was: before.minutes ?? ritual.minutes))
            }
            if let goal = after.goal, goal != (before.goal ?? ritual.tail) {
                changes.append(.goal(id: ritual.id, name: ritual.label, goal: goal, target: after.target, was: before.goal ?? ritual.tail))
            }
        }
        return changes
    }
}

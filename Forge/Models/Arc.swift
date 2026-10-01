import Foundation

// MARK: - Which Arc

/// The four Arcs (DIRECTION_1_1 §5), by the id `forge.arcs.v1` stores.
///
/// The raw values are on disk and never change. A fifth Arc is a new case and
/// a new entry in `ArcCatalog.all`; nothing else in the app names one.
enum ArcID: String, CaseIterable, Codable, Sendable, Identifiable {
    case lockIn = "lockin7"
    case monk = "monk30"
    case discipline = "discipline66"
    case winter = "winter90"

    var id: String { rawValue }
}

// MARK: - What an Arc asks for

/// What one phase asks of one activity: the days, and — where the phase sets
/// them — the length and the standard.
///
/// A phase never says *when* in the day. The hour is decided once, on joining
/// (`ArcTime`), and after that it is somebody's own: an Arc that moved their
/// training back to seven every fortnight would be overruling the one part of
/// the week they are most likely to have tuned.
struct ArcStandard: Equatable, Sendable {
    /// `Calendar` weekdays, 1 = Sunday. Never empty.
    var weekdays: Set<Int>
    /// How long, where the phase says. Nil leaves the length alone.
    var minutes: Int? = nil
    /// The target in the row's right-hand column — "10,000", "20 pages" —
    /// where the phase sets one. Nil leaves it alone.
    var goal: String? = nil
    /// The number behind `goal`, for an activity the phone can one day
    /// measure (`Ritual.measure`). Nil leaves it alone.
    var target: Int? = nil

    static let everyDay: Set<Int> = Set(1...7)
    static let weekdays: Set<Int> = [2, 3, 4, 5, 6]
}

/// When an Arc puts an activity in the day, decided once, on joining.
enum ArcTime: Equatable, Sendable {
    /// No clock: some time that day.
    case anytime
    /// This many minutes after the wake time somebody chose on joining.
    case afterWake(Int)
    /// This clock time, in minutes past midnight.
    case at(Int)

    func minute(wake: Int) -> Int? {
        switch self {
        case .anytime: nil
        case .afterWake(let offset): ((wake + offset) % 1440 + 1440) % 1440
        case .at(let minute): minute
        }
    }
}

/// One activity an Arc asks for, and what each phase asks of it.
///
/// **Always a library activity.** Only concrete, countable things, written the
/// way the library is — the label is the act and the subtitle is the standard
/// — and taken from the library rather than minted, so an Arc's training is
/// the same `workout` somebody's record already knows (§5 #7: a suggestion
/// appends, and appends the real thing).
struct ArcActivity: Equatable, Sendable {
    let ritualID: String
    /// Library activities that already do this one's job. Somebody who keeps
    /// one of these has the Arc count theirs, and nothing is added: Winter's
    /// reading is "Read on paper", but a person who already keeps "Read" is not
    /// handed a second book.
    var alsoCounts: [String] = []
    var time: ArcTime = .anytime
    /// One per phase, in phase order. A phase past the end keeps the last.
    let standards: [ArcStandard]

    func standard(inPhase index: Int) -> ArcStandard {
        standards[max(0, min(index, standards.count - 1))]
    }
}

/// A stretch of an Arc with a name. Days are counted from one.
struct ArcPhase: Equatable, Sendable {
    let name: String
    let firstDay: Int
    let lastDay: Int
    /// What this phase is, in one line of prose.
    let line: String

    /// The week of the Arc this phase begins in — "Week 3" on the card that
    /// offers what it changes.
    var week: Int { (firstDay - 1) / 7 + 1 }

    func contains(day: Int) -> Bool { (firstDay...lastDay).contains(day) }

    /// "Days 15–42". Arc day counters are digits (DIRECTION_1_1 §3).
    var span: String {
        firstDay == lastDay ? "Day \(firstDay)" : "Days \(firstDay)\u{2013}\(lastDay)"
    }
}

/// One week's trial: something countable to aim the week at.
///
/// Trials run in weeks of seven from the first day, so the thirteenth of a
/// ninety-day Arc is its last six days. **Every one is a count**, and most of
/// them are read straight off the record; the few nothing in Forge can see — a
/// cold shower, a book finished — are counted by the person, one tap each,
/// which is the same Your Word every other promise here is kept on.
struct ArcTrial: Equatable, Sendable {
    let title: String
    let detail: String
    let count: Count

    enum Count: Equatable, Sendable {
        /// Days this week the Arc's activity was done. Read off the record.
        case activity(String, days: Int)
        /// Days this week on which everything the Arc asked of that day was
        /// done. Read off the record.
        case everything(days: Int)
        /// Days this week kept — the blade pulled. Read off the record; a rest
        /// day is no part of it either way.
        case kept(days: Int)
        /// Daily challenges finished this week. Read off the record.
        case challenges(Int)
        /// Something only the person can count, marked by hand.
        case tally(Int)

        var target: Int {
            switch self {
            case .activity(_, let days), .everything(let days), .kept(let days): days
            case .challenges(let count), .tally(let count): count
            }
        }

        var isTally: Bool {
            if case .tally = self { return true }
            return false
        }
    }
}

/// What "Completed" means for an Arc: this many kept of every so many days.
struct ArcGoal: Equatable, Sendable {
    let kept: Int
    let of: Int

    /// Eighty per cent, the line for every Arc but the starter.
    static let fourInFive = ArcGoal(kept: 4, of: 5)
    /// Lock In 7's own goal: five of the seven.
    static let fiveInSeven = ArcGoal(kept: 5, of: 7)

    func isMet(kept daysKept: Int, counted: Int) -> Bool {
        counted > 0 && daysKept * of >= counted * kept
    }
}

// MARK: - An Arc

/// A program with a start and an end (DIRECTION_1_1 §5): activities that ramp
/// by phase, a trial each week, and a mark on the record when it is finished.
///
/// This is the definition, and it is data — written here, never stored. What
/// somebody *did* with one is `ArcEnrollment` (the stated part: which, when,
/// their choices) read against their `DayRecord`s (`ArcReading`, everything
/// else), so the day count, the days kept, the phase and whether it was
/// completed are all derived on read (§5 #2).
struct ArcProgram: Identifiable, Equatable, Sendable {
    let id: ArcID
    let name: String
    /// In days.
    let length: Int
    /// One line for the list.
    let summary: String
    /// One honest line of why — never a promise about outcomes (§5 #4).
    let why: String
    /// The finding `why` paraphrases, in small type, or nil. Only the four
    /// papers DIRECTION_1_1 allows.
    var source: String? = nil
    let phases: [ArcPhase]
    /// Everything the Arc asks for, with what each phase asks of it. Empty for
    /// Lock In 7, which runs on the week as it is.
    let activities: [ArcActivity]
    /// One per week, in order.
    let trials: [ArcTrial]
    var completesAt: ArcGoal = .fourInFive
    /// Whether joining asks for a wake time.
    var asksForWake = false
    /// How many activities somebody chooses for it themselves.
    var picks = 0
    /// Whether the daily challenge is part of every day of it.
    var withChallenge = false
    /// What finishing it earns beyond its mark, said plainly, or nil.
    var reward: String? = nil

    /// The cover in the asset catalogue. `ArcCover` draws a typographic one
    /// where the image is missing.
    var cover: String {
        switch id {
        case .lockIn: "arc-lockin"
        case .monk: "arc-monk"
        case .discipline: "arc-66"
        case .winter: "arc-winter"
        }
    }

    /// "90 days". A day counter, so digits.
    var lengthLabel: String { "\(length) days" }

    var isSeasonal: Bool { id == .winter }

    /// Which phase a day of the Arc falls in.
    func phaseIndex(onDay day: Int) -> Int {
        phases.lastIndex { $0.firstDay <= max(1, day) } ?? 0
    }

    /// Which week's trial a day of the Arc falls in.
    func trialIndex(onDay day: Int) -> Int {
        guard !trials.isEmpty else { return 0 }
        return min(trials.count - 1, (max(1, day) - 1) / 7)
    }

    /// The days of the Arc a trial covers: seven from its first, cut at the end.
    func trialDays(_ index: Int) -> ClosedRange<Int> {
        let first = index * 7 + 1
        return first...min(length, first + 6)
    }

    /// The wake time a join starts from, before anybody moves it.
    static let defaultWake = 6 * 60 + 30
}

// MARK: - The four

enum ArcCatalog {

    static let all: [ArcProgram] = [lockIn, monk, discipline, winter]

    static func program(_ id: ArcID) -> ArcProgram {
        all.first { $0.id == id } ?? lockIn
    }

    /// The winter: the first of October to the last of January, both days in.
    ///
    /// Winter Arc can be started on any day of the year; this is when it is
    /// put first and said to start today (DIRECTION_1_1 §5). A season is one
    /// of the dates people choose to start again — the fresh start effect —
    /// which is the only reason a calendar decides anything here.
    static func isWinterSeason(_ day: ForgeDay) -> Bool {
        day.month >= 10 || day.month == 1
    }

    /// The order the Arcs are offered in: in the winter, Winter Arc first.
    static func offered(on day: ForgeDay) -> [ArcProgram] {
        guard isWinterSeason(day) else { return all }
        return [winter] + all.filter { $0.id != .winter }
    }

    /// The winter an Arc started in, named for the year it began: a Winter Arc
    /// started in January belongs to the winter that began the October before.
    static func winterYear(startingOn day: ForgeDay) -> Int {
        day.month == 1 ? day.year - 1 : day.year
    }

    // MARK: Lock In 7

    /// The starter, and the onboarding's default. Seven days on the plan as it
    /// is, with the daily challenge each day.
    static let lockIn = ArcProgram(
        id: .lockIn,
        name: "Lock In 7",
        length: 7,
        summary: "Seven days on the plan you have, with the daily challenge each day.",
        why: "Seven days is short enough to see the end of from the first morning, and long enough to find out what your week can hold.",
        phases: [
            ArcPhase(
                name: "Lock in", firstDay: 1, lastDay: 7,
                line: "The plan as it is, and the daily challenge every day."
            ),
        ],
        activities: [],
        trials: [
            ArcTrial(
                title: "Five challenges",
                detail: "Finish the daily challenge on five of the seven days.",
                count: .challenges(5)
            ),
        ],
        completesAt: .fiveInSeven,
        withChallenge: true,
        reward: "Seven days kept earns the Folded Sword."
    )

    // MARK: Monk Mode 30

    static let monk = ArcProgram(
        id: .monk,
        name: "Monk Mode 30",
        length: 30,
        summary: "Thirty days of long work blocks, early nights and no short-form video.",
        why: "Thirty days of fewer, longer things: one block of real work, training, five lines at night, and a phone that sleeps somewhere else.",
        phases: [
            ArcPhase(
                name: "Clear", firstDay: 1, lastDay: 10,
                line: "Everything starts on day one. Deep work is ninety minutes a weekday."
            ),
            ArcPhase(
                name: "Deepen", firstDay: 11, lastDay: 20,
                line: "The block goes to two hours."
            ),
            ArcPhase(
                name: "Hold", firstDay: 21, lastDay: 30,
                line: "Two and a half hours, for the last ten days."
            ),
        ],
        activities: [
            ArcActivity(
                ritualID: "focus", time: .at(9 * 60),
                standards: [
                    ArcStandard(weekdays: ArcStandard.weekdays, minutes: 90),
                    ArcStandard(weekdays: ArcStandard.weekdays, minutes: 120),
                    ArcStandard(weekdays: ArcStandard.weekdays, minutes: 150),
                ]
            ),
            ArcActivity(
                ritualID: "workout", time: .at(7 * 60),
                standards: [ArcStandard(weekdays: ArcStandard.weekdays, minutes: 45)]
            ),
            ArcActivity(
                ritualID: "nightlines", time: .at(22 * 60),
                standards: [ArcStandard(weekdays: ArcStandard.everyDay)]
            ),
            ArcActivity(
                ritualID: "bedroom", time: .at(22 * 60 + 30),
                standards: [ArcStandard(weekdays: ArcStandard.everyDay)]
            ),
            ArcActivity(
                ritualID: "noshort",
                standards: [ArcStandard(weekdays: ArcStandard.everyDay)]
            ),
        ],
        trials: [
            ArcTrial(
                title: "Seven nights, phone outside",
                detail: "The phone charges in another room every night this week.",
                count: .activity("bedroom", days: 7)
            ),
            ArcTrial(
                title: "Five full blocks",
                detail: "Deep work on all five weekdays, the whole block, nothing else open.",
                count: .activity("focus", days: 5)
            ),
            ArcTrial(
                title: "Seven days without a clip",
                detail: "Not one short video, all week.",
                count: .activity("noshort", days: 7)
            ),
            ArcTrial(
                title: "Five sessions",
                detail: "Forty-five minutes of training, five times this week.",
                count: .activity("workout", days: 5)
            ),
            ArcTrial(
                title: "Both nights, five lines",
                detail: "The last two nights, written down before the phone goes out.",
                count: .activity("nightlines", days: 2)
            ),
        ]
    )

    // MARK: Discipline 66

    /// Built on Lally et al. (2010): the same few things, every day, for the
    /// median time the study found a daily behaviour took to become automatic.
    /// No ramp, on purpose — the point is sixty-six of the same day.
    static let discipline = ArcProgram(
        id: .discipline,
        name: "Discipline 66",
        length: 66,
        summary: "A fixed wake time and three things you choose, every day for sixty-six days.",
        why: "In a 2010 study of people taking up one new daily habit, it took a median of sixty-six days to feel automatic, with a wide range either side, and missing a single day did not set the process back.",
        source: "Lally, van Jaarsveld, Potts & Wardle (2010), European Journal of Social Psychology",
        phases: [
            ArcPhase(
                name: "The same thing", firstDay: 1, lastDay: 66,
                line: "Up at the same time and the three you chose, every day. Nothing ramps."
            ),
        ],
        activities: [
            ArcActivity(
                ritualID: "wake", time: .afterWake(0),
                standards: [ArcStandard(weekdays: ArcStandard.everyDay)]
            ),
        ],
        trials: [
            ArcTrial(title: "Seven wake-ups on time", detail: "Up at your wake time every morning this week.", count: .activity("wake", days: 7)),
            ArcTrial(title: "All four, five days", detail: "The wake-up and the three you chose, all done, on five days.", count: .everything(days: 5)),
            ArcTrial(title: "Six days kept", detail: "The blade pulled on six days this week.", count: .kept(days: 6)),
            ArcTrial(title: "All four, six days", detail: "Everything the Arc asks, done on six days.", count: .everything(days: 6)),
            ArcTrial(title: "Seven wake-ups on time", detail: "Up at your wake time every morning this week.", count: .activity("wake", days: 7)),
            ArcTrial(title: "All four, every day", detail: "Everything the Arc asks, done on all seven days.", count: .everything(days: 7)),
            ArcTrial(title: "Six days kept", detail: "The blade pulled on six days this week.", count: .kept(days: 6)),
            ArcTrial(title: "Seven wake-ups on time", detail: "Up at your wake time every morning this week.", count: .activity("wake", days: 7)),
            ArcTrial(title: "All four, every day", detail: "Everything the Arc asks, done on all seven days.", count: .everything(days: 7)),
            ArcTrial(title: "The last three, all four", detail: "Days 64 to 66, everything done on each.", count: .everything(days: 3)),
        ],
        asksForWake: true,
        picks: 3
    )

    // MARK: Winter Arc 90

    /// The flagship. Ninety days in four phases, built up rather than started
    /// at full weight, and promoted from the first of October to the end of
    /// January (`isWinterSeason`).
    static let winter = ArcProgram(
        id: .winter,
        name: "Winter Arc",
        length: 90,
        summary: "Ninety days through the dark months, in four phases: early mornings, training, steps, reading and deep work.",
        why: "People are more likely to start what they want for themselves at a fresh start, like a new week or a new season. Winter is one, and Monday is another.",
        source: "Dai, Milkman & Riis (2014), Management Science",
        phases: [
            ArcPhase(
                name: "Foundation", firstDay: 1, lastDay: 14,
                line: "The hours go in: the same wake time, the first half hour without the phone, everything at its smallest."
            ),
            ArcPhase(
                name: "Build", firstDay: 15, lastDay: 42,
                line: "Training goes to five days and forty-five minutes, steps to 10,000, deep work to ninety minutes."
            ),
            ArcPhase(
                name: "Harden", firstDay: 43, lastDay: 70,
                line: "An hour of training, twenty pages a night, two hours of deep work."
            ),
            ArcPhase(
                name: "Finish", firstDay: 71, lastDay: 90,
                line: "Nothing new. The last twenty days are for keeping what you built."
            ),
        ],
        activities: [
            ArcActivity(
                ritualID: "wake", time: .afterWake(0),
                standards: [ArcStandard(weekdays: ArcStandard.everyDay)]
            ),
            ArcActivity(
                ritualID: "firstthirty", time: .afterWake(0),
                standards: [ArcStandard(weekdays: ArcStandard.everyDay)]
            ),
            // Four days, then five: Monday, Tuesday, Thursday and Friday while
            // the hours go in, every weekday from Build.
            ArcActivity(
                ritualID: "workout", time: .afterWake(30),
                standards: [
                    ArcStandard(weekdays: [2, 3, 5, 6], minutes: 30),
                    ArcStandard(weekdays: ArcStandard.weekdays, minutes: 45),
                    ArcStandard(weekdays: ArcStandard.weekdays, minutes: 60),
                ]
            ),
            ArcActivity(
                ritualID: "steps",
                standards: [
                    ArcStandard(weekdays: ArcStandard.everyDay, goal: "8,000", target: 8_000),
                    ArcStandard(weekdays: ArcStandard.everyDay, goal: "10,000", target: 10_000),
                ]
            ),
            ArcActivity(
                ritualID: "focus", time: .afterWake(150),
                standards: [
                    ArcStandard(weekdays: ArcStandard.weekdays, minutes: 60),
                    ArcStandard(weekdays: ArcStandard.weekdays, minutes: 90),
                    ArcStandard(weekdays: ArcStandard.weekdays, minutes: 120),
                ]
            ),
            ArcActivity(
                ritualID: "pages", alsoCounts: ["read"], time: .at(21 * 60),
                standards: [
                    ArcStandard(weekdays: ArcStandard.everyDay, goal: "10 pages"),
                    ArcStandard(weekdays: ArcStandard.everyDay, goal: "10 pages"),
                    ArcStandard(weekdays: ArcStandard.everyDay, goal: "20 pages"),
                ]
            ),
            ArcActivity(
                ritualID: "bedroom", time: .at(22 * 60 + 30),
                standards: [ArcStandard(weekdays: ArcStandard.everyDay)]
            ),
            // One real conversation a week, on Sunday until somebody moves it.
            ArcActivity(
                ritualID: "listen",
                standards: [ArcStandard(weekdays: [1])]
            ),
        ],
        trials: [
            ArcTrial(title: "Seven wake-ups on time", detail: "Up at your wake time every morning this week.", count: .activity("wake", days: 7)),
            ArcTrial(title: "Train four times", detail: "Four sessions this week, thirty minutes each.", count: .activity("workout", days: 4)),
            ArcTrial(title: "Two cold showers", detail: "The last minute of the shower cold, twice this week. Mark each one.", count: .tally(2)),
            ArcTrial(title: "10,000 steps on five days", detail: "Check the count before dinner, five days this week.", count: .activity("steps", days: 5)),
            ArcTrial(title: "Finish one book", detail: "The last page of a book, this week. Mark it when it is shut.", count: .tally(1)),
            ArcTrial(title: "Five deep-work blocks", detail: "Ninety minutes with nothing else open, every weekday.", count: .activity("focus", days: 5)),
            ArcTrial(title: "No sugary drinks this week", detail: "No soda, no juice, no energy drinks. Mark each day you kept to it.", count: .tally(7)),
            ArcTrial(title: "Seven nights, phone outside", detail: "The phone charges in another room every night this week.", count: .activity("bedroom", days: 7)),
            ArcTrial(title: "Twenty pages, six days", detail: "Six evenings this week, twenty pages each.", count: .activity("pages", days: 6)),
            ArcTrial(title: "Three cold showers", detail: "The last minute cold, three times this week. Mark each one.", count: .tally(3)),
            ArcTrial(title: "Train five times", detail: "Five sessions this week, an hour each.", count: .activity("workout", days: 5)),
            ArcTrial(title: "The conversation you have put off", detail: "In person or on a call, this week. Mark it once it is had.", count: .tally(1)),
            ArcTrial(title: "Keep all six days", detail: "The last six days of the winter, every one kept.", count: .kept(days: 6)),
        ],
        asksForWake: true
    )
}

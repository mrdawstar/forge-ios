import Foundation

/// A practice, read back in numbers.
///
/// Everything here is derived from the same pile of `DayRecord`s the rest of the
/// app reads, on demand, exactly like `Trends` and the heatmap — nothing is
/// banked, so no figure on the analytics sheet can ever disagree with the grid
/// three inches above it.
///
/// **The rule these are written to.** A number about somebody's practice is
/// allowed to describe and is not allowed to grade. So there are no targets in
/// here, no deltas against last month, no "you're down 12%", and nothing that
/// goes red. A quiet month was a month with other things in it. What the sheet
/// is for is the question people actually have — *which of these do I keep, and
/// which do I only mean to keep* — and that one is answered honestly or not at
/// all: every rate carries the sample it was drawn from, and a rate with too
/// little behind it is not shown rather than shown small.
enum Analytics {

    /// How many days an activity has to have been asked for before its rate is
    /// worth printing. The same bar `Trends` uses, and for the same reason:
    /// below it, one good week looks like mastery.
    static let minimumSample = ProgressStore.trendMinimumSample

    // MARK: - Habits

    /// One activity's record: how often it was asked for, and how often it was
    /// actually done.
    ///
    /// The denominator is *days it was planned for*, never days elapsed. An
    /// activity added on Tuesday is not answerable for the fortnight before it
    /// existed, and one that only repeats on Mondays is not answerable for
    /// Tuesdays — that asymmetry is the whole reason this is not simply a count.
    struct HabitRate: Identifiable, Equatable, Sendable {
        let id: String
        let planned: Int
        let completed: Int

        var rate: Double { planned > 0 ? Double(completed) / Double(planned) : 0 }
        /// Whether there is enough behind this to be worth saying out loud.
        var isReadable: Bool { planned >= Analytics.minimumSample }
        var percent: Int { Int((rate * 100).rounded()) }
    }

    // MARK: - The chain, in full

    /// One unbroken run of kept days.
    ///
    /// Held as a list rather than reduced to "longest ever" because a personal
    /// best is a number whose only job is to be beaten, and which spends most of
    /// its life describing somebody the user no longer is. A *history* of runs
    /// says something kinder and truer: this is a practice that has started
    /// again several times, and that is what practices do.
    struct StreakRun: Identifiable, Equatable, Sendable {
        let start: ForgeDay
        let end: ForgeDay
        let length: Int
        /// Whether this is the run still going.
        let isCurrent: Bool

        var id: ForgeDay { start }
    }

    // MARK: - Periods

    /// A week or a month, and how much of it was kept.
    ///
    /// `possible` is days that could have been kept — inside the tracked
    /// history, already over, and not a weekday the user set aside in Settings.
    /// Without that subtraction a week containing two chosen rest days can never
    /// read above 71%, and somebody who rests on purpose would be shown a
    /// permanent shortfall for doing exactly what they decided to do.
    struct Period: Identifiable, Equatable, Sendable {
        let label: String
        let kept: Int
        let possible: Int
        /// The first day of the period, which is what orders these.
        let start: ForgeDay
        /// A period that has not begun. Empty and future are both drawn as a
        /// dash, and they are not the same fact: one is a month somebody lived
        /// through with nothing recorded, the other is a month they have not
        /// reached. Only the second is worth keeping on a timeline — see
        /// `ProgressStore.year(_:)`, which drops the first.
        var isFuture: Bool = false

        var rate: Double { possible > 0 ? Double(kept) / Double(possible) : 0 }
        var percent: Int { Int((rate * 100).rounded()) }
        /// A period with nothing in it yet — drawn as absent rather than as zero.
        var isEmpty: Bool { possible == 0 }
        var id: ForgeDay { start }
    }

    // MARK: - A year

    /// One calendar year, and the twelve months in it.
    struct Year: Equatable, Sendable {
        let year: Int
        let kept: Int
        /// Days of the year that have happened and were being tracked.
        let possible: Int
        let months: [Period]

        var rate: Double { possible > 0 ? Double(kept) / Double(possible) : 0 }
        var percent: Int { Int((rate * 100).rounded()) }
    }

    // MARK: - The headline

    /// The four numbers the sheet opens with.
    struct Summary: Equatable, Sendable {
        /// Activities finished over activities asked for, across the whole
        /// history. This is "completion rate" in the sense every other habit app
        /// means it — the granular one, not the day one.
        let activitiesCompleted: Int
        let activitiesPlanned: Int
        /// Days kept over days that could have been kept.
        let daysKept: Int
        let daysPossible: Int

        var completionRate: Double {
            activitiesPlanned > 0
                ? Double(activitiesCompleted) / Double(activitiesPlanned) : 0
        }
        var dayRate: Double {
            daysPossible > 0 ? Double(daysKept) / Double(daysPossible) : 0
        }
        var completionPercent: Int { Int((completionRate * 100).rounded()) }
        var dayPercent: Int { Int((dayRate * 100).rounded()) }
        /// Nothing has been recorded yet, so every rate below is 0/0 and the
        /// sheet should say so in words rather than print three zeroes.
        var isEmpty: Bool { activitiesPlanned == 0 && daysPossible == 0 }
    }
}

// MARK: - Reading it out of the history

extension ProgressStore {

    /// The first day anything was recorded. Everything measured "over the whole
    /// history" is measured from here rather than from an install date, which is
    /// not stored and would be the wrong answer anyway on a restored phone.
    var firstTrackedDay: ForgeDay? { byDay.keys.min() }

    /// Whether a day counts toward a denominator: inside the tracked history,
    /// already finished, and not a weekday deliberately set aside.
    ///
    /// Today is excluded on purpose, everywhere. A day is not missed until it is
    /// over — the same rule the streak walk uses — and counting an unfinished
    /// morning as a shortfall would make every rate on the sheet dip at
    /// midnight and recover by evening.
    func countsTowardRate(_ day: ForgeDay) -> Bool {
        guard let first = firstTrackedDay else { return false }
        guard day >= first, day < currentDay else { return false }
        return !restWeekdays.contains(day.weekday)
    }

    /// Every activity the history has ever asked for, most recently planned
    /// first.
    ///
    /// Read out of the record rather than off the day's current list, so an
    /// activity somebody has since taken out of their day can still be the
    /// subject of a milestone they are part-way through — and so this needs no
    /// second source of truth handed in from the Forge tab.
    var knownActivityIDs: [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for record in records.reversed() {
            for id in record.plannedIDs where !seen.contains(id) {
                seen.insert(id)
                ordered.append(id)
            }
        }
        return ordered
    }

    /// How many days this activity was finished on, ever.
    ///
    /// Days rather than "times", and they are the same number: an activity can
    /// only be completed once in a day — `complete(_:method:)` guards on it — so
    /// "Meditate 100 times" and "Meditate 100 days" ask for exactly the same
    /// thing. The unit is a matter of how somebody wants it worded, which is why
    /// `MilestoneUnit` is presentation and this is arithmetic.
    func timesCompleted(_ ritualID: String) -> Int {
        byDay.values.count { $0.completedIDs.contains(ritualID) }
    }

    /// Every activity's record, best first.
    func habitRates() -> [Analytics.HabitRate] {
        var planned: [String: Int] = [:]
        var completed: [String: Int] = [:]
        for record in byDay.values {
            let done = record.completedIDs
            for id in Set(record.plannedIDs) {
                planned[id, default: 0] += 1
                if done.contains(id) { completed[id, default: 0] += 1 }
            }
        }
        return planned
            .map { Analytics.HabitRate(id: $0.key, planned: $0.value, completed: completed[$0.key] ?? 0) }
            // Rate first, then sample, then id — so the order is total and two
            // habits sitting at 100% cannot swap places between redraws.
            .sorted {
                if $0.rate != $1.rate { return $0.rate > $1.rate }
                if $0.planned != $1.planned { return $0.planned > $1.planned }
                return $0.id < $1.id
            }
    }

    /// The habits worth drawing conclusions from, best first.
    func readableHabitRates() -> [Analytics.HabitRate] {
        habitRates().filter(\.isReadable)
    }

    /// Every run of kept days, longest first.
    ///
    /// Rest days count as *continuing* a run rather than as part of it — the
    /// chain is unbroken, so the run is one run, but a day nobody kept is not
    /// added to its length. That is the same bargain `computeStreakState` makes,
    /// and the two must agree or the sheet would contradict the number on the
    /// card above it.
    func streakRuns() -> [Analytics.StreakRun] {
        guard let oldest = firstTrackedDay else { return [] }
        let earned = Set(byDay.values.filter(\.isEarned).map(\.day))
        let rested = streakState.restDays

        var runs: [Analytics.StreakRun] = []
        var start: ForgeDay?
        var last: ForgeDay?
        var length = 0
        var cursor = oldest

        func close(current: Bool) {
            if let start, let last, length > 0 {
                runs.append(
                    Analytics.StreakRun(start: start, end: last, length: length, isCurrent: current)
                )
            }
            start = nil
            last = nil
            length = 0
        }

        while cursor <= currentDay {
            defer { cursor = cursor.adding(days: 1) }

            if earned.contains(cursor) {
                if start == nil { start = cursor }
                last = cursor
                length += 1
                continue
            }
            // Carried, not broken: a chosen rest weekday, a day a banked rest
            // covered, or today, which is not over.
            if restWeekdays.contains(cursor.weekday)
                || rested.contains(cursor)
                || cursor == currentDay {
                continue
            }
            close(current: false)
        }
        close(current: true)

        return runs.sorted {
            if $0.length != $1.length { return $0.length > $1.length }
            return $0.start > $1.start
        }
    }

    // MARK: - Summary

    /// Every day the sheet may draw a rate from, oldest first.
    ///
    /// One list, so that every figure on the overview is a fraction of the same
    /// thing. Two of them were not, and both were wrong in a way somebody would
    /// see:
    ///
    /// - The activity tally ran over **every** record, today's included, so the
    ///   completion rate counted an unfinished morning as a shortfall and sagged
    ///   at four in the morning, recovering by evening. That is the exact
    ///   failure `countsTowardRate` was written to prevent, happening in the
    ///   figure printed beside the one it protects.
    /// - `daysKept` counts every earned day and `daysPossible` excluded rest
    ///   weekdays, so a numerator and a denominator from two different sets were
    ///   being divided. Somebody who keeps their rest days could read **over a
    ///   hundred per cent**; on the very first day it read `1 of 0` and printed
    ///   0%, because the one day kept was today and today was not in the
    ///   denominator.
    ///
    /// Today is in the list only once it has been **earned** — which is the same
    /// rule stated from the other side. An unfinished today is not a miss, and a
    /// finished one is not a day to leave out of the count of days kept.
    func ratedDays() -> [ForgeDay] {
        guard let first = firstTrackedDay else { return [] }
        var days: [ForgeDay] = []
        var cursor = first
        while cursor < currentDay {
            defer { cursor = cursor.adding(days: 1) }
            if countsTowardRate(cursor) { days.append(cursor) }
        }
        if isTodayEarned { days.append(currentDay) }
        return days
    }

    func analyticsSummary() -> Analytics.Summary {
        var planned = 0
        var completed = 0
        var kept = 0
        var possible = 0

        for day in ratedDays() {
            possible += 1
            guard let record = byDay[day] else { continue }
            if record.isEarned { kept += 1 }
            planned += record.plannedCount
            completed += min(record.completedCount, record.plannedCount)
        }

        return Analytics.Summary(
            activitiesCompleted: completed,
            activitiesPlanned: planned,
            daysKept: kept,
            daysPossible: possible
        )
    }

    // MARK: - Consistency

    /// The last `weeks` weeks, oldest first, each starting on the user's own
    /// first weekday so the columns line up with the heatmap above them.
    func weeklyConsistency(weeks: Int = 12, calendar: Calendar = .current) -> [Analytics.Period] {
        let weekdayIndex = (currentDay.weekday - calendar.firstWeekday + 7) % 7
        let thisWeek = currentDay.adding(days: -weekdayIndex)

        return stride(from: weeks - 1, through: 0, by: -1).map { back in
            let start = thisWeek.adding(days: -back * 7)
            return period(
                from: start,
                to: start.adding(days: 6),
                label: Self.weekFormat.string(from: start.startOfDay())
            )
        }
    }

    /// The last `months` calendar months, oldest first.
    func monthlyConsistency(months: Int = 12, calendar: Calendar = .current) -> [Analytics.Period] {
        let today = currentDay.startOfDay()
        return stride(from: months - 1, through: 0, by: -1).compactMap { back in
            guard let anchor = calendar.date(byAdding: .month, value: -back, to: today),
                  let range = calendar.dateInterval(of: .month, for: anchor)
            else { return nil }
            return monthPeriod(range: range, anchor: anchor, calendar: calendar)
        }
    }

    /// Years with anything in them, most recent first. Empty until something
    /// has been recorded, which is what keeps the year picker from offering a
    /// year nobody has lived in the app.
    func availableYears(calendar: Calendar = .current) -> [Int] {
        Set(byDay.keys.map(\.year)).sorted(by: >)
    }

    /// One calendar year, from the month the record starts in to December.
    ///
    /// # Why it does not start in January
    ///
    /// It did, and for somebody who installed Forge in September that drew eight
    /// rows of grey dash — months they had lived through, in an app they did not
    /// have, presented as part of their record. There is no reading of those
    /// rows that is useful and one that is actively misleading: an empty bar in
    /// a list of bars looks like a month somebody let slide.
    ///
    /// **The months ahead stay.** They are empty for the opposite reason — not
    /// yet reached rather than not recorded — and that is the half of a year
    /// worth showing: the timeline runs from where somebody actually started to
    /// the end of the year in front of them. `Period.isFuture` is what lets the
    /// list say which kind of empty a month is.
    ///
    /// Nothing is trimmed off the totals, because what is trimmed is zeros.
    func year(_ year: Int, calendar: Calendar = .current) -> Analytics.Year {
        let first = firstTrackedDay
        var months: [Analytics.Period] = []

        for month in 1...12 {
            var parts = DateComponents()
            parts.year = year
            parts.month = month
            parts.day = 1
            guard let anchor = calendar.date(from: parts),
                  let range = calendar.dateInterval(of: .month, for: anchor)
            else { continue }

            let period = monthPeriod(range: range, anchor: anchor, calendar: calendar)
            // Everything before the record began, dropped rather than drawn as
            // an empty month. The comparison is on the month's *last* day, so
            // the month somebody started in is kept whole.
            if let first {
                let last = ForgeDay.containing(
                    range.end.addingTimeInterval(-1), calendar: calendar, dayStartHour: 0
                )
                if last < first { continue }
            }
            months.append(period)
        }

        return Analytics.Year(
            year: year,
            kept: months.reduce(0) { $0 + $1.kept },
            possible: months.reduce(0) { $0 + $1.possible },
            months: months
        )
    }

    /// The last `days` days ending **yesterday**, one `ForgeHeatMark` a day,
    /// oldest first — the trail the widgets draw their grid from.
    ///
    /// # Why it stops at yesterday
    ///
    /// Because today is the one day that can change after this is written. The
    /// snapshot already carries today twice over (`fraction`, `isEarned`) and
    /// the widget draws today's square from those; if today were in here as
    /// well there would be two answers to the same question in one file, and
    /// the stale one would be the one on the Home Screen at four in the
    /// afternoon.
    ///
    /// # Why the bucketing happens here
    ///
    /// So there is one of it. The extension compiles `Shared/` and `ForgeDay`
    /// and nothing else, so a grid drawn over there off raw fractions would be a
    /// second implementation of `ForgeHeatLevel.of` — and the first time the two
    /// disagreed by a step it would be on the Home Screen next to the Blade tab
    /// that disagrees with it.
    ///
    /// Days before the record begins are `ForgeHeatMark.beforeRecord`, never
    /// `none`: an empty square for a day Forge was not installed on is the app
    /// telling somebody they failed a day it was not there for.
    func heatTrail(days: Int, calendar: Calendar = .current) -> (start: ForgeDay, marks: [Int]) {
        let start = currentDay.adding(days: -days)
        guard days > 0 else { return (start, []) }

        let rested = streakState.restDays
        let first = firstTrackedDay
        var marks: [Int] = []
        marks.reserveCapacity(days)

        for offset in 0..<days {
            let day = start.adding(days: offset)
            if let first, day < first {
                marks.append(ForgeHeatMark.beforeRecord)
                continue
            }
            guard let record = byDay[day] else {
                // Inside the record and nothing written: a day that happened
                // and was not kept, unless a banked rest covered it.
                marks.append(ForgeHeatMark(
                    level: rested.contains(day) ? .rest : .none, wasKept: false
                ).raw)
                continue
            }
            marks.append(ForgeHeatMark(
                level: .of(record.fraction, isRest: rested.contains(day)),
                wasKept: record.isEarned
            ).raw)
        }

        return (start, marks)
    }

    /// The grid for a whole calendar year, in the same shape the twelve-week
    /// card draws — so one view renders both and they can never drift apart.
    ///
    /// Weeks rather than months across, deliberately. A year laid out as twelve
    /// blocks of thirty-ish squares has no line the eye can follow; a year laid
    /// out as columns of seven has fifty-three of them, and the row a day sits
    /// in is always the same weekday.
    func yearHeatmap(_ year: Int, calendar: Calendar = .current) -> Heatmap {
        var parts = DateComponents()
        parts.year = year
        parts.month = 1
        parts.day = 1
        guard let firstOfYear = calendar.date(from: parts) else {
            return Heatmap(columns: [], restColumns: [], start: currentDay, end: currentDay, earnedCount: 0)
        }
        let january = ForgeDay.containing(firstOfYear, calendar: calendar, dayStartHour: 0)
        // Back to the top of the week January the first falls in, so every
        // column is a whole week and the rows stay one weekday each.
        let lead = (january.weekday - calendar.firstWeekday + 7) % 7
        let start = january.adding(days: -lead)

        let rested = streakState.restDays
        var columns: [[Double]] = []
        var restColumns: [[Bool]] = []
        var earned = 0

        for week in 0..<53 {
            var column: [Double] = []
            var restColumn: [Bool] = []
            for offset in 0..<7 {
                let day = start.adding(days: week * 7 + offset)
                // Outside the year, or not yet lived: an empty cell either way.
                guard day.year == year, day <= currentDay, let record = byDay[day] else {
                    restColumn.append(day.year == year && rested.contains(day))
                    column.append(0)
                    continue
                }
                restColumn.append(rested.contains(day))
                if record.isEarned { earned += 1 }
                column.append(record.fraction)
            }
            columns.append(column)
            restColumns.append(restColumn)
        }

        // The weeks before anything was recorded are dropped, for the same
        // reason the months are — see `year(_:)`. Thirty-five blank columns in
        // front of somebody's first September is not their year, and the grid
        // scrolls sideways, so those columns were also thirty-five columns of
        // nothing between the reader and their own record. The weeks *ahead*
        // stay: the year in front of you is the half worth seeing.
        var gridStart = start
        if let first = firstTrackedDay, first.year == year {
            let lead = columns.indices.first { week in
                (0..<7).contains { start.adding(days: week * 7 + $0) >= first }
            }
            if let lead, lead > 0 {
                columns.removeFirst(lead)
                restColumns.removeFirst(lead)
                gridStart = start.adding(days: lead * 7)
            }
        }

        return Heatmap(
            columns: columns,
            restColumns: restColumns,
            start: gridStart,
            end: min(currentDay, january.adding(days: 364)),
            earnedCount: earned
        )
    }

    // MARK: - Shared arithmetic

    private func monthPeriod(
        range: DateInterval, anchor: Date, calendar: Calendar
    ) -> Analytics.Period {
        let first = ForgeDay.containing(range.start, calendar: calendar, dayStartHour: 0)
        // `end` is the first instant of the next month, so a second is stepped
        // back off it to land inside this one.
        let last = ForgeDay.containing(
            range.end.addingTimeInterval(-1), calendar: calendar, dayStartHour: 0
        )
        return period(from: first, to: last, label: Self.shortMonthFormat.string(from: anchor))
    }

    private func period(from first: ForgeDay, to last: ForgeDay, label: String) -> Analytics.Period {
        var kept = 0
        var possible = 0
        var cursor = first
        while cursor <= last {
            defer { cursor = cursor.adding(days: 1) }
            guard countsTowardRate(cursor) else { continue }
            possible += 1
            if byDay[cursor]?.isEarned == true { kept += 1 }
        }
        return Analytics.Period(
            label: label,
            kept: kept,
            possible: possible,
            start: first,
            isFuture: first > currentDay
        )
    }

    private static let shortMonthFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter
    }()

    private static let weekFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }()
}


// MARK: - The Forge Shape

/// Six dimensions of a person, scored on what they have actually been doing.
///
/// # What this is for
///
/// Forge could say how *much* somebody had done — days kept, completion, the
/// chain — and nothing at all about what those days had been about. The Shape
/// is the answer to the question a practice raises after about a month of it:
/// **which parts of me are getting stronger, and which are getting nothing.**
///
/// # The scoring, and why it is built this way
///
/// Each dimension scores 0–100 over a rolling window of `window` days:
///
///     score = 100 × (kept / asked) × min(1, asked / presenceFloor)
///
/// - `asked` is **days the dimension was planned**, not days elapsed. A
///   dimension taken up last week is not answerable for the month before it
///   existed — the same fairness rule `HabitRate` and identity evidence follow.
/// - `kept` is **days at least one of its activities was completed**. Days, not
///   completions: stacking six activities into Physical cannot inflate it,
///   because doing all six on one Tuesday is one day of Physical. This is the
///   single most important anti-gaming property here and it is the same rule
///   identity evidence has always used.
/// - `presenceFloor` stops the other obvious exploit. Without it somebody could
///   plan one easy thing once, do it, and hold a perfect hundred forever. Eight
///   days in twenty-eight is roughly twice a week — the least that can honestly
///   be called a part of somebody's life — and below it the score is scaled
///   down in proportion. Plan once and keep it and the dimension reads twelve,
///   which is a true description of one day in a month.
///
/// **It can go down.** That is deliberate and it is the difference between this
/// and every number Forge had before. Days kept is cumulative and can never
/// fall, which is what makes it safe to lead with. A Shape that could only rise
/// would be a trophy cabinet; one that reflects the last four weeks is a mirror,
/// and a mirror is the only thing that can tell somebody something they did not
/// already know.
///
/// **Nothing here is stored.** Every figure is derived on read from the same
/// `DayRecord`s as everything else, so the Shape cannot drift from the history
/// behind it.
struct ForgeShape: Equatable, Sendable {

    /// The rolling window. Four weeks: long enough that one bad week does not
    /// redraw the whole shape, short enough that it is describing who somebody
    /// is now rather than who they were in March.
    static let window = 28
    /// Days inside the window at which a dimension counts as fully present.
    static let presenceFloor = 8
    /// The half-window each side of the direction comparison.
    static let half = 14

    /// Which way a dimension has moved between the last fortnight and the one
    /// before it.
    enum Direction: Equatable, Sendable {
        case rising, steady, slipping
        /// Not enough behind it to say. Never rendered as an arrow.
        case unknown

        var label: String {
            switch self {
            case .rising: "Rising"
            case .steady: "Steady"
            case .slipping: "Slipping"
            case .unknown: "Early"
            }
        }

        var symbol: String? {
            switch self {
            case .rising: "arrow.up.right"
            case .slipping: "arrow.down.right"
            case .steady, .unknown: nil
            }
        }
    }

    struct Dimension: Identifiable, Equatable, Sendable {
        let category: RitualCategory
        /// 0–100.
        let score: Int
        /// Weighted days in the window it was planned for. Fractional because a
        /// day fed only by a secondary contribution is worth less than one — see
        /// `Ritual.dimensionWeights`.
        let asked: Double
        /// Weighted days in the window it was actually kept.
        let kept: Double
        /// How many activities somebody currently keeps in it.
        let activityCount: Int
        let direction: Direction

        var id: String { category.rawValue }
        /// Whether anything at all is filed here.
        var hasActivities: Bool { activityCount > 0 }
        /// Whether the record can say anything about it yet.
        var isMeasured: Bool { asked > 0 }
        /// 0…1, for drawing.
        var fraction: Double { Double(score) / 100 }
    }

    /// All six, always, in `RitualCategory.dimensions` order.
    ///
    /// **Empty dimensions are present rather than omitted**, and that is the
    /// point of a shape rather than a list. A polygon with a flat side says
    /// something no ranked list can: there is a whole part of this that nothing
    /// is pointing at. Dropping it would answer "where am I strong" and refuse
    /// the more useful half.
    let dimensions: [Dimension]

    /// The overall state, and it is a mean of all six rather than of the ones in
    /// use.
    ///
    /// Averaging only the measured dimensions would mean somebody who does one
    /// thing well scores higher than somebody doing five things well and one
    /// badly, which is precisely backwards for a reading whose whole subject is
    /// breadth. The cost is that a beginner's number is low; that is handled by
    /// not showing the Shape at all until there is something to show, rather
    /// than by flattering the arithmetic.
    var overall: Int {
        guard !dimensions.isEmpty else { return 0 }
        return Int((Double(dimensions.map(\.score).reduce(0, +)) / Double(dimensions.count)).rounded())
    }

    /// The word under the number. Describes the *direction of the whole*, not a
    /// grade — there is no band here called "poor".
    var state: Direction {
        let measured = dimensions.filter(\.isMeasured)
        guard measured.count >= 2 else { return .unknown }
        let rising = measured.count { $0.direction == .rising }
        let slipping = measured.count { $0.direction == .slipping }
        if rising > slipping { return .rising }
        if slipping > rising { return .slipping }
        return .steady
    }

    /// The strongest dimension anything is filed under.
    var strongest: Dimension? {
        dimensions.filter(\.isMeasured).max { $0.score < $1.score }
    }

    /// The one to look at next.
    ///
    /// **Only ever a dimension somebody actually keeps something in.** A
    /// dimension nothing is filed under is not being neglected — it is simply
    /// not part of this practice yet, and naming it would be the app inventing
    /// an obligation nobody agreed to. The same rule
    /// `ReviewObservation.neglectedIdentity` follows.
    var needsAttention: Dimension? {
        let candidates = dimensions.filter { $0.hasActivities && $0.isMeasured }
        guard candidates.count > 1 else { return nil }
        guard let weakest = candidates.min(by: { $0.score < $1.score }) else { return nil }
        // Not worth naming when everything is level: "Physical needs attention"
        // on a shape where every side reads 80 is the app manufacturing a
        // problem to give itself something to say.
        guard let best = candidates.max(by: { $0.score < $1.score }),
              best.score - weakest.score >= 15
        else { return nil }
        return weakest
    }

    /// A dimension nothing has ever been filed under, if there is one. What the
    /// next-step row offers when everything measured is already level.
    var untouched: Dimension? {
        dimensions.first { !$0.hasActivities }
    }

    /// Whether there is enough here to draw.
    ///
    /// Two measured dimensions and a week of record. A polygon drawn on three
    /// days of history is a shape the app made up, and the first impression of
    /// the whole feature would be a nearly-empty hexagon that says the person is
    /// nothing yet.
    var isReadable: Bool {
        dimensions.count { $0.isMeasured } >= 2
            && dimensions.map(\.kept).reduce(0, +) >= 5
    }

    /// Rounded whole days, for saying out loud. Nobody wants to be told they
    /// kept 4.2 days of anything.
    static func spokenDays(_ credited: Double) -> Int { Int(credited.rounded()) }

    /// A few concrete things that would feed a dimension, none of which the
    /// user already keeps.
    ///
    /// # Why this is a filter over the library and not a new system
    ///
    /// Because the library *is* the recommendation set. Twenty-seven of these
    /// were already written, filed and effort-ranked, and twelve more were added
    /// when the dimensions arrived precisely so that every side of the shape has
    /// something honest to offer. A separate table of "suggestions" would be a
    /// second list of activities to keep in step with the first, and the first
    /// time they drifted the app would be recommending something that could not
    /// be added.
    ///
    /// **Three, never more.** The instruction this was built to was that
    /// Becoming must not become a catalogue — there is already a catalogue, it
    /// is one tap away behind the day editor, and its job is browsing. This
    /// is the opposite job: the smallest number of specific things that would
    /// move the weakest side of somebody's shape, offered at the moment the app
    /// has just explained why that side is weak.
    ///
    /// Ordered by effort ascending, so the first thing offered to somebody who
    /// is already struggling in an area is the smallest one.
    static func suggestions(
        for category: RitualCategory, avoiding kept: Set<String>, limit: Int = 3
    ) -> [Ritual] {
        Ritual.library
            .filter { $0.category == category && !kept.contains($0.id) }
            .sorted { IdentityActivities.effort(of: $0.id) < IdentityActivities.effort(of: $1.id) }
            .prefix(limit)
            .map { $0 }
    }
}

extension ProgressStore {

    /// Read the Shape off the history, given what somebody currently keeps.
    ///
    /// Takes the activities rather than reaching for them, so this stays a pure
    /// function of the record and the day — testable without a view model, the
    /// same shape as every other reading in this file.
    func forgeShape(of activities: [Ritual]) -> ForgeShape {
        let last = currentDay.adding(days: -1)
        let windowStart = currentDay.adding(days: -ForgeShape.window)
        let midpoint = currentDay.adding(days: -ForgeShape.half)

        // Every activity's contribution to every dimension, resolved once
        // rather than per dimension per day.
        let weights = activities.reduce(into: [String: [RitualCategory: Double]]()) {
            $0[$1.id] = $1.dimensionWeights
        }

        let dimensions = RitualCategory.dimensions.map { category in
            let contributing = weights.filter { $0.value[category] != nil }
            let weightFor = contributing.mapValues { $0[category] ?? 0 }

            let asked = creditedDays(weightFor, from: windowStart, to: last, planned: true)
            let kept = creditedDays(weightFor, from: windowStart, to: last, planned: false)

            return ForgeShape.Dimension(
                category: category,
                score: ForgeShape.score(kept: kept, asked: asked),
                asked: asked,
                kept: kept,
                // The count somebody would recognise: activities *filed* here,
                // not everything that happens to touch it. A row reading "four
                // activities" when the user can only find one under this
                // heading would be the app arguing with its own editor.
                activityCount: activities.count { $0.category == category },
                direction: direction(
                    weightFor, midpoint: midpoint, last: last, start: windowStart
                )
            )
        }
        return ForgeShape(dimensions: dimensions)
    }

    /// Which way one dimension has moved across the two halves of the window.
    ///
    /// Both halves have to have been asked for before this says anything. A
    /// dimension taken up nine days ago has an empty first half, and calling
    /// that "rising" would be reporting the moment it was created as progress.
    /// Weighted days in a window: for each day, the **strongest** contribution
    /// any qualifying activity made to this dimension.
    ///
    /// The `max` is what keeps the day the unit. Summing contributions instead
    /// would mean six physical activities on one Tuesday credited six times over
    /// — the exact exploit the whole model is built to refuse — so a day is
    /// worth at most one, and worth less when the only thing feeding the
    /// dimension that day was a secondary.
    private func creditedDays(
        _ weights: [String: Double], from first: ForgeDay, to last: ForgeDay, planned: Bool
    ) -> Double {
        guard !weights.isEmpty else { return 0 }
        return byDay.values.reduce(into: 0.0) { total, record in
            guard record.day >= first, record.day <= last else { return }
            let ids = planned ? Set(record.plannedIDs) : record.completedIDs
            let best = ids.compactMap { weights[$0] }.max() ?? 0
            total += best
        }
    }

    private func direction(
        _ weights: [String: Double], midpoint: ForgeDay, last: ForgeDay, start: ForgeDay
    ) -> ForgeShape.Direction {
        guard !weights.isEmpty else { return .unknown }
        let priorEnd = midpoint.adding(days: -1)
        let recentAsked = creditedDays(weights, from: midpoint, to: last, planned: true)
        let priorAsked = creditedDays(weights, from: start, to: priorEnd, planned: true)
        guard recentAsked > 0, priorAsked > 0 else { return .unknown }

        let recent = ForgeShape.score(
            kept: creditedDays(weights, from: midpoint, to: last, planned: false),
            asked: recentAsked,
            floor: Double(ForgeShape.presenceFloor) / 2
        )
        let prior = ForgeShape.score(
            kept: creditedDays(weights, from: start, to: priorEnd, planned: false),
            asked: priorAsked,
            floor: Double(ForgeShape.presenceFloor) / 2
        )
        // Eight points of noise either way is not a trend. Two kept days out of
        // fourteen moves a score by about that much, and a fortnight that
        // happened to contain one head cold should not be reported as decline.
        if recent - prior > 8 { return .rising }
        if prior - recent > 8 { return .slipping }
        return .steady
    }
}

extension ForgeShape {

    /// The scoring function, in one place so the dimension and its direction
    /// cannot be computed two different ways.
    static func score(
        kept: Double, asked: Double, floor: Double = Double(ForgeShape.presenceFloor)
    ) -> Int {
        guard asked > 0, floor > 0 else { return 0 }
        let rate = kept / asked
        let presence = min(1, asked / floor)
        return Int((100 * rate * presence).rounded())
    }
}

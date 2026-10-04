import SwiftUI

/// Everything the app knows about what you have actually done.
///
/// One pile of `DayRecord`s, and every number on every screen derived from
/// it on read. Nothing here banks a streak or a total: the entire class of bug
/// where the badge says twelve and the calendar shows nine cannot happen if
/// there is only one number and it is computed.
@Observable
final class ProgressStore {

    /// Keyed rather than kept in an array so a day is one lookup. The array is
    /// only the storage format.
    private(set) var byDay: [ForgeDay: DayRecord] = [:] {
        didSet { streakMemo = nil }
    }

    /// The hour a day begins. Before it, you are still in yesterday.
    var dayStartHour: Int = 4 {
        didSet {
            guard dayStartHour != oldValue else { return }
            persistSettings()
            rollOver()
        }
    }

    /// Weekdays (1 = Sunday) the ritual is deliberately skipped. They neither
    /// break a streak nor extend one — Settings promises exactly that, so the
    /// streak has to honour it.
    var restWeekdays: Set<Int> = [] {
        didSet {
            guard restWeekdays != oldValue else { return }
            streakMemo = nil
            persistSettings()
        }
    }

    /// Which day the app currently believes it is. Only `rollOver` moves it.
    private(set) var currentDay: ForgeDay {
        didSet { streakMemo = nil }
    }

    private let defaults: UserDefaults
    /// Suppresses the `didSet` writes that loading would otherwise trigger.
    private var isLoaded = false

    /// Every daily challenge finished, by day. See `KeptChallenge`.
    ///
    /// Kept here rather than by `ChallengeStore` because it is the same kind of
    /// fact as everything else in this file — a thing somebody did on a day —
    /// and because what reads it is the Shape, which reads this store. The
    /// challenge store still holds only today's challenge and its state; it
    /// writes here when that state reaches `completed` and when it leaves it.
    private(set) var challengesKept: [ForgeDay: KeptChallenge] = [:]

    private enum Key {
        static let history = "forge.history.v1"
        static let dayStartHour = "forge.dayStartHour.v1"
        static let restDays = "forge.restDays.v1"
        static let challenges = "forge.challengesKept.v1"
    }

    /// `defaults` is injectable so tests get a scratch suite instead of
    /// scribbling on the simulator's real one.
    init(defaults: UserDefaults = ForgeShared.defaults) {
        self.defaults = defaults
        self.currentDay = ForgeDay.containing(.now, dayStartHour: 4)
        load()
        rollOver()
    }

    // MARK: - Clock

    #if DEBUG
    /// Days added to the real clock. Streak logic cannot be tested by waiting a
    /// month for it, so in debug builds the whole app reads the date from here.
    var debugDayOffset: Int = 0 {
        didSet {
            guard debugDayOffset != oldValue else { return }
            rollOver()
        }
    }
    #endif

    var now: Date {
        #if DEBUG
        Calendar.current.date(byAdding: .day, value: debugDayOffset, to: .now) ?? .now
        #else
        .now
        #endif
    }

    // MARK: - Storage

    private func load() {
        defer { isLoaded = true }

        // One day at a time (§17.7). It was all or nothing: one record that
        // did not read emptied the whole history, and the next write saved the
        // empty one over it. A day that does not read, or is no day anybody
        // could have had, is dropped; every other day is kept.
        if let data = defaults.data(forKey: Key.history),
           let decoded = try? JSONDecoder().decode(LossyList<DayRecord>.self, from: data) {
            let days = decoded.elements.filter(\.day.isPlausible)
            byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { _, latest in latest })
        }
        if defaults.object(forKey: Key.dayStartHour) != nil {
            dayStartHour = defaults.integer(forKey: Key.dayStartHour)
        }
        if let rest = defaults.array(forKey: Key.restDays) as? [Int] {
            restWeekdays = Set(rest)
        }
        if let data = defaults.data(forKey: Key.challenges) {
            challengesKept = Dictionary(
                KeptChallenge.decodeAll(data).map { ($0.day, $0) },
                uniquingKeysWith: { _, latest in latest }
            )
        }
    }

    private func persistHistory() {
        guard isLoaded else { return }
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Key.history)
    }

    private func persistChallenges() {
        guard isLoaded else { return }
        let kept = challengesKept.values.sorted { $0.day < $1.day }
        guard let data = try? JSONEncoder().encode(kept) else { return }
        defaults.set(data, forKey: Key.challenges)
    }

    // MARK: - The challenge, kept

    /// A challenge was finished on its day. One per day: a second for the same
    /// day replaces the first, because there is one challenge a day.
    func keepChallenge(_ challenge: DailyChallenge, on day: ForgeDay, at instant: Date) {
        let kept = KeptChallenge(day: day, id: challenge.id, focus: challenge.focus, at: instant)
        guard challengesKept[day] != kept else { return }
        challengesKept[day] = kept
        persistChallenges()
    }

    /// The day's finished challenge is not finished after all — undone,
    /// skipped, or swapped for another.
    func releaseChallenge(on day: ForgeDay) {
        guard challengesKept[day] != nil else { return }
        challengesKept[day] = nil
        persistChallenges()
    }

    /// Which of the six each day's finished challenge fed — what the Shape
    /// credits. See `ForgeShape.crediting`.
    var challengeCredit: [ForgeDay: RitualCategory] {
        challengesKept.mapValues(\.focus.category)
    }

    private func persistSettings() {
        guard isLoaded else { return }
        defaults.set(dayStartHour, forKey: Key.dayStartHour)
        defaults.set(Array(restWeekdays), forKey: Key.restDays)
    }

    // MARK: - Reading

    /// Oldest first — the storage order, and the order everything iterating
    /// history wants.
    var records: [DayRecord] { byDay.values.sorted { $0.day < $1.day } }

    var today: DayRecord { byDay[currentDay] ?? DayRecord(day: currentDay) }

    /// The oldest day the history holds anything for.
    ///
    /// Forge writes today's record the first time it opens — the day's planned
    /// list goes down before anything is done (`ForgeViewModel.publishPlanned`)
    /// — so on any install this is the day the app was first opened, read out
    /// of the record rather than kept beside it. Nil only before that first
    /// write.
    var firstRecordedDay: ForgeDay? { byDay.keys.min() }

    /// Days between the first record and today. Zero on the first day, and
    /// zero before there is a record at all. What telemetry reports as
    /// `days_since_install` — see `ForgeTelemetry`.
    var daysSinceFirstRecord: Int {
        firstRecordedDay.map { max(0, currentDay.days(since: $0)) } ?? 0
    }

    /// The instant this day began — the window anything measuring the day
    /// has to be read over. Four in the morning, not midnight.
    var currentDayStart: Date {
        let midnight = currentDay.startOfDay()
        return Calendar.current.date(
            bySettingHour: dayStartHour, minute: 0, second: 0, of: midnight
        ) ?? midnight
    }

    var todayCompletedIDs: Set<String> { today.completedIDs }
    /// The order today's activities were finished in, so a done row drops to the
    /// bottom of the list rather than to the bottom of its own original slot.
    var todayCompletedOrder: [String] { today.completions.map(\.ritualID) }
    var isTodayEarned: Bool { today.isEarned }

    private var earnedDays: Set<ForgeDay> {
        Set(byDay.values.filter(\.isEarned).map(\.day))
    }

    /// Days kept, ever. The number Forge leads with: it counts up and never
    /// down, so it survives a bad week intact and there is nothing in it to
    /// protect.
    var daysKept: Int { earnedDays.count }
    var totalRituals: Int { byDay.values.reduce(0) { $0 + $1.completedCount } }

    /// The rung of the one ladder somebody is standing on. See `Ladder`.
    var rung: LadderRung { Ladder.current(daysKept: daysKept) }

    // MARK: - Over a window
    //
    // A chapter is a window laid over the history rather than a container for
    // part of it — see `Chapter` — so everything it reports has to be answerable
    // as "this arithmetic, between these two days". These three are that, and
    // they are the only bounded readings anything needs: kept, asked-for, and
    // evidence.

    /// Days earned between two days, inclusive. Cumulative inside its window and
    /// impossible to reduce, like every other count this store hands out.
    func daysKept(from first: ForgeDay, to last: ForgeDay) -> Int {
        byDay.values.count { $0.isEarned && $0.day >= first && $0.day <= last }
    }

    /// Of everything asked for inside the window, how much was done. 0…1.
    ///
    /// Weighted by activity rather than by day, the same arithmetic
    /// `analyticsSummary` uses: a day that asked for six things and finished
    /// three is half a day, not a whole one and not a zero. Days that asked for
    /// nothing are left out of both halves — an empty day is not a failed one.
    func completionRate(from first: ForgeDay, to last: ForgeDay) -> Double {
        let inside = byDay.values.filter { $0.day >= first && $0.day <= last }
        let planned = inside.reduce(0) { $0 + $1.plannedCount }
        guard planned > 0 else { return 0 }
        let done = inside.reduce(0) { $0 + min($1.completedCount, $1.plannedCount) }
        return Double(done) / Double(planned)
    }

    /// Days inside the window on which at least one of these was completed.
    /// Days, not completions — see the unbounded version for why.
    func daysOfEvidence(
        taggedTo activities: Set<String>, from first: ForgeDay, to last: ForgeDay
    ) -> Int {
        guard !activities.isEmpty else { return 0 }
        return byDay.values.count {
            $0.day >= first && $0.day <= last
                && !$0.completedIDs.isDisjoint(with: activities)
        }
    }

    /// Days inside the window that asked for at least one of these.
    ///
    /// The denominator to the above, and the reason a week with no run in it
    /// reads as "nothing asked" rather than as "nothing done" — see
    /// `ReviewObservation.neglectedIdentity`, which will not call an identity
    /// neglected on a week it was never on the list.
    func daysAsking(
        for activities: Set<String>, from first: ForgeDay, to last: ForgeDay
    ) -> Int {
        guard !activities.isEmpty else { return 0 }
        return byDay.values.count {
            $0.day >= first && $0.day <= last
                && !Set($0.plannedIDs).isDisjoint(with: activities)
        }
    }

    /// Days inside the window that asked for anything at all.
    ///
    /// An empty day is not a failed one, so it is not in the denominator of
    /// anything — the same rule `completionRate(from:to:)` follows.
    func daysAsking(from first: ForgeDay, to last: ForgeDay) -> Int {
        byDay.values.count { $0.day >= first && $0.day <= last && $0.plannedCount > 0 }
    }

    /// What each weekday has actually done over the trailing window.
    ///
    /// The arithmetic behind the one observation somebody could not have made
    /// themselves — everybody knows how their week went, and almost nobody
    /// knows which weekday has been quietly costing them for a month. See
    /// `ReviewObservation.weekdaySplit`.
    ///
    /// Weekdays the user has set aside in Settings are left out entirely. A day
    /// deliberately not kept is not a day that went badly, and reporting it as
    /// the worst weekday of the month would be the app failing to read its own
    /// settings back.
    func weekdayFacts(weeks: Int, endingOn last: ForgeDay) -> [ReviewFacts.Weekday] {
        let first = last.adding(days: -(weeks * 7 - 1))
        var asked: [Int: Int] = [:]
        var kept: [Int: Int] = [:]
        for record in byDay.values where record.day >= first && record.day <= last {
            guard record.plannedCount > 0, !isRestDay(record.day) else { continue }
            asked[record.day.weekday, default: 0] += 1
            if record.isEarned { kept[record.day.weekday, default: 0] += 1 }
        }
        return asked.keys.sorted().map {
            ReviewFacts.Weekday(weekday: $0, kept: kept[$0] ?? 0, asked: asked[$0] ?? 0)
        }
    }

    /// Every activity the window asked for, with what it did.
    func habitCounts(from first: ForgeDay, to last: ForgeDay) -> [(id: String, planned: Int, completed: Int)] {
        var planned: [String: Int] = [:]
        var completed: [String: Int] = [:]
        for record in byDay.values where record.day >= first && record.day <= last {
            for id in Set(record.plannedIDs) {
                planned[id, default: 0] += 1
                if record.completedIDs.contains(id) { completed[id, default: 0] += 1 }
            }
        }
        return planned.keys.sorted().map { ($0, planned[$0] ?? 0, completed[$0] ?? 0) }
    }

    // MARK: - Coming back

    /// The most recent day that was actually kept.
    var lastKeptDay: ForgeDay? { earnedDays.max() }

    /// How long it has been since a day was kept, in days.
    ///
    /// Nil for somebody who has never kept one — there is nothing to have
    /// returned from, and the re-entry screen must not greet a stranger as
    /// though they had lapsed. Zero for a day kept today.
    ///
    /// Deliberately **not** the streak. The streak is a number that can go down
    /// and the whole point of the return screen is that nothing on it can; this
    /// is a distance, used once, to decide whether to say anything at all. See
    /// `ReEntry`.
    var daysSinceLastKept: Int? {
        lastKeptDay.map { currentDay.days(since: $0) }
    }

    private func isRestDay(_ day: ForgeDay) -> Bool {
        restWeekdays.contains(day.weekday)
    }

    // MARK: - The chain

    /// How many days buy one rest day.
    static let daysPerRest = 7
    /// How many can be held at once. A ceiling rather than a balance: rest is
    /// for the week you are ill, not a currency to save up, and a number that
    /// grows without limit turns into one more thing to protect.
    static let maxBankedRest = 2

    /// Everything the chain is, worked out in one pass.
    ///
    /// Derived, like every other number in Forge. A banked rest day is not
    /// stored anywhere — it is a fact about the history, and storing it would
    /// create the one bug this whole store exists to prevent: a balance that
    /// disagrees with the days it was supposedly earned from.
    /// There is no `longest` here, and its absence is the point.
    ///
    /// A longest streak is a personal best, which is a number whose only job is
    /// to be beaten and which spends most of its life describing somebody the
    /// user no longer is. It was taken off the summary card for exactly that
    /// reason and then went on being computed, stored in this struct and shown
    /// on the analytics sheet — so the app was still keeping a high score, one
    /// screen further back. The field is gone rather than hidden: a value that
    /// exists is a value the next screen puts back on a card.
    ///
    /// What survives is `streakRuns()`, which is a *history* of chains rather
    /// than a trophy for the best one. Reading "you have kept eleven runs, the
    /// last four of them longer than a fortnight" is a description of a
    /// practice; "LONGEST: 34" is a record to protect.
    struct StreakState: Equatable {
        var current = 0
        /// Rest days in hand, 0…`maxBankedRest`.
        var banked = 0
        /// Every day a banked rest has ever covered. The heatmap draws
        /// these differently from misses, because a chain that is unbroken and
        /// a grid with a hole in it would be the app contradicting itself.
        var restDays: Set<ForgeDay> = []
        /// The most recent rest inside the run that is still going. Cleared by
        /// a break, so nothing offers somebody a day off they took before a
        /// chain they have already lost.
        var lastRest: ForgeDay?
    }

    /// Memoised because the walk is over the whole history and the streak is
    /// read on every frame the scene draws.
    ///
    /// `@ObservationIgnored` matters: without it, filling the cache during a
    /// view's body would count as a mutation of observed state and invalidate
    /// the very view that just read it.
    @ObservationIgnored private var streakMemo: StreakState?

    var streakState: StreakState {
        if let streakMemo { return streakMemo }
        let computed = computeStreakState()
        streakMemo = computed
        return computed
    }

    /// Consecutive earned days ending today — or yesterday, if today is not
    /// finished yet. A day is not missed until it is over, so an untouched
    /// day at 9am does not read as a broken chain.
    var currentStreak: Int { streakState.current }
    /// Rest days earned and not yet spent.
    var bankedRest: Int { streakState.banked }
    /// The last day rest covered, if the chain it belongs to is still alive.
    var lastRestDay: ForgeDay? { streakState.lastRest }

    /// Walk the whole history forwards, once.
    ///
    /// Forwards rather than backwards, which is what the streak used to do, for
    /// one reason: the cap. Banking is capped at the moment it happens, so
    /// twenty-eight unbroken days hold two rest days and not four, and that
    /// can only be worked out by replaying the days in the order they were
    /// lived. Counting milestones backwards and subtracting what was spent gets
    /// the wrong answer the first time somebody rests after hitting the ceiling.
    private func computeStreakState() -> StreakState {
        let earned = earnedDays
        guard let oldest = byDay.keys.min() else { return StreakState() }

        var state = StreakState()
        var run = 0
        var sinceBank = 0
        var cursor = oldest

        while cursor <= currentDay {
            defer { cursor = cursor.adding(days: 1) }

            if earned.contains(cursor) {
                run += 1
                sinceBank += 1
                if sinceBank == Self.daysPerRest {
                    // Reset even when the bank is full, so resting once does not
                    // hand back a replacement on the same day.
                    sinceBank = 0
                    state.banked = min(state.banked + 1, Self.maxBankedRest)
                }
                continue
            }

            // A weekday the user set aside in Settings. It was never a day,
            // so it neither breaks the chain nor costs a banked rest.
            if isRestDay(cursor) { continue }

            // Today has not been missed. It is not over.
            if cursor == currentDay { continue }

            // A day that was missed, and there is something to cover it.
            if state.banked > 0 {
                state.banked -= 1
                state.restDays.insert(cursor)
                state.lastRest = cursor
                continue
            }

            run = 0
            sinceBank = 0
            state.lastRest = nil
        }

        state.current = run
        return state
    }

    /// How often an activity gets finished on the days it was actually part
    /// of. An activity added yesterday is not punished for the fortnight before
    /// it existed.
    func completionRate(for ritualID: String) -> Double {
        let planned = byDay.values.filter { $0.plannedIDs.contains(ritualID) }
        guard !planned.isEmpty else { return 0 }
        let done = planned.filter { $0.completedIDs.contains(ritualID) }.count
        return Double(done) / Double(planned.count)
    }

    // MARK: - Evidence

    // What the record says about a *direction* rather than a volume. See
    // `Identity`.
    //
    // All three take the set of activity ids tagged to an identity rather than
    // the identity's own id, and that is deliberate rather than awkward. A
    // `DayRecord` holds activity ids and nothing else; which identity an
    // activity belongs to is a property of `Ritual`, which lives behind
    // `ForgeViewModel` because a user-made activity only resolves there. Giving
    // this store a way to reach that would put a view model inside the one type
    // whose whole value is that it is a pile of records and some arithmetic —
    // and it is the same reason `BladeViewModel` takes a resolver and
    // `MilestoneStore.measured` takes a closure.
    //
    // So the resolution happens one level up and these stay pure. The
    // identity-named wrappers are on `ForgeViewModel`, which is the object that
    // can actually answer the question.

    /// Days on which at least one of these activities was completed.
    ///
    /// Counted in **days, not completions**. Somebody who trained and read and
    /// journalled on Tuesday, all three tagged to the same identity, has one
    /// day of evidence for it and not three — the unit of this whole app is a
    /// day, and a figure that rewarded stacking activities would quietly turn
    /// an identity into a score.
    ///
    /// Cumulative by construction, so it can never go down on a bad week.
    func daysOfEvidence(taggedTo activities: Set<String>) -> Int {
        guard !activities.isEmpty else { return 0 }
        return byDay.values.count { !$0.completedIDs.isDisjoint(with: activities) }
    }

    /// How often evidence actually appears on the days it was asked for.
    ///
    /// The same shape as `completionRate(for:)` and the same fairness rule: the
    /// denominator is days one of these activities was *planned*, so an identity
    /// named last week is not punished for the months before it existed.
    func evidenceRate(taggedTo activities: Set<String>) -> Double {
        guard !activities.isEmpty else { return 0 }
        let planned = byDay.values.filter { !Set($0.plannedIDs).isDisjoint(with: activities) }
        guard !planned.isEmpty else { return 0 }
        let met = planned.count { !$0.completedIDs.isDisjoint(with: activities) }
        return Double(met) / Double(planned.count)
    }

    /// The first day any of these was completed — where the evidence starts.
    ///
    /// Read off the record rather than off the identity's `createdAt`, and the
    /// two genuinely differ: somebody who has been running for a year and names
    /// "Someone who trains" today has a year of evidence, not none. Naming a
    /// thing is not the same as starting it, and the record is the honest
    /// answer to which one happened first.
    func firstEvidence(taggedTo activities: Set<String>) -> ForgeDay? {
        guard !activities.isEmpty else { return nil }
        return byDay.values
            .filter { !$0.completedIDs.isDisjoint(with: activities) }
            .map(\.day)
            .min()
    }

    /// Days earned before a given time of day, read in the timezone the
    /// user is in now. Good enough for an achievement and wrong for nothing
    /// else.
    func daysEarned(before hour: Int, minute: Int, calendar: Calendar = .current) -> Int {
        byDay.values.filter { record in
            guard let at = record.extractedAt else { return false }
            let parts = calendar.dateComponents([.hour, .minute], from: at)
            guard let h = parts.hour, let m = parts.minute else { return false }
            return h < hour || (h == hour && m <= minute)
        }.count
    }

    // MARK: - Trends

    /// What a long record says that a short one cannot.
    ///
    /// Every reading here needs months behind it to mean anything, which is
    /// exactly why this is the thing Premium buys: it is not a feature being
    /// withheld, it is a feature that does not exist until somebody has been
    /// keeping days for a while.
    ///
    /// Nothing in here is a target and nothing is a score. It is a description
    /// of a practice — which months were fuller, which day of the week holds up
    /// best, which activity actually survives contact with a real day.
    struct Trends: Equatable {
        struct Month: Equatable, Identifiable {
            let label: String
            let kept: Int
            var id: String { label }
        }

        /// Oldest first, one entry per calendar month.
        var months: [Month] = []
        /// The weekday kept most often, 1 = Sunday. Nil until there is enough
        /// history for one day to be meaningfully ahead of the others.
        var steadiestWeekday: Int?
        /// The activity finished on the greatest share of the days it was
        /// actually part of, and that share.
        var mostKept: (id: String, rate: Double)?

        /// The tuple is not `Equatable` for free.
        static func == (lhs: Trends, rhs: Trends) -> Bool {
            lhs.months == rhs.months
                && lhs.steadiestWeekday == rhs.steadiestWeekday
                && lhs.mostKept?.id == rhs.mostKept?.id
        }
    }

    /// How many days an activity has to have been planned for before its
    /// rate is worth reading. Below this a single good week looks like mastery.
    static let trendMinimumSample = 5

    func trends(months monthCount: Int = 6, calendar: Calendar = .current) -> Trends {
        var trends = Trends()
        let earned = earnedDays

        // MARK: Months
        //
        // Walked from the current month backwards through real calendar months
        // rather than in 30-day blocks, so the labels line up with the months
        // somebody actually lived.
        let today = currentDay.startOfDay()
        for back in stride(from: monthCount - 1, through: 0, by: -1) {
            guard let anchor = calendar.date(byAdding: .month, value: -back, to: today),
                  let range = calendar.dateInterval(of: .month, for: anchor)
            else { continue }

            let first = ForgeDay.containing(range.start, calendar: calendar, dayStartHour: 0)
            // `end` is the first instant of the next month, so a day is stepped
            // back off it to land on the last day of this one.
            let last = ForgeDay.containing(
                range.end.addingTimeInterval(-1), calendar: calendar, dayStartHour: 0
            )

            // Months that ended before anything was recorded are not part of
            // this person's six — the same rule `year(_:)` follows, and for the
            // same reason: an empty bar in a row of bars reads as a month
            // somebody let slide rather than as one they did not have the app
            // for. The window is still "the last six months"; it is simply
            // clipped to the record, so a young history draws three bars rather
            // than three bars and three hairlines.
            if let start = firstTrackedDay, last < start { continue }

            var kept = 0
            var cursor = first
            while cursor <= last {
                if earned.contains(cursor) { kept += 1 }
                cursor = cursor.adding(days: 1)
            }
            trends.months.append(
                Trends.Month(label: Self.monthFormat.string(from: anchor), kept: kept)
            )
        }

        // MARK: Weekday
        //
        // Counted over the whole history rather than the window above: which day
        // holds up is a fact about somebody's week, and a wider sample is a
        // better answer to it.
        var byWeekday: [Int: Int] = [:]
        for day in earned { byWeekday[day.weekday, default: 0] += 1 }
        let ranked = byWeekday.sorted { $0.value > $1.value }
        if let top = ranked.first, top.value >= Self.trendMinimumSample {
            // A tie is not an answer. Saying "Tuesdays" when Tuesday and Friday
            // are level would be inventing a pattern out of a coin toss.
            let isClear = ranked.dropFirst().first.map { $0.value < top.value } ?? true
            if isClear { trends.steadiestWeekday = top.key }
        }

        // MARK: Activity
        var best: (id: String, rate: Double)?
        for id in Set(byDay.values.flatMap(\.plannedIDs)) {
            let planned = byDay.values.filter { $0.plannedIDs.contains(id) }
            guard planned.count >= Self.trendMinimumSample else { continue }
            let rate = Double(planned.filter { $0.completedIDs.contains(id) }.count)
                / Double(planned.count)
            if rate > (best?.rate ?? 0) { best = (id, rate) }
        }
        trends.mostKept = best

        return trends
    }

    private static let monthFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter
    }()

    // MARK: - Heatmap

    struct Heatmap {
        /// Twelve columns of seven, oldest week first, each column running down
        /// the week from the user's own first weekday.
        let columns: [[Double]]
        /// The same grid again, marking the days a banked rest covered. An
        /// empty cell where the chain carried on would read as a hole the app
        /// had failed to notice.
        let restColumns: [[Bool]]
        let start: ForgeDay
        let end: ForgeDay
        /// Days actually earned inside the window.
        let earnedCount: Int
    }

    func heatmap(weeks: Int = 12, calendar: Calendar = .current) -> Heatmap {
        // Wind back to the top of this week, then back again to the first week
        // in the window, so the last column is the week in progress.
        let weekdayIndex = (currentDay.weekday - calendar.firstWeekday + 7) % 7
        let start = currentDay.adding(days: -(weekdayIndex + (weeks - 1) * 7))

        let rested = streakState.restDays
        var columns: [[Double]] = []
        var restColumns: [[Bool]] = []
        var earned = 0
        for week in 0..<weeks {
            var column: [Double] = []
            var restColumn: [Bool] = []
            for offset in 0..<7 {
                let day = start.adding(days: week * 7 + offset)
                restColumn.append(rested.contains(day))
                // The rest of this week has not happened yet.
                guard day <= currentDay, let record = byDay[day] else {
                    column.append(0)
                    continue
                }
                if record.isEarned { earned += 1 }
                column.append(record.fraction)
            }
            columns.append(column)
            restColumns.append(restColumn)
        }
        return Heatmap(
            columns: columns,
            restColumns: restColumns,
            start: start,
            end: currentDay,
            earnedCount: earned
        )
    }

    // MARK: - The week

    /// One day, as the week strip draws it.
    struct WeekDay: Identifiable, Equatable {
        let day: ForgeDay
        /// 0…1 of what that day asked for. Zero for a day that has not happened.
        let fraction: Double
        let isEarned: Bool
        /// Covered by a banked rest, so an empty cell in an unbroken chain does
        /// not read as a hole the app failed to notice.
        let isRest: Bool
        /// A weekday deliberately set aside in Settings.
        let isSetAside: Bool
        let isToday: Bool
        /// Not yet lived. Drawn as absence rather than as a miss.
        let isFuture: Bool

        var id: ForgeDay { day }
    }

    /// The week the app is currently in, from the user's own first weekday.
    ///
    /// Here rather than in the view for the same reason `heatmap` is: it is
    /// arithmetic over the history, it has a rest-day rule and a rollover in it,
    /// and both of those are things worth being able to test without a screen.
    func week(calendar: Calendar = .current) -> [WeekDay] {
        let weekdayIndex = (currentDay.weekday - calendar.firstWeekday + 7) % 7
        let start = currentDay.adding(days: -weekdayIndex)
        return (0..<7).map { weekDay(start.adding(days: $0)) }
    }

    /// One day, in the form the week strip draws.
    ///
    /// Extracted from `week()` so the weekly review can draw *its* seven days —
    /// which end on the review weekday rather than on the calendar's first one
    /// — out of the same arithmetic. Two constructions of this value would
    /// eventually disagree about what a rest day looks like, on two screens
    /// showing the same week.
    func weekDay(_ day: ForgeDay) -> WeekDay {
        let record = byDay[day]
        return WeekDay(
            day: day,
            fraction: day <= currentDay ? (record?.fraction ?? 0) : 0,
            isEarned: record?.isEarned ?? false,
            isRest: streakState.restDays.contains(day),
            isSetAside: isRestDay(day),
            isToday: day == currentDay,
            isFuture: day > currentDay
        )
    }

    // MARK: - Writing

    /// Records what the day is made of today. Called whenever the list
    /// changes, so a day's denominator is whatever it was on the day.
    func setPlanned(_ ritualIDs: [String]) {
        var record = today
        guard record.plannedIDs != ritualIDs else { return }
        record.plannedIDs = ritualIDs
        write(record)
    }

    func complete(_ ritualID: String, method: VerificationMethod) {
        var record = today
        guard !record.completedIDs.contains(ritualID) else { return }
        record.completions.append(
            DayRecord.Completion(ritualID: ritualID, method: method, at: now)
        )
        write(record)
    }

    func undo(_ ritualID: String) {
        var record = today
        guard record.completedIDs.contains(ritualID) else { return }
        record.completions.removeAll { $0.ritualID == ritualID }
        write(record)
    }

    /// Days before the first run finished on which nothing was done.
    ///
    /// A new install writes today's plan the moment it opens (`setPlanned`),
    /// before anybody can keep anything: the first run is still on screen, and
    /// since 1.1 a hard paywall stands between it and the day. Somebody who
    /// stops at the paywall and finishes three days later — or whose first run
    /// crosses four in the morning — would begin with a day that was never
    /// theirs to keep: a miss in the heatmap, a day asked and not kept in the
    /// six, the start of every rate (1.1 release pass, FORGE_CONTEXT §17.7).
    /// When the first run finishes, those go: every day before `day` that
    /// planned something and had nothing done in it. Nothing done is nothing
    /// lost.
    func forgetUnstartedDays(before day: ForgeDay) {
        let unstarted = byDay.values.filter {
            $0.day < day && $0.completions.isEmpty && $0.extractedAt == nil
        }
        guard !unstarted.isEmpty else { return }
        for record in unstarted { byDay[record.day] = nil }
        persistHistory()
    }

    /// The blade came free. This is what makes a day count.
    func markEarned() {
        var record = today
        guard record.extractedAt == nil else { return }
        record.extractedAt = now
        write(record)
    }

    /// The blade went back into the stone.
    func clearEarned() {
        var record = today
        guard record.extractedAt != nil else { return }
        record.extractedAt = nil
        write(record)
    }

    #if DEBUG
    /// The single write path, opened up so tests can lay down a history without
    /// living through it. The app never calls this — its mutations go through
    /// the intent-named methods above.
    func record(_ record: DayRecord) { write(record) }
    #endif

    private func write(_ record: DayRecord) {
        var stamped = record
        // The one place a day is dated. Every mutation above funnels
        // through here, so there is no path by which a record can change and
        // fail to say when — which is the only thing that lets two phones agree
        // about one Tuesday.
        stamped.updatedAt = now

        // An empty record is not a day; dropping it keeps the history a
        // list of what happened rather than a list of dates.
        if stamped.isEmpty && stamped.plannedIDs.isEmpty {
            byDay[stamped.day] = nil
        } else {
            byDay[stamped.day] = stamped
        }
        persistHistory()
    }

    // MARK: - Sync

    /// Take on a merged history wholesale.
    ///
    /// Deliberately not `write`: these records arrive already dated, by a merge
    /// that decided which version of each day survives, and re-stamping them
    /// here would destroy the very ordering that decision was made with — every
    /// day would look like it changed the moment it landed, and the next
    /// pass would send the whole history back up.
    ///
    /// A replacement rather than a union, because the merge has already done
    /// the uniting and handing it a second opinion here would be two answers
    /// again.
    func adopt(_ records: [DayRecord]) {
        let merged = Dictionary(
            records.map { ($0.day, $0) }, uniquingKeysWith: { _, latest in latest }
        )
        guard merged != byDay else { return }
        byDay = merged
        persistHistory()
    }

    /// Settings that came down from another device.
    ///
    /// One call rather than two assignments, so a change to the day's start
    /// rolls the day over exactly once instead of once per property.
    func adopt(dayStartHour hour: Int, restWeekdays rest: Set<Int>) {
        let changed = dayStartHour != hour || restWeekdays != rest
        guard changed else { return }
        restWeekdays = rest
        dayStartHour = hour
    }

    // MARK: - Rollover

    /// Move the app on to the day it actually is.
    ///
    /// Nothing is reset and nothing is recomputed, because nothing was stored:
    /// today's state *is* whichever record sits under `currentDay`, so a new day
    /// starts empty by construction and yesterday keeps whatever it earned.
    func rollOver() {
        let day = ForgeDay.containing(now, dayStartHour: dayStartHour)
        guard day != currentDay else { return }
        currentDay = day
    }

    // MARK: - Debug

    #if DEBUG
    /// Fills in a plausible history so streaks, levels and the heatmap can be
    /// looked at without living through a season of them.
    func seedSyntheticHistory(days: Int = 84, planned: [String] = Ritual.defaultActive) {
        var seeded: [ForgeDay: DayRecord] = [:]

        for back in 1...days {
            let day = currentDay.adding(days: -back)
            // Three kinds of day, so the heatmap has partials to shade and the
            // streak has real breaks in it rather than one unbroken block.
            let roll = Int.random(in: 0..<100)
            guard roll >= 18 else { continue }
            let earned = roll >= 33

            let base = day.startOfDay()
            let at = Calendar.current.date(
                bySettingHour: Int.random(in: 5...8),
                minute: Int.random(in: 0..<60),
                second: 0,
                of: base
            ) ?? base
            let finished = earned ? planned.count : Int.random(in: 1..<max(2, planned.count))

            seeded[day] = DayRecord(
                day: day,
                completions: planned.prefix(finished).map {
                    DayRecord.Completion(
                        ritualID: $0,
                        method: Ritual.find($0)?.verification ?? .honor,
                        at: at
                    )
                },
                plannedIDs: planned,
                extractedAt: earned ? at : nil
            )
        }

        // Today is left exactly as the user left it.
        let mine = byDay[currentDay]
        byDay = seeded
        byDay[currentDay] = mine
        persistHistory()
    }

    func clearHistory() {
        byDay = [:]
        challengesKept = [:]
        persistHistory()
        persistChallenges()
    }
    #endif
}

import SwiftUI

/// Display state for the Blade tab.
///
/// Owns nothing. The collection and the equipped blade live in `SwordStore`;
/// every number on this screen is read straight out of `ProgressStore` on
/// demand. The only thing here that is genuinely this tab's own business is
/// which page of the stats carousel is showing.
@Observable
final class BladeViewModel {
    private let progress: ProgressStore
    /// Turns an activity id into the activity, including one the user made.
    private let resolve: (String) -> Ritual?
    /// Which activities carry a given identity.
    ///
    /// Handed in for the same reason `resolve` is: an activity's `identityID`
    /// lives on `Ritual`, which only resolves through `ForgeViewModel`, and this
    /// screen has no business holding the Forge tab's day. What comes back is
    /// fed straight to `ProgressStore`, which counts days and knows nothing
    /// about identities — see the note above `daysOfEvidence(taggedTo:)`.
    private let tagged: (String) -> Set<String>

    /// The markers somebody set for themselves.
    ///
    /// Owned here rather than at the root, and that is a deliberate exception to
    /// this class owning nothing. Custom milestones are read and written on this
    /// screen and nowhere else — no widget draws one, the Live Activity has
    /// never heard of them, and the Forge tab does not care — so hoisting the
    /// store into `ContentView` would put a dependency in front of four other
    /// screens to serve one.
    let milestones = MilestoneStore()

    var statPage: Int = 0
    /// The analytics sheet, which is where everything that needs room lives.
    var showAnalytics = false

    init(
        progress: ProgressStore,
        resolve: @escaping (String) -> Ritual?,
        tagged: @escaping (String) -> Set<String> = { _ in [] }
    ) {
        self.progress = progress
        self.resolve = resolve
        self.tagged = tagged
    }

    // MARK: - So far

    var daysKept: Int { progress.daysKept }
    var streak: Int { progress.currentStreak }
    var totalRituals: Int { progress.totalRituals }

    // MARK: - The ladder

    /// The rung somebody is standing on.
    var rung: LadderRung { Ladder.current(daysKept: daysKept) }

    /// The next one up. Nil never happens in practice — the ladder generates
    /// itself past a thousand days — and is handled anyway.
    var nextRung: LadderRung? { Ladder.rung(after: daysKept) }

    /// How far between this rung and the next, 0…1.
    var rungProgress: Double { Ladder.progress(daysKept: daysKept) }

    /// What the blade looks like now. Derived from days kept on every read.
    var bladeState: BladeState { Ladder.state(daysKept: daysKept) }

    /// "Forty days to go" — what stands between here and the next rung.
    ///
    /// Said as a distance rather than as a percentage, because a percentage of
    /// a practice is a completion bar and this is not a thing being completed.
    var nextRungLabel: String? {
        guard let next = nextRung else { return nil }
        let remaining = max(0, next.threshold - daysKept)
        guard remaining > 0 else { return nil }
        return remaining == 1 ? "One day to go" : "\(remaining) days to go"
    }

    // MARK: - Who you're becoming

    /// What the record says about one identity. All three figures are read out
    /// of `ProgressStore` on demand and none is stored anywhere.
    struct IdentityEvidence: Equatable {
        let days: Int
        /// Where the record starts, not when the sentence was written — see
        /// `ProgressStore.firstEvidence(taggedTo:)`.
        let since: String?
        let hasActivities: Bool
    }

    func evidence(for identity: Identity) -> IdentityEvidence {
        let activities = tagged(identity.id)
        return IdentityEvidence(
            days: progress.daysOfEvidence(taggedTo: activities),
            since: progress.firstEvidence(taggedTo: activities).map(Self.monthName),
            hasActivities: !activities.isEmpty
        )
    }

    // MARK: - The chapter

    func reading(for chapter: Chapter) -> ChapterReading { chapter.reading(from: progress) }

    func evidence(for identity: Identity, in chapter: Chapter) -> Int {
        chapter.evidence(taggedTo: tagged(identity.id), from: progress)
    }

    /// Where a chapter is in its six weeks, in the words somebody would use.
    func place(of chapter: Chapter) -> String {
        chapter.placeLabel(dayStartHour: progress.dayStartHour, today: progress.currentDay)
    }

    func progress(of chapter: Chapter) -> Double {
        chapter.progress(dayStartHour: progress.dayStartHour, today: progress.currentDay)
    }

    // MARK: - Rest

    /// One quiet line, and only when there is something true to say.
    ///
    /// It lives here rather than on the home screen because the home screen is
    /// for today, and rest is always about a day that has already gone.
    ///
    /// Written to close the subject rather than open it. No count of how many
    /// days until the next one, no warning that the last one is about to be
    /// spent, no celebration of a streak surviving — those are the shapes that
    /// turn a chain into something to be anxious about, which is the thing that
    /// actually makes people leave.
    var restNote: String? {
        let banked = progress.bankedRest

        if let last = progress.lastRestDay, wasRecent(last) {
            guard banked > 0 else { return "You'd earned a day off." }
            return "You'd earned a day off. \(Self.count(banked)) still in hand."
        }

        guard banked > 0 else { return nil }
        return "\(Self.count(banked)) in hand. Seven days earns another."
    }

    /// Recent enough to be worth explaining. A rest spent a fortnight ago is
    /// simply how the chain ran, and repeating it forever would make a day off
    /// feel like something on somebody's record.
    private func wasRecent(_ day: ForgeDay) -> Bool {
        progress.currentDay.days(since: day) <= ProgressStore.daysPerRest
    }

    /// The cap is two, so these are the only numbers this ever has to say.
    private static func count(_ banked: Int) -> String {
        banked == 1 ? "One rest day" : "\(banked) rest days"
    }

    /// What the summary is measured from — the first day on record, rather
    /// than a date somebody typed into the layout.
    var since: String {
        guard let first = progress.records.first?.day else { return "No days yet" }
        return "Since \(BladeViewModel.dayFormat.string(from: first.startOfDay()))"
    }

    // MARK: - Milestones

    /// The ones somebody made, unreached first.
    var customMilestones: [Milestone] {
        milestones.measured(in: progress) { [resolve] id in resolve(id)?.label }
    }

    /// Every activity a milestone could be about, in the words the user knows
    /// them by.
    ///
    /// Read out of the history rather than off today's list, which is what lets
    /// this exist without the Blade tab being handed the Forge tab's day. An
    /// activity taken out of the day last month is still a fair subject for a
    /// milestone somebody is part-way through, and one added this morning is
    /// already here — `publishPlanned` writes today's list the moment it
    /// changes.
    var milestoneSubjects: [(id: String, name: String)] {
        progress.knownActivityIDs.compactMap { id in
            guard let ritual = resolve(id) else { return nil }
            return (id, ritual.label)
        }
    }

    func activityName(_ id: String) -> String? { resolve(id)?.label }

    /// Notice anything reached while the app was away, and queue its
    /// congratulation. Cheap enough to call on every appearance.
    func refreshMilestones() {
        milestones.refresh(against: progress)
    }

    func addMilestone(_ draft: MilestoneDraft) {
        milestones.add(draft)
        // A milestone somebody sets *having already done the work* is reached
        // the instant it exists — "read 30 days" typed on day forty is true —
        // and it should say so rather than waiting for the next launch.
        refreshMilestones()
    }

    func updateMilestone(_ id: String, to draft: MilestoneDraft) {
        milestones.update(id, to: draft)
        refreshMilestones()
    }

    func deleteMilestone(_ id: String) {
        milestones.delete(id)
    }

    /// The draft that edits an existing one.
    func draft(for id: String) -> MilestoneDraft? {
        guard let made = milestones.custom.first(where: { $0.id == id }) else { return nil }
        return MilestoneDraft(
            name: made.name, symbol: made.symbol,
            subject: made.subject, unit: made.unit, target: made.target
        )
    }

    // MARK: - Analytics

    var summary: Analytics.Summary { progress.analyticsSummary() }
    var habitRates: [Analytics.HabitRate] { progress.readableHabitRates() }
    var streakRuns: [Analytics.StreakRun] { progress.streakRuns() }
    var availableYears: [Int] { progress.availableYears() }

    func weekly(_ weeks: Int = 12) -> [Analytics.Period] { progress.weeklyConsistency(weeks: weeks) }
    func monthly(_ months: Int = 12) -> [Analytics.Period] { progress.monthlyConsistency(months: months) }
    func year(_ year: Int) -> Analytics.Year { progress.year(year) }
    func yearHeatmap(_ year: Int) -> ProgressStore.Heatmap { progress.yearHeatmap(year) }

    /// The year the sheet opens on: the one the app is currently in.
    var currentYear: Int { progress.currentDay.year }

    /// The best and worst habit, when there is enough behind both to say so.
    ///
    /// Nil rather than a placeholder when there is one habit or none — a
    /// "worst" that is also the best is not a finding, it is the same row twice
    /// with a crueller label on it.
    var habitExtremes: (best: Analytics.HabitRate, worst: Analytics.HabitRate)? {
        let readable = habitRates
        guard readable.count >= 2, let best = readable.first, let worst = readable.last else {
            return nil
        }
        // Everything at the same rate is not a spread, and naming one of them
        // "worst" would be inventing a difference out of a tie.
        guard best.rate > worst.rate else { return nil }
        return (best, worst)
    }

    /// An activity's name for the analytics sheet, falling back to something
    /// readable rather than to an id if it has since been deleted.
    /// The activity with the most days behind it, where one stands out.
    ///
    /// # Why a rate is not an answer to "what do I actually do"
    ///
    /// The habits list is ranked by rate, which answers *what holds* — and on a
    /// day of sixteen activities that is the only question it answers. An
    /// activity asked for four times and kept four times sits at the top on
    /// 100%; the run somebody has done sixty times out of ninety sits well down
    /// the list on 67%. Both readings are true and only one of them is what the
    /// person actually does.
    ///
    /// So the row with the largest `completed` is marked. It is one word on a
    /// row that is already there rather than a second list — the ranking stays
    /// the ranking, and the volume stops being invisible.
    ///
    /// Nil when nothing stands out: fewer than two habits, or a tie for the
    /// most, because naming one of two equals is inventing a difference.
    var mostKeptHabit: Analytics.HabitRate? {
        let readable = habitRates
        guard readable.count >= 2 else { return nil }
        let ranked = readable.sorted { $0.completed > $1.completed }
        guard let top = ranked.first, top.completed > 0 else { return nil }
        guard ranked.dropFirst().first?.completed != top.completed else { return nil }
        return top
    }

    /// The day the record starts, and how much of it there is.
    ///
    /// Every rate on the sheet is a fraction of this, and it was the one thing
    /// the overview did not say. See `AnalyticsSheet.overview` for what it
    /// replaced.
    var recordStart: ForgeDay? { progress.firstTrackedDay }

    func habitName(_ rate: Analytics.HabitRate) -> String {
        resolve(rate.id)?.label ?? "Removed activity"
    }

    // MARK: - Heatmap

    /// The grid, over the window everybody gets.
    ///
    /// This used to take a number of weeks decided by what had been bought.
    /// Nothing on this screen depends on that any more: the chain, the count,
    /// the milestones, the grid and the trends are all read over the whole
    /// history, for everybody, permanently.
    ///
    /// Twelve because that is roughly a season, which is the shortest window in
    /// which a practice starts to look like a practice rather than a fortnight.
    /// The constant used to live on `FreeTier`, which is the last trace of the
    /// grid having once been something people paid to widen.
    static let historyWeeks = 12

    var heatmap: ProgressStore.Heatmap {
        progress.heatmap(weeks: Self.historyWeeks)
    }

    func heatCount(_ heatmap: ProgressStore.Heatmap) -> String {
        heatmap.earnedCount == 1 ? "1 day" : "\(heatmap.earnedCount) days"
    }

    let heatWindow = "LAST TWELVE WEEKS"

    static func shortDate(_ day: ForgeDay) -> String {
        gridFormat.string(from: day.startOfDay()).uppercased()
    }

    // MARK: - Trends

    var trends: ProgressStore.Trends { progress.trends() }

    /// The steadiest weekday, spelled out. Nil when the history has not yet said
    /// anything a person could rely on.
    var steadiestDay: String? {
        guard let weekday = trends.steadiestWeekday else { return nil }
        let symbols = Calendar.current.weekdaySymbols
        guard symbols.indices.contains(weekday - 1) else { return nil }
        return symbols[weekday - 1]
    }

    /// The activity that survives a real day best, by the name the user
    /// knows it by — which is why the lookup is handed in rather than done here:
    /// an activity somebody invented lives on `ForgeViewModel`, and this screen
    /// has no business knowing that.
    var mostKept: (name: String, rate: Double)? {
        guard let best = trends.mostKept, let ritual = resolve(best.id) else { return nil }
        return (ritual.label, best.rate)
    }

    /// "March", or "March 2024" once it is far enough back to be ambiguous.
    ///
    /// The year appears only when the month alone would be a lie by omission —
    /// "since March" is warm and exact inside the current year and quietly wrong
    /// eighteen months later.
    static func monthName(_ day: ForgeDay) -> String {
        let date = day.startOfDay()
        let thisYear = Calendar.current.component(.year, from: Date())
        let formatter = day.year == thisYear ? monthFormat : monthYearFormat
        return formatter.string(from: date)
    }

    private static let monthFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter
    }()

    private static let monthYearFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }()

    private static let dayFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMMM")
        return formatter
    }()

    private static let gridFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()
}

import Foundation
import Observation

/// The Arcs somebody has joined, and the only place that answer lives.
///
/// Holds enrollments and nothing else — the same shape as `ChapterStore`. How
/// an Arc is going is read out of `ProgressStore` every time it is asked for
/// (`ArcReading`), so the day count, the days kept and whether it was completed
/// can never disagree with the days behind them.
///
/// # One at a time
///
/// One active Arc, and an Arc waiting for its Monday counts as the active one.
/// Not a storage limit but a product one: two programs ramping two weeks in
/// different directions is no program. `start` refuses while one is running,
/// so the rule cannot be broken by a caller forgetting to check.
///
/// # It writes to the week, and only like everything else does
///
/// Joining, a phase's changes and leaving all touch somebody's week, and every
/// one goes through the day's own `apply` as a `SchedulePlan` — the same door
/// `DayPlanner` uses — after the change was shown and accepted (§5 #9).
/// Joining only ever appends (§5 #7). The week is reached through closures,
/// the seam `ChallengeStore` already uses, so nothing here keeps the day alive
/// and a test can hand it a week of its own.
@Observable
final class ArcStore {

    /// Oldest first. Finished and left ones stay: a finished Arc is a mark on
    /// the record, and a left one is still a stretch of somebody's history.
    private(set) var enrollments: [ArcEnrollment] = []

    private let progress: ProgressStore
    private let defaults: UserDefaults
    private static let key = "forge.arcs.v1"
    /// Suppresses the write that loading would otherwise trigger.
    private var isLoaded = false

    /// The week as the day's view model holds it, resolved.
    private let week: () -> [Ritual]
    /// One activity, resolved through anything somebody has changed about it.
    private let find: (String) -> Ritual?
    /// The one door into the week. Returns how many changes it made.
    private let write: (SchedulePlan) -> Int
    /// Take these out of the week.
    private let takeOff: ([String]) -> Void

    init(
        progress: ProgressStore,
        defaults: UserDefaults = ForgeShared.defaults,
        week: @escaping () -> [Ritual] = { [] },
        find: @escaping (String) -> Ritual? = Ritual.find,
        write: @escaping (SchedulePlan) -> Int = { _ in 0 },
        takeOff: @escaping ([String]) -> Void = { _ in }
    ) {
        self.progress = progress
        self.defaults = defaults
        self.week = week
        self.find = find
        self.write = write
        self.takeOff = takeOff
        load()
    }

    // MARK: - Storage

    private func load() {
        defer { isLoaded = true }
        guard let data = defaults.data(forKey: Self.key) else { return }
        enrollments = ArcEnrollment.decodeAll(data)
    }

    private func persist() {
        guard isLoaded, let data = try? JSONEncoder().encode(enrollments) else { return }
        defaults.set(data, forKey: Self.key)
    }

    // MARK: - Reading

    private var today: ForgeDay { progress.currentDay }

    /// The Arc being lived in, or waiting for its start day. Nil is ordinary.
    var current: ArcEnrollment? {
        enrollments.last { $0.leftOn == nil && $0.endDay >= today }
    }

    /// Whether a new one can be started: only when none is running.
    var canStart: Bool { current == nil }

    /// Every Arc run to its end, most recent first. Each is a mark on the
    /// record — Completed or Finished, never anything less.
    var finished: [ArcEnrollment] {
        enrollments
            .filter { $0.leftOn == nil && $0.endDay < today }
            .sorted { $0.endDay > $1.endDay }
    }

    /// Whether a Winter Arc has been run to its end, and so is engraved on the
    /// blade.
    var winterMarks: [ArcEnrollment] {
        finished.filter { $0.arc == .winter }
    }

    func reading(_ enrollment: ArcEnrollment) -> ArcReading {
        ArcReading.read(
            enrollment,
            byDay: progress.byDay,
            today: today,
            restWeekdays: progress.restWeekdays,
            challengeDays: Set(progress.challengesKept.keys),
            resolved: resolved(enrollment)
        )
    }

    /// The running Arc's reading, or nil.
    var currentReading: ArcReading? { current.map(reading) }

    /// Which id in the week does each of this Arc's activities.
    func resolved(_ enrollment: ArcEnrollment) -> [String: String] {
        ArcPlan.resolved(enrollment.program, picks: enrollment.picks, week: Set(week().map(\.id)))
    }

    /// What joining would add to the week, right now — the list somebody reads
    /// before pressing Start.
    func preview(_ arc: ArcID, wake: Int? = nil, picks: [String] = []) -> ArcJoin {
        ArcPlan.join(
            ArcCatalog.program(arc),
            wake: wake ?? ArcProgram.defaultWake,
            picks: picks,
            week: week(),
            find: find
        )
    }

    // MARK: - Joining

    /// Join an Arc from a day — today, or the coming Monday.
    ///
    /// Returns nil, and does nothing, while another is running. A start day
    /// that has come is written into the week at once; one still ahead is
    /// written on the morning it arrives (`applyIfDue`), so a "Start Monday"
    /// pressed on a Thursday does not change Thursday.
    @discardableResult
    func start(
        _ arc: ArcID, on day: ForgeDay, wake: Int? = nil, picks: [String] = [], at instant: Date = .now
    ) -> ArcEnrollment? {
        guard canStart else { return nil }
        let program = ArcCatalog.program(arc)
        let enrollment = ArcEnrollment(
            arc: arc,
            startDay: max(day, today),
            wakeMinute: program.asksForWake ? (wake ?? ArcProgram.defaultWake) : nil,
            picks: Array(picks.prefix(program.picks)),
            joinedAt: instant
        )
        enrollments.append(enrollment)
        persist()
        applyIfDue()
        return enrollments.last
    }

    /// Write a joined Arc into the week once its start day has come. Safe to
    /// call on every launch and every turn of the day: it does nothing unless
    /// something is waiting.
    func applyIfDue() {
        guard let index = enrollments.lastIndex(where: {
            $0.leftOn == nil && !$0.isApplied && $0.startDay <= today && $0.endDay >= today
        }) else { return }
        let enrollment = enrollments[index]
        let join = ArcPlan.join(
            enrollment.program, wake: enrollment.wake, picks: enrollment.picks,
            week: week(), find: find
        )
        if !join.changes.isEmpty {
            _ = write(SchedulePlan(summary: join.headline, changes: join.changes))
        }
        // What actually arrived, read back from the week rather than assumed —
        // only these may ever be taken off again.
        let held = Set(week().map(\.id))
        enrollments[index].added = join.additions.map(\.id).filter(held.contains)
        enrollments[index].isApplied = true
        persist()
    }

    /// Record that the first run's plan, written by the first run itself, is
    /// this Arc's week from today.
    ///
    /// The one join that does not go through `start`: the first run replaces
    /// the default day with the plan somebody just read (`adoptPlan`), and that
    /// plan *is* the Arc's activities. `added` is what the plan put there,
    /// because a new install had nothing of its own to keep.
    ///
    /// A first run walked twice — quit before the end and opened again, which
    /// starts it over — records the second answer: anything begun today is
    /// that same first run's earlier pass, and it is replaced.
    @discardableResult
    func startFromFirstRun(
        _ arc: ArcID, wake: Int?, picks: [String], added: [String], at instant: Date = .now
    ) -> ArcEnrollment? {
        enrollments.removeAll { $0.leftOn == nil && $0.startDay == today }
        guard canStart else { return nil }
        let program = ArcCatalog.program(arc)
        let enrollment = ArcEnrollment(
            arc: arc,
            startDay: today,
            wakeMinute: program.asksForWake ? (wake ?? ArcProgram.defaultWake) : nil,
            picks: Array(picks.prefix(program.picks)),
            // Lock In 7 adds nothing: the first run's plan was the plan before
            // it was an Arc, and leaving must not offer to take it away.
            added: program.activities.isEmpty && program.picks == 0 ? [] : added,
            isApplied: true,
            joinedAt: instant
        )
        enrollments.append(enrollment)
        persist()
        return enrollment
    }

    // MARK: - The phases

    /// What the running Arc's current phase would change in the week, if it
    /// has not been answered and there is anything to change.
    func phaseOffer() -> ArcPhaseOffer? {
        guard let enrollment = current, enrollment.isApplied else { return nil }
        let reading = reading(enrollment)
        guard reading.isRunning, enrollment.phaseAnswers[reading.phase] == nil else { return nil }
        let changes = ArcPlan.changes(
            for: enrollment.program, picks: enrollment.picks, phase: reading.phase, week: week()
        )
        guard !changes.isEmpty else { return nil }
        return ArcPhaseOffer(
            program: enrollment.program, phase: reading.phase, changes: changes
        )
    }

    /// The one explicit tap: write a phase's changes into the week.
    @discardableResult
    func applyPhase(_ offer: ArcPhaseOffer) -> Int {
        guard let index = currentIndex else { return 0 }
        // Recomputed rather than trusted: the week may have moved since the
        // card was drawn, and the changes have to be the ones it shows now.
        let changes = ArcPlan.changes(
            for: enrollments[index].program, picks: enrollments[index].picks,
            phase: offer.phase, week: week()
        )
        let applied = changes.isEmpty ? 0 : write(
            SchedulePlan(summary: offer.title, changes: changes)
        )
        enrollments[index].phaseAnswers[offer.phase] = true
        persist()
        return applied
    }

    /// "Keep mine": the phase is answered and its changes are not offered
    /// again. Nothing in the week moves.
    func keepPhase(_ offer: ArcPhaseOffer) {
        guard let index = currentIndex else { return }
        enrollments[index].phaseAnswers[offer.phase] = false
        persist()
    }

    // MARK: - The counts only the person can keep

    /// One more cold shower, one book shut — or one fewer, for a tap made too
    /// soon. Clamped to the trial's own count and never below nought.
    func tally(_ delta: Int, trial index: Int) {
        guard let position = currentIndex else { return }
        let program = enrollments[position].program
        guard program.trials.indices.contains(index), program.trials[index].count.isTally else { return }
        let target = program.trials[index].count.target
        let now = enrollments[position].tallies[index] ?? 0
        let next = max(0, min(target, now + delta))
        guard next != now else { return }
        enrollments[position].tallies[index] = next == 0 ? nil : next
        persist()
    }

    // MARK: - Leaving

    /// Leave the running Arc, keeping its activities in the week or taking off
    /// exactly what joining added.
    ///
    /// The Arc stays on the record as left, on the day it was left, and the
    /// days kept inside it are where they always were. An Arc still waiting for
    /// its start day is simply withdrawn: nothing has happened in it.
    func leave(takingOff: Bool) {
        guard let index = currentIndex else { return }
        let enrollment = enrollments[index]
        if takingOff, !enrollment.added.isEmpty {
            let held = Set(week().map(\.id))
            takeOff(enrollment.added.filter(held.contains))
        }
        if enrollment.startDay > today || !enrollment.isApplied {
            enrollments.remove(at: index)
        } else {
            enrollments[index].leftOn = today
        }
        persist()
    }

    private var currentIndex: Int? {
        enrollments.lastIndex { $0.leftOn == nil && $0.endDay >= today }
    }

    #if DEBUG
    // MARK: - Debug

    /// Start an Arc as if it had been joined `daysAgo` days ago, so every
    /// phase and the ending can be walked without living through them. The
    /// running one, if any, is withdrawn first. Debug builds only.
    func debugStart(_ arc: ArcID, daysAgo: Int) {
        enrollments.removeAll { $0.leftOn == nil && $0.endDay >= today }
        let program = ArcCatalog.program(arc)
        let enrollment = ArcEnrollment(
            arc: arc,
            startDay: today.adding(days: -max(0, daysAgo)),
            wakeMinute: program.asksForWake ? ArcProgram.defaultWake : nil,
            picks: program.picks > 0 ? Array(week().map(\.id).prefix(program.picks)) : [],
            joinedAt: progress.now
        )
        enrollments.append(enrollment)
        persist()
        applyIfDue()
        // Already past its end: nothing to write into the week, and a finished
        // Arc has nothing waiting.
        if let index = enrollments.lastIndex(where: { $0.id == enrollment.id }), !enrollments[index].isApplied {
            enrollments[index].isApplied = true
            persist()
        }
    }

    /// Throw every Arc away. Debug builds only.
    func debugClear() {
        enrollments = []
        persist()
    }
    #endif
}

/// A phase's changes, waiting on the Arc's card for one explicit tap.
struct ArcPhaseOffer: Equatable, Sendable {
    let program: ArcProgram
    let phase: Int
    let changes: [ScheduleChange]

    /// "Week 3: Build". On the first phase it is "Week 1: Foundation", and
    /// what it offers is lining up what somebody already kept with how the Arc
    /// starts — joining itself never changes those (§5 #7).
    var title: String {
        let current = program.phases[max(0, min(phase, program.phases.count - 1))]
        return "Week \(current.week): \(current.name)"
    }
}

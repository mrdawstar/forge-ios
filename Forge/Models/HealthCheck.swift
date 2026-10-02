import Foundation

// MARK: - When a reading belongs to a day

/// The stretch of real time each metric is read over, for one Forge day.
///
/// **HealthKit-free on purpose**, so the arithmetic that decides whether a
/// step taken at 03:50 is today's or yesterday's is tested without a phone.
/// `HealthBridge` asks Health for exactly these intervals and nothing wider.
///
/// Built from the `ForgeDay` label and the user's own calendar at the moment
/// of reading, never stored: the Forge day is a civil date, and its start is
/// worked out where the phone is now, so a clock change moves the instant and
/// never the label (see `ForgeDay`).
enum HealthWindow {

    /// The Forge day itself: from the day start hour (04:00 unless somebody
    /// moved it) on its date to the same hour on the next date.
    ///
    /// **Not 24 hours.** On the night the clocks go forward it is 23, and on
    /// the night they go back it is 25. Both ends are set by wall clock, so a
    /// day is always "four to four", which is what the person lived.
    static func day(
        _ day: ForgeDay, dayStartHour: Int, calendar: Calendar = .current
    ) -> DateInterval {
        let start = instant(day, hour: dayStartHour, calendar: calendar)
        let end = instant(day.adding(days: 1), hour: dayStartHour, calendar: calendar)
        return DateInterval(start: start, end: max(start, end))
    }

    /// Where the night that ended on this morning is looked for: from 18:00 on
    /// the date before to noon on the day's own date.
    ///
    /// Wide on purpose and on both sides. Somebody asleep at 21:00 and up at
    /// 05:00 is in it, and so is somebody asleep at 03:00 and up at 11:00. Only
    /// time Health files as *asleep* is counted inside it (`HealthBridge`), so
    /// an evening on the sofa with the watch on is not mistaken for a night.
    ///
    /// It is the day's **date** rather than its 04:00 start that decides the
    /// night, because sleep crosses the day start almost every night: a night
    /// from 23:00 to 07:00 is half yesterday's Forge day by the clock, and all
    /// of it is the night this morning ended.
    static func night(endingOn day: ForgeDay, calendar: Calendar = .current) -> DateInterval {
        let start = instant(day.adding(days: -1), hour: nightStartHour, calendar: calendar)
        let end = instant(day, hour: nightEndHour, calendar: calendar)
        return DateInterval(start: start, end: max(start, end))
    }

    static let nightStartHour = 18
    static let nightEndHour = 12

    /// The window a metric is read over on a day.
    static func window(
        for metric: ActivityMetric, on day: ForgeDay, dayStartHour: Int,
        calendar: Calendar = .current
    ) -> DateInterval {
        switch metric {
        case .sleepMinutes: night(endingOn: day, calendar: calendar)
        case .steps, .workoutMinutes, .mindfulMinutes:
            self.day(day, dayStartHour: dayStartHour, calendar: calendar)
        }
    }

    /// A wall-clock hour on a civil date, in `calendar`'s time zone.
    ///
    /// An hour that does not exist that night (02:30 on the morning the clocks
    /// go forward) lands on the next one that does, which is what
    /// `Calendar.date(bySettingHour:)` does by default.
    private static func instant(_ day: ForgeDay, hour: Int, calendar: Calendar) -> Date {
        let midnight = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day))
            ?? .distantPast
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: midnight) ?? midnight
    }
}

// MARK: - Counting time

/// The arithmetic Health's samples go through. Pure, and the reason the
/// bridge has so little in it.
enum HealthMath {

    /// Whole minutes covered by `intervals` inside `window`, **counting any
    /// moment once**.
    ///
    /// A watch and a phone both record the same night; two apps both log the
    /// same run. Adding their lengths would make seven hours asleep read as
    /// fourteen, so the intervals are clipped to the window, merged where they
    /// overlap, and only then measured. A workout from 03:30 to 04:30 gives
    /// thirty minutes to each of the two Forge days it touches.
    ///
    /// Rounded down: a target of thirty minutes is met at thirty, not at
    /// twenty-nine and a half.
    static func minutes(of intervals: [DateInterval], within window: DateInterval) -> Int {
        let clipped = intervals.compactMap { interval -> DateInterval? in
            let start = max(interval.start, window.start)
            let end = min(interval.end, window.end)
            return end > start ? DateInterval(start: start, end: end) : nil
        }
        .sorted { $0.start < $1.start }

        var total: TimeInterval = 0
        var current: DateInterval?
        for interval in clipped {
            guard let open = current else { current = interval; continue }
            if interval.start <= open.end {
                current = DateInterval(start: open.start, end: max(open.end, interval.end))
            } else {
                total += open.duration
                current = interval
            }
        }
        total += current?.duration ?? 0
        return Int((total / 60).rounded(.down))
    }

    /// Whether a reading meets an activity's standard.
    static func meets(_ value: Int?, _ measure: ActivityMeasure) -> Bool {
        guard let value else { return false }
        return value >= measure.target
    }
}

// MARK: - What Forge remembers about Health

/// Everything Forge stores about Apple Health, which is decisions and never
/// readings (APP_STORE.md §1: Health data is not collected).
///
/// Under `forge.health.v1` in the App Group, written only by `ForgeViewModel`.
/// Tolerant per field, like every other stored value in the app: a key this
/// build cannot read falls back to its default rather than failing the whole.
struct HealthLedger: Codable, Equatable, Sendable {

    /// What somebody said on the primer. Health itself never says whether a
    /// person allowed *reading* (HealthKit hides it, so an app cannot tell a
    /// "no" from an empty Health app), so this is the only answer Forge has.
    enum Decision: String, Codable, Sendable {
        /// Never asked. The primer comes up the first time a measurable
        /// activity enters the day, once the first run is over.
        case undecided
        /// Continue on the primer, and iOS was asked. What iOS was told is
        /// the person's own business; `HealthBridge.visibleMetrics` is how
        /// Forge finds out what it can actually see.
        case asked
        /// "Keep it Your Word" on the primer. **Final** (FORGE_CONTEXT §8):
        /// nothing in Forge raises the primer again on its own. Settings has
        /// the one door back, and it is the person's to open.
        case declined
    }

    var decision: Decision = .undecided

    /// Activities that were already in somebody's week when 1.1 made them
    /// Health activities, and so were kept as Your Word (`migrate`). Each is
    /// offered "Let Apple Health check this" once.
    var awaitingOffer: Set<String> = []
    /// Of those, the ones whose offer has been shown. Shown once, whatever
    /// the answer.
    var offered: Set<String> = []
    /// Whether `migrate` has run on this install.
    var hasMigrated = false

    /// The day `ticked` belongs to.
    var tickedDay: ForgeDay?
    /// What Apple Health has ticked off on `tickedDay`. **Health ticks each
    /// activity off at most once a day**, so an undo stands: the steps are
    /// still over the target, and they are not allowed to take the activity
    /// back from the person who just said it was not done.
    var ticked: Set<String> = []

    static let key = "forge.health.v1"

    init() {}

    private enum CodingKeys: String, CodingKey {
        case decision, awaitingOffer, offered, hasMigrated, tickedDay, ticked
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        decision = (try? c.decodeIfPresent(Decision.self, forKey: .decision)) ?? .undecided
        awaitingOffer = (try? c.decodeIfPresent(Set<String>.self, forKey: .awaitingOffer)) ?? []
        offered = (try? c.decodeIfPresent(Set<String>.self, forKey: .offered)) ?? []
        hasMigrated = (try? c.decodeIfPresent(Bool.self, forKey: .hasMigrated)) ?? false
        tickedDay = try? c.decodeIfPresent(ForgeDay.self, forKey: .tickedDay)
        ticked = (try? c.decodeIfPresent(Set<String>.self, forKey: .ticked)) ?? []
    }

    /// Whether HealthKit's observers start when the app launches: only once
    /// somebody has said Continue. Starting one asks nothing, but a new
    /// install has no business with HealthKit at all until then.
    var observesAtLaunch: Bool { decision == .asked }

    // MARK: Ticks

    /// Whether Health has already ticked this off today.
    func hasTicked(_ id: String, on day: ForgeDay) -> Bool {
        tickedDay == day && ticked.contains(id)
    }

    mutating func noteTick(_ id: String, on day: ForgeDay) {
        if tickedDay != day {
            tickedDay = day
            ticked = []
        }
        ticked.insert(id)
    }

    // MARK: The offer on existing activities

    /// Whether the honor prompt for this activity carries "Let Apple Health
    /// check this". Never once declined, never twice.
    func offersHealth(for id: String) -> Bool {
        decision != .declined && awaitingOffer.contains(id) && !offered.contains(id)
    }

    // MARK: Migration

    /// The 1.1 switch, run once per install: **existing activities do not
    /// change without asking.**
    ///
    /// Every library activity that 1.1 made a Health activity and that is
    /// already in the week, with no verification of the person's own, is
    /// pinned to Your Word with an ordinary `RitualEdit` (the same one the
    /// composer would write) and put down for its one offer. Anything added
    /// after this is new, and arrives as Health.
    ///
    /// A new install has nothing measurable in its week when this runs (the
    /// defaults are water, bed, teeth, push-ups, reading), so it pins nothing.
    static func migrate(
        _ ledger: HealthLedger,
        week: [String],
        edits: [String: RitualEdit]
    ) -> (ledger: HealthLedger, edits: [String: RitualEdit]) {
        guard !ledger.hasMigrated else { return (ledger, edits) }
        var ledger = ledger
        var edits = edits
        for id in week where Ritual.find(id) != nil
            && Ritual.libraryVerification[id] == .health
            && Ritual.metrics[id] != nil
            && edits[id]?.verification == nil {
            var edit = edits[id] ?? RitualEdit()
            edit.verification = .honor
            edits[id] = edit
            ledger.awaitingOffer.insert(id)
        }
        ledger.hasMigrated = true
        return (ledger, edits)
    }

    // MARK: Storage

    static func read(from defaults: UserDefaults) -> HealthLedger {
        guard let data = defaults.data(forKey: key),
              let ledger = try? JSONDecoder().decode(HealthLedger.self, from: data)
        else { return HealthLedger() }
        return ledger
    }

    func write(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: HealthLedger.key)
    }
}

// MARK: - The reader

/// What the day needs from Apple Health, and nothing more. `HealthBridge` is
/// the real one; tests hand `ForgeViewModel` a fake.
///
/// There is no write in this protocol and there never will be: Forge reads.
protocol HealthReading: AnyObject {
    /// Asks iOS for read access to the four types. Returns once the system
    /// sheet has been answered (or was not needed). What was chosen on it is
    /// not knowable, by HealthKit's design.
    func requestReadAccess() async
    /// Starts listening for new samples (`HKObserverQuery`). Asks nothing.
    func startObserving()
    /// The metrics Health has any sample of that Forge is able to read. Empty
    /// when reading was refused, which is how a refusal shows itself.
    func visibleMetrics() async -> Set<ActivityMetric>
    /// Today's number for one activity's measure, or nil when Health has none.
    func value(
        of measure: ActivityMeasure, on day: ForgeDay, dayStartHour: Int
    ) async -> Int?
}

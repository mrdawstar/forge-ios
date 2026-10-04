import Foundation
import SwiftUI

/// What the widgets and the Live Activity are allowed to know.
///
/// A flat reading of one day rather than a window onto the model. The
/// extension could be given `ProgressStore`, `Ritual` and the whole history
/// instead — they are only files — but then two processes would each be deriving
/// streaks and completion from raw records, and the first time those disagreed
/// it would be on somebody's Lock Screen with no way to tell which was lying.
///
/// The app writes; the widgets read. There is exactly one direction.
struct ForgeSnapshot: Codable, Equatable, Sendable {

    /// One activity, reduced to what a widget can usefully show: whether it is
    /// done, and what it is called. No subtitle, no target, no icon — a widget
    /// that showed those would be a smaller copy of the list rather than a
    /// glance at it.
    struct Activity: Codable, Equatable, Sendable, Identifiable {
        let id: String
        let name: String
        let isDone: Bool
    }

    /// The day this reading belongs to, in the user's own reckoning.
    var day: ForgeDay
    /// Carried so a widget can work out whether `day` is still today without
    /// needing the settings that decided it.
    var dayStartHour: Int
    /// Days kept, ever. Not the streak: a Lock Screen is the last place a
    /// number that can only fall to zero belongs.
    var daysKept: Int
    /// The blade is out. The only state worth its own treatment.
    var isEarned: Bool
    var activities: [Activity]
    /// Which accent the app is drawn in, as a raw value.
    ///
    /// Carried so the widgets look like the app somebody actually has rather
    /// than like the one Forge shipped: the extension cannot see
    /// `ForgeAppearance`, and reading its defaults key from two processes would
    /// be a second source of truth on the one boundary this file exists to keep
    /// one-directional. Resolved through `ForgeAccentPalette`, which falls back
    /// on anything it does not recognise.
    var accent: String = ForgeAccentPalette.fallback

    /// The colour, resolved.
    var tint: Color { ForgeAccentPalette.color(accent) }

    // MARK: - The record behind today

    /// Roughly the last six months, one `ForgeHeatLevel` a day, oldest first and
    /// ending on `day`.
    ///
    /// Bucketed by the app (`ProgressStore.heatTrail`) rather than by the
    /// widget, for the reason everything else across this boundary is: the
    /// large widget draws the same grid the Blade tab draws, and a second
    /// implementation of "how full is this square" is a second opinion waiting
    /// to be noticed. `ForgeHeatLevel.beforeRecord` marks a day earlier than
    /// anything this person has — drawn as an empty slot, never as a day they
    /// failed.
    ///
    /// **It stops at yesterday.** Today is not in it and must not be: the trail
    /// is written when the app publishes and the widget is drawn whenever the
    /// system feels like it, so a today baked into the trail is a today that can
    /// go stale. The grid takes today's square from `fraction` and `isEarned`
    /// like every other family does, and takes every day before it from here —
    /// one fact, one source, in both directions.
    ///
    /// Empty on a phone whose app has not run since before this field existed,
    /// which is the whole reason the decoder is hand-written and the large
    /// family checks before it draws.
    var history: [Int] = []

    /// The day `history[0]` describes. Every later entry is one day after the
    /// one before it, so a square's date is `historyStart + its index` — which
    /// is how the grid stays aligned to real dates even for a phone that has
    /// not opened Forge in a week.
    var historyStart: ForgeDay?

    // MARK: - New days, locked

    /// New days need Forge Pro on this phone: lapsed, or never subscribed,
    /// after the first run (DIRECTION_1_1 §1).
    ///
    /// The Forge tab then shows "New days need Forge Pro." in place of the
    /// day's list, and the widgets say the same thing rather than a list of
    /// things nobody can keep: before 1.1's release pass they still read "3
    /// left · Breathe" on a phone that would not let Breathe be kept (§17.7).
    /// The record — days kept, the weeks, the grid — is drawn exactly as
    /// before; it is readable forever. No Live Activity is started or kept.
    var isLocked: Bool = false

    /// What every family says in place of the day while new days are locked:
    /// the app's own `PremiumCopy.lockedTitle`, without its full stop, as the
    /// widgets' other headlines are written ("The day is yours"). Spelled here
    /// because the extension cannot see `Premium.swift`; a test holds the two
    /// together.
    static let lockedHeadline = "New days need Forge Pro"

    /// What the record says about one day, or nil where it says nothing —
    /// before the trail begins, after it ends, or past today.
    ///
    /// Every reading the grid makes goes through here, including today's, so
    /// there is one place in the extension that decides what a square means.
    func mark(on target: ForgeDay) -> ForgeHeatMark? {
        if target > day { return nil }
        if target == day {
            return ForgeHeatMark(
                level: .of(fraction, isRest: false),
                wasKept: isEarned
            )
        }
        guard let historyStart, target >= historyStart else { return nil }
        let index = target.days(since: historyStart)
        guard index >= 0, index < history.count else {
            // Past the end of the trail: a day the app was not opened on.
            // Nothing can be recorded without it, so an empty square is the
            // true reading rather than a hole in the data.
            return ForgeHeatMark(level: .none, wasKept: false)
        }
        // Nil where the trail says this day is earlier than the record — the
        // grid draws nothing there. See `ForgeHeatMark.beforeRecord`.
        return ForgeHeatMark(raw: history[index])
    }

    /// Days kept in the `days` days ending today, today included.
    ///
    /// Counted off the trail rather than carried as its own number, so the two
    /// readings on the large widget — the grid and the line under it — cannot
    /// disagree, and neither can go stale while the other does not.
    func daysKept(inLast days: Int) -> Int {
        guard days > 0 else { return 0 }
        return (0..<days).count { mark(on: day.adding(days: -$0))?.wasKept == true }
    }


    // MARK: - Derived

    var total: Int { activities.count }
    var done: Int { activities.filter(\.isDone).count }
    var remaining: Int { max(0, total - done) }

    /// 0…1 of the day. An earned day is whole whatever the list says —
    /// the first pull is granted with the list unfinished, and a gauge that read
    /// a third full under a freed blade would be contradicting the blade.
    var fraction: Double {
        if isEarned { return 1 }
        guard total > 0 else { return 0 }
        return Double(done) / Double(total)
    }

    /// Hand-written and tolerant, like every other decoder in this app.
    ///
    /// A snapshot written by the build before `accent` existed has no such key,
    /// and the synthesised decoder throws on a missing key even where there is a
    /// default. The failure mode is not academic: `read` catches the throw and
    /// falls back to `.fresh`, so the first launch after an update would show
    /// every widget an empty day until the app was next opened.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(ForgeDay.self, forKey: .day)
        dayStartHour = try c.decodeIfPresent(Int.self, forKey: .dayStartHour) ?? 4
        daysKept = try c.decodeIfPresent(Int.self, forKey: .daysKept) ?? 0
        isEarned = try c.decodeIfPresent(Bool.self, forKey: .isEarned) ?? false
        activities = try c.decodeIfPresent([Activity].self, forKey: .activities) ?? []
        accent = try c.decodeIfPresent(String.self, forKey: .accent)
            ?? ForgeAccentPalette.fallback
        history = try c.decodeIfPresent([Int].self, forKey: .history) ?? []
        historyStart = try c.decodeIfPresent(ForgeDay.self, forKey: .historyStart)
        // Absent in every snapshot written before 1.1's release pass: a day
        // that was not locked, which is what it was.
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
    }

    init(
        day: ForgeDay,
        dayStartHour: Int,
        daysKept: Int,
        isEarned: Bool,
        activities: [Activity],
        accent: String = ForgeAccentPalette.fallback,
        history: [Int] = [],
        historyStart: ForgeDay? = nil,
        isLocked: Bool = false
    ) {
        self.day = day
        self.dayStartHour = dayStartHour
        self.daysKept = daysKept
        self.isEarned = isEarned
        self.activities = activities
        self.accent = accent
        self.history = history
        self.historyStart = historyStart
        self.isLocked = isLocked
    }

    private enum CodingKeys: String, CodingKey {
        case day, dayStartHour, daysKept, isEarned, activities, accent
        case history, historyStart, isLocked
    }

    /// Whether this reading still describes the day the clock is in.
    ///
    /// A widget refreshes on the system's schedule, not the app's, so it will
    /// eventually be asked to draw a snapshot written yesterday. Showing
    /// yesterday's finished day on today's Lock Screen would be the worst
    /// thing a Forge widget could do.
    func isCurrent(now: Date = .now, calendar: Calendar = .current) -> Bool {
        day == ForgeDay.containing(now, calendar: calendar, dayStartHour: dayStartHour)
    }

    /// What to draw when there is nothing to draw: a day not yet begun.
    static func fresh(
        daysKept: Int = 0,
        total: Int = 0,
        now: Date = .now,
        dayStartHour: Int = 4,
        accent: String = ForgeAccentPalette.fallback,
        history: [Int] = [],
        historyStart: ForgeDay? = nil,
        isLocked: Bool = false
    ) -> ForgeSnapshot {
        ForgeSnapshot(
            day: ForgeDay.containing(now, dayStartHour: dayStartHour),
            dayStartHour: dayStartHour,
            daysKept: daysKept,
            isEarned: false,
            activities: (0..<total).map {
                Activity(id: "placeholder.\($0)", name: "", isDone: false)
            },
            accent: accent,
            history: history,
            historyStart: historyStart,
            isLocked: isLocked
        )
    }

    // MARK: - Storage

    private static let key = "forge.snapshot.v1"

    /// The reading the widgets should draw right now.
    ///
    /// Returns a fresh day rather than nil when the stored one has gone
    /// stale, so a widget never has to decide what an out-of-date snapshot
    /// means — by the time it gets here, it is either today's or it is nothing.
    static func read(
        from defaults: UserDefaults = ForgeShared.defaults,
        now: Date = .now
    ) -> ForgeSnapshot {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(ForgeSnapshot.self, from: data)
        else { return .fresh(now: now) }

        guard stored.isCurrent(now: now) else {
            // The count survives the rollover; nothing else does. A day
            // that has not started yet still sits on top of the ones before it.
            // The count and the colour survive the rollover; nothing else
            // does. A day that has not started yet still sits on top of the ones
            // before it, and is still drawn in the accent they chose.
            // The history survives too, minus today. Yesterday's grid is still
            // a true picture of yesterday, and dropping it would empty the large
            // widget every night at four in the morning until the app was next
            // opened — the one time of day nobody opens it.
            // Locked yesterday is locked this morning: what somebody owns does
            // not change at four o'clock, and a fresh day would otherwise show
            // a locked phone a day to be kept until the app was next opened.
            return .fresh(
                daysKept: stored.daysKept,
                total: stored.total,
                now: now,
                dayStartHour: stored.dayStartHour,
                accent: stored.accent,
                history: stored.history,
                historyStart: stored.historyStart,
                isLocked: stored.isLocked
            )
        }
        return stored
    }

    func write(to defaults: UserDefaults = ForgeShared.defaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

import Foundation

// MARK: - The first-week contract

/// What the Becoming tab says before there is a shape to draw.
///
/// # The contract
///
/// *"Your shape draws itself on Sunday. Until then: three days kept of seven."*
///
/// One promise and one count. The promise names the day the first week of the
/// record ends — the weekday of the first recorded day, a week on — because the
/// hexagon is a reading of weeks, and a polygon drawn on three days is a shape
/// the app made up (see `ForgeShape.isReadable`). The count is the only thing
/// somebody can do anything about in the meantime.
///
/// # When it gives way to the shape
///
/// **Both** of these, and only these:
///
/// 1. the record has a week behind it (`today` is at least seven days after
///    the first recorded day), and
/// 2. `ForgeShape.isReadable` — two dimensions measured and five kept days of
///    credit in the window, the rule the hexagon has always waited for.
///
/// A week that ends without enough to read keeps the card, with the promise
/// replaced by what is still true: the shape draws itself as the days add up,
/// and here are the last seven.
///
/// # Nothing is stored
///
/// Every figure is read off the same `DayRecord`s as the streak and the
/// heatmap (§5 rule #2). There is no counter, no flag, no "first week done" key
/// — a first week that was edited, synced or cleared answers correctly on the
/// next read because there was never a second answer to disagree with.
struct FirstWeek: Equatable, Sendable {

    /// The length of the first week, and of the rolling window after it.
    static let length = 7

    /// The first day of the record — or today, for a record with nothing in it.
    let start: ForgeDay
    let today: ForgeDay
    /// Days earned inside the window this card counts: the first week so far,
    /// or the last seven once the first week is over.
    let kept: Int
    /// Days of the window lived through, today included. 1…7.
    let lived: Int
    /// Still inside the first seven days of the record.
    let isOpeningWeek: Bool

    /// The day the first week ends and the shape is due.
    var drawDay: ForgeDay { start.adding(days: Self.length) }

    /// 0…1 toward the first readout.
    ///
    /// In the opening week it is time: days lived of the seven, because the
    /// draw day comes whatever is kept. After it, it is the last seven's kept
    /// days of seven — the thing that actually brings the shape in.
    var progress: Double {
        let numerator = isOpeningWeek ? lived : kept
        return min(1, max(0, Double(numerator) / Double(Self.length)))
    }

    /// The contract for this record, or nil once the shape should be drawn.
    static func make(
        firstDay: ForgeDay?,
        today: ForgeDay,
        earned: [ForgeDay],
        isShapeReadable: Bool
    ) -> FirstWeek? {
        let start = min(firstDay ?? today, today)
        let since = today.days(since: start)
        if since >= length, isShapeReadable { return nil }

        let isOpening = since < length
        let windowStart = isOpening ? start : today.adding(days: -(length - 1))
        let kept = Set(earned).count { $0 >= windowStart && $0 <= today }
        return FirstWeek(
            start: start,
            today: today,
            kept: kept,
            lived: isOpening ? since + 1 : length,
            isOpeningWeek: isOpening
        )
    }

    // MARK: Words

    /// The contract, in one or two sentences, with every count agreeing with
    /// its noun.
    var sentence: String {
        if isOpeningWeek {
            return "Your shape draws itself \(when). Until then: \(Self.days(kept)) kept of seven."
        }
        return "Your shape draws itself as the days add up. The last seven: \(Self.days(kept)) kept."
    }

    /// "on Sunday", "tomorrow", or "next Sunday" on the day it starts.
    var when: String {
        let until = drawDay.days(since: today)
        if until == 1 { return "tomorrow" }
        let name = Self.weekdayNames[max(0, min(6, drawDay.weekday - 1))]
        return drawDay.weekday == today.weekday ? "next \(name)" : "on \(name)"
    }

    /// "no days", "one day", "three days" — spelled, lower-case, and never
    /// "one days". `ForgeCount.spelled` beyond a hundred falls back to digits.
    static func days(_ count: Int) -> String {
        switch count {
        case ..<1: "no days"
        case 1: "one day"
        default: "\(ForgeCount.spelled(count).lowercased()) days"
        }
    }

    /// English, like the rest of the interface, and fixed rather than read off
    /// the device so the sentence is the same everywhere it is tested.
    static let weekdayNames = [
        "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
    ]
}

extension ProgressStore {

    /// The first-week contract, read off the record. See `FirstWeek`.
    func firstWeek(isShapeReadable: Bool) -> FirstWeek? {
        FirstWeek.make(
            firstDay: firstRecordedDay,
            today: currentDay,
            earned: records.filter(\.isEarned).map(\.day),
            isShapeReadable: isShapeReadable
        )
    }
}

// MARK: - A first thing for an empty dimension

/// The smallest honest start for a part of somebody that nothing feeds yet.
///
/// **One, from the library, never invented.** It is
/// `ForgeShape.suggestions(for:avoiding:limit:)` at a limit of one — the same
/// effort-ranked filter the "Add to your day" list uses — so the row offers the
/// easiest thing filed under that dimension that somebody does not already
/// keep, and nil when the library has nothing left to offer. There is no
/// second list of activities to drift from the first.
enum BecomingStarter {

    /// Whether a dimension should carry a starter: nothing is filed under it.
    /// A dimension with activities but no days yet is waiting on its first day,
    /// not missing something to do.
    static func isEmpty(_ dimension: ForgeShape.Dimension) -> Bool {
        !dimension.hasActivities
    }

    static func starter(for dimension: ForgeShape.Dimension, avoiding kept: Set<String>) -> Ritual? {
        guard isEmpty(dimension) else { return nil }
        return ForgeShape.suggestions(for: dimension.category, avoiding: kept, limit: 1).first
    }

    /// Every empty dimension's starter, keyed by dimension. Computed on read.
    static func starters(in shape: ForgeShape, avoiding kept: Set<String>) -> [RitualCategory: Ritual] {
        var found: [RitualCategory: Ritual] = [:]
        for dimension in shape.dimensions {
            if let ritual = starter(for: dimension, avoiding: kept) {
                found[dimension.category] = ritual
            }
        }
        return found
    }
}

/// The one way the Becoming tab adds anything to the day.
///
/// Through the existing `ForgeViewModel.addRitual` — the same path the library
/// uses — and reported as `activity_added { source: becoming }`, which carries
/// the source and nothing else: never the activity's name or any text.
/// Only ever called from a button somebody pressed.
enum BecomingOffer {
    @MainActor
    static func add(
        _ ritual: Ritual,
        to forge: ForgeViewModel,
        send: (ForgeTelemetry.Event) -> Void = { ForgeTelemetry.send($0) }
    ) {
        forge.addRitual(ritual.id)
        send(.activityAdded(.becoming))
    }
}

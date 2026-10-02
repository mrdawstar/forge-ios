import Foundation

/// The six at a glance: one tile per dimension, the score, whether somebody is
/// building it, and how far it has moved in a week.
///
/// # Why a week, and why it is read rather than kept
///
/// A score on its own says where somebody is; the one thing a glance cannot get
/// from a number is whether it is going anywhere. The direction word under each
/// row of the old list answered that across a fortnight against a fortnight,
/// which is right for a trend and too slow for a glance. Seven days is the
/// shortest span that is not noise in a twenty-eight day window, and it is the
/// span somebody actually remembers ("last week I was at 58").
///
/// **Nothing here is stored** (§5 #2). The change is the blended shape read
/// today minus the same function read as of seven days ago, over the same
/// record — what the tile would have said a week ago, worked out again. A
/// stored "last week" would be a number that could disagree with the history
/// it came from, which is the bug class this codebase designs itself out of.
///
/// # When it is not shown
///
/// Only when it cannot be known. A week ago there has to have been a record
/// and, if this person has answered the seven questions, the answers — a
/// reading taken before either existed is a reading of somebody else. And the
/// dimension has to have had a number then and have one now: "—" to 12 is not
/// a change of +12, it is a start.
enum StatGlance {

    /// How far back the change looks.
    static let span = 7

    /// The six tiles, in `RitualCategory.dimensions` order — the hexagon's
    /// order, clockwise from the top, so the grid and the polygon can never
    /// disagree about which is which.
    static func tiles(
        now: BlendedShape, weekAgo: BlendedShape?, focus: Set<RitualCategory>
    ) -> [GlanceTile] {
        RitualCategory.dimensions.compactMap { category in
            guard let dimension = now.dimension(category) else { return nil }
            return GlanceTile(
                dimension: dimension,
                isBuilding: focus.contains(category),
                weekChange: change(of: category, now: now, weekAgo: weekAgo)
            )
        }
    }

    /// The blended shape as it read seven days ago, or nil when a week ago
    /// there was nothing of this person to read.
    ///
    /// The same `BlendedShape.read` every screen uses, given the day a week ago
    /// as "today" — so that day counts the way it did while it was being lived
    /// (only what was kept in it), and nothing after it is read at all. The
    /// answers are passed only if they had been given by then.
    static func weekAgo(
        _ byDay: [ForgeDay: DayRecord],
        today: ForgeDay,
        activities: [Ritual],
        assessment: Assessment?,
        challenges: [ForgeDay: RitualCategory] = [:]
    ) -> BlendedShape? {
        let then = today.adding(days: -span)
        guard let first = byDay.keys.min(), first <= then else { return nil }
        if let assessment, assessment.day > then { return nil }
        let past = byDay.filter { $0.key <= then }
        return BlendedShape.read(
            past, today: then, activities: activities,
            assessment: assessment, challenges: challenges.filter { $0.key <= then }
        )
    }

    /// One dimension's change, or nil when it cannot be known.
    static func change(of category: RitualCategory, now: BlendedShape, weekAgo: BlendedShape?) -> Int? {
        guard let weekAgo,
              let current = now.dimension(category), current.hasScore,
              let earlier = weekAgo.dimension(category), earlier.hasScore
        else { return nil }
        return current.score - earlier.score
    }

    /// "+4", "−3", "±0". Digits, because it is a score (DIRECTION_1_1 §3), and
    /// a real minus sign rather than a hyphen.
    static func label(_ change: Int) -> String {
        switch change {
        case 1...: "+\(change)"
        case 0: "\u{00B1}0"
        default: "\u{2212}\(-change)"
        }
    }

    /// The same, for VoiceOver: "up 4 this week".
    static func spoken(_ change: Int) -> String {
        switch change {
        case 1...: "up \(change) this week"
        case 0: "unchanged this week"
        default: "down \(-change) this week"
        }
    }
}

/// One of the six, as a tile on Becoming. (`StatTile`, the view, is the
/// onboarding's; this is the reading a Becoming tile draws.)
struct GlanceTile: Identifiable, Equatable, Sendable {
    let dimension: BlendedShape.Dimension
    /// Whether this is one somebody said they were building.
    let isBuilding: Bool
    /// The change over seven days, or nil when it cannot be known.
    let weekChange: Int?

    var category: RitualCategory { dimension.category }
    var id: String { category.rawValue }
}

// MARK: - What one completion did

/// What keeping one activity just did to the six: "+4 Physical".
///
/// The **real** change, read off the blend before the write and after it, and
/// stored nowhere — the chip that says it fades in a second and a half and
/// nothing about it survives the moment (§5 #2).
///
/// # Which dimension, when an activity feeds more than one
///
/// The one that moved most, so the chip is never a smaller number than the
/// truth; on a tie, the dimension the activity is filed under, then the
/// hexagon's order. A dimension that had no number before counts from nought —
/// the tile went from "—" to a figure, and that is what the chip says.
///
/// # Never a minus
///
/// A completion can only add kept days, but while the answers are still part
/// of a number (`BlendedShape`) a day of record can pull a high starting answer
/// down towards what the record says. That is true and the tile shows it; it is
/// not something to announce on the act of keeping a promise, so a change that
/// is not upward draws no chip at all — the same as one that rounds to nought.
struct StatGain: Identifiable, Equatable, Sendable {
    let id: UUID
    /// The activity whose completion this was.
    let ritualID: String
    let dimension: RitualCategory
    let delta: Int

    /// "+4 Physical".
    var label: String { "+\(delta) \(dimension.label)" }

    /// The gain between two readings, or nil when nothing rose.
    static func between(
        _ before: BlendedShape, _ after: BlendedShape,
        ritualID: String, filedUnder own: RitualCategory
    ) -> StatGain? {
        let order = [own] + RitualCategory.dimensions.filter { $0 != own }
        var best: (category: RitualCategory, delta: Int)?
        for category in order {
            guard let now = after.dimension(category), now.hasScore else { continue }
            let was = before.dimension(category).map { $0.hasScore ? $0.score : 0 } ?? 0
            let delta = now.score - was
            if delta > (best?.delta ?? 0) { best = (category, delta) }
        }
        guard let best else { return nil }
        return StatGain(id: UUID(), ritualID: ritualID, dimension: best.category, delta: best.delta)
    }
}

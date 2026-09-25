import Foundation

/// A named stretch of practice, with a beginning and an end somebody chose.
///
/// # What it is for
///
/// Forge could tell somebody how many days they had kept and nothing else about
/// the shape of them. That is fine at forty days and it is the whole problem at
/// four hundred: the number goes up, nothing else changes, and what began as
/// becoming somebody has quietly turned into maintaining a total. There is
/// nothing to be *inside*.
///
/// A chapter is the inside. Six weeks, a name, one sentence about what it is
/// for, and an end — which is the part that matters most, because a practice
/// with no ending has no natural moment to look back from. Every review, season
/// reading and honest question the app might one day ask hangs off a thing that
/// closes.
///
/// # What it is not
///
/// **Not a goal, and it cannot be failed.** There is no target, no completion
/// bar to fill, and closing one early costs nothing. A chapter that could be
/// failed would be a streak with a longer period — the same anxiety on a
/// six-week cycle instead of a daily one, and this app has spent its whole
/// design taking that shape out.
///
/// **Not a container for the record either.** Days do not belong to chapters:
/// the history is one continuous thing and a chapter is a window laid over it.
/// So closing one loses nothing, an overlapping one would still read correctly,
/// and a user who never opens a chapter has a record that is exactly as complete
/// as anybody else's. See `ChapterReading`, which is entirely derived.
///
/// **Optional, and meant to stay that way** — the promise
/// `Identity` both make, for the same reason: a feature that can be declined is
/// the only kind that can be genuinely wanted.
struct Chapter: Identifiable, Codable, Equatable, Sendable {

    /// Minted, stable, and never derived from the name. The name is the part
    /// somebody rewrites in week three when they work out what they meant.
    let id: String

    /// What they are calling it. Theirs, in their own words — "The winter one",
    /// "Getting back to it", "Six weeks of mornings".
    var name: String

    /// The identities this chapter is about, by id.
    ///
    /// Ids rather than values, and never a copy of the statement: an identity
    /// rewritten mid-chapter must not leave the chapter describing a person the
    /// user has stopped being. An id that resolves to nothing reads as untagged,
    /// exactly as it does on an activity — see `IdentityStore.delete(_:)`.
    ///
    /// May be empty. A chapter about no identity in particular is a perfectly
    /// ordinary six weeks, and the app has no business requiring the answer to a
    /// question it only started asking recently.
    var identityIDs: [String]

    /// One sentence the user writes about what this stretch is for.
    ///
    /// Deliberately not a goal and deliberately not measured. Nothing reads this
    /// except the person who wrote it, which is the entire point: it is the
    /// thing they will be looking at in six weeks when the review asks whether
    /// it happened. May be empty.
    var intention: String

    var openedAt: Date
    /// Nil while it is the one being lived in.
    var closedAt: Date?

    /// When this row last changed, for the merge.
    ///
    /// Stored, unlike everything a chapter *reports*, and the distinction is
    /// the usual one: the readings are derived because they can be, and this
    /// cannot — "when did this change" is not recoverable from the record. It
    /// is the same field `LocalPractice.IdentityDefinition` carries, kept on the
    /// model here rather than in the ledger because a chapter has no tombstone
    /// machinery and does not need any: closing one is a value, not a deletion.
    var updatedAt: Date = .distantPast

    /// How long a chapter runs before the app suggests closing it.
    ///
    /// Six weeks, and it is a suggestion rather than a deadline — nothing
    /// happens at day forty-three. Short enough that somebody can see the end
    /// from the beginning, long enough that a fortnight of illness does not
    /// define it. Four weeks reads as a month and gets treated like one; three
    /// months is a season nobody can hold in their head as a single thing.
    static let defaultWeeks = 6
    static var defaultDays: Int { defaultWeeks * 7 }

    /// The longest a name may be — a heading, not a sentence.
    static let nameLimit = 40
    /// The longest an intention may be. Long enough for a real sentence, short
    /// enough that it cannot become a plan.
    static let intentionLimit = 140

    var isOpen: Bool { closedAt == nil }

    init(
        id: String = "chapter.\(UUID().uuidString)",
        name: String,
        identityIDs: [String] = [],
        intention: String = "",
        openedAt: Date = .now,
        closedAt: Date? = nil,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = Chapter.trimmed(name, to: Chapter.nameLimit)
        self.identityIDs = identityIDs
        self.intention = Chapter.trimmed(intention, to: Chapter.intentionLimit)
        self.openedAt = openedAt
        self.closedAt = closedAt
        self.updatedAt = updatedAt
    }

    static func trimmed(_ text: String, to limit: Int) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }

    // MARK: - The window

    /// The first day inside it, on Forge's own day clock.
    ///
    /// Read through `ForgeDay` rather than off the `Date`, because everything
    /// this is compared against is a `ForgeDay` and the day starts at four in
    /// the morning. A chapter opened at one a.m. belongs to the day that is
    /// still going, not to the one about to start.
    func firstDay(dayStartHour: Int) -> ForgeDay {
        ForgeDay.containing(openedAt, dayStartHour: dayStartHour)
    }

    /// The last day inside it: the day it closed, or today while it is open.
    func lastDay(dayStartHour: Int, today: ForgeDay) -> ForgeDay {
        guard let closedAt else { return today }
        return ForgeDay.containing(closedAt, dayStartHour: dayStartHour)
    }

    /// Where it is in its six weeks, 0…1. Past six weeks it simply sits at one —
    /// a chapter cannot overrun, because there is nothing it was late for.
    func progress(dayStartHour: Int, today: ForgeDay) -> Double {
        let elapsed = lastDay(dayStartHour: dayStartHour, today: today)
            .days(since: firstDay(dayStartHour: dayStartHour))
        return min(1, max(0, Double(elapsed) / Double(Chapter.defaultDays)))
    }

    /// "Week three of six" — where somebody is, in the words they would use.
    ///
    /// Weeks rather than days because six weeks is how the chapter was
    /// described, and "day nineteen" invites arithmetic nobody wanted to do.
    func placeLabel(dayStartHour: Int, today: ForgeDay) -> String {
        let elapsed = lastDay(dayStartHour: dayStartHour, today: today)
            .days(since: firstDay(dayStartHour: dayStartHour))
        let week = min(Chapter.defaultWeeks, elapsed / 7 + 1)
        guard isOpen else {
            let total = max(1, elapsed / 7 + (elapsed % 7 == 0 ? 0 : 1))
            return total == 1 ? "One week, closed" : "\(ForgeCount.spelled(total)) weeks, closed"
        }
        return "Week \(week) of \(Chapter.defaultWeeks)"
    }

    // MARK: - Reading what is on disk

    /// Hand-written and tolerant, for the reason every decoder in this app is:
    /// one throw fails the whole array, and the failure mode here is somebody
    /// opening Forge to find the six weeks they are in the middle of gone. Only
    /// `id` is genuinely required.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = Chapter.trimmed(
            try c.decodeIfPresent(String.self, forKey: .name) ?? "", to: Chapter.nameLimit
        )
        identityIDs = try c.decodeIfPresent([String].self, forKey: .identityIDs) ?? []
        intention = Chapter.trimmed(
            try c.decodeIfPresent(String.self, forKey: .intention) ?? "",
            to: Chapter.intentionLimit
        )
        openedAt = try c.decodeIfPresent(Date.self, forKey: .openedAt) ?? .now
        closedAt = try c.decodeIfPresent(Date.self, forKey: .closedAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? openedAt
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(identityIDs, forKey: .identityIDs)
        try c.encode(intention, forKey: .intention)
        try c.encode(openedAt, forKey: .openedAt)
        try c.encodeIfPresent(closedAt, forKey: .closedAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, identityIDs, intention, openedAt, closedAt, updatedAt
    }
}

// MARK: - What happened inside it

/// A chapter measured against the record.
///
/// **Derived, never stored, and the whole type exists to make that obvious.**
/// Not one number here is written to disk: they are all read out of
/// `ProgressStore` at the moment somebody looks, which is why a chapter cannot
/// develop a count that disagrees with the days behind it — the bug class this
/// codebase designs itself out of everywhere.
///
/// It also means a chapter can be opened *retroactively over days that already
/// happened* and immediately say something true about them, which is the correct
/// behaviour: naming a stretch of practice is not the same as starting it, the
/// same lesson `firstEvidence` learned.
struct ChapterReading: Equatable, Sendable {
    /// Days earned inside the window. Cumulative while the chapter is open and
    /// fixed once it closes; it can never go down either way.
    let daysKept: Int
    /// Days the window covers so far.
    let daysElapsed: Int
    /// Of everything asked for inside the window, how much was done. 0…1.
    let completionRate: Double

    var completionPercent: Int { Int((completionRate * 100).rounded()) }

    /// How long a chapter has to have run before the way out is offered.
    ///
    /// Two weeks. Closing is still free and still resets nothing — see
    /// `ChapterStore.close` — but a "Close this chapter" link under a chapter
    /// opened this morning is an invitation to abandon a six-week promise on
    /// its first bad day, which is exactly the moment the chapter exists to
    /// carry somebody through.
    static let daysBeforeClosing = 14

    /// Whether "Close this chapter" is shown.
    var canClose: Bool { daysElapsed >= Self.daysBeforeClosing }
}

extension Chapter {
    /// What the record says about this chapter, read on demand.
    ///
    /// Takes the store rather than a pile of numbers, for the same reason
    /// `Milestone.all(from:)` does: the caller should not be able to hand this a
    /// count from somewhere else.
    func reading(from progress: ProgressStore) -> ChapterReading {
        let first = firstDay(dayStartHour: progress.dayStartHour)
        let last = lastDay(dayStartHour: progress.dayStartHour, today: progress.currentDay)
        return ChapterReading(
            daysKept: progress.daysKept(from: first, to: last),
            daysElapsed: max(0, last.days(since: first)) + 1,
            completionRate: progress.completionRate(from: first, to: last)
        )
    }

    /// Days inside this chapter that are evidence for one identity.
    ///
    /// `activities` is handed in rather than looked up, the same shape
    /// `ProgressStore.daysOfEvidence(taggedTo:)` uses and for the same reason:
    /// which activities carry an identity is a question only `ForgeViewModel`
    /// can answer, and nothing in `Models` has any business knowing that.
    func evidence(
        taggedTo activities: Set<String>, from progress: ProgressStore
    ) -> Int {
        progress.daysOfEvidence(
            taggedTo: activities,
            from: firstDay(dayStartHour: progress.dayStartHour),
            to: lastDay(dayStartHour: progress.dayStartHour, today: progress.currentDay)
        )
    }
}

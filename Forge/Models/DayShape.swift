import Foundation

/// The parts a day is divided into, and who owns what.
///
/// This is the layer that lets a Path reach the one screen it never could: the
/// day itself, every time the app is opened, rather than only the card where a
/// world is chosen and the summary where one is finished. A flat list of six
/// activities is a list. The same six under *before the world*, *while it asks*
/// and *when it lets go* is a claim about where in a day discipline is actually
/// decided — which is the thing somebody agreed with when they chose the Path,
/// finally visible in the place they spend their time.
///
/// # Why membership is not stored here
///
/// A part holds ids, and it is emphatically **not** the truth about which
/// activities are in the day. `ForgeViewModel.activeRitualIDs` is, exactly as it
/// was before any of this existed, and this type is reconciled against it on
/// every read.
///
/// The alternative — parts owning the day, with the flat list derived — is the
/// tidier object model and was rejected. It would have migrated the one file
/// people would genuinely grieve losing, and it would have put a presentational
/// idea underneath sync, the widgets, the snapshot and the Live Activity, all of
/// which currently read a flat ordered list and are right to.
///
/// So the drift that arrangement invites cannot happen here: parts never own
/// membership, so they can never disagree with it about whether somebody keeps
/// an activity. The worst a corrupt or stale shape can do is put a row under the
/// wrong heading for one launch, and `reconciled(with:)` fixes even that.
struct DayPart: Codable, Equatable, Identifiable, Sendable {

    /// Stable across renames, so a part keeps its identity when the user gives
    /// it their own words. Generated once and never derived from the name.
    let id: String

    /// The user's word for this part of their day.
    ///
    /// Seeded from a Path's movement when a routine is taken and owned by the
    /// user from that moment on. Empty renders as no heading at all, which is
    /// what a day with one unnamed part looks like — and a day with one unnamed
    /// part is exactly the flat list Forge has always shown.
    var name: String

    /// Activity ids in this part, in the order the day meets them.
    var activities: [String]

    /// The movement this part was created from, if a routine created it.
    ///
    /// Kept because `name` is the user's and moves the moment they retype it,
    /// and something has to still know which heading is which. Without it,
    /// somebody who renamed "Before the world" to "My mornings" and then took
    /// the routine again got their part emptied and the world's heading built
    /// back beside it — their word quietly discarded by the act of agreeing
    /// with the world a second time.
    ///
    /// Optional, and nil for a part the user made themselves. Decodes as nil
    /// from a shape written before this existed, which is exactly right: that
    /// shape's parts came from a routine whose name they still carry, and the
    /// name match below catches them.
    var origin: String?

    init(id: String = UUID().uuidString, name: String, activities: [String], origin: String? = nil) {
        self.id = id
        self.name = name
        self.activities = activities
        self.origin = origin
    }

    /// Whether this part is the one a movement belongs in.
    ///
    /// By origin first, so a renamed part is still recognised. By name second,
    /// so a part the user built and named "Before the world" themselves is
    /// joined rather than duplicated — if somebody has already written the
    /// heading, the world has nothing to add but its activities.
    func answersTo(_ movementName: String) -> Bool {
        origin == movementName || (origin == nil && name == movementName)
    }

    /// Whether this heading is the user's own words.
    ///
    /// The day list draws a heading only when this is true, and the reason is a
    /// piece of feedback worth writing down: somebody who took a Path's routine
    /// found "WHEN IT LETS GO" sitting between two of their activities and read
    /// it as the app talking to itself. They were right. A world's movement name
    /// is an argument the world is making on its own screen; transplanted into
    /// somebody's day list it is a line of poetry between "Brush teeth" and
    /// "Read", with no way to tell what it is or how to get rid of it.
    ///
    /// So the world's word orders the day and stays out of it, and the moment
    /// the user renames a part — or builds one of their own — the heading is
    /// theirs and appears. `origin` is what makes the distinction possible; it
    /// was added for a different reason and turns out to answer this exactly.
    var isUserNamed: Bool {
        guard !name.isEmpty else { return false }
        guard let origin else { return true }
        return name != origin
    }
}

/// A part with its activities looked up and ordered, which is what a view wants.
///
/// The counterpart to `ResolvedMovement`: a Path's routine resolves into that on
/// the way to a card, and the user's own day resolves into this on the way to
/// the list. Two types rather than one because they are genuinely different
/// things — a movement is a world's proposal and cannot be edited, and a part is
/// somebody's day and is nothing but editable.
struct ShapedPart: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let activities: [Ritual]

    /// Whether the day list should draw this heading — see `DayPart.isUserNamed`.
    /// The editor ignores it and shows every part, named or not, because that is
    /// where a name gets given.
    var isUserNamed: Bool = false

    /// Every activity in this part is behind you.
    ///
    /// Worth having as its own idea rather than a count comparison at the call
    /// site: a finished part is the one genuinely new thing parts made possible,
    /// and it is the payoff. "Before the world" complete at seven in the
    /// morning is a fact about the day that a flat list could not show, and it
    /// is exactly what the Vigil's standard is about.
    var isComplete: Bool { !activities.isEmpty && completed == activities.count }

    /// How many of this part's activities are done.
    var completed: Int = 0
}

/// A day's parts, kept honest against the day itself.
///
/// Every operation here is pure arithmetic on lists of ids. That is deliberate:
/// this decides what somebody sees when they open the app, and the rule that
/// keeps it from ever losing an activity has to be testable without a view
/// model, a store or a phone.
struct DayShape: Codable, Equatable, Sendable {

    var parts: [DayPart]

    /// One unnamed part: the flat list Forge has always shown, and what every
    /// install starts with.
    static let flat = DayShape(parts: [])

    var isFlat: Bool { parts.count <= 1 }

    // MARK: - Reconciliation

    /// This shape, made true about `day`.
    ///
    /// **`day` always wins.** The rules, in order:
    ///
    /// - an id in a part but no longer in the day is dropped, so removing an
    ///   activity cannot leave a ghost under a heading;
    /// - an id in the day but in no part joins the last part, so adding one from
    ///   the picker lands somewhere real rather than vanishing;
    /// - an id in two parts stays in the first, so a shape that was written
    ///   twice cannot show the same activity twice;
    /// - a part left with nothing in it is dropped, so a heading never sits over
    ///   an empty space;
    /// - a shape with nothing left in it becomes flat, which is the same list
    ///   the app drew before parts existed.
    ///
    /// Run on every read rather than on write. Writes are where a state like
    /// this normally rots — one path forgets to call the fixer and the bug ships
    /// — and this way there is no path to forget.
    func reconciled(with day: [String]) -> DayShape {
        let inDay = Set(day)
        var seen: Set<String> = []

        var kept: [DayPart] = []
        for part in parts {
            let activities = part.activities.filter { id in
                guard inDay.contains(id), !seen.contains(id) else { return false }
                seen.insert(id)
                return true
            }
            guard !activities.isEmpty else { continue }
            kept.append(DayPart(id: part.id, name: part.name,
                                activities: activities, origin: part.origin))
        }

        // Anything the day holds that no part claimed. Appended in the day's own
        // order so a run of new activities keeps the order they were added in.
        let unclaimed = day.filter { !seen.contains($0) }
        if !unclaimed.isEmpty {
            if kept.isEmpty {
                kept = [DayPart(name: "", activities: unclaimed)]
            } else {
                kept[kept.count - 1].activities.append(contentsOf: unclaimed)
            }
        }

        return DayShape(parts: kept)
    }

    /// The day as these parts order it — the flat list this shape describes.
    ///
    /// Used to check a shape against the day it claims to describe, and by the
    /// import to hand the view model a reordered list in one assignment.
    var flattened: [String] { parts.flatMap(\.activities) }

    // MARK: - Changing it

    /// Puts `id` into the part named by `partID`, taking it out of wherever it
    /// was. The day's membership is untouched — this only moves a row between
    /// headings, which is what "move it to another part of the day" means.
    func moving(_ id: String, to partID: String) -> DayShape {
        var parts = self.parts
        for index in parts.indices {
            parts[index].activities.removeAll { $0 == id }
        }
        guard let target = parts.firstIndex(where: { $0.id == partID }) else { return self }
        parts[target].activities.append(id)
        return DayShape(parts: parts.filter { !$0.activities.isEmpty })
    }

    /// Reorders within one part, from indices local to that part.
    ///
    /// Local indices because that is what a `ForEach` over a section hands back,
    /// and translating them to positions in the flat day at the call site is the
    /// kind of arithmetic that is wrong once and then wrong forever. The part
    /// owns its own order; the day's order is read back out of the parts
    /// afterwards — see `flattened`.
    /// Written out rather than calling SwiftUI's `move(fromOffsets:toOffset:)`,
    /// so this file stays Foundation-only — the rules about somebody's day
    /// should not need a UI framework to be true, or to be tested.
    ///
    /// The semantics are SwiftUI's, because they are what a `ForEach` reports:
    /// `destination` is an offset in the list *as it was before the move*, so
    /// the insertion point has to be pulled back by however many of the moving
    /// rows were above it.
    func reordering(inPart partID: String, from source: IndexSet, to destination: Int) -> DayShape {
        var parts = self.parts
        guard let index = parts.firstIndex(where: { $0.id == partID }) else { return self }

        let activities = parts[index].activities
        let valid = source.filter { activities.indices.contains($0) }
        guard !valid.isEmpty else { return self }

        let moving = valid.map { activities[$0] }
        var rest = activities
        for offset in valid.sorted(by: >) { rest.remove(at: offset) }
        let insertAt = min(destination - valid.count { $0 < destination }, rest.count)

        rest.insert(contentsOf: moving, at: max(0, insertAt))
        parts[index].activities = rest
        return DayShape(parts: parts)
    }

    /// Renames a part. The user's words from the moment they type them.
    func renaming(_ partID: String, to name: String) -> DayShape {
        DayShape(parts: parts.map { part in
            guard part.id == partID else { return part }
            // `origin` carries through. It is what the part *is*; `name` is only
            // what it is called, and the user has just changed that.
            return DayPart(id: part.id, name: name,
                           activities: part.activities, origin: part.origin)
        })
    }

}

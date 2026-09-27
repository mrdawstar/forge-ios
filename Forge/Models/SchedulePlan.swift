import Foundation

// MARK: - The week, as a value

/// One activity, reduced to the four things a planner cares about.
///
/// A flattened `Ritual` rather than the thing itself, and that is the point: a
/// plan has to be computable, previewable and testable without a view model, a
/// store or a `UserDefaults` suite anywhere near it. Everything a planner needs
/// to know about somebody's week fits in here, and nothing it does not need can
/// reach it.
struct ScheduledActivity: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    /// Minutes past midnight, or nil for "some time that day".
    var startMinute: Int?
    /// How long it takes. Zero for an activity that has never been given one.
    var minutes: Int
    /// `Calendar` weekdays, 1 = Sunday. Empty means every day — the same rule
    /// `RitualRepeat.includes` uses, kept identical on purpose.
    var weekdays: Set<Int>
    /// Who this is evidence for, or nil. See `Ritual.identityID`.
    ///
    /// Carried so a planner can keep a person's week balanced across the things
    /// they said they were becoming rather than merely across free hours — an
    /// arrangement that quietly buries one identity under another is worse than
    /// no arrangement, and only this field makes that checkable.
    ///
    /// It is an **id and never the statement**. What leaves the phone is
    /// decided in one place, `AIBrief`, and an opaque identifier that means
    /// nothing outside this device is a different disclosure from the sentence
    /// somebody wrote about who they are. See `AIBrief` for what is deliberately
    /// absent from it.
    ///
    /// Defaulted so that every existing construction site keeps compiling and
    /// keeps meaning exactly what it meant — untagged, which is what every
    /// activity on every phone is until somebody says otherwise.
    var identityID: String? = nil

    func happens(on weekday: Int) -> Bool {
        weekdays.isEmpty || weekdays.contains(weekday)
    }

    /// When it ends, for the overlap arithmetic a planner does.
    var endMinute: Int? {
        guard let startMinute, minutes > 0 else { return startMinute }
        return startMinute + minutes
    }
}

// MARK: - What a plan actually is

/// One edit to somebody's week.
///
/// **This is the whole reason the AI work is not a chat window.** A model that
/// answers in prose leaves the user to go and do the thing themselves, which is
/// the same amount of work they had before plus reading. A model that answers in
/// these can have its answer *applied*, and — just as important — shown first, so
/// nobody's week is rearranged by something they have not read.
///
/// Every case carries what it is replacing. That is what lets the review screen
/// say "07:00, was 09:30" rather than "07:00", and it is the difference between
/// a proposal somebody can judge and a list of assertions.
enum ScheduleChange: Identifiable, Equatable, Sendable {
    /// Give an activity a clock time, or move the one it has.
    case time(id: String, name: String, minute: Int, was: Int?)
    /// Change how long it takes.
    case duration(id: String, name: String, minutes: Int, was: Int)
    /// Change which days of the week it happens on.
    case days(id: String, name: String, weekdays: Set<Int>, was: Set<Int>)
    /// Something that is not in the day yet.
    case create(draft: ActivityDraft)
    /// An activity that **already exists in the catalogue** and is not in the
    /// day, taken up on the days and at the hour proposed.
    ///
    /// Distinct from `.create` on purpose, and the distinction is not cosmetic.
    /// `.create` mints a user-made activity with a fresh id; adopting "Call
    /// someone" that way would produce a *copy* of a shipped activity — a
    /// second id for the same act, with the library's own subtitle, icon,
    /// verification and dimension filing all left behind, and every count that
    /// runs over time split between the two. The planner recommends out of the
    /// library, so it needs a change that says "this one, the real one".
    case adopt(id: String, name: String, minutes: Int, weekdays: Set<Int>, minute: Int?)

    var id: String {
        switch self {
        case .time(let id, _, _, _): "time.\(id)"
        case .duration(let id, _, _, _): "duration.\(id)"
        case .days(let id, _, _, _): "days.\(id)"
        case .create(let draft): "create.\(draft.label)"
        case .adopt(let id, _, _, _, _): "adopt.\(id)"
        }
    }

    var activityName: String {
        switch self {
        case .time(_, let name, _, _), .duration(_, let name, _, _), .days(_, let name, _, _):
            name
        case .create(let draft):
            draft.label
        case .adopt(_, let name, _, _, _):
            name
        }
    }

    /// What this change does, in the fewest words that are still true.
    var summary: String {
        switch self {
        case .time(_, _, let minute, let was):
            if let was, was != minute {
                return "\(ClockMinute.label(minute)), was \(ClockMinute.label(was))"
            }
            return "At \(ClockMinute.label(minute))"

        case .duration(_, _, let minutes, let was):
            let now = ClockMinute.duration(minutes) ?? "no set length"
            if was > 0, was != minutes {
                return "\(now), was \(ClockMinute.duration(was) ?? "unset")"
            }
            return now

        case .days(_, _, let weekdays, _):
            return RitualRepeat(weekdays: weekdays).label

        case .create(let draft):
            var parts: [String] = ["New"]
            if let start = draft.startMinute { parts.append(ClockMinute.label(start)) }
            parts.append(draft.repeats.label.lowercased())
            return parts.joined(separator: " · ")

        case .adopt(_, _, _, let weekdays, let minute):
            var parts: [String] = []
            if let minute { parts.append(ClockMinute.label(minute)) }
            parts.append(RitualRepeat(weekdays: weekdays).label.lowercased())
            return parts.joined(separator: " · ")
        }
    }

    var symbol: String {
        switch self {
        case .time: "clock"
        case .duration: "timer"
        case .days: "calendar"
        case .create, .adopt: "plus"
        }
    }
}

/// A proposed week, and the edits that would produce it.
///
/// Held rather than applied. Nothing in Forge changes until somebody has seen
/// this and said yes — which is the one rule that makes an automatic planner
/// something people will let near a routine they have spent months building.
struct SchedulePlan: Identifiable, Equatable, Sendable {
    var id = UUID()
    /// One sentence about the shape of it, in Forge's voice.
    var summary: String
    var changes: [ScheduleChange]
    /// Whether a real model wrote this, or the phone worked it out.
    ///
    /// Shown, never hidden. A schedule the phone assembled from the user's own
    /// activities is a genuinely useful thing and a model's answer is a
    /// different useful thing; calling the first one the second would be the app
    /// lying about what it just did. See `LocalForgeAI`.
    var isModelWritten: Bool = false

    var isEmpty: Bool { changes.isEmpty }

    /// The week these changes would produce, applied to a set of activities.
    ///
    /// Pure, so the review screen and the thing that actually writes the changes
    /// can never disagree about what "apply" means — the preview is not a
    /// separate rendering of the plan, it is the same arithmetic run twice.
    func projected(onto activities: [ScheduledActivity]) -> [ScheduledActivity] {
        var result = activities
        var index = Dictionary(uniqueKeysWithValues: activities.enumerated().map { ($1.id, $0) })

        for change in changes {
            switch change {
            case .time(let id, _, let minute, _):
                guard let slot = index[id] else { continue }
                result[slot].startMinute = minute

            case .duration(let id, _, let minutes, _):
                guard let slot = index[id] else { continue }
                result[slot].minutes = minutes

            case .days(let id, _, let weekdays, _):
                guard let slot = index[id] else { continue }
                result[slot].weekdays = weekdays

            case .create(let draft):
                // Provisional, and only ever used by the preview: the real id is
                // minted by `Ritual.makeCustom` at the moment of applying.
                let provisional = "plan.new.\(draft.label)"
                guard index[provisional] == nil else { continue }
                index[provisional] = result.count
                result.append(
                    ScheduledActivity(
                        id: provisional,
                        name: draft.label,
                        startMinute: draft.startMinute,
                        minutes: draft.minutes,
                        weekdays: draft.repeats.weekdays
                    )
                )

            case .adopt(let id, let name, let minutes, let weekdays, let minute):
                // The real id, because the activity really exists. An adopt for
                // something already in the week is a no-op rather than a
                // duplicate row in the preview.
                guard index[id] == nil else { continue }
                index[id] = result.count
                result.append(
                    ScheduledActivity(
                        id: id, name: name, startMinute: minute,
                        minutes: minutes, weekdays: weekdays
                    )
                )
            }
        }
        return result
    }

    /// The seven days the projection produces, each in clock order.
    ///
    /// Monday first. A week that starts on Sunday reads as a fortnight to most
    /// of the people who will see it — the same reasoning `RitualRepeat.label`
    /// already uses, kept in step deliberately.
    func week(onto activities: [ScheduledActivity]) -> [PlannedDay] {
        let projected = projected(onto: activities)
        return [2, 3, 4, 5, 6, 7, 1].map { weekday in
            PlannedDay(
                weekday: weekday,
                items: projected
                    .filter { $0.happens(on: weekday) }
                    .sorted { ($0.startMinute ?? .max) < ($1.startMinute ?? .max) }
            )
        }
    }
}

/// One day of a proposed week.
struct PlannedDay: Identifiable, Equatable, Sendable {
    let weekday: Int
    var items: [ScheduledActivity]

    var id: Int { weekday }

    /// "Mon". The short form, because seven of these sit in a row.
    var label: String { RitualRepeat.short(weekday) }
}

// MARK: - What the model would be told

/// Everything Forge would hand a model about the person asking, taken once.
///
/// A value rather than the stores it came from, for the same reason
/// `PremiumMoment` is one: it makes "what does the AI know about me" a list in a
/// single place that can be read, tested and — the part that matters — audited.
/// Nothing reaches this struct by accident, so nothing can reach a model by
/// accident either.
///
/// Note what is deliberately absent. **No history, no dates, no per-day record,
/// no health readings, no account, no name, no device.** A planner needs to know
/// what somebody's week is made of, roughly how long they have been at it, and
/// who they said they were becoming; it does not need the record of every
/// morning they have ever had, and the cheapest way to keep that promise is to
/// have no field to put it in.
///
/// Two fields were added when the reading was: `identities` and
/// `chapterIntention`. Both are **sentences the user wrote themselves**, and
/// both are a real widening of what leaves the phone — which is exactly why
/// they are here, in the one struct somebody can read end to end, and why
/// `AIDisclosureView` renders this value verbatim rather than describing it.
/// Note what still is not here even so: the identity *ids* stay out (they mean
/// nothing off the device and would only ever be a join key), and the
/// per-identity evidence counts stay out of everything except the reading,
/// which cannot do its job without them.
struct AIBrief: Equatable, Sendable {
    /// Days kept, ever. Enough to tell a first week from a second year.
    var daysKept: Int = 0
    var streak: Int = 0
    /// The world being walked, by name.
    ///
    /// **Always nil.** The archetypes are gone and nothing sets this any more.
    /// It survives because `RemoteForgeAI` encodes it into the request body and
    /// the edge function's schema still names the field — removing it here is a
    /// wire-format change to a deployed service, which is not a change to make
    /// from the client side alone. It is not rendered on the disclosure screen,
    /// because a row reading "None" for every user is a question with no answer.
    var world: String?
    /// The week as it stands — what the planner is rearranging.
    var activities: [ScheduledActivity] = []
    /// The day's movements, if it has any — "Before the world", and so on.
    var parts: [String] = []
    /// When the phone is set to wake them, in minutes past midnight.
    var wakeMinutes: Int?

    /// The statements somebody wrote about who they are becoming.
    ///
    /// The sentences, not the ids. A planner that knows one of these weeks is
    /// meant to be evidence for "someone who trains" can keep it from being
    /// buried under the other four; without them it is arranging free hours.
    var identities: [String] = []

    /// What the open chapter is for, in the user's own words, or empty.
    ///
    /// Six weeks of intent in one sentence, which is the single most useful
    /// thing a model could be told about a week it is being asked to arrange —
    /// and the single most personal. It is here because a plan that ignores it
    /// is a plan about a calendar rather than about a life.
    var chapterIntention: String = ""

    /// The week being read back, when one is — and nil for every other call.
    ///
    /// Only `reading(brief:)` sets this. A planner does not need to know which
    /// Fridays somebody missed and a challenge does not either, so neither of
    /// them sends it: the widest thing Forge ever transmits is transmitted only
    /// by the one feature that cannot work without it.
    ///
    /// It lives on the brief rather than as a second parameter so that "what
    /// leaves the phone" stays answerable by reading one struct. See
    /// `AIDisclosureView`, which shows this field to the user in full.
    var week: ReviewFacts?

    var isEmpty: Bool { activities.isEmpty }

    /// Whether anything in here is a sentence somebody wrote, as opposed to a
    /// count or a clock time. Read by the disclosure screen, which words itself
    /// differently when the answer is no.
    var carriesWrittenWords: Bool {
        !identities.isEmpty || !chapterIntention.isEmpty
    }
}

// MARK: - The record, read back

/// One true sentence about a week or a chapter, and who wrote it.
///
/// The return of `ForgeAI.reading(brief:)`, and the shape is the whole point:
/// the sentence and the provenance travel together and cannot be separated by a
/// call site. There is no initialiser that produces a model-written reading
/// without saying so, and `isModelWritten` is not defaulted to `true` anywhere.
///
/// A reading that fails validation never becomes one of these. See
/// `ReviewObservation.validate(_:against:)` — the model's sentence is checked
/// against the record it claims to describe *before* it is wrapped in this, and
/// a sentence that asserts anything the record does not support is discarded in
/// favour of the rules. A false claim about somebody's own life is the one
/// failure this product does not survive, so the validator is the load-bearing
/// part of the feature and the prompt is merely the cheap part.
struct PracticeReading: Equatable, Sendable {
    /// The observation itself. One sentence, sometimes two.
    var observation: String
    /// Whether a model wrote it, or the phone worked it out.
    var isModelWritten: Bool = false
}

// MARK: - The seam

/// Everything Forge would ask a model to do.
///
/// One protocol, three methods, and no network anywhere near the rest of the
/// app. It exists now — before there is anything behind it — so that connecting a
/// real model later is a matter of writing one conforming type and handing it to
/// `ContentView`, rather than of finding every screen that has grown an opinion
/// about how to talk to an API.
protocol ForgeAI: Sendable {

    /// Whether a real model is behind this. Views ask, so the one thing they
    /// must never do — imply a model wrote something it did not — is impossible
    /// to do by accident.
    var isConnected: Bool { get }

    /// A challenge made for this person, at this difficulty, aimed here.
    ///
    /// `wish` is what they typed, if they typed anything: "something to stop me
    /// procrastinating". Empty is the ordinary case.
    func challenge(
        brief: AIBrief,
        difficulty: ChallengeDifficulty,
        focus: ChallengeFocus,
        wish: String
    ) async throws -> DailyChallenge

    /// A week, proposed, in answer to whatever they typed.
    ///
    /// The same method answers "plan my week" and "move my workout to Wednesday".
    /// They are the same request with different amounts of it already decided,
    /// and splitting them into two entry points would make the user classify
    /// their own sentence before typing it.
    func plan(brief: AIBrief, request: String) async throws -> SchedulePlan

    /// The record, read back to the person who made it.
    ///
    /// The only method here that produces a claim *about the user* rather than
    /// a proposal *for* them, and it is therefore the only one with a hard rule
    /// attached: **whatever comes back is checked against the record before it
    /// is shown.** A plan that misreads a sentence proposes a bad Tuesday and
    /// the user declines it; a reading that misreads the record tells somebody
    /// something untrue about their own life, which they have no way to check
    /// and every reason to believe. See `ReviewObservation.validate(_:against:)`.
    ///
    /// The week it is reading rides in `brief.week`, so that everything which
    /// leaves the phone for any reason is still described by exactly one
    /// struct. A reading asked for with no week in the brief throws
    /// `.nothingToRead` rather than inventing one.
    func reading(brief: AIBrief) async throws -> PracticeReading
}

enum ForgeAIError: Error, Equatable {
    /// The sentence was not one the phone can work out on its own.
    ///
    /// Named for what it originally meant — "a model would have got this and
    /// there is not one" — and kept because that is still true. What changed is
    /// what it *says*: 1.0 ships with the model deliberately off (see
    /// `RemoteForgeAI.isModelEnabled`), so telling somebody their request is
    /// waiting on a connection is telling them to come back for something that
    /// is not coming. The message teaches the grammar that does work instead.
    case notConnected
    /// There is nothing in the day to arrange.
    case nothingToPlan
    /// A reading was asked for with no week in the brief.
    case nothingToRead
    /// Understood, and it would change nothing.
    case noChange
    /// The model answered, and what it said did not survive being checked
    /// against the record. Never surfaced to a user as an error — every caller
    /// falls back to the phone's own reading — but distinct so it can be
    /// counted, tested and noticed.
    case unverifiable
    case failed

    /// What the screen says. Written here rather than in the view because these
    /// are product sentences, and a second copy of them in a `catch` block is
    /// how two screens end up describing the same failure differently.
    var message: String {
        switch self {
        case .notConnected:
            "Forge did not follow that one. It understands hours you cannot move (\"I work 9 to 17\"), how often something should happen (\"train three times\"), moving one activity to another day, and shifting everything later or earlier."
        case .nothingToPlan:
            "There is nothing in your week yet. Add an activity or two first — Forge arranges what you already keep."
        case .nothingToRead:
            "There is no week here to read yet."
        case .noChange:
            "Your week already looks like that. Nothing to change."
        case .unverifiable:
            "Forge could not check that against your record, so it did not show it."
        case .failed:
            "That did not come through. Nothing about your week has changed."
        }
    }
}

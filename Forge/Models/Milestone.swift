import Foundation

/// Numbers as words.
///
/// A day is something you did, not a score. "Thirty days" says that;
/// "30" reads as a counter somebody is watching. Past a hundred the words grow
/// longer than the sentence they sit in, so the figures take back over.
///
/// Pinned to English rather than the device locale, because every other string
/// in Forge is an English literal — a spelled-out number in one language beside
/// a hand-written sentence in another would read as a bug.
enum ForgeCount {
    static func spelled(_ value: Int) -> String {
        guard (0...100).contains(value) else { return "\(value)" }
        guard let words = speller.string(from: NSNumber(value: value)) else { return "\(value)" }
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    private static let speller: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()
}

// MARK: - What a milestone counts

/// The thing a milestone is measured against.
///
/// Two answers, and only two, because there are only two things Forge actually
/// counts: whole days that were kept, and days a particular activity was done.
/// Anything else somebody might want to aim at — hours, streaks, a personal
/// best — is either not recorded or is a number whose job is to be beaten, and
/// neither belongs on a marker of practice.
enum MilestoneSubject: Codable, Equatable, Hashable, Sendable {
    /// Whole days earned. What the shipped ladder counts.
    case daysKept
    /// Days one activity was finished on.
    case activity(String)

    var activityID: String? {
        if case let .activity(id) = self { return id }
        return nil
    }

    /// Stored as a plain string — an activity id, or empty for the day itself.
    ///
    /// Written out rather than synthesised, and the reason is the one this
    /// codebase keeps relearning: the compiler's encoding for an enum with an
    /// associated value is a nested object keyed by the case name, and its
    /// decoder **throws** on a case it does not recognise. One throw fails the
    /// whole array, so the day somebody's build sees a subject written by a
    /// later one is the day their own milestones vanish. A bare string cannot
    /// fail to decode into something usable — see `VerificationMethod`, which
    /// learned this the same way.
    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = raw.isEmpty ? .daysKept : .activity(raw)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(activityID ?? "")
    }
}

/// How a target is worded — and *only* how it is worded.
///
/// "Read 30 days", "Meditate 100 times" and "Workout 50 sessions" are the same
/// arithmetic three times over: an activity can be completed at most once in a
/// day, so days and times are the same number. What differs is which of those
/// words somebody would actually use about their own practice, and being able
/// to pick is the difference between a milestone that sounds like theirs and
/// one that sounds like a form they filled in.
enum MilestoneUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case days, times, sessions

    var id: String { rawValue }

    /// Anything unrecognised becomes days.
    ///
    /// The synthesised decoder throws on a raw value it has never heard of, and
    /// `decodeIfPresent` does **not** rescue that — it returns nil for a missing
    /// key, not for a value it cannot read. So without this a unit added by a
    /// later build would fail the whole array on an older one. Days is the safe
    /// landing: every unit counts the same thing, so being wrong here costs a
    /// word and never a number.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MilestoneUnit(rawValue: raw) ?? .days
    }

    /// "days" / "times" / "sessions", as the picker offers them.
    var plural: String { rawValue }

    func noun(_ count: Int) -> String {
        guard count == 1 else { return plural }
        return switch self {
        case .days: "day"
        case .times: "time"
        case .sessions: "session"
        }
    }

    /// "30 days", "100 times", "50 sessions".
    func phrase(_ count: Int) -> String { "\(count) \(noun(count))" }

    /// "18 days to go", "40 more times", "12 sessions to go" — whichever of
    /// those is the sentence somebody would say.
    func remaining(_ count: Int) -> String {
        switch self {
        case .times: count == 1 ? "One more time" : "\(count) more times"
        default: "\(count) \(noun(count)) to go"
        }
    }
}

// MARK: - One somebody made

/// A marker the user set for themselves.
///
/// Stored, unlike the shipped ladder, because it is the one part of this screen
/// that is not derivable — Forge cannot work out from a history that somebody
/// wanted to read for thirty days. Everything *about* it is still derived: the
/// count, the percentage and whether it has been reached are all read out of
/// `ProgressStore` on demand, so a custom milestone can no more disagree with
/// the record than a shipped one can.
///
/// `reachedAt` is the single exception, and it is not a cache of the progress —
/// it is the answer to a different question. "Is this reached" is arithmetic;
/// "have we already congratulated them for it" is a fact about what the app has
/// done, and it has to be written down or the celebration fires on every launch
/// forever.
struct CustomMilestone: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var name: String
    /// An SF Symbol, chosen from the same catalogue activities use.
    var symbol: String
    var subject: MilestoneSubject
    var unit: MilestoneUnit
    var target: Int
    var createdAt: Date
    /// When the app first saw this reached, and therefore whether the
    /// celebration is still owed. Never cleared once set: a milestone that was
    /// reached and then fell back — an activity undone, a day taken back — is
    /// still a thing that happened, and congratulating somebody twice for it
    /// would be worse than the arithmetic wobbling.
    var reachedAt: Date?

    /// The smallest and largest a target may be.
    ///
    /// One is allowed because "do it once" is a real intention. The ceiling is
    /// ten years of daily practice, which is past every honest use and short of
    /// the numbers people type to see what happens.
    static let targetRange = 1...3_650

    init(
        id: String = "milestone.\(UUID().uuidString)",
        name: String,
        symbol: String,
        subject: MilestoneSubject,
        unit: MilestoneUnit,
        target: Int,
        createdAt: Date = .now,
        reachedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.subject = subject
        self.unit = unit
        self.target = min(max(target, Self.targetRange.lowerBound), Self.targetRange.upperBound)
        self.createdAt = createdAt
        self.reachedAt = reachedAt
    }

    /// Tolerant of anything ever written to disk, for the same reason every
    /// other decoder in this app is hand-written: one throw fails the whole
    /// array, and the failure mode is somebody opening Forge to find the
    /// milestones they set for themselves gone. Only `id` is required.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Milestone"
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? ActivityIcons.fallback
        subject = try c.decodeIfPresent(MilestoneSubject.self, forKey: .subject) ?? .daysKept
        unit = try c.decodeIfPresent(MilestoneUnit.self, forKey: .unit) ?? .days
        let raw = try c.decodeIfPresent(Int.self, forKey: .target) ?? 1
        target = min(max(raw, Self.targetRange.lowerBound), Self.targetRange.upperBound)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        reachedAt = try c.decodeIfPresent(Date.self, forKey: .reachedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, symbol, subject, unit, target, createdAt, reachedAt
    }
}

/// What the composer collects. One value rather than seven arguments, for the
/// same reason `ActivityDraft` is one.
struct MilestoneDraft: Equatable {
    var name: String
    var symbol: String
    var subject: MilestoneSubject
    var unit: MilestoneUnit
    var target: Int

    static func blank() -> MilestoneDraft {
        MilestoneDraft(
            name: "", symbol: ActivityIcons.fallback,
            subject: .daysKept, unit: .days, target: 30
        )
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    // Deliberately no `isValid`. There is nothing here a user can get wrong:
    // the name falls back to a true description of what they built, and the
    // target is clamped by `CustomMilestone.init` — which is the one place that
    // rule lives. A second copy of it here, rejecting rather than clamping,
    // meant a draft could be silently dropped on save by a bound the composer's
    // own stepper made unreachable, and two policies for one rule is how they
    // start disagreeing.
}

// MARK: - One as it is shown

/// A marker of practice, measured against what somebody has actually done.
///
/// Not an achievement, and deliberately not rewarded: there is nothing to
/// collect here and nothing is paid out for reaching one. A milestone is a
/// sentence about who somebody has become, and the only thing it needs in order
/// to be worth reading is being true.
///
/// The ladder is counted in days *kept*, never in streaks. A cumulative number
/// cannot be taken away by one bad week, which is the whole reason it is the one
/// Forge shows: somebody who has kept two hundred days and missed yesterday is
/// still somebody who keeps days. A custom one counts whatever it was told to
/// count, and the same rule applies — days an activity was done is cumulative
/// too, and nothing here can go backwards on a bad Tuesday.
///
/// **Everything here is now user-authored.** Forge shipped five of these at
/// 1/7/30/100/365 days kept, and they counted the same number as the seven
/// blades at 0/1/3/7/14/30/60 — two ladders against one figure, drawn on the
/// same screen, so "Folded Sword · 7 days" sat above "Seven days · A week of
/// this" and each made the other read as filler. The shipped rungs are gone and
/// their job moved to `Ladder`, which is one progression and does not run out at
/// sixty days. What is left in this file is the part that was never duplicated
/// and is the best thing on that screen: a marker somebody set for themselves,
/// which Forge could not have derived and has no opinion about.
struct Milestone: Identifiable, Equatable {
    let id: String
    let name: String
    let note: String
    /// The library icon key, for the shipped ladder.
    let iconKey: String
    /// An SF Symbol, for one somebody made. Takes precedence over `iconKey`.
    let symbol: String?
    /// What this asks for.
    let target: Int
    let current: Int
    let unit: MilestoneUnit
    let isCustom: Bool

    init(
        id: String,
        name: String,
        note: String,
        iconKey: String = "sparkle",
        symbol: String? = nil,
        target: Int,
        current: Int,
        unit: MilestoneUnit = .days,
        isCustom: Bool = false
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.iconKey = iconKey
        self.symbol = symbol
        self.target = target
        self.current = current
        self.unit = unit
        self.isCustom = isCustom
    }

    var isReached: Bool { current >= target }
    var progress: Double {
        guard target > 0 else { return 0 }
        return min(1.0, Double(current) / Double(target))
    }
    /// Rounded down, so nothing reads "100%" until it actually is. A bar at
    /// ninety-nine and a half rounding up to a hundred beside an unfilled bar is
    /// the app telling somebody they are finished when they are not.
    var percent: Int { isReached ? 100 : Int(progress * 100) }
    var remaining: Int { max(0, target - current) }
    var countLabel: String { "\(min(current, target))/\(target)" }
    var remainingLabel: String { unit.remaining(remaining) }

    // The shipped ladder used to live here as `all(from:path:)` and `forge(kept:)`.
    // Both are deleted rather than deprecated: a second answer to "how far along
    // is this practice" that still compiles is a second answer somebody puts
    // back on a screen. `Ladder` is the one, it carries the world renames that
    // used to be applied here — by the same milestone ids, so no archetype
    // needed a word changed — and it does not stop at a year.
}

extension CustomMilestone {
    /// This milestone as the list draws it.
    ///
    /// `activityName` is handed in rather than looked up, for the same reason
    /// `BladeViewModel.mostKept` takes a resolver: an activity somebody invented
    /// lives on the Forge tab's view model, and nothing in `Models` has any
    /// business knowing that.
    func measured(current: Int, activityName: String?) -> Milestone {
        Milestone(
            id: id,
            name: name,
            note: note(activityName: activityName),
            symbol: symbol,
            target: target,
            current: current,
            unit: unit,
            isCustom: true
        )
    }

    /// "Read · 30 days", or "Days kept · 100 days" for one counting the day
    /// itself. Says what is being counted, because the name is the user's and
    /// may not — "The long haul" is a fine name and tells you nothing.
    func note(activityName: String?) -> String {
        let subject = switch self.subject {
        case .daysKept: "Days kept"
        case .activity: activityName ?? "An activity you removed"
        }
        return "\(subject) · \(unit.phrase(target))"
    }

    /// What to call one aimed at a given subject, before the user names it
    /// themselves. "Read 30 days" is exactly the name somebody would type, so
    /// the field starts there rather than empty.
    static func suggestedName(
        target: Int, unit: MilestoneUnit, activityName: String?
    ) -> String {
        guard let activityName, !activityName.isEmpty else {
            return "\(ForgeCount.spelled(target)) days kept"
        }
        return "\(activityName) \(unit.phrase(target))"
    }
}

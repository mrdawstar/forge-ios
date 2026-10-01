import Foundation

// MARK: - Verification

/// How an activity gets confirmed.
///
/// Three answers, and honor is not the one left over. Either the phone already
/// measured the thing, or you say it was done — and for a prayer, a cold
/// shower, or a bed you made, saying so is the only confirmation an app can
/// honestly offer. Most of a day lives here, by design.
///
/// `basic` is the third, and it is deliberately the plainest thing in the app:
/// a checkbox, ticked, done. It exists because "Your Word" asks a question, and
/// a question is the right weight for a promise and the wrong weight for
/// "vitamins". Somebody who wants a list they can run down at speed should not
/// have to answer for each row, and making them was the app confusing ceremony
/// with meaning.
enum VerificationMethod: String, Codable, CaseIterable, Identifiable {
    // `health` (Apple Health auto-completion) was removed with HealthKit.
    // Activities stored with it decode as `.honor` — see `init(from:)`.
    /// Nobody checks this one but you.
    case honor
    /// A checkbox, and nothing else asked.
    case basic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .honor: "Your Word"
        case .basic: "Basic Check"
        }
    }

    /// The one line shown under the suggestion. Written to explain the choice,
    /// never to justify a demand.
    var rationale: String {
        switch self {
        case .honor: "Nobody checks this one but you."
        case .basic: "One tap, and it's done."
        }
    }

    var symbol: String {
        switch self {
        case .honor: "hand.raised.fill"
        case .basic: "checkmark.circle"
        }
    }

    /// Whether ticking this one asks anything of the user.
    ///
    /// The one behavioural difference between the three, in one place, so a
    /// tap and a row's own hint can never disagree about what happens next.
    var asksForConfirmation: Bool { self == .honor }

    /// Tolerant of everything that has ever been written to disk.
    ///
    /// Forge used to have `.aiVerified` and `.aiAssisted`, and both were
    /// persisted inside user-made activities and library edits. The synthesised
    /// decoder throws on a raw value it does not recognise, and one throw fails
    /// the whole array — so without this, updating would silently take away
    /// every activity somebody had made for themselves.
    ///
    /// Anything unrecognised becomes honor rather than only the two names we
    /// happen to remember: honor is the one tier that claims nothing was
    /// measured, which makes it the only safe place to put a value we cannot
    /// interpret. A bed you made is a promise you kept.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = VerificationMethod(rawValue: raw) ?? .honor
    }
}

/// What the user has taught us by disagreeing.
///
/// Two kinds of memory. `tokenPreferences` is specific — you changed "day
/// pages" to honor, so anything else you name with those words starts there.
/// `overrideTally` is a disposition — somebody who has moved four different
/// activities off Health is telling us something about how they want to be
/// treated, and the classifier should stop reaching for a sensor on close
/// calls.
struct VerificationMemory: Codable, Equatable {
    var tokenPreferences: [String: String] = [:]
    var overrideTally: [String: Int] = [:]

    static let empty = VerificationMemory()

    private enum CodingKeys: String, CodingKey {
        case tokenPreferences
        case overrideTally
    }

    init() {}

    /// Written out rather than synthesised, and the defaults above are the
    /// reason it has to be.
    ///
    /// A default on a property is used by the memberwise initialiser and by
    /// nothing else — the synthesised decoder still treats every key as
    /// required, so `{}` throws. That is not a hypothetical shape: it is what
    /// the signup trigger in `0001` puts in `verification_memory`, and it is
    /// therefore what every brand-new account holds until something overwrites
    /// it. Decoding the profile row would fail, the failure would be a schema
    /// error rather than a network one, and the sync engine treats those as
    /// permanent — so the first sync of every new account failed, and could
    /// never recover, because the pull throws before anything is pushed.
    ///
    /// A missing key means nothing has been learned yet, which is exactly what
    /// an empty memory is.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tokenPreferences =
            try container.decodeIfPresent([String: String].self, forKey: .tokenPreferences) ?? [:]
        overrideTally =
            try container.decodeIfPresent([String: Int].self, forKey: .overrideTally) ?? [:]
    }

    /// The method this user reaches for when they disagree — but only once
    /// they've said it enough times to mean it, and only if it's a clear
    /// favourite rather than a tie.
    var leaning: VerificationMethod? {
        let ranked = overrideTally.sorted { $0.value > $1.value }
        guard let top = ranked.first, top.value >= 3 else { return nil }
        if ranked.count > 1, ranked[1].value == top.value { return nil }
        return VerificationMethod(rawValue: top.key)
    }

    mutating func record(_ chosen: VerificationMethod, for name: String) {
        overrideTally[chosen.rawValue, default: 0] += 1
        for token in ActivityVerification.tokens(in: name) {
            tokenPreferences[token] = chosen.rawValue
        }
    }
}

/// Decides how a user-made activity should be confirmed, from its name and the
/// icon chosen for it.
///
/// Deliberately deterministic and on-device. The suggestion has to land between
/// keystrokes, has to work on a plane, and — for an app whose whole premise is
/// promises you make to yourself — has no business sending the list of those
/// promises anywhere to be graded.
enum ActivityVerification {

    // MARK: - Entry point

    static func suggest(
        name: String,
        symbol: String? = nil,
        memory: VerificationMemory = .empty
    ) -> VerificationMethod {
        let words = tokens(in: name)

        // Something the user said explicitly about these words outranks
        // everything the lexicon believes.
        for word in words {
            if let raw = memory.tokenPreferences[word],
               let taught = VerificationMethod(rawValue: raw) {
                return taught
            }
        }

        var scores: [VerificationMethod: Int] = [:]
        for entry in lexicon where entry.tokens.contains(where: words.contains) {
            scores[entry.method, default: 0] += entry.weight
        }
        // The icon is a second opinion, never a first one — it breaks ties and
        // rescues names the lexicon has never seen, but a word in the name
        // always outweighs a picture beside it.
        if let symbol, let affinity = iconAffinity(for: symbol) {
            scores[affinity, default: 0] += 2
        }

        let ranked = scores.sorted { $0.value > $1.value }
        guard let best = ranked.first else {
            // Nothing recognised. Claiming the phone measures a thing we do not
            // understand is the one answer that is certainly wrong, so an
            // unknown activity is taken on trust.
            return memory.leaning ?? .honor
        }

        // A close call is exactly where a user's disposition should decide.
        let runnerUp = ranked.dropFirst().first?.value ?? 0
        if best.value - runnerUp <= 1, let leaning = memory.leaning {
            return leaning
        }
        return best.key
    }

    /// Lowercased, punctuation-stripped, stop-words dropped, and de-pluralised.
    /// "Read 10 pages of a book" → `["read", "pages", "page", "book"]`.
    ///
    /// The singular is emitted *alongside* the original rather than replacing
    /// it, so the lexicon can hold whichever form reads naturally without every
    /// entry needing both. Without this, "Deadlifts" missed a lexicon that
    /// listed "deadlift" and fell all the way through to honor.
    static func tokens(in name: String) -> Set<String> {
        let cleaned = name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
        var result: Set<String> = []
        for word in String(cleaned).split(separator: " ").map(String.init) {
            guard word.count > 1, !stopWords.contains(word) else { continue }
            result.insert(word)
            // "glass" and "press" are not plurals; "-ss" is the giveaway.
            if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") {
                result.insert(String(word.dropLast()))
            }
        }
        return result
    }

    // MARK: - Lexicon
    //
    // Weights encode how decisive a word is, not how common. "Prayer" can only
    // mean one thing; "practice" could be a language or a bench press.
    //
    // With two methods left, the only question a row answers is whether the
    // phone already measures the thing. The honor rows are kept split into the
    // vocabularies they came from rather than merged into one: their weight is
    // what settles a name that also carries a movement word — "cold plunge"
    // reads as a shower, not a swim — and a name that lands in two of them
    // should outrank one that clips a single health word.

    private static let lexicon: [(tokens: Set<String>, method: VerificationMethod, weight: Int)] = [
        // Measured already — the strongest signal, because it asks nothing at all.
        (["run", "running", "jog", "jogging", "sprint", "5k", "10k", "marathon"], .honor, 4),
        (["walk", "walking", "walks", "steps", "stroll"], .honor, 4),
        (["workout", "exercise", "gym", "training", "cardio", "hiit"], .honor, 3),
        // No "press": a French press is not a bench press.
        (["lift", "lifting", "weights", "deadlift", "squat", "bench"], .honor, 3),
        (["cycle", "cycling", "bike", "biking", "spin"], .honor, 3),
        (["swim", "swimming", "laps"], .honor, 3),
        (["hike", "hiking", "climb", "climbing"], .honor, 3),
        (["yoga", "pilates", "stretch", "stretching", "mobility", "warmup"], .honor, 2),
        (["pushups", "pullups", "situps", "plank", "reps", "sets"], .honor, 2),

        // A thing exists afterwards, and a bed you made is a promise you kept.
        (["water", "hydrate", "glass", "bottle"], .honor, 4),
        (["bed", "sheets", "duvet", "pillows"], .honor, 4),
        (["breakfast", "lunch", "dinner", "meal", "eat", "cook", "protein"], .honor, 3),
        (["fruit", "vegetables", "veg", "salad", "greens", "smoothie"], .honor, 3),
        (["vitamins", "supplements", "pills", "medication", "meds"], .honor, 3),
        (["dishes", "sink", "laundry", "tidy", "clean", "vacuum", "bins"], .honor, 3),
        (["plants", "water the plants", "garden"], .honor, 3),
        (["coffee", "tea", "espresso", "brew"], .honor, 2),
        (["teeth", "brush", "floss"], .honor, 2),

        // Begun in the open, finished on your own.
        (["read", "reading", "book", "pages", "chapter"], .honor, 4),
        (["journal", "journalling", "diary", "notebook", "handwrite"], .honor, 3),
        (["write", "writing", "draft", "essay", "pages"], .honor, 2),
        // No bare "french" or "german": a French press is a coffee maker and a
        // German shepherd is a dog. The unambiguous words carry this row.
        (["language", "vocabulary", "vocab", "duolingo", "anki", "flashcards",
          "lesson", "spanish", "italian", "japanese", "mandarin", "portuguese"], .honor, 3),
        (["study", "studying", "revise", "revision", "homework", "course"], .honor, 3),
        (["piano", "guitar", "instrument", "practice", "rehearse", "scales"], .honor, 2),
        (["draw", "drawing", "paint", "painting", "sketch"], .honor, 2),

        // Inside your head, or nobody's business.
        (["pray", "prayer", "praying", "scripture", "devotional", "rosary"], .honor, 5),
        (["meditate", "meditation", "mindfulness", "stillness", "silence"], .honor, 5),
        (["breathe", "breathing", "breath", "breathwork"], .honor, 5),
        (["gratitude", "grateful", "thankful", "affirmations", "intentions"], .honor, 5),
        (["reflect", "reflection", "think", "thinking", "visualise", "visualize"], .honor, 4),
        (["plan", "planning", "prioritise", "prioritize", "review"], .honor, 3),
        // No "wash": "wash the dishes" is a thing the camera can check.
        (["shower", "cold", "bath", "sauna", "plunge"], .honor, 4),
        (["code", "coding", "program", "programming", "debug", "leetcode"], .honor, 4),
        (["therapy", "counselling", "call", "text", "message"], .honor, 3),
        (["phone", "screen", "scroll", "feed", "social", "detox"], .honor, 3),
        (["sleep", "rest", "nap", "wind", "unwind"], .honor, 2),
    ]

    /// Words that carry no signal and would otherwise let a stray match win.
    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "your", "you", "any", "all", "one", "two",
        "min", "mins", "minute", "minutes", "hour", "hours", "day", "daily",
        "morning", "every", "some", "get", "got", "make", "made", "take", "have",
        "out", "off", "not", "before", "after", "then", "into", "from", "own",
    ]

    // MARK: - Icon affinity

    /// The icon the user reached for is a genuine second signal — somebody who
    /// picked the shower glyph has told us something the word "reset" never
    /// would.
    private static func iconAffinity(for symbol: String) -> VerificationMethod? {
        switch ActivityIcons.groupName(for: symbol) {
        case "Movement", "Stillness", "Fuel", "Home", "Mind", "Discipline": .honor
        default: nil
        }
    }
}

// MARK: - How long, when, and how often

/// How much an activity matters when the day does not go to plan.
///
/// Three rungs, and the middle one is the default and the normal case — most of
/// a day is neither optional nor non-negotiable. The words are chosen so that
/// none of them is a grade: an activity marked `light` is not a lesser activity,
/// it is one you decided in advance you could drop, and deciding that in advance
/// is the useful act.
///
/// It changes nothing about whether a day is earned. That was the first design
/// and it was wrong: a priority that quietly re-weighted the count would mean
/// two people with the same finished list had done different amounts, and the
/// one honest number in this app is "everything you planned, done". What it does
/// is mark the row, so a day you are losing has a visible order to abandon it in.
enum RitualPriority: String, Codable, CaseIterable, Equatable, Sendable {
    case light, normal, essential

    var label: String {
        switch self {
        case .light: "If there's time"
        case .normal: "Normal"
        case .essential: "Non-negotiable"
        }
    }

    /// The short form, for a row that has no space for a sentence.
    var badge: String? {
        switch self {
        case .light: "Optional"
        case .normal: nil
        case .essential: "Essential"
        }
    }

    var symbol: String {
        switch self {
        case .light: "circle"
        case .normal: "circle.lefthalf.filled"
        case .essential: "exclamationmark.circle.fill"
        }
    }
}

/// Which days of the week an activity belongs to.
///
/// A set of weekdays rather than an enum of named schedules, because the named
/// schedules are the ones you can build out of a set and the set is the one you
/// cannot build out of names. `Calendar`'s numbering — 1 is Sunday — so nothing
/// has to translate on the way to a date.
///
/// Every activity ships as `.daily`, and an activity that has never been touched
/// decodes as `.daily`, which is what Forge has always done. That matters more
/// than it looks: this is the one new field that can make an activity *not
/// appear*, and the failure mode of a bad default is somebody opening the app to
/// find their day half gone.
struct RitualRepeat: Codable, Equatable, Sendable {
    /// 1 = Sunday … 7 = Saturday, matching `Calendar.component(.weekday,)`.
    var weekdays: Set<Int>

    static let daily = RitualRepeat(weekdays: Set(1...7))
    static let weekdays5 = RitualRepeat(weekdays: [2, 3, 4, 5, 6])
    static let weekends = RitualRepeat(weekdays: [1, 7])

    /// One day of the week and no other — what a newly created activity starts
    /// out as. See `ActivityComposer.Mode.create`.
    static func onlyToday(_ weekday: Int) -> RitualRepeat {
        RitualRepeat(weekdays: [weekday])
    }

    var isDaily: Bool { weekdays.count == 7 }

    /// Whether this belongs to a given `Calendar` weekday.
    ///
    /// An empty set counts as every day rather than as no day. A set can only
    /// become empty by somebody unticking the last box, and the two readings of
    /// that are "I meant never" and "I have not finished choosing" — one of them
    /// silently deletes an activity from every day forever, and the other costs
    /// nothing to be wrong about.
    func includes(_ weekday: Int) -> Bool {
        weekdays.isEmpty || weekdays.contains(weekday)
    }

    /// "Every day", "Weekdays", "Weekends", "Mon, Wed, Fri".
    var label: String {
        if weekdays.isEmpty || isDaily { return "Every day" }
        if weekdays == Self.weekdays5.weekdays { return "Weekdays" }
        if weekdays == Self.weekends.weekdays { return "Weekends" }
        // Monday first, because a week that starts on Sunday reads as a
        // fortnight to most of the people who will see this.
        let order = [2, 3, 4, 5, 6, 7, 1]
        return order.filter(weekdays.contains).map(Self.short).joined(separator: ", ")
    }

    static func short(_ weekday: Int) -> String {
        ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][max(0, min(6, weekday - 1))]
    }

    static func name(_ weekday: Int) -> String {
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][
            max(0, min(6, weekday - 1))
        ]
    }

    /// The days at a glance, for a row with a time beside it and no room for a
    /// sentence: "Daily", "Weekdays", "Weekends", "Sundays", "Mon · Wed · Fri".
    /// The first run's plan reads "Mon · Wed · Fri · 18:00" off this.
    var compactLabel: String {
        if weekdays.isEmpty || isDaily { return "Daily" }
        if weekdays == Self.weekdays5.weekdays { return "Weekdays" }
        if weekdays == Self.weekends.weekdays { return "Weekends" }
        let days = Self.mondayFirst.filter(weekdays.contains)
        if days.count == 1 { return Self.name(days[0]) + "s" }
        return days.map(Self.short).joined(separator: " \u{00B7} ")
    }

    /// The same, said in full, for VoiceOver: "Monday, Wednesday and Friday".
    /// "Mon" read aloud is a syllable, not a day.
    var spokenLabel: String {
        if weekdays.isEmpty || isDaily { return "Every day" }
        if weekdays == Self.weekdays5.weekdays { return "Weekdays" }
        if weekdays == Self.weekends.weekdays { return "Weekends" }
        let names = Self.mondayFirst.filter(weekdays.contains).map(Self.name)
        guard let last = names.last else { return "Every day" }
        if names.count == 1 { return last + "s" }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }

    /// Monday first, as `label` orders them.
    private static let mondayFirst = [2, 3, 4, 5, 6, 7, 1]
}

/// Minutes since midnight, said the way a person says it.
///
/// A free function on `Int` rather than a wrapper type: the value really is just
/// a number of minutes, everything that stores one stores an `Int`, and a
/// `struct TimeOfDay` would have bought a `Codable` conformance and a conversion
/// at every call site in exchange for nothing.
enum ClockMinute {

    /// "6:30 AM", in the user's own locale and 12/24-hour preference.
    static func label(_ minute: Int) -> String {
        let clamped = ((minute % 1440) + 1440) % 1440
        var components = DateComponents()
        components.hour = clamped / 60
        components.minute = clamped % 60
        let calendar = Calendar.current
        guard let date = calendar.date(from: components) else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// "45 min", "2 h", "1 h 30". Never "0 min" — an untimed activity has no
    /// duration to show, which is a different thing from a duration of nothing.
    static func duration(_ minutes: Int) -> String? {
        guard minutes > 0 else { return nil }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest)"
    }

    /// What the duration picker offers, in the order somebody would scan them.
    ///
    /// Chips rather than a number pad, and this list rather than a wheel. The
    /// old field made somebody type "45" into a text box to say three quarters
    /// of an hour, which is the single most-used value in the app; now it is one
    /// tap. The set stops at three hours because a single activity longer than
    /// that is a day, not an activity — and the wheel underneath still reaches
    /// anything this list does not.
    static let commonDurations = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180]
}

/// A user's changes to a library activity. Every field is optional: what is not
/// set still comes from the definition.
struct RitualEdit: Codable, Equatable {
    var label: String? = nil
    var symbol: String? = nil
    var verification: VerificationMethod? = nil
    /// The target in the row's right-hand column. Empty string is a real value
    /// here — it is how somebody clears a shipped activity's target — so this is
    /// nil only when the goal has never been touched.
    var tail: String? = nil
    /// The user's own note. Empty string is a real value, same as `tail`.
    var note: String? = nil
    var minutes: Int? = nil
    /// Doubly optional on purpose. The outer `nil` means "never set a start
    /// time"; `.some(nil)` means "cleared the one this had". Without the
    /// distinction there is no way to take a start time off a library activity
    /// that shipped with one.
    var startMinute: Int?? = nil
    var priority: RitualPriority? = nil
    var repeats: RitualRepeat? = nil
    var category: RitualCategory? = nil
    /// Doubly optional for the same reason `startMinute` is, and it is needed
    /// here for the same shape of reason: the outer `nil` means "never tagged
    /// this", `.some(nil)` means "took the tag off". Without the distinction
    /// there is no way to untag a library activity and have the edit stop
    /// counting as an edit — the untagging would be indistinguishable from
    /// never having tagged it, which is fine until you want "reset to default"
    /// to have something to undo.
    var identityID: String?? = nil

    var isEmpty: Bool {
        label == nil && symbol == nil && verification == nil && tail == nil
            && note == nil && minutes == nil && startMinute == nil
            && priority == nil && repeats == nil && category == nil
            && identityID == nil
    }

    /// Tolerant of every shape ever written to disk.
    ///
    /// The synthesised decoder treats a non-optional property as required and
    /// this type gained seven properties after shipping, so without this every
    /// edit anybody had made to a library activity would fail to decode — and
    /// one throw fails the whole dictionary. See `VerificationMethod` for the
    /// same lesson learned the same way.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol)
        verification = try c.decodeIfPresent(VerificationMethod.self, forKey: .verification)
        tail = try c.decodeIfPresent(String.self, forKey: .tail)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes)
        startMinute = try c.decodeIfPresent(Int?.self, forKey: .startMinute)
        priority = try c.decodeIfPresent(RitualPriority.self, forKey: .priority)
        repeats = try c.decodeIfPresent(RitualRepeat.self, forKey: .repeats)
        // Through `init(migrating:)` so an edit written before the dimensions
        // existed keeps its filing. See `RitualCategory`.
        category = (try c.decodeIfPresent(String.self, forKey: .category))
            .flatMap(RitualCategory.init(migrating:))
        identityID = try c.decodeIfPresent(String?.self, forKey: .identityID)
    }

    init() {}
}

/// The six dimensions of the Forge Shape, and the filing system for every
/// activity in the app.
///
/// # Why this replaced the old five rather than joining them
///
/// The cases used to be `body, mind, home, fuel, focus` — a description of
/// *where in a day something happens*, which is what a picker needs to sort by
/// and nothing else. The Shape needs a different question answered: **which
/// part of a person is this evidence for.** Home and fuel are not parts of a
/// person; they are places and inputs.
///
/// The alternative was to add a second taxonomy beside this one and map between
/// them. That is the shape of bug this codebase spends most of its doc comments
/// designing itself out of: two answers to one question, drifting apart, with
/// nothing to say which is right. So there is one enum, it has six real cases,
/// and every screen that used to sort by the old five sorts by these.
///
/// # Migration
///
/// Old raw values are still on disk, on every custom activity and every library
/// edit anybody has made. `init(migrating:)` maps them, and the two decoders in
/// this file go through it — so nobody opens the app to find their activities
/// unfiled. The mapping is a judgement in two places and worth stating: stored
/// `mind` becomes `intellect` (the commonest user meaning of the word) and
/// stored `focus` becomes `ambition`. The shipped library is re-filed by hand
/// below rather than through this map, which is why `meditate` correctly lands
/// on `mental` while a *user's* old `mind` activity lands on `intellect`.
enum RitualCategory: String, Codable, CaseIterable, Sendable {
    /// A filter, not a dimension. Never assignable, never on the Shape.
    case all
    case physical, intellect, discipline, mental, relationship, ambition

    /// The six, in the order the Shape draws them clockwise from the top. Also
    /// the order every list of dimensions in the app uses, so the polygon and
    /// the rows underneath it can never disagree about which is which.
    static let dimensions: [RitualCategory] = [
        .intellect, .relationship, .discipline, .ambition, .mental, .physical,
    ]

    /// Everything except `all`, which is a filter rather than a category and has
    /// no business being offered as one when somebody is classifying an activity.
    static var assignable: [RitualCategory] { dimensions }

    var label: String {
        switch self {
        case .all: "All"
        case .physical: "Physical"
        case .intellect: "Intellect"
        case .discipline: "Discipline"
        case .mental: "Mental"
        case .relationship: "Relationship"
        case .ambition: "Ambition"
        }
    }

    /// One line saying what the dimension is *for*, in the words somebody would
    /// use about their own life. Shown wherever a dimension is chosen or
    /// inspected — a six-way choice between single nouns is a quiz, and the
    /// difference between "Mental" and "Intellect" is not self-evident to
    /// anybody who has not read this file.
    var meaning: String {
        switch self {
        case .all: ""
        // One short line each. The onboarding stacks all six under the
        // hexagon, and at two lines a row the sixth was clipped on a standard
        // iPhone — the sentence that cost somebody the last choice on the
        // screen. Every one fits on one line at the default text size.
        case .physical: "Your body, and what fuels it."
        case .intellect: "What you read, learn and make."
        case .discipline: "Keeping your word to yourself."
        case .mental: "Staying steady on a bad day."
        case .relationship: "The people you show up for."
        case .ambition: "The work that is truly yours."
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .physical: "figure.run"
        case .intellect: "book"
        case .discipline: "shield"
        case .mental: "brain"
        case .relationship: "person.2"
        case .ambition: "target"
        }
    }

    /// Reads an old or new raw value, and never fails.
    ///
    /// Unknown values land on `nil` rather than throwing, for the reason every
    /// decoder in this file is tolerant: one `throw` fails a whole array, and
    /// the failure mode is somebody opening Forge to find their custom
    /// activities gone.
    init?(migrating raw: String) {
        if let exact = RitualCategory(rawValue: raw) {
            self = exact
            return
        }
        switch raw {
        case "body": self = .physical
        case "fuel": self = .physical
        case "mind": self = .intellect
        case "home": self = .discipline
        case "focus": self = .ambition
        default: return nil
        }
    }
}

struct Ritual: Identifiable, Equatable, Codable {
    let id: String
    /// `var` only so a user-made activity can be renamed; library entries are
    /// never written to.
    var label: String
    let iconKey: String
    let sub: String
    /// The target, shown on the right of the row. `var` because a user-made
    /// activity can be given one, changed, or have it taken away again.
    var tail: String
    var reps: Int = 0
    /// An SF Symbol chosen by the user, set only on user-made activities.
    /// Library entries resolve their glyph through `iconKey` instead; both end
    /// up as the same monochrome symbol, drawn the same way.
    var symbolName: String? = nil
    var isCustom: Bool = false
    /// Set on user-made activities only — what the classifier suggested, or what
    /// the user changed it to. Library entries resolve through the table below
    /// instead, so their verification stays a property of the definition.
    var verificationOverride: VerificationMethod? = nil

    // MARK: What the user can say about it
    //
    // Everything below arrived after the app shipped, which is why the decoder
    // further down is hand-written. All six default to what Forge did before
    // they existed: no note, no clock, ordinary importance, every day.

    /// The user's own sentence about this activity. Distinct from `sub`, which
    /// is the definition's and belongs to us — somebody who renames "Read" to
    /// "Fifty pages" is entitled to say why without losing the shipped subtitle
    /// underneath, and a single field would have made those the same act.
    var note: String = ""

    /// How long it takes, in minutes. `0` means untimed, and untimed is a real
    /// answer rather than a missing one — a made bed does not have a duration.
    var minutes: Int = 0

    /// When it starts, in minutes since midnight. Nil is the ordinary case.
    ///
    /// **A time on an activity is a note to yourself, not an appointment.**
    /// Nothing schedules from this, nothing notifies from it, and a start time
    /// that has come and gone marks nothing. That restraint is deliberate and it
    /// is the difference between this and a calendar: an activity that could be
    /// *late* would mean somebody who slept in had failed the day before
    /// breakfast, on a screen they opened for encouragement.
    var startMinute: Int? = nil

    /// What to abandon first on a day that is not going well. See
    /// `RitualPriority` — it never changes whether a day is earned.
    var priority: RitualPriority = .normal

    /// Which days this belongs to. `.daily` is the default and what everything
    /// written before this field decodes as.
    var repeats: RitualRepeat = .daily

    /// The user's own filing, where they disagreed with ours. Nil keeps the
    /// shipped category — see `category`.
    var categoryOverride: RitualCategory? = nil

    /// Who this is evidence for. See `Identity`.
    ///
    /// **The spine.** Everything Forge records is otherwise a volume — days
    /// kept, a completion rate, a chain — and a volume cannot say what the days
    /// were *for*. This one field is what turns a finished activity into
    /// evidence for a claim somebody made about who they are becoming, and it is
    /// what every reading of direction in the app is derived from.
    ///
    /// **Nil is the ordinary case and must behave exactly as it always has.**
    /// Every activity on every phone is untagged until somebody says otherwise,
    /// and an untagged day is a complete, correct, earnable day forever. Nothing
    /// here may become required, and nothing may read differently for want of
    /// it. An id that no longer resolves — an identity somebody deleted — reads
    /// as untagged too, which is why nothing clears these on deletion; see
    /// `IdentityStore.delete(_:ledger:at:)`.
    var identityID: String? = nil

    /// How this activity gets confirmed.
    var verification: VerificationMethod {
        verificationOverride ?? Ritual.libraryVerification[id] ?? .honor
    }

    /// When it finishes, derived rather than stored.
    ///
    /// Stored end times were the first design and they are a bug with two
    /// spellings: the moment a duration and an end time are both writable they
    /// can disagree, and then some third piece of code has to decide which one
    /// the user meant. A start and a length can only ever say one thing.
    var endMinute: Int? {
        guard let startMinute, minutes > 0 else { return nil }
        return startMinute + minutes
    }

    /// "6:30 – 7:15", or just "6:30" for something with no length, or nil for
    /// something with no time at all.
    var scheduleLabel: String? {
        guard let startMinute else { return nil }
        guard let endMinute else { return ClockMinute.label(startMinute) }
        return "\(ClockMinute.label(startMinute)) – \(ClockMinute.label(endMinute))"
    }

    /// Whether this activity belongs to a given `Calendar` weekday.
    func happens(on weekday: Int) -> Bool { repeats.includes(weekday) }

    /// What the row puts in its right-hand column, which is never empty.
    ///
    /// The target where there is one. Where there is not, the word the activity
    /// is finished on — a column that is filled on some rows and blank on others
    /// reads as missing data rather than as an activity that simply has no
    /// number, and the blank ones were the honor activities, which is the last
    /// place in Forge that should look like an omission.
    ///
    /// Only an activity that carries a mark of its own can come back empty —
    /// a genuinely measurable Health activity and a Basic Check both draw one
    /// in this column instead, and the word would be a second copy of it.
    ///
    /// The fallback follows **behaviour, not the setting**. An activity marked
    /// Health that the phone cannot actually settle is going to be confirmed by
    /// the user saying so, so it says "Honor" like everything else that will
    /// be — the alternative left it wearing neither a heart nor a word, which
    /// is the blank column this property exists to prevent.
    var metadata: String {
        if !tail.isEmpty { return tail }
        return verification == .basic ? "" : "Honor"
    }


    static func == (lhs: Ritual, rhs: Ritual) -> Bool { lhs.id == rhs.id }

    var category: RitualCategory {
        categoryOverride ?? Ritual.categories[id] ?? .discipline
    }

    // MARK: - Reading what is on disk

    /// Hand-written, and it has to stay that way.
    ///
    /// Six properties were added to this type after it shipped, and the
    /// synthesised decoder treats a non-optional property with a default as
    /// **required** — the default belongs to the memberwise initialiser and
    /// nothing else. So a synthesised `init(from:)` would throw on every
    /// activity anybody had already made, and one throw fails the whole array:
    /// updating the app would silently delete every custom activity on the
    /// phone. That is the single worst thing this file could do.
    ///
    /// Only `id` is genuinely required. Everything else falls back to what the
    /// app did before the field existed, so a record written by any build ever
    /// shipped decodes into something usable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        iconKey = try c.decodeIfPresent(String.self, forKey: .iconKey) ?? "sparkle"
        sub = try c.decodeIfPresent(String.self, forKey: .sub) ?? ""
        tail = try c.decodeIfPresent(String.self, forKey: .tail) ?? ""
        reps = try c.decodeIfPresent(Int.self, forKey: .reps) ?? 0
        symbolName = try c.decodeIfPresent(String.self, forKey: .symbolName)
        isCustom = try c.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
        verificationOverride =
            try c.decodeIfPresent(VerificationMethod.self, forKey: .verificationOverride)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 0
        startMinute = try c.decodeIfPresent(Int.self, forKey: .startMinute)
        priority = try c.decodeIfPresent(RitualPriority.self, forKey: .priority) ?? .normal
        repeats = try c.decodeIfPresent(RitualRepeat.self, forKey: .repeats) ?? .daily
        categoryOverride = (try c.decodeIfPresent(String.self, forKey: .categoryOverride))
            .flatMap(RitualCategory.init(migrating:))
        identityID = try c.decodeIfPresent(String.self, forKey: .identityID)
    }

    /// Spelled out because `init(from:)` is, and a synthesised `CodingKeys`
    /// beside a hand-written decoder is the kind of pairing that goes wrong the
    /// first time somebody renames a property.
    private enum CodingKeys: String, CodingKey {
        case id, label, iconKey, sub, tail, reps, symbolName, isCustom
        case verificationOverride, note, minutes, startMinute, priority
        case repeats, categoryOverride, identityID
    }

    /// Written out because the decoder is, and the two have to agree about the
    /// key names. The memberwise initialiser below is what the app actually
    /// builds these with.
    init(
        id: String,
        label: String,
        iconKey: String,
        sub: String,
        tail: String,
        reps: Int = 0,
        symbolName: String? = nil,
        isCustom: Bool = false,
        verificationOverride: VerificationMethod? = nil,
        note: String = "",
        minutes: Int = 0,
        startMinute: Int? = nil,
        priority: RitualPriority = .normal,
        repeats: RitualRepeat = .daily,
        categoryOverride: RitualCategory? = nil,
        identityID: String? = nil
    ) {
        self.id = id
        self.label = label
        self.iconKey = iconKey
        self.sub = sub
        self.tail = tail
        self.reps = reps
        self.symbolName = symbolName
        self.isCustom = isCustom
        self.verificationOverride = verificationOverride
        self.note = note
        self.minutes = minutes
        self.startMinute = startMinute
        self.priority = priority
        self.repeats = repeats
        self.categoryOverride = categoryOverride
        self.identityID = identityID
    }

    /// Every shipped activity, filed by hand against the six dimensions.
    ///
    /// Done by hand rather than through `RitualCategory.init(migrating:)`
    /// because the coarse map is only good enough for a value somebody else
    /// stored. Read against these directly: `meditate` was `mind` and belongs on
    /// `mental`, while `read` was also `mind` and belongs on `intellect` — one
    /// mapping cannot separate those, and the whole worth of the Shape is that
    /// it does.
    ///
    /// Two calls worth defending. **`cold` is mental, not physical**: thirty
    /// seconds of cold water changes nothing about a body and quite a lot about
    /// somebody's relationship with discomfort. **The household activities are
    /// discipline**: making a bed is not a life area, it is the smallest
    /// possible instance of doing a thing you do not feel like doing, which is
    /// what the dimension means.
    static let categories: [String: RitualCategory] = [
        // Physical — the body, and what goes into it.
        "push": .physical, "stretch": .physical, "walk": .physical,
        "run": .physical, "lift": .physical, "workout": .physical,
        "water": .physical, "protein": .physical, "vitamins": .physical,
        "coffee": .physical, "sleep": .physical,

        // Intellect — what you read, learn and make.
        "read": .intellect, "play": .intellect,

        // Discipline — done whether or not you feel like it.
        "bed": .discipline, "teeth": .discipline, "tidy": .discipline,
        "dishes": .discipline, "plants": .discipline, "nofeed": .discipline,
        "wake": .discipline,

        // Mental — steadiness, attention, meeting a bad day.
        "meditate": .mental, "journal": .mental, "gratitude": .mental,
        "light": .mental, "cold": .mental,

        // Relationship — the people you show up for.
        "help": .relationship,

        // Ambition — the work that is actually yours.
        "focus": .ambition, "hardest": .ambition, "plan": .ambition,
        "ship": .ambition, "reach": .ambition,

        // The rest of the twelve added with the dimensions.
        "learn": .intellect, "language": .intellect,
        "write": .intellect, "study": .intellect,
        "call": .relationship, "present": .relationship,
        "thanks": .relationship, "meal": .relationship,

        // The thirteen added to fill out the thin dimensions. See the block at
        // the foot of `library`.
        "teach": .intellect, "sketch": .intellect, "lookup": .intellect,
        "listen": .relationship, "letter": .relationship, "arrange": .relationship,
        "numbers": .ambition, "askfor": .ambition, "craft": .ambition,
        "breathe": .mental, "silence": .mental, "worry": .mental,
        "prep": .discipline,
    ]

    static let defaultActive = ["water", "bed", "teeth", "push", "read"]

    /// How each library activity is confirmed.
    ///
    /// Kept as a table rather than a field on all 22 initializers. Only the
    /// handful the phone genuinely counts are `.health`; everything else is a
    /// promise, which is what the rest of the app now says out loud.
    static let libraryVerification: [String: VerificationMethod] = [
        "push": .honor, "run": .honor, "lift": .honor, "walk": .honor,
        "stretch": .honor,
        "water": .honor, "bed": .honor, "tidy": .honor, "protein": .honor,
        "vitamins": .honor, "plants": .honor, "dishes": .honor, "coffee": .honor,
        "teeth": .honor, "read": .honor, "journal": .honor, "play": .honor,
        "meditate": .honor, "cold": .honor, "nofeed": .honor,
        "gratitude": .honor, "light": .honor, "focus": .honor,
        // The four the routines needed and the library did not have. `workout`
        // is the only one the phone can settle: getting up, going to bed and
        // doing something for somebody are all things only the person who did
        // them can report.
        "workout": .honor,
        "wake": .honor, "sleep": .honor, "help": .honor,
        // The twelve added with the dimensions. Nothing here is measurable by a
        // phone: none of them is a distance, a heart rate or a step count, and
        // pretending otherwise would be the app claiming to check something it
        // cannot see.
        "learn": .honor, "language": .honor, "write": .honor, "study": .honor,
        "call": .honor, "present": .honor, "thanks": .honor, "meal": .honor,
        "hardest": .honor, "plan": .honor, "ship": .honor, "reach": .honor,
        // The thirteen. Nothing a phone can see, for the same reason as above.
        "teach": .honor, "sketch": .honor, "lookup": .honor,
        "listen": .honor, "letter": .honor, "arrange": .honor,
        "numbers": .honor, "askfor": .honor, "craft": .honor,
        "breathe": .honor, "silence": .honor, "worry": .honor,
        "prep": .honor,
    ]

    /// The shipped activities, each with the length it actually takes.
    ///
    /// The durations are new and they are what make a routine addable to a day
    /// with a shape: without them a template could say *Morning* and could not
    /// say whether the morning was twenty minutes or two hours, which is the
    /// first thing anybody wants to know about somebody else's routine.
    ///
    /// A few are deliberately `0`. A made bed, an empty sink and a cleared
    /// surface take as long as they take and nobody times them — and a made-up
    /// "2 min" on those would be the app inventing a fact to fill a column.
    static let library: [Ritual] = [
        Ritual(id: "water", label: "Drink water", iconKey: "drop", sub: "A full glass, before anything else", tail: "350 ml", minutes: 1),
        Ritual(id: "bed", label: "Make your bed", iconKey: "bed", sub: "Flat, both pillows squared", tail: ""),
        Ritual(id: "teeth", label: "Brush teeth", iconKey: "brush", sub: "Two minutes, both arches", tail: "2:00", minutes: 2),
        Ritual(id: "push", label: "Push-ups", iconKey: "figure", sub: "Chest to the floor, no half reps", tail: "20", reps: 20, minutes: 5),
        Ritual(id: "read", label: "Read", iconKey: "book", sub: "Ten pages of paper", tail: "10 pages", minutes: 15),
        Ritual(id: "stretch", label: "Stretch", iconKey: "stretch", sub: "Five minutes on the floor", tail: "5 min", minutes: 5),
        Ritual(id: "meditate", label: "Sit still", iconKey: "meditate", sub: "Four minutes, eyes closed", tail: "4 min", minutes: 4),
        Ritual(id: "walk", label: "Walk outside", iconKey: "sun", sub: "Eight minutes, sky above you", tail: "8 min", minutes: 8),
        Ritual(id: "journal", label: "Write three lines", iconKey: "journal", sub: "Paper, not the notes app", tail: "3 lines", minutes: 5),
        Ritual(id: "light", label: "Ten minutes of light", iconKey: "sun", sub: "Daylight on your face", tail: "10 min", minutes: 10),
        Ritual(id: "tidy", label: "Clear one surface", iconKey: "surface", sub: "Desk or counter, nothing on it", tail: "", minutes: 5),
        Ritual(id: "protein", label: "Eat something real", iconKey: "fork", sub: "Protein, not sugar", tail: "", minutes: 20),
        Ritual(id: "cold", label: "Cold finish", iconKey: "drop", sub: "Thirty seconds, cold", tail: "0:30", minutes: 1),
        // The tail read "passive", which was the old verification mode leaking
        // into the list. Nothing measures this one; the promise is the whole of it.
        Ritual(id: "nofeed", label: "No feed first", iconKey: "lock", sub: "Nothing scrolled before this", tail: ""),
        Ritual(id: "run", label: "Go for a run", iconKey: "run", sub: "Twenty minutes, outside", tail: "20 min", minutes: 20),
        Ritual(id: "lift", label: "Lift something heavy", iconKey: "dumbbell", sub: "Three sets, any weight", tail: "3 sets", reps: 24, minutes: 45),
        Ritual(id: "vitamins", label: "Take your vitamins", iconKey: "pill", sub: "The ones you keep forgetting", tail: ""),
        Ritual(id: "plants", label: "Water the plants", iconKey: "plant", sub: "Before they ask twice", tail: "", minutes: 3),
        Ritual(id: "play", label: "Play something", iconKey: "music", sub: "An instrument, not a playlist", tail: "10 min", minutes: 10),
        Ritual(id: "dishes", label: "Empty the sink", iconKey: "dishes", sub: "Nothing left standing", tail: ""),
        Ritual(id: "coffee", label: "Make it properly", iconKey: "coffee", sub: "Ground, not instant", tail: "", minutes: 5),
        Ritual(id: "gratitude", label: "Name three good things", iconKey: "sparkle", sub: "Out loud, before the phone", tail: "3", minutes: 2),
        // The one activity the library was missing, and it was missing in a way
        // that only showed once Paths started recommending: three of the four
        // worlds want an uninterrupted block of work and there was nothing here
        // to point at. Shipped to the library rather than owned by a Path,
        // because there is nothing world-specific about it — it is simply an
        // activity Forge did not have, and one id space is what keeps a future
        // Path's suggestion from colliding with somebody's own.
        Ritual(id: "focus", label: "Deep work", iconKey: "lock", sub: "One block, nothing else open", tail: "45 min", minutes: 45),

        // The four a beginner's day is actually made of, and which the library
        // was missing in a way that only showed once a routine had to describe a
        // whole day rather than decorate one. Every world here could say "read
        // ten pages" and none of them could say "get up" — so the two ends of
        // the day, the thing most people mean by exercise, and the one act that
        // is about somebody else.
        //
        // `wake` and `sleep` are deliberately untimed. Neither takes an amount
        // of time; both are the moment a day is opened and closed, and putting
        // "5 min" on getting out of bed would be the app inventing a fact.
        Ritual(id: "wake", label: "Wake up", iconKey: "sunrise", sub: "Up and on your feet, not on your phone", tail: ""),
        Ritual(id: "workout", label: "Work out", iconKey: "figure", sub: "Move properly, whatever kind", tail: "20 min", minutes: 20),
        Ritual(id: "help", label: "Help someone", iconKey: "hands", sub: "One thing, for somebody who did not ask", tail: ""),
        Ritual(id: "sleep", label: "Lights out", iconKey: "moon", sub: "The day ends when you say it does", tail: ""),

        // Twelve added when the six dimensions arrived, because three of them
        // had almost nothing to recommend. Intellect held two activities,
        // Relationship one and Ambition one — so the first thing the Shape did
        // for somebody weak in those was point at a gap and offer nothing to
        // put in it.
        //
        // Every one of these is concrete, doable today, needs nothing bought,
        // and is written the way the rest of the library is: the label is the
        // act and the subtitle is the standard.
        Ritual(id: "learn", label: "Learn something", iconKey: "lightbulb", sub: "Twenty minutes on one thing, not ten", tail: "20 min", minutes: 20),
        Ritual(id: "language", label: "Practise a language", iconKey: "globe", sub: "Out loud, badly, every day", tail: "10 min", minutes: 10),
        Ritual(id: "write", label: "Write something", iconKey: "journal", sub: "For nobody but you", tail: "15 min", minutes: 15),
        Ritual(id: "study", label: "Study", iconKey: "cap", sub: "One subject, notes closed at the end", tail: "30 min", minutes: 30),

        Ritual(id: "call", label: "Call someone", iconKey: "phone", sub: "The one you keep meaning to", tail: "", minutes: 10),
        Ritual(id: "present", label: "Phone in another room", iconKey: "lock", sub: "An hour where you are actually there", tail: "1 hr", minutes: 60),
        Ritual(id: "thanks", label: "Say the thing", iconKey: "quote", sub: "Tell someone what you noticed", tail: ""),
        Ritual(id: "meal", label: "Eat with someone", iconKey: "coffee", sub: "At a table, no screen", tail: "", minutes: 30),

        Ritual(id: "hardest", label: "Hardest thing first", iconKey: "target", sub: "Before anything easier gets a turn", tail: "", minutes: 45),
        Ritual(id: "plan", label: "Set tomorrow's one thing", iconKey: "target", sub: "Decided tonight, not in the morning", tail: "", minutes: 5),
        Ritual(id: "ship", label: "Ship something", iconKey: "bolt", sub: "Small and finished beats large and open", tail: "", minutes: 30),
        Ritual(id: "reach", label: "Send the message", iconKey: "hands", sub: "The email you have been avoiding", tail: "", minutes: 10),

        // Thirteen more, added because the Shape made the gaps impossible to
        // ignore. Once every activity is filed against one of six parts of a
        // person, a thin dimension stops being a curation detail and becomes
        // the app naming a weakness and then having almost nothing to offer for
        // it — Mental, Relationship and Ambition each held five, and three of
        // those five were the only sensible answer to half the situations
        // somebody would arrive in.
        //
        // The bar every one of these had to clear, which is the bar the whole
        // library is written to: **the label is the act and the subtitle is the
        // standard.** No aspiration, nothing that needs buying, nothing that
        // cannot be done today by somebody standing where they are — and each
        // one has to be a thing a person could genuinely fail at, or it is a
        // reminder rather than a promise.

        // Intellect. All three are about doing something with what you read,
        // which is the half of learning that nothing in the library reached.
        Ritual(id: "teach", label: "Explain it out loud", iconKey: "speech", sub: "To someone, or to an empty room", tail: "", minutes: 10),
        Ritual(id: "sketch", label: "Draw something", iconKey: "pencil", sub: "Ten minutes, badly, no eraser", tail: "10 min", minutes: 10),
        Ritual(id: "lookup", label: "Look one thing up", iconKey: "search", sub: "The thing you keep meaning to find out", tail: "", minutes: 5),

        // Relationship. The dimension with the least in it and the most at
        // stake — five activities, four of which needed the other person to be
        // available. These three can be started alone.
        Ritual(id: "listen", label: "Listen properly", iconKey: "ear", sub: "One conversation, no phone in the room", tail: "", minutes: 15),
        Ritual(id: "letter", label: "Write to someone", iconKey: "envelope", sub: "Longer than a text, to one person", tail: "", minutes: 10),
        Ritual(id: "arrange", label: "Make the plan", iconKey: "calendar", sub: "An actual date, not \u{201C}soon\u{201D}", tail: "", minutes: 5),

        // Ambition. `focus` and `hardest` are both an hour of the same thing;
        // what was missing was the work that is uncomfortable rather than long.
        Ritual(id: "numbers", label: "Look at the numbers", iconKey: "chart", sub: "The real ones, for ten minutes", tail: "10 min", minutes: 10),
        Ritual(id: "askfor", label: "Ask for something", iconKey: "hand", sub: "A rate, a meeting, an introduction", tail: "", minutes: 10),
        Ritual(id: "craft", label: "Practise the craft", iconKey: "hammer", sub: "The skill itself, not the work around it", tail: "30 min", minutes: 30),

        // Mental. Two of the three are subtractions, which is what the
        // dimension is mostly about and what a list of things to *do* finds
        // hardest to express.
        Ritual(id: "breathe", label: "Breathe", iconKey: "wind", sub: "Two minutes. Four in, six out", tail: "2 min", minutes: 2),
        Ritual(id: "silence", label: "Ten minutes of silence", iconKey: "mute", sub: "No music, no podcast, no screen", tail: "10 min", minutes: 10),
        Ritual(id: "worry", label: "Name the worry", iconKey: "cloud", sub: "On paper, where you can see its size", tail: "", minutes: 5),

        // Discipline. The smallest, most reliable lever there is on tomorrow
        // morning, and the library had nothing that touched the night before.
        Ritual(id: "prep", label: "Lay it out the night before", iconKey: "bag", sub: "Clothes, bag, keys, by the door", tail: "", minutes: 5),
    ]

    static func find(_ id: String) -> Ritual? {
        library.first { $0.id == id }
    }

    /// Guess which dimension an activity belongs to from what it is called.
    ///
    /// # Why a word list and not a model
    ///
    /// Because it has to be right instantly, offline, on the first keystroke
    /// after a name is typed, and it has to be *wrong* in a way somebody can fix
    /// in one tap. A wrong guess here costs a tap; a slow guess costs the whole
    /// point of guessing. The set below is small on purpose — it covers the
    /// activities people actually write down, and everything it does not
    /// recognise falls through to `nil` rather than to a confident wrong answer.
    ///
    /// Order matters. The list is checked in dimension order and the first hit
    /// wins, so a name containing two signals resolves the same way every time
    /// rather than depending on dictionary ordering. "Read to the kids" lands on
    /// Intellect rather than Relationship, which is arguable — and the answer to
    /// an arguable case is the picker directly under the field, not a longer
    /// list here.
    ///
    /// Matched on word boundaries rather than substrings. `hasPrefix` on a bare
    /// substring turns "brainstorm" into Mental and "runner beans" into
    /// Physical, and a classifier that is confidently wrong on ordinary English
    /// is worse than one that shrugs.
    static func suggestedCategory(for name: String) -> RitualCategory? {
        let words = Set(
            name.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
        guard !words.isEmpty else { return nil }

        for (category, signals) in categorySignals where !words.isDisjoint(with: signals) {
            return category
        }
        return nil
    }

    /// What an activity builds *besides* the dimension it is filed under.
    ///
    /// # Why an activity contributes to more than one thing
    ///
    /// Because it is true, and the single-category model was quietly lying. A
    /// run is filed under Physical and it is obviously also thirty minutes of
    /// not stopping when you want to — that is Mental, and refusing to say so
    /// made the Shape a picture of somebody's filing rather than of their life.
    /// Cold water is the clearest case: it changes nothing about a body and
    /// quite a lot about a person's relationship with discomfort.
    ///
    /// # Why secondaries are worth less, and why that is the anti-gaming rule
    ///
    /// A secondary contributes at `Ritual.secondaryWeight` — a third of a day
    /// rather than a whole one. Without that, one run would credit three
    /// dimensions in full, and the fastest way to a perfect hexagon would be to
    /// find the four activities with the most tags. Weighting them down means
    /// **the only way to score well in a dimension is to do things that are
    /// actually about it**, which is the entire claim this feature makes.
    ///
    /// The weight applies to the denominator as well as the numerator — see
    /// `ProgressStore.forgeShape(of:)` — so a dimension fed only by secondaries
    /// is not punished for it. Somebody whose Mental is entirely fed by running
    /// still scores well if they always run. They just have to run a lot more
    /// often than somebody who meditates, which is the honest arithmetic.
    ///
    /// Hand-authored, and deliberately sparse. Two secondaries is the most any
    /// activity gets. An activity tagged with five dimensions is not
    /// well-understood, it is uncommitted, and it makes the shape mush.
    static let secondaryDimensions: [String: [RitualCategory]] = [
        // Movement is a physical act and a decision not to stop.
        "run": [.mental, .discipline],
        "lift": [.mental],
        "workout": [.discipline],
        "push": [.discipline],
        "cold": [.physical, .discipline],
        "stretch": [.mental],
        "walk": [.mental],

        // Getting up and going to bed are the two ends of a day somebody is
        // deciding to run rather than to be run by.
        "wake": [.mental],
        "sleep": [.discipline],

        // Sitting still is training attention, which is the thing deep work
        // runs on.
        "meditate": [.discipline],
        "journal": [.intellect],
        "nofeed": [.mental],
        "light": [.physical],

        // Reading is intake; playing an instrument is intake plus the daily
        // refusal to stop being bad at something.
        "read": [.mental],
        "play": [.discipline],

        // A block of real work is the thing ambition is made of, and holding
        // one is attention.
        "focus": [.mental],

        // Doing something for somebody who did not ask is a relationship and a
        // decision.
        "help": [.mental],

        // The twelve added with the dimensions.
        "learn": [.discipline],
        "language": [.discipline],
        "write": [.mental],
        "study": [.discipline],
        "present": [.discipline],
        "meal": [.mental],
        "hardest": [.discipline, .mental],
        "plan": [.discipline],
        "ship": [.discipline],
        "reach": [.mental],
    ]

    /// How much of a day each dimension gets from this activity.
    ///
    /// The primary is always a whole day; every secondary is
    /// `secondaryWeight`. Library activities read the hand-authored table above.
    /// A user-made activity has no entry there, so its secondaries are inferred
    /// from its name by the same word list that guesses its primary — which
    /// means "Cold shower run" typed by hand behaves like the shipped one
    /// without anybody maintaining a second table.
    var dimensionWeights: [RitualCategory: Double] {
        let primary = category
        var weights: [RitualCategory: Double] = [primary: 1]

        let secondaries: [RitualCategory]
        if let shipped = Ritual.secondaryDimensions[id] {
            secondaries = shipped
        } else if isCustom {
            secondaries = Ritual.inferredDimensions(for: label).filter { $0 != primary }
        } else {
            secondaries = []
        }

        for dimension in secondaries where weights[dimension] == nil {
            weights[dimension] = Ritual.secondaryWeight
        }
        return weights
    }

    /// A secondary is worth a third of a day. One number, in one place, so the
    /// scoring and any future explanation of it cannot disagree.
    static let secondaryWeight: Double = 0.35

    /// **Every** dimension whose signal words appear in a name, not just the
    /// first. `suggestedCategory(for:)` answers "what is this mostly", this
    /// answers "what does this touch" — and a custom activity's secondaries come
    /// from the difference between the two.
    static func inferredDimensions(for name: String) -> [RitualCategory] {
        let words = Set(
            name.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
        guard !words.isEmpty else { return [] }
        return categorySignals
            .filter { !words.isDisjoint(with: $0.1) }
            .map(\.0)
    }

    /// Checked in this order; first hit wins. An array of pairs rather than a
    /// dictionary because a dictionary has no order and this needs one.
    private static let categorySignals: [(RitualCategory, Set<String>)] = [
        (.physical, [
            "run", "running", "jog", "walk", "walking", "gym", "lift", "lifting",
            "weights", "workout", "exercise", "train", "training", "swim", "cycle",
            "bike", "yoga", "stretch", "stretching", "pushups", "pullups", "squat",
            "cardio", "steps", "sleep", "water", "protein", "eat", "meal", "diet",
            "vitamins", "supplement", "hydrate", "breakfast", "cook", "cooking",
        ]),
        (.intellect, [
            "read", "reading", "book", "books", "study", "studying", "learn",
            "learning", "course", "language", "practice", "piano", "guitar",
            "instrument", "write", "writing", "draw", "drawing", "paint", "code",
            "coding", "research", "lesson", "duolingo", "chess",
        ]),
        (.mental, [
            "meditate", "meditation", "breathe", "breathing", "journal",
            "journaling", "gratitude", "reflect", "reflection", "therapy",
            "mindfulness", "stillness", "cold", "sauna", "prayer", "pray",
            "sunlight", "daylight", "outside",
        ]),
        (.relationship, [
            "call", "text", "family", "friend", "friends", "wife", "husband",
            "partner", "kids", "children", "mum", "mom", "dad", "parents",
            "dinner", "date", "help", "volunteer", "gift", "visit", "listen",
        ]),
        (.ambition, [
            "work", "deep", "focus", "project", "business", "client", "ship",
            "launch", "build", "plan", "planning", "review", "goals", "goal",
            "email", "outreach", "apply", "portfolio", "side",
        ]),
        (.discipline, [
            "bed", "tidy", "clean", "dishes", "laundry", "chores", "budget",
            "finances", "wake", "early", "screen", "phone", "scroll",
            "abstain", "quit", "avoid", "floss", "brush", "teeth",
            "plants", "admin", "inbox",
        ]),
    ]

    /// A list of activities put into the order the day happens in.
    ///
    /// Applied to the **pending** half of the day list and to nothing else,
    /// which is what keeps it from fighting the two orders that already exist.
    /// Finished activities stay in the order they were finished, because that
    /// is a record of the day rather than a plan for it; the **editor** stays
    /// in the order the user arranged, because a drag reports an index into the
    /// rows it can see and re-sorting underneath one would move the wrong
    /// activity — see `ForgeViewModel.dayParts`.
    ///
    /// Untimed activities keep their arranged position **after** the timed ones
    /// rather than being scattered among them. Two readings were possible and
    /// only this one is stable: interleaving would need an untimed activity to
    /// be given a time it does not have, and the moment the app invents one it
    /// has to defend it. "Everything with a time, in time order, then everything
    /// else, as you arranged it" is a sentence somebody can predict the
    /// behaviour of without being told.
    ///
    /// A day where nothing carries a time — which is most days, and every day
    /// until somebody sets one — comes back exactly as it went in.
    static func chronological(_ rituals: [Ritual]) -> [Ritual] {
        rituals.enumerated()
            .sorted { first, second in
                let a = first.element.startMinute ?? .max
                let b = second.element.startMinute ?? .max
                // The arranged index breaks every tie, so this is stable even
                // though `sorted(by:)` does not promise to be — two activities
                // set to the same minute must not swap places between redraws.
                return a == b ? first.offset < second.offset : a < b
            }
            .map(\.element)
    }

    /// A user-made activity, built from everything the composer collected.
    ///
    /// One value in rather than nine arguments. The composer grew from three
    /// fields to nine and the call sites were about to grow the same
    /// positional-argument problem — `makeCustom(symbol:label:goal:verification:)`
    /// was already one comma away from silently swapping two strings.
    ///
    /// The `custom.` prefix keeps these out of the library's id space for good,
    /// so a future library addition can never collide with one somebody made.
    static func makeCustom(_ draft: ActivityDraft) -> Ritual {
        Ritual(
            id: "custom.\(UUID().uuidString)",
            label: draft.label,
            iconKey: "sparkle",
            sub: "",
            tail: draft.goal,
            symbolName: draft.symbol,
            isCustom: true,
            verificationOverride: draft.verification,
            note: draft.note,
            minutes: draft.minutes,
            startMinute: draft.startMinute,
            priority: draft.priority,
            repeats: draft.repeats,
            categoryOverride: draft.category
        )
    }

    /// This activity's current state as an editable draft.
    var draft: ActivityDraft {
        ActivityDraft(
            symbol: symbolName ?? ForgeIcons.symbol(for: iconKey),
            label: label,
            note: note,
            goal: tail,
            minutes: minutes,
            startMinute: startMinute,
            priority: priority,
            repeats: repeats,
            category: category,
            verification: verification,
            identityID: identityID
        )
    }
}

// MARK: - What the composer collects

/// Everything an activity can be told about itself, in one value.
///
/// It exists so that adding a field to the composer is a change to one struct
/// rather than to a four-argument closure, two view-model methods, an
/// initialiser and three call sites — which is what it was, and is why the
/// composer stayed at three fields for as long as it did.
struct ActivityDraft: Equatable, Sendable {
    var symbol: String
    var label: String
    var note: String
    var goal: String
    var minutes: Int
    var startMinute: Int?
    var priority: RitualPriority
    var repeats: RitualRepeat
    var category: RitualCategory
    var verification: VerificationMethod
    /// Who this is evidence for, or nil for untagged — which is what a blank
    /// draft is and what every activity stays until somebody says otherwise.
    /// See `Ritual.identityID`.
    var identityID: String?

    /// The hour a newly-timed activity starts at.
    ///
    /// Seven in the morning, and it is a *placeholder* rather than a
    /// recommendation — somebody who switches a time on is about to set one, and
    /// the value's only job is to be a sensible thing to be dragging away from.
    /// Deliberately not the current time: offering "now" means the first thing
    /// anybody does is change it.
    ///
    /// It was `DayPeriod.morning.defaultStartMinute`, which lived with the
    /// archetypes and went with them.
    static let defaultStartMinute = 7 * 60

    /// A blank one, for the composer opening on nothing.
    static func blank(named name: String = "") -> ActivityDraft {
        ActivityDraft(
            symbol: ActivityIcons.fallback,
            label: name,
            note: "",
            goal: "",
            minutes: 0,
            startMinute: nil,
            priority: .normal,
            repeats: .daily,
            category: .discipline,
            verification: .honor,
            identityID: nil
        )
    }

    var trimmedLabel: String { label.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedGoal: String { goal.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The draft with its text fields trimmed, which is what gets committed.
    var cleaned: ActivityDraft {
        var copy = self
        copy.label = trimmedLabel
        copy.note = trimmedNote
        copy.goal = trimmedGoal
        return copy
    }
}

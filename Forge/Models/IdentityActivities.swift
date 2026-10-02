import Foundation

/// What a day should be made of, given who somebody says they are becoming.
///
/// The first run used to offer a hardcoded eight, the same eight to everybody,
/// and that was honest while Forge had no idea who it was talking to. It does
/// now — see `Identity` — and an app that asks "who are you becoming" and then
/// offers the identical list either way has asked a question it did not intend
/// to use the answer to. That is worse than not asking.
///
/// Everything here is a **suggestion and never a filter**. Every library
/// activity stays reachable from the picker afterwards, nothing is hidden, and
/// somebody who names no identity at all gets exactly the list Forge shipped
/// with. The whole type resolves to the old behaviour when it has nothing to go
/// on, which is the property that keeps it safe to put in front of a stranger in
/// their first ninety seconds.
enum IdentityActivities {

    // MARK: - The effort ladder

    /// Every library activity, smallest ask first.
    ///
    /// The order is the whole reason this is a list rather than a set, and it
    /// does two jobs: it decides how the choosing screen reads, and it decides
    /// which activity the first run asks somebody to go and do — see
    /// `ForgeViewModel.firstRunActivity`. **The first thing Forge ever asks
    /// anybody to do should be the smallest thing they chose**, because the only
    /// job of that beat is to be finished.
    ///
    /// It is hand-ordered rather than sorted by `minutes`, and it has to be: a
    /// duration says how long something takes and not how hard it is to start.
    /// Getting out of bed is `0` minutes and is the hardest thing on this list
    /// for the person the first run is written for.
    /// It is **one interleaved list**, not the original twenty-seven with later
    /// batches appended. That distinction has been got wrong once already: the
    /// twelve added with the dimensions were tacked on the end, which put
    /// "Say the thing" — three seconds, and the easiest activity in the app —
    /// above "Lift something heavy" on a ladder whose only job is to say what is
    /// smallest. Appending is always the tempting shape and it is always wrong
    /// here, because a batch is a fact about when something was written and this
    /// list is a claim about how hard it is to start.
    static let effortOrder = [
        // A glass of water, a pill, two minutes of breathing. Nothing here
        // needs a decision, which is the whole definition of this end.
        "water", "vitamins", "breathe", "bed", "teeth", "gratitude", "lookup",
        "plants", "dishes", "thanks", "prep", "bedroom", "tidy", "coffee", "arrange",
        // Five to fifteen minutes, and each one asks for something: cold water,
        // an honest sentence, sitting still.
        "cold", "worry", "journal", "nightlines", "plan", "meditate", "light", "push",
        "stretch", "sketch", "nofeed", "firstthirty", "call", "silence", "reach", "play",
        "language", "letter", "read", "pages", "teach", "walk", "write",
        // Half an hour or more, or a real interruption to a day. A whole day
        // without a clip is an interruption to most days, which is why it sits
        // among the long ones despite taking no time at all.
        "protein", "listen", "wake", "numbers", "sleep", "help", "meal",
        "learn", "steps", "slept", "run", "workout", "present", "noshort", "study",
        // The hard end. Long, uncomfortable, or both — and "Ask for something"
        // is on it despite taking ten minutes, because the ladder is about the
        // ask and not the clock.
        "craft", "askfor", "focus", "hardest", "lift", "ship",
    ]

    /// Where an activity sits on the ladder. Anything unknown — a user-made
    /// activity, or one added to the library after this list was written — sorts
    /// to the end rather than to the front, so a stranger's first ask can never
    /// accidentally be the hardest thing on screen.
    static func effort(of id: String) -> Int {
        effortOrder.firstIndex(of: id) ?? effortOrder.count
    }

    /// The eight Forge offers somebody who has named nothing.
    ///
    /// The list the first run shipped with, unchanged and deliberately so. Half
    /// routine, half movement, nothing needing a particular hour — somebody
    /// installing at two in the afternoon can do any of them from where they are
    /// standing.
    static let unaimed = [
        "water", "bed", "journal", "push", "stretch", "read", "walk", "run",
    ]

    /// How many the choosing screen offers. Eight is what it has always shown:
    /// enough that the list is a choice, few enough to be read without
    /// scrolling past the point of deciding.
    static let offerCount = 8

    // MARK: - What an identity asks for

    /// What each shipped starting point suggests.
    ///
    /// Curated rather than derived, because the mapping is a claim about what a
    /// kind of person actually does and there is no signal in the data that
    /// could produce it. Order inside each list is irrelevant — the effort
    /// ladder does the ordering — so these are written in whatever order makes
    /// the claim easiest to check.
    ///
    /// Each list is deliberately wider than the eight that will be shown. Two
    /// identities together should still have something to offer after the
    /// overlap is taken out.
    static let byPrompt: [IdentityPrompt: [String]] = [
        .trains: ["stretch", "push", "walk", "run", "workout", "lift", "protein", "water"],
        .finishes: ["focus", "nofeed", "tidy", "journal", "wake", "sleep"],
        .present: ["gratitude", "meditate", "light", "walk", "journal", "nofeed"],
        .reads: ["read", "journal", "nofeed", "light", "meditate"],
        .builds: ["focus", "tidy", "nofeed", "journal", "walk", "play"],
        .early: ["wake", "water", "bed", "light", "sleep", "cold", "coffee"],
        .steady: ["bed", "water", "teeth", "vitamins", "dishes", "plants", "tidy"],
    ]

    /// Words that reach an activity from a sentence somebody wrote themselves.
    ///
    /// The fallback for a free-text identity, and it is word overlap rather than
    /// comprehension — the same honest limitation `LocalForgeAI.bestMatch` has.
    ///
    /// Matched as a **prefix of a word** rather than as a substring of the whole
    /// sentence, which is not a refinement — it is the difference between
    /// working and not. Substring matching had "Someone who xylophones" reaching
    /// `nofeed`, because *xylo-phones* contains *phone*. Prefix-of-word keeps
    /// everything the loose version was for ("runs" and "running" both reach
    /// `run`, "writes" reaches `writ`) and stops a word from matching something
    /// buried in the middle of another one.
    ///
    /// Kept short on purpose. A long table finds a signal in everything, and a
    /// list that matches every identity is the hardcoded eight with extra steps.
    static let signals: [String: [String]] = [
        "run": ["run", "marathon", "jog"],
        "workout": ["train", "fit", "strong", "gym", "exercise", "athlete"],
        "lift": ["lift", "strong", "weight", "muscle"],
        "walk": ["walk", "outside", "outdoors", "steps"],
        "stretch": ["stretch", "mobile", "flexib", "yoga"],
        "push": ["push", "strong", "fit"],
        "read": ["read", "book", "learn", "study", "scholar"],
        "journal": ["writ", "journal", "reflect", "think", "honest"],
        "meditate": ["calm", "still", "present", "meditat", "patient", "peace"],
        "gratitude": ["grateful", "gratitude", "present", "kind"],
        "focus": ["focus", "deep", "work", "build", "make", "ship", "finish",
                  "creat", "craft"],
        "nofeed": ["present", "focus", "phone", "scroll", "distract", "attention"],
        "tidy": ["tidy", "clean", "order", "organis", "organiz"],
        "wake": ["early", "morning", "rise", "dawn"],
        "sleep": ["sleep", "rest", "early", "night"],
        "cold": ["cold", "discipline", "tough", "hard"],
        "water": ["health", "hydrat", "water"],
        "protein": ["eat", "diet", "nutrit", "health", "fuel"],
        "light": ["outside", "sun", "daylight", "morning"],
        "help": ["help", "kind", "generous", "give", "serve", "others", "father",
                 "mother", "parent", "friend"],
        "play": ["music", "play", "instrument", "practice", "creat"],
        // Single words only, now that matching is prefix-of-word: a two-word
        // signal like "look after" can never begin a word and would sit here
        // being silently dead.
        "teeth": ["health", "hygien"],
        "bed": ["tidy", "order", "discipline"],
        "vitamins": ["health"],
        "plants": ["garden", "plant"],
        "dishes": ["clean", "tidy", "home"],
        "coffee": ["morning", "ritual"],
    ]

    // MARK: - Putting it together

    /// The activities to offer, given who somebody said they are becoming.
    ///
    /// Ordered by the effort ladder and capped at `offerCount`. Falls all the
    /// way back to `unaimed` when there is nothing to go on, which is what
    /// somebody who skipped the question gets — and what everybody got before
    /// identity existed.
    ///
    /// Topped up rather than left short: an identity that only reaches three
    /// activities would otherwise produce a screen asking somebody to choose
    /// three from three, which is not a choice. The top-up comes from `unaimed`,
    /// so the padding is always a defensible thing to offer anybody.
    /// The padding is applied **after** the cap rather than before it, and the
    /// order of those two steps is the whole correctness of this function. Done
    /// the other way round — pad, then sort, then take eight — the shipped
    /// list's small activities outrank the aimed ones on the effort ladder and
    /// push them off the end: somebody who said "Someone who reads" was offered
    /// water, a made bed and a journal, and `read` fell off at position nine.
    /// An identity-derived list that does not contain the identity's own
    /// activity is worse than not asking.
    static func offered(for identities: [Identity]) -> [String] {
        let aimed = identities
            .flatMap(matches)
            .uniqued()
            .filter { Ritual.find($0) != nil }
            .sorted { effort(of: $0) < effort(of: $1) }

        var chosen = Array(aimed.prefix(offerCount))

        if chosen.count < offerCount {
            let held = Set(chosen)
            let padding = unaimed.filter { !held.contains($0) && Ritual.find($0) != nil }
            chosen += padding.prefix(offerCount - chosen.count)
        }

        return chosen.sorted { effort(of: $0) < effort(of: $1) }
    }

    /// The same list, resolved. What the choosing screen draws.
    static func offeredRituals(for identities: [Identity]) -> [Ritual] {
        offered(for: identities).compactMap(Ritual.find)
    }

    /// Which identity an activity is evidence for, among the ones named.
    ///
    /// The **first** match in the order the identities were named, which is the
    /// order somebody put them in and the only one they can predict. An activity
    /// that genuinely serves two — a walk, for somebody becoming both present
    /// and someone who trains — is filed under the one they said first rather
    /// than under both, because a tag is singular and a row that claimed two
    /// would be promising an arithmetic the app does not do.
    static func evidence(for ritualID: String, among identities: [Identity]) -> Identity? {
        identities.first { matches($0).contains(ritualID) }
    }

    /// What one identity reaches, by whichever route it has.
    ///
    /// An untouched shipped prompt gets its curated list; anything somebody
    /// rewrote falls through to the words. See `IdentityPrompt.matching(_:)`,
    /// which is where that distinction is made and why.
    static func matches(_ identity: Identity) -> [String] {
        if let prompt = IdentityPrompt.matching(identity) {
            return byPrompt[prompt] ?? []
        }

        // Words rather than the raw sentence. A signal has to begin a word to
        // count — see the note on `signals`.
        let statement = identity.statement.lowercased()
        let words = statement.split { !$0.isLetter }.map(String.init)
        return signals
            .filter { _, signals in
                signals.contains { signal in words.contains { $0.hasPrefix(signal) } }
            }
            .map(\.key)
            .sorted { effort(of: $0) < effort(of: $1) }
    }

    // MARK: - What a set of dimensions asks for

    /// What each part of a person is best *started* with.
    ///
    /// # Why this is hand-written and the effort ladder is not enough
    ///
    /// The offer used to be "that dimension's library activities, cheapest
    /// first", which is a sensible-looking rule that produced a bad screen:
    /// somebody who said they wanted to build their body was offered vitamins,
    /// a glass of water and a properly made coffee, because those are the three
    /// physical activities that ask least. All of them are real and none of them
    /// is what a person means when they point at Physical. The cheapest thing in
    /// a dimension is not the most *representative* thing in it, and the first
    /// run's offer has to look like the answer somebody just gave.
    ///
    /// So each list is ordered by **how much it is the thing** — how likely a
    /// person is to have meant it, and to still be doing it in a month — and the
    /// round robin below takes from the front. The effort ladder still decides
    /// the order they are *shown* in, and still decides which one Forge asks for
    /// first, so the smallest thing chosen is still the first thing asked for.
    ///
    /// Every id here is in `Ritual.library` and every dimension lists all of its
    /// own activities, so nothing is unreachable and the eight can always be
    /// filled from one dimension alone. A test holds both.
    static let starters: [RitualCategory: [String]] = [
        // The three people mean by "get fit" first, then what holds them up.
        // The Arcs' additions go last in each list (`steps`, `pages`, …): a
        // proposal is only ever each list's first entry, so nothing a first run
        // offers moves because the Arcs exist.
        .physical: [
            "walk", "workout", "stretch", "push", "run", "water", "protein",
            "sleep", "lift", "vitamins", "coffee", "steps", "slept",
        ],
        // Reading is the whole dimension for most people; the rest is what you
        // do with what you read.
        .intellect: [
            "read", "learn", "write", "study", "language", "teach", "sketch",
            "lookup", "play", "pages",
        ],
        // The two ends of a day, and the small levers on the one after it.
        .discipline: [
            "wake", "bed", "nofeed", "prep", "tidy", "teeth", "dishes", "plants",
            "firstthirty", "bedroom", "noshort",
        ],
        // Two minutes of breathing is the honest entry point. Cold water is
        // here because it is about discomfort rather than about the body.
        .mental: [
            "breathe", "meditate", "journal", "gratitude", "silence", "worry",
            "light", "cold", "nightlines",
        ],
        // A call and a sentence said out loud are the two anybody can do today,
        // from where they are standing, without arranging anything.
        .relationship: [
            "call", "thanks", "listen", "arrange", "meal", "present", "help",
            "letter",
        ],
        // The uncomfortable half first: the work that is actually yours is
        // rarely the work that is easiest to sit down to.
        .ambition: [
            "hardest", "focus", "plan", "ship", "craft", "numbers", "askfor",
            "reach",
        ],
    ]

    /// How many to offer for a given answer.
    ///
    /// Eight for one, two or three chosen — what the screen has always shown,
    /// and what somebody who skipped still gets. Beyond that it is two per
    /// dimension, because the cap on choosing was lifted and eight across six
    /// parts of a person is one activity each plus rounding: an offer that
    /// cannot represent the answer it was given is worse than a longer list.
    /// Twelve is the ceiling, which is a scroll rather than a catalogue.
    static func offerCount(for focus: Set<RitualCategory>) -> Int {
        guard focus.count > 3 else { return offerCount }
        return min(12, focus.count * 2)
    }

    /// The activities offered in the first run, chosen from the dimensions
    /// somebody said they wanted to build.
    ///
    /// The same contract as `offered(for:)` and deliberately the same shape:
    /// ordered by the effort ladder so the smallest thing is first, capped at
    /// `offerCount(for:)`, and falling all the way back to `unaimed` when there
    /// is nothing to go on. An empty focus therefore produces **exactly** the
    /// shipped eight the first run offered before any of this existed, which is
    /// the property that keeps skipping the beat free.
    ///
    /// Drawn round-robin across the chosen dimensions rather than by taking the
    /// easiest eight overall. Somebody who picks Physical and Relationship
    /// should not be handed six stretches and two calls because stretching
    /// happens to be cheap — the offer has to look like the answer they gave.
    static func offered(forDimensions focus: Set<RitualCategory>) -> [String] {
        guard !focus.isEmpty else { return Array(unaimed.prefix(offerCount)) }
        let wanted = offerCount(for: focus)

        // Each chosen dimension's activities, most representative first — see
        // `starters`. The library is the fallback for a dimension the table has
        // not been written for, so a new one cannot silently offer nothing.
        var queues = RitualCategory.dimensions
            .filter(focus.contains)
            .map { dimension -> [String] in
                let curated = (starters[dimension] ?? []).filter { Ritual.find($0) != nil }
                let rest = Ritual.library
                    .filter { $0.category == dimension && !curated.contains($0.id) }
                    .map(\.id)
                    .sorted { effort(of: $0) < effort(of: $1) }
                return curated + rest
            }
            .filter { !$0.isEmpty }

        var chosen: [String] = []
        while chosen.count < wanted, queues.contains(where: { !$0.isEmpty }) {
            for index in queues.indices where chosen.count < wanted {
                guard !queues[index].isEmpty else { continue }
                chosen.append(queues[index].removeFirst())
            }
        }

        // A focus whose dimensions between them hold fewer than the offer still
        // gets a full screen, padded from the default day.
        if chosen.count < wanted {
            let held = Set(chosen)
            chosen += unaimed.filter { !held.contains($0) }.prefix(wanted - chosen.count)
        }
        return Array(chosen.prefix(wanted)).sorted { effort(of: $0) < effort(of: $1) }
    }

    static func offeredRituals(forDimensions focus: Set<RitualCategory>) -> [Ritual] {
        offered(forDimensions: focus).compactMap(Ritual.find)
    }
}

// MARK: - Which world fits

// MARK: -

private extension Array where Element: Hashable {
    /// Order-preserving dedupe. `Set` would lose the effort ordering that the
    /// whole of `IdentityActivities` turns on.
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }

}

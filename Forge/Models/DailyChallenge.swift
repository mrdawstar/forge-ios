import Foundation

// MARK: - What a challenge is about

/// The six things a challenge can be about — and they are **the six**.
///
/// # Why this stopped being its own set
///
/// It used to be `discipline · focus · fitness · courage · mind · productivity`,
/// on the argument that a challenge is not *sorted* but *aimed*: courage is not
/// a place in somebody's day, it is the thing the challenge is for. That was a
/// good argument in an app whose activity categories were body, mind, home, fuel
/// and focus — a filing system for a picker.
///
/// It is the wrong argument now. `RitualCategory` is no longer a filing system:
/// the six dimensions are the spine of the product — the Shape scores them, the
/// first run asks which of them somebody wants to build, `DayPlanner` reads the
/// gap between the two, and the Becoming tab is six rows and a hexagon. A
/// seventh and eighth vocabulary sitting beside that (is "Focus" the dimension
/// Ambition, or the challenge aim, or neither?) makes the app harder to hold in
/// the head for nothing.
///
/// So a challenge is aimed at one of the same six parts of a person the rest of
/// Forge is about, and "Chosen for the part of you that has had the least"
/// becomes a sentence the app can actually say. The mapping is the identity —
/// see `category`.
///
/// The old raw values still decode. See `init(from:)`: today's challenge state
/// is stored, and an update that threw on it would drop somebody's accepted
/// challenge mid-morning.
enum ChallengeFocus: String, Codable, CaseIterable, Sendable, Identifiable {
    // Declared in the order the Shape draws them, so a grid of six here and the
    // hexagon on the Becoming tab can never disagree about which is which.
    case intellect, relationship, discipline, ambition, mental, physical

    var id: String { rawValue }

    /// The dimension this is aimed at. One to one, deliberately: two enums that
    /// nearly agree is how a product ends up with two names for one idea.
    var category: RitualCategory {
        switch self {
        case .intellect: .intellect
        case .relationship: .relationship
        case .discipline: .discipline
        case .ambition: .ambition
        case .mental: .mental
        case .physical: .physical
        }
    }

    /// The dimension's own words, so a challenge tag and a Shape row read the
    /// same. `RitualCategory` owns all three of these strings.
    var label: String { category.label }
    var meaning: String { category.meaning }
    var symbol: String { category.symbol }

    init?(_ category: RitualCategory) {
        guard let match = Self.allCases.first(where: { $0.category == category }) else { return nil }
        self = match
    }

    /// Tolerant, like every decoder in this app.
    ///
    /// The five names that changed are mapped rather than dropped, and anything
    /// unrecognised lands on `discipline` rather than throwing — a `throw` here
    /// takes the whole of `ChallengeDay` with it, and the failure mode is
    /// somebody opening Forge at eleven to find the challenge they accepted at
    /// eight replaced by a new one.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? Self.legacy[raw] ?? .discipline
    }

    /// What the old names meant, in the vocabulary that replaced them.
    ///
    /// `productivity` lands on Discipline rather than Ambition because what it
    /// held was inbox-and-surfaces work — the things done whether or not you
    /// feel like them — while `focus` was the uninterrupted block, which is
    /// Ambition. `courage` was almost entirely about other people, so it is
    /// Relationship.
    private static let legacy: [String: ChallengeFocus] = [
        "fitness": .physical,
        "mind": .intellect,
        "focus": .ambition,
        "productivity": .discipline,
        "courage": .relationship,
    ]
}

/// How much the day is being asked for.
///
/// Three, and the middle one is the default. A ladder with more rungs than this
/// invites somebody to tune the difficulty instead of doing the thing.
enum ChallengeDifficulty: String, Codable, CaseIterable, Sendable, Identifiable {
    case easy, medium, hard

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    /// What picking this actually means, said in the words somebody would use
    /// about their own day rather than in a number of points.
    var detail: String {
        switch self {
        case .easy: "Ten minutes, and no excuse survives it."
        case .medium: "A real dent in the day."
        case .hard: "You will have to arrange the day around it."
        }
    }
}

// MARK: - The challenge itself

/// One thing, for one day.
///
/// A value, not an object: it is chosen once in the morning, written down, and
/// never edited. Everything that changes about it during the day lives in
/// `ChallengeState` beside it, so the challenge somebody accepted at eight is
/// provably the one they completed at six.
struct DailyChallenge: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    /// One sentence saying what doing it looks like. Never a paragraph — a
    /// challenge that needs explaining is two challenges.
    let detail: String
    let focus: ChallengeFocus
    let difficulty: ChallengeDifficulty
    /// Whether this came out of the catalogue or was made for this person.
    /// Shown, because "chosen for you" and "written for you" are different
    /// promises and the app should not blur them.
    var isPersonal: Bool = false

    /// Why this one, said in one clause: "a day of deep work".
    ///
    /// Written down at the moment the challenge is chosen rather than derived
    /// when the sheet opens, for the same reason the challenge itself is: the
    /// day goes on changing and this must not. Somebody who adds a run at four
    /// in the afternoon should not find that the morning's challenge has
    /// retroactively been "for a day of training".
    ///
    /// Optional, and that is load-bearing rather than lazy: a `ChallengeDay`
    /// written by an older build has no such key, and Swift's synthesised
    /// decoder only tolerates a missing key when the property is `Optional`. A
    /// non-optional with a default would throw, and the whole of today's
    /// challenge state would be lost on the update.
    var reason: String? = nil
}

/// Where a challenge is in its one day.
///
/// Four states, and every move between them is reversible. `completed` used to
/// be terminal on the grounds that a finished thing is a fact — which sounds
/// principled and is wrong here for a reason worth writing down: an activity is
/// undone by tapping the row it lives on, so a mis-tap costs a second, while the
/// challenge has exactly one button and pressing it by accident used to be
/// permanent for the rest of the day. A rule that cannot be unwound has to be
/// worth its worst case, and "I pressed Done before I did it" is not.
///
/// The chain never hears about it either way. Since 1.1 a finished challenge
/// counts as a kept day for its dimension in the Shape (`KeptChallenge`), and
/// every move away from `completed` takes that day back in the same write — so
/// there is still nothing here that undoing could falsify.
enum ChallengeState: String, Codable, Sendable {
    /// Offered, and not yet answered.
    case offered
    case accepted
    case skipped
    case completed

    var isSettled: Bool { self == .completed || self == .skipped }
}

/// A challenge and what has happened to it, for one particular day.
///
/// Stored as one value so the day, the challenge and the state can never be
/// written apart — the bug where the app rolls over at four in the morning and
/// keeps yesterday's "completed" against today's challenge is not reachable if
/// there is only one thing to write.
struct ChallengeDay: Codable, Equatable, Sendable {
    var day: ForgeDay
    var challenge: DailyChallenge
    var state: ChallengeState = .offered
    /// When it was finished. Only ever set once.
    var completedAt: Date?
}

/// A daily challenge somebody finished, as the record keeps it: the day, which
/// one, and which of the six it was aimed at.
///
/// # Why a finished challenge is kept at all
///
/// It was not, on purpose: "a scoreboard of challenges taken and missed is
/// exactly the pressure this feature must not add". 1.1 makes the challenge
/// count (DIRECTION_1_1 §7) — a finished one is a kept day for its dimension in
/// the Shape — and a thing that counts has to be written down, or the Shape
/// would forget it at four in the morning.
///
/// **Only what was finished.** Nothing is kept about a challenge skipped,
/// ignored or swapped, so there is still no list of misses anywhere: this is a
/// record of things done, the same kind of fact as a `DayRecord.Completion`,
/// and the Shape reads it the same way — derived on read, one day per
/// dimension however much was done in it. See `ForgeShape.crediting`.
///
/// One per day, because there is one challenge a day: taking another one, or
/// undoing the finish, takes the day's entry away again. Stored by
/// `ProgressStore` under `forge.challengesKept.v1`.
struct KeptChallenge: Codable, Equatable, Sendable {
    let day: ForgeDay
    /// The catalogue id, for the record. Nothing reads it to count.
    let id: String
    /// Which of the six it fed.
    let focus: ChallengeFocus
    let at: Date

    init(day: ForgeDay, id: String, focus: ChallengeFocus, at: Date) {
        self.day = day
        self.id = id
        self.focus = focus
        self.at = at
    }

    /// Tolerant, like every decoder here: the day and the aim are the whole of
    /// what counts, so only they are required. `ChallengeFocus` already lands
    /// an unknown aim somewhere safe rather than throwing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(ForgeDay.self, forKey: .day)
        // Not a day on anybody's record: the row is dropped (§17.7).
        guard day.isPlausible else {
            throw DecodingError.dataCorruptedError(forKey: .day, in: c, debugDescription: "Not a day.")
        }
        focus = try c.decode(ChallengeFocus.self, forKey: .focus)
        // Neither is counted, so neither may cost the row (§17.7).
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        at = (try? c.decodeIfPresent(Date.self, forKey: .at)) ?? day.startOfDay()
    }

    private enum CodingKeys: String, CodingKey { case day, id, focus, at }

    /// A whole list, keeping every entry that reads and dropping the rest — one
    /// bad row must not cost somebody every challenge they ever finished.
    static func decodeAll(_ data: Data) -> [KeptChallenge] {
        struct Lossy: Decodable {
            let value: KeptChallenge?
            init(from decoder: Decoder) throws { value = try? KeptChallenge(from: decoder) }
        }
        // `Lossy?`: a `null` element is an error before any initialiser runs,
        // and it used to cost the whole list (§17.7).
        return ((try? JSONDecoder().decode([Lossy?].self, from: data)) ?? []).compactMap { $0?.value }
    }
}

// MARK: - What the day is already about

/// The day's own shape, reduced to what choosing a challenge needs.
///
/// A value rather than the view model, so "which challenge does this day get"
/// is a pure function that can be checked without a store, a clock or a phone —
/// the same reason `AIBrief` and `PremiumMoment` are values.
struct ChallengeContext: Equatable, Sendable {
    /// What today asks for, by name. Lowercased on the way in.
    var activities: [String] = []
    /// The categories those activities are filed under.
    var categories: [RitualCategory] = []

    /// The identity with the least evidence behind it this week, by the words
    /// somebody wrote for it — and what the challenge is now aimed at.
    ///
    /// # Why this replaced reading the day's own names
    ///
    /// The leaning was inferred from what today happens to hold, which meant the
    /// challenge always pointed at whatever the day was **already** about: a day
    /// of running got a fitness challenge, on top of the run. That is the least
    /// useful thing it could do. What a challenge is *for* is the part of
    /// somebody's practice that is quietly not happening, and since the identity
    /// spine landed the app knows which part that is — the identity whose tagged
    /// activities have the fewest days of evidence behind them this week.
    ///
    /// So the input changed and nothing else did. The selection is still
    /// deterministic per date (`ChallengeCatalog.index(for:count:)`), the
    /// leaning still weights the shelf rather than filtering it, and everybody
    /// still gets a challenge every day. What moved is where the aim comes from.
    ///
    /// Nil for the majority who have named nothing, and the old reading takes
    /// over — see `leanings`. Nothing about this is required and no day is
    /// worse for its absence.
    var neglected: String?

    init(
        activities: [String] = [],
        categories: [RitualCategory] = [],
        neglected: String? = nil
    ) {
        self.activities = activities.map { $0.lowercased() }
        self.categories = categories
        self.neglected = neglected.map { $0.lowercased() }
    }

    /// Which focuses this day leans toward, if any.
    ///
    /// **The neglected identity wins outright where there is one.** Not weighted
    /// against the day's own names but read instead of them: a sentence somebody
    /// wrote about who they are becoming is a better statement of what is worth
    /// asking for than a list of what they happen to have on today, and mixing
    /// the two would let a busy day drown out the thing being neglected — which
    /// is exactly the failure this is here to fix.
    ///
    /// Ties are kept rather than broken. A day with a run *and* two hours of
    /// deep work genuinely leans both ways, and picking one of them by an
    /// arbitrary rule would be inventing a preference the day does not express.
    var leanings: Set<ChallengeFocus> {
        if let aimed = aimedFocuses, !aimed.isEmpty { return aimed }

        var score: [ChallengeFocus: Int] = [:]

        for name in activities {
            for (focus, words) in Self.signals where words.contains(where: name.contains) {
                score[focus, default: 0] += 2
            }
        }
        for category in categories {
            guard let focus = Self.byCategory[category] else { continue }
            score[focus, default: 0] += 1
        }

        guard let best = score.values.max(), best > 0 else { return [] }
        return Set(score.filter { $0.value == best }.keys)
    }

    /// What the neglected identity's own sentence asks for, read through the
    /// same signal table the activities are.
    ///
    /// The identity is free text, so this is word overlap and not comprehension
    /// — the same honest limitation `IdentityActivities.signals` has. A sentence
    /// nothing matches yields nil and the day's own reading takes over, which is
    /// the correct behaviour: "Someone who is kind to their mother" is a real
    /// identity and there is no challenge on the shelf that answers it.
    private var aimedFocuses: Set<ChallengeFocus>? {
        guard let neglected, !neglected.isEmpty else { return nil }
        let matched = Self.signals
            .filter { _, words in words.contains(where: neglected.contains) }
            .map(\.key)
        return matched.isEmpty ? nil : Set(matched)
    }

    /// The one thing the day is most about, or nil when it says nothing.
    ///
    /// `leanings` keeps ties because a challenge shelf can be weighted toward
    /// two things at once. Anything that has to *name* the day — the sentence
    /// under a challenge, the line after the blade comes out — needs exactly one
    /// answer and needs it to be the same answer on every device, so the tie is
    /// broken by the case's own name rather than by set order, which is not
    /// stable across launches.
    var leaning: ChallengeFocus? {
        leanings.min { $0.rawValue < $1.rawValue }
    }

    /// The words that say what an activity is really for.
    ///
    /// Substrings rather than whole words, so "running", "runs" and "morning
    /// run" all reach `run`. Kept short on purpose: a long list finds a signal
    /// in everything, and a context that leans every way leans no way.
    static let signals: [ChallengeFocus: [String]] = [
        .physical: ["run", "walk", "gym", "lift", "train", "workout", "swim", "cycle",
                    "push-up", "pushup", "steps", "yoga", "stretch", "protein"],
        .intellect: ["read", "book", "study", "learn", "language", "write", "draw",
                     "sketch", "teach", "explain", "course", "revise"],
        .discipline: ["cold", "shower", "no ", "wake", "bed", "sleep", "fast", "sugar",
                      "screen", "phone", "tidy", "teeth", "sink"],
        .mental: ["meditat", "still", "breath", "silence", "journal", "grateful",
                  "gratitude", "worry", "reflect", "daylight"],
        // No "someone" here, however tempting: this table is also read against
        // a free-text identity, and every shipped one of those begins "Someone
        // who …" — so that single word would have aimed every challenge on
        // every phone at Relationship.
        .relationship: ["call", "listen", "letter", "message", "meal", "eat with",
                        "together", "family", "friend", "partner", "dinner", "help"],
        .ambition: ["deep work", "focus", "ship", "hardest", "numbers", "craft",
                    "pitch", "publish", "session", "code", "invoice"],
    ]

    /// The dimension an activity is filed under, read as the aim.
    ///
    /// One to one, and it can be, which is the whole point of the six replacing
    /// the old aims. There used to be a hole here — nothing was aimed at other
    /// people, on the grounds that a challenge involving a third party is a task
    /// somebody else has not agreed to. That objection survives in *how the
    /// Relationship challenges are written* (every one of them is something the
    /// user does, needing nobody's cooperation to start), rather than as a
    /// missing sixth of the app.
    static let byCategory: [RitualCategory: ChallengeFocus] = Dictionary(
        uniqueKeysWithValues: ChallengeFocus.allCases.map { ($0.category, $0) }
    )
}

private extension Array {
    /// `self` repeated, for the weighting above. Written out because
    /// `Array(repeating:count:)` builds an array of arrays.
    static func * (array: [Element], times: Int) -> [Element] {
        (0..<Swift.max(0, times)).flatMap { _ in array }
    }
}

// MARK: - The catalogue

/// Every challenge Forge ships with.
///
/// Forty-eight of them, eight per focus, spread across the three difficulties.
/// That is nearly two months of days before anything repeats, which is the
/// shortest run that does not feel like a list of five things on a loop.
///
/// # Every one of them is countable
///
/// "Twenty pages", "a hundred press-ups", "ninety uninterrupted minutes", "ten
/// lines by heart". The rule is that somebody standing at the end of the day
/// must be able to answer *did I do it* without interpreting anything, because a
/// challenge you can argue yourself into having done is not a test of discipline
/// — it is a mood. The handful that cannot carry a number carry a bright line
/// instead: no snooze, nothing sweet, the phone in another room.
///
/// Written as data rather than generated, because each one has to be a real
/// sentence somebody could act on before lunch. "Do 30 minutes of Discipline" is
/// what a generator produces and it is not a challenge, it is a category with a
/// number stapled to it.
enum ChallengeCatalog {

    /// Sixty, ten per part of a person, spread across the three weights.
    ///
    /// Two months before anything repeats even for somebody who takes one every
    /// day, and — the reason it went from eight to ten — every one of the six is
    /// now deep enough that a person who chose Relationship and only
    /// Relationship could browse for a fortnight without meeting the same
    /// challenge twice. See `browse`, which draws one per dimension.
    static let all: [DailyChallenge] =
        intellect + relationship + discipline + ambition + mental + physical

    /// The one for a given day, and it is the same one all day.
    ///
    /// Deterministic on the date and the day's shape: no randomness, no stored
    /// cursor, no server. Two phones signed into the same account get the same
    /// challenge on the same date without ever having spoken to each other, and
    /// reinstalling the app at noon does not hand somebody a second challenge.
    ///
    /// The mixing is written out rather than taken from `Hashable`, and that is
    /// load-bearing: Swift seeds `hashValue` per process, so a catalogue indexed
    /// by it would change the day's challenge every time the app was launched.
    ///
    /// # Why the day's own activities are an input
    ///
    /// A challenge drawn blind from sixty is a fortune cookie: it lands on
    /// "A hundred press-ups" for somebody whose day is reading and journalling
    /// and there is no reading of it under which that is a good offer. Weighting
    /// by what the day already holds means the challenge is *about the day* — a
    /// morning with a run in it leans physical, one with deep work leans
    /// ambition — which is the difference between a prompt and a suggestion.
    ///
    /// It leans rather than filters. Every challenge in the catalogue stays
    /// reachable, because a week of six physical challenges in a row is the
    /// other way to be repetitive.
    static func challenge(for day: ForgeDay, context: ChallengeContext = .init()) -> DailyChallenge {
        let shelf = weighted(by: context)
        var chosen = shelf[Self.index(for: day, count: shelf.count)]
        // Only when the day actually pulled it that way. A challenge that
        // happened to land on physical for somebody whose day says nothing about
        // training must not claim it was chosen for them — the sentence is worth
        // having precisely because it is not always there.
        if let leaning = context.leaning, leaning == chosen.focus {
            chosen.reason = Self.reason(for: leaning)
        }
        return chosen
    }

    /// One challenge per part of a person, for the same day — what the sheet
    /// lets somebody swipe through.
    ///
    /// **Still nothing random and still nothing stored.** Each dimension's own
    /// shelf is indexed by the same arithmetic the day's challenge uses, salted
    /// with the dimension's name so the six are not all the same rung of their
    /// respective lists. So the six cards are the same six on both of somebody's
    /// phones, they do not change when the app is reopened, and browsing them
    /// is reading rather than rolling.
    ///
    /// # The order is the six, and it does not move
    ///
    /// `including` is today's actual challenge, and it **takes its own
    /// dimension's slot** rather than leading the list. Leading was the obvious
    /// shape and it was wrong for one concrete reason: taking a card would then
    /// reorder the deck under the finger that took it. Everything the pager
    /// showed afterwards — the dot that is lit, the card on screen, the buttons
    /// under it — was one position out from everything the state believed,
    /// because a scrolled offset does not move when the array beneath it does.
    ///
    /// Fixed slots make that unreachable: the six cards are the six parts of a
    /// person, always in `RitualCategory.dimensions` order, and taking one only
    /// changes what the card in *that* slot says about itself.
    /// # And it does not stop at six
    ///
    /// `page` is how far down the browse somebody has scrolled: page zero is the
    /// six above, page one is a second draw from the same six shelves, and so on
    /// for as long as anybody keeps swiping. Ten per shelf means sixty distinct
    /// cards before the arithmetic starts coming back round, which is a fortnight
    /// of uninterrupted browsing and further than anybody will go.
    ///
    /// Still nothing random and still nothing stored: the page is folded into the
    /// same salt, so the ninth card is the ninth card on both of somebody's
    /// phones and after the app is reopened. And page zero is unchanged — the
    /// salt for it is exactly the string it always was — so the six cards
    /// somebody has seen every day do not move because this exists.
    ///
    /// A challenge can legitimately appear twice down a long browse, so the
    /// **pager** keys its cards by page and position rather than by challenge id
    /// — see `DailyChallengeSheet.Card`. Nothing here is mangled to make that
    /// work: an id is the identity of a challenge, not of a slot in a list.
    static func browse(
        for day: ForgeDay, including current: DailyChallenge? = nil, page: Int = 0
    ) -> [DailyChallenge] {
        ChallengeFocus.allCases.compactMap { focus -> DailyChallenge? in
            if page == 0, let current, current.focus == focus { return current }
            let shelf = all.filter { $0.focus == focus }
            guard !shelf.isEmpty else { return nil }
            let salt = page == 0 ? focus.rawValue : "\(focus.rawValue)#\(page)"
            return shelf[Self.index(for: day, count: shelf.count, salt: salt)]
        }
    }

    /// "a day of deep work" — the clause that goes after "Chosen for".
    ///
    /// Names the day rather than the dimension: nobody thinks of their Tuesday
    /// as "ambition", they think of it as a day with a lot to get through.
    static func reason(for focus: ChallengeFocus) -> String {
        switch focus {
        case .physical: "a day with training in it"
        case .intellect: "a day with reading in it"
        case .discipline: "the day you have arranged"
        case .mental: "a day you will need to be steady for"
        case .relationship: "a day with people in it"
        case .ambition: "a day of deep work"
        }
    }

    /// The catalogue with the day's own leanings counted more than once.
    ///
    /// The multiplier is not a taste decision, it is arithmetic, and the obvious
    /// guess is wrong: with six aims in the catalogue, weighting the matching
    /// one three-to-one still only reaches it 37% of the time, because it is
    /// competing with five others. Four extra copies is what puts a
    /// single-leaning day at about half — often enough to read as "it noticed",
    /// rare enough that a runner still meets a Relationship challenge most weeks.
    ///
    /// It leans rather than filters: every challenge in the catalogue is still
    /// in the shelf exactly because a week of six physical prompts on a loop is
    /// the other way to be repetitive.
    static let leaningWeight = 4

    static func weighted(by context: ChallengeContext) -> [DailyChallenge] {
        let leanings = context.leanings
        guard !leanings.isEmpty else { return all }
        return all + all.filter { leanings.contains($0.focus) } * leaningWeight
    }

    /// The stable ordinal a day maps to, exposed for the tests that prove it
    /// does not move.
    ///
    /// `salt` folds one more string into the same mixing, and it is what lets
    /// `browse` draw six different rungs from six shelves of the same
    /// length. Empty — the default, and what the day's own challenge uses —
    /// folds nothing and reproduces the original hash exactly.
    static func index(for day: ForgeDay, count: Int, salt: String = "") -> Int {
        precondition(count > 0)
        // FNV-1a over the date's digits. Cheap, well-spread and — the only
        // property that matters here — identical on every device and every
        // launch.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in [UInt64(day.year), UInt64(day.month), UInt64(day.day)] {
            hash = (hash ^ byte) &* 0x1000_0000_01b3
        }
        for byte in salt.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x1000_0000_01b3
        }
        return Int(hash % UInt64(count))
    }

    // MARK: Intellect
    //
    // What you read, learn and make. The old `mind` shelf was half stillness and
    // half study, which is two dimensions; the stillness went to Mental and what
    // is left is the half that has an output — you have read it, drawn it, or
    // can say it out loud to somebody.

    static let intellect: [DailyChallenge] = [
        DailyChallenge(
            id: "ch.int.read",
            title: "Twenty pages",
            detail: "Paper if you have it, in one sitting rather than in five.",
            focus: .intellect,
            difficulty: .easy
        ),
        DailyChallenge(
            id: "ch.int.lookup",
            title: "Look up the thing you pretend to know",
            detail: "The word, the acronym, the bit of history you nod along to. Ten minutes, properly.",
            focus: .intellect,
            difficulty: .easy
        ),
        DailyChallenge(
            id: "ch.int.log",
            title: "Three sentences on what you learned today",
            detail: "Written before you sleep, and none of it something you already knew this morning.",
            focus: .intellect,
            difficulty: .easy
        ),
        DailyChallenge(
            id: "ch.int.disagree",
            title: "Read something you disagree with",
            detail: "All the way to the end, without composing the reply in your head.",
            focus: .intellect,
            difficulty: .medium
        ),
        DailyChallenge(
            id: "ch.int.teach",
            title: "Teach it to somebody in five minutes",
            detail: "Something you learned this month. If you cannot, you did not learn it.",
            focus: .intellect,
            difficulty: .medium
        ),
        DailyChallenge(
            id: "ch.int.worst",
            title: "An hour on the thing you are worst at",
            detail: "The skill you avoid because you are bad at it. One hour, badly, today.",
            focus: .intellect,
            difficulty: .medium
        ),
        DailyChallenge(
            id: "ch.int.draw",
            title: "Draw what is in front of you",
            detail: "Twenty minutes, from life rather than a photograph. Look more than you draw.",
            focus: .intellect,
            difficulty: .medium
        ),
        DailyChallenge(
            id: "ch.int.fifty",
            title: "Fifty pages",
            detail: "One book, one day. Put the hours somewhere and take them.",
            focus: .intellect,
            difficulty: .hard
        ),
        DailyChallenge(
            id: "ch.int.memorise",
            title: "Ten lines, by heart",
            detail: "A poem, a passage, a proof. Recite it tonight without looking.",
            focus: .intellect,
            difficulty: .hard
        ),
        DailyChallenge(
            id: "ch.int.apart",
            title: "Take one thing apart",
            detail: "A song, a recipe, a page of somebody's code. Work out how it is made, then write down how.",
            focus: .intellect,
            difficulty: .hard
        ),
    ]

    // MARK: Relationship
    //
    // The people you show up for — and the dimension that had no challenges at
    // all until the aims became the six. Every one of these is something the
    // user starts and can finish alone: a call placed, a letter written, a
    // question asked. Nothing here needs a third party to agree to anything
    // before it counts, which is the rule that used to be an argument for having
    // no Relationship challenges and is now the rule for writing them.

    static let relationship: [DailyChallenge] = [
        DailyChallenge(
            id: "ch.rel.notice",
            title: "Say the thing you noticed",
            detail: "Out loud, to the person it is about. Specific, not nice: what they did and what it took.",
            focus: .relationship,
            difficulty: .easy
        ),
        DailyChallenge(
            id: "ch.rel.call",
            title: "Call instead of typing",
            detail: "The next message you were going to send, say it. Four minutes, and it lands differently.",
            focus: .relationship,
            difficulty: .easy
        ),
        DailyChallenge(
            id: "ch.rel.second",
            title: "Ask a second question",
            detail: "Every conversation today, one more question before you start talking about yourself.",
            focus: .relationship,
            difficulty: .easy
        ),
        DailyChallenge(
            id: "ch.rel.present",
            title: "Phone in another room all evening",
            detail: "Whoever is in the house tonight gets a version of you that is actually in it.",
            focus: .relationship,
            difficulty: .medium
        ),
        DailyChallenge(
            id: "ch.rel.letter",
            title: "Write to somebody on paper",
            detail: "A letter, in an envelope, posted today. Slower than a text and it stays on a shelf.",
            focus: .relationship,
            difficulty: .medium
        ),
        DailyChallenge(
            id: "ch.rel.plan",
            title: "Put a date on the thing you keep saying soon about",
            detail: "One person, one actual day, in both calendars before tonight.",
            focus: .relationship,
            difficulty: .medium
        ),
        DailyChallenge(
            id: "ch.rel.avoid",
            title: "Ring the one you have been avoiding",
            detail: "Ten minutes, and it stops being a thing you carry around all week.",
            focus: .relationship,
            difficulty: .medium
        ),
        DailyChallenge(
            id: "ch.rel.sorry",
            title: "Apologise properly, once",
            detail: "One sentence, no \"but\", nothing explained afterwards. To whoever is owed it.",
            focus: .relationship,
            difficulty: .hard
        ),
        DailyChallenge(
            id: "ch.rel.cook",
            title: "Cook for somebody tonight",
            detail: "From ingredients, at a table, for one person who was not expecting it.",
            focus: .relationship,
            difficulty: .hard
        ),
        DailyChallenge(
            id: "ch.rel.no",
            title: "Say no once, without apologising",
            detail: "No excuse and no softening. \"No, I can't do that.\" Then stop talking.",
            focus: .relationship,
            difficulty: .hard
        ),
    ]

    // MARK: Discipline

    static let discipline: [DailyChallenge] = [
        DailyChallenge(
            id: "ch.disc.cold",
            title: "Ninety seconds cold",
            detail: "Turn it to cold at the end of the shower and do not negotiate the count.",
            focus: .discipline,
            difficulty: .easy
        ),
        DailyChallenge(
            id: "ch.disc.bedroom",
            title: "The phone sleeps elsewhere",
            detail: "It charges in another room tonight. Buy an alarm clock if you have to.",
            focus: .discipline,
            difficulty: .easy
        ),
        DailyChallenge(
            id: "ch.disc.reset",
            title: "Everything back where it lives",
            detail: "Every object you pick up today goes back when you are done with it. All day, no pile.",
            focus: .discipline,
            difficulty: .easy
        ),
        DailyChallenge(
            id: "ch.disc.alarm",
            title: "Up on the first alarm",
            detail: "No snooze. Feet on the floor inside ten seconds, every time it goes.",
            focus: .discipline,
            difficulty: .medium
        ),
        DailyChallenge(
            id: "ch.disc.first",
            title: "No screen for the first hour",
            detail: "Whatever is on the phone was there yesterday. It will keep.",
            focus: .discipline,
            difficulty: .medium
        ),
        DailyChallenge(
            id: "ch.disc.sugar",
            title: "Nothing sweet for a day",
            detail: "One day, not a diet. A decision you only have to make once.",
            focus: .discipline,
            difficulty: .medium
        ),
        DailyChallenge(
            id: "ch.disc.bed",
            title: "Lights out by eleven",
            detail: "In bed, phone in another room, screen off. The day ends when you say it does.",
            focus: .discipline,
            difficulty: .medium
        ),
        DailyChallenge(
            id: "ch.disc.worst",
            title: "The task you have moved three times",
            detail: "The one that keeps being rewritten onto tomorrow. Do it before anything easier.",
            focus: .discipline,
            difficulty: .hard
        ),
        DailyChallenge(
            id: "ch.disc.silent",
            title: "A day without complaining",
            detail: "Out loud, in writing, or under your breath. Count the times you nearly do.",
            focus: .discipline,
            difficulty: .hard
        ),
        DailyChallenge(
            id: "ch.disc.promises",
            title: "Keep every small promise you make today",
            detail: "Every \"I'll send it tonight\", every \"two minutes\". Make fewer, or keep all of them.",
            focus: .discipline,
            difficulty: .hard
        ),
    ]

    // MARK: Ambition

    static let ambition: [DailyChallenge] = [
        DailyChallenge(
            id: "ch.amb.three",
            title: "Three things, then stop",
            detail: "Decide them before you start. Everything else belongs to tomorrow.",
            focus: .ambition,
            difficulty: .easy
        ),
        DailyChallenge(
            id: "ch.amb.first",
            title: "Hardest thing first",
            detail: "Before the inbox, before the coffee. The one you were going to leave until four.",
            focus: .ambition,
            difficulty: .easy
        ),
        DailyChallenge(
            id: "ch.amb.sentence",
            title: "One sentence on what you are actually building",
            detail: "Write it down today. Read it back tomorrow and see whether it survives.",
            focus: .ambition,
            difficulty: .easy
        ),
        DailyChallenge(
            id: "ch.amb.deep",
            title: "Ninety uninterrupted minutes",
            detail: "One block, one problem, nothing else allowed in. Set the clock before you begin.",
            focus: .ambition,
            difficulty: .medium
        ),
        DailyChallenge(
            id: "ch.amb.numbers",
            title: "Look at the real numbers",
            detail: "The one you have been estimating — money, hours, users, weight. Look, and write it down.",
            focus: .ambition,
            difficulty: .medium
        ),
        DailyChallenge(
            id: "ch.amb.show",
            title: "Show somebody the unfinished thing",
            detail: "The work you have been polishing in private. One person sees it today.",
            focus: .ambition,
            difficulty: .medium
        ),
        DailyChallenge(
            id: "ch.amb.morning",
            title: "Two hours before your first message",
            detail: "Nothing answered until the work that is actually yours has had two hours of you.",
            focus: .ambition,
            difficulty: .medium
        ),
        DailyChallenge(
            id: "ch.amb.ship",
            title: "Ship the rough version",
            detail: "Send it today at eighty per cent instead of next week at ninety.",
            focus: .ambition,
            difficulty: .hard
        ),
        DailyChallenge(
            id: "ch.amb.ask",
            title: "Say the number out loud",
            detail: "The rate, the salary, the price. Say it, and then say nothing else.",
            focus: .ambition,
            difficulty: .hard
        ),
        DailyChallenge(
            id: "ch.amb.cancel",
            title: "Cancel one thing that is not yours",
            detail: "The meeting, the favour, the project you agreed to out of politeness. One, today.",
            focus: .ambition,
            difficulty: .hard
        ),
    ]

    // MARK: Mental

    static let mental: [DailyChallenge] = [
        DailyChallenge(
            id: "ch.men.sit",
            title: "Ten minutes, sitting still",
            detail: "No app, no timer voice, no music. Set a clock and sit.",
            focus: .mental,
            difficulty: .easy
        ),
        DailyChallenge(
            id: "ch.men.meal",
            title: "Eat one meal with nothing else happening",
            detail: "No phone, no screen, nothing to read. Just the food, until it is gone.",
            focus: .mental,
            difficulty: .easy
        ),
        DailyChallenge(
            id: "ch.men.worry",
            title: "Name the worry and its actual size",
            detail: "On paper: what it is, what it would cost, what you would do. Ten minutes.",
            focus: .mental,
            difficulty: .easy
        ),
        DailyChallenge(
            id: "ch.men.unplugged",
            title: "An hour outside without your phone",
            detail: "Not in your pocket. Left at home, with nothing in your ears.",
            focus: .mental,
            difficulty: .medium
        ),
        DailyChallenge(
            id: "ch.men.review",
            title: "Three lines on what went wrong",
            detail: "Last week, honestly, with no defence attached to any of them.",
            focus: .mental,
            difficulty: .medium
        ),
        DailyChallenge(
            id: "ch.men.evening",
            title: "A whole evening with no screen",
            detail: "From dinner until bed. Books, people, the window, whatever is left.",
            focus: .mental,
            difficulty: .medium
        ),
        DailyChallenge(
            id: "ch.men.pause",
            title: "Ten seconds before you answer",
            detail: "Every time somebody says something that lands badly today. Count them out.",
            focus: .mental,
            difficulty: .medium
        ),
        DailyChallenge(
            id: "ch.men.silence",
            title: "No music, no podcast, all day",
            detail: "The commute, the kitchen, the gym, the walk. Twenty-four hours of your own head.",
            focus: .mental,
            difficulty: .hard
        ),
        DailyChallenge(
            id: "ch.men.twenty",
            title: "Twenty minutes, no timer, no guide",
            detail: "Sit until it is genuinely uncomfortable, and then stay another five.",
            focus: .mental,
            difficulty: .hard
        ),
        DailyChallenge(
            id: "ch.men.letgo",
            title: "Let one thing go today",
            detail: "The argument you are still holding. Decide it is finished, and behave as if it is.",
            focus: .mental,
            difficulty: .hard
        ),
    ]

    // MARK: Physical

    static let physical: [DailyChallenge] = [
        DailyChallenge(
            id: "ch.phy.mobility",
            title: "Ten minutes on the floor",
            detail: "Hips, hamstrings, shoulders. The ten minutes everybody skips.",
            focus: .physical,
            difficulty: .easy
        ),
        DailyChallenge(
            id: "ch.phy.stairs",
            title: "Stairs only",
            detail: "Every lift and escalator you meet today, walk straight past it.",
            focus: .physical,
            difficulty: .easy
        ),
        DailyChallenge(
            id: "ch.phy.walk",
            title: "Forty minutes on foot",
            detail: "Outside, no podcast, no call. Just the walk and the weather.",
            focus: .physical,
            difficulty: .easy
        ),
        DailyChallenge(
            id: "ch.phy.hundred",
            title: "One hundred press-ups",
            detail: "Across the whole day, in as many sets as it takes. Count them.",
            focus: .physical,
            difficulty: .medium
        ),
        DailyChallenge(
            id: "ch.phy.squats",
            title: "Two hundred squats",
            detail: "Bodyweight, spread across the day. Twenty every time you stand up works.",
            focus: .physical,
            difficulty: .medium
        ),
        DailyChallenge(
            id: "ch.phy.tenk",
            title: "Ten thousand steps",
            detail: "However you get them. Check before dinner, not after.",
            focus: .physical,
            difficulty: .medium
        ),
        DailyChallenge(
            id: "ch.phy.water",
            title: "Nothing to drink but water",
            detail: "One day. Every coffee, beer and can you skip, you will notice yourself skipping.",
            focus: .physical,
            difficulty: .medium
        ),
        DailyChallenge(
            id: "ch.phy.fivek",
            title: "Five kilometres",
            detail: "Run it or walk it, in one go, before the day gets away from you.",
            focus: .physical,
            difficulty: .hard
        ),
        DailyChallenge(
            id: "ch.phy.twomore",
            title: "Two reps past the number",
            detail: "Every set today, add two to the number you had in your head when you started.",
            focus: .physical,
            difficulty: .hard
        ),
        DailyChallenge(
            id: "ch.phy.carry",
            title: "Carry something heavy for a kilometre",
            detail: "A pack, a case, a sandbag. Put it down at the end and not before.",
            focus: .physical,
            difficulty: .hard
        ),
    ]
}

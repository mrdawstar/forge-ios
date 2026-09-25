import SwiftUI

/// Who somebody is becoming.
///
/// The one thing Forge had no way to say. Everything else this app records is a
/// **volume** — days kept, completion rate, the chain — and a volume cannot
/// answer the only question the product is actually about. "Two hundred days"
/// says how much; it does not say what of, or what for. An identity is the
/// direction those days are pointing in, and it is supplied by the user in their
/// own words because nobody else is in a position to write it.
///
/// It is a **claim, not a goal**. There is no target, no deadline, no percentage
/// and nothing to complete: an identity is not a thing you finish, it is a thing
/// you accumulate evidence for. That distinction decides the whole type — the
/// moment this gained a `target` it would be a milestone with a sentence on it,
/// and the app already has milestones.
///
/// **Optional, and meant to stay that way.** Forge with no identities is Forge:
/// every screen works, every day is earned the same way, and an install that
/// never names one has lost nothing. That is the same promise `ForgePath` makes
/// about worlds, and it is load-bearing for the same reason — a feature that can
/// be declined is the only kind that can be genuinely wanted.
struct Identity: Identifiable, Codable, Equatable, Sendable {

    /// Minted, stable, and never derived from the statement.
    ///
    /// The statement is the part somebody rewrites at two in the morning when
    /// they work out what they actually meant. Deriving the id from it would
    /// mean every rewrite orphaned the evidence behind it, which is the one
    /// thing this type exists to accumulate.
    let id: String

    /// The user's own words. Second person, present tense: "Someone who trains".
    ///
    /// Not a name and not a title. "Fitness" is a category and says nothing;
    /// "Someone who trains" is a claim about a person, and a claim is the thing
    /// a day can be evidence for. The shipped `IdentityPrompt` values are
    /// written in exactly this register so the first one somebody sees teaches
    /// the shape of the rest.
    var statement: String

    /// An SF Symbol, from the same catalogue activities are drawn from
    /// (`ActivityIcons`), so an identity and the activities under it are visibly
    /// the same kind of object.
    var symbol: String

    /// The colour an identity tints its own rows with.
    ///
    /// `ForgeAccent` rather than a free `Color`, reused deliberately: it is
    /// already a closed set chosen so nothing can fail contrast against the
    /// scene, and a second palette type would be a second place for that review
    /// to fail to happen. See `ForgeAccent.palette`.
    var accent: ForgeAccent

    var createdAt: Date

    /// When this stopped being something somebody was working toward.
    ///
    /// **Retired, never deleted, and the distinction is the whole rule.** An
    /// identity somebody pursued for eight months still explains eight months of
    /// their history: every tagged activity, every day of evidence, every
    /// sentence the record could say about that stretch. Deleting it would
    /// orphan all of that and leave a year of days that were *for* something
    /// pointing at nothing — the app quietly losing the meaning of work somebody
    /// actually did.
    ///
    /// So the only destructive operation is the one a person explicitly asks for
    /// by a different name. See `IdentityStore.retire(_:)` and `delete(_:)`.
    var retiredAt: Date?

    /// Whether this is one of the ones being worked toward now.
    var isActive: Bool { retiredAt == nil }

    /// How many may be pursued at once.
    ///
    /// Three, and it is a product decision rather than a storage one. Three is
    /// about the most a person can hold in their head as things they are
    /// *becoming*; a fourth is the point at which the list stops being an answer
    /// to "who are you" and starts being a to-do list wearing a different word.
    /// The cap is on **active** identities only — retiring one makes room, which
    /// is what keeps the limit from punishing somebody whose life changed.
    static let activeLimit = 3

    /// The longest a statement may be.
    ///
    /// Long enough for "Someone who finishes what they start" with room to
    /// spare, short enough that it cannot become a paragraph. This is a sentence
    /// that has to fit under a heading and be readable at a glance in a row.
    static let statementLimit = 60

    init(
        id: String = "identity.\(UUID().uuidString)",
        statement: String,
        symbol: String = ActivityIcons.fallback,
        accent: ForgeAccent = .forge,
        createdAt: Date = .now,
        retiredAt: Date? = nil
    ) {
        self.id = id
        self.statement = Identity.trimmed(statement)
        self.symbol = symbol
        self.accent = accent
        self.createdAt = createdAt
        self.retiredAt = retiredAt
    }

    /// Trimmed and clamped in one place, so there is one answer to "what does
    /// the store actually hold" whichever door a statement arrives through.
    static func trimmed(_ statement: String) -> String {
        let clean = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(clean.prefix(statementLimit))
    }

    // MARK: - Reading what is on disk

    /// Hand-written and tolerant, for the reason every decoder in this app is.
    ///
    /// The synthesised decoder treats a non-optional property as **required**
    /// even when it has a default — the default belongs to the memberwise
    /// initialiser and nothing else — and one throw fails the whole array. The
    /// failure mode is somebody opening Forge to find the sentence they wrote
    /// about who they are gone, which is the single worst thing this file could
    /// do. Only `id` is genuinely required; everything else falls back to
    /// something usable. See `CustomMilestone` and `Ritual`, which learned this
    /// the same way.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        statement = Identity.trimmed(
            try c.decodeIfPresent(String.self, forKey: .statement) ?? ""
        )
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? ActivityIcons.fallback
        // Read through the raw value rather than by conforming `ForgeAccent` to
        // `Codable`. A synthesised enum decoder throws on a case it has never
        // heard of, so an accent added by a later build would fail the whole
        // array on an older one — and Forge's own accent is the safe landing,
        // because being wrong here costs a tint and never a fact.
        accent = ForgeAccent(
            rawValue: try c.decodeIfPresent(String.self, forKey: .accent) ?? ""
        ) ?? .forge
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        retiredAt = try c.decodeIfPresent(Date.self, forKey: .retiredAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(statement, forKey: .statement)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(accent.rawValue, forKey: .accent)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(retiredAt, forKey: .retiredAt)
    }

    /// Spelled out because the coder is, and a synthesised `CodingKeys` beside a
    /// hand-written decoder goes wrong the first time somebody renames a
    /// property.
    private enum CodingKeys: String, CodingKey {
        case id, statement, symbol, accent, createdAt, retiredAt
    }
}

// MARK: - Where to start

/// The starting points offered to somebody who cannot write their own.
///
/// A blank field is the fastest way to make a person feel they have failed a
/// question about themselves. These exist so the first screen is a **choice**
/// rather than an essay, and every one of them is editable the moment it is
/// taken — what somebody picks here is a first draft, not a category they have
/// been filed under.
///
/// Data rather than generated, and written in one register: *second person,
/// present tense, no adjective about how well it is going.* "Someone who trains"
/// and never "Someone who trains hard" — the second one is a standard somebody
/// can fail before breakfast, and Forge does not do that.
///
/// Seven, which is enough that most people find themselves on the list and few
/// enough that the list can be read without scrolling past the point of caring.
enum IdentityPrompt: String, CaseIterable, Identifiable, Sendable {
    case trains
    case finishes
    case present
    case reads
    case builds
    case early
    case steady

    var id: String { rawValue }

    /// The sentence itself, in the register described above.
    var statement: String {
        switch self {
        case .trains: "Someone who trains"
        case .finishes: "Someone who finishes what they start"
        case .present: "Someone who is present"
        case .reads: "Someone who reads"
        case .builds: "Someone who builds things"
        case .early: "Someone who is up early"
        case .steady: "Someone who keeps their word"
        }
    }

    var symbol: String {
        switch self {
        case .trains: "figure.strengthtraining.traditional"
        case .finishes: "checkmark.seal"
        case .present: "figure.mind.and.body"
        case .reads: "book"
        case .builds: "hammer"
        case .early: "sunrise"
        case .steady: "hand.raised"
        }
    }

    /// A colour each, so a shelf of seven does not read as one list in one
    /// tint. Nothing is reserved and nothing is exclusive — two identities may
    /// share an accent, and the user may change it afterwards.
    var accent: ForgeAccent {
        switch self {
        case .trains: .ember
        case .finishes: .forge
        case .present: .dawn
        case .reads: .slate
        case .builds: .ember
        case .early: .dawn
        case .steady: .gold
        }
    }

    /// This prompt as a real identity, ready to be stored. The user owns it
    /// from this moment: the statement, the symbol and the colour are all
    /// editable, and nothing records which prompt it came from.
    func made(at instant: Date = .now) -> Identity {
        Identity(
            statement: statement,
            symbol: symbol,
            accent: accent,
            createdAt: instant
        )
    }

    /// The shipped starting point an identity is still wearing, if any.
    ///
    /// Matched on the **statement** rather than by a stored reference, because
    /// `Identity` deliberately records nothing about where it came from — taking
    /// a prompt mints an ordinary identity the user owns, and they may rewrite
    /// it into something else entirely. So an untouched prompt is recognised
    /// here and an edited one is honestly not, which is the correct answer for
    /// both: the app should not go on treating a sentence somebody replaced as
    /// though it were the one it shipped.
    ///
    /// The one place that lookup lives. It used to be written out inside
    /// `IdentityActivities.matches`, and `ForgePath` needing the same question
    /// answered — see `affinity(among:)` — is exactly how two copies of a rule
    /// like this start to disagree.
    static func matching(_ identity: Identity) -> IdentityPrompt? {
        let statement = identity.statement.lowercased()
        return allCases.first { $0.statement.lowercased() == statement }
    }
}

// MARK: - Reaching them from a view

private struct IdentitiesKey: EnvironmentKey {
    static let defaultValue: [Identity] = []
}

extension EnvironmentValues {
    /// The identities being worked toward now, for the screens that draw them.
    ///
    /// Pushed into the environment rather than passed down, the same way
    /// `activePath` is and for the same reason: a row that wants to tint itself
    /// by what it is evidence for should not need a view model threaded through
    /// four initialisers to find out.
    ///
    /// Empty is the ordinary state and every reader has to be correct for it —
    /// an install that never names one must look exactly like the app did
    /// before this existed. See `Identity`.
    var identities: [Identity] {
        get { self[IdentitiesKey.self] }
        set { self[IdentitiesKey.self] = newValue }
    }
}

// MARK: - Accent

/// The closed set of colours an identity may carry.
///
/// # Why this outlived the worlds it was written for
///
/// It was `ForgeAccent`, and it existed so that eight archetypes could each look
/// like a different place. The archetypes are gone; the type is not, because
/// `Identity` uses it and the raw values are on disk in every identity anybody
/// has ever named. Renaming the *type* is free — the `String` raw values are the
/// storage contract and they are untouched — but deleting it would mean either
/// migrating that column or picking colours at random.
///
/// It stays a **closed set** for the reason it always was: something that can
/// name any colour can make the app unreadable, and the review that catches that
/// has to happen in one file rather than in whatever file the next feature is
/// written in. Nothing here tints a control any more — `ForgeTheme.accent` is
/// the only colour allowed on a button. These mark an identity, and nothing
/// else.

/// The accents worlds are allowed to pick from.
///
/// A closed set rather than a free `Color`, so no Path can choose something that
/// fails contrast against the scene. Adding one is a deliberate act with a
/// review attached, which is the point.
enum ForgeAccent: String, Equatable, Sendable, CaseIterable, Hashable {
    case forge, slate, gold, ember, dawn, ink, moss, tide, bone

    /// Every accent, for the tests that have to be exhaustive over the set.
    ///
    /// `CaseIterable` gives this for free; the alias exists so the contrast
    /// tests read as a promise about the whole set rather than as an
    /// implementation detail of the enum. See `AccessibilityTests`.
    static var allKnown: [ForgeAccent] { allCases }

    /// The colour this identity is marked in.
    var color: Color { palette.accent }

    /// The three colours a world is allowed, and why there are three.
    ///
    /// It was one. One accent is enough to tint a button and nowhere near enough
    /// to make a world *feel* like itself — every card ended up the same dark
    /// glass panel with a differently coloured button on it, which is the visual
    /// equivalent of four novels with the same cover in four colours.
    ///
    /// Three is the smallest set that can carry an identity, and each has a job
    /// it does everywhere:
    ///
    /// - `accent` tints controls. It is the only one allowed on a button, and
    ///   the only one that has to clear contrast against glass.
    /// - `highlight` marks structure — the hairline beside a movement, the rule
    ///   under a heading, the difficulty rungs. Never text-sized, never on its
    ///   own, so it can be a colour that would fail as a label.
    /// - `base` is the dark a world's surfaces grade toward, so the scrim over
    ///   the Operator's night is cold and the scrim over the Craftsman's fire is not.
    ///   Nothing is ever *set* to it; it is always mixed under something.
    ///
    /// Still a closed set rather than a free `ForgePalette` on `PathTheme`, for
    /// the reason the single accent was: a world that can name any three colours
    /// is a world that can make the app unreadable, and the review that catches
    /// that has to happen here rather than in whatever file a future Path is
    /// written in.
    /// No world's primary is grey.
    ///
    /// Two of them were, and it was the same mistake twice. The Beginner's was chosen
    /// "to be unmemorable, because it is the one somebody is meant to leave" —
    /// which is a good argument for quiet copy and a bad one for a colour: it
    /// made the first world anybody sees the one that looks least like a
    /// decision. The Operator's slate had drifted the same way, so the two cards
    /// at the top of the shelf were both grey-blue and the tab read as
    /// monochrome.
    ///
    /// The one exception, argued for where it is used: the Monk's `bone`. See
    /// the case itself — it is a warm off-white rather than a neutral, and a
    /// world whose whole subject is subtraction is the only one that can carry
    /// the absence of a colour as a statement rather than as an omission.
    ///
    /// A grey accent is also unreachable as an *identity*. Every other lever a
    /// world has — the plate, the blade, the weather — is expensive to add;
    /// colour is free and does most of the work of making eight worlds feel like
    /// eight places. Spending it on neutrality is spending the cheapest thing
    /// there is on nothing — and with the plates gone it is currently doing
    /// almost all of that work on its own.
    var palette: ForgePalette {
        switch self {
        // Forge itself, in the system blue it is drawn in again.
        //
        // The accent is the app's own, so Default Forge and a Path with no art
        // chosen for it still look identical. What changed is that the app's own
        // went orange for a while and is back: blue is what every control in
        // iOS is, it is the colour a Forge user's muscle memory already has for
        // "this is the button", and the ember it was replaced with was competing
        // with the one place in the app that genuinely is on fire.
        case .forge:
            ForgePalette(
                accent: ForgeTheme.accent,
                highlight: Color(red: 0.46, green: 0.75, blue: 1.0),
                base: Color(red: 0.04, green: 0.05, blue: 0.07)
            )
        // The Operator: a cold, deep signal blue with steel on it. Darker and far
        // more saturated than the slate it replaces, so a night city reads as a
        // night city rather than as an unfinished screen.
        case .slate:
            ForgePalette(
                accent: Color(red: 0.35, green: 0.56, blue: 0.92),
                highlight: Color(red: 0.62, green: 0.78, blue: 1.0),
                base: Color(red: 0.04, green: 0.06, blue: 0.11)
            )
        // The Athlete: gold off the floodlights, pitch green under it.
        case .gold:
            ForgePalette(
                accent: Color(red: 0.95, green: 0.75, blue: 0.26),
                highlight: Color(red: 0.42, green: 0.72, blue: 0.42),
                base: Color(red: 0.07, green: 0.06, blue: 0.03)
            )
        // The Craftsman: black, red, and the orange of an arc coming off metal.
        case .ember:
            ForgePalette(
                accent: Color(red: 0.93, green: 0.31, blue: 0.24),
                highlight: Color(red: 1.0, green: 0.62, blue: 0.26),
                base: Color(red: 0.07, green: 0.04, blue: 0.04)
            )
        // The Beginner: first light. A clean sky blue with the warm edge the sun
        // comes up with — the one world whose colour is meant to feel like a
        // morning rather than like a brand.
        case .dawn:
            ForgePalette(
                accent: Color(red: 0.20, green: 0.62, blue: 0.98),
                highlight: Color(red: 1.0, green: 0.78, blue: 0.52),
                base: Color(red: 0.05, green: 0.07, blue: 0.11)
            )
        // The Scholar: ink and lamplight. A deep indigo with the warm paper
        // colour a desk lamp throws, which is the only pairing that reads as
        // reading rather than as a technology brand's evening mode.
        case .ink:
            ForgePalette(
                accent: Color(red: 0.53, green: 0.51, blue: 0.95),
                highlight: Color(red: 0.98, green: 0.86, blue: 0.66),
                base: Color(red: 0.05, green: 0.05, blue: 0.10)
            )
        // The Steward: the one green in the catalog. Not a health-app green —
        // deeper and greyer than that, the colour of something looked after for
        // a long time rather than of something recently bought.
        case .moss:
            ForgePalette(
                accent: Color(red: 0.38, green: 0.70, blue: 0.48),
                highlight: Color(red: 0.86, green: 0.78, blue: 0.52),
                base: Color(red: 0.04, green: 0.07, blue: 0.05)
            )
        // The Builder: a cold working teal against the Craftsman's fire. The two
        // making worlds have to be told apart at a glance on a shelf, and the
        // temperature does it faster than the name does.
        case .tide:
            ForgePalette(
                accent: Color(red: 0.25, green: 0.75, blue: 0.76),
                highlight: Color(red: 0.55, green: 0.88, blue: 0.80),
                base: Color(red: 0.03, green: 0.07, blue: 0.08)
            )
        // The Monk: bone. The one place the no-grey rule is argued with, and it
        // survives the argument — this is a warm off-white, the colour of paper
        // and unglazed clay, not the neutral that made two worlds look
        // unfinished. A world about subtraction cannot arrive in a strong tint
        // without disagreeing with itself, and the warmth is what keeps it from
        // reading as a screen with no colour in it.
        case .bone:
            ForgePalette(
                accent: Color(red: 0.90, green: 0.86, blue: 0.78),
                highlight: Color(red: 0.78, green: 0.72, blue: 0.60),
                base: Color(red: 0.07, green: 0.06, blue: 0.05)
            )
        }
    }
}

/// A world's three colours. See `ForgeAccent.palette` for what each one does.
struct ForgePalette: Equatable, Sendable {
    let accent: Color
    let highlight: Color
    let base: Color
}

import Foundation

// MARK: - What Ask Forge is told, on top of the brief

/// Everything Ask Forge sends about the person beyond `AIBrief`, taken once,
/// at the moment of asking (DIRECTION_1_1 §9, FORGE_CONTEXT §17.6).
///
/// # Why a second struct and not more fields on `AIBrief`
///
/// `AIBrief` is what Plan and the Weekly Reading send, and its documentation
/// promises "no per-day record". Ask Forge needs a little more to be useful —
/// the six numbers on Becoming, the running Arc and today's list — and that is
/// a **wider transmission**, made only by the one feature that needs it. So it
/// lives here, beside the brief rather than inside it: Plan and the reading
/// send exactly what they always sent, and `AIDisclosureView` draws this struct
/// in a section of its own headed "When you use Ask Forge, also".
///
/// Nothing here is new information about the person. Every value is on a
/// screen they already see: the scores and OVR on Becoming, the Arc's day and
/// phase on its card, today's list on the Forge tab.
struct CoachBrief: Equatable, Sendable {

    /// Where somebody is in the running Arc. The id, the day and the phase are
    /// sent; the name and length are kept for the screen (the starters, "Ask
    /// about this Arc") and are derivable from the id anyway.
    struct ArcPlace: Equatable, Sendable {
        let id: String
        let name: String
        let day: Int
        let length: Int
        /// The phase's name, as its card shows it: "Build".
        let phase: String
        /// The week of the Arc today falls in, from one.
        var week: Int { (max(day, 1) - 1) / 7 + 1 }
        var weeks: Int { (max(length, 1) - 1) / 7 + 1 }
    }

    /// One of the six, as Becoming shows it: a score, or nil for a dimension
    /// with nothing to score yet.
    struct Score: Equatable, Sendable {
        let category: RitualCategory
        let score: Int?
        /// The change over seven days, when it can be known (`StatGlance`).
        /// Used for the starters only and never sent.
        var weekChange: Int? = nil
    }

    /// One of today's activities and whether it is done. Names only — no time,
    /// no verification, no date.
    struct TodayItem: Equatable, Sendable {
        let name: String
        let isDone: Bool
    }

    var brief: AIBrief
    var arc: ArcPlace?
    var scores: [Score] = []
    /// OVR as Becoming shows it, or nil before any of the six has a score.
    var overall: Int?
    var today: [TodayItem] = []
}

/// Where Ask Forge was opened from, which only changes the starters.
enum CoachTopic: Equatable, Sendable, Identifiable {
    /// The Becoming navigation bar.
    case general
    /// "Ask about this Arc", on the running Arc's card.
    case arc

    var id: String {
        switch self {
        case .general: "general"
        case .arc: "arc"
        }
    }
}

// MARK: - The conversation, kept on the phone

/// One line in Ask Forge.
///
/// Kept on this phone only (`CoachHistory`), never synced, never in telemetry.
struct CoachMessage: Codable, Identifiable, Equatable, Sendable {

    enum Role: String, Codable, Sendable {
        case user
        /// Forge's side of the conversation. Not a character: there is no name
        /// or avatar on screen, and the label says what wrote it.
        case forge
    }

    enum Kind: String, Codable, Sendable {
        /// What the person wrote, or a reply the model wrote.
        case message
        /// The 988 reply to a message that suggests a crisis. Never part of
        /// what a later request carries, and neither is the message it answered.
        case safety
        /// "Ask Forge can't reach the server right now." Said once, never sent.
        case notice
        /// Worked out on this phone when the server could not be reached.
        case local
    }

    var id = UUID()
    var role: Role
    var kind: Kind = .message
    var text: String
    var at: Date = .now
    /// A proposed change to the week, never applied from here: it opens Plan's
    /// review (§5 #9). Re-checked against the week as it is when opened, so a
    /// proposal from last week cannot write against activities that are gone.
    var proposal: CoachProposal?
    /// The person's message that a safety reply answered: kept on screen,
    /// never sent again.
    var isWithheld = false

    /// Whether a later request may carry this line.
    var isTransmittable: Bool {
        switch role {
        case .user: kind == .message && !isWithheld
        case .forge: kind == .message
        }
    }

    init(
        id: UUID = UUID(), role: Role, kind: Kind = .message, text: String, at: Date = .now,
        proposal: CoachProposal? = nil, isWithheld: Bool = false
    ) {
        self.id = id
        self.role = role
        self.kind = kind
        self.text = text
        self.at = at
        self.proposal = proposal
        self.isWithheld = isWithheld
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, kind, text, at, proposal, isWithheld
    }

    /// Hand-written and tolerant, like every stored type here (§16). It was
    /// synthesised until 1.1's release pass, where that meant one line written
    /// by a later build — a kind this one does not know — or one damaged field
    /// emptied the whole conversation, and the next line saved overwrote it
    /// (FORGE_CONTEXT §17.7). `CoachHistory` now drops a line that does not
    /// read and keeps the rest.
    ///
    /// The role and the words are required: without them there is no line. A
    /// kind that is not this build's drops the line rather than mislabelling it
    /// — a reply cannot be called the model's, or the phone's, on a guess
    /// (§5 #10). A missing kind is the person's own message, or no line at all
    /// on Forge's side. **A person's line whose withholding cannot be read is
    /// withheld**: the only cost is a turn of context, and the alternative is
    /// sending a message a safety reply answered.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        role = try c.decode(Role.self, forKey: .role)
        text = try c.decode(String.self, forKey: .text)
        if c.contains(.kind) {
            kind = try c.decode(Kind.self, forKey: .kind)
        } else if role == .user {
            kind = .message
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.kind, .init(codingPath: c.codingPath, debugDescription: "A reply says what wrote it.")
            )
        }
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        at = (try? c.decodeIfPresent(Date.self, forKey: .at)) ?? .distantPast
        proposal = try? c.decodeIfPresent(CoachProposal.self, forKey: .proposal)
        isWithheld = (try? c.decodeIfPresent(Bool.self, forKey: .isWithheld)) ?? (role == .user)
    }
}

/// A list read one element at a time: an element that does not read is
/// dropped and the rest are kept — the shape of every tolerant list here
/// (`ArcEnrollment.decodeAll`, `KeptChallenge.decodeAll`).
struct LossyList<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: Decoder) throws {
        // `Slot?`, not `Slot`: JSONDecoder answers a `null` element with an
        // error before any initialiser runs, which would cost the whole list.
        elements = try [Slot?].init(from: decoder).compactMap { $0?.value }
    }

    /// Always decodes, so the list moves past an element that does not.
    private struct Slot: Decodable {
        let value: Element?
        init(from decoder: Decoder) throws { value = try? Element(from: decoder) }
    }
}

/// A proposal as it came over the wire — the plan's shape — and as it is
/// kept in the history. Untrusted until `plan(against:)` resolves it.
struct CoachProposal: Codable, Equatable, Sendable {
    struct Change: Codable, Equatable, Sendable {
        var kind: String
        var id: String
        var minute: Int?
        var minutes: Int?
        var weekdays: [Int]?
    }

    var summary: String
    var changes: [Change]

    /// The reviewable plan this describes against the week as it is now, or
    /// nil when nothing in it still applies. Every change goes through the
    /// same check a model's plan does (`AIWirePlan.Change.resolved`).
    func plan(against brief: AIBrief, isModelWritten: Bool) -> SchedulePlan? {
        let resolved = changes.compactMap {
            AIWirePlan.Change(kind: $0.kind, id: $0.id, minute: $0.minute, minutes: $0.minutes, weekdays: $0.weekdays)
                .resolved(against: brief)
        }
        let trimmed = String(summary.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        guard !resolved.isEmpty, !trimmed.isEmpty else { return nil }
        return SchedulePlan(summary: trimmed, changes: resolved, isModelWritten: isModelWritten)
    }

    /// A plan the phone worked out, kept in the same shape. Only the three
    /// kinds a model may also propose survive; the phone's planner makes no
    /// others for a typed request.
    init?(_ plan: SchedulePlan) {
        let mapped: [Change] = plan.changes.compactMap { change -> Change? in
            switch change {
            case .time(let id, _, let minute, _):
                Change(kind: "time", id: id, minute: minute)
            case .duration(let id, _, let minutes, _):
                Change(kind: "duration", id: id, minutes: minutes)
            case .days(let id, _, let weekdays, _):
                Change(kind: "days", id: id, weekdays: weekdays.sorted())
            case .create, .adopt, .goal:
                nil
            }
        }
        guard !mapped.isEmpty else { return nil }
        self.init(summary: plan.summary, changes: mapped)
    }

    init(summary: String, changes: [Change]) {
        self.summary = summary
        self.changes = changes
    }

    /// One change that does not read costs that change, not the proposal:
    /// `plan(against:)` keeps whatever still resolves, and an unreadable
    /// change resolves to nothing (§17.7).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = (try? c.decodeIfPresent(String.self, forKey: .summary)) ?? ""
        changes = (try? c.decodeIfPresent(LossyList<Change>.self, forKey: .changes))?.elements ?? []
    }

    private enum CodingKeys: String, CodingKey { case summary, changes }
}

/// One turn as a request carries it.
struct CoachTurn: Encodable, Equatable, Sendable {
    /// "user" or "assistant" — the server's two roles. Anything else is
    /// dropped there.
    let role: String
    let text: String
}

/// Ask Forge's history: on this phone, the last forty lines, cleared in one
/// tap.
///
/// A versioned key in the App Group suite like every other preference. Never
/// synced and never sent whole: a request carries only the last eight
/// transmittable turns (`turns`), and the server keeps nothing (`store: false`
/// at OpenAI, no message text in any table or log).
@MainActor
@Observable
final class CoachHistory {
    static let key = "forge.askForge.v1"
    /// The most lines kept.
    static let limit = 40
    /// The most turns a request carries.
    static let turnLimit = 8
    /// The most of one message that is ever sent. The server cuts at the same.
    static let messageLimit = 600

    private let defaults: UserDefaults
    private(set) var messages: [CoachMessage]

    init(defaults: UserDefaults = ForgeShared.defaults) {
        self.defaults = defaults
        messages = Self.read(defaults)
    }

    func append(_ message: CoachMessage) {
        messages.append(message)
        if messages.count > Self.limit { messages.removeFirst(messages.count - Self.limit) }
        persist()
    }

    /// Marks a person's message as answered by a safety reply, so no later
    /// request carries it.
    func withhold(_ id: CoachMessage.ID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].isWithheld = true
        persist()
    }

    func clear() {
        messages = []
        defaults.removeObject(forKey: Self.key)
    }

    /// What the next request carries: the last eight lines that may be sent,
    /// oldest first, each cut to the message limit.
    var turns: [CoachTurn] { Self.turns(from: messages) }

    nonisolated static func turns(from messages: [CoachMessage]) -> [CoachTurn] {
        messages
            .filter(\.isTransmittable)
            .suffix(turnLimit)
            .map {
                CoachTurn(
                    role: $0.role == .user ? "user" : "assistant",
                    text: String($0.text.prefix(messageLimit))
                )
            }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// Tolerant, line by line: a line that does not read is dropped and the
    /// rest of the conversation kept. Anything that is not a list at all is an
    /// empty history, never a crash.
    nonisolated static func read(_ defaults: UserDefaults) -> [CoachMessage] {
        guard let data = defaults.data(forKey: key),
              let messages = try? JSONDecoder().decode(LossyList<CoachMessage>.self, from: data)
        else { return [] }
        return Array(messages.elements.suffix(limit))
    }
}

// MARK: - Safety, on the phone

/// What Ask Forge does before anything leaves the phone, and to what comes
/// back.
///
/// The server has the same screen and the model has the rules
/// (`supabase/functions/forge-ai/safety.ts`, `prompts.ts`). This half exists so
/// that **a message suggesting a crisis is answered on the phone, at once,
/// online or not, and is never sent** — and so the voice holds even if a reply
/// slips past the server's check.
enum CoachSafety {

    /// The 988 line, word for word the server's `LIFELINE_LINE`.
    static let lifelineLine =
        "Call or text 988 to reach the 988 Suicide & Crisis Lifeline, free and any time, in the US."

    /// The whole reply to a crisis message, word for word the server's
    /// `CRISIS_REPLY`. One caring line and the lifeline; no coaching.
    static let crisisReply =
        "That sounds like a lot to carry, and you don't have to carry it alone. \(lifelineLine)"

    static let callURL = URL(string: "tel:988")!
    static let textURL = URL(string: "sms:988")!

    /// The server's crisis patterns, the same in both places
    /// (`AskForgeTests.crisisScreenMatchesTheServer` reads both lists).
    static let crisisPatterns: [String] = [
        #"\b(kill|killing|hurt|hurting|harm|harming|cut|cutting|burn|burning)\s+(myself|yourself)\b"#,
        #"\bsuicid"#,
        #"\bself[\s-]?harm"#,
        #"\bend(ing)?\s+(my\s+life|it\s+all)\b"#,
        #"\btake\s+my\s+(own\s+)?life\b"#,
        #"\b(want|wanna|going|ready)\s+(to\s+)?die\b"#,
        #"\b(don'?t|do\s+not)\s+want\s+to\s+(live|be\s+alive|be\s+here|exist|wake\s+up)\b"#,
        #"\bno\s+(reason|point)\s+(to|in)\s+(live|living|go\s+on|going\s+on)\b"#,
        #"\bnot\s+worth\s+living\b"#,
        #"\bbetter\s+off\s+(dead|without\s+me)\b"#,
        #"\boverdos(e|ed|ing)\b"#,
    ]

    private static let crisis: [NSRegularExpression] = crisisPatterns.compactMap {
        try? NSRegularExpression(pattern: $0)
    }

    /// Lower case, straight apostrophes, single spaces — the server's
    /// `normalise`.
    static func normalised(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "[\u{2018}\u{2019}\u{02BC}]", with: "'", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Whether a message suggests self-harm or a crisis.
    static func suggestsCrisis(_ text: String) -> Bool {
        let line = normalised(text)
        let range = NSRange(line.startIndex..., in: line)
        return crisis.contains { $0.firstMatch(in: line, range: range) != nil }
    }

    /// Whether a reply carries the 988 line, so the screen offers Call and
    /// Text under it.
    static func mentionsLifeline(_ text: String) -> Bool {
        text.range(of: #"\b988\b"#, options: .regularExpression) != nil
    }

    /// Forge's voice, held on the phone too: no exclamation marks, no emoji.
    static func inVoice(_ text: String) -> String {
        var cleaned = String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            !(scalar.properties.isEmojiPresentation
                || (scalar.properties.isEmoji && scalar.value > 0x238C)
                || scalar.value == 0xFE0F || scalar.value == 0x200D)
        }))
        cleaned = cleaned.replacingOccurrences(of: #"([?.])!+"#, with: "$1", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "!+", with: ".", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - The words on the screen

enum AskForgeCopy {
    static let title = "Ask Forge"
    /// Under the title, always.
    static let disclaimer = "Not medical advice"
    /// Offline, 402, 429, 5xx: one plain line, whatever the cause.
    static let unreachable = "Ask Forge can't reach the server right now. Your record is fine."
    static let local = "Worked out on this phone from the week you already keep. Nothing was sent."
    static let declined = "Nothing was sent. Ask Forge needs your allowance to send a question to Forge's server."
    static let intro = "Ask about your week, your six stats or your Arc. Answers are written by Forge's AI from your record, and can be wrong."
    static let modelLabel = "Written by Forge's AI"
}

// MARK: - Three ways to start, from the record

/// Three starters built from somebody's own record: a dimension that is
/// slipping (or the weakest), the Arc, and the day or the week.
///
/// Built, never invented: a dimension is named "slipping" only when its score
/// fell over the last seven days (§5 #3: nothing manufactures a problem), and
/// the Arc's starter names a week that exists.
enum CoachStarters {
    static func make(_ coach: CoachBrief, topic: CoachTopic) -> [String] {
        let dimension = dimensionStarter(coach)
        let arc = arcStarter(coach)
        let week = weekStarter(coach)
        let ordered: [String?]
        switch topic {
        case .general: ordered = [dimension, arc, week]
        case .arc: ordered = [arc, phaseStarter(coach), dimension, week]
        }
        var seen = Set<String>()
        return ordered.compactMap { $0 }.filter { seen.insert($0).inserted }.prefix(3).map { $0 }
    }

    /// "Why is Discipline slipping?" for the dimension that fell furthest this
    /// week; otherwise the weakest scored one.
    static func dimensionStarter(_ coach: CoachBrief) -> String? {
        let fell = coach.scores
            .compactMap { score in score.weekChange.map { (score.category, $0) } }
            .filter { $0.1 < 0 }
            .min { $0.1 < $1.1 }
        if let fell { return "Why is \(fell.0.label) slipping?" }
        let weakest = coach.scores
            .compactMap { score in score.score.map { (score.category, $0) } }
            .min { $0.1 < $1.1 }
        if let weakest { return "How do I raise \(weakest.0.label)?" }
        return "Which of the six should I build first?"
    }

    /// "Make week 3 harder" while an Arc runs and has a week left after this
    /// one; otherwise about the Arc's end, or which Arc fits.
    static func arcStarter(_ coach: CoachBrief) -> String {
        guard let arc = coach.arc else { return "Which Arc fits my week?" }
        if arc.week < arc.weeks { return "Make week \(arc.week + 1) harder" }
        return "What should the last days of \(arc.name) look like?"
    }

    static func phaseStarter(_ coach: CoachBrief) -> String? {
        guard let arc = coach.arc else { return nil }
        return "What is the \(arc.phase) phase asking of me?"
    }

    /// The day or the week: an activity with no hour first, then what is left
    /// today, then evenings around work.
    static func weekStarter(_ coach: CoachBrief) -> String {
        if let untimed = coach.brief.activities.first(where: { $0.startMinute == nil }) {
            return "Give \(untimed.name) a time that sticks"
        }
        if coach.today.contains(where: { !$0.isDone }) {
            return "What's left today, in what order?"
        }
        return "Fit my evenings around work until 18:00"
    }
}

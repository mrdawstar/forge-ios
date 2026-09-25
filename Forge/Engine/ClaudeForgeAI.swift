import Foundation

/// The real model, reached the only way an iOS app may reach one.
///
/// # Why there is no API key in this file
///
/// An API key shipped in an iOS binary is an extracted API key. Not "at risk of
/// being extracted" — extracted, by anybody with a copy of the app and twenty
/// minutes, because the binary is on their device and the key is a string inside
/// it. Obfuscating it, splitting it across constants, fetching it at launch and
/// holding it in memory: all of these change how long the twenty minutes takes
/// and none of them change the outcome. The first person to find it can spend
/// Forge's money at their own leisure until somebody notices the bill.
///
/// So every request in this file goes to **Forge's own backend** — a Supabase
/// edge function at `functions/v1/forge-ai`, see `supabase/functions/forge-ai` —
/// which holds the key as a server secret, checks that the caller is signed in
/// and entitled, and talks to Anthropic on the app's behalf. The app never sees
/// a model endpoint, never holds a model key, and cannot be made to leak one.
/// That the function also becomes the one place to add rate limiting, a spend
/// cap and an audit log is the second reason, and it would be sufficient on its
/// own.
///
/// # Why `LocalForgeAI` is still here
///
/// Every method below falls back to it. A phone in a tunnel, an account that is
/// not signed in, a backend that is down, a model that answers with something
/// that does not survive validation — all of them land on the arithmetic, which
/// is genuinely useful and always available. **The fallback is never disguised.**
/// `SchedulePlan.isModelWritten` and `PracticeReading.isModelWritten` come back
/// false, and every screen that shows either of them says which it got.
struct ClaudeForgeAI: ForgeAI {

    /// **Whether this release may talk to a model at all. It may not.**
    ///
    /// # Why this is a constant and not a setting
    ///
    /// 1.0 sends nothing anywhere for any AI feature, and that has to be a fact
    /// about the binary rather than a state it can be talked into. A toggle —
    /// in Settings, in a config file, behind an entitlement — is a thing that
    /// can be flipped by a bug, a stale default, a merge or a sync, and the
    /// failure mode of every one of those is somebody's own sentences about
    /// themselves leaving their phone when the product promised they would not.
    /// A `let` that is `false` cannot be flipped by anything except a person
    /// editing this line.
    ///
    /// # Why the switch is here and not at the call site
    ///
    /// Because it protects **every** construction of this type, including one
    /// written next year by somebody who has not read this file. `ContentView`
    /// is where the app is wired together and it would have been the natural
    /// place; it is also a place where a second `ClaudeForgeAI` could appear
    /// without anybody noticing the flag was not copied.
    ///
    /// # What it does, mechanically
    ///
    /// It forces `endpoint` to nil. There is then no object in the process
    /// capable of forming a request: `AIEndpoint` is the only type that builds
    /// one, it is the only thing holding an `HTTPClient` on this path, and every
    /// method below opens with `guard let endpoint` and falls to
    /// `LocalForgeAI`. Because Swift stops at the first failing condition in a
    /// `guard`, the `await token()` beside it is never evaluated either — so
    /// this also stops the session refresh that asking for a token can trigger.
    ///
    /// # Turning it back on
    ///
    /// Change `false` to `true`. Nothing else — not one line of UI, not one
    /// screen, not one string. `isConnected` starts returning true, the
    /// disclosure screen and the Settings footer swap to their connected
    /// wording on their own, `Plan`'s free-text field starts reaching the
    /// model, and the weekly review starts asking for a written reading. The
    /// whole seam is intact behind this Bool; see `AIWireBrief`,
    /// `AIWirePlan.resolved(against:)` and
    /// `ReviewObservation.validate(_:against:)`, none of which was deleted.
    ///
    /// Before flipping it: the edge function has to be deployed, migration
    /// `0007_ai_usage.sql` applied, and `APP_STORE.md` §1 changed back — the
    /// privacy nutrition labels currently say Forge collects nothing for this,
    /// and that answer is only true while this is `false`.
    static let isModelEnabled = false

    /// Nil in a build with no Supabase project configured — and nil in **every**
    /// build of 1.0, see `isModelEnabled`. Either way this whole type is then a
    /// passthrough to the arithmetic.
    private let endpoint: AIEndpoint?

    /// A token for the signed-in account, or nil for somebody who is not.
    ///
    /// A closure rather than a reference to `AuthService`, for the reason the
    /// whole `ForgeAI` protocol exists: this file must not know what an auth
    /// service is, and the day somebody swaps the backend it must not need to.
    ///
    /// It is never called while `isModelEnabled` is false. See the note above.
    private let token: @Sendable () async -> String?

    /// What answers when the model cannot. Not a stub — see `LocalForgeAI`.
    ///
    /// In 1.0 it answers *everything*, and `Plan`'s own suggestions do not come
    /// through here at all — `DayPlanner` computes those from the record before
    /// this type is consulted. What is left for this path is the free-text
    /// field, which `LocalForgeAI` genuinely answers for stated work hours,
    /// frequencies, whole-week shifts and moving one activity, and refuses
    /// honestly for anything wider.
    private let fallback = LocalForgeAI()

    var isConnected: Bool { endpoint != nil }

    init(config: SupabaseConfig?, token: @escaping @Sendable () async -> String?) {
        self.endpoint = Self.isModelEnabled ? config.map(AIEndpoint.init) : nil
        self.token = token
    }

    // MARK: - Challenges

    /// A challenge written for this person, or the catalogue's nearest one.
    ///
    /// The fallback here is unusually good — sixty hand-written challenges
    /// filtered by aim and weight — so the bar for using the model's answer is
    /// simply that it came back and was not empty. There is no claim about the
    /// user in a challenge, so there is nothing to check it against.
    func challenge(
        brief: AIBrief,
        difficulty: ChallengeDifficulty,
        focus: ChallengeFocus,
        wish: String
    ) async throws -> DailyChallenge {
        guard let endpoint, let token = await token() else {
            return try await fallback.challenge(
                brief: brief, difficulty: difficulty, focus: focus, wish: wish
            )
        }
        do {
            let written = try await endpoint.challenge(
                AIRequest(
                    task: .challenge,
                    brief: AIWireBrief(brief),
                    request: wish,
                    difficulty: difficulty.rawValue,
                    focus: focus.rawValue
                ),
                token: token
            )
            guard let made = written.challenge(focus: focus, difficulty: difficulty) else {
                throw ForgeAIError.failed
            }
            return made
        } catch {
            return try await fallback.challenge(
                brief: brief, difficulty: difficulty, focus: focus, wish: wish
            )
        }
    }

    // MARK: - Planning

    /// A week, proposed.
    ///
    /// Everything the model sends back is checked against the brief before it
    /// becomes a change: an edit naming an activity that does not exist is
    /// dropped, a clock time outside a day is dropped, a weekday outside one to
    /// seven is dropped. This is the same doctrine as the reading's validator
    /// and for a smaller version of the same reason — a plan that invents a row
    /// would be applied against an id nothing owns.
    func plan(brief: AIBrief, request: String) async throws -> SchedulePlan {
        guard !brief.isEmpty else { throw ForgeAIError.nothingToPlan }
        guard let endpoint, let token = await token() else {
            return try await fallback.plan(brief: brief, request: request)
        }
        do {
            let written = try await endpoint.plan(
                AIRequest(task: .plan, brief: AIWireBrief(brief), request: request),
                token: token
            )
            let changes = written.changes.compactMap { $0.resolved(against: brief) }
            guard !changes.isEmpty, !written.summary.isEmpty else {
                throw ForgeAIError.noChange
            }
            return SchedulePlan(
                summary: written.summary, changes: changes, isModelWritten: true
            )
        } catch {
            return try await fallback.plan(brief: brief, request: request)
        }
    }

    // MARK: - Reading the record back

    /// One true sentence about a week, checked before it is believed.
    ///
    /// The order here is the whole design. The model answers, and then
    /// `ReviewObservation.validate(_:against:)` decides whether what it said is
    /// a description of the week in `brief.week` — and if it is not, the phone's
    /// own sentence is used and nobody is told anything happened. A model that
    /// hallucinates a plan wastes somebody's afternoon; a model that
    /// hallucinates a reading tells them something false about their own life,
    /// which they cannot check and have every reason to believe.
    func reading(brief: AIBrief) async throws -> PracticeReading {
        guard let facts = brief.week else { throw ForgeAIError.nothingToRead }
        guard let endpoint, let token = await token() else {
            return try await fallback.reading(brief: brief)
        }
        do {
            let written = try await endpoint.reading(
                AIRequest(task: .reading, brief: AIWireBrief(brief)),
                token: token
            )
            guard let checked = ReviewObservation.validate(written.observation, against: facts)
            else { throw ForgeAIError.unverifiable }
            return PracticeReading(observation: checked, isModelWritten: true)
        } catch {
            return try await fallback.reading(brief: brief)
        }
    }

}

// MARK: - The wire

/// Everything that actually crosses the network, and nothing else.
///
/// Split from `ClaudeForgeAI` so the thing above can be read as product logic —
/// what is asked, what is checked, what is fallen back to — without HTTP in the
/// middle of it, and so the shapes below sit next to each other where the edge
/// function's own types can be compared against them by eye.
struct AIEndpoint: Sendable {

    let config: SupabaseConfig
    let client: HTTPClient

    init(config: SupabaseConfig) {
        self.config = config
        self.client = HTTPClient(config: config)
    }

    /// `https://<project>.supabase.co/functions/v1/forge-ai`.
    var url: URL { config.url.appendingPathComponent("functions/v1/forge-ai") }

    func challenge(_ request: AIRequest, token: String) async throws -> AIWireChallenge {
        try await send(AIWireChallenge.self, request, token: token)
    }

    func plan(_ request: AIRequest, token: String) async throws -> AIWirePlan {
        try await send(AIWirePlan.self, request, token: token)
    }

    func reading(_ request: AIRequest, token: String) async throws -> AIWireReading {
        try await send(AIWireReading.self, request, token: token)
    }

    private func send<T: Decodable>(
        _ type: T.Type, _ request: AIRequest, token: String
    ) async throws -> T {
        guard let body = try? JSONEncoder().encode(request) else {
            throw ForgeAIError.failed
        }
        return try await client.send(
            type, .post, url: url, body: body, accessToken: token
        )
    }
}

/// What Forge posts. One shape for all four tasks, because four request types
/// for one endpoint is four places to add a field and three places to forget.
struct AIRequest: Encodable, Sendable {
    enum Task: String, Encodable, Sendable {
        case challenge, plan, reading
    }

    let task: Task
    let brief: AIWireBrief
    var request: String = ""
    var difficulty: String?
    var focus: String?
}

/// `AIBrief`, flattened for JSON.
///
/// A separate type rather than `Codable` on `AIBrief` itself, and the separation
/// is doing real work: `AIBrief` is the *record* of what may leave the phone and
/// it is read by a screen, and this is the *encoding* of it. A field added to
/// the first and not to the second sends nothing; a field added to the second
/// and not to the first cannot exist, because there is nowhere to read it from.
struct AIWireBrief: Encodable, Sendable {

    struct Activity: Encodable, Sendable {
        let id: String
        let name: String
        let startMinute: Int?
        let minutes: Int
        let weekdays: [Int]
        let identity: String?
    }

    struct Week: Encodable, Sendable {
        struct Weekday: Encodable, Sendable {
            let name: String
            let kept: Int
            let asked: Int
        }
        struct Habit: Encodable, Sendable {
            let name: String
            let planned: Int
            let completed: Int
        }
        struct Identity: Encodable, Sendable {
            let statement: String
            let days: Int
            let asked: Int
        }

        let kept: Int
        let asked: Int
        let windowWeeks: Int
        let weekdays: [Weekday]
        let habits: [Habit]
        let identities: [Identity]
    }

    let daysKept: Int
    let streak: Int
    let world: String?
    let activities: [Activity]
    let parts: [String]
    let wakeMinutes: Int?
    let identities: [String]
    let chapterIntention: String
    let week: Week?

    init(_ brief: AIBrief) {
        daysKept = brief.daysKept
        streak = brief.streak
        world = brief.world
        parts = brief.parts
        wakeMinutes = brief.wakeMinutes
        identities = brief.identities
        chapterIntention = brief.chapterIntention
        activities = brief.activities.map {
            Activity(
                id: $0.id,
                name: $0.name,
                startMinute: $0.startMinute,
                minutes: $0.minutes,
                // Sorted so two identical weeks encode identically. An
                // unordered `Set` would produce a different body each launch,
                // which makes a request log unreadable and a cache impossible.
                weekdays: $0.weekdays.sorted(),
                // The statement, never the id — an id means nothing off this
                // device and would only ever be a join key for somebody else.
                identity: nil
            )
        }
        week = brief.week.map { facts in
            let symbols = Calendar.current.weekdaySymbols
            return Week(
                kept: facts.kept,
                asked: facts.asked,
                windowWeeks: facts.windowWeeks,
                weekdays: facts.weekdays.map {
                    Week.Weekday(
                        name: symbols.indices.contains($0.weekday - 1)
                            ? symbols[$0.weekday - 1] : "Day \($0.weekday)",
                        kept: $0.kept,
                        asked: $0.asked
                    )
                },
                habits: facts.habits.map {
                    Week.Habit(name: $0.name, planned: $0.planned, completed: $0.completed)
                },
                identities: facts.identities.map {
                    Week.Identity(statement: $0.statement, days: $0.days, asked: $0.asked)
                }
            )
        }
    }
}

// MARK: - What comes back

/// Hand-written and tolerant, the same as every other decoder in this codebase:
/// a missing field is a missing field rather than a thrown error that loses the
/// whole answer. The edge function constrains the model to this shape with a
/// JSON schema, so a field arriving absent means something has gone wrong on the
/// far side — and the right response to that is to use what did arrive, or fall
/// back, not to crash a review screen.
struct AIWireChallenge: Decodable, Sendable {
    var title: String = ""
    var detail: String = ""

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
    }

    private enum CodingKeys: String, CodingKey { case title, detail }

    /// Nil when there is not enough here to show somebody.
    func challenge(focus: ChallengeFocus, difficulty: ChallengeDifficulty) -> DailyChallenge? {
        let title = String(self.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(70))
        let detail = String(self.detail.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        guard !title.isEmpty, !detail.isEmpty else { return nil }
        return DailyChallenge(
            id: "model.\(UUID().uuidString.prefix(8))",
            title: title,
            detail: detail,
            focus: focus,
            difficulty: difficulty,
            isPersonal: true
        )
    }
}

struct AIWireReading: Decodable, Sendable {
    var observation: String = ""

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        observation = try c.decodeIfPresent(String.self, forKey: .observation) ?? ""
    }

    private enum CodingKeys: String, CodingKey { case observation }
}

struct AIWirePlan: Decodable, Sendable {
    var summary: String = ""
    var changes: [Change] = []

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = String(
            (try c.decodeIfPresent(String.self, forKey: .summary) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)
        )
        changes = try c.decodeIfPresent([Change].self, forKey: .changes) ?? []
    }

    private enum CodingKeys: String, CodingKey { case summary, changes }

    /// One proposed edit, still untrusted.
    struct Change: Decodable, Sendable {
        var kind: String = ""
        var id: String = ""
        var minute: Int?
        var minutes: Int?
        var weekdays: [Int]?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
            id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
            minute = try c.decodeIfPresent(Int.self, forKey: .minute)
            minutes = try c.decodeIfPresent(Int.self, forKey: .minutes)
            weekdays = try c.decodeIfPresent([Int].self, forKey: .weekdays)
        }

        private enum CodingKeys: String, CodingKey { case kind, id, minute, minutes, weekdays }

        /// The change this describes, or nil when it describes nothing real.
        ///
        /// **Every edit must name an activity that exists in the brief.** The
        /// model is only ever shown the user's own week and is only ever asked
        /// to rearrange it, so an id that is not in the brief is either a
        /// misquote or an invention, and both produce a row that `projected`
        /// silently drops and `apply` would write against nothing. Rejecting it
        /// here means a plan is either wholly applicable or is not offered.
        func resolved(against brief: AIBrief) -> ScheduleChange? {
            guard let activity = brief.activities.first(where: { $0.id == id }) else { return nil }
            switch kind {
            case "time":
                guard let minute, (0..<(24 * 60)).contains(minute), minute != activity.startMinute
                else { return nil }
                return .time(
                    id: activity.id, name: activity.name,
                    minute: minute, was: activity.startMinute
                )

            case "duration":
                guard let minutes, (1...(8 * 60)).contains(minutes), minutes != activity.minutes
                else { return nil }
                return .duration(
                    id: activity.id, name: activity.name,
                    minutes: minutes, was: activity.minutes
                )

            case "days":
                let days = Set((weekdays ?? []).filter { (1...7).contains($0) })
                guard !days.isEmpty, days != activity.weekdays else { return nil }
                return .days(
                    id: activity.id, name: activity.name,
                    weekdays: days, was: activity.weekdays
                )

            default:
                // No `.create`. A model may rearrange what somebody keeps and
                // may not add to it: an activity nobody chose, appearing in a
                // routine somebody built by hand, is the app deciding what their
                // day is for. The case stays in `ScheduleChange` because the
                // arithmetic uses it; nothing from the network reaches it.
                return nil
            }
        }
    }
}


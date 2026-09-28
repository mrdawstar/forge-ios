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
/// which holds `OPENAI_API_KEY` as a server secret and talks to OpenAI on the
/// app's behalf. The app never sees a model endpoint, never holds a model key,
/// and cannot be made to leak one. That the function also becomes the one place
/// to check entitlement and cap spend is the second reason, and it would be
/// sufficient on its own.
///
/// # Who the request is from, with no account
///
/// Forge has no visible account (`FORGE_CONTEXT.md` §2n) and this does not add
/// one. Every request carries two things, and neither is anything a person
/// types, sees or manages:
///
/// - **A Supabase JWT for an anonymous user** (`AnonymousIdentity`) — a random
///   id with no name, email or password, created silently the first time a
///   Premium feature reaches the model. The function requires it.
/// - **The signed StoreKit 2 transaction** for the current Premium purchase, in
///   `X-Forge-Transaction` (`ForgeStore.entitlementProof`). The function
///   verifies it offline against Apple's root certificate and keys its spend
///   cap on the purchase, so one purchase cannot power unlimited identities.
///
/// # The order a request is allowed to happen in
///
/// `connect()` checks four things and stops at the first that fails, so the
/// later ones never run:
///
/// 1. **The switch** — `isModelEnabled`. Off in this build (§2r).
/// 2. **Consent** — `AIConsentStore`. Nobody's words leave the phone until they
///    have read the disclosure and pressed Allow.
/// 3. **The purchase** — the StoreKit JWS. Somebody without Forge Pro never
///    has an anonymous identity created for them.
/// 4. **The identity** — only now is the anonymous session read, minted or
///    refreshed.
///
/// And all four only when a request is actually being made — a button was
/// pressed. Nothing here runs at launch, on opening Settings, or on opening a
/// weekly review (`FORGE_CONTEXT.md` §2q, §2r).
///
/// # The two jobs
///
/// `reading` and `plan`, and nothing else. It is not a chat: there is no
/// conversation and no free-form answer, only the shapes below, each checked on
/// this phone before it is shown.
///
/// # Why `LocalForgeAI` is still here
///
/// Every method below falls back to it. A phone in a tunnel, an account that is
/// not signed in, a backend that is down, a model that answers with something
/// that does not survive validation — all of them land on the arithmetic, which
/// is genuinely useful and always available. **The fallback is never disguised.**
/// `SchedulePlan.isModelWritten` and `PracticeReading.isModelWritten` come back
/// false, and every screen that shows either of them says which it got.
struct RemoteForgeAI: ForgeAI {

    /// **Whether this release may talk to a model at all. It may not.**
    ///
    /// # Why this is a constant and not a setting
    ///
    /// Until activation (§2r) Forge sends nothing anywhere for any AI feature —
    /// remote AI is prepared, not on — and that has to be a fact
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
    /// place; it is also a place where a second `RemoteForgeAI` could appear
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
    /// Before flipping it: follow `supabase/README.md` (anonymous sign-ins on,
    /// migrations through `0008`, `OPENAI_API_KEY` set, `forge-ai` deployed),
    /// put the project in `Info.plist`, and switch `APP_STORE.md` §1 to its
    /// prepared "once AI is activated" labels. The whole checklist is
    /// `FORGE_CONTEXT.md` §2r, "Activation".
    ///
    /// **Still `false` after §2r.** The consent screen, the entitlement proof,
    /// the Weekly Reading flow and the tests are all in place; this line is the
    /// one thing the activation PR changes.
    static let isModelEnabled = false

    /// Nil in a build with no Supabase project configured — and nil in **every**
    /// build of 1.0, see `isModelEnabled`. Either way this whole type is then a
    /// passthrough to the arithmetic.
    private let endpoint: AIEndpoint?

    /// A JWT for the invisible anonymous identity, or nil when one cannot be
    /// had (no project, offline, anonymous sign-ins off on the server).
    ///
    /// A closure rather than a reference to `AnonymousIdentity`, for the reason
    /// the whole `ForgeAI` protocol exists: this file must not know what an
    /// auth service is, and the day somebody swaps the backend it must not
    /// need to.
    ///
    /// It is never called while `isModelEnabled` is false, and never called
    /// without a proof of purchase in hand. See the notes above.
    private let token: @Sendable () async -> String?

    /// `Transaction.jwsRepresentation` for the current Premium entitlement, or
    /// nil for somebody without one. See `ForgeStore.entitlementProof`.
    private let entitlement: @Sendable () async -> String?

    /// Whether the person has pressed Allow on the disclosure. Read before the
    /// purchase and before the identity. See `AIConsentStore`.
    private let consent: @Sendable () async -> Bool

    /// Told when a model answered and its reading did not survive
    /// `ReviewObservation.validate` — the `reading_fell_back` signal. Never
    /// handed the text: telemetry carries no generated or user-written words.
    private let onReadingFallback: @Sendable () -> Void

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

    init(
        config: SupabaseConfig?,
        token: @escaping @Sendable () async -> String?,
        entitlement: @escaping @Sendable () async -> String?,
        consent: @escaping @Sendable () async -> Bool = { AIConsentStore.isAllowed() },
        onReadingFallback: @escaping @Sendable () -> Void = { ForgeTelemetry.send(.readingFellBack) }
    ) {
        self.endpoint = Self.isModelEnabled ? config.map { AIEndpoint(config: $0) } : nil
        self.token = token
        self.entitlement = entitlement
        self.consent = consent
        self.onReadingFallback = onReadingFallback
    }

    #if DEBUG
    /// **Tests only, and never compiled into a release build.** The path the
    /// activation PR will switch on, run against a scripted endpoint so the
    /// order of checks and the shape of the request can be held by tests while
    /// `isModelEnabled` is still false. No real network: the endpoint's client
    /// is whatever transport the test hands it.
    init(
        testingEndpoint: AIEndpoint,
        token: @escaping @Sendable () async -> String?,
        entitlement: @escaping @Sendable () async -> String?,
        consent: @escaping @Sendable () async -> Bool,
        onReadingFallback: @escaping @Sendable () -> Void = {}
    ) {
        self.endpoint = testingEndpoint
        self.token = token
        self.entitlement = entitlement
        self.consent = consent
        self.onReadingFallback = onReadingFallback
    }
    #endif

    /// Everything a request needs, in the order that matters: the switch,
    /// consent, the purchase, then the identity. Nil means "answer locally",
    /// and the caller does not care why.
    ///
    /// `guard` stops at the first failing condition: with no endpoint nothing
    /// runs; without consent the purchase is not even read; without a purchase
    /// no identity is created.
    private func connect() async -> Connection? {
        guard let endpoint,
              await consent(),
              let transaction = await entitlement(),
              let token = await token()
        else { return nil }
        return Connection(
            endpoint: endpoint,
            credentials: AICredentials(token: token, transaction: transaction)
        )
    }

    private struct Connection {
        let endpoint: AIEndpoint
        let credentials: AICredentials
    }

    // MARK: - Challenges

    /// The catalogue's nearest challenge — sixty hand-written ones, filtered by
    /// aim and weight. The model does not write challenges; this stays on the
    /// protocol as the seam it has always been.
    func challenge(
        brief: AIBrief,
        difficulty: ChallengeDifficulty,
        focus: ChallengeFocus,
        wish: String
    ) async throws -> DailyChallenge {
        // Always the catalogue. The model's challenge job was retired with the
        // generator (§2j.3) and the backend no longer serves it: the two jobs a
        // model does for Forge are the reading and the plan.
        try await fallback.challenge(
            brief: brief, difficulty: difficulty, focus: focus, wish: wish
        )
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
        guard let call = await connect() else {
            return try await fallback.plan(brief: brief, request: request)
        }
        do {
            let written = try await call.endpoint.plan(
                AIRequest(task: .plan, brief: AIWireBrief(brief), request: request),
                credentials: call.credentials
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
        guard let call = await connect() else {
            return try await fallback.reading(brief: brief)
        }
        do {
            let written = try await call.endpoint.reading(
                AIRequest(task: .reading, brief: AIWireBrief(brief)),
                credentials: call.credentials
            )
            guard let checked = ReviewObservation.validate(written.observation, against: facts)
            else {
                // A model answered and was wrong about the week. Counted — the
                // count, never the words — and the phone's sentence stands.
                onReadingFallback()
                throw ForgeAIError.unverifiable
            }
            return PracticeReading(observation: checked, isModelWritten: true)
        } catch {
            return try await fallback.reading(brief: brief)
        }
    }

}

// MARK: - The wire

/// Everything that actually crosses the network, and nothing else.
///
/// Split from `RemoteForgeAI` so the thing above can be read as product logic —
/// what is asked, what is checked, what is fallen back to — without HTTP in the
/// middle of it, and so the shapes below sit next to each other where the edge
/// function's own types can be compared against them by eye.
struct AIEndpoint: Sendable {

    let config: SupabaseConfig
    let client: HTTPClient

    init(config: SupabaseConfig) {
        self.init(config: config, client: HTTPClient(config: config))
    }

    /// A client handed in whole — the tests' way of seeing the request
    /// without a network.
    init(config: SupabaseConfig, client: HTTPClient) {
        self.config = config
        self.client = client
    }

    /// `https://<project>.supabase.co/functions/v1/forge-ai`.
    var url: URL { config.url.appendingPathComponent("functions/v1/forge-ai") }

    /// The header the function reads the StoreKit transaction from.
    static let transactionHeader = "X-Forge-Transaction"

    func plan(_ request: AIRequest, credentials: AICredentials) async throws -> AIWirePlan {
        try await send(AIWirePlan.self, request, credentials: credentials)
    }

    func reading(_ request: AIRequest, credentials: AICredentials) async throws -> AIWireReading {
        try await send(AIWireReading.self, request, credentials: credentials)
    }

    private func send<T: Decodable>(
        _ type: T.Type, _ request: AIRequest, credentials: AICredentials
    ) async throws -> T {
        guard let body = try? JSONEncoder().encode(request) else {
            throw ForgeAIError.failed
        }
        return try await client.send(
            type, .post, url: url, body: body,
            headers: [Self.transactionHeader: credentials.transaction],
            accessToken: credentials.token
        )
    }
}

/// What a model request is sent under: the anonymous identity's JWT and the
/// signed StoreKit transaction. Neither names a person.
struct AICredentials: Sendable {
    let token: String
    let transaction: String
}

/// What Forge posts. One shape for both tasks, because a request type per task
/// for one endpoint is a place per task to add a field and forget one.
///
/// Carries nothing that says who is asking or what they bought — those travel
/// as the JWT and `X-Forge-Transaction`, and the function reads them from
/// there alone.
struct AIRequest: Encodable, Sendable {
    enum Task: String, Encodable, Sendable {
        case plan, reading
    }

    let task: Task
    let brief: AIWireBrief
    var request: String = ""
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


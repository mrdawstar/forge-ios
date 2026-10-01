import Foundation
import Testing
@testable import Forge

/// §2r — AI prepared, activation pending.
///
/// Everything the activation PR will switch on is held here **without a
/// network**: the AI path runs against `ScriptedTransport`, the anonymous
/// identity against a scripted auth endpoint and an in-memory session store,
/// and the production path — the one the app actually builds — is checked to
/// be off. No test in this file can reach OpenAI or a Supabase project.

// MARK: - Consent

@MainActor
@Suite("AI consent")
struct AIConsentTests {

    private func suite() -> UserDefaults {
        UserDefaults(suiteName: "forge.aiconsent.\(UUID().uuidString)") ?? .standard
    }

    @Test("Nobody has consented until they press Allow")
    func startsUndecided() {
        let defaults = suite()
        let consent = AIConsentStore(defaults: defaults)
        #expect(consent.state == .undecided)
        #expect(!consent.isAllowed)
        #expect(!AIConsentStore.isAllowed(in: defaults))
    }

    @Test("Allow is remembered in the suite, for the request path to read")
    func allowPersists() {
        let defaults = suite()
        AIConsentStore(defaults: defaults).allow()
        #expect(AIConsentStore(defaults: defaults).isAllowed)
        #expect(AIConsentStore.isAllowed(in: defaults))
        #expect(ForgeShared.ownedKeys.contains(AIConsentStore.key))
    }

    @Test("Not now is a decision, and it is not a yes")
    func notNowDeclines() {
        let defaults = suite()
        let consent = AIConsentStore(defaults: defaults)
        consent.decline()
        #expect(consent.state == .declined)
        #expect(consent.hasDecided)
        #expect(!AIConsentStore.isAllowed(in: defaults))
    }

    @Test("Consent can be revoked, and the revocation outlives the process")
    func revocable() {
        let defaults = suite()
        let consent = AIConsentStore(defaults: defaults)
        consent.allow()
        consent.revoke()
        #expect(!consent.isAllowed)
        #expect(AIConsentStore(defaults: defaults).state == .declined)
        #expect(!AIConsentStore.isAllowed(in: defaults))
    }

    /// The five things somebody must be told before a first request, each held
    /// so none can be edited out of the disclosure without a test failing.
    @Test("The disclosure says what, where, who processes it, whose words, and what it is not for")
    func disclosureCoversTheFivePoints() {
        let all = AIDisclosureView.explanations.joined(separator: " ")
        #expect(AIDisclosureView.explanations.count == 5)
        #expect(all.contains("What is sent"))
        #expect(all.contains("Forge's own backend"))
        #expect(all.contains("OpenAI"))
        #expect(all.contains("Your own words"))
        #expect(all.contains("advertising or tracking"))
        // OpenAI behind Forge's backend, and nobody else's name.
        for gone in ["Anthropic", "Claude", "ANTHROPIC_API_KEY"] {
            #expect(!all.contains(gone), Comment(rawValue: gone))
        }
        #expect(AIDisclosureView.label(for: .undecided) == "Not asked yet")
        #expect(AIDisclosureView.label(for: .declined) == "Off")
    }
}

// MARK: - The sentence every plan request sends

/// A sentence the phone answers on its own: `LocalForgeAI` moves one activity
/// to another day. So wherever a test below expects the phone to answer, it
/// really does, with a plan of its own.
///
/// It was "Move read to 7" — a time, which the phone refuses by design: it
/// moves an activity to a day, lays out hours, spreads a frequency and shifts
/// the whole week, and says so in `ForgeAIError.notConnected`. Every test that
/// fell back threw `.notConnected` before reaching its own assertions.
private let movesReadToWednesday = "Move read to Wednesday"

/// The phone's answer to it: Read, every day until now, on Wednesdays.
private let readOnWednesdays = ScheduleChange.days(id: "read", name: "Read", weekdays: [4], was: [])

// MARK: - Still off

@Suite("AI prepared, still switched off")
struct AIStillOffTests {

    private let configured = SupabaseConfig(
        url: URL(string: "https://example.supabase.co")!,
        anonKey: "sb_publishable_test"
    )

    @Test("The remote model is disabled in this build")
    func disabled() {
        #expect(RemoteForgeAI.isModelEnabled == false)
        #expect(!RemoteForgeAI(config: configured, token: { "t" }, entitlement: { "j" }, consent: { true }).isConnected)
    }

    /// Consent given, Pro owned, a project configured: still nothing, because
    /// the switch is read first. Not one of the three closures is called.
    @Test("With consent and Pro, a disabled build still asks for nothing and sends nothing")
    func nothingEvenWithEverything() async throws {
        let calls = AICallCounter()
        let ai = RemoteForgeAI(
            config: configured,
            token: { await calls.token() },
            entitlement: { await calls.entitlement(); return "j" },
            consent: { await calls.consent() }
        )
        var brief = AIBrief()
        brief.activities = [ScheduledActivity(id: "read", name: "Read", startMinute: nil, minutes: 15, weekdays: [])]
        brief.week = ReviewFacts(kept: 3, asked: 7)

        let plan = try await ai.plan(brief: brief, request: movesReadToWednesday)
        #expect(!plan.isModelWritten)
        #expect(plan.changes == [readOnWednesdays])
        #expect(!(try await ai.reading(brief: brief).isModelWritten))
        #expect(await calls.consents == 0)
        #expect(await calls.entitlements == 0)
        #expect(await calls.tokens == 0)
    }

    /// The allowlist is prepared to take the backend's host, and does not.
    @Test("The network allowlist is still TelemetryDeck alone; the AI host joins only when switched on")
    func allowlistPrepared() {
        #expect(ForgeNetwork.allowedHosts == [ForgeTelemetry.host])
        #expect(ForgeNetwork.aiHost(enabled: false, config: configured) == nil)
        #expect(ForgeNetwork.aiHost(enabled: true, config: nil) == nil)
        #expect(ForgeNetwork.aiHost(enabled: true, config: configured) == "example.supabase.co")
    }

    @Test("The reading fallback is a closed telemetry event with no text")
    func fallbackEvent() {
        #expect(ForgeTelemetry.Event.readingFellBack.name == "reading_fell_back")
        #expect(ForgeTelemetry.Event.readingFellBack.parameters.isEmpty)
    }
}

// MARK: - The path activation will switch on

/// `RemoteForgeAI(testingEndpoint:)` — DEBUG only — with a scripted model
/// endpoint and a real `AnonymousIdentity` on a scripted auth endpoint. This is
/// the request the activation PR turns on, held now.
@Suite("The future AI path, against scripts")
struct FutureAIPathTests {

    private let config = SupabaseConfig(
        url: URL(string: "https://example.supabase.co")!,
        anonKey: "sb_publishable_test"
    )

    private let anonymousSession = """
    {"access_token":"anon-jwt","refresh_token":"r1","expires_in":3600,\
    "user":{"id":"8f7c0e2a-0000-4000-8000-00000000000a","app_metadata":{"provider":"anonymous"}}}
    """

    private let modelPlan = #"{"summary":"Read moves to Wednesday.","changes":[{"kind":"days","id":"read","weekdays":[4]}]}"#

    private var brief: AIBrief {
        var brief = AIBrief()
        brief.activities = [ScheduledActivity(id: "read", name: "Read", startMinute: nil, minutes: 15, weekdays: [])]
        brief.week = ReviewFacts(kept: 3, asked: 7)
        return brief
    }

    /// Everything the path needs, with each input under the test's control.
    private struct Rig {
        let ai: RemoteForgeAI
        let model: ScriptedTransport
        let auth: ScriptedTransport
        let sessions: InMemorySessionStore
        let calls: AICallCounter
    }

    private func rig(
        consent: @escaping @Sendable () async -> Bool,
        proof: String?,
        model: [ScriptedTransport.Reply] = [],
        onFallback: @escaping @Sendable () -> Void = {}
    ) -> Rig {
        let modelTransport = ScriptedTransport(model)
        let authTransport = ScriptedTransport([.json(200, anonymousSession)])
        let sessions = InMemorySessionStore()
        let identity = AnonymousIdentity(
            api: SupabaseAuthAPI(client: HTTPClient(config: config, transport: authTransport)),
            store: sessions
        )
        let calls = AICallCounter()
        let ai = RemoteForgeAI(
            testingEndpoint: AIEndpoint(config: config, client: HTTPClient(config: config, transport: modelTransport)),
            token: { _ = await calls.token(); return await identity.accessToken() },
            entitlement: { await calls.entitlement(); return proof },
            consent: { _ = await calls.consent(); return await consent() },
            onReadingFallback: onFallback
        )
        return Rig(ai: ai, model: modelTransport, auth: authTransport, sessions: sessions, calls: calls)
    }

    @Test("Building the AI at launch creates no anonymous session and makes no request")
    func nothingAtLaunch() async {
        let rig = rig(consent: { true }, proof: "signed.jws")
        _ = rig.ai.isConnected
        #expect(rig.auth.requests.isEmpty)
        #expect(rig.model.requests.isEmpty)
        #expect(rig.sessions.load() == nil)
        #expect(await rig.calls.consents == 0)
        #expect(await rig.calls.entitlements == 0)
        #expect(await rig.calls.tokens == 0)
    }

    @Test("Without Forge Pro, no anonymous session is created and the phone answers")
    func noSessionForFree() async throws {
        let rig = rig(consent: { true }, proof: nil)
        let plan = try await rig.ai.plan(brief: brief, request: movesReadToWednesday)
        #expect(!plan.isModelWritten)
        #expect(plan.changes == [readOnWednesdays])
        #expect(await rig.calls.tokens == 0)
        #expect(rig.auth.requests.isEmpty)
        #expect(rig.model.requests.isEmpty)
        #expect(rig.sessions.load() == nil)
    }

    @Test("Without consent, the purchase is not read and no session is created")
    func noSessionWithoutConsent() async throws {
        let rig = rig(consent: { false }, proof: "signed.jws")
        let reading = try await rig.ai.reading(brief: brief)
        #expect(!reading.isModelWritten)
        #expect(await rig.calls.consents == 1)
        #expect(await rig.calls.entitlements == 0)
        #expect(await rig.calls.tokens == 0)
        #expect(rig.auth.requests.isEmpty)
        #expect(rig.model.requests.isEmpty)
    }

    /// "Not now", stored exactly as the disclosure stores it, read exactly as
    /// the app reads it.
    @MainActor
    @Test("Not now keeps the phone's own answers and sends nothing")
    func notNowStaysLocal() async throws {
        let defaults = UserDefaults(suiteName: "forge.ainotnow.\(UUID().uuidString)") ?? .standard
        AIConsentStore(defaults: defaults).decline()
        let rig = rig(consent: { AIConsentStore.isAllowed(in: defaults) }, proof: "signed.jws")

        let plan = try await rig.ai.plan(brief: brief, request: movesReadToWednesday)
        let reading = try await rig.ai.reading(brief: brief)
        #expect(!plan.isModelWritten)
        #expect(plan.changes == [readOnWednesdays])
        #expect(!reading.isModelWritten)
        #expect(rig.model.requests.isEmpty)
        #expect(rig.auth.requests.isEmpty)
    }

    /// The whole future request: consent, then the purchase, then — only now —
    /// the anonymous session, then the model call carrying both.
    @Test("A future request carries the anonymous JWT and X-Forge-Transaction, and mints the session only then")
    func fullRequest() async throws {
        let rig = rig(consent: { true }, proof: "signed.jws.value", model: [.json(200, modelPlan)])
        #expect(rig.sessions.load() == nil)

        let plan = try await rig.ai.plan(brief: brief, request: movesReadToWednesday)
        #expect(plan.isModelWritten)

        #expect(rig.auth.requests.count == 1)
        #expect(rig.auth.requests.first?.url?.path.hasSuffix("/auth/v1/signup") == true)
        #expect(rig.sessions.load()?.provider == .anonymous)

        let sent = try #require(rig.model.requests.first)
        #expect(sent.url?.path.hasSuffix("/functions/v1/forge-ai") == true)
        #expect(sent.value(forHTTPHeaderField: AIEndpoint.transactionHeader) == "signed.jws.value")
        #expect(sent.value(forHTTPHeaderField: "X-Forge-Transaction") == "signed.jws.value")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer anon-jwt")
        let body = try #require(sent.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(!body.contains("signed.jws.value"))
    }

    @MainActor
    @Test("Revoking consent stops the very next request")
    func revokeStops() async throws {
        let defaults = UserDefaults(suiteName: "forge.airevoke.\(UUID().uuidString)") ?? .standard
        let consent = AIConsentStore(defaults: defaults)
        consent.allow()
        let rig = rig(
            consent: { AIConsentStore.isAllowed(in: defaults) },
            proof: "signed.jws",
            model: [.json(200, modelPlan), .json(200, modelPlan)]
        )

        #expect(try await rig.ai.plan(brief: brief, request: movesReadToWednesday).isModelWritten)
        #expect(rig.model.requests.count == 1)

        consent.revoke()
        #expect(!(try await rig.ai.plan(brief: brief, request: movesReadToWednesday).isModelWritten))
        #expect(rig.model.requests.count == 1)
    }

    @Test("A reading that fails validation falls back, is counted, and is never shown")
    func readingFallsBack() async throws {
        let fallbacks = AICallCounter()
        let rig = rig(
            consent: { true },
            proof: "signed.jws",
            model: [.json(200, #"{"observation":"Nine days were kept."}"#)],
            onFallback: { Task { await fallbacks.fellBack() } }
        )
        let reading = try await rig.ai.reading(brief: brief)
        #expect(!reading.isModelWritten)
        #expect(!reading.observation.contains("Nine"))
        try await Task.sleep(for: .milliseconds(50))
        #expect(await fallbacks.fallbacks == 1)
    }

    @Test("A reading that checks out against the week is marked as model-written")
    func readingValidates() async throws {
        let rig = rig(
            consent: { true },
            proof: "signed.jws",
            model: [.json(200, #"{"observation":"Three days were kept."}"#)]
        )
        let reading = try await rig.ai.reading(brief: brief)
        #expect(reading.isModelWritten)
        #expect(reading.observation == "Three days were kept.")
    }
}

// MARK: - The weekly review

@Suite("Weekly Reading layout")
struct WeeklyReadingLayoutTests {

    private func parts(
        observation: Bool = true, pro: Bool, offering: Bool = false,
        reachable: Bool = false, written: Bool = false
    ) -> [WeeklyReviewReading.Part] {
        WeeklyReviewReading.parts(
            hasObservation: observation, isPremium: pro, isOfferingLocked: offering,
            canReachModel: reachable, hasWritten: written
        )
    }

    @Test("The rules' observation is free and always first")
    func observationFirst() {
        for pro in [false, true] {
            for offering in [false, true] {
                for reachable in [false, true] {
                    for written in [false, true] {
                        let laid = parts(pro: pro, offering: offering, reachable: reachable, written: written)
                        #expect(laid.first == .observation)
                    }
                }
            }
        }
    }

    @Test("Without Pro the Weekly Reading stays locked — door 2 — and is never shown")
    func freeIsLocked() {
        #expect(parts(pro: false, offering: true) == [.observation, .locked])
        #expect(parts(pro: false, offering: false) == [.observation])
        // Not even if a reading somehow exists or a model is reachable.
        #expect(parts(pro: false, offering: true, reachable: true, written: true) == [.observation, .locked])
    }

    @Test("Pro with the model off adds nothing; nothing is invented to fill the space")
    func proWhileDisabled() {
        #expect(parts(pro: true, reachable: false) == [.observation])
    }

    @Test("Pro with a reachable model offers Read my week, then shows the written reading under the observation")
    func proWhenActivated() {
        #expect(parts(pro: true, reachable: true) == [.observation, .readButton])
        #expect(parts(pro: true, reachable: true, written: true) == [.observation, .written])
    }

    @Test("A week with nothing to observe offers nothing further")
    func emptyWeek() {
        #expect(parts(observation: false, pro: false, offering: true).isEmpty)
        #expect(parts(observation: false, pro: true, reachable: true).isEmpty)
    }
}

// MARK: -

/// Counts how often the AI path reaches for each of its inputs.
actor AICallCounter {
    private(set) var consents = 0
    private(set) var entitlements = 0
    private(set) var tokens = 0
    private(set) var fallbacks = 0

    func consent() -> Bool { consents += 1; return true }
    func entitlement() { entitlements += 1 }
    func token() -> String? { tokens += 1; return "counted-token" }
    func fellBack() { fallbacks += 1 }
}

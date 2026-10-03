import Foundation
import Testing
@testable import Forge

/// §17.6 — Ask Forge. Everything here runs without a network: the request
/// against `ScriptedTransport`, the wire format against the edge function's own
/// fixtures (`supabase/functions/forge-ai/tests/fixtures`), which its Deno
/// tests feed through the handler — so the two sides are held to one shape.

private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private let fixtures = root.appendingPathComponent("supabase/functions/forge-ai/tests/fixtures")

private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: fixtures.appendingPathComponent(name))
}

/// The record the fixtures describe: the brief and the coach's additions.
private func fixtureCoach() -> CoachBrief {
    var brief = AIBrief()
    brief.daysKept = 12
    brief.streak = 4
    brief.activities = [
        ScheduledActivity(id: "read", name: "Read", startMinute: 21 * 60, minutes: 20, weekdays: [1, 2, 3, 4, 5, 6, 7]),
        ScheduledActivity(id: "workout", name: "Work out", startMinute: nil, minutes: 45, weekdays: [2, 4, 6]),
    ]
    brief.wakeMinutes = 7 * 60
    brief.identities = ["Someone who trains"]
    return CoachBrief(
        brief: brief,
        arc: .init(id: "monk30", name: "Monk Mode 30", day: 12, length: 30, phase: "Build"),
        scores: [
            .init(category: .intellect, score: 62),
            .init(category: .relationship, score: nil),
            .init(category: .discipline, score: 41, weekChange: -6),
            .init(category: .ambition, score: 47),
            .init(category: .mental, score: 50, weekChange: -2),
            .init(category: .physical, score: 58, weekChange: 3),
        ],
        overall: 52,
        today: [.init(name: "Read", isDone: true), .init(name: "Work out", isDone: false)]
    )
}

private let fixtureTurns = [
    CoachTurn(role: "user", text: "Why is Discipline slipping?"),
    CoachTurn(role: "assistant", text: "Work out was kept on one of its last three days."),
    CoachTurn(role: "user", text: "Make week 3 harder"),
]

// MARK: - The wire, against the server's fixtures

@Suite("Ask Forge's wire format")
struct AskForgeWireTests {

    @Test("A coach request encodes exactly as the edge function's fixture")
    func requestMatchesTheServerFixture() throws {
        let coach = fixtureCoach()
        let request = AIRequest(
            task: .coach,
            brief: AIWireBrief(coach.brief, coach: AIWireCoach(coach)),
            messages: fixtureTurns
        )
        let sent = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? NSDictionary
        let expected = try JSONSerialization.jsonObject(with: fixture("coach-request.json")) as? NSDictionary
        #expect(sent != nil)
        #expect(sent == expected)
    }

    /// Plan and the reading send what they always did: no `messages`, no
    /// `coach`. Ask Forge's widening is Ask Forge's alone.
    @Test("Plan and the reading send no conversation and no coach fields")
    func otherTasksAreUnchanged() throws {
        for task in [AIRequest.Task.plan, .reading] {
            let body = try JSONEncoder().encode(AIRequest(task: task, brief: AIWireBrief(fixtureCoach().brief)))
            let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(object["messages"] == nil)
            let brief = try #require(object["brief"] as? [String: Any])
            #expect(brief["coach"] == nil)
        }
    }

    @Test("The arc sends its id, day and phase, and nothing else of it")
    func arcIsNarrow() throws {
        let body = try JSONEncoder().encode(AIWireCoach(fixtureCoach()))
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let arc = try #require(object["arc"] as? [String: Any])
        #expect(Set(arc.keys) == ["id", "day", "phase"])
        let text = String(decoding: body, as: UTF8.self)
        #expect(!text.contains("Monk Mode"))
        #expect(!text.contains("weekChange"))
    }

    @Test("The server's answers decode, and a proposal resolves against the week")
    func answersDecode() throws {
        let plain = try JSONDecoder().decode(AIWireCoachAnswer.self, from: fixture("coach-answer-plain.json"))
        #expect(plain.reply.hasPrefix("Discipline is 41."))
        #expect(plain.proposal == nil)

        let answer = try JSONDecoder().decode(AIWireCoachAnswer.self, from: fixture("coach-answer-proposal.json"))
        let proposal = try #require(answer.proposal)
        let plan = try #require(proposal.plan(against: fixtureCoach().brief, isModelWritten: true))
        #expect(plan.isModelWritten)
        #expect(plan.changes == [
            .time(id: "workout", name: "Work out", minute: 420, was: nil),
            .days(id: "workout", name: "Work out", weekdays: [2, 3, 5, 7], was: [2, 4, 6]),
        ])
    }

    @Test("An unreadable proposal is no proposal, and a missing reply is an empty one")
    func tolerant() throws {
        let odd = try JSONDecoder().decode(AIWireCoachAnswer.self, from: Data(#"{"proposal":"nope"}"#.utf8))
        #expect(odd.reply.isEmpty)
        #expect(odd.proposal == nil)
    }
}

// MARK: - Proposals

@Suite("Ask Forge's proposals")
struct CoachProposalTests {

    @Test("A change naming an activity that is not in the week is dropped; none left is no plan")
    func onlyRealActivities() {
        let brief = fixtureCoach().brief
        let invented = CoachProposal(summary: "Add a run.", changes: [.init(kind: "time", id: "run", minute: 360)])
        #expect(invented.plan(against: brief, isModelWritten: true) == nil)
        let mixed = CoachProposal(summary: "Read earlier.", changes: [
            .init(kind: "time", id: "run", minute: 360),
            .init(kind: "time", id: "read", minute: 20 * 60),
        ])
        #expect(mixed.plan(against: brief, isModelWritten: true)?.changes
                == [.time(id: "read", name: "Read", minute: 1200, was: 1260)])
    }

    @Test("No kind can add an activity, whatever the model sends")
    func noCreate() {
        let brief = fixtureCoach().brief
        for kind in ["create", "adopt", "goal", "remove", ""] {
            let proposal = CoachProposal(summary: "s", changes: [.init(kind: kind, id: "read", minute: 60, minutes: 10, weekdays: [1])])
            #expect(proposal.plan(against: brief, isModelWritten: true) == nil, Comment(rawValue: kind))
        }
    }

    @Test("The phone's own plan keeps the shape, and says it is the phone's")
    func localPlan() throws {
        let local = SchedulePlan(
            summary: "Read moves to Wednesday.",
            changes: [.days(id: "read", name: "Read", weekdays: [4], was: [])],
            isModelWritten: false
        )
        let proposal = try #require(CoachProposal(local))
        let replan = try #require(proposal.plan(against: fixtureCoach().brief, isModelWritten: false))
        #expect(!replan.isModelWritten)
        #expect(replan.changes.count == 1)
        let creating = SchedulePlan(summary: "s", changes: [.goal(id: "read", name: "Read", goal: "20 pages", target: 20, was: "10 pages")])
        #expect(CoachProposal(creating) == nil)
    }

    @Test("A proposal survives the history round trip")
    func roundTrip() throws {
        let proposal = CoachProposal(summary: "s", changes: [.init(kind: "days", id: "read", weekdays: [2, 4])])
        let message = CoachMessage(role: .forge, text: "t", proposal: proposal)
        let back = try JSONDecoder().decode(CoachMessage.self, from: JSONEncoder().encode(message))
        #expect(back == message)
    }
}

// MARK: - History

@MainActor
@Suite("Ask Forge's history")
struct CoachHistoryTests {

    private func suite() -> UserDefaults {
        UserDefaults(suiteName: "forge.askforge.\(UUID().uuidString)") ?? .standard
    }

    @Test("Kept on the phone under a versioned key, the last forty lines, across launches")
    func keepsForty() {
        let defaults = suite()
        let history = CoachHistory(defaults: defaults)
        for i in 0..<45 { history.append(CoachMessage(role: i.isMultiple(of: 2) ? .user : .forge, text: "line \(i)")) }
        #expect(CoachHistory.key == "forge.askForge.v1")
        #expect(CoachHistory.limit == 40)
        #expect(history.messages.count == 40)
        #expect(history.messages.first?.text == "line 5")
        let relaunched = CoachHistory(defaults: defaults)
        #expect(relaunched.messages.map(\.text) == history.messages.map(\.text))
        #expect(ForgeShared.ownedKeys.contains(CoachHistory.key))
    }

    @Test("Clear removes it from the phone")
    func clears() {
        let defaults = suite()
        let history = CoachHistory(defaults: defaults)
        history.append(CoachMessage(role: .user, text: "hello"))
        history.clear()
        #expect(history.messages.isEmpty)
        #expect(defaults.data(forKey: CoachHistory.key) == nil)
        #expect(CoachHistory(defaults: defaults).messages.isEmpty)
    }

    @Test("An unreadable history is an empty one, not a crash")
    func tolerant() {
        let defaults = suite()
        defaults.set(Data("not json".utf8), forKey: CoachHistory.key)
        #expect(CoachHistory(defaults: defaults).messages.isEmpty)
    }

    @Test("A request carries the last eight sendable turns, oldest first, each cut to 600 characters")
    func lastEight() {
        let history = CoachHistory(defaults: suite())
        for i in 0..<12 { history.append(CoachMessage(role: i.isMultiple(of: 2) ? .user : .forge, text: "turn \(i)")) }
        history.append(CoachMessage(role: .user, text: String(repeating: "x", count: 700)))
        let turns = history.turns
        #expect(CoachHistory.turnLimit == 8)
        #expect(turns.count == 8)
        #expect(turns.first?.text == "turn 5")
        #expect(turns.last?.text.count == 600)
        #expect(turns.last?.role == "user")
        #expect(Set(turns.map(\.role)) == ["user", "assistant"])
    }

    @Test("Safety replies, the messages they answered, notices and the phone's own answers are never sent")
    func neverSent() {
        let history = CoachHistory(defaults: suite())
        history.append(CoachMessage(role: .user, text: "plan my week"))
        history.append(CoachMessage(role: .forge, kind: .notice, text: AskForgeCopy.unreachable))
        history.append(CoachMessage(role: .forge, kind: .local, text: "Read moves to Wednesday."))
        let crisis = CoachMessage(role: .user, text: "something private and heavy")
        history.append(crisis)
        history.withhold(crisis.id)
        history.append(CoachMessage(role: .forge, kind: .safety, text: CoachSafety.crisisReply))
        history.append(CoachMessage(role: .user, text: "Why is Discipline slipping?"))
        #expect(history.turns.map(\.text) == ["plan my week", "Why is Discipline slipping?"])
    }
}

// MARK: - Safety on the phone

@Suite("Ask Forge's safety on the phone")
struct CoachSafetyTests {

    private var serverSafety: String {
        get throws {
            try String(
                contentsOf: root.appendingPathComponent("supabase/functions/forge-ai/safety.ts"),
                encoding: .utf8
            )
        }
    }

    @Test("A message suggesting a crisis is caught, in the words people actually use")
    func catchesCrisis() {
        for text in [
            "I want to kill myself",
            "I've been thinking about suicide",
            "I don’t want to be alive anymore",
            "I keep wanting to self-harm",
            "what's the point, I want to end my life",
            "everyone would be better off without me",
            "I want to die",
            "thinking about taking an overdose",
        ] {
            #expect(CoachSafety.suggestsCrisis(text), Comment(rawValue: text))
        }
    }

    @Test("Ordinary sentences are not mistaken for one")
    func passesOrdinary() {
        for text in [
            "Why is Discipline slipping?",
            "this workout is killing me",
            "I'm dying to get stronger",
            "Make week 3 harder",
            "help me quit porn",
        ] {
            #expect(!CoachSafety.suggestsCrisis(text), Comment(rawValue: text))
        }
    }

    /// The phone answers first and the server answers the same: one list of
    /// patterns and one reply, word for word.
    @Test("The crisis screen and the 988 reply are the server's, word for word")
    func matchesTheServer() throws {
        let source = try serverSafety
        let block = try #require(source.components(separatedBy: "const CRISIS: RegExp[] = [").last?
            .components(separatedBy: "];").first)
        let server = block.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("/") && $0.hasSuffix("/,") }
            .map { String($0.dropFirst().dropLast(2)) }
        #expect(server == CoachSafety.crisisPatterns)
        #expect(source.contains("\"\(CoachSafety.lifelineLine)\""))
        #expect(source.contains("That sounds like a lot to carry, and you don't have to carry it alone. ${LIFELINE_LINE}"))
        #expect(CoachSafety.crisisReply.hasSuffix(CoachSafety.lifelineLine))
    }

    @Test("The 988 reply offers a call and a text, and nothing else")
    func lifeline() {
        #expect(CoachSafety.callURL.absoluteString == "tel:988")
        #expect(CoachSafety.textURL.absoluteString == "sms:988")
        #expect(CoachSafety.mentionsLifeline(CoachSafety.crisisReply))
        #expect(!CoachSafety.mentionsLifeline("Day 9 of 88."))
        #expect(!CoachSafety.crisisReply.contains("!"))
        #expect(!CoachSafety.crisisReply.contains("?"))
    }

    @Test("Forge's voice is held on the phone: no exclamation marks, no emoji, digits kept")
    func voice() {
        #expect(CoachSafety.inVoice("Nice work! 🔥🔥 Day 12 of 30.") == "Nice work. Day 12 of 30.")
        #expect(CoachSafety.inVoice("Really?! Read at 21:00.") == "Really? Read at 21:00.")
        #expect(CoachSafety.inVoice("Discipline 41, OVR 52 — #1 priority.") == "Discipline 41, OVR 52 — #1 priority.")
        #expect(CoachSafety.inVoice("👍") == "")
    }

    @Test("Report is a pre-filled email to support, with the reply in it, that the person sends")
    func report() throws {
        let url = try #require(AskForgeView.reportURL(for: "Take a rest day & sleep 9h."))
        #expect(url.scheme == "mailto")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == ForgeLinks.supportEmail)
        #expect(ForgeLinks.supportEmail == "forge.discipline.daily@gmail.com")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["subject"] == "Ask Forge: reporting a reply")
        #expect(items["body"]?.contains("\"Take a rest day & sleep 9h.\"") == true)
    }

    @Test("The words on screen keep the voice, and the failure line is the one asked for")
    func copy() {
        #expect(AskForgeCopy.unreachable == "Ask Forge can't reach the server right now. Your record is fine.")
        #expect(AskForgeCopy.disclaimer == "Not medical advice")
        for line in [AskForgeCopy.unreachable, AskForgeCopy.local, AskForgeCopy.declined, AskForgeCopy.intro,
                     AskForgeCopy.modelLabel, CoachSafety.crisisReply] {
            #expect(!line.contains("!"), Comment(rawValue: line))
        }
    }
}

// MARK: - Starters

@Suite("Ask Forge's starters")
struct CoachStarterTests {

    @Test("Three starters from the record: the slipping dimension, the next week of the Arc, the day")
    func fromTheRecord() {
        var coach = fixtureCoach()
        coach.brief.activities = coach.brief.activities.map {
            var timed = $0
            timed.startMinute = timed.startMinute ?? 18 * 60
            return timed
        }
        let starters = CoachStarters.make(coach, topic: .general)
        #expect(starters == [
            "Why is Discipline slipping?",
            "Make week 3 harder",
            "What's left today, in what order?",
        ])
    }

    @Test("Nothing is called slipping unless it fell: otherwise the weakest, or which to build")
    func noManufacturedProblem() {
        var coach = fixtureCoach()
        coach.scores = coach.scores.map { CoachBrief.Score(category: $0.category, score: $0.score, weekChange: 2) }
        #expect(CoachStarters.dimensionStarter(coach) == "How do I raise Discipline?")
        coach.scores = []
        #expect(CoachStarters.dimensionStarter(coach) == "Which of the six should I build first?")
    }

    @Test("The Arc starter names a week that exists, and there is one without an Arc")
    func arc() {
        var coach = fixtureCoach()
        coach.arc = .init(id: "lockin7", name: "Lock In 7", day: 5, length: 7, phase: "Lock in")
        #expect(CoachStarters.arcStarter(coach) == "What should the last days of Lock In 7 look like?")
        coach.arc = nil
        #expect(CoachStarters.arcStarter(coach) == "Which Arc fits my week?")
    }

    @Test("The day's starter: an untimed activity first, then what is left, then evenings around work")
    func day() {
        var coach = fixtureCoach()
        #expect(CoachStarters.weekStarter(coach) == "Give Work out a time that sticks")
        coach.brief.activities = coach.brief.activities.map { var a = $0; a.startMinute = 600; return a }
        #expect(CoachStarters.weekStarter(coach) == "What's left today, in what order?")
        coach.today = coach.today.map { .init(name: $0.name, isDone: true) }
        #expect(CoachStarters.weekStarter(coach) == "Fit my evenings around work until 18:00")
    }

    @Test("From the Arc's card, the Arc leads; there are always three, and never twice the same")
    func arcTopic() {
        let starters = CoachStarters.make(fixtureCoach(), topic: .arc)
        #expect(starters.first == "Make week 3 harder")
        #expect(starters.count == 3)
        #expect(Set(starters).count == 3)
        #expect(starters.contains("What is the Build phase asking of me?"))
    }
}

// MARK: - The request

@Suite("Ask Forge, against scripts")
struct AskForgeRequestTests {

    private let config = SupabaseConfig(
        url: URL(string: "https://example.supabase.co")!,
        anonKey: "sb_publishable_test"
    )

    private func rig(
        _ replies: [ScriptedTransport.Reply],
        consent: Bool = true,
        proof: String? = "signed.jws",
        calls: AICallCounter = AICallCounter()
    ) -> (RemoteForgeAI, ScriptedTransport) {
        let transport = ScriptedTransport(replies)
        let ai = RemoteForgeAI(
            testingEndpoint: AIEndpoint(config: config, client: HTTPClient(config: config, transport: transport)),
            token: { _ = await calls.token(); return "anon-jwt" },
            entitlement: { await calls.entitlement(); return proof },
            consent: { _ = await calls.consent(); return consent }
        )
        return (ai, transport)
    }

    @Test("A message carries the brief, the coach's additions, the turns, the JWT and the transaction")
    func fullRequest() async throws {
        let (ai, transport) = rig([.json(200, String(decoding: try fixture("coach-answer-proposal.json"), as: UTF8.self))])
        let reply = try await ai.coach(brief: fixtureCoach(), turns: fixtureTurns)
        #expect(reply.text.hasPrefix("Week 3 is Build."))
        #expect(reply.proposal?.changes.count == 2)
        #expect(!reply.isSafety)

        let sent = try #require(transport.requests.first)
        #expect(sent.url?.path.hasSuffix("/functions/v1/forge-ai") == true)
        #expect(sent.value(forHTTPHeaderField: "X-Forge-Transaction") == "signed.jws")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer anon-jwt")
        let body = try #require(sent.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(body["task"] as? String == "coach")
        #expect((body["messages"] as? [[String: Any]])?.count == 3)
        #expect((body["brief"] as? [String: Any])?["coach"] != nil)
        let raw = String(decoding: sent.httpBody ?? Data(), as: UTF8.self)
        #expect(!raw.contains("signed.jws"))
    }

    @Test("Offline, 402, 429 and 5xx are one error, which the screen says in one line")
    func failures() async {
        for reply in [ScriptedTransport.Reply.offline, .json(402, #"{"error":"not_entitled"}"#),
                      .json(429, #"{"error":"rate_limited"}"#), .json(500, "{}"), .json(503, "{}"),
                      .json(200, #"{"reply":"","proposal":null}"#), .json(200, "not json")] {
            let (ai, _) = rig([reply])
            await #expect(throws: CoachError.unreachable) {
                _ = try await ai.coach(brief: fixtureCoach(), turns: fixtureTurns)
            }
        }
    }

    @Test("Without consent nothing is read or sent; without a purchase no identity is made")
    func order() async {
        let calls = AICallCounter()
        let (noConsent, transport) = rig([], consent: false, calls: calls)
        await #expect(throws: CoachError.unreachable) {
            _ = try await noConsent.coach(brief: fixtureCoach(), turns: fixtureTurns)
        }
        #expect(await calls.entitlements == 0)
        #expect(await calls.tokens == 0)
        #expect(transport.requests.isEmpty)

        let (noProof, transport2) = rig([], proof: nil, calls: calls)
        await #expect(throws: CoachError.unreachable) {
            _ = try await noProof.coach(brief: fixtureCoach(), turns: fixtureTurns)
        }
        #expect(await calls.tokens == 0)
        #expect(transport2.requests.isEmpty)
    }

    @Test("A conversation whose last turn is not the person's is never sent")
    func lastTurnIsTheirs() async {
        let (ai, transport) = rig([])
        await #expect(throws: CoachError.unreachable) {
            _ = try await ai.coach(brief: fixtureCoach(), turns: [CoachTurn(role: "assistant", text: "x")])
        }
        #expect(transport.requests.isEmpty)
    }

    @Test("A reply is held to the voice, and one carrying the 988 line keeps no proposal")
    func voiceAndSafety() async throws {
        let (loud, _) = rig([.json(200, #"{"reply":"Great question! 💪 Read at 21:00.","proposal":null}"#)])
        #expect(try await loud.coach(brief: fixtureCoach(), turns: fixtureTurns).text == "Great question. Read at 21:00.")

        let crisis = #"{"reply":"That sounds hard. \#(CoachSafety.lifelineLine)","proposal":{"summary":"s","changes":[{"kind":"time","id":"read","minute":60,"minutes":null,"weekdays":null}]}}"#
        let (safe, _) = rig([.json(200, crisis)])
        let reply = try await safe.coach(brief: fixtureCoach(), turns: fixtureTurns)
        #expect(reply.isSafety)
        #expect(reply.proposal == nil)
    }
}

// MARK: - Who may open it, and what it discloses

@Suite("Ask Forge's gate and disclosure")
struct AskForgeGateTests {

    @Test("Forge Pro and the free week open Ask Forge; founders, lapsed and never-subscribed meet the paywall")
    func gate() {
        let now = Date()
        #expect(!PremiumGate.isLocked(.askForge, for: .pro(.annual)))
        #expect(!PremiumGate.isLocked(.askForge, for: .trial(.annual, ends: now)))
        #expect(!PremiumGate.isLocked(.askForge, for: .unknown))
        #expect(PremiumGate.isLocked(.askForge, for: .founder))
        #expect(PremiumGate.isLocked(.askForge, for: .lapsed))
        #expect(PremiumGate.isLocked(.askForge, for: .none))
        #expect(ForgeTelemetry.PaywallDoor.ai.rawValue == "ai")
    }

    /// The manifest moves with the switch: with the model on, the three AI
    /// types are declared — linked, for app functionality, never tracking —
    /// beside anonymous usage, and Forge still tracks nobody.
    @Test("The privacy manifest declares what the AI collects, and still no tracking")
    func manifest() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("Forge/PrivacyInfo.xcprivacy"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["NSPrivacyTracking"] as? Bool == false)
        #expect((plist["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
        let types = try #require(plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let byName = Dictionary(uniqueKeysWithValues: types.compactMap { entry in
            (entry["NSPrivacyCollectedDataType"] as? String).map { ($0, entry) }
        })
        #expect(RemoteForgeAI.isModelEnabled)
        for type in ["NSPrivacyCollectedDataTypeOtherUserContent", "NSPrivacyCollectedDataTypePurchaseHistory",
                     "NSPrivacyCollectedDataTypeUserID"] {
            let entry = try #require(byName[type], Comment(rawValue: type))
            #expect(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool == true, Comment(rawValue: type))
            #expect(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool == false, Comment(rawValue: type))
            #expect(entry["NSPrivacyCollectedDataTypePurposes"] as? [String]
                    == ["NSPrivacyCollectedDataTypePurposeAppFunctionality"], Comment(rawValue: type))
        }
        for type in ["NSPrivacyCollectedDataTypeProductInteraction", "NSPrivacyCollectedDataTypeOtherDiagnosticData"] {
            #expect(byName[type]?["NSPrivacyCollectedDataTypeLinked"] as? Bool == false, Comment(rawValue: type))
        }
        #expect(byName["NSPrivacyCollectedDataTypeHealth"] == nil)
        #expect(byName["NSPrivacyCollectedDataTypeFitness"] == nil)
        #expect(types.count == 5)
    }

    @Test("The disclosure names what Ask Forge sends, and no longer claims no day's record leaves")
    func disclosure() {
        let all = AIDisclosureView.explanations.joined(separator: " ")
        #expect(all.contains("Ask Forge"))
        #expect(all.contains("six stats and OVR"))
        #expect(all.contains("today's list"))
        #expect(all.contains("what you write to Ask Forge"))
        #expect(!AIDisclosureView.absent.contains("Any single day's record"))
        #expect(AIDisclosureView.absent.contains("Any past day's record"))
        #expect(AIDisclosureView.absent.contains { $0.contains("Apple Health") })
    }
}

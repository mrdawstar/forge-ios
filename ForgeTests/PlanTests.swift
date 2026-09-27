import Foundation
import Testing
@testable import Forge

/// What Forge offers to change about somebody's week.
///
/// Two promises hold this whole file up, and the first outranks everything else:
/// **nothing is invented.** Every move states a reason drawn from the record,
/// and a planner that will manufacture a fourth-best suggestion to avoid an
/// empty screen is a planner whose suggestions mean nothing. So most of what is
/// here is the *silence* cases — the weeks where the honest answer is that there
/// is nothing worth changing.
///
/// The second is that a move never quietly costs somebody something. Rest days
/// are never a destination, an activity is never reduced below three days, and
/// `.adopt` only ever names an activity that already exists in the catalogue and
/// is not already in the week.
@Suite("Plan")
struct PlanTests {

    // MARK: - Fixtures

    private func activity(
        _ id: String,
        _ name: String,
        at start: Int? = nil,
        minutes: Int = 30,
        weekdays: Set<Int> = []
    ) -> ScheduledActivity {
        ScheduledActivity(
            id: id, name: name, startMinute: start, minutes: minutes, weekdays: weekdays
        )
    }

    /// A week with an hour on everything and nothing wrong with it.
    private var settled: DayPlanner.Facts {
        DayPlanner.Facts(
            activities: [
                activity("water", "Drink water", at: 7 * 60, minutes: 5),
                activity("read", "Read", at: 20 * 60, minutes: 15),
                activity("walk", "Walk outside", at: 12 * 60, minutes: 20),
            ],
            categories: ["water": .physical, "read": .intellect, "walk": .physical],
            wakeMinutes: 6 * 60 + 30
        )
    }

    // MARK: - Nothing to say

    /// The most important test here. A tidy week, no shape, no focus, no
    /// history: the answer is an empty array and the screen says so.
    @Test("A week with nothing wrong with it produces no moves")
    func silenceIsAnAnswer() {
        #expect(DayPlanner.moves(settled).isEmpty)
    }

    @Test("An empty week produces no moves")
    func nothingToPlan() {
        #expect(DayPlanner.moves(DayPlanner.Facts()).isEmpty)
    }

    // MARK: - Untangling

    @Test("Two activities running over each other on the same day is a clash")
    func overlapIsFound() throws {
        var facts = settled
        facts.activities = [
            activity("focus", "Deep work", at: 9 * 60, minutes: 60, weekdays: [3]),
            activity("run", "Go for a run", at: 9 * 60 + 30, minutes: 20, weekdays: [3]),
        ]
        let move = try #require(DayPlanner.untangle(facts))
        #expect(move.plan.changes.count == 1)
        // The *second* one moves. The first is where it is because somebody put
        // it there, and a planner that moves the earlier of two is a planner
        // that walks a whole morning backwards.
        #expect(move.plan.changes.first?.activityName == "Go for a run")
    }

    /// The false positive that would make this feature worth dismissing unread.
    @Test("Two activities at the same hour on different days do not clash")
    func differentDaysDoNotClash() {
        var facts = settled
        facts.activities = [
            activity("focus", "Deep work", at: 9 * 60, minutes: 60, weekdays: [3]),
            activity("run", "Go for a run", at: 9 * 60, minutes: 20, weekdays: [5]),
        ]
        #expect(DayPlanner.untangle(facts) == nil)
    }

    @Test("Something starting before the day opens is moved after it")
    func beforeWakingIsFound() throws {
        var facts = settled
        facts.wakeMinutes = 7 * 60
        facts.activities = [activity("push", "Push-ups", at: 5 * 60, minutes: 10)]

        let move = try #require(DayPlanner.untangle(facts))
        guard case .time(_, _, let minute, let was) = try #require(move.plan.changes.first) else {
            Issue.record("expected a time change")
            return
        }
        #expect(was == 5 * 60)
        #expect(minute > facts.wakeMinutes ?? 0)
    }

    // MARK: - Strengthening

    @Test("A chosen dimension with nothing filed under it is what gets offered")
    func chosenAndEmptyIsOffered() throws {
        var facts = settled
        facts.focus = [.relationship]
        facts.available = [
            .init(id: "thanks", name: "Say the thing", minutes: 0, category: .relationship),
            .init(id: "meal", name: "Eat with someone", minutes: 30, category: .relationship),
        ]

        let move = try #require(DayPlanner.strengthen(facts))
        guard case .adopt(let id, _, _, let weekdays, _) = try #require(move.plan.changes.first) else {
            Issue.record("expected an adopt")
            return
        }
        // The *smallest* one on the ladder, not the most impressive. Somebody
        // weak in an area is the last person to hand the hardest thing in it.
        #expect(id == "thanks")
        #expect(!weekdays.isEmpty)
        #expect(move.reason.lowercased().contains("relationship"))
    }

    /// The one that keeps the feature from being a nag. Somebody who said they
    /// wanted Physical and Relationship does not want to be told about
    /// Discipline, however low it reads.
    @Test("Nothing is offered for a dimension nobody asked about")
    func unchosenDimensionsAreLeftAlone() {
        var facts = settled
        facts.focus = [.physical]
        facts.available = [
            .init(id: "call", name: "Call someone", minutes: 10, category: .relationship),
        ]
        // Physical is already kept and there is nothing available in it, so
        // there is nothing to say — and Relationship is not somebody's problem
        // just because the library has something to sell for it.
        #expect(DayPlanner.strengthen(facts) == nil)
    }

    @Test("Nothing is offered when the library has nothing left in that dimension")
    func nothingToOffer() {
        var facts = settled
        facts.focus = [.relationship]
        facts.available = []
        #expect(DayPlanner.strengthen(facts) == nil)
    }

    /// Rest days are somebody's own decision and a planner does not get to
    /// spend them.
    @Test("A new activity is never put on a rest day")
    func restDaysAreNeverADestination() throws {
        var facts = settled
        facts.focus = [.relationship]
        facts.restWeekdays = [1, 7]
        facts.available = [
            .init(id: "call", name: "Call someone", minutes: 10, category: .relationship),
        ]

        let move = try #require(DayPlanner.strengthen(facts))
        guard case .adopt(_, _, _, let weekdays, _) = try #require(move.plan.changes.first) else {
            Issue.record("expected an adopt")
            return
        }
        #expect(weekdays.isDisjoint(with: facts.restWeekdays))
    }

    // MARK: - Easing off

    @Test("Something kept four times in eleven is offered three days instead")
    func slippingIsEased() throws {
        var facts = settled
        facts.activities = [activity("read", "Read", at: 20 * 60, minutes: 15)]
        facts.recent = [.init(id: "read", planned: 11, completed: 4)]

        let move = try #require(DayPlanner.ease(facts))
        guard case .days(_, _, let weekdays, _) = try #require(move.plan.changes.first) else {
            Issue.record("expected a days change")
            return
        }
        #expect(weekdays.count == 3)
        #expect(move.reason.contains("4"))
        #expect(move.reason.contains("11"))
    }

    /// The floor. Something already asked for three days cannot be talked down
    /// to two, however badly it is going — at some point the answer is not a
    /// smaller ask.
    @Test("Something already asked for three days is left alone")
    func threeDaysIsTheFloor() {
        var facts = settled
        facts.activities = [activity("read", "Read", minutes: 15, weekdays: [2, 4, 6])]
        facts.recent = [.init(id: "read", planned: 11, completed: 2)]
        #expect(DayPlanner.ease(facts) == nil)
    }

    @Test("Something being kept is left alone")
    func whatWorksIsLeftAlone() {
        var facts = settled
        facts.recent = [.init(id: "read", planned: 20, completed: 18)]
        #expect(DayPlanner.ease(facts) == nil)
    }

    /// Two bad weeks is not a pattern. The sample floor is what stops the app
    /// telling somebody their new activity is failing on its fourth day.
    @Test("A small sample says nothing")
    func smallSamplesAreSilent() {
        var facts = settled
        facts.recent = [.init(id: "read", planned: 3, completed: 0)]
        #expect(DayPlanner.ease(facts) == nil)
    }

    // MARK: - Balance

    @Test("A day carrying the week gives one activity to the lightest day")
    func balanceMovesOneThing() throws {
        var facts = settled
        facts.activities = [
            activity("lift", "Lift something heavy", minutes: 45, weekdays: [3]),
            activity("run", "Go for a run", minutes: 20, weekdays: [3]),
            activity("focus", "Deep work", minutes: 45, weekdays: [3]),
            activity("read", "Read", minutes: 15, weekdays: [6]),
        ]

        let move = try #require(DayPlanner.balance(facts))
        #expect(move.plan.changes.count == 1, "one thing moves, never a whole week")
        guard case .days(_, _, let weekdays, let was) = try #require(move.plan.changes.first) else {
            Issue.record("expected a days change")
            return
        }
        #expect(!weekdays.contains(3))
        #expect(was.contains(3))
    }

    @Test("A level week is not rebalanced")
    func levelWeeksAreLeftAlone() {
        var facts = settled
        facts.activities = [
            activity("read", "Read", minutes: 15, weekdays: [2]),
            activity("walk", "Walk outside", minutes: 15, weekdays: [4]),
        ]
        #expect(DayPlanner.balance(facts) == nil)
    }

    /// A daily activity is never narrowed to "every day except Tuesday". That
    /// is a far bigger edit than "move one thing", and nobody reading the card
    /// is agreeing to it.
    @Test("A daily activity is never moved off one day")
    func dailyActivitiesAreNotNarrowed() {
        var facts = settled
        facts.activities = [
            activity("lift", "Lift something heavy", minutes: 90),
            activity("read", "Read", minutes: 15, weekdays: [6]),
        ]
        #expect(DayPlanner.balance(facts) == nil)
    }

    // MARK: - What a move produces

    /// Every move has to survive the trip through the review screen, which
    /// projects it onto the week before drawing it.
    @Test("Every move projects onto the week without losing an activity")
    func movesProjectCleanly() {
        var facts = settled
        facts.focus = [.relationship]
        facts.available = [
            .init(id: "call", name: "Call someone", minutes: 10, category: .relationship),
        ]
        facts.recent = [.init(id: "read", planned: 11, completed: 3)]
        facts.activities.append(
            activity("focus", "Deep work", at: 20 * 60 + 5, minutes: 60, weekdays: [2])
        )

        let moves = DayPlanner.moves(facts)
        #expect(!moves.isEmpty)
        for move in moves {
            let projected = move.plan.projected(onto: facts.activities)
            #expect(
                projected.count >= facts.activities.count,
                Comment(rawValue: "\(move.kind) lost an activity")
            )
            #expect(!move.plan.changes.isEmpty)
            #expect(!move.reason.isEmpty)
            #expect(!move.title.isEmpty)
            // Nothing here was written by a model, and nothing may claim to be.
            #expect(!move.plan.isModelWritten)
        }
    }

    @Test("Adopting an activity already in the week is a no-op in the preview")
    func adoptDoesNotDuplicate() {
        let plan = SchedulePlan(
            summary: "",
            changes: [.adopt(id: "read", name: "Read", minutes: 15, weekdays: [2], minute: nil)]
        )
        let projected = plan.projected(onto: settled.activities)
        #expect(projected.count == settled.activities.count)
    }
}

// MARK: - What somebody said they wanted to build

/// `ForgeViewModel.focus` and the activities it aims.
///
/// The one property that has to hold: **an empty focus behaves exactly as the
/// app behaved before any of this existed.** Somebody who skips the first run's
/// question, and everybody who installed before the question existed, must get
/// the shipped eight and nothing withheld anywhere.
@Suite("What you're building")
struct FocusTests {

    @Test("Choosing nothing offers exactly what the app always offered")
    func skippingCostsNothing() {
        let offered = IdentityActivities.offered(forDimensions: [])
        #expect(offered.count == IdentityActivities.offerCount)
        #expect(offered == Array(IdentityActivities.unaimed.prefix(IdentityActivities.offerCount)))
    }

    @Test("What is offered is aimed at what was chosen")
    func offersFollowTheChoice() {
        let offered = IdentityActivities.offeredRituals(forDimensions: [.relationship])
        #expect(offered.count == IdentityActivities.offerCount)
        #expect(offered.allSatisfy { $0.category == .relationship })
    }

    /// Round robin, not "the eight cheapest". Somebody who picks two dimensions
    /// should see an offer that looks like the answer they gave.
    @Test("Two chosen dimensions are both represented")
    func twoDimensionsAreBalanced() {
        let offered = IdentityActivities.offeredRituals(forDimensions: [.physical, .relationship])
        #expect(offered.contains { $0.category == .physical })
        #expect(offered.contains { $0.category == .relationship })
    }

    @Test("The smallest thing is always first")
    func theLadderDecidesTheOrder() {
        for dimension in RitualCategory.dimensions {
            let offered = IdentityActivities.offered(forDimensions: [dimension])
            let efforts = offered.map { IdentityActivities.effort(of: $0) }
            #expect(efforts == efforts.sorted(), Comment(rawValue: "\(dimension) is out of order"))
        }
    }

    @Test("Every offered activity resolves to a real one")
    func nothingOfferedIsAGhost() {
        for dimension in RitualCategory.dimensions {
            for id in IdentityActivities.offered(forDimensions: [dimension]) {
                #expect(
                    Ritual.find(id) != nil,
                    Comment(rawValue: "\(dimension) offers \(id), which does not exist")
                )
            }
        }
    }

    /// The offer is curated per dimension now, not "that dimension's cheapest".
    /// Somebody who says Physical must not be handed vitamins and a coffee.
    @Test("Every dimension's curated list is real, complete and unique")
    func startersAreWellFormed() {
        for dimension in RitualCategory.dimensions {
            let curated = IdentityActivities.starters[dimension] ?? []
            let library = Set(Ritual.library.filter { $0.category == dimension }.map(\.id))

            #expect(!curated.isEmpty, Comment(rawValue: "\(dimension) has no starters"))
            #expect(Set(curated).count == curated.count,
                    Comment(rawValue: "\(dimension) lists something twice"))
            #expect(Set(curated) == library,
                    Comment(rawValue: "\(dimension) does not cover its own activities exactly"))
        }
    }

    /// The three-dimension cap was lifted in the first run, so an answer wider
    /// than three has to get an offer that can represent it. Eight across six
    /// parts of a person is one each and rounding.
    @Test("A wide answer is offered more than eight")
    func aWideAnswerWidensTheOffer() {
        let three: Set<RitualCategory> = [.physical, .intellect, .mental]
        #expect(IdentityActivities.offered(forDimensions: three).count == IdentityActivities.offerCount)

        let all = Set(RitualCategory.dimensions)
        let offered = IdentityActivities.offeredRituals(forDimensions: all)
        #expect(offered.count == 12)
        #expect(Set(offered.map(\.category)) == all, "every chosen part is represented")
        #expect(Set(offered.map(\.id)).count == offered.count)
    }

    /// The first row of a dimension's curated list is the thing a person
    /// actually means by it, and one dimension alone still fills the screen.
    @Test("One dimension leads with what people mean by it")
    func oneDimensionLeadsWell() {
        let physical = IdentityActivities.offered(forDimensions: [.physical])
        #expect(physical.count == IdentityActivities.offerCount)
        #expect(physical.contains("walk"))
        #expect(physical.contains("workout"))
        // The three that were being offered instead, because they ask least.
        #expect(!physical.contains("vitamins"))
        #expect(!physical.contains("coffee"))
    }

    /// The Shape names weak dimensions out loud, so every one of the six has to
    /// have something honest to put in it. Six was the bar; four of them were
    /// under it before the library was widened.
    @Test("Every dimension has enough in the library to recommend from")
    func noDimensionIsThin() {
        for dimension in RitualCategory.dimensions {
            let count = Ritual.library.count { $0.category == dimension }
            #expect(count >= 6, Comment(rawValue: "\(dimension) holds only \(count)"))
        }
    }

    /// The ladder decides what a stranger is asked for first and what the
    /// choosing screen shows. An activity missing from it silently sorts to the
    /// end, which is survivable; one listed twice is an ordering that depends on
    /// which copy is found first, which is not.
    @Test("The effort ladder covers the library exactly once")
    func theLadderIsComplete() {
        let library = Set(Ritual.library.map(\.id))
        let ladder = IdentityActivities.effortOrder

        #expect(Set(ladder) == library)
        #expect(ladder.count == library.count, "the ladder lists something twice")
    }

    /// Every activity is filed, verified and effort-ranked, or a screen
    /// somewhere shows a blank where a fact should be.
    @Test("Every shipped activity is filed and verifiable")
    func everyActivityIsComplete() {
        for ritual in Ritual.library {
            #expect(
                Ritual.categories[ritual.id] != nil,
                Comment(rawValue: "\(ritual.id) is unfiled")
            )
            #expect(
                Ritual.libraryVerification[ritual.id] != nil,
                Comment(rawValue: "\(ritual.id) has no verification")
            )
            #expect(!ritual.metadata.isEmpty)
        }
    }

    /// A duplicated glyph three rows apart reads as a list that has lost its
    /// data. It is allowed within reason — thirty-nine ids share twenty-odd
    /// marks — but no mark may be doing more than three jobs.
    @Test("No glyph is stretched across more than three activities")
    func glyphsAreNotOverloaded() {
        var uses: [String: Int] = [:]
        for ritual in Ritual.library { uses[ritual.iconKey, default: 0] += 1 }
        for (key, count) in uses {
            #expect(count <= 3, Comment(rawValue: "\(key) is used \(count) times"))
        }
    }
}

// MARK: - What today's count is a count of

/// The numerator on the day panel.
///
/// One rule and it is load-bearing: **the count is about today's list.** It was
/// a count of everything completed today, which is a different thing the moment
/// somebody finishes something and then takes it off the day — and because
/// `allDone` compares the two, that difference is a route to earning a day with
/// an unfinished activity still on the panel.
@MainActor
@Suite("Today's count")
struct DayCountTests {

    private func makeViewModel() -> ForgeViewModel {
        let suite = UserDefaults(suiteName: "forge.tests.\(UUID().uuidString)") ?? .standard
        let progress = ProgressStore(defaults: suite)
        let vm = ForgeViewModel(progress: progress)
        vm.resetFirstRun()
        vm.finishFirstRun()
        return vm
    }

    /// The reachable version of the bug. Taking an activity off *today* when it
    /// also happens on another day leaves the completion in the record — which
    /// is right, because it was done — and used to leave it in the day's count
    /// too, which is not.
    @Test("Taking a finished activity off today does not finish the day")
    func removingIsNotFinishing() {
        let vm = makeViewModel()
        let today = vm.progress.currentDay.weekday
        let other = today == 7 ? 1 : today + 1
        vm.chooseStarters(["water", "bed", "teeth"])
        // Two days, so `removeFromDay` takes it off today rather than out of
        // the week — the path that keeps the completion.
        vm.setWeekday("bed", other, on: true)

        vm.keepPromise("water")
        vm.keepPromise("bed")
        #expect(vm.totalDone == 2)
        #expect(!vm.allDone, "one is still on the list")

        vm.removeFromDay("bed", weekday: today)

        #expect(vm.totalActive == 2)
        #expect(vm.totalDone == 1, "the count is about today's list")
        #expect(!vm.allDone, "taking something off today must never earn the day")
        #expect(vm.isDone("bed"), "the completion itself is untouched")
    }

    @Test("The dots and the words say the same number")
    func theDotsAgreeWithTheCount() {
        let vm = makeViewModel()
        let today = vm.progress.currentDay.weekday
        let other = today == 7 ? 1 : today + 1
        vm.chooseStarters(["water", "bed", "teeth"])
        vm.setWeekday("water", other, on: true)
        vm.keepPromise("water")
        vm.removeFromDay("water", weekday: today)

        #expect(vm.progressSegments.count { $0 } == vm.totalDone)
        #expect(vm.listLabel == "0 OF 2")
    }
}

// MARK: - Nothing leaves the phone

/// The promise 1.0 makes about the network, held by a test rather than by
/// somebody remembering.
///
/// **Forge 1.0 sends nothing anywhere for any AI feature.** Not for a plan, not
/// for a challenge, not for the weekly reading — and not on a phone that is
/// signed in to a fully configured project, which is the case that would
/// otherwise slip through, because everything about it looks like the case that
/// should work.
///
/// This is a tripwire and it is meant to fail loudly the day somebody turns the
/// model on. When that day comes, the thing to change is
/// `RemoteForgeAI.isModelEnabled` **and** the privacy nutrition labels in
/// `APP_STORE.md` §1, which currently answer "not collected" for the AI brief
/// on the strength of exactly this.
///
/// **One host is allowed, and only one** (since 2p, `FORGE_CONTEXT.md`):
/// TelemetryDeck's ingest host, for anonymous usage. The last three tests here
/// hold that to exactly one host, prove a request to any other host is refused
/// before a socket exists, and prove the telemetry itself is silent under test.
@Suite("Nothing leaves the phone but anonymous usage")
struct NoNetworkTests {

    /// A project that is configured in every way that matters, so the test is
    /// about the switch and not about a missing key.
    private var configured: SupabaseConfig {
        SupabaseConfig(
            url: URL(string: "https://example.supabase.co")!,
            anonKey: "sb_publishable_test"
        )
    }

    @Test("The model is off in this release")
    func theModelIsOff() {
        #expect(RemoteForgeAI.isModelEnabled == false)
    }

    /// The one that matters. A configured project **and** a valid token still
    /// produces a disconnected client, because the switch is read before either.
    @Test("A configured project with a signed-in token is still not connected")
    func aConfiguredProjectStaysOffline() {
        let ai = RemoteForgeAI(
            config: configured,
            token: { "a-valid-looking-token" },
            entitlement: { "a-valid-looking-transaction" }
        )
        #expect(!ai.isConnected)
    }

    @Test("No project configured is not connected either")
    func noProjectStaysOffline() {
        #expect(!RemoteForgeAI(config: nil, token: { nil }, entitlement: { nil }).isConnected)
    }

    /// Every answer comes from the arithmetic, and says so. `isModelWritten` is
    /// what every screen reads to decide whether to claim a model wrote
    /// something; nothing may come back true.
    @Test("Every answer is the phone's own, and admits it")
    func everyAnswerIsLocal() async throws {
        let ai = RemoteForgeAI(
            config: configured,
            token: { "a-valid-looking-token" },
            entitlement: { "a-valid-looking-transaction" }
        )

        var brief = AIBrief()
        brief.activities = [
            ScheduledActivity(
                id: "read", name: "Read", startMinute: nil, minutes: 15, weekdays: []
            ),
        ]
        brief.wakeMinutes = 7 * 60

        let plan = try await ai.plan(brief: brief, request: "plan my week")
        #expect(!plan.isModelWritten)

        // Off the shipped shelf, which is the proof it was not written
        // anywhere else: every local answer is one of the sixty.
        let challenge = try await ai.challenge(
            brief: brief, difficulty: .medium, focus: .discipline, wish: ""
        )
        #expect(ChallengeCatalog.all.contains { $0.title == challenge.title })
    }

    /// A reading is the widest thing the app could transmit — it carries
    /// `ReviewFacts` on top of the brief — and it is also the only AI call that
    /// was ever made without a button being pressed. It has to come back
    /// phone-written too.
    @Test("A weekly reading is written by the rules")
    func theReadingIsLocal() async throws {
        let ai = RemoteForgeAI(
            config: configured,
            token: { "a-valid-looking-token" },
            entitlement: { "a-valid-looking-transaction" }
        )
        var brief = AIBrief()
        brief.week = ReviewFacts(kept: 3, asked: 7)

        let reading = try await ai.reading(brief: brief)
        #expect(!reading.isModelWritten)
    }

    /// The anonymous identity is only ever minted on the way to a model, and
    /// with the model off nothing is on the way to one. Neither credential is
    /// even asked for — no StoreKit read, no sign-up, no refresh.
    @Test("With the model off, neither credential is ever asked for")
    func credentialsAreNeverRequested() async throws {
        let asked = CredentialCounter()
        let ai = RemoteForgeAI(
            config: configured,
            token: { await asked.token() },
            entitlement: { await asked.entitlement() }
        )

        var brief = AIBrief()
        brief.activities = [
            ScheduledActivity(id: "read", name: "Read", startMinute: nil, minutes: 15, weekdays: []),
        ]
        brief.week = ReviewFacts(kept: 3, asked: 7)
        _ = try await ai.plan(brief: brief, request: "plan my week")
        _ = try await ai.reading(brief: brief)
        _ = try await ai.challenge(brief: brief, difficulty: .medium, focus: .discipline, wish: "")

        #expect(await asked.tokens == 0)
        #expect(await asked.entitlements == 0)
    }

    // MARK: - The one host

    /// Changing this list is changing the privacy labels. See `ForgeNetwork`.
    @Test("TelemetryDeck's ingest host is the only one Forge may reach")
    func onlyTelemetryDeck() {
        #expect(ForgeNetwork.allowedHosts == ["nom.telemetrydeck.com"])
        #expect(ForgeTelemetry.host == "nom.telemetrydeck.com")
        #expect(ForgeNetwork.permits(URL(string: "https://nom.telemetrydeck.com/v2/")))

        for other in [
            "https://example.supabase.co/rest/v1/days",
            "https://api.anthropic.com/v1/messages",
            "https://forgebetter.app/privacy",
            // Not https.
            "http://nom.telemetrydeck.com/v2/",
            // A suffix match would let these through.
            "https://nom.telemetrydeck.com.example.net/v2/",
            "https://evil-nom.telemetrydeck.com/",
            "https://telemetrydeck.com/",
        ] {
            #expect(!ForgeNetwork.permits(URL(string: other)), Comment(rawValue: other))
        }
        #expect(!ForgeNetwork.permits(nil))
    }

    /// The transport is the one place Forge's own code opens a connection.
    /// Anything off the list is refused before the session is touched — the
    /// tripwire standing where the network would be sees nothing — and the one
    /// host on the list gets through to it.
    @Test("A request to any other host is refused before it reaches the network")
    func otherHostsNeverLeave() async throws {
        let marker = UUID().uuidString
        let transport = URLSessionTransport(session: NetworkTripwire.session())

        for other in [
            "https://example.supabase.co/rest/v1/\(marker)",
            "https://api.anthropic.com/\(marker)",
            "http://nom.telemetrydeck.com/\(marker)",
        ] {
            let request = URLRequest(url: URL(string: other)!)
            await #expect(throws: BackendError.notConfigured) {
                _ = try await transport.send(request)
            }
        }
        #expect(NetworkTripwire.requests(containing: marker).isEmpty)

        let allowed = URLRequest(url: URL(string: "https://nom.telemetrydeck.com/\(marker)")!)
        let (_, response) = try await transport.send(allowed)
        #expect(response.statusCode == 200)
        #expect(NetworkTripwire.requests(containing: marker).map(\.host) == ["nom.telemetrydeck.com"])
    }

    /// The whole of the telemetry is behind this. A test run that could send a
    /// signal would be a test run reaching the network.
    @Test("Telemetry is silent under test")
    func telemetryIsInertUnderTest() {
        #expect(ForgeTelemetry.isRunningTests)
        #expect(!ForgeTelemetry.isActive)
        // And sending is a no-op rather than a crash or a queue.
        ForgeTelemetry.send(.dayEarned)
    }
}

/// A `URLProtocol` standing where the network would be. It answers every
/// request with an empty 200 and writes down what it was asked for, so a test
/// can prove what did — and did not — try to leave.
final class NetworkTripwire: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [URL] = []

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NetworkTripwire.self]
        return URLSession(configuration: configuration)
    }

    static func requests(containing marker: String) -> [URL] {
        lock.lock(); defer { lock.unlock() }
        return seen.filter { $0.absoluteString.contains(marker) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let url = request.url {
            Self.lock.lock()
            Self.seen.append(url)
            Self.lock.unlock()
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://invalid")!,
            statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - What telemetry says

/// The event list and what each one may carry. Nothing here sends anything —
/// see `NoNetworkTests.telemetryIsInertUnderTest` — so what is tested is the
/// payload that *would* be built.
@Suite("Telemetry")
struct TelemetryTests {

    /// One of every event, with a value in each slot.
    private let every: [ForgeTelemetry.Event] = [
        .appFirstOpen,
        .onboardingBeatView(.doOne),
        .onboardingFocusChosen(count: 2),
        .onboardingCompleted,
        .firstPullCompleted,
        .activityCompleted(.honor),
        .dayEarned,
        .pullAbandoned,
        .challengeAccepted,
        .challengeCompleted,
        .activityAdded(.library),
        .notificationOpened(.morning),
        .weeklyReviewCompleted,
        .reentryShown,
        .reentryRecovered,
        .chapterClosed,
        .paywallView(.firstBlade),
        .paywallDismissed(.weeklyReading),
        .trialStarted(.annual),
        .purchaseCompleted(.lifetime),
        .restoreTapped,
    ]

    @Test("The event names are exactly the agreed list")
    func names() {
        #expect(every.map(\.name) == [
            "app_first_open", "onboarding_beat_view", "onboarding_focus_chosen",
            "onboarding_completed", "first_pull_completed", "activity_completed",
            "day_earned", "pull_abandoned", "challenge_accepted",
            "challenge_completed", "activity_added", "notification_opened",
            "weekly_review_completed", "reentry_shown", "reentry_recovered",
            "chapter_closed", "paywall_view", "paywall_dismissed",
            "trial_started", "purchase_completed", "restore_tapped",
        ])
    }

    /// The only keys that may ever appear. There is no key an activity name,
    /// a sentence somebody wrote or a health reading could arrive under.
    @Test("Every payload carries only closed values and the install's age")
    func payloadsAreClosed() {
        let allowed: Set<String> = [
            "beat", "count", "method", "source", "kind", "door", "plan", "days_since_install",
        ]
        for event in every {
            let payload = ForgeTelemetry.payload(for: event, daysSinceInstall: 3)
            #expect(Set(payload.keys).isSubset(of: allowed), Comment(rawValue: event.name))
            #expect(payload["days_since_install"] == "3", Comment(rawValue: event.name))
        }
        #expect(ForgeTelemetry.Event.onboardingBeatView(.doOne).parameters == ["beat": "do_one"])
        #expect(ForgeTelemetry.Event.activityCompleted(.basic).parameters == ["method": "basic"])
        #expect(ForgeTelemetry.Event.notificationOpened(.review).parameters == ["kind": "review"])
        #expect(ForgeTelemetry.Event.purchaseCompleted(.annual).parameters == ["plan": "annual"])
        #expect(ForgeTelemetry.Event.onboardingFocusChosen(count: 0).parameters == ["count": "0"])
    }

    @Test("A missing install age reads as zero, never as nothing")
    func installAgeDefaults() {
        #expect(ForgeTelemetry.payload(for: .dayEarned, daysSinceInstall: nil)["days_since_install"] == "0")
        #expect(ForgeTelemetry.payload(for: .dayEarned, daysSinceInstall: -4)["days_since_install"] == "0")
    }

    @Test("Every first-run beat before the end is named, and the end is not")
    func beats() {
        #expect(ForgeTelemetry.Beat(.promise) == .promise)
        #expect(ForgeTelemetry.Beat(.doOne) == .doOne)
        #expect(ForgeTelemetry.Beat(.closing) == .closing)
        #expect(ForgeTelemetry.Beat(.finished) == nil)
    }

    /// Derived from the record, so nothing new is stored to know it.
    @Test("days_since_install is read off the oldest record")
    func installAgeIsDerived() {
        let progress = ProgressStore(
            defaults: UserDefaults(suiteName: "forge.tests.\(UUID().uuidString)") ?? .standard
        )
        #expect(progress.firstRecordedDay == nil)
        #expect(progress.daysSinceFirstRecord == 0)

        let first = progress.currentDay.adding(days: -9)
        progress.record(DayRecord(day: first, plannedIDs: ["water"]))
        progress.record(DayRecord(day: progress.currentDay.adding(days: -2), plannedIDs: ["water"]))
        #expect(progress.firstRecordedDay == first)
        #expect(progress.daysSinceFirstRecord == 9)
    }
}

/// Counts how often `RemoteForgeAI` reaches for its credentials.
actor CredentialCounter {
    private(set) var tokens = 0
    private(set) var entitlements = 0

    func token() -> String? {
        tokens += 1
        return "a-valid-looking-token"
    }

    func entitlement() -> String? {
        entitlements += 1
        return "a-valid-looking-transaction"
    }
}

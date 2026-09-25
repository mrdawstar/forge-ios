import Foundation
import Testing
@testable import Forge

/// The daily challenge: the same one all day, a different one tomorrow, and the
/// same one on two phones.
///
/// All three of those are properties of the *selection*, which is why it is a
/// pure function of a date rather than a random draw with a cursor beside it.
/// Everything here checks that function, plus the state machine that sits on top
/// of it and the one rule the free tier depends on — that nothing is locked.
@Suite("Daily challenge")
struct ChallengeTests {

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> ForgeDay {
        ForgeDay(year: year, month: month, day: dayOfMonth)
    }

    // MARK: - Choosing

    @Test("The same day always gives the same challenge")
    func stableWithinADay() {
        let today = day(2026, 8, 9)
        let first = ChallengeCatalog.challenge(for: today)
        for _ in 0..<50 {
            #expect(ChallengeCatalog.challenge(for: today).id == first.id)
        }
    }

    /// The context is read once, when the day turns over, and written down. A
    /// challenge that changed because somebody added a run at four in the
    /// afternoon would break the one promise this feature makes.
    @Test("Editing the day does not change the challenge already offered")
    func contextIsReadOnce() {
        let suite = UserDefaults(suiteName: "forge.tests.challenge.\(UUID().uuidString)")!
        var context = ChallengeContext()
        let challenges = ChallengeStore(
            progress: ProgressStore(defaults: suite),
            defaults: suite,
            context: { context }
        )
        let offered = challenges.today.challenge.id

        context = ChallengeContext(activities: ["Morning run", "Gym"])
        challenges.rollOver()
        #expect(challenges.today.challenge.id == offered)
    }

    /// The one property a `hashValue`-based index would have quietly broken:
    /// Swift seeds string and integer hashing per process, so a catalogue
    /// indexed by it hands somebody a new challenge every time they reopen the
    /// app. The mixing in `ChallengeCatalog.index` is written out for exactly
    /// this reason — see the note there.
    @Test("The index is arithmetic, not a per-process hash")
    func indexIsStableAcrossRuns() {
        // Worked out by hand from the FNV-1a constants, so this test fails if
        // the mixing changes rather than merely agreeing with whatever it does.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in [UInt64(2026), UInt64(8), UInt64(9)] {
            hash = (hash ^ byte) &* 0x1000_0000_01b3
        }
        let expected = Int(hash % UInt64(ChallengeCatalog.all.count))
        #expect(ChallengeCatalog.index(for: day(2026, 8, 9), count: ChallengeCatalog.all.count) == expected)
    }

    @Test("Consecutive days are not all the same challenge")
    func rotatesAcrossAMonth() {
        var seen: Set<String> = []
        for offset in 0..<31 {
            seen.insert(ChallengeCatalog.challenge(for: day(2026, 8, 1).adding(days: offset)).id)
        }
        // Not "all thirty-one differ" — a hash is allowed to collide, and
        // demanding otherwise would be testing luck. What matters is that a
        // month is not three challenges on a loop.
        #expect(seen.count >= 20)
    }

    @Test("Every focus and difficulty is somewhere in the catalogue")
    func catalogueCoversTheGrid() {
        for focus in ChallengeFocus.allCases {
            #expect(ChallengeCatalog.all.contains { $0.focus == focus })
        }
        for difficulty in ChallengeDifficulty.allCases {
            #expect(ChallengeCatalog.all.contains { $0.difficulty == difficulty })
        }
        // Ids are what persistence is keyed on; two challenges sharing one would
        // make a completed day ambiguous.
        #expect(Set(ChallengeCatalog.all.map(\.id)).count == ChallengeCatalog.all.count)
    }

    // MARK: - The state machine

    private func store() -> ChallengeStore {
        let suite = UserDefaults(suiteName: "forge.tests.challenge.\(UUID().uuidString)")!
        return ChallengeStore(
            progress: ProgressStore(defaults: suite),
            defaults: suite
        )
    }

    @Test("Everybody starts with a challenge, unanswered")
    func startsOffered() {
        let challenges = store()
        #expect(challenges.today.state == .offered)
        #expect(challenges.today.challenge.title.isEmpty == false)
    }

    @Test("Accept, skip and complete each move the state")
    func moves() {
        let challenges = store()
        challenges.accept()
        #expect(challenges.today.state == .accepted)
        challenges.skip()
        #expect(challenges.today.state == .skipped)
        challenges.accept()
        #expect(challenges.today.state == .accepted)
        challenges.complete()
        #expect(challenges.today.state == .completed)
        #expect(challenges.today.completedAt != nil)
    }

    /// The rule that changed: a mis-tap on Done used to be permanent until four
    /// in the morning, which is a worse failure than the one the old rule was
    /// protecting against. Nothing is scored, so nothing can be falsified.
    @Test("A completed challenge can be taken back")
    func completionIsReversible() {
        let challenges = store()
        challenges.complete()
        #expect(challenges.today.state == .completed)

        challenges.undoCompletion()
        // Back to accepted, not offered: they took it on and have not finished.
        #expect(challenges.today.state == .accepted)
        #expect(challenges.today.completedAt == nil)

        // And it only ever undoes a completion.
        challenges.undoCompletion()
        #expect(challenges.today.state == .accepted)
    }

    @Test("A challenge survives being reloaded on the same day")
    func persists() {
        let suite = UserDefaults(suiteName: "forge.tests.challenge.\(UUID().uuidString)")!
        let progress = ProgressStore(defaults: suite)

        let first = ChallengeStore(progress: progress, defaults: suite)
        first.accept()
        let id = first.today.challenge.id

        let second = ChallengeStore(progress: progress, defaults: suite)
        #expect(second.today.challenge.id == id)
        #expect(second.today.state == .accepted)
    }


    /// What somebody types has to reach the shelf, or the field is decoration.
    @Test("What you ask for picks the challenge off the shelf")
    func wishSteersThePick() {
        let shelf = ChallengeCatalog.discipline
        let picked = LocalForgeAI.bestMatch(for: "something about negotiating with myself", in: shelf)
        #expect(picked?.id == "ch.disc.cold")
        // Nothing in common is nil rather than a shrug-shaped answer, so the
        // caller can fall back deliberately.
        #expect(LocalForgeAI.bestMatch(for: "xylophone", in: shelf) == nil)
        #expect(LocalForgeAI.bestMatch(for: "", in: shelf) == nil)
    }

    @Test("Nothing behind the AI screens claims to be a model")
    func stubIsHonest() {
        #expect(LocalForgeAI().isConnected == false)
    }
}

// MARK: -

extension ScheduledActivity {
    /// A bare activity, for tests that care about one field at a time.
    static func stub(
        _ name: String,
        at start: Int? = nil,
        minutes: Int = 0,
        on weekdays: Set<Int> = Set(1...7)
    ) -> ScheduledActivity {
        ScheduledActivity(
            id: name.lowercased(),
            name: name,
            startMinute: start,
            minutes: minutes,
            weekdays: weekdays
        )
    }
}

/// The arithmetic a plan is made of.
///
/// This is the type the review screen previews and the view model applies, so
/// these are the tests that keep those two honest about each other — a preview
/// that disagreed with what "Apply" did would be the worst bug this feature
/// could have.
@Suite("Schedule plans")
struct SchedulePlanTests {

    private let week: [ScheduledActivity] = [
        .stub("Read", at: 20 * 60, minutes: 20),
        .stub("Train", minutes: 45, on: [2, 4, 6]),
    ]

    @Test("Projecting applies each kind of change")
    func projects() {
        let plan = SchedulePlan(
            summary: "",
            changes: [
                .time(id: "train", name: "Train", minute: 18 * 60, was: nil),
                .duration(id: "read", name: "Read", minutes: 30, was: 20),
                .days(id: "read", name: "Read", weekdays: [2, 3], was: Set(1...7)),
            ]
        )
        let after = plan.projected(onto: week)
        #expect(after.first { $0.id == "train" }?.startMinute == 18 * 60)
        #expect(after.first { $0.id == "read" }?.minutes == 30)
        #expect(after.first { $0.id == "read" }?.weekdays == [2, 3])
    }

    /// A plan is read off a snapshot and the week is allowed to have moved
    /// under it, so a change naming something that is gone is skipped rather
    /// than crashing or inventing a row.
    @Test("A change naming an activity that is gone is ignored")
    func toleratesAMissingActivity() {
        let plan = SchedulePlan(
            summary: "",
            changes: [.time(id: "ghost", name: "Ghost", minute: 600, was: nil)]
        )
        #expect(plan.projected(onto: week).count == week.count)
    }

    @Test("A created activity shows up in the projection")
    func projectsACreation() {
        var draft = ActivityDraft.blank(named: "Cold shower")
        draft.startMinute = 7 * 60
        draft.repeats = RitualRepeat(weekdays: [2])
        let plan = SchedulePlan(summary: "", changes: [.create(draft: draft)])

        let after = plan.projected(onto: week)
        #expect(after.count == 3)
        #expect(after.last?.name == "Cold shower")
        #expect(after.last?.startMinute == 7 * 60)
    }

    /// Monday first, seven days, each in clock order and holding only what
    /// belongs to it.
    @Test("The week reads Monday first and in clock order")
    func buildsTheWeek() {
        let days = SchedulePlan(summary: "", changes: [
            .time(id: "train", name: "Train", minute: 7 * 60, was: nil),
        ]).week(onto: week)

        #expect(days.count == 7)
        #expect(days.map(\.weekday) == [2, 3, 4, 5, 6, 7, 1])
        // Monday holds both, training first because it is now at seven.
        #expect(days[0].items.map(\.name) == ["Train", "Read"])
        // Tuesday is a rest day for training.
        #expect(days[1].items.map(\.name) == ["Read"])
    }

    @Test("An empty weekday set means every day, as it does everywhere else")
    func emptyMeansDaily() {
        let anytime = ScheduledActivity.stub("Water", on: [])
        let days = SchedulePlan(summary: "", changes: []).week(onto: [anytime])
        #expect(days.allSatisfy { $0.items.count == 1 })
    }
}

/// The local stand-in for a model, which has to behave itself because every AI
/// screen in the app is currently driven by it.
@Suite("Local planner")
struct LocalPlannerTests {

    private func window(_ request: String) -> [Int]? {
        LocalForgeAI.window(in: request).map { [$0.start, $0.end] }
    }

    @Test("A stated window is read out of plain English")
    func readsAWindow() {
        #expect(window("I have work from 9 to 17") == [540, 1020])
        #expect(window("09:30-17:00") == [570, 1020])
        // Nine to five means the afternoon, which is the single most common way
        // anybody says this.
        #expect(window("work 9 until 5") == [540, 1020])
        #expect(window("9 am to 5 pm") == [540, 1020])
        #expect(window("Plan my day") == nil)
        // Backwards, and out of range: neither is a window.
        #expect(window("from 17 to 9") == nil)
        #expect(window("from 44 to 55") == nil)
    }

    // MARK: - Laying out a week

    private let brief = AIBrief(
        activities: [
            .stub("Read", minutes: 20),
            .stub("Train", minutes: 45),
            .stub("Build", minutes: 60),
        ],
        wakeMinutes: 7 * 60
    )

    @Test("Nothing is planned inside the hours you said you were busy")
    func respectsTheWindow() async throws {
        let plan = try await LocalForgeAI().plan(
            brief: brief,
            request: "I work from 9 to 17 and want to train three times and read every evening"
        )
        let after = plan.projected(onto: brief.activities)
        for activity in after {
            guard let start = activity.startMinute else { continue }
            let end = start + max(activity.minutes, 1)
            #expect(start >= 17 * 60 || end <= 9 * 60)
        }
        #expect(plan.isModelWritten == false)
    }

    /// The single most useful thing this does without a model: "three times"
    /// becomes three days that are not next to each other.
    @Test("A stated frequency becomes days with rest between them")
    func spreadsSessions() async throws {
        let plan = try await LocalForgeAI().plan(
            brief: brief,
            request: "I work from 9 to 17 and want to train three times and read every evening"
        )
        let after = plan.projected(onto: brief.activities)
        #expect(after.first { $0.id == "train" }?.weekdays == [2, 4, 6])
        // "every evening" is seven, and it is read from the clause around the
        // activity's own name rather than from the sentence as a whole.
        #expect(after.first { $0.id == "read" }?.weekdays == Set(1...7))
    }

    @Test("Frequency is read per activity, not per sentence")
    func frequencyIsLocal() {
        let request = "train three times and read every evening"
        #expect(LocalForgeAI.frequency(for: "Train", in: request) == 3)
        #expect(LocalForgeAI.frequency(for: "Read", in: request) == 7)
        #expect(LocalForgeAI.frequency(for: "Build", in: request) == nil)
    }

    @Test("Sessions are spread rather than stacked")
    func spread() {
        #expect(LocalForgeAI.spread(2) == [3, 6])
        #expect(LocalForgeAI.spread(3) == [2, 4, 6])
        #expect(LocalForgeAI.spread(5) == RitualRepeat.weekdays5.weekdays)
        #expect(LocalForgeAI.spread(9) == Set(1...7))
        #expect(LocalForgeAI.spread(0) == [4])
    }

    /// Somebody who set an activity to six in the morning meant it, and a
    /// planner that reshuffles what it was not asked about is one nobody
    /// presses twice.
    @Test("A time that already works is left alone")
    func keepsAGoodTime() async throws {
        let settled = AIBrief(
            activities: [.stub("Read", at: 6 * 60, minutes: 20), .stub("Train", minutes: 45)],
            wakeMinutes: 7 * 60
        )
        let plan = try await LocalForgeAI().plan(brief: settled, request: "plan my week")
        #expect(plan.changes.contains { $0.activityName == "Train" })
        #expect(plan.changes.contains { $0.activityName == "Read" } == false)
    }

    // MARK: - Adjusting

    @Test("Everything an hour later moves only what has a time")
    func shiftsTheWeek() async throws {
        let mixed = AIBrief(activities: [.stub("Read", at: 20 * 60), .stub("Train")])
        let plan = try await LocalForgeAI().plan(brief: mixed, request: "everything an hour later")
        #expect(plan.changes.count == 1)
        #expect(plan.projected(onto: mixed.activities).first?.startMinute == 21 * 60)
    }

    @Test("An offset is read with its direction")
    func readsAnOffset() {
        #expect(LocalForgeAI.shift(in: "everything an hour later") == 60)
        #expect(LocalForgeAI.shift(in: "push everything back 30 minutes") == 30)
        #expect(LocalForgeAI.shift(in: "start two hours earlier") == -120)
        // No direction, or both, is not an instruction.
        #expect(LocalForgeAI.shift(in: "an hour") == nil)
        #expect(LocalForgeAI.shift(in: "plan my week") == nil)
    }

    @Test("Moving one activity to a day changes only that activity")
    func movesOne() async throws {
        let plan = try await LocalForgeAI().plan(brief: brief, request: "move my train to wednesday")
        #expect(plan.changes.count == 1)
        #expect(plan.projected(onto: brief.activities).first { $0.id == "train" }?.weekdays == [4])
    }

    @Test("A weekday is found by name or abbreviation")
    func readsAWeekday() {
        #expect(LocalForgeAI.weekday(in: "move it to wednesday") == 4)
        #expect(LocalForgeAI.weekday(in: "on sat") == 7)
        #expect(LocalForgeAI.weekday(in: "sometime soon") == nil)
    }

    // MARK: - Refusing

    /// The rule that keeps this honest: anything it cannot genuinely do is
    /// declined by name rather than answered with a guess.
    @Test("A request it cannot understand is refused, not guessed at")
    func refusesHonestly() async {
        await #expect(throws: ForgeAIError.notConnected) {
            _ = try await LocalForgeAI().plan(
                brief: AIBrief(activities: [.stub("Read")]),
                request: "give me more time for my app"
            )
        }
    }

    @Test("An empty week cannot be planned")
    func refusesAnEmptyWeek() async {
        await #expect(throws: ForgeAIError.nothingToPlan) {
            _ = try await LocalForgeAI().plan(brief: AIBrief(), request: "plan my week")
        }
    }

    @Test("A plan that would change nothing says so")
    func refusesANoOp() async {
        let settled = AIBrief(activities: [.stub("Read", at: 7 * 60, minutes: 20)], wakeMinutes: 6 * 60)
        await #expect(throws: ForgeAIError.noChange) {
            _ = try await LocalForgeAI().plan(brief: settled, request: "plan my week")
        }
    }
}

/// Small things that decide whether a generated day looks written or computed.
@Suite("Planner polish")
struct PlannerPolishTests {

    @Test("Placements land on the fives")
    func roundsToFives() async throws {
        let brief = AIBrief(
            activities: [
                .stub("Water", minutes: 1),
                .stub("Bed", minutes: 0),
                .stub("Teeth", minutes: 2),
            ],
            wakeMinutes: 7 * 60
        )
        let plan = try await LocalForgeAI().plan(brief: brief, request: "plan my week")
        for case .time(_, _, let minute, _) in plan.changes {
            #expect(minute % 5 == 0, "\(ClockMinute.label(minute)) is not on a five")
        }
    }

    /// Rounding must never round *into* the commitment it was told to avoid.
    @Test("Rounding up cannot push an activity into a busy window")
    func roundingRespectsTheWindow() async throws {
        let brief = AIBrief(
            activities: [.stub("Water", minutes: 1), .stub("Long", minutes: 90)],
            wakeMinutes: 7 * 60
        )
        let plan = try await LocalForgeAI().plan(brief: brief, request: "I work 9 to 17")
        for activity in plan.projected(onto: brief.activities) {
            guard let start = activity.startMinute else { continue }
            #expect(start + max(activity.minutes, 1) <= 9 * 60 || start >= 17 * 60)
        }
    }
}

/// Whether the day's challenge is about the day.
@Suite("Challenge context")
struct ChallengeContextTests {

    @Test("An activity's own name says what it is for")
    func readsNames() {
        #expect(ChallengeContext(activities: ["Morning run"]).leanings == [.physical])
        #expect(ChallengeContext(activities: ["Deep work"]).leanings == [.ambition])
        #expect(ChallengeContext(activities: ["Read 10 pages"]).leanings == [.intellect])
        #expect(ChallengeContext(activities: ["Cold shower"]).leanings == [.discipline])
    }

    /// A day that genuinely leans two ways keeps both rather than having one
    /// picked for it by an arbitrary rule.
    @Test("A day with two signals leans both ways")
    func keepsTies() {
        let both = ChallengeContext(activities: ["Morning run", "Deep work"]).leanings
        #expect(both == [.physical, .ambition])
    }

    /// The name outranks the category, because a "Cold shower" filed under
    /// Physical is obviously not a training challenge's neighbour.
    @Test("A name outranks the category it is filed under")
    func nameBeatsCategory() {
        let context = ChallengeContext(activities: ["Cold shower"], categories: [.physical])
        #expect(context.leanings == [.discipline])
    }

    @Test("A day that says nothing leans nowhere")
    func staysNeutral() {
        #expect(ChallengeContext().leanings.isEmpty)
        #expect(ChallengeContext(activities: ["Zzz"]).leanings.isEmpty)
        // And an unweighted shelf is the whole catalogue, so nothing is lost.
        #expect(ChallengeCatalog.weighted(by: ChallengeContext()).count == ChallengeCatalog.all.count)
    }

    /// Leaning, not filtering: every challenge stays reachable, and a day of
    /// training still lands on Physical most of the time.
    @Test("Weighting leans without locking anything out")
    func leansWithoutFiltering() {
        let context = ChallengeContext(activities: ["Morning run"])
        let shelf = ChallengeCatalog.weighted(by: context)
        #expect(Set(shelf.map(\.id)) == Set(ChallengeCatalog.all.map(\.id)))

        // About half: often enough to read as "it noticed", rare enough that a
        // runner still meets the rest of the catalogue. See `leaningWeight`.
        let share = Double(shelf.count { $0.focus == .physical }) / Double(shelf.count)
        #expect(share > 0.45)
        #expect(share < 0.6)
    }

    /// Across a month a runner should still meet other kinds of challenge —
    /// six Physical prompts on a loop is the other way to be repetitive.
    @Test("A leaning day still varies across a month")
    func staysVaried() {
        let context = ChallengeContext(activities: ["Morning run"])
        var seen: Set<String> = []
        var focuses: Set<ChallengeFocus> = []
        for offset in 0..<31 {
            let picked = ChallengeCatalog.challenge(
                for: ForgeDay(year: 2026, month: 8, day: 1).adding(days: offset),
                context: context
            )
            seen.insert(picked.id)
            focuses.insert(picked.focus)
        }
        #expect(seen.count >= 12)
        #expect(focuses.count >= 2)
    }
}

/// A heading in the day list is the user's word or it is not drawn.
@Suite("Day part headings")
struct DayPartHeadingTests {

    @Test("A world's own movement name is not a heading")
    func worldNameIsSilent() {
        let part = DayPart(name: "When it lets go", activities: ["read"], origin: "When it lets go")
        #expect(part.isUserNamed == false)
    }

    @Test("A renamed part is the user's, and shows")
    func renamedShows() {
        let part = DayPart(name: "My evenings", activities: ["read"], origin: "When it lets go")
        #expect(part.isUserNamed)
    }

    @Test("A part the user built has no origin and shows")
    func ownPartShows() {
        #expect(DayPart(name: "Mornings", activities: ["read"]).isUserNamed)
        // Except an unnamed one, which was never a heading.
        #expect(DayPart(name: "", activities: ["read"]).isUserNamed == false)
    }
}

/// New activities start on one day.
@Suite("New activity defaults")
struct NewActivityDefaultTests {

    @Test("One day only, not every day")
    func oneDay() {
        let thursday = RitualRepeat.onlyToday(5)
        #expect(thursday.weekdays == [5])
        #expect(thursday.isDaily == false)
        #expect(thursday.includes(5))
        #expect(thursday.includes(4) == false)
    }
}

// MARK: - The wall

/// The quotations, and the one rule that makes them shippable: every line is
/// something the named source is reliably documented as having said. Nothing
/// here can check *that* — it is a matter of sourcing, not of code — so these
/// check the properties that keep the system honest around it: nothing is blank,
/// nothing is unattributed, nothing is duplicated, and the same day says the same
/// thing on every device.
@MainActor
@Suite("Forge quotes")
struct ForgeQuoteTests {

    private func day(_ year: Int, _ month: Int, _ day: Int) -> ForgeDay {
        ForgeDay(year: year, month: month, day: day)
    }

    @Test("Every line has words and a name")
    func everyQuoteIsAttributed() {
        #expect(!ForgeQuotes.all.isEmpty)
        for quote in ForgeQuotes.all {
            #expect(!quote.text.trimmingCharacters(in: .whitespaces).isEmpty)
            #expect(!quote.source.trimmingCharacters(in: .whitespaces).isEmpty, Comment(rawValue: quote.id.description))
            // An attribution that is only a first name, or a bare "Anonymous",
            // is the shape of a quotation nobody checked.
            #expect(quote.source.count > 3, Comment(rawValue: quote.id.description))
        }
    }

    @Test("No line and no id appears twice")
    func quotesAreUnique() {
        #expect(Set(ForgeQuotes.all.map(\.id)).count == ForgeQuotes.all.count)
        #expect(Set(ForgeQuotes.all.map(\.text)).count == ForgeQuotes.all.count)
    }

    @Test("Every theme has something to say")
    func everyThemeIsStocked() {
        for theme in QuoteTheme.allCases {
            #expect(ForgeQuotes.quotes(for: theme).count >= 3, Comment(rawValue: theme.rawValue))
        }
    }

    /// The same reason `QuoteBook` is arithmetic: a line that differs between a
    /// phone and an iPad is the app admitting the moment is decorative.
    @Test("The same day says the same thing")
    func quotesAreDeterministic() {
        let moment = EarnedMoment.day(leaning: .physical)
        let first = ForgeQuotes.quote(for: moment, on: day(2026, 8, 10))
        for _ in 0..<50 {
            #expect(ForgeQuotes.quote(for: moment, on: day(2026, 8, 10)).id == first.id)
        }
    }

    @Test("Consecutive days are not all the same line")
    func quotesRotate() {
        var seen: Set<String> = []
        for offset in 0..<14 {
            let on = day(2026, 8, 1).adding(days: offset)
            seen.insert(ForgeQuotes.quote(for: .day(leaning: nil), on: on).id)
        }
        #expect(seen.count > 1)
    }

    // MARK: What a line is about

    @Test("A finished challenge is always about toughness")
    func challengesDrawFromToughness() {
        for focus in ChallengeFocus.allCases {
            #expect(EarnedMoment.challenge(focus).theme == .toughness)
            let quote = ForgeQuotes.quote(for: .challenge(focus), on: day(2026, 8, 10))
            #expect(ForgeQuotes.toughness.contains(quote))
        }
    }

    @Test(
        "The day's own leaning decides what the line is about",
        arguments: [
            (ChallengeFocus.physical, QuoteTheme.resilience),
            (.ambition, .focus),
            (.intellect, .focus),
            (.discipline, .discipline),
            (.relationship, .action),
            (.mental, .perseverance),
        ]
    )
    func dayThemeFollowsTheLeaning(leaning: ChallengeFocus, theme: QuoteTheme) {
        #expect(EarnedMoment.day(leaning: leaning).theme == theme)
        let quote = ForgeQuotes.quote(for: .day(leaning: leaning), on: day(2026, 8, 10))
        #expect(ForgeQuotes.quotes(for: theme).contains(quote))
    }

    /// A day that says nothing about itself still earns a sentence. This is the
    /// one path that must never come back empty — most first weeks take it.
    @Test("A day with no leaning still gets a line")
    func silentDaysStillSpeak() {
        #expect(EarnedMoment.day(leaning: nil).theme == .perseverance)
        let quote = ForgeQuotes.quote(for: .day(leaning: nil), on: day(2026, 8, 10))
        #expect(ForgeQuotes.perseverance.contains(quote))
    }

    // MARK: Where it ends up

    @Test("The earned summary carries the line, and the resting one does not")
    func summaryCarriesTheQuote() {
        let quote = ForgeQuotes.quote(for: .day(leaning: .physical), on: day(2026, 8, 10))
        let earned = DaySummary.make(daysKept: 12, quote: quote)
        #expect(earned.quote == quote)
        #expect(earned.headline == "Twelve days.")

        // What the freed panel shows for the rest of the day is Forge's own
        // sentence and nothing borrowed.
        #expect(DaySummary.make(daysKept: 12).quote == nil)
    }
}

// MARK: - Why this challenge

/// The sentence under a challenge that says the day was read.
@MainActor
@Suite("Challenge reasons")
struct ChallengeReasonTests {

    private func day(_ day: Int) -> ForgeDay {
        ForgeDay(year: 2026, month: 8, day: day)
    }

    @Test("The catalogue is ten per aim")
    func catalogueIsBalanced() {
        for focus in ChallengeFocus.allCases {
            #expect(ChallengeCatalog.all.count { $0.focus == focus } == 10, Comment(rawValue: focus.rawValue))
        }
        #expect(ChallengeCatalog.all.count == 60)
    }

    /// The six aims are the six dimensions, and nothing may quietly reintroduce
    /// a seventh vocabulary — see `ChallengeFocus`.
    @Test("Every aim is one of the six, and every one of the six has an aim")
    func aimsAreTheSix() {
        #expect(Set(ChallengeFocus.allCases.map(\.category)) == Set(RitualCategory.dimensions))
        #expect(ChallengeFocus.allCases.map(\.category) == RitualCategory.dimensions)
        for dimension in RitualCategory.dimensions {
            #expect(ChallengeFocus(dimension) != nil, Comment(rawValue: dimension.rawValue))
        }
    }

    /// The pager on the sheet. Six cards, one per part of a person, in the order
    /// the Shape draws them — and the same six on two phones, because it is
    /// arithmetic on the date rather than a draw.
    @Test("Browsing offers one per aim, in the order of the six, never twice")
    func browsingIsOnePerAim() {
        let today = day(9)
        let chosen = ChallengeCatalog.challenge(for: today)
        let cards = ChallengeCatalog.browse(for: today, including: chosen)

        #expect(cards.count == ChallengeFocus.allCases.count)
        #expect(cards.map(\.focus) == ChallengeFocus.allCases)
        #expect(cards.map(\.focus.category) == RitualCategory.dimensions)
        #expect(Set(cards.map(\.id)).count == cards.count, "a card is offered twice")
        // Today's sits in its own dimension's slot rather than leading.
        #expect(cards.first { $0.focus == chosen.focus }?.id == chosen.id)
    }

    /// The property the leading-card version got wrong: taking a card must not
    /// move any other card, or the pager's offset and its state disagree.
    @Test("Taking a card leaves every slot where it was")
    func takingDoesNotReorder() {
        let today = day(9)
        let before = ChallengeCatalog.browse(for: today, including: ChallengeCatalog.challenge(for: today))
        guard let taken = before.first(where: { $0.focus != before[0].focus }) else {
            Issue.record("nothing to take")
            return
        }
        let after = ChallengeCatalog.browse(for: today, including: taken)

        #expect(after.map(\.focus) == before.map(\.focus))
        #expect(after.firstIndex(of: taken) == before.firstIndex(of: taken))
    }

    @Test("The same day always offers the same six")
    func browsingIsStable() {
        let today = day(17)
        let first = ChallengeCatalog.browse(for: today).map(\.id)
        for _ in 0..<20 {
            #expect(ChallengeCatalog.browse(for: today).map(\.id) == first)
        }
        // And the salt actually moves them: six shelves of the same length
        // indexed by an unsalted date would all be the same rung of their own.
        let rungs = ChallengeCatalog.browse(for: today).map { card -> Int? in
            ChallengeCatalog.all.filter { $0.focus == card.focus }.firstIndex(of: card)
        }
        #expect(Set(rungs).count > 1, "every aim landed on the same rung")
    }

    /// The salted index must not have moved the day's own challenge, which is
    /// the one thing about this feature that people would notice.
    @Test("Salting the index left the unsalted one exactly where it was")
    func saltDoesNotMoveTheDay() {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in [UInt64(2026), UInt64(8), UInt64(9)] {
            hash = (hash ^ byte) &* 0x1000_0000_01b3
        }
        #expect(ChallengeCatalog.index(for: day(9), count: 97) == Int(hash % 97))
    }

    /// Taking one from the pager replaces today's rather than adding a second,
    /// and it arrives taken on.
    @Test("Taking an alternate replaces today's challenge")
    func takingAnAlternate() {
        let suite = UserDefaults(suiteName: "forge.tests.challenge.\(UUID().uuidString)")!
        let challenges = ChallengeStore(
            progress: ProgressStore(defaults: suite),
            defaults: suite
        )
        let was = challenges.today.challenge
        guard let other = challenges.browsable().first(where: { $0.focus != was.focus }) else {
            Issue.record("nothing to browse")
            return
        }

        challenges.take(other)
        #expect(challenges.today.challenge.id == other.id)
        #expect(challenges.today.state == .accepted)
        // One a day: the one it replaced is not still on the day.
        #expect(challenges.today.challenge.id != was.id)
        // The aim it displaced is back on the shelf. What is not kept is the
        // exact challenge: the day's own is drawn from the whole weighted
        // catalogue and the pager draws one rung per aim, so swapping back
        // returns a challenge of that aim rather than that challenge.
        #expect(challenges.browsable().contains { $0.focus == was.focus })
        #expect(challenges.browsable().count == ChallengeFocus.allCases.count)

        // Taking the one already showing changes nothing, so it cannot reset a
        // challenge somebody has finished.
        challenges.complete()
        challenges.take(other)
        #expect(challenges.today.state == .completed)
    }

    /// Ties are broken by name rather than by set order, which is not stable
    /// across launches — a line naming the day must not change when the app is
    /// restarted.
    @Test("A day that leans two ways names one of them, always the same one")
    func leaningIsStable() {
        let both = ChallengeContext(activities: ["Deep work", "Go for a run"])
        #expect(both.leanings == [.ambition, .physical])
        let named = both.leaning
        for _ in 0..<50 {
            #expect(ChallengeContext(activities: ["Deep work", "Go for a run"]).leaning == named)
        }
        #expect(named == .ambition, "alphabetical among the tied, for stability alone")
    }

    @Test("A day that says nothing names nothing")
    func silentDayHasNoLeaning() {
        #expect(ChallengeContext().leaning == nil)
    }

    /// Only when the day actually pulled it that way. A challenge that happened
    /// to land on fitness for a day of reading must not claim it was chosen for
    /// the reader.
    @Test("A challenge only claims the day when it matches it")
    func reasonOnlyWhenItMatches() {
        let context = ChallengeContext(activities: ["Deep work", "Ship the build"])
        for offset in 0..<40 {
            let chosen = ChallengeCatalog.challenge(for: day(1).adding(days: offset), context: context)
            if let reason = chosen.reason {
                #expect(chosen.focus == context.leaning)
                #expect(reason == ChallengeCatalog.reason(for: chosen.focus))
            }
        }
    }

    @Test("A day with no leaning never claims one")
    func noReasonWithoutALeaning() {
        for offset in 0..<40 {
            let chosen = ChallengeCatalog.challenge(for: day(1).adding(days: offset))
            #expect(chosen.reason == nil)
        }
    }

    /// Somewhere in a leaning month, the day gets named. The rule is worth
    /// nothing if it never fires.
    @Test("A leaning day does get told why, sometimes")
    func reasonAppearsAtAll() {
        let context = ChallengeContext(activities: ["Go for a run", "Lift something heavy"])
        let named = (0..<40).contains {
            ChallengeCatalog.challenge(for: day(1).adding(days: $0), context: context).reason != nil
        }
        #expect(named)
    }

    /// The field was added after the app shipped, and a `ChallengeDay` written
    /// by an older build has no such key. Optional is what makes that survivable
    /// — a non-optional with a default would throw and lose the whole day.
    @Test("A challenge written before reasons existed still decodes")
    func legacyChallengeDecodes() throws {
        let legacy = """
            {
              "id": "ch.disc.cold",
              "title": "Ninety seconds cold",
              "detail": "Turn it to cold.",
              "focus": "discipline",
              "difficulty": "easy",
              "isPersonal": false
            }
            """
        let decoded = try JSONDecoder().decode(DailyChallenge.self, from: Data(legacy.utf8))
        #expect(decoded.id == "ch.disc.cold")
        #expect(decoded.reason == nil)
    }
}

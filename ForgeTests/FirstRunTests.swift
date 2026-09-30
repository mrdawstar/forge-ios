import Foundation
import Testing
@testable import Forge

/// The first two minutes, and the things they must not get wrong.
///
/// **Everything written is real.** The answers are the assessment, the plan is
/// the day, the completion is in the history and the blade is a blade. There is
/// no tutorial state to clean up, which means every one of these is checking
/// the actual product rather than a rehearsal of it.
///
/// **Skipping costs nothing.** Somebody who declines to say what they are
/// building still gets a plan, drawn from their lowest answers, and the
/// identity offers still fall back to exactly what the app always offered.
@MainActor
@Suite("The first run")
struct FirstRunTests {

    /// **The trap this closes.** `hasCompletedFirstRun` is only written by the
    /// closing beat, and the beat before it is the real home screen where the
    /// first pull happens. Anything that ends the process in between — a force
    /// quit, a call, the OS reclaiming memory — used to bring the app back to
    /// the promise screen for somebody who had already kept a day. Worse, the
    /// sequence could not finish a second time: its last beat waits for the day
    /// to be earned, and today's already was.
    ///
    /// An earned day is proof the sequence was walked, so the record settles it.
    @Test("An earned day means the first run is over, whatever the flag says")
    func anEarnedDayEndsTheFirstRun() {
        let suite = UserDefaults(suiteName: "forge.tests.\(UUID().uuidString)") ?? .standard
        let progress = ProgressStore(defaults: suite)

        // Somebody mid-first-run: the flag is false, and they have just pulled.
        ForgeShared.defaults.set(false, forKey: "forge.hasCompletedFirstRun.v1")
        progress.setPlanned(["water"])
        progress.complete("water", method: .honor)
        progress.markEarned()
        #expect(progress.today.isEarned)

        // The app comes back from being killed.
        let vm = ForgeViewModel(progress: progress)
        #expect(vm.hasCompletedFirstRun, "an earned day must not replay onboarding")
        #expect(!vm.isFirstRunCovering)
        #expect(vm.firstRunStage == .finished)
    }

    /// And the other half: nothing earned, so the sequence is genuinely still
    /// ahead of them and must still run.
    @Test("A day with nothing earned still gets the first run")
    func anUnearnedDayStillRunsTheFirstRun() {
        let suite = UserDefaults(suiteName: "forge.tests.\(UUID().uuidString)") ?? .standard
        let progress = ProgressStore(defaults: suite)
        ForgeShared.defaults.set(false, forKey: "forge.hasCompletedFirstRun.v1")
        progress.setPlanned(["water"])

        let vm = ForgeViewModel(progress: progress)
        #expect(!vm.hasCompletedFirstRun)
        #expect(vm.isFirstRunCovering)
    }

    private func makeViewModel() -> (ForgeViewModel, IdentityStore) {
        let suite = UserDefaults(suiteName: "forge.tests.\(UUID().uuidString)") ?? .standard
        let progress = ProgressStore(defaults: suite)
        let vm = ForgeViewModel(progress: progress)
        let identities = IdentityStore(defaults: suite)
        vm.resetFirstRun(identities: identities)
        return (vm, identities)
    }

    @Test("Naming nobody offers exactly what the app always offered")
    func skippingCostsNothing() {
        let offered = IdentityActivities.offered(for: [])
        #expect(offered.count == IdentityActivities.offerCount)
        // The shipped eight, in the order the effort ladder puts them.
        #expect(offered == Array(IdentityActivities.unaimed.prefix(IdentityActivities.offerCount)))
    }

    @Test("What is offered is aimed at what was named")
    func offersFollowTheIdentity() {
        let trains = Identity(statement: IdentityPrompt.trains.statement, symbol: "figure.run")
        let offered = IdentityActivities.offered(for: [trains])

        #expect(offered.count == IdentityActivities.offerCount)
        #expect(offered.contains { Ritual.find($0)?.category == .physical })
    }

    @Test("The smallest thing is asked for first")
    func theFirstAskIsTheSmallest() {
        let reads = Identity(statement: IdentityPrompt.reads.statement, symbol: "book")
        let offered = IdentityActivities.offered(for: [reads])
        let efforts = offered.map { IdentityActivities.effort(of: $0) }

        #expect(efforts == efforts.sorted(), "the ladder decides the order")
    }

    @Test("Every offered activity resolves to a real one")
    func nothingOfferedIsAGhost() {
        for prompt in IdentityPrompt.allCases {
            let identity = Identity(statement: prompt.statement, symbol: prompt.symbol)
            for id in IdentityActivities.offered(for: [identity]) {
                #expect(
                    Ritual.find(id) != nil,
                    Comment(rawValue: "\(prompt) offers \(id), which does not exist")
                )
            }
        }
    }

    @Test("The plan writes the real day: every activity, every day, at its time")
    func thePlanIsTheDay() {
        let (vm, _) = makeViewModel()
        let answers = Assessment(
            day: vm.progress.currentDay,
            answers: Dictionary(uniqueKeysWithValues: Assessment.Question.allCases.map { ($0, 1) })
        )
        let plan = OnboardingPlan.propose(focus: [.physical, .relationship], assessment: answers)

        vm.adoptPlan(plan)

        #expect(vm.activeRitualIDs == plan.map(\.ritualID))
        #expect(vm.totalActive == plan.count)
        #expect(Set(vm.progress.today.plannedIDs) == Set(plan.map(\.ritualID)), "today's record asks for it")
        let tomorrow = vm.progress.currentDay.adding(days: 1).weekday
        for entry in plan {
            let ritual = vm.ritual(entry.ritualID)
            #expect(ritual?.startMinute == entry.minute)
            #expect(ritual?.repeats.isDaily == true)
            #expect(ritual?.happens(on: tomorrow) == true, "the plan is tomorrow's too")
        }
    }

    @Test("The first thing asked for is the smallest thing on the plan")
    func theFirstAskIsTheSmallestOnThePlan() {
        let (vm, _) = makeViewModel()
        let answers = Assessment(
            day: vm.progress.currentDay,
            answers: Dictionary(uniqueKeysWithValues: Assessment.Question.allCases.map { ($0, 0) })
        )
        let plan = OnboardingPlan.propose(focus: Set(RitualCategory.dimensions), assessment: answers)
        vm.adoptPlan(plan)

        let smallest = plan.map(\.ritualID).min { IdentityActivities.effort(of: $0) < IdentityActivities.effort(of: $1) }
        #expect(vm.firstRunActivity?.id == smallest)
    }

    @Test("Skipping what to build still leaves a plan, from the lowest answers")
    func skippingStillPlans() {
        var picks = Dictionary(uniqueKeysWithValues: Assessment.Question.allCases.map { ($0, 2) })
        picks[.friends] = 0
        let answers = Assessment(day: ForgeDay(year: 2026, month: 10, day: 1), answers: picks)
        let plan = OnboardingPlan.propose(focus: [], assessment: answers)
        #expect(plan.count == OnboardingPlan.minimum)
        #expect(plan.contains { $0.dimension == .relationship }, "the lowest answer is on it")
    }

    // MARK: - The sequence

    /// Everything before the pull is over the top of the app; the pull and the
    /// closing line are on it.
    @Test("Every beat before the pull covers the app, and the pull does not")
    func whatCovers() {
        let (vm, _) = makeViewModel()
        let covering: [ForgeViewModel.FirstRunStage] = [
            .coldOpen, .question(0), .question(6), .build, .drawing,
            .transformation, .science, .plan, .metaphor, .doOne,
        ]
        for stage in covering {
            vm.firstRunStage = stage
            #expect(vm.isFirstRunCovering, Comment(rawValue: "\(stage) should cover"))
        }
        for stage in [ForgeViewModel.FirstRunStage.pull, .closing] {
            vm.firstRunStage = stage
            #expect(!vm.isFirstRunCovering)
            #expect(vm.isFirstPullGranted)
        }
    }

    @Test("A replay starts at the cold open")
    func replayStartsCold() {
        let (vm, _) = makeViewModel()
        #expect(vm.firstRunStage == .coldOpen)
    }

    // MARK: - The assessment

    @Test("The answers are kept, read back, and go with a replay")
    func theAssessmentIsKept() {
        let (vm, _) = makeViewModel()
        #expect(vm.assessment == nil, "a replay has said nothing yet")

        let answers = Assessment(
            day: vm.progress.currentDay,
            answers: Dictionary(uniqueKeysWithValues: Assessment.Question.allCases.map { ($0, 3) })
        )
        vm.assessment = answers
        #expect(Assessment.read(from: ForgeShared.defaults) == answers)

        // A fresh launch reads it back.
        let again = ForgeViewModel(progress: vm.progress)
        #expect(again.assessment == answers)
        #expect(again.blended.hasAssessment)

        vm.resetFirstRun()
        #expect(vm.assessment == nil)
        #expect(Assessment.read(from: ForgeShared.defaults) == nil)
    }

    @Test("Without an assessment the view model's six are the record's")
    func noAssessmentMeansTheRecord() {
        let (vm, _) = makeViewModel()
        #expect(vm.assessment == nil)
        #expect(vm.blended.dimensions.map(\.score) == vm.shape.dimensions.map(\.score))
        #expect(vm.blended.overall == vm.shape.overall)
    }
}

// MARK: - 1.0.1 hygiene

/// The words and proportions 1.0.1 changed on the first run and on the first
/// morning of the home screen.
@Suite("1.0.1: first-run and first-day copy")
struct FirstDayCopyTests {

    @Test("The cold open says the mechanic, and the questions say what they are for")
    func openingCopy() {
        #expect(FirstRunCopy.coldOpenTitle == "Every day you keep, the blade comes loose.")
        #expect(FirstRunCopy.coldOpenLine == "You pull it free.")
        #expect(FirstRunCopy.coldOpenButton == "Begin")
        #expect(FirstRunCopy.questionsCaption
                == "Seven questions. Your starting stats come from your answers. From tomorrow, from what you do.")
        #expect(FirstRunCopy.suggested == "Suggested from your answers.")
        #expect(FirstRunCopy.drawingTitle == "Drawing your starting shape.")
    }

    /// Every line the new first run adds, read against the voice: no
    /// exclamation marks, nothing that says "will", no congratulation.
    @Test("No line of the first run exclaims, congratulates or promises")
    func voice() {
        var lines = [
            FirstRunCopy.coldOpenTitle, FirstRunCopy.coldOpenLine, FirstRunCopy.questionsCaption,
            FirstRunCopy.suggested, FirstRunCopy.drawingTitle, FirstRunCopy.scienceTitle,
            FirstRunCopy.planTitle, FirstRunCopy.planSubtitle,
        ]
        lines += Assessment.Question.allCases.flatMap { [$0.prompt] + $0.options.map(\.label) }
        lines += Transformation.Stop.allCases.flatMap { [$0.title, $0.footnote] }
        lines += FirstRunCopy.findings.flatMap { [$0.title, $0.body, $0.mechanic] }
        lines += (0..<4).compactMap {
            Assessment(day: ForgeDay(year: 2026, month: 1, day: 1), answers: [.screenTime: $0]).gainLine
        }
        for line in lines {
            #expect(!line.contains("!"), Comment(rawValue: line))
            #expect(!line.lowercased().contains(" will "), Comment(rawValue: line))
            #expect(!line.lowercased().contains("congratulat"), Comment(rawValue: line))
        }
    }

    /// DIRECTION_1_1 lists the four papers Forge may cite, and nothing else.
    @Test("Only the listed papers are cited, and prose counts are words")
    func science() {
        let allowed = ["Lally, van Jaarsveld, Potts & Wardle (2010)", "Gollwitzer & Sheeran (2006)",
                       "Harkin et al. (2016)", "Dai, Milkman & Riis (2014)"]
        #expect(FirstRunCopy.findings.count == 3)
        for finding in FirstRunCopy.findings {
            #expect(allowed.contains { finding.citation.hasPrefix($0) }, Comment(rawValue: finding.citation))
            // A number in the prose is a word up to a hundred; only a count
            // over a hundred may be digits.
            let numbers = finding.body.split { !$0.isNumber }.compactMap { Int($0) }
            #expect(numbers.allSatisfy { $0 > 100 }, Comment(rawValue: finding.body))
        }
        #expect(FirstRunCopy.findings.map(\.mechanic) == [
            "Arcs are built around it.",
            "Every activity gets a time.",
            "That's why you pull the sword.",
        ])
    }

    @Test("The closing line promises the plan again, not a new choice")
    func closingLine() {
        let state = ForgeNotificationState(
            now: .now, currentDay: ForgeDay(year: 2026, month: 10, day: 1), dayStartHour: 4,
            wakeMinutes: 7 * 60, completedToday: 1, plannedToday: 3,
            isTodayEarned: true, streak: 1
        )
        #expect(FirstRunClosingView(remaining: 0, notificationState: state, onFinish: {}).line
                == "Tomorrow, the same plan again.")
        #expect(FirstRunClosingView(remaining: 2, notificationState: state, focus: [.physical], onFinish: {}).line
                == "Two more, today. Tomorrow, more physical.")
    }

    @Test("A chosen dimension fills the hexagon to about half, not the edge")
    func hexagonReach() {
        #expect(FocusHexagon.reach(isChosen: true) == 0.55)
        #expect(FocusHexagon.reach(isChosen: false) < FocusHexagon.reach(isChosen: true))
        #expect(FocusHexagon.reach(isChosen: false) > 0)
    }

    /// Two lines a row clipped the sixth row on a standard iPhone. Thirty-two
    /// characters is one line of `.caption` beside the glyph and the mark.
    @Test("Every dimension says what it is for in one short line")
    func dimensionMeaningsAreShort() {
        for dimension in RitualCategory.dimensions {
            #expect(!dimension.meaning.isEmpty)
            #expect(dimension.meaning.count <= 32, Comment(rawValue: dimension.meaning))
        }
    }

    @Test("Before anything is kept the badge says DAY ONE, not 0 DAYS")
    func dayOne() {
        let badge = HomeCopy.daysBadge(daysKept: 0)
        #expect(badge.count == nil)
        #expect(badge.word == "DAY ONE")
        #expect(badge.accessibility == "Day one")
    }

    @Test("After the first day the badge counts")
    func daysCount() {
        #expect(HomeCopy.daysBadge(daysKept: 1) == HomeCopy.DaysBadge(count: "1", word: "DAY", accessibility: "1 day kept"))
        #expect(HomeCopy.daysBadge(daysKept: 12) == HomeCopy.DaysBadge(count: "12", word: "DAYS", accessibility: "12 days kept"))
    }

    @Test("The loose panel says what is left, in one line")
    func leftLine() {
        #expect(HomeCopy.leftLine([]) == nil)
        #expect(HomeCopy.leftLine(["Deep work"]) == "1 left \u{00B7} Deep work")
        #expect(HomeCopy.leftLine(["Deep work", "Wake up"]) == "2 left \u{00B7} Deep work, Wake up")
    }
}

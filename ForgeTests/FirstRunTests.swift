import Foundation
import Testing
@testable import Forge

/// The first ninety seconds, and the two things they must not get wrong.
///
/// **Everything written is real.** The identities are real identities, the
/// activities are today's, the completion is in the history and the blade is a
/// blade. There is no tutorial state to clean up, which means every one of these
/// is checking the actual product rather than a rehearsal of it.
///
/// **Skipping costs nothing.** Somebody who declines to name anybody gets the
/// app exactly as it was before identity existed. Half of what is here exists to
/// hold that line, because it is the half that would fail silently.
///
/// The suites that tested the archetype beat went with the archetypes. What is
/// left is the sequence that survived them: name somebody, be offered evidence
/// for them, keep one.
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

    @Test("Choosing writes real activities onto today")
    func chosenStartersLandOnTheDay() {
        let (vm, _) = makeViewModel()
        let chosen = Array(IdentityActivities.offered(for: []).prefix(3))

        vm.chooseStarters(chosen, identities: [])

        #expect(Set(vm.activeRitualIDs) == Set(chosen))
        #expect(vm.totalActive == 3)
    }

    @Test("Choosing tags what was chosen with who it is evidence for")
    func chosenStartersCarryTheIdentity() {
        let (vm, identities) = makeViewModel()
        let trains = identities.add(
            statement: IdentityPrompt.trains.statement, symbol: "figure.run"
        )
        let named = try? #require(trains)
        guard let named else { return }

        let chosen = IdentityActivities.offered(for: [named])
        vm.chooseStarters(Array(chosen.prefix(3)), identities: [named])

        // At least one of the three is filed as evidence for the sentence they
        // wrote — which is the whole of what the beat is for.
        #expect(vm.activeRituals.contains { $0.identityID == named.id })
    }
}

// MARK: - 1.0.1 hygiene

/// The words and proportions 1.0.1 changed on the first run and on the first
/// morning of the home screen.
@Suite("1.0.1: first-run and first-day copy")
struct FirstDayCopyTests {

    @Test("The choose-three title is fixed, whatever was built")
    func chooseTitleIsFixed() {
        #expect(FirstRunCopy.chooseTitle == "Pick three for today.")
    }

    /// A count of where somebody is, not a refusal to go on.
    @Test(
        "The choose-three button counts",
        arguments: [
            (0, "Choose 3 \u{00B7} 0 selected"),
            (1, "Choose 3 \u{00B7} 1 selected"),
            (2, "Choose 3 \u{00B7} 2 selected"),
            (3, "Continue"),
        ]
    )
    func chooseButtonCounts(selected: Int, title: String) {
        #expect(FirstRunCopy.chooseButton(selected: selected) == title)
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

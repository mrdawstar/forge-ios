import Foundation
import Testing
@testable import Forge

/// QuickAdd (§17.4): one tap per activity, on the right day, never twice, and
/// an Undo that leaves nothing behind.
///
/// Every guarantee `ActivityLibraryView` documented is checked here against
/// the one path QuickAdd's rows take (`ForgeViewModel.quickAdd`), and the
/// catalogue the sheet draws (`QuickAddCatalog`).
@MainActor
@Suite("QuickAdd")
struct QuickAddTests {

    /// A view model with a day of its own. See `OnboardingDayTests` for why
    /// the day is cleared through the model's own properties.
    private func makeViewModel() -> (ForgeViewModel, ProgressStore) {
        let suite = UserDefaults(suiteName: "forge.tests.\(UUID().uuidString)") ?? .standard
        let progress = ProgressStore(defaults: suite)
        let vm = ForgeViewModel(progress: progress)
        vm.customRituals = []
        vm.libraryEdits = [:]
        vm.activeRitualIDs = []
        return (vm, progress)
    }

    private func otherWeekday(than weekday: Int) -> Int {
        weekday == 1 ? 2 : weekday - 1
    }

    // MARK: - The right day

    @Test("A library activity lands on the day being filled, and on no other")
    func addsOnTheRightDay() {
        let (vm, progress) = makeViewModel()
        let today = progress.currentDay.weekday
        let other = otherWeekday(than: today)

        #expect(vm.quickAdd("run", onWeekday: other) == .added)
        #expect(vm.ritual("run")?.repeats.weekdays == [other])
        #expect(!vm.todayRitualIDs.contains("run"), "Thursday's add is not today's")

        #expect(vm.quickAdd("read", onWeekday: today) == .added)
        #expect(vm.ritual("read")?.repeats.weekdays == [today])
        #expect(vm.todayRitualIDs.contains("read"))
    }

    @Test("Something already in the week gains the day and is never copied")
    func alreadyInTheWeekAddsTheDay() {
        let (vm, progress) = makeViewModel()
        let today = progress.currentDay.weekday
        let other = otherWeekday(than: today)
        vm.quickAdd("run", onWeekday: other)

        #expect(vm.quickAdd("run", onWeekday: today) == .dayAdded)
        #expect(vm.activeRitualIDs == ["run"], "no second copy")
        #expect(vm.ritual("run")?.repeats.weekdays == [other, today])
        #expect(vm.todayRitualIDs == ["run"])
    }

    @Test("Nothing is ever duplicated")
    func neverTwice() {
        let (vm, progress) = makeViewModel()
        let today = progress.currentDay.weekday

        #expect(vm.quickAdd("run", onWeekday: today) == .added)
        #expect(vm.quickAdd("run", onWeekday: today) == .alreadyThere)
        #expect(vm.activeRitualIDs.filter { $0 == "run" }.count == 1)
        #expect(vm.quickAdd("no.such.activity", onWeekday: today) == .alreadyThere)
        #expect(!vm.activeRitualIDs.contains("no.such.activity"))
    }

    // MARK: - Undo

    @Test("Undo puts the week back exactly, whichever kind of add it was")
    func undoRestoresExactly() {
        let (vm, progress) = makeViewModel()
        let today = progress.currentDay.weekday
        let other = otherWeekday(than: today)

        // A week with something in every part of the snapshot.
        vm.quickAdd("read", onWeekday: other)
        var draft = ActivityDraft.blank(named: "Swim")
        draft.repeats = .weekends
        let swim = vm.createCustomRitual(draft)
        vm.removeRitual(swim.id)
        let planned = vm.todayRitualIDs

        // A new activity.
        let beforeNew = vm.weekSnapshot
        vm.quickAdd("run", onWeekday: today)
        #expect(vm.weekSnapshot != beforeNew)
        vm.restore(beforeNew)
        #expect(vm.weekSnapshot == beforeNew)
        #expect(vm.libraryEdits["run"] == nil, "not even the pinned day is left behind")

        // A day added to something already kept.
        let beforeDay = vm.weekSnapshot
        vm.quickAdd("read", onWeekday: today)
        #expect(vm.ritual("read")?.happens(on: today) == true)
        vm.restore(beforeDay)
        #expect(vm.weekSnapshot == beforeDay)
        #expect(vm.ritual("read")?.repeats.weekdays == [other])

        // One of theirs, back from "Yours".
        let beforeYours = vm.weekSnapshot
        vm.quickAdd(swim.id, onWeekday: today)
        vm.restore(beforeYours)
        #expect(vm.weekSnapshot == beforeYours)
        #expect(vm.ritual(swim.id)?.repeats == .weekends, "their days, untouched")

        // Something made from a search that found nothing.
        let beforeMade = vm.weekSnapshot
        let made = vm.createCustomRitual(ActivityDraft.blank(named: "Stretch"))
        #expect(vm.activeRitualIDs.contains(made.id))
        vm.restore(beforeMade)
        #expect(vm.weekSnapshot == beforeMade)
        #expect(vm.ritual(made.id) == nil)

        // And today's list reads as it did, which is what the record is told.
        #expect(vm.todayRitualIDs == planned)
        #expect(progress.byDay[progress.currentDay]?.plannedIDs ?? [] == planned)
    }

    // MARK: - The catalogue

    private func catalogue(
        week: [Ritual], weekday: Int, weakest: RitualCategory? = nil, gaps: [String] = [],
        custom: [Ritual] = []
    ) -> QuickAddCatalog {
        QuickAddCatalog.make(
            week: week,
            library: Ritual.library,
            unusedCustom: custom,
            weekday: weekday,
            weakest: weakest,
            arcGaps: gaps,
            arcName: gaps.isEmpty ? nil : "Winter Arc",
            find: Ritual.find
        )
    }

    private func ritual(_ id: String, on weekdays: Set<Int>) -> Ritual {
        var found = Ritual.find(id)!
        found.repeats = RitualRepeat(weekdays: weekdays)
        return found
    }

    @Test("The week planner's day is honoured: what runs on other days is offered for it")
    func catalogueForAWeekday() {
        let monday = 2, thursday = 5
        let week = [ritual("run", on: [monday]), ritual("read", on: [thursday])]
        let list = catalogue(week: week, weekday: thursday)

        let inWeek = list.rows(in: .inWeek, matching: "")
        #expect(inWeek.map(\.id) == ["run"], "Thursday's own read is not offered for Thursday")
        #expect(inWeek.first?.detail == RitualRepeat(weekdays: [monday]).label)
        #expect(!list.rows(in: .library, matching: "").contains { $0.id == "run" || $0.id == "read" },
                "something already in the week is never offered as new")
    }

    @Test("Suggested: the Arc's gaps first, then the weakest dimension's three")
    func suggestedSection() {
        let list = catalogue(week: [], weekday: 2, weakest: .relationship, gaps: ["pages"])
        let suggested = list.rows(in: .suggested, matching: "")
        #expect(suggested.first?.id == "pages")
        #expect(suggested.first?.detail == "Part of Winter Arc")
        let forWeakest = ForgeShape.suggestions(for: .relationship, avoiding: [])
        #expect(Array(suggested.dropFirst().map(\.id)) == forWeakest.map(\.id))
        #expect(suggested.dropFirst().allSatisfy { $0.detail == "Builds relationship" })
    }

    @Test("Each activity is offered once, in the first section it belongs to")
    func offeredOnce() {
        let custom = Ritual.makeCustom(ActivityDraft.blank(named: "Swim"))
        let list = catalogue(week: [ritual("run", on: [2])], weekday: 5, weakest: .physical,
                             gaps: ["run", "pages"], custom: [custom])
        let ids = list.rows.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(list.rows.first { $0.id == "run" }?.section == .inWeek, "a gap already in the week is not a gap")
        #expect(list.rows.first { $0.id == custom.id }?.section == .yours)
    }

    @Test("The chips narrow what is offered, never what is already somebody's")
    func chipsNarrowOffersOnly() {
        let week = [ritual("read", on: [2])]
        let list = catalogue(week: week, weekday: 5, weakest: .relationship)
        #expect(list.rows(in: .inWeek, matching: "", category: .physical).map(\.id) == ["read"])
        #expect(list.rows(in: .library, matching: "", category: .physical).allSatisfy { $0.ritual.category == .physical })
        #expect(list.rows(in: .suggested, matching: "", category: .physical).isEmpty)
    }

    @Test("A search that finds nothing is what offers to make it")
    func emptySearch() {
        let list = catalogue(week: [], weekday: 5)
        #expect(list.isEmpty(matching: "zzqx no such thing"))
        #expect(!list.isEmpty(matching: "read"))
        #expect(!list.isEmpty(matching: "  READ "), "trimmed and case-insensitive")
    }
}

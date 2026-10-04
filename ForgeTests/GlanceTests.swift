import Foundation
import Testing
import TipKit
@testable import Forge

/// Becoming at a glance (§17.4): the tiles, the change over seven days, and
/// the chip a kept activity raises.
///
/// The readings run over records built in memory on fixed days, like
/// `BlendedShapeTests`, so nothing here depends on the day it is run on.
@Suite("Becoming at a glance")
struct GlanceTests {

    private let start = ForgeDay(year: 2026, month: 10, day: 1)

    private func activity(_ id: String) -> Ritual { Ritual.find(id)! }

    private func record(_ day: ForgeDay, planned: [String], done: [String]) -> DayRecord {
        DayRecord(
            day: day,
            completions: done.map {
                DayRecord.Completion(ritualID: $0, method: .honor, at: day.startOfDay())
            },
            plannedIDs: planned,
            extractedAt: done.isEmpty ? nil : day.startOfDay()
        )
    }

    /// `id` planned on each of `days` days from `first`, kept where `kept` says.
    private func history(
        _ id: String = "water", from first: ForgeDay, days: Int, kept: (Int) -> Bool = { _ in true }
    ) -> [ForgeDay: DayRecord] {
        var records: [ForgeDay: DayRecord] = [:]
        for index in 0..<days {
            let day = first.adding(days: index)
            records[day] = record(day, planned: [id], done: kept(index) ? [id] : [])
        }
        return records
    }

    private func answers(on day: ForgeDay) -> Assessment {
        var picks = Dictionary(uniqueKeysWithValues: Assessment.Question.allCases.map { ($0, 1) })
        picks[.sleep] = 1
        return Assessment(day: day, answers: picks)
    }

    // MARK: - The tiles

    @Test("The tiles are the six, in the hexagon's order, with the chosen ones marked")
    func tileOrder() {
        let today = start.adding(days: 20)
        let six = BlendedShape.read(history(from: start, days: 20), today: today,
                                    activities: [activity("water")], assessment: nil)
        let tiles = StatGlance.tiles(now: six, weekAgo: nil, focus: [.physical, .mental])

        #expect(tiles.map(\.category) == RitualCategory.dimensions)
        #expect(tiles.map(\.category) == six.dimensions.map(\.category), "the grid and the polygon agree")
        #expect(tiles.filter(\.isBuilding).map(\.category) == [.mental, .physical])
        #expect(tiles.allSatisfy { $0.weekChange == nil }, "no week ago, no change")
    }

    // MARK: - Seven days

    @Test("The change over seven days is today's reading minus the reading a week ago")
    func sevenDayChange() throws {
        // Water every day for a month, missed for the first ten: Physical rises.
        let today = start.adding(days: 30)
        let records = history(from: start, days: 30) { $0 >= 10 }
        let kept = [activity("water")]

        let now = BlendedShape.read(records, today: today, activities: kept, assessment: nil)
        let then = try #require(StatGlance.weekAgo(records, today: today, activities: kept, assessment: nil))

        // Exactly the reading the tab would have drawn a week ago: that day as
        // "today", nothing after it.
        let weekAgo = today.adding(days: -7)
        let direct = BlendedShape.read(records.filter { $0.key <= weekAgo }, today: weekAgo,
                                       activities: kept, assessment: nil)
        #expect(then == direct)

        let tiles = StatGlance.tiles(now: now, weekAgo: then, focus: [])
        let physical = try #require(tiles.first { $0.category == .physical })
        let expected = now.dimension(.physical)!.score - direct.dimension(.physical)!.score
        #expect(physical.weekChange == expected)
        #expect(expected > 0, "a dimension kept more this week reads up")

        // A dimension nothing feeds has no number, so no change either.
        #expect(tiles.first { $0.category == .relationship }?.weekChange == nil)
    }

    @Test("A week ago reads only what had happened by then")
    func weekAgoIgnoresLaterDays() {
        let today = start.adding(days: 30)
        let kept = [activity("water")]
        let records = history(from: start, days: 30)
        var changedLater = records
        for back in 0..<7 {
            let day = today.adding(days: -back)
            changedLater[day] = record(day, planned: ["water"], done: [])
        }
        #expect(StatGlance.weekAgo(records, today: today, activities: kept, assessment: nil)
                == StatGlance.weekAgo(changedLater, today: today, activities: kept, assessment: nil))
    }

    @Test("The change is hidden when a week ago there was nobody to read")
    func changeHiddenWithoutAWeek() {
        let kept = [activity("water")]
        // A record five days old.
        #expect(StatGlance.weekAgo(history(from: start, days: 5), today: start.adding(days: 5),
                                   activities: kept, assessment: nil) == nil)
        // An older record, but answers given since the day a week ago: the
        // reading a week ago would be of somebody who had not answered yet.
        let today = start.adding(days: 20)
        #expect(StatGlance.weekAgo(history(from: start, days: 20), today: today, activities: kept,
                                   assessment: answers(on: today.adding(days: -3))) == nil)
        // Answers given before then are part of it.
        #expect(StatGlance.weekAgo(history(from: start, days: 20), today: today, activities: kept,
                                   assessment: answers(on: start)) != nil)
    }

    @Test("A change is said in digits, with a real minus sign")
    func changeLabels() {
        #expect(StatGlance.label(4) == "+4")
        #expect(StatGlance.label(0) == "\u{00B1}0")
        #expect(StatGlance.label(-3) == "\u{2212}3")
        #expect(StatGlance.spoken(4) == "up 4 this week")
        #expect(StatGlance.spoken(-3) == "down 3 this week")
    }

    @Test("The blade line under the hexagon")
    func bladeLine() {
        #expect(BecomingTabView.bladeLine(blade: "Quenched", daysKept: 23) == "Quenched \u{00B7} 23 days")
        #expect(BecomingTabView.bladeLine(blade: "Struck", daysKept: 1) == "Struck \u{00B7} 1 day")
        #expect(BecomingTabView.bladeLine(blade: "Rough", daysKept: 0) == "Rough \u{00B7} no days kept yet")
    }

    // MARK: - The chip

    @Test("A gain is the blended difference, in the dimension that moved most")
    func gainIsTheDifference() throws {
        let today = start.adding(days: 12)
        let kept = [activity("water")]
        var records = history(from: start, days: 12) { $0.isMultiple(of: 2) }
        let before = BlendedShape.read(records, today: today, activities: kept, assessment: nil)
        records[today] = record(today, planned: ["water"], done: ["water"])
        let after = BlendedShape.read(records, today: today, activities: kept, assessment: nil)

        let gain = try #require(StatGain.between(before, after, ritualID: "water", filedUnder: .physical))
        #expect(gain.dimension == .physical)
        #expect(gain.delta == after.dimension(.physical)!.score - before.dimension(.physical)!.score)
        #expect(gain.label == "+\(gain.delta) Physical")
    }

    @Test("No chip when nothing rose")
    func noChipWithoutARise() {
        let today = start.adding(days: 12)
        let six = BlendedShape.read(history(from: start, days: 12), today: today,
                                    activities: [activity("water")], assessment: nil)
        #expect(StatGain.between(six, six, ritualID: "water", filedUnder: .physical) == nil)
    }
}

// MARK: - The chip, through the view model

@MainActor
@Suite("Every kept activity moves a number")
struct GainTests {

    private func makeViewModel() -> (ForgeViewModel, ProgressStore) {
        let suite = UserDefaults(suiteName: "forge.tests.\(UUID().uuidString)") ?? .standard
        let progress = ProgressStore(defaults: suite)
        let vm = ForgeViewModel(progress: progress)
        vm.customRituals = []
        vm.libraryEdits = [:]
        vm.activeRitualIDs = ["water", "read"]
        return (vm, progress)
    }

    @Test("The chip's value is the blended score before the write and after it")
    func chipIsTheBlendedDifference() throws {
        let (vm, progress) = makeViewModel()
        // A fortnight of water kept every other day: room to rise.
        for back in 1...14 {
            let day = progress.currentDay.adding(days: -back)
            progress.record(DayRecord(
                day: day,
                completions: back.isMultiple(of: 2)
                    ? [DayRecord.Completion(ritualID: "water", method: .honor, at: day.startOfDay())]
                    : [],
                plannedIDs: ["water"]
            ))
        }

        let before = vm.blended
        vm.keepPromise("water")
        let after = vm.blended

        // Whatever the shared suite holds by way of answers, the chip says
        // exactly what the two readings either side of the write say — the
        // view model keeps no number of its own.
        let expected = StatGain.between(before, after, ritualID: "water", filedUnder: .physical)
        #expect(vm.lastGain?.ritualID == expected?.ritualID)
        #expect(vm.lastGain?.dimension == expected?.dimension)
        #expect(vm.lastGain?.delta == expected?.delta)
        if let gain = vm.lastGain {
            let was = before.dimension(gain.dimension).map { $0.hasScore ? $0.score : 0 } ?? 0
            #expect(gain.delta == after.dimension(gain.dimension)!.score - was)
            #expect(gain.delta > 0)
        }
        // With the record alone — no answers — keeping water raises Physical.
        if !before.hasAssessment {
            let gain = try #require(vm.lastGain)
            #expect(gain.dimension == .physical)
        }
    }

    @Test("Taking a completion back raises nothing")
    func undoingRaisesNothing() {
        let (vm, _) = makeViewModel()
        vm.keepPromise("water")
        let first = vm.lastGain
        vm.tapRitual("water")           // a tap on a done row takes it back
        #expect(vm.lastGain == first, "an undo is not a gain")
    }
}

// MARK: - The first week's tips

@Suite("The first week's tips")
struct TipsTests {

    @Test("Never during the first run")
    func neverInTheFirstRun() {
        #expect(!ForgeTips.mayShow(.init(hasCompletedFirstRun: false)))
        #expect(!ForgeTips.mayShow(.init(hasCompletedFirstRun: false, isFirstRunCovering: true)))
        #expect(!ForgeTips.mayShow(.init(hasCompletedFirstRun: true, isFirstRunCovering: true)))
    }

    @Test("Never over a summary, a pull or a celebration")
    func neverOverTheDay() {
        #expect(!ForgeTips.mayShow(.init(hasCompletedFirstRun: true, isDayMomentOnScreen: true)))
        #expect(ForgeTips.mayShow(.init(hasCompletedFirstRun: true)))
    }

    @Test("Five, in order, each at most once")
    func fiveInOrder() {
        #expect(ForgeTips.order == [
            "forge.tip.row", "forge.tip.pull", "forge.tip.becoming", "forge.tip.arcs", "forge.tip.add",
        ])
        let tips: [any Tip] = [RowTip(), PullTip(), BecomingTip(), ArcsTip(), AddTip()]
        for tip in tips {
            #expect(tip.options.contains { $0 is Tips.MaxDisplayCount }, Comment(rawValue: tip.id))
            #expect(!tip.rules.isEmpty, Comment(rawValue: tip.id))
        }
    }

    /// The first run ends in a real pull. Retiring the pull's tip there
    /// skipped it for every new install: the ordered group passes over an
    /// invalidated tip, and the Becoming tab's tip came second.
    @Test("The first run's own pull leaves the pull's tip for later")
    func firstRunPullKeepsTheTip() throws {
        #expect(!ForgeTips.pullRetiresTip(hasCompletedFirstRun: false))
        #expect(ForgeTips.pullRetiresTip(hasCompletedFirstRun: true))
        let root = try source("ContentView.swift")
        let pulled = try #require(root.range(of: "guard !wasOut, isOut else { return }"))
        let body = root[pulled.upperBound...].prefix(400)
        #expect(body.contains("ForgeTips.pullRetiresTip(hasCompletedFirstRun: forgeVM.hasCompletedFirstRun)"))
    }

    /// Walked in the 1.1 release pass: a 1.0.1 install with fifty days kept
    /// updated and opened to "Tap when it's done." An install that ran 1.0 or
    /// 1.0.1 is spared the two that teach the day, and still sees the three
    /// about what 1.1 added, in order; a new install sees all five.
    @Test("An install that ran 1.0 starts at the six, not at how to tap a row")
    func foundersSkipTheBasics() throws {
        #expect(ForgeTips.knownAtLaunch(founderRecorded: false).isEmpty)
        let known = ForgeTips.knownAtLaunch(founderRecorded: true)
        #expect(known == Array(ForgeTips.order.prefix(2)))
        #expect(ForgeTips.order.filter { !known.contains($0) }
            == ["forge.tip.becoming", "forge.tip.arcs", "forge.tip.add"])
        // Retired at launch, after TipKit is configured, from the founder record.
        let app = try source("ForgeApp.swift")
        let configured = try #require(app.range(of: "ForgeTips.configure()"))
        let retired = try #require(app.range(
            of: "ForgeTips.retireKnown(founderRecorded: Founder.isRecorded(in: ForgeShared.defaults))"
        ))
        #expect(configured.upperBound <= retired.lowerBound)
        let founders = try #require(app.range(of: "Founder.recordOnFirstLaunch(in: ForgeShared.defaults)"))
        #expect(founders.upperBound <= retired.lowerBound)
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Forge")
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The rule is only as good as what the root hands it: the first run, and
    /// every moment that is the day rather than a pause in it.
    @Test("The root hands TipKit the first run and every moment over the day")
    func rootFeedsTheRule() throws {
        let root = try source("ContentView.swift")
        #expect(root.contains("hasCompletedFirstRun: forgeVM.hasCompletedFirstRun"))
        #expect(root.contains("isFirstRunCovering: forgeVM.isFirstRunCovering"))
        #expect(root.contains("isDayMomentOnScreen: isDayMomentOnScreen"))
        let moment = try #require(root.range(of: "private var isDayMomentOnScreen: Bool {"))
        let body = root[moment.upperBound...].prefix(400)
        for fact in ["summary", "pendingUnlock", "pull", "honorRitualID", "isReturning", "showReview", "showChapterClose"] {
            #expect(body.contains(fact), Comment(rawValue: fact))
        }
        // A blade that is out rests at the top of its travel for the rest of
        // the day; that is not a pull under way, or no earned day would ever
        // see a tip, or the rating prompt, again.
        #expect(body.contains("forgeVM.pull > 0.01 && !forgeVM.isOut"))
        #expect(try source("ForgeApp.swift").contains("ForgeTips.configure()"))
    }
}

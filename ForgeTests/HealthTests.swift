import Foundation
import Testing
@testable import Forge

// Apple Health (DIRECTION_1_1 §8, FORGE_CONTEXT §17.5): the windows a reading
// belongs to, the arithmetic, the decoder, the ledger, and the view model's
// promises — Health ticks off once, never takes back a hand-ticked box, an
// undo stands, and permission is never asked at launch or in the first run.

/// A calendar in a US time zone, so both 2026 clock changes are real.
private let newYork: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
}()

private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    newYork.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func interval(_ start: Date, _ end: Date) -> DateInterval {
    DateInterval(start: start, end: end)
}

// MARK: - Windows

@Suite("Apple Health: the Forge day and the night")
struct HealthWindowTests {

    @Test("A Forge day runs from four to four")
    func fourToFour() {
        let day = ForgeDay(year: 2026, month: 10, day: 2)
        let window = HealthWindow.day(day, dayStartHour: 4, calendar: newYork)
        #expect(window.start == at(2026, 10, 2, 4))
        #expect(window.end == at(2026, 10, 3, 4))
        #expect(window.duration == 24 * 3600)
    }

    @Test("A step at 03:50 is yesterday's, one at 04:00 is today's")
    func theFourOClockLine() {
        let today = HealthWindow.day(ForgeDay(year: 2026, month: 10, day: 2), dayStartHour: 4, calendar: newYork)
        let yesterday = HealthWindow.day(ForgeDay(year: 2026, month: 10, day: 1), dayStartHour: 4, calendar: newYork)
        #expect(!today.contains(at(2026, 10, 2, 3, 50)))
        #expect(yesterday.contains(at(2026, 10, 2, 3, 50)))
        #expect(today.contains(at(2026, 10, 2, 4)))
    }

    @Test("A workout across 04:00 gives each day only its own minutes")
    func workoutAcrossTheLine() {
        let run = interval(at(2026, 10, 2, 3, 30), at(2026, 10, 2, 4, 30))
        let today = HealthWindow.day(ForgeDay(year: 2026, month: 10, day: 2), dayStartHour: 4, calendar: newYork)
        let yesterday = HealthWindow.day(ForgeDay(year: 2026, month: 10, day: 1), dayStartHour: 4, calendar: newYork)
        #expect(HealthMath.minutes(of: [run], within: today) == 30)
        #expect(HealthMath.minutes(of: [run], within: yesterday) == 30)
    }

    /// 8 March 2026: the clocks go forward at 02:00, inside the Forge day of
    /// the 7th. That day is four to four by the wall and 23 hours long.
    @Test("The day the clocks go forward is 23 hours, four to four")
    func springForward() {
        let window = HealthWindow.day(ForgeDay(year: 2026, month: 3, day: 7), dayStartHour: 4, calendar: newYork)
        #expect(window.start == at(2026, 3, 7, 4))
        #expect(window.end == at(2026, 3, 8, 4))
        #expect(window.duration == 23 * 3600)
        let next = HealthWindow.day(ForgeDay(year: 2026, month: 3, day: 8), dayStartHour: 4, calendar: newYork)
        #expect(next.start == window.end, "no gap and no overlap between days")
    }

    /// 1 November 2026: the clocks go back at 02:00, inside the Forge day of
    /// 31 October, which is 25 hours long.
    @Test("The day the clocks go back is 25 hours, four to four")
    func fallBack() {
        let window = HealthWindow.day(ForgeDay(year: 2026, month: 10, day: 31), dayStartHour: 4, calendar: newYork)
        #expect(window.start == at(2026, 10, 31, 4))
        #expect(window.end == at(2026, 11, 1, 4))
        #expect(window.duration == 25 * 3600)
        // An hour-long walk in the repeated hour counts as an hour, once.
        let walk = interval(window.start.addingTimeInterval(21 * 3600), window.start.addingTimeInterval(22 * 3600))
        #expect(HealthMath.minutes(of: [walk], within: window) == 60)
    }

    @Test("Last night is the night that ended this morning, across the day start")
    func lastNight() {
        let day = ForgeDay(year: 2026, month: 10, day: 2)
        let night = HealthWindow.night(endingOn: day, calendar: newYork)
        #expect(night.start == at(2026, 10, 1, 18))
        #expect(night.end == at(2026, 10, 2, 12))
        let sleep = interval(at(2026, 10, 1, 23), at(2026, 10, 2, 7))
        #expect(HealthMath.minutes(of: [sleep], within: night) == 8 * 60)
        // The same night is not also the next morning's.
        let tomorrow = HealthWindow.night(endingOn: day.adding(days: 1), calendar: newYork)
        #expect(HealthMath.minutes(of: [sleep], within: tomorrow) == 0)
        #expect(HealthWindow.window(for: .sleepMinutes, on: day, dayStartHour: 4, calendar: newYork) == night)
    }

    @Test("Sleep across a clock change is counted in real hours")
    func sleepAcrossDST() {
        // 23:00 to 07:00 by the wall: eight hours, nine when the clocks go
        // back that night, seven when they go forward.
        let back = interval(at(2026, 10, 31, 23), at(2026, 11, 1, 7))
        let backNight = HealthWindow.night(endingOn: ForgeDay(year: 2026, month: 11, day: 1), calendar: newYork)
        #expect(HealthMath.minutes(of: [back], within: backNight) == 9 * 60)

        let forward = interval(at(2026, 3, 7, 23), at(2026, 3, 8, 7))
        let forwardNight = HealthWindow.night(endingOn: ForgeDay(year: 2026, month: 3, day: 8), calendar: newYork)
        #expect(HealthMath.minutes(of: [forward], within: forwardNight) == 7 * 60)
    }
}

// MARK: - Arithmetic

@Suite("Apple Health: counting time")
struct HealthMathTests {

    @Test("A watch and a phone recording one night count it once")
    func overlapsCountOnce() {
        let window = interval(at(2026, 10, 1, 18), at(2026, 10, 2, 12))
        let watch = interval(at(2026, 10, 1, 23), at(2026, 10, 2, 6))
        let phone = interval(at(2026, 10, 2, 0), at(2026, 10, 2, 7))
        #expect(HealthMath.minutes(of: [watch, phone], within: window) == 8 * 60)
    }

    @Test("Separate stretches add up, and nothing outside the window counts")
    func separateStretches() {
        let window = interval(at(2026, 10, 2, 4), at(2026, 10, 3, 4))
        let morning = interval(at(2026, 10, 2, 7), at(2026, 10, 2, 7, 20))
        let evening = interval(at(2026, 10, 2, 18), at(2026, 10, 2, 18, 15))
        let before = interval(at(2026, 10, 1, 20), at(2026, 10, 1, 21))
        #expect(HealthMath.minutes(of: [evening, before, morning], within: window) == 35)
        #expect(HealthMath.minutes(of: [], within: window) == 0)
    }

    @Test("A target is met at the number, not a minute before")
    func meets() {
        let measure = ActivityMeasure(metric: .workoutMinutes, target: 30)
        #expect(HealthMath.meets(30, measure))
        #expect(!HealthMath.meets(29, measure))
        #expect(!HealthMath.meets(nil, measure))
    }

    @Test("Targets read the way somebody types them")
    func targetsFromGoals() {
        #expect(ActivityMetric.steps.target(fromGoal: "12,000") == 12_000)
        #expect(ActivityMetric.steps.target(fromGoal: "12k") == 12_000)
        #expect(ActivityMetric.steps.target(fromGoal: "lots") == nil)
        #expect(ActivityMetric.sleepMinutes.target(fromGoal: "8 h") == 480)
        #expect(ActivityMetric.sleepMinutes.target(fromGoal: "7.5 h") == 450)
        #expect(ActivityMetric.sleepMinutes.target(fromGoal: "7 h 30") == 450)
        #expect(ActivityMetric.workoutMinutes.target(fromGoal: "45 min") == nil, "a length is the row's minutes")
    }

    @Test("A target is shown in digits")
    func labels() {
        #expect(ActivityMetric.steps.label(8_000) == "8,000")
        #expect(ActivityMetric.steps.label(10_000) == "10,000")
        #expect(ActivityMetric.workoutMinutes.label(20) == "20 min")
        #expect(ActivityMetric.sleepMinutes.label(420) == "7 h")
        #expect(ActivityMetric.sleepMinutes.label(450) == "7 h 30 min")
    }
}

// MARK: - What is stored

@Suite("Apple Health: the decoder and the library")
struct HealthDecodingTests {

    @Test("health, honor and basic round-trip, and anything unknown is honor")
    func methodRoundTrips() throws {
        for method in VerificationMethod.allCases {
            let data = try JSONEncoder().encode(method)
            #expect(try JSONDecoder().decode(VerificationMethod.self, from: data) == method)
        }
        let decode = { (raw: String) throws -> VerificationMethod in
            try JSONDecoder().decode(VerificationMethod.self, from: Data("\"\(raw)\"".utf8))
        }
        #expect(try decode("health") == .health)
        #expect(try decode("honor") == .honor)
        #expect(try decode("basic") == .basic)
        #expect(try decode("aiVerified") == .honor)
        #expect(try decode("telepathy") == .honor)
    }

    @Test("A day's Health completion survives the record round trip")
    func completionRoundTrips() throws {
        var record = DayRecord(day: ForgeDay(year: 2026, month: 10, day: 2))
        record.completions.append(.init(ritualID: "steps", method: .health, at: .now))
        let data = try JSONEncoder().encode(record)
        let back = try JSONDecoder().decode(DayRecord.self, from: data)
        #expect(back.completions.first?.method == .health)
    }

    @Test("A custom activity stored as health, with nothing to count, behaves as Your Word")
    func customHealthIsYourWord() {
        var ritual = Ritual.makeCustom(.blank(named: "Walk the dog"))
        ritual.verificationOverride = .health
        #expect(ritual.verification == .health)
        #expect(!ritual.checksWithHealth)
        #expect(ritual.metadata == "Honor")
    }

    @Test("The library's Health activities are exactly the measurable ones")
    func libraryMatchesMetrics() {
        let health = Set(Ritual.libraryVerification.filter { $0.value == .health }.keys)
        #expect(health == Set(Ritual.metrics.keys))
        for id in health {
            #expect(Ritual.find(id)?.checksWithHealth == true, Comment(rawValue: id))
        }
        #expect(Ritual.find("sleep")?.verification == .honor, "Lights out is tonight; Health only knows last night")
        #expect(Ritual.find("slept")?.measure == ActivityMeasure(metric: .sleepMinutes, target: 420))
    }

    @Test("The Arcs' measurable activities are Health's, at their targets")
    func arcsAreHealth() {
        #expect(Ritual.find("steps")?.measure == ActivityMeasure(metric: .steps, target: 8_000))
        #expect(Ritual.find("workout")?.measure == ActivityMeasure(metric: .workoutMinutes, target: 20))
        #expect(Ritual.find("run")?.measure?.workout == .running)
        #expect(Ritual.find("lift")?.measure?.workout == .strength)
        var winterSteps = Ritual.find("steps")
        winterSteps?.target = 10_000
        #expect(winterSteps?.measure?.target == 10_000)
    }

    @Test("The ledger reads anything, including nothing")
    func ledgerIsTolerant() throws {
        let empty = try JSONDecoder().decode(HealthLedger.self, from: Data("{}".utf8))
        #expect(empty == HealthLedger())
        let odd = try JSONDecoder().decode(
            HealthLedger.self,
            from: Data(#"{"decision":"maybe","offered":["run"],"ticked":7}"#.utf8)
        )
        #expect(odd.decision == .undecided)
        #expect(odd.offered == ["run"])
        #expect(odd.ticked.isEmpty)
    }

    @Test("Existing measurable activities stay Your Word; nothing else is touched")
    func migration() {
        let week = ["water", "run", "steps", "read"]
        var mine = RitualEdit()
        mine.verification = .basic
        let (ledger, edits) = HealthLedger.migrate(HealthLedger(), week: week, edits: ["steps": mine])
        #expect(edits["run"]?.verification == .honor)
        #expect(edits["steps"]?.verification == .basic, "a choice somebody made stands")
        #expect(edits["water"] == nil && edits["read"] == nil)
        #expect(ledger.awaitingOffer == ["run"])
        #expect(ledger.hasMigrated)

        // Once only.
        let again = HealthLedger.migrate(ledger, week: week + ["workout"], edits: edits)
        #expect(again.edits["workout"] == nil)
        #expect(again.ledger == ledger)
    }

    @Test("Observers start at launch only after a yes on the primer")
    func launch() {
        var ledger = HealthLedger()
        #expect(!ledger.observesAtLaunch)
        ledger.decision = .declined
        #expect(!ledger.observesAtLaunch)
        ledger.decision = .asked
        #expect(ledger.observesAtLaunch)
    }
}

// MARK: - The view model

/// What Health can see, and how many times it was asked. Never touches HealthKit.
private final class FakeHealth: HealthReading, @unchecked Sendable {
    var values: [ActivityMetric: Int] = [:]
    var visible: Set<ActivityMetric> = Set(ActivityMetric.allCases)
    private(set) var requests = 0
    private(set) var reads = 0

    func requestReadAccess() async { requests += 1 }
    func startObserving() {}
    func visibleMetrics() async -> Set<ActivityMetric> { visible }
    func value(of measure: ActivityMeasure, on day: ForgeDay, dayStartHour: Int) async -> Int? {
        reads += 1
        return values[measure.metric]
    }
}

@MainActor
@Suite("Apple Health: ticking off", .serialized)
struct HealthCompletionTests {

    /// A view model past its first run, with a day of its own, Health allowed
    /// and a fake in place of HealthKit.
    private func makeViewModel(
        week: [String] = ["steps"], decision: HealthLedger.Decision = .asked
    ) -> (ForgeViewModel, FakeHealth) {
        let suite = UserDefaults(suiteName: "forge.tests.\(UUID().uuidString)") ?? .standard
        let vm = ForgeViewModel(progress: ProgressStore(defaults: suite))
        vm.resetFirstRun()
        let fake = FakeHealth()
        vm.health = fake
        vm.customRituals = []
        vm.libraryEdits = [:]
        vm.finishFirstRun()
        vm.activeRitualIDs = week
        var ledger = HealthLedger()
        ledger.hasMigrated = true
        ledger.decision = decision
        vm.healthLedger = ledger
        vm.healthPrimer = nil
        return (vm, fake)
    }

    private func completions(_ vm: ForgeViewModel, _ id: String) -> [DayRecord.Completion] {
        vm.progress.today.completions.filter { $0.ritualID == id }
    }

    @Test("A count over its target ticks the activity off, as Apple Health's")
    func ticksOff() async {
        let (vm, fake) = makeViewModel()
        fake.values[.steps] = 7_999
        await vm.sweepHealth()
        #expect(!vm.isDone("steps"), "one short is not done")

        fake.values[.steps] = 8_000
        await vm.sweepHealth()
        #expect(vm.isDone("steps"))
        #expect(vm.checkedByHealth("steps"))
        #expect(vm.healthChecks(vm.ritual("steps")!))
    }

    @Test("Health ticks off once a day, and an undo stands")
    func firesOnceAndUndoStands() async {
        let (vm, fake) = makeViewModel()
        fake.values[.steps] = 12_000
        await vm.sweepHealth()
        await vm.sweepHealth()
        #expect(completions(vm, "steps").count == 1)

        vm.tapRitual("steps")   // done → taken back
        #expect(!vm.isDone("steps"))
        await vm.sweepHealth()
        #expect(!vm.isDone("steps"), "the steps are still there; the undo is the person's answer")

        // A tap now asks rather than letting Health take it back again.
        await vm.checkWithHealth("steps")
        #expect(!vm.isDone("steps"))
        #expect(vm.honorRitualID == "steps")
        vm.keepPromise("steps")
        #expect(completions(vm, "steps").map(\.method) == [.honor])
    }

    @Test("A box ticked by hand is never taken back or rewritten by Health")
    func neverUndoesAManualTick() async {
        let (vm, fake) = makeViewModel()
        fake.values[.steps] = 0
        vm.keepPromise("steps")
        await vm.sweepHealth()
        #expect(vm.isDone("steps"), "a low count never unticks anything")

        fake.values[.steps] = 20_000
        await vm.sweepHealth()
        #expect(completions(vm, "steps").map(\.method) == [.honor], "still the person's word, once")
        #expect(!vm.checkedByHealth("steps"))
    }

    @Test("A tap looks once more, and asks when Health has not counted enough")
    func tapPath() async {
        let (vm, fake) = makeViewModel(week: ["steps", "workout"])
        fake.values[.steps] = 9_000
        fake.values[.workoutMinutes] = 5
        // No sweep yet, as if the app had sat open on the desk all walk.
        await vm.checkWithHealth("steps")
        #expect(vm.isDone("steps") && vm.checkedByHealth("steps"))
        #expect(vm.honorRitualID == nil)

        await vm.checkWithHealth("workout")
        #expect(!vm.isDone("workout"))
        #expect(vm.honorRitualID == "workout")
    }

    @Test("Nothing Health shows, nothing ticked: a refusal leaves Your Word")
    func refusedReadsAsYourWord() async {
        let (vm, fake) = makeViewModel()
        fake.visible = []
        fake.values[.steps] = 50_000
        await vm.sweepHealth()
        #expect(!vm.isDone("steps"))
        #expect(!vm.healthChecks(vm.ritual("steps")!), "the row is drawn as Your Word")
    }

    @Test("Health ticks nothing off a locked day, or off a declined Health")
    func lockedAndDeclined() async {
        let (vm, fake) = makeViewModel()
        fake.values[.steps] = 50_000
        vm.keepsNewDays = { false }
        await vm.sweepHealth()
        #expect(!vm.isDone("steps"))

        let (declined, other) = makeViewModel(decision: .declined)
        other.values[.steps] = 50_000
        await declined.sweepHealth()
        #expect(!declined.isDone("steps"))
        #expect(other.reads == 0)
    }

    @Test("Only today's activities are read, and only the measurable ones")
    func onlyToday() async {
        let (vm, fake) = makeViewModel(week: ["steps", "read", "workout"])
        let other = vm.progress.currentDay.weekday == 1 ? 2 : 1
        vm.moveActivity("workout", from: vm.progress.currentDay.weekday, to: other)
        fake.values[.steps] = 9_000
        fake.values[.workoutMinutes] = 90
        await vm.sweepHealth()
        #expect(vm.isDone("steps"))
        #expect(!vm.isDone("workout"), "Thursday's training is not today's")
        #expect(!vm.isDone("read"))
    }

    // MARK: Permission

    @Test("Nothing is asked at launch, and nothing during the first run")
    func neverAtLaunchOrInTheFirstRun() async {
        let suite = UserDefaults(suiteName: "forge.tests.\(UUID().uuidString)") ?? .standard
        let vm = ForgeViewModel(progress: ProgressStore(defaults: suite))
        let fake = FakeHealth()
        vm.health = fake
        vm.resetFirstRun()
        #expect(vm.healthPrimer == nil, "launch raises nothing")

        // The first run's plan takes on Winter's steps and training.
        vm.activeRitualIDs = ["steps", "workout", "read"]
        #expect(vm.healthPrimer == nil)
        vm.tapRitual("steps")
        #expect(vm.healthPrimer == nil, "never during the first run")
        #expect(vm.honorRitualID == "steps", "the tap is answered the ordinary way")
        await vm.sweepHealth()
        #expect(fake.requests == 0 && fake.reads == 0)
    }

    @Test("The primer comes up once, the first time a measurable activity arrives")
    func primerOnce() async {
        let (vm, fake) = makeViewModel(week: ["read"], decision: .undecided)
        vm.activeRitualIDs.append("water")
        #expect(vm.healthPrimer == nil, "nothing measurable arrived")

        vm.addRitual("steps")
        #expect(vm.healthPrimer == HealthPrimerTestRequest.added("steps"))
        #expect(vm.isHealthPrimerWaiting)
        await vm.answerHealthPrimer(allow: false)
        #expect(vm.healthLedger.decision == .declined)
        #expect(fake.requests == 0, "a no on the primer never reaches iOS")

        vm.addRitual("workout")
        #expect(vm.healthPrimer == nil, "a no is final")
        vm.tapRitual("workout")
        #expect(vm.healthPrimer == nil)
        #expect(vm.honorRitualID == "workout")
    }

    @Test("Continue asks iOS once, and then Health reads")
    func primerContinue() async {
        let (vm, fake) = makeViewModel(week: ["read"], decision: .undecided)
        fake.values[.steps] = 9_000
        vm.addRitual("steps")
        await vm.answerHealthPrimer(allow: true)
        #expect(fake.requests == 1)
        #expect(vm.healthLedger.decision == .asked)
        #expect(vm.isDone("steps"), "read straight after the answer")

        vm.addRitual("workout")
        #expect(vm.healthPrimer == nil, "asked once")
    }

    @Test("A tap on a measurable row nobody was asked about brings the primer up")
    func primerFromATap() {
        let (vm, _) = makeViewModel(decision: .undecided)
        vm.healthPrimer = nil
        vm.tapRitual("steps")
        #expect(vm.healthPrimer == HealthPrimerTestRequest.tapped("steps"))
        #expect(vm.honorRitualID == nil)
    }

    @Test("An existing activity is offered Health once, and switches only on a yes")
    func offerOnExisting() {
        let (vm, _) = makeViewModel(week: ["run"], decision: .asked)
        var ledger = vm.healthLedger
        ledger.hasMigrated = false
        let migrated = HealthLedger.migrate(ledger, week: vm.activeRitualIDs, edits: vm.libraryEdits)
        vm.libraryEdits = migrated.edits
        vm.healthLedger = migrated.ledger

        #expect(vm.ritual("run")?.verification == .honor, "unchanged without asking")
        #expect(vm.offersHealth(for: "run"))
        vm.noteHealthOffered("run")
        #expect(!vm.offersHealth(for: "run"), "once")

        vm.letHealthCheck("run")
        #expect(vm.ritual("run")?.verification == .health)
        #expect(vm.libraryEdits["run"] == nil, "the pin came off and nothing else was written")
    }
}

/// Shorthand for the two ways the primer is raised.
private enum HealthPrimerTestRequest {
    static func added(_ id: String) -> ForgeViewModel.HealthPrimerRequest {
        .init(ritualID: id, fromTap: false)
    }
    static func tapped(_ id: String) -> ForgeViewModel.HealthPrimerRequest {
        .init(ritualID: id, fromTap: true)
    }
}

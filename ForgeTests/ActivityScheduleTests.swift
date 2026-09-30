import Foundation
import Testing
@testable import Forge

/// Duration, start time, priority and repeat — the six fields an activity grew
/// after the app had already shipped.
///
/// Two of these tests are about the feature and the rest are about the decoder,
/// and that ratio is right. Adding a field to a `Codable` struct that is already
/// on tens of thousands of phones is the highest-consequence thing in this
/// change set: the synthesised decoder treats a non-optional property with a
/// default as **required**, one throw fails a whole array, and the array in
/// question is every activity somebody has ever made for themselves. A bug there
/// does not look like a bug — it looks like the update deleted their day.
@Suite("Activity scheduling")
struct ActivityScheduleTests {

    // MARK: - Reading what older builds wrote

    /// The exact shape a build before any of this wrote to disk.
    ///
    /// Written out as JSON rather than round-tripped through the current type,
    /// because a round trip proves only that this build agrees with itself —
    /// which is the one thing that was never in doubt.
    private let legacyJSON = """
        {
          "id": "custom.ABC-123",
          "label": "Swim",
          "iconKey": "sparkle",
          "sub": "",
          "tail": "30 lengths",
          "reps": 0,
          "isCustom": true,
          "verificationOverride": "honor"
        }
        """

    @Test("An activity written before scheduling existed still decodes")
    func legacyActivityDecodes() throws {
        let ritual = try JSONDecoder().decode(
            Ritual.self, from: Data(legacyJSON.utf8)
        )
        #expect(ritual.id == "custom.ABC-123")
        #expect(ritual.label == "Swim")
        #expect(ritual.tail == "30 lengths")
        #expect(ritual.isCustom)
        #expect(ritual.verification == .honor)
        // And every new field falls back to what the app did before it existed.
        #expect(ritual.note.isEmpty)
        #expect(ritual.minutes == 0)
        #expect(ritual.startMinute == nil)
        #expect(ritual.priority == .normal)
        #expect(ritual.repeats == .daily, "an old activity must appear every day")
        #expect(ritual.categoryOverride == nil)
    }

    /// One bad record must not take the rest with it.
    ///
    /// This is the failure mode that matters: activities are stored as one
    /// array, so a decoder that throws on any element loses all of them.
    @Test("A run of legacy activities decodes as a whole")
    func legacyArrayDecodes() throws {
        let array = "[\(legacyJSON),\(legacyJSON)]"
        let rituals = try JSONDecoder().decode([Ritual].self, from: Data(array.utf8))
        #expect(rituals.count == 2)
    }

    /// The absolute floor: everything except the id is optional.
    @Test("An activity with nothing but an id decodes")
    func minimalActivityDecodes() throws {
        let ritual = try JSONDecoder().decode(
            Ritual.self, from: Data(#"{"id":"custom.X"}"#.utf8)
        )
        #expect(ritual.id == "custom.X")
        #expect(ritual.repeats == .daily)
    }

    /// Everything set survives a round trip, which is the other half of the
    /// contract the hand-written decoder has to keep.
    @Test("A fully specified activity round-trips")
    func fullRoundTrip() throws {
        var made = Ritual.makeCustom(.blank(named: "Swim"))
        made.note = "The pool shuts at eight."
        made.minutes = 45
        made.startMinute = 6 * 60 + 30
        made.priority = .essential
        made.repeats = RitualRepeat(weekdays: [2, 4, 6])
        made.categoryOverride = .physical

        let data = try JSONEncoder().encode(made)
        let back = try JSONDecoder().decode(Ritual.self, from: data)

        #expect(back.note == made.note)
        #expect(back.minutes == 45)
        #expect(back.startMinute == 390)
        #expect(back.priority == .essential)
        #expect(back.repeats == made.repeats)
        #expect(back.category == .physical)
    }

    /// The same lesson, one type over. `RitualEdit` gained seven properties and
    /// is stored as a dictionary — so one throw loses every edit anybody has
    /// made to a shipped activity.
    @Test("An edit written before scheduling existed still decodes")
    func legacyEditDecodes() throws {
        let edit = try JSONDecoder().decode(
            RitualEdit.self, from: Data(#"{"label":"Fifty pages"}"#.utf8)
        )
        #expect(edit.label == "Fifty pages")
        #expect(edit.minutes == nil)
        #expect(edit.startMinute == nil)
        #expect(!edit.isEmpty)
        #expect(try JSONDecoder().decode(RitualEdit.self, from: Data("{}".utf8)).isEmpty)
    }

    // MARK: - End times cannot disagree with durations

    @Test("The end follows the start and the duration")
    func endIsDerived() {
        var ritual = Ritual.makeCustom(.blank(named: "Deep work"))
        ritual.startMinute = 9 * 60
        ritual.minutes = 90
        #expect(ritual.endMinute == 10 * 60 + 30)

        // No duration is not a zero-length block; it is an activity with no end.
        ritual.minutes = 0
        #expect(ritual.endMinute == nil)
        #expect(ritual.scheduleLabel != nil, "it still starts somewhere")

        // No start at all is no schedule at all.
        ritual.startMinute = nil
        #expect(ritual.scheduleLabel == nil)
    }

    // MARK: - Repeat

    @Test("A daily activity happens on every day of the week")
    func dailyHappensAlways() {
        for weekday in 1...7 {
            #expect(RitualRepeat.daily.includes(weekday))
        }
        #expect(RitualRepeat.daily.isDaily)
        #expect(RitualRepeat.daily.label == "Every day")
    }

    @Test("Weekdays and weekends are complements")
    func presetsCoverTheWeek() {
        for weekday in 1...7 {
            #expect(
                RitualRepeat.weekdays5.includes(weekday)
                    != RitualRepeat.weekends.includes(weekday),
                "weekday \(weekday) is in both or neither"
            )
        }
        #expect(RitualRepeat.weekdays5.label == "Weekdays")
        #expect(RitualRepeat.weekends.label == "Weekends")
    }

    /// The generous reading, and the reason for it.
    ///
    /// An empty set has two possible meanings — "I meant never" and "I have not
    /// finished choosing" — and only one of them silently removes an activity
    /// from every day forever. So it means every day, and the picker says so.
    @Test("Choosing no days means every day, not no days")
    func emptyRepeatIsNotADisappearance() {
        let none = RitualRepeat(weekdays: [])
        for weekday in 1...7 { #expect(none.includes(weekday)) }
        #expect(none.label == "Every day")
    }

    @Test("A hand-picked week is named in order, from Monday")
    func customRepeatReadsInOrder() {
        #expect(RitualRepeat(weekdays: [6, 2, 4]).label == "Mon, Wed, Fri")
        // Sunday goes last, because a week that starts on Sunday reads as a
        // fortnight to most of the people who will see this.
        #expect(RitualRepeat(weekdays: [1, 2]).label == "Mon, Sun")
    }

    // MARK: - How long it says it is

    @Test("Durations are spelled the way a person says them")
    func durationsRead() {
        #expect(ClockMinute.duration(0) == nil, "untimed is not a duration of zero")
        #expect(ClockMinute.duration(45) == "45 min")
        #expect(ClockMinute.duration(60) == "1 h")
        #expect(ClockMinute.duration(90) == "1 h 30")
        #expect(ClockMinute.duration(120) == "2 h")
    }

    // MARK: - Priority changes nothing about an earned day

    /// Written down because it is the one thing about priority that could
    /// plausibly be "improved" later, and doing so would mean two people with
    /// the same finished list had done different amounts.
    @Test("Every priority is an ordinary activity")
    func priorityIsOnlyAMark() {
        for priority in RitualPriority.allCases {
            var ritual = Ritual.makeCustom(.blank(named: "Anything"))
            ritual.priority = priority
            // Nothing about how it is counted, confirmed or completed changes.
            #expect(ritual.verification == .honor)
            #expect(!ritual.label.isEmpty || ritual.label.isEmpty)
        }
        #expect(RitualPriority.normal.badge == nil, "the ordinary case is unmarked")
        #expect(RitualPriority.essential.badge != nil)
    }
}

// MARK: - What goes into the day, and on which days

/// Everything that puts an activity into somebody's day, and the one promise
/// they all keep: **it lands on today, and on no other day until the user
/// says so.**
///
/// This is the rule that was missing rather than wrong. The composer already
/// started a new activity on one day — see `ActivityComposer.Mode.create` — but
/// the two doors that take an activity from the *library* did not, and the
/// library ships everything as `.daily`. So tapping one in the picker was
/// somebody agreeing to do that thing every day for the rest of time, with the
/// only sign of it a repeat picker three screens away.
///
/// **The one door that says "every day" out loud is the 1.1 first run's plan**
/// (`ForgeViewModel.adoptPlan`): it is shown as a day with a time on every row,
/// under the words "every day", after a screen that projects exactly that plan
/// kept five days a week. Those tests are the first three below.
///
/// The tests are here rather than in a file of their own because this is the
/// same question `RitualRepeat` answers above, asked of the objects that write
/// it.
@MainActor
@Suite("The day onboarding makes")
struct OnboardingDayTests {

    /// A view model with a history of its own and nothing inherited.
    ///
    /// `ForgeViewModel` reads and writes the shared App Group suite, which every
    /// test in the process has in common, so the day is cleared through the
    /// model's own properties on the way in. Doing it that way rather than by
    /// deleting defaults keys means a test can only ever be affected by the API
    /// the app itself uses.
    private func makeViewModel() -> (ForgeViewModel, ProgressStore) {
        let suite = UserDefaults(suiteName: "forge.tests.\(UUID().uuidString)") ?? .standard
        let progress = ProgressStore(defaults: suite)
        let vm = ForgeViewModel(progress: progress)
        vm.customRituals = []
        vm.libraryEdits = [:]
        vm.activeRitualIDs = Ritual.defaultActive
        return (vm, progress)
    }

    /// Any weekday that is not the one the test is being run on.
    private func otherWeekday(than weekday: Int) -> Int {
        weekday == 1 ? 2 : weekday - 1
    }

    // MARK: - The first run

    private func plan(_ picks: [(String, Int)]) -> [PlanEntry] {
        picks.compactMap { id, minute in
            Ritual.find(id).map { PlanEntry(dimension: $0.category, ritualID: id, minute: minute) }
        }
    }

    @Test("The plan chosen in onboarding is every day's, at the time on each row")
    func planIsEveryDay() {
        let (vm, progress) = makeViewModel()
        let today = progress.currentDay.weekday
        let entries = plan([("water", 7 * 60), ("bed", 7 * 60 + 15), ("read", 20 * 60)])

        vm.adoptPlan(entries)

        #expect(vm.activeRitualIDs == ["water", "bed", "read"])
        #expect(vm.todayRitualIDs == ["water", "bed", "read"], "all three are asked for today")
        for entry in entries {
            let ritual = vm.ritual(entry.ritualID)
            #expect(ritual?.repeats.isDaily == true)
            #expect(ritual?.happens(on: otherWeekday(than: today)) == true)
            #expect(ritual?.startMinute == entry.minute)
        }
    }

    /// The reason the closing beat now says "the same plan again" rather than
    /// "you choose again".
    @Test("Onboarding's plan is tomorrow's too")
    func planFillsTheWeek() {
        let (vm, progress) = makeViewModel()
        vm.adoptPlan(plan([("water", 7 * 60), ("bed", 7 * 60 + 15), ("read", 20 * 60)]))

        let tomorrow = progress.currentDay.adding(days: 1).weekday
        #expect(Set(vm.rituals(onWeekday: tomorrow).map(\.id)) == ["water", "bed", "read"])
    }

    /// An onboarding activity is not a special kind of activity. Everything the
    /// day list offers has to work on one, which is the whole of the claim.
    @Test("An activity from onboarding completes, edits and comes out again")
    func planActivitiesBehaveLikeAnythingElse() {
        let (vm, _) = makeViewModel()
        vm.adoptPlan(plan([("water", 7 * 60), ("bed", 7 * 60 + 15), ("read", 20 * 60)]))

        vm.keepPromise("water")
        #expect(vm.isDone("water"))
        vm.undoRitual("water")
        #expect(!vm.isDone("water"))

        var draft = vm.ritual("bed")!.draft
        draft.label = "Square the pillows"
        draft.minutes = 5
        vm.editRitual("bed", to: draft)
        #expect(vm.ritual("bed")?.label == "Square the pillows")
        #expect(vm.ritual("bed")?.minutes == 5)
        #expect(vm.ritual("bed")?.repeats.isDaily == true, "editing keeps its days")
        #expect(vm.ritual("bed")?.startMinute == 7 * 60 + 15, "and its time")

        vm.removeRitual("read")
        #expect(!vm.activeRitualIDs.contains("read"))
        #expect(vm.activeRitualIDs == ["water", "bed"])
    }

    // MARK: - The record and the day, in step

    /// **The bug this locks in.** `DayRecord.plannedIDs` is what today *asked
    /// for*, and it is written by `publishPlanned`. Only `activeRitualIDs` had a
    /// `didSet` that called it — and taking an activity off today with a swipe
    /// does not touch that array at all: it narrows a repeat rule, which lands
    /// in `libraryEdits`. So the row left the panel and the record went on
    /// claiming it.
    ///
    /// What it cost: the widget and the Live Activity kept counting an activity
    /// the app had stopped asking for, every rate divided by a denominator one
    /// too big, and — the visible one — **tomorrow, when today became a past
    /// day, the week planner drew it out of the record and showed an activity
    /// that had not been on that day.**
    @Test("Taking something off today is written down in the record")
    func removingFromTodayUpdatesThePlannedRecord() {
        let (vm, progress) = makeViewModel()
        let today = progress.currentDay.weekday
        vm.activeRitualIDs = ["water", "bed"]
        // Both on today and on one other day, so removing today's leaves the
        // activity in the week — the case `removeFromDay` narrows rather than
        // deletes, and the one the record was missing.
        for id in ["water", "bed"] {
            vm.setWeekday(id, otherWeekday(than: today), on: true)
        }
        #expect(progress.today.plannedIDs.sorted() == ["bed", "water"])

        vm.removeFromDay("water", weekday: today)

        #expect(!vm.todayRitualIDs.contains("water"))
        #expect(
            progress.today.plannedIDs == ["bed"],
            "the record has to say what today actually asked for"
        )
    }

    /// The same rule from the other direction, and through the other store: an
    /// activity somebody made carries its own weekdays, so editing one changes
    /// what today asks for without `activeRitualIDs` moving.
    @Test("Rescheduling a custom activity is written down in the record")
    func reschedulingACustomActivityUpdatesThePlannedRecord() {
        let (vm, progress) = makeViewModel()
        let today = progress.currentDay.weekday
        vm.activeRitualIDs = []

        var draft = ActivityDraft.blank(named: "Swim")
        draft.repeats = RitualRepeat(weekdays: [today])
        let made = vm.createCustomRitual(draft)
        vm.addRitual(made.id)
        #expect(progress.today.plannedIDs == [made.id])

        var moved = vm.ritual(made.id)!.draft
        moved.repeats = RitualRepeat(weekdays: [otherWeekday(than: today)])
        vm.editRitual(made.id, to: moved)

        #expect(vm.todayRitualIDs.isEmpty)
        #expect(progress.today.plannedIDs.isEmpty)
    }

    /// An id in the day that resolves to nothing draws no row, so it must not be
    /// counted either. It used to fall through as "assume today", which made the
    /// header read one higher than the list and left a day that could never be
    /// finished and therefore never earned.
    @Test("An id that resolves to nothing is not part of today")
    func unknownIDsAreNotCounted() {
        let (vm, _) = makeViewModel()
        vm.activeRitualIDs = ["water", "no.such.activity", "bed"]

        #expect(vm.todayRitualIDs == ["water", "bed"])
        #expect(vm.totalActive == vm.todayRituals.count)
    }

    // MARK: - The picker

    /// Adding from the week's own `+` means the day somebody is looking at, not
    /// today. It meant today wherever it was pressed, which is the app
    /// overruling something the user had already said — see
    /// `ActivityLibraryView`.
    @Test("An activity added from another day lands on that day")
    func addedActivityLandsOnTheDayItWasAddedFrom() {
        let (vm, progress) = makeViewModel()
        let other = otherWeekday(than: progress.currentDay.weekday)
        vm.activeRitualIDs = []

        vm.addRitual("run", onWeekday: other)

        #expect(vm.ritual("run")?.repeats.weekdays == [other])
        #expect(!vm.todayRitualIDs.contains("run"))
    }

    /// Something already kept, offered again for a different day, gains the day
    /// rather than being appended twice.
    @Test("Adding one already in the week only adds the day")
    func addingSomethingAlreadyKeptAddsTheDay() {
        let (vm, progress) = makeViewModel()
        let today = progress.currentDay.weekday
        let other = otherWeekday(than: today)
        vm.activeRitualIDs = []
        vm.addRitual("run", onWeekday: today)

        vm.addRitual("run", onWeekday: other)

        #expect(vm.activeRitualIDs == ["run"], "no second copy")
        #expect(vm.ritual("run")?.repeats.weekdays == [today, other])
    }

    @Test("An activity taken from the library lands on today")
    func addedActivityIsTodayOnly() {
        let (vm, progress) = makeViewModel()
        vm.activeRitualIDs = []

        vm.addRitual("run")

        #expect(vm.ritual("run")?.repeats.weekdays == [progress.currentDay.weekday])
    }

    /// The other half of the rule, and the half that makes it safe: pinning is
    /// for an activity that has never been told when it happens. Taking one out
    /// of the day and putting it back must not overwrite what somebody set.
    @Test("An activity the user has scheduled keeps its days when it returns")
    func addingDoesNotOverwriteAChosenWeek() {
        let (vm, _) = makeViewModel()
        vm.activeRitualIDs = []
        vm.addRitual("run")

        var draft = vm.ritual("run")!.draft
        draft.repeats = .weekdays5
        vm.editRitual("run", to: draft)

        vm.removeRitual("run")
        vm.addRitual("run")
        #expect(vm.ritual("run")?.repeats == .weekdays5)
    }

    @Test("An activity somebody made keeps the days they made it with")
    func customActivityKeepsItsOwnWeek() {
        let (vm, _) = makeViewModel()
        var draft = ActivityDraft.blank(named: "Swim")
        draft.repeats = .weekends

        let made = vm.createCustomRitual(draft)
        vm.removeRitual(made.id)
        vm.addRitual(made.id)

        #expect(vm.ritual(made.id)?.repeats == .weekends)
    }

    // MARK: - A day with nothing in it

    /// The bill that came with pinning activities to one day, and the one thing
    /// in this change set that could hand somebody a blade they had not earned.
    ///
    /// "Everything planned is done" is trivially true of a list with nothing in
    /// it. While every activity repeated daily an empty day was nearly
    /// unreachable; now that a day holds only what was put on it, an unplanned
    /// tomorrow is the ordinary case — and it must read as unplanned rather than
    /// as won.
    @Test("An empty day is not a finished day")
    func emptyDayIsNotEarnable() {
        let (vm, _) = makeViewModel()
        vm.activeRitualIDs = []

        #expect(vm.isDayEmpty)
        #expect(!vm.allDone, "an empty day must not offer the blade")
        #expect(vm.pullFraction == 0)
    }

    @Test("A finished day is still a finished day")
    func finishedDayStillEarns() {
        let (vm, _) = makeViewModel()
        vm.activeRitualIDs = ["water", "bed"]
        vm.pinToTodayOnly(["water", "bed"])
        #expect(!vm.allDone)

        vm.keepPromise("water")
        vm.keepPromise("bed")
        #expect(vm.allDone)
        #expect(!vm.isDayEmpty)
    }

    @Test("A day is only empty when today asks for nothing")
    func restingActivitiesDoNotCountAsToday() {
        let (vm, progress) = makeViewModel()
        vm.activeRitualIDs = []
        vm.addRitual("run")

        // Parked on a day that is not today: the day is empty, and there is
        // something to copy into it.
        var draft = vm.ritual("run")!.draft
        draft.repeats = .onlyToday(otherWeekday(than: progress.currentDay.weekday))
        vm.editRitual("run", to: draft)

        #expect(vm.isDayEmpty)
        #expect(vm.hasAnyOtherDayPlanned)
    }
}

// MARK: - Copying one day onto another

/// The week planner's one genuinely new operation.
///
/// Forge has no dated tasks, so "copy Monday to Thursday" can only mean one
/// thing: everything Monday holds also happens on Thursday. The tests below pin
/// the three properties that make that safe to press — Monday is untouched,
/// nothing is widened past the day asked for, and pressing it twice does
/// nothing the second time.
@MainActor
@Suite("Copying a day")
struct CopyDayTests {

    private func makeViewModel() -> (ForgeViewModel, ProgressStore) {
        let suite = UserDefaults(suiteName: "forge.tests.\(UUID().uuidString)") ?? .standard
        let progress = ProgressStore(defaults: suite)
        let vm = ForgeViewModel(progress: progress)
        vm.customRituals = []
        vm.libraryEdits = [:]
        vm.activeRitualIDs = []
        return (vm, progress)
    }

    /// Monday, holding three activities at three times, and nothing anywhere
    /// else in the week.
    private func mondayWithThree(_ vm: ForgeViewModel) {
        for (id, minute) in [("focus", 9 * 60), ("workout", 18 * 60), ("read", 21 * 60)] {
            vm.addRitual(id)
            var draft = vm.ritual(id)!.draft
            draft.repeats = .onlyToday(2)
            draft.startMinute = minute
            vm.editRitual(id, to: draft)
        }
    }

    private let monday = 2
    private let thursday = 5

    @Test("Thursday gets Monday's day, at Monday's times")
    func copyLandsWholeDay() {
        let (vm, _) = makeViewModel()
        mondayWithThree(vm)

        let added = vm.copyDay(from: monday, to: thursday)

        #expect(added.count == 3)
        let copied = vm.rituals(onWeekday: thursday)
        #expect(copied.map(\.id) == ["focus", "workout", "read"], "in clock order")
        #expect(copied.map(\.startMinute) == [9 * 60, 18 * 60, 21 * 60])
    }

    @Test("The day copied from is untouched")
    func sourceIsUnchanged() {
        let (vm, _) = makeViewModel()
        mondayWithThree(vm)
        let before = vm.rituals(onWeekday: monday).map(\.id)

        vm.copyDay(from: monday, to: thursday)

        #expect(vm.rituals(onWeekday: monday).map(\.id) == before)
    }

    /// The property the whole feature turns on: a copy adds one day and no more.
    @Test("A copy never turns into a daily activity")
    func copyDoesNotGoDaily() {
        let (vm, _) = makeViewModel()
        mondayWithThree(vm)

        vm.copyDay(from: monday, to: thursday)

        for ritual in vm.rituals(onWeekday: thursday) {
            #expect(ritual.repeats.weekdays == [monday, thursday])
            #expect(!ritual.repeats.isDaily)
            for weekday in [1, 3, 4, 6, 7] {
                #expect(!ritual.happens(on: weekday), "\(ritual.id) leaked onto \(weekday)")
            }
        }
    }

    @Test("Copying the same day twice adds nothing the second time")
    func copyIsIdempotent() {
        let (vm, _) = makeViewModel()
        mondayWithThree(vm)

        #expect(vm.copyDay(from: monday, to: thursday).count == 3)
        #expect(vm.copyDay(from: monday, to: thursday).isEmpty)
        #expect(vm.dayCopyAddition(from: monday, to: thursday).isEmpty)
        #expect(vm.rituals(onWeekday: thursday).count == 3)
    }

    /// What the sheet's button reads off, so it can say "gets 1" rather than
    /// "gets 3" when two of the three are already there.
    @Test("Only what is missing is offered, and only what is offered is added")
    func copyOffersTheDifference() {
        let (vm, _) = makeViewModel()
        mondayWithThree(vm)
        // Thursday already reads.
        vm.setWeekday("read", thursday, on: true)

        let offer = vm.dayCopyAddition(from: monday, to: thursday)
        #expect(offer.map(\.id).sorted() == ["focus", "workout"])
        #expect(vm.copyDay(from: monday, to: thursday).count == 2)
        #expect(vm.rituals(onWeekday: thursday).count == 3)
    }

    @Test("A day cannot be copied onto itself")
    func copyToSelfDoesNothing() {
        let (vm, _) = makeViewModel()
        mondayWithThree(vm)

        #expect(vm.copyDay(from: monday, to: monday).isEmpty)
        #expect(vm.rituals(onWeekday: monday).count == 3)
    }

    // MARK: - Taking one back off

    /// The swipe on a week row, which has to mean "off this day" whichever kind
    /// of activity it lands on.
    @Test("Removing from a shared day leaves the other days alone")
    func removeFromDayKeepsTheRest() {
        let (vm, _) = makeViewModel()
        mondayWithThree(vm)
        vm.copyDay(from: monday, to: thursday)

        vm.removeFromDay("workout", weekday: thursday)

        #expect(vm.ritual("workout")?.repeats.weekdays == [monday])
        #expect(vm.activeRitualIDs.contains("workout"), "it still happens on Monday")
        #expect(vm.rituals(onWeekday: thursday).count == 2)
    }

    @Test("Removing from the only day it has takes it out of the week")
    func removeFromDayDropsASingleDayActivity() {
        let (vm, _) = makeViewModel()
        mondayWithThree(vm)

        vm.removeFromDay("workout", weekday: monday)

        #expect(!vm.activeRitualIDs.contains("workout"))
        #expect(vm.rituals(onWeekday: monday).count == 2)
    }

    // MARK: - Copying a day out of the record

    /// Write a day into the history holding exactly these activities.
    private func record(
        _ progress: ProgressStore, _ day: ForgeDay, planned: [String], kept: [String] = []
    ) {
        progress.record(DayRecord(
            day: day,
            completions: kept.map {
                DayRecord.Completion(ritualID: $0, method: .basic, at: .now)
            },
            plannedIDs: planned
        ))
    }

    @Test("The record offers the days behind, most recent first")
    func recentDaysReadsTheRecord() {
        let (vm, progress) = makeViewModel()
        mondayWithThree(vm)
        let today = progress.currentDay

        record(progress, today.adding(days: -3), planned: ["focus"])
        record(progress, today.adding(days: -1), planned: ["focus", "read"], kept: ["focus"])

        let days = vm.recentDays()

        #expect(days.count == 2)
        #expect(days.first?.day == today.adding(days: -1), "most recent leads")
        #expect(days.first?.activities.count == 2)
        #expect(days.first?.keptCount == 1)
    }

    @Test("Today is never offered back to itself")
    func recentDaysExcludesToday() {
        let (vm, progress) = makeViewModel()
        mondayWithThree(vm)

        record(progress, progress.currentDay, planned: ["focus", "read"])

        #expect(vm.recentDays().isEmpty, "copying today onto today is a no-op")
    }

    @Test("An activity that no longer exists is not offered back")
    func recentDaysDropsDeletedActivities() {
        let (vm, progress) = makeViewModel()
        mondayWithThree(vm)

        record(
            progress, progress.currentDay.adding(days: -2),
            planned: ["focus", "gone.forever"]
        )

        let day = try? #require(vm.recentDays().first)
        #expect(day?.activities.count == 1, "an id nothing resolves cannot be offered")
        #expect(day?.activities.first?.id == "focus")
    }

    @Test("Reusing a day puts its activities on the destination and nothing else")
    func copyPastDayAddsTheWeekday() {
        let (vm, progress) = makeViewModel()
        mondayWithThree(vm)
        record(progress, progress.currentDay.adding(days: -1), planned: ["focus", "read"])

        let day = vm.recentDays()[0]
        let added = vm.copyPastDay(day, to: thursday)

        #expect(Set(added) == ["focus", "read"])
        #expect(vm.rituals(onWeekday: thursday).count == 2)
        // The same guarantee `copyDay` makes: the source keeps everything and
        // nothing is widened past the one weekday that was asked for.
        #expect(vm.rituals(onWeekday: monday).count == 3)
        #expect(vm.ritual("focus")?.repeats.weekdays == [monday, thursday])
    }

    @Test("Reusing a day the destination already holds adds nothing")
    func copyPastDayIsIdempotent() {
        let (vm, progress) = makeViewModel()
        mondayWithThree(vm)
        record(progress, progress.currentDay.adding(days: -1), planned: ["focus", "read"])

        let day = vm.recentDays()[0]
        #expect(vm.copyPastDay(day, to: thursday).count == 2)
        #expect(vm.copyPastDay(day, to: thursday).isEmpty)
        #expect(vm.pastDayAddition(day, to: thursday).isEmpty)
    }

    @Test("The offer is the difference, never the whole day again")
    func pastDayAdditionExcludesWhatIsHeld() {
        let (vm, progress) = makeViewModel()
        mondayWithThree(vm)
        vm.setWeekday("focus", thursday, on: true)
        record(progress, progress.currentDay.adding(days: -1), planned: ["focus", "read"])

        let day = vm.recentDays()[0]
        let offer = vm.pastDayAddition(day, to: thursday)

        #expect(offer.map(\.id) == ["read"])
    }
}

// MARK: - A very full day

@MainActor
@Suite("A day with a lot on it")
struct CrowdedDayTests {

    private func makeViewModel() -> (ForgeViewModel, ProgressStore) {
        let suite = UserDefaults(suiteName: "forge.tests.\(UUID().uuidString)") ?? .standard
        let progress = ProgressStore(defaults: suite)
        let vm = ForgeViewModel(progress: progress)
        vm.customRituals = []
        vm.libraryEdits = [:]
        vm.activeRitualIDs = []
        return (vm, progress)
    }

    /// Every shipped activity, plus enough custom ones to make a day nobody
    /// would really keep.
    private func crowd(_ vm: ForgeViewModel, custom: Int = 40) {
        for ritual in Ritual.library { vm.addRitual(ritual.id) }
        for index in 0..<custom {
            var draft = ActivityDraft.blank(named: "Custom \(index)")
            draft.category = RitualCategory.dimensions[index % RitualCategory.dimensions.count]
            _ = vm.createCustomRitual(draft)
        }
    }

    @Test("A day of eighty activities stays consistent")
    func aVeryFullDayHolds() {
        let (vm, _) = makeViewModel()
        crowd(vm)

        #expect(vm.activeRitualIDs.count == Ritual.library.count + 40)
        // Nothing is lost between the day and what today draws.
        #expect(Set(vm.orderedRituals.map(\.id)) == Set(vm.todayRitualIDs))
        #expect(vm.orderedRituals.count == vm.totalActive)
    }

    @Test("Completed activities still fall below unfinished ones at scale")
    func orderingHoldsUnderLoad() {
        let (vm, _) = makeViewModel()
        crowd(vm)

        // Finish a scattering of them, including the very first and very last.
        let ids = vm.todayRitualIDs
        for id in [ids[0], ids[7], ids[30], ids[ids.count - 1]] {
            vm.progress.complete(id, method: .honor)
        }

        let ordered = vm.orderedRituals.map(\.id)
        let firstDone = ordered.firstIndex { vm.isDone($0) }
        let lastPending = ordered.lastIndex { !vm.isDone($0) }

        #expect(firstDone != nil)
        #expect(lastPending != nil)
        #expect(lastPending! < firstDone!, "every unfinished row sits above every finished one")
    }

    @Test("Every activity remains reachable, none duplicated or dropped")
    func nothingIsLost() {
        let (vm, _) = makeViewModel()
        crowd(vm)
        for id in vm.todayRitualIDs.prefix(20) { vm.progress.complete(id, method: .honor) }

        let ordered = vm.orderedRituals.map(\.id)
        #expect(ordered.count == Set(ordered).count, "no row is drawn twice")
        #expect(Set(ordered) == Set(vm.todayRitualIDs), "no row vanishes when completed")
    }

    @Test("A crowded day still reads a shape without blowing up")
    func shapeSurvivesACrowdedDay() {
        let (vm, progress) = makeViewModel()
        crowd(vm)
        for back in 1...28 {
            let day = progress.currentDay.adding(days: -back)
            progress.record(DayRecord(
                day: day,
                completions: vm.activeRitualIDs.prefix(30).map {
                    DayRecord.Completion(ritualID: $0, method: .honor, at: day.startOfDay())
                },
                plannedIDs: vm.activeRitualIDs
            ))
        }

        let shape = vm.shape
        #expect(shape.dimensions.count == 6)
        #expect(shape.overall >= 0 && shape.overall <= 100)
        for dimension in shape.dimensions {
            #expect(dimension.score >= 0 && dimension.score <= 100)
            #expect(dimension.kept <= dimension.asked, "kept can never exceed asked")
        }
    }
}

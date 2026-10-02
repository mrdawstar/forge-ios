import SwiftUI

@Observable
final class ForgeViewModel {
    /// Where the day actually lives. Everything about *what has been done*
    /// is read straight back out of here rather than mirrored into this class,
    /// so force-quitting halfway through a day loses nothing and there is no
    /// second copy to fall out of step.
    let progress: ProgressStore

    var activeRitualIDs: [String] = Ritual.defaultActive {
        didSet {
            persist()
            publishPlanned()
            noteArrivals(since: oldValue)
        }
    }
    /// Activities the user made. Kept whole even when one is taken out of the
    /// day, so removing it from today's list is not the same as throwing it
    /// away — it stays in the picker to be put back.
    ///
    /// **`publishPlanned` for the same reason `activeRitualIDs` does it**: a
    /// custom activity carries its own weekdays, so editing one can add today's
    /// weekday or take it away, and the record has to be told. See
    /// `libraryEdits` below, where the bug this fixes actually showed.
    var customRituals: [Ritual] = [] { didSet { persist(); publishPlanned() } }
    /// What the user has taught the classifier by disagreeing with it.
    var verificationMemory: VerificationMemory = .empty { didSet { persist() } }
    /// Changes the user has made to library activities.
    ///
    /// An overlay rather than a copy: a renamed "Drink water" still tracks the
    /// definition it came from, so a later change to its verification spec or
    /// subtitle reaches the people who renamed it. It also makes "reset to
    /// default" a deletion rather than a restore.
    ///
    /// # Why this writes the day down again
    ///
    /// Because **an edit here changes what today is asking for**, and until this
    /// line existed nothing told the record. `activeRitualIDs` is the list, and
    /// only the list had a `didSet`: taking an activity off today with a swipe
    /// calls `setWeekday`, which narrows a repeat rule and touches *this*
    /// dictionary, not that array. So the row left the panel and
    /// `DayRecord.plannedIDs` went on claiming it.
    ///
    /// What that cost, in order of how visible it was: the widget and the Live
    /// Activity kept counting an activity the app had stopped asking for; the
    /// completion rate and the Shape divided by a denominator that was one too
    /// big; and — the one somebody would actually report — **tomorrow, when
    /// today became a past day, the week planner drew it out of the record and
    /// showed an activity that had not been on that day.** The planner reads
    /// `plannedIDs` for a day already lived, which is right, and `plannedIDs`
    /// was wrong.
    var libraryEdits: [String: RitualEdit] = [:] { didSet { persist(); publishPlanned() } }

    /// The parts of themselves somebody said they wanted to build.
    ///
    /// # Why this is stored at all, when the Shape is derived
    ///
    /// Because they are two different facts and the difference is the whole
    /// point. `ForgeShape` is what somebody's record **says about them** — read
    /// off completed days, never stored, and unable to lie. This is what they
    /// **said they wanted**, which no record can infer: nothing in a history of
    /// dishes and push-ups says a person meant to become steadier with people.
    ///
    /// Keeping both is what lets Forge say the one sentence it could not say
    /// before: *you chose Relationship, and it is the lowest of the six.* An app
    /// with only the derived half can rank; an app with only the stated half is
    /// a wishlist. The gap between them is the only place advice can honestly
    /// come from, and it is what `DayPlanner` reads.
    ///
    /// **Empty is ordinary and must stay ordinary.** Somebody who skipped the
    /// question — or who installed before this existed — has an empty set, and
    /// every reader falls back to what it did before: the planner uses the
    /// weakest measured dimension instead, the first run offers the shipped
    /// eight, and nothing anywhere is withheld.
    var focus: Set<RitualCategory> = [] { didSet { persist() } }

    /// What somebody said about themselves in the seven questions, and when.
    ///
    /// **Stated data, like `focus`**, and kept for the same reason: no record
    /// can infer how much somebody trained before they installed the app. Only
    /// the answers and the day are stored (`Assessment.key`); every starting
    /// number is derived from them on read, and `blended` is where they meet
    /// the record.
    ///
    /// **Nil is ordinary.** Every 1.0 install has none until they take it from
    /// the Becoming tab, and every reader falls back to the record alone —
    /// `BlendedShape` with no assessment is `ForgeShape`, number for number.
    var assessment: Assessment? {
        didSet {
            guard isLoaded, assessment != oldValue else { return }
            Assessment.write(assessment, to: ForgeShared.defaults)
        }
    }

    /// The activity waiting on an "I kept my promise" — honor activities get a
    /// moment of their own rather than a checkbox.
    var honorRitualID: String? = nil

    // MARK: Apple Health (DIRECTION_1_1 §8)

    /// Where Health is read from. The live `HealthBridge` in the app; tests
    /// hand in a fake, so nothing here needs a phone.
    var health: HealthReading = HealthBridge.shared

    /// What Forge remembers about Health: the primer's answer, the one offer
    /// on each existing activity, and what Health ticked off today. Decisions,
    /// never readings. See `HealthLedger`.
    var healthLedger = HealthLedger() {
        didSet {
            guard isLoaded, healthLedger != oldValue else { return }
            healthLedger.write(to: ForgeShared.defaults)
        }
    }

    /// The metrics Health showed anything of on the last read. In memory only:
    /// it is a reading, and readings are not kept. A refusal on the iOS sheet
    /// shows up here as nothing visible, and the rows then stay Your Word.
    private(set) var healthVisible: Set<ActivityMetric> = []

    /// The primer, waiting for the Forge tab to be calm enough to show it.
    var healthPrimer: HealthPrimerRequest?

    struct HealthPrimerRequest: Equatable {
        /// The measurable activity that brought it up.
        let ritualID: String
        /// A tap on the row, rather than the activity arriving: after the
        /// answer, the tap still deserves an answer of its own.
        let fromTap: Bool
    }

    /// Whether new days can be kept right now (DIRECTION_1_1 §1). Health does
    /// not tick anything off a day that is locked; set from the store by
    /// `ContentView` as a reading of the store. True until StoreKit answers,
    /// as everywhere else.
    var keepsNewDays: () -> Bool = { true }

    private var isSweeping = false
    private var sweepAgain = false

    var doneIDs: Set<String> { progress.todayCompletedIDs }
    /// The order rituals were finished in, so a completed one drops to the
    /// *bottom of the list* rather than to the bottom of its own original slot.
    private var doneOrder: [String] { progress.todayCompletedOrder }

    var streak: Int { progress.currentStreak }
    var daysKept: Int { progress.daysKept }

    /// The blade is out of the stone. Reached only by dragging it free (§5.6),
    /// never by completing the last ritual — finishing the rituals makes it
    /// *loose*, and the user still has to pull.
    ///
    /// Backed by the day's record rather than by a flag, so a blade pulled at
    /// seven is still out when the app is reopened at nine.
    var isOut: Bool {
        get { progress.isTodayEarned }
        set {
            guard newValue else { progress.clearEarned(); return }
            guard !progress.isTodayEarned else { return }
            // Read before the day is marked: both are about what was true the
            // moment before the blade came out.
            let isFirstPull = !hasCompletedFirstRun
            let wasReturning = isReturning
            progress.markEarned()
            ForgeTelemetry.send(.dayEarned)
            if isFirstPull { ForgeTelemetry.send(.firstPullCompleted) }
            // A day earned by somebody the re-entry screen was for. Derived from
            // the same gap `ReEntry` reads, so nothing is kept to know it.
            if wasReturning { ForgeTelemetry.send(.reentryRecovered) }
        }
    }

    /// Live 0…1 pull, mirrored from the physics engine every frame.
    var pull: Double = 0
    var pullProgress: Double = 0
    var showEditRituals: Bool = false
    /// QuickAdd, from the day panel's `+`. On the view model, beside the
    /// editor's flag, so a notification landing on the Forge tab can put it
    /// away the same way (`ContentView.landOnHome`).
    var showQuickAdd: Bool = false
    var reviewOpen: Bool = false
    var showTomorrow: Bool = false

    // MARK: - First run

    /// How far into the first run somebody is.
    ///
    /// Held in memory only. Quitting halfway starts it again, which is the right
    /// trade for a two-minute sequence — resuming into the middle of it would
    /// drop somebody on a screen with no idea how they got there.
    var firstRunStage: FirstRunStage = .coldOpen {
        didSet {
            guard firstRunStage != oldValue, !hasCompletedFirstRun,
                  let step = ForgeTelemetry.Step(firstRunStage) else { return }
            ForgeTelemetry.send(.onboardingStep(step))
        }
    }

    /// Whether the first run has ever been finished. The only part persisted.
    private(set) var hasCompletedFirstRun: Bool = false

    /// The beats, in order. Everything up to `pull` happens over the top of the
    /// app; the pull itself happens on the real home screen, where every pull
    /// after it will.
    ///
    /// Straight through, one screen per beat (§17.1), with one branch: the
    /// paywall is passed by anybody who already has the practice (§17.2). The
    /// 1.0 sequence — promise, build, choose, metaphor — was replaced in 1.1 by
    /// one that shows somebody where they are and where the same arithmetic
    /// says they would be, before it asks them to do anything (DIRECTION_1_1
    /// §2).
    enum FirstRunStage: Equatable {
        /// The sword in the stone, and what keeping a day does to it.
        case coldOpen
        /// One of the seven questions, by index into
        /// `Assessment.Question.allCases`. One screen each, one tap each.
        case question(Int)
        /// **What they want to build**, as any number of the six. Preselected
        /// from the two lowest answers, skippable, and skipping costs nothing.
        ///
        /// This was `who` — "Who are you becoming?" — before 1.0 shipped, and
        /// the argument for replacing it still holds: a stranger cannot answer
        /// an identity question in their first minute, and anybody can point at
        /// the parts of themselves they want stronger. See `ForgeViewModel.focus`.
        case build
        /// The starting shape drawing itself from the answers, about two and a
        /// half seconds, tap to skip.
        case drawing
        /// Now, in seven days, in thirty, and at full potential: the six, OVR
        /// and the blade each stage earns. See `Transformation`.
        case transformation
        /// Three cited findings, each with the part of Forge it explains.
        case science
        /// The proposed day, with a time on every activity. Writes the day.
        case plan
        /// The blade, pulled once with nothing at stake.
        case metaphor
        /// Forge Pro: a free week, then a decision (DIRECTION_1_1 §1). Passed
        /// straight through by anybody who already has the practice — a
        /// founder, a subscriber, a restore. See `PaywallView`.
        case paywall
        /// The one thing they go and do now.
        case doOne
        /// The cover is gone and they are pulling on the real home screen.
        case pull
        /// The blade is out. One line, and the offer of a reminder.
        case closing
        case finished
    }

    var isFirstRunCovering: Bool {
        switch firstRunStage {
        case .coldOpen, .question, .build, .drawing, .transformation, .science,
             .plan, .metaphor, .paywall, .doOne:
            !hasCompletedFirstRun
        case .pull, .closing, .finished:
            false
        }
    }

    /// The one day the blade comes loose without the list being finished.
    ///
    /// A first pull has to happen on the day somebody installs, at whatever hour
    /// that is, or the product does not exist for them until tomorrow — and
    /// most of them will not be there tomorrow. Everything about it is real: the
    /// drag, the record it writes, the blade it earns. The only thing waived is
    /// the requirement, and only this once.
    var isFirstPullGranted: Bool {
        !hasCompletedFirstRun && (firstRunStage == .pull || firstRunStage == .closing)
    }

    init(progress: ProgressStore) {
        self.progress = progress
        load()
        publishPlanned()
    }

    // MARK: - Storage
    //
    // Only what the user *arranged* is kept here: their own activities, and the
    // order of the day. What they have *done* belongs to `ProgressStore`,
    // which owns the whole history and persists it under its own keys.

    private enum Key {
        static let firstRun = "forge.hasCompletedFirstRun.v1"
        static let custom = "forge.customRituals.v1"
        static let active = "forge.activeRituals.v1"
        static let memory = "forge.verificationMemory.v1"
        static let edits = "forge.libraryEdits.v1"
        static let commitment = "forge.commitment.v1"
        static let shape = "forge.dayShape.v1"
        static let focus = "forge.focus.v1"
    }

    /// Suppresses the `didSet` writes that loading would otherwise trigger.
    private var isLoaded = false

    private func load() {
        defer { isLoaded = true }
        let defaults = ForgeShared.defaults

        hasCompletedFirstRun = defaults.bool(forKey: Key.firstRun)
        // **A day that was earned means the first run is behind you**, whatever
        // the flag says.
        //
        // The flag is only written at the very end of the sequence, from the
        // closing beat — and the beat before it is the *real home screen*, where
        // the first pull happens. So the whole window between the blade coming
        // out and the closing beat being dismissed is a window in which the flag
        // is still false. Anything that ends the process in it — a force quit, a
        // call, the OS reclaiming memory, the phone being put down overnight —
        // brings the app back to the promise screen for somebody who has already
        // kept a day, with their activities, their blade and their history
        // sitting behind it.
        //
        // And it is not merely embarrassing, it is a trap: the sequence cannot
        // finish a second time. Its last beat waits for the day to be earned,
        // today's day is already earned, so nothing fires and there is no way
        // out of onboarding until tomorrow.
        //
        // Read from the record rather than patched with a second flag, because
        // the record is the thing that cannot be wrong (§5.2). Nobody reaches an
        // earned day without having been through the first run, so this can only
        // ever be true of somebody it is true of.
        if !hasCompletedFirstRun, progress.records.contains(where: \.isEarned) {
            hasCompletedFirstRun = true
            defaults.set(true, forKey: Key.firstRun)
        }
        if hasCompletedFirstRun { firstRunStage = .finished }

        if let data = defaults.data(forKey: Key.custom),
           let decoded = try? JSONDecoder().decode([Ritual].self, from: data) {
            customRituals = decoded
        }
        if let data = defaults.data(forKey: Key.memory),
           let decoded = try? JSONDecoder().decode(VerificationMemory.self, from: data) {
            verificationMemory = decoded
        }
        if let data = defaults.data(forKey: Key.edits),
           let decoded = try? JSONDecoder().decode([String: RitualEdit].self, from: data) {
            libraryEdits = decoded
        }
        if let data = defaults.data(forKey: Key.commitment),
           let decoded = try? JSONDecoder().decode(DayCommitment.self, from: data) {
            commitment = decoded
        }
        if let data = defaults.data(forKey: Key.shape),
           let decoded = try? JSONDecoder().decode(DayShape.self, from: data) {
            storedShape = decoded
        }
        // Raw strings through the tolerant initialiser, so a dimension renamed
        // in a later version drops out of the set rather than failing the whole
        // read. An empty focus is the ordinary state, so there is nothing here
        // worth throwing over.
        if let saved = defaults.stringArray(forKey: Key.focus) {
            focus = Set(saved.compactMap(RitualCategory.init(migrating:)).filter { $0 != .all })
        }
        // Tolerant all the way down (`Assessment.init(from:)`): an answer this
        // version cannot read is dropped on its own, and only a record with no
        // day at all reads as no assessment.
        assessment = Assessment.read(from: defaults)
        // Custom activities have to be in hand before the order is read, or
        // every custom id in it would fail to resolve and be dropped.
        if let saved = defaults.stringArray(forKey: Key.active) {
            let known = saved.filter { ritual($0) != nil }
            if !known.isEmpty { activeRitualIDs = known }
        }
        // Last, because it reads the week and the edits. The 1.1 switch to
        // Health keeps every existing measurable activity as Your Word until
        // somebody says otherwise (`HealthLedger.migrate`). Written straight
        // to the suite: nothing persists during the load.
        let stored = HealthLedger.read(from: defaults)
        let migrated = HealthLedger.migrate(stored, week: activeRitualIDs, edits: libraryEdits)
        healthLedger = migrated.ledger
        if migrated.ledger != stored {
            libraryEdits = migrated.edits
            if let data = try? JSONEncoder().encode(libraryEdits) {
                defaults.set(data, forKey: Key.edits)
            }
            migrated.ledger.write(to: defaults)
        }
    }

    private func persist() {
        guard isLoaded else { return }
        let defaults = ForgeShared.defaults
        defaults.set(activeRitualIDs, forKey: Key.active)
        if let data = try? JSONEncoder().encode(customRituals) {
            defaults.set(data, forKey: Key.custom)
        }
        if let data = try? JSONEncoder().encode(verificationMemory) {
            defaults.set(data, forKey: Key.memory)
        }
        if let data = try? JSONEncoder().encode(libraryEdits) {
            defaults.set(data, forKey: Key.edits)
        }
        if let data = try? JSONEncoder().encode(storedShape) {
            defaults.set(data, forKey: Key.shape)
        }
        // Written in the app's own dimension order rather than the set's, so
        // the stored value is stable and a diff of the defaults plist is
        // readable.
        defaults.set(
            RitualCategory.dimensions.filter(focus.contains).map(\.rawValue),
            forKey: Key.focus
        )
    }

    // MARK: - Lookup

    /// Resolves an id against the user's own activities first, then the
    /// library. Everything that turns an id into a ritual goes through here so
    /// custom activities behave exactly like built-in ones everywhere.
    func ritual(_ id: String) -> Ritual? {
        if let mine = customRituals.first(where: { $0.id == id }) { return mine }
        guard var found = Ritual.find(id) else { return nil }
        if let edit = libraryEdits[id] {
            if let label = edit.label { found.label = label }
            if let symbol = edit.symbol { found.symbolName = symbol }
            if let verification = edit.verification { found.verificationOverride = verification }
            if let tail = edit.tail { found.tail = tail }
            if let note = edit.note { found.note = note }
            if let minutes = edit.minutes { found.minutes = minutes }
            // The one double unwrap in the app, and it is load-bearing: the
            // outer `if let` asks whether a start time was ever set, and the
            // inner value is allowed to be nil because clearing one is a thing
            // somebody can do. See `RitualEdit.startMinute`.
            if let startMinute = edit.startMinute { found.startMinute = startMinute }
            if let priority = edit.priority { found.priority = priority }
            if let repeats = edit.repeats { found.repeats = repeats }
            if let category = edit.category { found.categoryOverride = category }
            // The second double unwrap, and it is load-bearing for the same
            // reason `startMinute` above is: the outer `if let` asks whether a
            // tag was ever decided, and the inner value is allowed to be nil
            // because untagging is a thing somebody can do. See
            // `RitualEdit.identityID`.
            if let identityID = edit.identityID { found.identityID = identityID }
            if let target = edit.target { found.target = target }
        }
        return found
    }

    /// Every library activity, resolved through any edits — what the picker
    /// should show, so a renamed activity is searchable by its new name.
    var libraryRituals: [Ritual] {
        Ritual.library.compactMap { ritual($0.id) }
    }

    func isEdited(_ id: String) -> Bool {
        libraryEdits[id]?.isEmpty == false
    }

    /// Everything in the day, whatever weekday it belongs to.
    ///
    /// This is what the **editor** shows. It has to: somebody on a Tuesday must
    /// still be able to find, rename and reschedule the run they only do on
    /// Mondays, and an editor that hid it would leave an activity that could
    /// only be changed on the day it happens.
    var activeRituals: [Ritual] {
        activeRitualIDs.compactMap { ritual($0) }
    }

    // MARK: - Today, as opposed to the day

    /// The activities that belong to **today**, after each one's repeat rule.
    ///
    /// The distinction this and `activeRitualIDs` draw is the whole of what
    /// repeat means, and getting it the wrong way round is the bug this comment
    /// exists to prevent. `activeRitualIDs` is *the day* — what somebody keeps,
    /// what the editor edits, what syncs. This is *today* — what is asked of
    /// them now, what has to be finished to earn the blade, and what the widgets
    /// and the Live Activity draw.
    ///
    /// Everything that counts toward earning a day reads this one, so a
    /// weekdays-only run cannot leave somebody's Sunday permanently unfinishable.
    var todayRitualIDs: [String] {
        // Read off the *civil day* rather than off `now`, so a session finished
        // at half past one in the morning is still filed under the weekday it
        // belongs to — the same reason `ForgeDay` exists at all.
        let weekday = progress.currentDay.weekday
        // An id that resolves to nothing is **dropped**, not kept. It used to
        // fall through as `true` — "if we cannot tell, assume today" — which
        // reads as the cautious choice and is the opposite. Every list on the
        // screen resolves its ids and drops the ones that fail, so a phantom id
        // draws no row; but `totalActive` counts this array, so it was counted.
        // What that produces is a day reading "0 OF 4" over three rows, which
        // can never be finished and therefore can never be earned. Dropping it
        // makes the count and the rows the same list by construction.
        return activeRitualIDs.filter { ritual($0)?.happens(on: weekday) ?? false }
    }

    var todayRituals: [Ritual] { todayRitualIDs.compactMap { ritual($0) } }

    /// Whether anything is being held back today, and how much.
    ///
    /// Shown as one quiet line under the day rather than left invisible: an
    /// activity that silently is not there is indistinguishable from one that
    /// was lost, and this app cannot afford that particular ambiguity.
    var restingTodayCount: Int { activeRitualIDs.count - todayRitualIDs.count }

    /// Whether today asks for anything at all.
    ///
    /// A day can now be genuinely empty — activities belong to the days they were
    /// put on, so tomorrow holds nothing until somebody plans it — and an empty
    /// day is a different thing from an unfinished one. Everything that draws the
    /// day has to ask this first; see `allDone`, which used to say yes to a day
    /// with nothing in it.
    var isDayEmpty: Bool { totalActive == 0 }

    /// Whether any day of the week other than today holds something.
    ///
    /// Asked by the empty day, which offers to copy another day into this one
    /// and must not offer it when there is nothing anywhere to copy.
    var hasAnyOtherDayPlanned: Bool {
        let today = progress.currentDay.weekday
        if activeRituals.contains(where: { $0.repeats.weekdays.contains { $0 != today } }) {
            return true
        }
        // Or a day that actually happened. The copy sheet offers both sources
        // now — see `recentDays(limit:)` — so gating its door on the recurring
        // half alone would hide the record from exactly the person it is most
        // useful to: somebody whose activities all sit on one weekday but who
        // has three weeks of kept days behind them.
        return !recentDays(limit: 1).isEmpty
    }

    /// Write down what today is asking for.
    ///
    /// Called from three places and it has to be all three: whenever the day
    /// list changes, at load, and **whenever the day itself turns over**. That
    /// last one is new and it is the one repeat rules made necessary — the
    /// denominator of a day used to be a property of the list, so a `didSet` was
    /// enough; now it is a property of the list *and the weekday*, and midnight
    /// changes the answer without anybody touching anything.
    func publishPlanned() {
        // Nothing during the load. Four properties now write the day down when
        // they change, and during `load()` three of them are set before the
        // fourth — so without this the record is written twice from a list that
        // is not finished being read. See `isLoaded`, which `persist()` has
        // always used for exactly this.
        guard isLoaded else { return }
        progress.setPlanned(todayRitualIDs)
    }

    // MARK: - The shape of the day

    /// The parts the user's day is divided into, as last written.
    ///
    /// Never read directly by anything that draws — `dayParts` is what views
    /// want, because this one is allowed to be stale and that one is not.
    private(set) var storedShape: DayShape = .flat {
        didSet { persist() }
    }

    /// The day, in its parts, each holding the activities it actually contains.
    ///
    /// Reconciled against `activeRitualIDs` on every read, so this can never
    /// disagree with the day about what is in it — see `DayShape`. Empty parts,
    /// stale ids and activities added since the shape was written all resolve
    /// here rather than in whichever view happened to notice.
    /// In the order the user **arranged** them, not the order they are shown.
    ///
    /// The distinction is load-bearing. The day list floats finished activities
    /// to the foot of their part, so what is left to do is always at the top;
    /// the editor must not, because a drag reports an index into the rows it can
    /// see, and reordering a list that has been re-sorted underneath would move
    /// the wrong activity. So the arrangement is what this returns, and the
    /// floating is a thing the day list does on the way to the screen — see
    /// `displayed(_:)`.
    var dayParts: [ShapedPart] {
        storedShape.reconciled(with: activeRitualIDs).parts.map { part in
            ShapedPart(
                id: part.id,
                name: part.name,
                activities: part.activities.compactMap { ritual($0) },
                isUserNamed: part.isUserNamed,
                completed: part.activities.count { doneIDs.contains($0) }
            )
        }
    }

    /// The day's parts as **today** sees them: the same headings, holding only
    /// what repeats today, with any part left empty dropped.
    ///
    /// What the day list draws. `dayParts` is what the editor draws — see
    /// `todayRitualIDs` for why those are two different questions.
    var todayParts: [ShapedPart] {
        let today = Set(todayRitualIDs)
        return storedShape.reconciled(with: activeRitualIDs).parts.compactMap { part in
            let ids = part.activities.filter(today.contains)
            guard !ids.isEmpty else { return nil }
            return ShapedPart(
                id: part.id,
                name: part.name,
                activities: ids.compactMap { ritual($0) },
                isUserNamed: part.isUserNamed,
                completed: ids.count { doneIDs.contains($0) }
            )
        }
    }

    /// A part as the day list draws it: what is left to do above what is done.
    ///
    /// The same rule the flat list has always used, applied within a part rather
    /// than across the whole day — so the top of every movement is that
    /// movement's remaining work.
    func displayed(_ part: ShapedPart) -> [Ritual] {
        let ids = part.activities.map(\.id)
        let pending = Ritual.chronological(
            ids.filter { !doneIDs.contains($0) }.compactMap { ritual($0) }
        )
        let finished = doneOrder.filter { ids.contains($0) }.compactMap { ritual($0) }
        return pending + finished
    }

    /// Whether the day has a shape worth drawing headings for.
    ///
    /// One part is a flat list, which is what Forge has always shown and what
    /// somebody who never took a routine keeps forever.
    var isDayShaped: Bool { dayParts.count > 1 }

    /// Whether **today** has enough shape to draw headings for.
    var isTodayShaped: Bool { todayParts.count > 1 }

    /// What the day list actually shows: unfinished first, in clock order where
    /// times have been set and in the order the user arranged them otherwise,
    /// then finished, in the order they were finished. The top of the list is
    /// therefore always what is left to do, and the top of *that* is what is
    /// due first. See `chronological(_:)`.
    var orderedRituals: [Ritual] {
        let today = todayRitualIDs
        let pending = Ritual.chronological(
            today.filter { !doneIDs.contains($0) }.compactMap { ritual($0) }
        )
        let finished = doneOrder.filter { today.contains($0) }.compactMap { ritual($0) }
        return pending + finished
    }

    /// How many activities today asks for — the denominator of an earned day.
    ///
    /// Today's, not the day's. An activity that does not repeat today is not
    /// something the user has failed to do; it is not being asked of them, and
    /// counting it would make a day with a weekends-only activity in it
    /// impossible to finish from Monday to Friday.
    var totalActive: Int { todayRitualIDs.count }

    /// How many activities are in the day in total, whatever weekday it is.
    /// What the editor's subtitle counts.
    var totalKept: Int { activeRitualIDs.count }

    /// How many of **today's** activities are done.
    ///
    /// It was `doneIDs.count`, which is the count of everything completed today
    /// whether or not today is still asking for it — and the two go apart the
    /// moment somebody finishes something and then takes it off the day.
    ///
    /// Seen on screen as "2 OF 3" over a list with one tick in it. The worse
    /// half never showed but is the reason this is a bug rather than a
    /// cosmetic slip: `allDone` is `totalDone >= totalActive`, so completing two
    /// activities and swiping one of them off today makes it `2 >= 2` — the
    /// blade comes loose, the room lights up and a day is earned with an
    /// unfinished activity sitting on the panel. Removing something from today
    /// must never be a way to finish it.
    ///
    /// The completion itself is untouched and stays in the record: it *was*
    /// done, `isDone` still says so, and every reading of history still counts
    /// it. This is only the numerator of today's list, and today's list is the
    /// only thing it was ever meant to be about.
    var totalDone: Int { todayRitualIDs.count { doneIDs.contains($0) } }

    /// Everything today asked for is done — and today asked for something.
    ///
    /// The second half is not a technicality. `totalDone >= totalActive` is true
    /// of a day with nothing in it, so an empty day used to arrive already
    /// finished: the blade came loose at midnight, the room lit up, and a day
    /// could be earned having done nothing. That was survivable while every
    /// activity repeated daily and an empty day was nearly impossible. It is not
    /// survivable now that activities belong to the day they were put on — an
    /// unplanned tomorrow is the ordinary case, and it must read as *unplanned*
    /// rather than as *won*. See `isDayEmpty`, and `ForgeTabView`, which draws
    /// the empty day instead of the pull prompt.
    var allDone: Bool { isFirstPullGranted || isListFinished }

    /// Whether today's list is *actually* finished, with no grace in it.
    ///
    /// `allDone` answers "may the blade come loose", and the first run says yes
    /// to that with one of three done — deliberately, because a stranger has to
    /// be able to pull on the day they install. This answers the different
    /// question "is there anything left to do", and the panel is the one place
    /// that must ask the second one.
    ///
    /// **They were the same property and it hid the day.** `ForgeTabView`
    /// swapped the list for the pull prompt on `allDone`, so for as long as the
    /// grace was in force the panel read "1 OF 16" over a screen with no list on
    /// it — fifteen activities on today that could not be seen, ticked or
    /// reached by any gesture. Three of three made it nearly invisible; anybody
    /// who added to their day during the first run lost the rest of it.
    var isListFinished: Bool { totalActive > 0 && totalDone >= totalActive }
    var pullFraction: Double { totalActive > 0 ? Double(totalDone) / Double(totalActive) : 0 }

    /// What the day header says above the list.
    ///
    /// It used to open on the word TODAY and switch to the count after the first
    /// activity. The panel now carries a TODAY/WEEK control directly above this
    /// line, so the old opening said the same word twice, eleven points apart, in
    /// two different type styles — and the second one was the less useful of the
    /// two, because the segment already answers "which of the two am I looking
    /// at" and only this can answer "how far in am I".
    ///
    /// So it is always the count. A fresh day reads "0 OF 5", which is a fact
    /// about the morning rather than a scolding: it is the same sentence the
    /// progress dots beside it are drawing, and it fills in as the day does.
    var listLabel: String {
        "\(totalDone) OF \(totalActive)"
    }

    /// What is still unticked on today's list, in list order.
    ///
    /// Empty on an ordinary loose day — loose means finished. It is only ever
    /// non-empty under the first run's grace, when the blade comes loose with
    /// one of three done and the panel swaps the list for the pull prompt; see
    /// `HomeCopy.leftLine`, which is what says so.
    var leftToday: [Ritual] { todayRituals.filter { !isDone($0.id) } }

    /// The dots beside the count, and they read the same number it does —
    /// `totalDone` rather than `doneIDs`, or the picture and the words would
    /// disagree in exactly the case above.
    var progressSegments: [Bool] {
        (0..<totalActive).map { totalDone > $0 }
    }

    func isDone(_ id: String) -> Bool {
        doneIDs.contains(id)
    }

    /// A finished ritual toggles back off. An unfinished one gets one last look
    /// at Health, and then its prompt.
    ///
    /// The sweep covers the ordinary case — you walk, the app is in the
    /// background, you come back to find it done. It cannot cover the case where
    /// Forge sat open on the desk the whole time, because nothing ever brought
    /// the app to the foreground. So a tap on a Health activity asks the phone
    /// once more before asking the user: the tap itself is the moment we know
    /// they think it is finished, and it would be a poor trade to hand them a
    /// promise to keep when the answer was sitting in Health all along.
    ///
    /// Falling back is silent. Nothing tells the user a lookup happened, and
    /// nothing mentions Health when it comes up empty.
    func tapRitual(_ id: String) {
        if doneIDs.contains(id) {
            undoRitual(id)
            return
        }
        guard let ritual = ritual(id) else {
            honorRitualID = id
            return
        }

        switch ritual.verification {
        // The tap *is* the confirmation. No sheet, no question, no second
        // gesture — an activity marked this way is a checkbox, and putting a
        // prompt in front of a checkbox is the thing this method exists to
        // avoid. See `VerificationMethod.basic`.
        case .basic:
            tick(ritual)

        // The first tap on a measurable activity nobody has been asked about
        // yet is the moment to ask, in context. After that, one more look at
        // Health, and the prompt when it has nothing.
        case .health:
            if healthPrimerIsDue(for: ritual) {
                healthPrimer = HealthPrimerRequest(ritualID: id, fromTap: true)
            } else if ritual.checksWithHealth, healthLedger.decision == .asked {
                Task { @MainActor in await self.checkWithHealth(id) }
            } else {
                honorRitualID = id
            }

        case .honor:
            honorRitualID = id
        }
    }

    /// A box, ticked.
    ///
    /// Banked as `.basic` rather than as honor, because the history should be
    /// able to tell the difference between somebody answering a question about
    /// a prayer and somebody running down a list of chores — those are not the
    /// same act, and the one number in this app that has to stay honest is what
    /// a day was made of.
    ///
    /// No haptic here. The one for this completion is fired by the row, the
    /// same way the honor prompt's button fires its own — see
    /// `RitualRowView.handleTap`. Everything that lands without a finger on it
    /// goes through `settle` instead, which is `@MainActor` precisely so that
    /// it can.
    private func tick(_ ritual: Ritual) {
        let isNew = !isDone(ritual.id)
        let before = isNew ? blended : nil
        withAnimation(.forgeRow) {
            progress.complete(ritual.id, method: .basic)
        }
        if isNew { ForgeTelemetry.send(.activityCompleted(.basic)) }
        if let before { noteGain(of: ritual.id, since: before) }
    }

    /// The promise was kept. Banked as honor however the activity is marked:
    /// saying so is not a measurement, and the history should not claim it was.
    func keepPromise(_ id: String) {
        let isNew = !isDone(id)
        let before = isNew ? blended : nil
        withAnimation(.forgeRow) {
            progress.complete(id, method: .honor)
        }
        honorRitualID = nil
        if isNew { ForgeTelemetry.send(.activityCompleted(.honor)) }
        if let before { noteGain(of: id, since: before) }
    }

    func cancelHonor() { honorRitualID = nil }

    // MARK: - Apple Health

    /// Whether this row is Health's to tick off right now: a measurable
    /// activity marked Health, the primer answered with Continue, and Health
    /// showing Forge anything of that type. Anything short of all three is
    /// drawn and behaves as Your Word.
    func healthChecks(_ ritual: Ritual) -> Bool {
        guard ritual.checksWithHealth, healthLedger.decision == .asked,
              let metric = ritual.measure?.metric else { return false }
        return healthVisible.contains(metric)
    }

    /// Whether today's completion of this activity was Apple Health's.
    func checkedByHealth(_ id: String) -> Bool {
        progress.today.completions.last { $0.ritualID == id }?.method == .health
    }

    /// Whether the primer should come up for this activity: once the first run
    /// is over (never during its questions), only while nobody has answered
    /// it, and only for something Health can actually check.
    func healthPrimerIsDue(for ritual: Ritual) -> Bool {
        ForgeFeatures.current.health
            && hasCompletedFirstRun
            && healthLedger.decision == .undecided
            && ritual.checksWithHealth
    }

    /// The primer is waiting and still about something in the week. A
    /// QuickAdd undone before the primer showed leaves nothing to ask about.
    var isHealthPrimerWaiting: Bool {
        guard let request = healthPrimer else { return false }
        return healthLedger.decision == .undecided
            && activeRitualIDs.contains(request.ritualID)
    }

    /// A measurable activity entered the week: adding one, QuickAdd, an Arc
    /// joining or moving a phase, the composer. One check on the list itself
    /// rather than one at every door, so a door added later cannot forget it.
    private func noteArrivals(since old: [String]) {
        guard isLoaded, !isHealthPrimerWaiting else { return }
        let arrived = activeRitualIDs.filter { !old.contains($0) }
        if let first = arrived.compactMap({ ritual($0) }).first(where: healthPrimerIsDue) {
            healthPrimer = HealthPrimerRequest(ritualID: first.id, fromTap: false)
        }
    }

    /// The primer's answer. Continue asks iOS (read-only) and then reads;
    /// "Keep it Your Word" is final.
    ///
    /// The primer stays on screen while iOS asks, so the system sheet is
    /// never raised over a sheet that is busy going away; it closes once iOS
    /// has its answer. A tap that brought the primer up still gets its own
    /// answer afterwards: ticked by Health, or the honor prompt.
    @MainActor
    func answerHealthPrimer(allow: Bool) async {
        let request = healthPrimer
        if allow {
            await health.requestReadAccess()
            healthLedger.decision = .asked
            health.startObserving()
        } else {
            healthLedger.decision = .declined
        }
        healthPrimer = nil
        if allow { await sweepHealth() }
        guard let request, request.fromTap, !isDone(request.ritualID) else { return }
        // After the primer's own dismissal, or the next sheet is refused.
        try? await Task.sleep(for: .milliseconds(500))
        guard !isDone(request.ritualID) else { return }
        if allow, let ritual = ritual(request.ritualID), ritual.checksWithHealth {
            await checkWithHealth(request.ritualID)
        } else {
            honorRitualID = request.ritualID
        }
    }

    /// A tap on a Health row that is not done: one more look, and the prompt
    /// when Health has not counted enough. Health not having counted it is not
    /// proof it was not done, so the person can always say so.
    ///
    /// An activity Health already ticked off today and somebody took back is
    /// not ticked off again here: the undo stands, and the tap means "ask me".
    @MainActor
    func checkWithHealth(_ id: String) async {
        guard let ritual = ritual(id), let measure = ritual.measure else {
            honorRitualID = id
            return
        }
        let day = progress.currentDay
        guard !healthLedger.hasTicked(id, on: day) else {
            honorRitualID = id
            return
        }
        let value = await health.value(of: measure, on: day, dayStartHour: progress.dayStartHour)
        guard !isDone(id) else { return }
        if HealthMath.meets(value, measure), progress.currentDay == day,
           !healthLedger.hasTicked(id, on: day) {
            settleFromHealth(id, on: day)
        } else {
            honorRitualID = id
        }
    }

    /// Read Health and tick off whatever has reached its target.
    ///
    /// Called when the app becomes active, when the Forge tab appears and when
    /// HealthKit reports new samples. Only ever **completes**: it never takes
    /// back anything, so a box somebody ticked by hand cannot be unticked by
    /// a number, and it never ticks off twice in a day (`HealthLedger.ticked`),
    /// so an undo stands.
    @MainActor
    func sweepHealth() async {
        guard healthLedger.decision == .asked, hasCompletedFirstRun, keepsNewDays() else { return }
        guard !isSweeping else { sweepAgain = true; return }
        isSweeping = true
        defer { isSweeping = false }
        repeat {
            sweepAgain = false
            healthVisible = await health.visibleMetrics()
            let day = progress.currentDay
            for ritual in todayRituals where ritual.checksWithHealth {
                guard let measure = ritual.measure,
                      healthVisible.contains(measure.metric),
                      !isDone(ritual.id),
                      !healthLedger.hasTicked(ritual.id, on: day)
                else { continue }
                let value = await health.value(
                    of: measure, on: day, dayStartHour: progress.dayStartHour
                )
                // Read again after the wait: the day may have turned, the
                // row been ticked by hand, or the activity taken off today.
                guard HealthMath.meets(value, measure),
                      progress.currentDay == day,
                      !isDone(ritual.id),
                      !healthLedger.hasTicked(ritual.id, on: day),
                      todayRitualIDs.contains(ritual.id)
                else { continue }
                settleFromHealth(ritual.id, on: day)
            }
        } while sweepAgain
    }

    /// Apple Health counted it. The same write a tap makes, banked as
    /// `.health` so the record can tell a measurement from a promise; the
    /// same telemetry, the same gain chip, and the haptic a kept activity
    /// gets. The Shape does not care which: a kept day is a kept day.
    ///
    /// **Not animated.** Most of these land as the app comes forward, and a
    /// row's strikethrough animated across the scene becoming active was left
    /// half-drawn: two strike lines and no name, until the next relaunch
    /// (found on the Simulator, §17.5). Nobody's finger is on the row, so
    /// there is no gesture for the motion to answer; it is simply done when
    /// the day is looked at.
    @MainActor
    private func settleFromHealth(_ id: String, on day: ForgeDay) {
        healthLedger.noteTick(id, on: day)
        let before = blended
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            progress.complete(id, method: .health)
        }
        ForgeTelemetry.send(.activityCompleted(.health))
        noteGain(of: id, since: before)
        ForgeHaptics.shared.ritualVerified()
    }

    /// The activities each type checks, by the names somebody sees, in library
    /// order: the primer's "for Hit your steps".
    func healthActivityNames(for metric: ActivityMetric) -> [String] {
        Ritual.library
            .filter { Ritual.metrics[$0.id] == metric }
            .compactMap { ritual($0.id)?.label }
    }

    /// Whether the honor prompt for this activity carries "Let Apple Health
    /// check this": an activity 1.1 kept as Your Word, once, and never after
    /// a no on the primer.
    func offersHealth(for id: String) -> Bool {
        ForgeFeatures.current.health && healthLedger.offersHealth(for: id)
    }

    /// The offer was on screen. It is not shown again, whatever the answer.
    func noteHealthOffered(_ id: String) {
        healthLedger.offered.insert(id)
    }

    /// "Let Apple Health check this": the Your Word pin the 1.1 switch wrote
    /// comes off, and the activity is Health's like any new one. The primer
    /// follows if nobody has answered it yet.
    func letHealthCheck(_ id: String) {
        healthLedger.offered.insert(id)
        healthLedger.awaitingOffer.remove(id)
        if var edit = libraryEdits[id] {
            edit.verification = nil
            libraryEdits[id] = edit.isEmpty ? nil : edit
        }
        honorRitualID = nil
        guard let ritual = ritual(id) else { return }
        if healthPrimerIsDue(for: ritual) {
            healthPrimer = HealthPrimerRequest(ritualID: id, fromTap: true)
        } else if healthLedger.decision == .asked {
            Task { @MainActor in await self.sweepHealth() }
        }
    }

    // MARK: - What a kept activity moved

    /// The last completion's effect on the six, for the chip that rises from
    /// its row on the Forge tab: "+4 Physical". See `StatGain`.
    ///
    /// In memory only, and replaced by the next completion. It is a reading of
    /// one moment, taken from the blend before and after the write, and the
    /// chip that shows it is gone a second and a half later — nothing about it
    /// is stored (§5 #2), and nil when nothing rose.
    private(set) var lastGain: StatGain?

    private func noteGain(of id: String, since before: BlendedShape) {
        guard let ritual = ritual(id) else { return }
        lastGain = StatGain.between(before, blended, ritualID: id, filedUnder: ritual.category)
    }

    // MARK: - First run

    /// Replace the day with the plan somebody just read — every activity on it
    /// **on the days and at the time on its row**.
    ///
    /// Not appended to the defaults: the defaults are our guess, and they have
    /// just read a better one.
    ///
    /// # Why its own days, when the 1.0 first run pinned its three to today
    ///
    /// The 1.0 choosing screen was a list of eight rows with nothing on it about
    /// repetition, and taking three used to be somebody agreeing — in their
    /// first thirty seconds — to do them every day forever, with the only sign
    /// of it a repeat picker three screens away. Pinning them to the day was
    /// the honest answer to *that* screen.
    ///
    /// This screen says it. Every row reads "Mon · Wed · Fri · 18:00" or
    /// "Daily · 21:30", each one opens the repeat picker, and the screen before
    /// projected exactly those days. So the days are written as shown: training
    /// on its three, reading on all seven. (1.1 first wrote the whole plan as
    /// every day — a workout swapped in became seven a week, deep work came on
    /// Sundays; §17.1.)
    /// Changing any of it later is the same repeat picker (§5 #12: an activity
    /// is a standing arrangement of weekdays and a time).
    ///
    /// Written through `amend`, so each is an ordinary `RitualEdit` — the same
    /// `repeats` and `startMinute` the editor writes — and every day and hour
    /// is the user's from the first second.
    func adoptPlan(_ entries: [PlanEntry]) {
        let ids = entries.map(\.ritualID).filter { ritual($0) != nil }
        guard !ids.isEmpty else { return }
        withAnimation(.forgeRow) {
            activeRitualIDs = ids
        }
        for entry in entries where ids.contains(entry.ritualID) {
            amend(entry.ritualID) {
                $0.repeats = entry.repeats
                $0.startMinute = entry.minute
            }
        }
        publishPlanned()
    }

    /// The first run's plan when it is an Arc's: the Arc's activities become
    /// the day, each on its days, at its hour and its length.
    ///
    /// The same replacement `adoptPlan` makes, for the same reason — the
    /// defaults are a guess and somebody has just read the plan — and through
    /// the same `amend`, so every day, hour and length is an ordinary edit
    /// from the first second. An untimed one (steps, a day without clips)
    /// stays untimed.
    func adoptPlan(_ additions: [ArcJoin.Addition]) {
        let ids = additions.map(\.id).filter { ritual($0) != nil }
        guard !ids.isEmpty else { return }
        withAnimation(.forgeRow) {
            activeRitualIDs = ids
        }
        for addition in additions where ids.contains(addition.id) {
            amend(addition.id) {
                $0.repeats = RitualRepeat(weekdays: addition.weekdays)
                $0.startMinute = addition.minute
                if addition.minutes > 0, addition.minutes != $0.minutes { $0.setLength(addition.minutes) }
            }
        }
        publishPlanned()
    }

    /// Pin activities to the day they arrived on, and no other.
    ///
    /// The same commitment the 1.0 first run refused to make on anybody's
    /// behalf, applied to the other way into a first day. A world's routine ships every
    /// activity as `.daily`, so accepting one in the first ninety seconds would
    /// otherwise be a stranger agreeing to a five-activity day every day for the
    /// rest of time — a promise they have no basis to make and no idea they
    /// made. Widening it later is one tap in the repeat picker.
    ///
    /// Only used by the first run. Taking a routine from the Becoming tab is
    /// done by somebody who has read the world's own screen and knows what a
    /// routine is, and it keeps the days the world proposed.
    func pinToTodayOnly(_ ids: [String]) {
        let weekday = progress.currentDay.weekday
        for id in ids {
            amend(id) { $0.repeats = .onlyToday(weekday) }
        }
        publishPlanned()
    }

    /// Tag activities a world's routine just added with what they are evidence
    /// for.
    ///
    /// Separate from `importRoutine` rather than a parameter on it, because
    /// taking a routine is a thing that happens all over the app and not every
    /// caller knows about identities. `importRoutine` returns exactly what it
    /// added, which is what this takes.
    ///
    /// **Two routes to an answer, and the specific one wins.** An activity is
    /// first asked which identity it is evidence for on its own terms — a run is
    /// evidence for someone who trains whichever world proposed it. Only where
    /// that finds nothing does the `archetype` answer, with the identity it is a
    /// shape for: taking The Scholar's routine files its no-feed hour under
    /// "Someone who reads" even though nothing about not scrolling says
    /// *reading* by itself. Without the second route roughly half of a routine
    /// arrived untagged, and an identity that shows evidence on three of its
    /// seven days is quietly lying about a day that was entirely for it.
    ///
    /// Nothing is invented. Where the user has named no identity this world is
    /// a shape for, the activity stays untagged — which is the ordinary state
    /// for every activity on every phone, and reads exactly as it always has.
    func tagImported(_ ids: [String], identities: [Identity]) {
        guard !identities.isEmpty else { return }
        for id in ids {
            guard let identity = IdentityActivities.evidence(for: id, among: identities)
            else { continue }
            setIdentity(identity.id, on: id)
        }
    }

    // MARK: - The week, read back

    /// Everything the weekly review is allowed to draw an observation from.
    ///
    /// Assembled here because this is the one object that can answer all three
    /// halves of the question: `ProgressStore` holds the days, `Ritual` holds
    /// the names — including for an activity somebody invented — and the
    /// identity tag lives on the activity. The generator itself takes the value
    /// and never the store, so the rules stay a pure function of facts and the
    /// empty and tied cases are literals in a test rather than seeded histories.
    /// See `ReviewObservation`.
    func reviewFacts(
        from first: ForgeDay,
        to last: ForgeDay,
        identities: [Identity],
        windowWeeks: Int = 5
    ) -> ReviewFacts {
        ReviewFacts(
            kept: progress.daysKept(from: first, to: last),
            asked: progress.daysAsking(from: first, to: last),
            windowWeeks: windowWeeks,
            weekdays: progress.weekdayFacts(weeks: windowWeeks, endingOn: last),
            habits: progress.habitCounts(from: first, to: last).compactMap { counts in
                // An activity the library has since dropped and the user has
                // since deleted resolves to nothing. It stays out of the facts
                // rather than appearing as an id — an observation naming
                // "nofeed" would read as a bug in front of somebody.
                guard let name = ritual(counts.id)?.label else { return nil }
                return ReviewFacts.Habit(
                    id: counts.id, name: name,
                    planned: counts.planned, completed: counts.completed
                )
            },
            identities: identities.map { identity in
                let activities = activityIDs(taggedTo: identity.id)
                return ReviewFacts.Identity(
                    id: identity.id,
                    statement: identity.statement,
                    days: progress.daysOfEvidence(taggedTo: activities, from: first, to: last),
                    asked: progress.daysAsking(for: activities, from: first, to: last)
                )
            }
        )
    }

    /// The week the review is about, as the panel draws it.
    ///
    /// The same `WeekDay` values the home screen's week mode uses, so the seven
    /// marks on the review read exactly like the seven a user already knows.
    func days(from first: ForgeDay, to last: ForgeDay) -> [ProgressStore.WeekDay] {
        let span = max(0, last.days(since: first))
        return (0...span).map { offset in
            let day = first.adding(days: offset)
            return progress.weekDay(day)
        }
    }

    // MARK: - Coming back

    /// Whether the app should open on the return screen. See `ReEntry`.
    var isReturning: Bool {
        ReEntry.isReturning(
            gap: progress.daysSinceLastKept,
            daysKept: progress.daysKept,
            isTodayEarned: progress.isTodayEarned
        )
    }

    /// How long they have been away, for the one sentence that names it.
    var daysAway: Int { progress.daysSinceLastKept ?? 0 }

    /// The one small thing the return screen offers.
    ///
    /// The least effort on today's list, on the shared ladder — the same
    /// reasoning `firstRunActivity` follows, and for a stronger reason here.
    /// The list somebody built for a good week is the exact list that stopped
    /// being kept, and handing it back whole is asking them to resume at the
    /// difficulty that beat them. One thing, and the smallest one.
    var returnActivity: Ritual? { firstRunActivity }

    /// The activity the first run asks for.
    ///
    /// The least effort of the three, on the shared ladder: the first thing
    /// Forge ever asks anybody to do should be the smallest thing they picked,
    /// whatever hour it happens to be. See `IdentityActivities.effortOrder`,
    /// which is now the one place that ordering lives — it used to be the
    /// hardcoded starter list, which stopped being the set of things somebody
    /// could arrive here holding the moment a world's routine could.
    var firstRunActivity: Ritual? {
        todayRitualIDs
            .filter { !isDone($0) }
            .min { IdentityActivities.effort(of: $0) < IdentityActivities.effort(of: $1) }
            .flatMap { ritual($0) }
    }

    // MARK: - Sync

    /// Take on everything a merge decided, in one pass.
    ///
    /// One method rather than five assignments from the outside, because each
    /// of those properties persists itself on `didSet` and setting them
    /// individually would write the same five defaults keys five times over —
    /// and because "what a merge is allowed to change" should be a list in one
    /// place rather than whatever a caller happened to reach for.
    ///
    /// `firstRunCompleted` only ever goes forwards. Somebody arriving on a new
    /// phone with a year behind them must not be walked through onboarding, and
    /// somebody midway through their first ninety seconds must not have it
    /// yanked out from under them by a sync landing.
    func adopt(
        firstRunCompleted: Bool,
        verificationMemory memory: VerificationMemory,
        customRituals customs: [Ritual],
        libraryEdits edits: [String: RitualEdit],
        activeRitualIDs ids: [String]
    ) {
        if firstRunCompleted, !hasCompletedFirstRun {
            hasCompletedFirstRun = true
            firstRunStage = .finished
            ForgeShared.defaults.set(true, forKey: Key.firstRun)
        }

        verificationMemory = memory
        customRituals = customs
        libraryEdits = edits

        // Anything that no longer resolves is dropped, exactly as it is on
        // load: an id in the arrangement whose activity was deleted on the
        // other phone would otherwise be a permanent blank row.
        let known = ids.filter { ritual($0) != nil }
        if !known.isEmpty, known != activeRitualIDs {
            activeRitualIDs = known
        }
    }

    /// The first pull is done and the sequence is over. Grace lapses here, so
    /// tomorrow the list has to be finished like any other day.
    func finishFirstRun() {
        let wasRunning = !hasCompletedFirstRun
        hasCompletedFirstRun = true
        firstRunStage = .finished
        ForgeShared.defaults.set(true, forKey: Key.firstRun)
        if wasRunning { ForgeTelemetry.send(.onboardingCompleted) }
    }

    #if DEBUG
    /// Puts the app back to the state of a fresh install, day included, so
    /// the ninety seconds can be walked again without deleting the app.
    ///
    /// `identities` is handed in rather than reached for, because this object
    /// has no reference to that store and should not gain one for a debug path.
    /// Passing nil replays the sequence over whatever identities are already
    /// there, which is occasionally what you want and never what you want by
    /// accident — so the caller has to say.
    /// `@MainActor` because `IdentityStore` is, and this is only ever called
    /// from a settings row — the isolation costs nothing and stating it is
    /// cheaper than making the store's isolation weaker to suit a debug path.
    @MainActor
    func resetFirstRun(identities: IdentityStore? = nil) {
        hasCompletedFirstRun = false
        firstRunStage = .coldOpen
        ForgeShared.defaults.set(false, forKey: Key.firstRun)
        // The answers go with the run they were given in: a replay is a fresh
        // install, and a fresh install has said nothing yet.
        assessment = nil
        activeRitualIDs = Ritual.defaultActive
        // The tags go with the identities they point at. Leaving them would
        // mean a replayed first run started with a day already claiming to be
        // evidence for sentences that no longer exist.
        libraryEdits = [:]
        customRituals = []
        progress.clearHistory()
        identities?.deleteAll()
        // A fresh install has not been asked about Health either. Migrated,
        // because a fresh install has nothing of its own to keep as Your Word.
        resetHealth()
    }

    /// DEBUG: forget the primer's answer and the offers, as a fresh install.
    func resetHealth() {
        var fresh = HealthLedger()
        fresh.hasMigrated = true
        healthLedger = fresh
        healthPrimer = nil
        healthVisible = []
    }
    #endif

    /// The blade tore free (§5.6). This is the moment the day is earned, so
    /// it is the moment it goes into the history — the extraction XP and the
    /// streak both fall out of that record rather than being added by hand.
    func breakFree() {
        guard !isOut else { return }
        withAnimation(.settle(2.4)) {
            isOut = true
        }
    }

    /// The sword settles back into the stone (§5.10). Reversible and weighty:
    /// every stone-attached transform runs back over its 2.4s Settle.
    ///
    /// The transaction is deliberately quick rather than the 2.4s Settle: what
    /// it governs here is the *list* reordering itself, and every scene layer
    /// that reads this state carries its own `.animation(_:value:)` at Settle
    /// speed. Sharing one 2.4s curve made the row crawl back up the list.
    func undoRitual(_ id: String) {
        withAnimation(.forgeRow) {
            progress.undo(id)
            // Taking a ritual back un-earns the day, and the XP and streak
            // go with it because they were only ever a reading of the record.
            if !allDone {
                isOut = false
                pull = 0
            }
        }
    }

    /// Take an activity into the week, landing on today.
    func addRitual(_ id: String) {
        addRitual(id, onWeekday: progress.currentDay.weekday)
    }

    /// Take an activity into the week, landing on a named day.
    ///
    /// The day is a parameter because the picker is now opened from the week as
    /// well as from today, and "add Read" pressed on a screen showing Thursday
    /// means Thursday. It used to mean today wherever it was pressed, which is
    /// the app overruling something the user had already said.
    func addRitual(_ id: String, onWeekday weekday: Int) {
        guard !activeRitualIDs.contains(id) else {
            // Already kept, just not on this day. Adding the day is the only
            // thing left that the word "add" can honestly mean here, and it is
            // what the picker's "Already in your week" section offers.
            setWeekday(id, weekday, on: true)
            return
        }
        withAnimation { activeRitualIDs.append(id) }
        pinIfUnscheduled(id, to: weekday)
    }

    /// An activity taken into the day arrives on **the day it was added from**,
    /// and on no other day until somebody says otherwise.
    ///
    /// The library ships everything as `.daily`, so adding "Read" from the picker
    /// was a promise to read every day for the rest of time, made silently on the
    /// way past. Every other door into the day already starts narrow — the
    /// composer opens on one day, the week's `+` opens on the day you were
    /// looking at — and this was the one that disagreed.
    ///
    /// Anything already scheduled is left exactly as it is. An activity somebody
    /// made carries the days they picked in the composer, and a library one they
    /// have edited carries the days they set; taking either out of the day and
    /// putting it back must not quietly overwrite that. Only an activity that has
    /// never been told when it happens is pinned.
    private func pinIfUnscheduled(_ id: String, to weekday: Int) {
        guard !customRituals.contains(where: { $0.id == id }) else { return }
        guard libraryEdits[id]?.repeats == nil else { return }
        amend(id) { $0.repeats = .onlyToday(weekday) }
    }

    func removeRitual(_ id: String) {
        withAnimation {
            activeRitualIDs.removeAll { $0 == id }
            progress.undo(id)
        }
    }

    // MARK: - Adding in one tap

    /// Everything adding something can change about the week, taken whole so
    /// it can be put back exactly.
    ///
    /// Four values and nothing else: the list, the activities somebody made,
    /// the edits to library activities (which is where a pinned day or an
    /// added weekday lands) and the day's parts. The record is not in it,
    /// because adding writes nothing to the record — `publishPlanned` derives
    /// today's planned list from these four again on the way back.
    struct WeekSnapshot: Equatable {
        let activeRitualIDs: [String]
        let customRituals: [Ritual]
        let libraryEdits: [String: RitualEdit]
        let shape: DayShape
    }

    var weekSnapshot: WeekSnapshot {
        WeekSnapshot(
            activeRitualIDs: activeRitualIDs,
            customRituals: customRituals,
            libraryEdits: libraryEdits,
            shape: storedShape
        )
    }

    /// Put the week back exactly as a snapshot had it — the Undo on QuickAdd's
    /// toast. Only ever handed the snapshot taken just before the add it
    /// undoes, so nothing else can have moved in between.
    func restore(_ snapshot: WeekSnapshot) {
        withAnimation(.forgeRow) {
            customRituals = snapshot.customRituals
            libraryEdits = snapshot.libraryEdits
            storedShape = snapshot.shape
            activeRitualIDs = snapshot.activeRitualIDs
        }
    }

    /// What one tap in QuickAdd did.
    enum QuickAddOutcome: Equatable {
        /// Put into the week, on the day being filled.
        case added
        /// Already in the week on other days; this day was added to it.
        case dayAdded
        /// Already on that day. Nothing changed, and nothing is duplicated.
        case alreadyThere
    }

    /// One tap, one activity, on one day — QuickAdd's whole job.
    ///
    /// The three cases are the three doors `ActivityLibraryView` always had,
    /// in one place so that no row can pick the wrong one: something new is
    /// appended and pinned to the day (`addRitual(_:onWeekday:)`), something
    /// already in the week gains the day and is never copied (`setWeekday`),
    /// and something already on the day is left alone.
    @discardableResult
    func quickAdd(_ id: String, onWeekday weekday: Int) -> QuickAddOutcome {
        guard ritual(id) != nil else { return .alreadyThere }
        if activeRitualIDs.contains(id) {
            if ritual(id)?.happens(on: weekday) == true { return .alreadyThere }
            setWeekday(id, weekday, on: true)
            return .dayAdded
        }
        addRitual(id, onWeekday: weekday)
        return .added
    }

    /// Take several out of the day in one pass — what leaving an Arc does when
    /// somebody asks for its activities to go with it.
    ///
    /// The same act as `removeRitual`, once for the lot, so the week redraws
    /// once and `publishPlanned` writes the day down once. Only what it is
    /// handed goes: an Arc hands it exactly what joining added, never an
    /// activity that was in the week before it (`ArcEnrollment.added`).
    func removeRituals(_ ids: [String]) {
        let leaving = Set(ids)
        guard !leaving.isEmpty, activeRitualIDs.contains(where: leaving.contains) else { return }
        withAnimation {
            activeRitualIDs.removeAll { leaving.contains($0) }
            for id in ids { progress.undo(id) }
        }
    }

    func moveRitual(from: Int, to: Int) {
        activeRitualIDs.move(fromOffsets: IndexSet(integer: from), toOffset: to)
    }
    /// Puts back exactly what an import added, and nothing else.
    ///
    /// Kept after the archetypes were removed because nothing about it was about
    /// archetypes: it takes a list of ids and takes them off the day. The undo
    /// on the suggestion rows in Becoming is the caller now.
    func undoRoutineImport(_ added: [String]) {
        guard !added.isEmpty else { return }
        withAnimation {
            let undoing = Set(added)
            activeRitualIDs.removeAll { undoing.contains($0) }
            for id in added { progress.undo(id) }
            // The headings go back too. Undoing the activities but leaving the
            // day cut into somebody else's three parts would be the half of the
            // change nobody asked to keep.
            if let before = shapeBeforeImport {
                storedShape = before.reconciled(with: activeRitualIDs)
                shapeBeforeImport = nil
            }
        }
    }

    /// The day's shape as it was before the last routine was taken.
    ///
    /// Held only until the undo is used or the screen goes away — this is the
    /// memory of one gesture, not a history, and a stack of them would be a
    /// promise the rest of the app does not make.
    private var shapeBeforeImport: DayShape?

    // MARK: - Owning the shape

    /// Moves an activity to another part of the day.
    ///
    /// Membership is untouched: this changes which heading a row sits under and
    /// nothing else. It is the one operation that makes a shape the user's
    /// rather than a world's — a routine can propose that lifting belongs before
    /// the world is awake, and somebody who lifts at six in the evening can
    /// disagree without giving up the routine.
    func moveActivity(_ id: String, toPart partID: String) {
        withAnimation {
            apply(storedShape.reconciled(with: activeRitualIDs).moving(id, to: partID))
        }
    }

    /// Reorders inside one part, from indices local to that part.
    ///
    /// The drag a `ForEach` in a section reports is local to the section, and it
    /// stays local all the way down — `DayShape` does the arithmetic, and the
    /// day's flat order is read back out afterwards.
    func reorderPart(_ partID: String, from source: IndexSet, to destination: Int) {
        withAnimation(.forgeRow) {
            apply(storedShape
                .reconciled(with: activeRitualIDs)
                .reordering(inPart: partID, from: source, to: destination))
        }
    }

    /// Writes a new shape and brings the day's own order into line with it.
    ///
    /// `activeRitualIDs` stays what it has always been — the truth about what is
    /// in the day — and this only ever reorders it, never adds or removes. That
    /// matters because everything downstream of the day reads the flat list:
    /// the widgets, the snapshot, sync and the Live Activity all show the day in
    /// its order, and a day that looked one way in the app and another on the
    /// lock screen would be the shape feature quietly breaking four surfaces
    /// that never heard of it.
    private func apply(_ shape: DayShape) {
        let reordered = shape.flattened
        assert(Set(reordered) == Set(activeRitualIDs), "a shape change altered the day")
        storedShape = shape
        activeRitualIDs = reordered
    }

    /// Renames a part of the day. Whatever a world called it, the user's words
    /// win from the moment they type them.
    func renamePart(_ partID: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        storedShape = storedShape.reconciled(with: activeRitualIDs).renaming(partID, to: trimmed)
    }

    // MARK: - Custom activities

    /// Makes an activity and puts it straight into the day — the user asked
    /// for it by name, so making them then find it in a picker would be a step
    /// that exists for no one.
    @discardableResult
    func createCustomRitual(_ draft: ActivityDraft) -> Ritual {
        let draft = draft.cleaned
        // Only a *disagreement* teaches anything. Accepting the suggestion is
        // not a preference, and counting it as one would slowly drag every
        // future guess toward whatever the classifier already favours.
        let suggested = ActivityVerification.suggest(
            name: draft.label,
            symbol: draft.symbol,
            memory: verificationMemory
        )
        if draft.verification != suggested {
            verificationMemory.record(draft.verification, for: draft.label)
        }
        let made = Ritual.makeCustom(draft)
        customRituals.append(made)
        withAnimation(.forgeRow) {
            activeRitualIDs.append(made.id)
        }
        return made
    }

    /// One edit path for every activity, whichever kind it is. A user renaming
    /// something has no reason to care whether we shipped it or they invented
    /// it, so the difference is not theirs to notice.
    func editRitual(_ id: String, to draft: ActivityDraft) {
        let wasHealth = ritual(id)?.checksWithHealth ?? false
        commit(draft, to: id, isDeliberate: true)
        // Switched to Apple Health in the composer: the same first time a
        // measurable activity enters the day, through a different door.
        if !wasHealth, activeRitualIDs.contains(id), let edited = ritual(id),
           healthPrimerIsDue(for: edited), !isHealthPrimerWaiting {
            healthPrimer = HealthPrimerRequest(ritualID: id, fromTap: false)
        }
    }

    /// The edit itself, and whether it counts as somebody making a decision.
    ///
    /// `isDeliberate` is false for the schedule operations below — dragging an
    /// activity to Wednesday, or a plan setting its hour — and the distinction
    /// exists because two of the things an edit does are only correct when a
    /// human is looking at the composer:
    ///
    /// * **The Health primer.** It is meant to be raised in context, the first
    ///   time somebody takes on an activity the phone could measure. Raising it
    ///   because a planner moved a run half an hour later would be a permission
    ///   sheet arriving out of nowhere, and it is only ever asked once.
    /// * **Teaching the classifier.** A disagreement with the suggested
    ///   verification is a preference. Re-writing that same preference every
    ///   time a time changes is not a second opinion, it is the same one logged
    ///   again — harmless, and still not a thing a drag should do.
    private func commit(_ draft: ActivityDraft, to id: String, isDeliberate: Bool) {
        var draft = draft.cleaned
        guard !draft.label.isEmpty else { return }

        // A new target typed for steps or sleep is the number Health checks,
        // not only the words in the column (`ActivityMetric.target(fromGoal:)`).
        // A target that does not parse leaves the number where it was.
        if let metric = Ritual.metrics[id], draft.goal != ritual(id)?.tail,
           let parsed = metric.target(fromGoal: draft.goal) {
            draft.target = parsed
        }

        if isDeliberate {

            let suggested = ActivityVerification.suggest(
                name: draft.label,
                symbol: draft.symbol,
                memory: verificationMemory
            )
            if draft.verification != suggested {
                verificationMemory.record(draft.verification, for: draft.label)
            }
        }

        if let index = customRituals.firstIndex(where: { $0.id == id }) {
            customRituals[index].label = draft.label
            customRituals[index].symbolName = draft.symbol
            customRituals[index].verificationOverride = draft.verification
            customRituals[index].tail = draft.goal
            customRituals[index].note = draft.note
            customRituals[index].minutes = draft.minutes
            customRituals[index].startMinute = draft.startMinute
            customRituals[index].priority = draft.priority
            customRituals[index].repeats = draft.repeats
            customRituals[index].categoryOverride = draft.category
            customRituals[index].identityID = draft.identityID
            customRituals[index].target = draft.target
            return
        }

        guard let original = Ritual.find(id) else { return }
        // Only what actually differs is stored, so an activity edited back to
        // how it shipped stops counting as edited and starts tracking the
        // definition again. Every field follows the same rule, including the
        // six that arrived with scheduling — an untouched duration must not be
        // written down, or "reset to default" would have nothing left to undo.
        var edit = RitualEdit()
        if draft.label != original.label { edit.label = draft.label }
        if draft.symbol != (original.symbolName ?? ForgeIcons.symbol(for: original.iconKey)) {
            edit.symbol = draft.symbol
        }
        if draft.verification != (Ritual.libraryVerification[id] ?? .honor) {
            edit.verification = draft.verification
        }
        if draft.goal != original.tail { edit.tail = draft.goal }
        if draft.note != original.note { edit.note = draft.note }
        if draft.minutes != original.minutes { edit.minutes = draft.minutes }
        // Doubly optional: the outer `.some` says the user set it, the inner
        // value says to what. See `RitualEdit.startMinute`.
        if draft.startMinute != original.startMinute { edit.startMinute = .some(draft.startMinute) }
        if draft.priority != original.priority { edit.priority = draft.priority }
        if draft.repeats != original.repeats { edit.repeats = draft.repeats }
        if draft.category != original.category { edit.category = draft.category }
        // Doubly optional, same as `startMinute` above: the outer `.some` says
        // the user decided, the inner value says what they decided. A library
        // activity ships untagged, so any tag at all differs — and untagging one
        // that was tagged has to be storable as a decision rather than as an
        // absence. See `RitualEdit.identityID`.
        if draft.identityID != original.identityID { edit.identityID = .some(draft.identityID) }
        if draft.target != original.target { edit.target = draft.target }
        libraryEdits[id] = edit.isEmpty ? nil : edit
    }

    // MARK: - The week
    //
    // What the Week planner and the AI both write through. Everything here is a
    // small, named edit to an activity's *schedule* — its hour, its length, the
    // days it belongs to — and every one of them funnels into `commit` so a
    // library activity and a user-made one behave identically, exactly as they
    // do in the composer.
    //
    // # What "the week" means in Forge, and what it does not
    //
    // Forge keeps a **practice**, not a calendar. An activity is a standing
    // arrangement — "read, every evening, twenty minutes" — and the week is the
    // shape of those arrangements. So moving Wednesday's reading to Thursday
    // here moves it *every* week, because that is the only kind of Wednesday
    // this app has ever had.
    //
    // That is the right model for what Forge is, and it is deliberately not a
    // calendar with one-off entries on dated rows. It does mean there is
    // currently no way to say "skip just this Tuesday" or "the dentist, once, on
    // the 14th" — which is a real gap, and the honest place to fix it is a dated
    // override on top of this, not by quietly reinterpreting what these methods
    // mean.

    /// What today is about, for whoever is choosing today's challenge.
    ///
    /// Today's activities rather than the whole week's: the challenge is offered
    /// against the day somebody is actually about to live, and a run scheduled
    /// for Saturday says nothing about a Tuesday. See `ChallengeContext`.
    var challengeContext: ChallengeContext {
        let today = todayRituals
        return ChallengeContext(
            activities: today.map(\.label),
            categories: today.map(\.category),
            neglected: neglectedIdentity?.statement
        )
    }

    /// Who somebody said they were becoming and has the least to show for it
    /// this week.
    ///
    /// **This week, not ever.** A cumulative reading would name the identity
    /// somebody took up most recently for months, whatever they did about it;
    /// seven days is short enough that the answer moves when the practice moves,
    /// which is the only thing that makes it worth aiming a challenge at.
    ///
    /// Evidence in days, and ties break on the order they were named — the same
    /// rule everything identity-shaped in this app follows, because it is the
    /// only order the user can predict.
    ///
    /// Nil for the majority who have named nothing. See `ChallengeContext`.
    var neglectedIdentity: Identity? {
        let identities = self.identities
        guard identities.count >= 1 else { return nil }
        let last = progress.currentDay
        let first = last.adding(days: -6)
        return identities.min { a, b in
            progress.daysOfEvidence(taggedTo: activityIDs(taggedTo: a.id), from: first, to: last)
                < progress.daysOfEvidence(taggedTo: activityIDs(taggedTo: b.id), from: first, to: last)
        }
    }

    /// The identities this object can see, for the readings that need them.
    ///
    /// Set from the root alongside `world`, and for the same reason: nothing on
    /// the day's path may hold a reference to a store it does not own, and this
    /// keeps `IdentityStore` out of the view model while letting the challenge
    /// and the notifications read what they need. Empty is the ordinary case.
    var identities: [Identity] = []

    /// Everything in the day, flattened to what a planner needs. See
    /// `ScheduledActivity`.
    var scheduledActivities: [ScheduledActivity] {
        activeRituals.map {
            ScheduledActivity(
                id: $0.id,
                name: $0.label,
                startMinute: $0.startMinute,
                minutes: $0.minutes,
                weekdays: $0.repeats.weekdays,
                identityID: $0.identityID
            )
        }
    }

    // MARK: - What Plan is allowed to see

    /// Everything `DayPlanner` reads, taken once.
    ///
    /// Assembled here for the same reason `AIBrief` is assembled in
    /// `ContentView`: the answer to "what does this feature know about me" has
    /// to be one readable list rather than whatever each rule happened to reach
    /// for. The difference is that **none of this leaves the phone**. It is
    /// wider than the brief precisely because it can afford to be — the shape,
    /// the four weeks of per-activity counts and the rest days are all things a
    /// planner is far better for having and none of them is anything Forge
    /// would transmit.
    ///
    /// `wakeMinutes` is handed in rather than read, because the wake time
    /// belongs to `ForgeNotifications` and nothing on the day's path holds a
    /// reference to it.
    func planFacts(wakeMinutes: Int?) -> DayPlanner.Facts {
        let kept = activeRituals
        let shape = progress.forgeShape(of: kept)
        let held = Set(activeRitualIDs)

        return DayPlanner.Facts(
            activities: scheduledActivities,
            categories: kept.reduce(into: [:]) { $0[$1.id] = $1.category },
            // Only when there is enough behind it to be worth reading. An
            // unreadable shape is not a shape of zeros — it is silence, and a
            // planner that treated it as zeros would tell somebody on their
            // third day that every part of them is failing.
            shape: shape.isReadable ? shape : nil,
            focus: focus,
            restWeekdays: progress.restWeekdays,
            wakeMinutes: wakeMinutes,
            recent: progress.habitCounts(
                from: progress.currentDay.adding(days: -ForgeShape.window),
                to: progress.currentDay.adding(days: -1)
            ).map { DayPlanner.Facts.Habit(id: $0.id, planned: $0.planned, completed: $0.completed) },
            // Library only, and in effort order. A move may recommend taking up
            // something Forge shipped and knows how to verify, file and count;
            // it may not invent an activity, and it may not hand somebody back
            // one of their own that they took out of the day on purpose.
            available: Ritual.library
                .filter { !held.contains($0.id) }
                .sorted { IdentityActivities.effort(of: $0.id) < IdentityActivities.effort(of: $1.id) }
                .map {
                    DayPlanner.Facts.Available(
                        id: $0.id, name: $0.label, minutes: $0.minutes, category: $0.category
                    )
                }
        )
    }

    // MARK: - Evidence

    /// Every activity in the day tagged to an identity.
    ///
    /// Read off the day rather than off the history, so an identity's evidence
    /// is measured against what somebody currently keeps for it. That is the
    /// only reading that stays honest when a tag moves: retagging an activity
    /// changes what it is evidence for from now on *and* backwards, because the
    /// tag is a property of the activity rather than of each completion.
    ///
    /// That was the alternative and it was rejected. Stamping the identity onto
    /// every `DayRecord.Completion` would freeze history correctly, and it would
    /// also mean a day recorded before somebody named an identity could never
    /// count toward it — so a person who had been running for a year and finally
    /// wrote "Someone who trains" would be told they had none. The retroactive
    /// reading is the one that matches what actually happened.
    func activityIDs(taggedTo identityID: String) -> Set<String> {
        Set(activeRituals.filter { $0.identityID == identityID }.map(\.id))
    }

    /// The six dimensions, scored on the last four weeks. See `ForgeShape`.
    ///
    /// Reads the activities somebody keeps *now* against the record, the same
    /// way identity evidence does — so re-filing an activity is retroactive, and
    /// somebody who has been running for a month and only just moved it to
    /// Physical has that month behind them. Naming a thing is not starting it,
    /// here either.
    var shape: ForgeShape { progress.forgeShape(of: activeRituals) }

    /// The six and OVR as every screen shows them: the answers, if there are
    /// any, handing over to the record. With no assessment it is `shape`
    /// exactly. See `BlendedShape` for the rules.
    var blended: BlendedShape {
        BlendedShape.read(
            progress.byDay,
            today: progress.currentDay,
            activities: activeRituals,
            assessment: assessment,
            // A finished daily challenge is a kept day for its dimension, in
            // the blend as in the record (DIRECTION_1_1 §7).
            challenges: progress.challengeCredit
        )
    }

    /// The six as they read seven days ago, for the change on each tile — or
    /// nil when there was nothing of this person to read a week ago. See
    /// `StatGlance.weekAgo`.
    var weekAgo: BlendedShape? {
        StatGlance.weekAgo(
            progress.byDay,
            today: progress.currentDay,
            activities: activeRituals,
            assessment: assessment,
            challenges: progress.challengeCredit
        )
    }

    /// The six tiles on the Becoming tab, in the hexagon's order. See
    /// `StatGlance`.
    var statTiles: [GlanceTile] {
        StatGlance.tiles(now: blended, weekAgo: weekAgo, focus: focus)
    }

    /// The dimension to build next, or nil when there is nothing honest to
    /// name (§5 #3).
    ///
    /// With a focus: a chosen dimension nothing is filed under, first — it is
    /// not being built at all — and otherwise the weakest of the chosen ones,
    /// but only when it is fifteen points behind the best of the six, the bar
    /// `DayPlanner` and `needsAttention` set before naming a weakest side.
    /// With no focus it is `BlendedShape.needsAttention`, exactly. Read from
    /// the blend, which is what the tiles above it show.
    var weakestDimension: RitualCategory? {
        let six = blended
        guard !focus.isEmpty else { return six.needsAttention?.category }
        let chosen = six.dimensions.filter { focus.contains($0.category) }
        if let empty = chosen.first(where: { !$0.record.hasActivities }) { return empty.category }
        guard let weakest = chosen.filter(\.hasScore).min(by: { $0.score < $1.score }),
              let best = six.dimensions.filter(\.hasScore).max(by: { $0.score < $1.score }),
              best.category != weakest.category,
              best.score - weakest.score >= 15
        else { return nil }
        return weakest.category
    }

    /// The Becoming tab's first-week contract, or nil once the shape is drawn.
    /// Read off the record every time; see `FirstWeek`. With an assessment the
    /// hexagon is drawn from day one and this is the progress line under it
    /// rather than the hero in its place.
    var firstWeek: FirstWeek? { progress.firstWeek(isShapeReadable: shape.isReadable) }

    /// The smallest library activity for each dimension nothing is filed under.
    /// See `BecomingStarter`.
    var starters: [RitualCategory: Ritual] {
        BecomingStarter.starters(in: shape, avoiding: Set(activeRitualIDs))
    }

    /// Concrete activities that would feed a dimension, minus anything already
    /// kept. See `ForgeShape.suggestions(for:avoiding:limit:)`.
    func suggestions(for category: RitualCategory) -> [Ritual] {
        ForgeShape.suggestions(for: category, avoiding: Set(activeRitualIDs))
    }

    /// Days this identity has evidence behind it. See
    /// `ProgressStore.daysOfEvidence(taggedTo:)`.
    func daysOfEvidence(for identityID: String) -> Int {
        progress.daysOfEvidence(taggedTo: activityIDs(taggedTo: identityID))
    }

    /// How often the evidence turns up on the days it was asked for, 0…1.
    func evidenceRate(for identityID: String) -> Double {
        progress.evidenceRate(taggedTo: activityIDs(taggedTo: identityID))
    }

    /// The day the evidence starts, which is not the day the identity was named.
    func firstEvidence(for identityID: String) -> ForgeDay? {
        progress.firstEvidence(taggedTo: activityIDs(taggedTo: identityID))
    }

    /// What an activity is evidence for, resolved through the same overlay
    /// everything else about it resolves through.
    func identityID(of ritualID: String) -> String? {
        ritual(ritualID)?.identityID
    }

    /// Tag an activity, or untag it by passing nil.
    ///
    /// Goes through `amend` like every other schedule-shaped edit, so a library
    /// activity's tag lands as an ordinary `RitualEdit` and is the user's from
    /// the first second — editable, resettable, and owned by nothing about
    /// identities.
    func setIdentity(_ identityID: String?, on ritualID: String) {
        amend(ritualID) { $0.identityID = identityID }
    }

    /// Take the tag off everything wearing it.
    ///
    /// Not called when an identity is retired — a retired identity still
    /// explains its history and its activities still point at it. This exists
    /// for the one caller that genuinely needs it: somebody who wants the tag
    /// gone from their day without deleting the identity.
    func clearIdentity(_ identityID: String) {
        for id in activityIDs(taggedTo: identityID) {
            setIdentity(nil, on: id)
        }
    }

    /// What a given weekday holds, in clock order.
    ///
    /// The same ordering the day list uses, so an activity sits in the same
    /// place in the week as it does in today — see `Ritual.chronological`.
    func rituals(onWeekday weekday: Int) -> [Ritual] {
        Ritual.chronological(activeRituals.filter { $0.happens(on: weekday) })
    }

    /// What somebody chose to build that tomorrow has something for, in the
    /// app's own order — all the first run's closing line may promise.
    ///
    /// The line reads "Tomorrow, more physical." It could be built from the
    /// focus alone while the plan was every activity every day; with the plan
    /// on its own days (§17.1), a call on Wednesdays and Sundays is not
    /// tomorrow's on a Monday, and the line would promise a part of somebody
    /// that tomorrow does not ask for.
    var focusTomorrow: [RitualCategory] {
        let tomorrow = progress.currentDay.adding(days: 1).weekday
        let built = Set(rituals(onWeekday: tomorrow).map(\.category))
        return RitualCategory.dimensions.filter { focus.contains($0) && built.contains($0) }
    }

    /// Change one activity's schedule, leaving everything else about it alone.
    private func amend(_ id: String, _ change: (inout ActivityDraft) -> Void) {
        guard let ritual = ritual(id) else { return }
        var draft = ritual.draft
        change(&draft)
        guard draft != ritual.draft else { return }
        commit(draft, to: id, isDeliberate: false)
    }

    /// Give it an hour, or take the one it has away.
    func setStart(_ id: String, minute: Int?) {
        withAnimation(.forgeRow) { amend(id) { $0.startMinute = minute } }
    }

    func setDuration(_ id: String, minutes: Int) {
        amend(id) { $0.minutes = max(0, minutes) }
    }

    /// Take an activity off one day, or put it back on.
    ///
    /// Unticking the last day is refused rather than obeyed. An empty set
    /// already means "every day" everywhere else in the app — see
    /// `RitualRepeat.includes` — so obeying it here would silently move an
    /// activity from one day a week to seven, which is the opposite of what
    /// somebody swiping it away is asking for. The way to have it on no days at
    /// all is to take it out of the day, and that is a different button.
    func setWeekday(_ id: String, _ weekday: Int, on: Bool) {
        amend(id) { draft in
            var days = draft.repeats.weekdays.isEmpty ? Set(1...7) : draft.repeats.weekdays
            if on { days.insert(weekday) } else { days.remove(weekday) }
            guard !days.isEmpty else { return }
            draft.repeats = RitualRepeat(weekdays: days)
        }
    }

    // MARK: - Copying a day

    /// What copying one day onto another would actually add.
    ///
    /// Asked before anything happens, so the button can say what it will do and
    /// take itself away when there is nothing left to say — the same rule the
    /// routine offer follows. Anything the destination already holds is left out
    /// rather than counted, so copying a Monday onto a Thursday that shares two
    /// of its activities is an offer of the difference.
    func dayCopyAddition(from source: Int, to destination: Int) -> [Ritual] {
        guard source != destination else { return [] }
        return rituals(onWeekday: source).filter { !$0.happens(on: destination) }
    }

    /// Give another day everything this one holds.
    ///
    /// **What a copy is, in an app with no dated tasks.** Forge keeps a practice:
    /// an activity is a standing arrangement and a day of the week is the set of
    /// arrangements that land on it. So copying Monday onto Thursday puts each of
    /// Monday's activities *on Thursday as well* — same name, same hour, same
    /// length — and that is the whole operation. Monday is untouched, which is
    /// the property that makes this safe to press.
    ///
    /// Nothing here widens anything. Each activity gains exactly one weekday, so
    /// a Monday-only run copied to Thursday runs on those two days and on no
    /// others — it does not become daily, and it does not become "every weekday"
    /// after three copies. Undoing one day of it is the row's own Delete, which
    /// takes an activity off the day it is shown on. See `setWeekday`.
    ///
    /// The alternative — minting a duplicate activity for the destination — was
    /// rejected. It reads the same on screen and it quietly breaks everything
    /// that counts an activity over time: two "Read"s in the picker, two entries
    /// in the analytics, and a thirty-day milestone that can never be met because
    /// half the days were logged under the copy's id.
    ///
    /// Returns what it added, so the screen can say how much happened.
    @discardableResult
    func copyDay(from source: Int, to destination: Int) -> [String] {
        let adding = dayCopyAddition(from: source, to: destination).map(\.id)
        guard !adding.isEmpty else { return [] }
        withAnimation(.forgeRow) {
            for id in adding { setWeekday(id, destination, on: true) }
        }
        return adding
    }

    // MARK: - Copying a day that actually happened

    /// A day in the record, reduced to what reusing it needs.
    ///
    /// A value rather than a `DayRecord`, for the reason every other value in
    /// this file is one: the sheet that draws these must not be able to reach
    /// the history, and everything it needs to render a row and explain a button
    /// is here.
    struct PastDay: Identifiable, Equatable {
        let day: ForgeDay
        /// What the day was planned as, resolved to activities that still exist.
        let activities: [Ritual]
        let keptCount: Int
        let plannedCount: Int
        /// Whether the blade came out on it.
        let isEarned: Bool

        var id: ForgeDay { day }
    }

    /// The days behind, most recent first, that held something.
    ///
    /// # Why this can exist without storing anything new
    ///
    /// `DayRecord.plannedIDs` has always recorded what a day was made of on the
    /// day itself — it is there so that adding an activity next week cannot
    /// retroactively make last Tuesday incomplete. That field is a complete
    /// answer to "what was I doing on the 14th", and nothing had ever read it
    /// for that. So browsing the record costs no schema change, no migration and
    /// no second copy of anything.
    ///
    /// **Today is excluded.** Copying today onto today is a no-op dressed as a
    /// button, and it would be the first row in the list.
    ///
    /// **Ids that no longer resolve are dropped rather than shown.** An activity
    /// deleted last month is not something anybody can be offered back, and a
    /// row that silently adds four of the six things it named would be worse
    /// than one that names four.
    func recentDays(limit: Int = 30) -> [PastDay] {
        progress.byDay.values
            .filter { $0.day < progress.currentDay && !$0.plannedIDs.isEmpty }
            .sorted { $0.day > $1.day }
            .prefix(limit)
            .compactMap { record in
                let activities = record.plannedIDs.compactMap { ritual($0) }
                guard !activities.isEmpty else { return nil }
                return PastDay(
                    day: record.day,
                    activities: Ritual.chronological(activities),
                    keptCount: record.completedCount,
                    plannedCount: record.plannedCount,
                    isEarned: record.isEarned
                )
            }
    }

    /// What reusing a past day would actually add to a weekday.
    ///
    /// The same contract `dayCopyAddition` has, and deliberately so: asked
    /// before anything happens, so the button can say what it will do and take
    /// itself away when there is nothing left to say. Anything the destination
    /// already holds is left out rather than counted.
    /// **Re-resolved by id rather than read off the value.** `PastDay` is a
    /// snapshot taken when a sheet appeared, and the `Ritual`s inside it carry
    /// the `repeats` they had at that moment. Filtering those directly answers
    /// "did this activity happen on Thursday *when the sheet opened*", which is
    /// the wrong question and goes stale the instant anything is copied — the
    /// button would go on offering activities it had already added. Looking each
    /// one up again asks the live day, which is the only version that can be
    /// right. A test holds this: see `copyPastDayIsIdempotent`.
    func pastDayAddition(_ past: PastDay, to weekday: Int) -> [Ritual] {
        past.activities
            .compactMap { ritual($0.id) }
            .filter { !$0.happens(on: weekday) }
    }

    /// Put a day that happened back into the practice.
    ///
    /// Exactly the operation `copyDay` performs, reached from the other
    /// direction — each activity gains one weekday and nothing is duplicated,
    /// widened or reset. It has to be the same operation: two ways of copying a
    /// day that produced two different kinds of result is how somebody ends up
    /// with two "Read"s in the picker and a milestone that can never be met.
    /// See `copyDay` for the whole argument, which applies here word for word.
    @discardableResult
    func copyPastDay(_ past: PastDay, to weekday: Int) -> [String] {
        let adding = pastDayAddition(past, to: weekday).map(\.id)
        guard !adding.isEmpty else { return [] }
        withAnimation(.forgeRow) {
            for id in adding { setWeekday(id, weekday, on: true) }
        }
        return adding
    }

    /// Take an activity off the day it is being looked at on.
    ///
    /// The one operation the week needs that neither `setWeekday` nor
    /// `removeRitual` is on its own, because which of the two is right depends on
    /// the activity: something that also happens on Tuesday should lose only
    /// Thursday, and something that happens on Thursday alone has nothing left to
    /// be once Thursday is taken away, so it leaves the week. Both are "take this
    /// off Thursday" to the person swiping, and that is the only sentence the row
    /// is allowed to need.
    func removeFromDay(_ id: String, weekday: Int) {
        guard let ritual = ritual(id) else { return }
        if ritual.repeats.weekdays.count > 1 {
            setWeekday(id, weekday, on: false)
        } else {
            removeRitual(id)
        }
    }

    /// Move an activity from one day of the week to another.
    ///
    /// Off the first and onto the second in one edit rather than two, so the
    /// week redraws once and an activity is never briefly on neither day.
    func moveActivity(_ id: String, from: Int, to: Int) {
        guard from != to else { return }
        withAnimation(.forgeRow) {
            amend(id) { draft in
                var days = draft.repeats.weekdays.isEmpty ? Set(1...7) : draft.repeats.weekdays
                days.remove(from)
                days.insert(to)
                guard !days.isEmpty else { return }
                draft.repeats = RitualRepeat(weekdays: days)
            }
        }
    }

    // MARK: - Applying a plan

    /// Take on everything a plan proposes, in one pass.
    ///
    /// Returns what it actually changed, so the screen can say "seven changes"
    /// rather than assume. A change naming an activity that has since been
    /// deleted is skipped rather than failing the batch — a plan is read from a
    /// snapshot of the week and the week is allowed to have moved under it.
    ///
    /// Nothing here asks. Consent happened on the review screen, which is the
    /// only place it can be given, because it is the only place the changes were
    /// legible — see `SchedulePlan`.
    @discardableResult
    func apply(_ plan: SchedulePlan) -> Int {
        var applied = 0
        withAnimation(.forgeRow) {
            for change in plan.changes {
                switch change {
                case .time(let id, _, let minute, _):
                    guard ritual(id) != nil else { continue }
                    amend(id) { $0.startMinute = minute }
                    applied += 1

                case .duration(let id, _, let minutes, _):
                    guard ritual(id) != nil else { continue }
                    // The target follows when it only ever said the length —
                    // see `ActivityDraft.setLength`.
                    amend(id) { $0.setLength(minutes) }
                    applied += 1

                case .days(let id, _, let weekdays, _):
                    guard ritual(id) != nil, !weekdays.isEmpty else { continue }
                    amend(id) { $0.repeats = RitualRepeat(weekdays: weekdays) }
                    applied += 1

                case .create(let draft):
                    guard !draft.cleaned.label.isEmpty else { continue }
                    createCustomRitual(draft)
                    ForgeTelemetry.send(.activityAdded(.plan))
                    applied += 1

                case .adopt(let id, _, let minutes, let weekdays, let minute):
                    // Has to resolve, and has to not already be in the day.
                    // Both guards are about the same failure: a plan somebody
                    // read ten minutes ago, applied after adding the same
                    // activity by hand.
                    guard ritual(id) != nil, !activeRitualIDs.contains(id) else { continue }
                    addRitual(id)
                    ForgeTelemetry.send(.activityAdded(.plan))
                    // After `addRitual`, which pins an unscheduled activity to
                    // today — the plan's own days are the deliberate answer and
                    // must win over that default.
                    //
                    // The length too, now that something proposes one other
                    // than the library's: an Arc takes "Work out" up at thirty
                    // minutes, not the twenty it ships with. `DayPlanner`
                    // proposes the library's own length, so for it this changes
                    // nothing.
                    amend(id) {
                        if !weekdays.isEmpty { $0.repeats = RitualRepeat(weekdays: weekdays) }
                        if let minute { $0.startMinute = minute }
                        if minutes > 0, minutes != $0.minutes { $0.setLength(minutes) }
                    }
                    applied += 1

                case .goal(let id, _, let goal, let target, _):
                    guard ritual(id) != nil else { continue }
                    amend(id) {
                        $0.goal = goal
                        if let target { $0.target = target }
                    }
                    applied += 1
                }
            }
        }
        return applied
    }

    /// Puts a library activity back the way it shipped.
    func resetRitual(_ id: String) {
        withAnimation(.forgeRow) {
            libraryEdits[id] = nil
        }
    }

    /// The live suggestion shown in the composer as the name is typed.
    func suggestedVerification(name: String, symbol: String?) -> VerificationMethod {
        ActivityVerification.suggest(name: name, symbol: symbol, memory: verificationMemory)
    }

    /// Throws a user-made activity away for good, day included. Removing it
    /// from the day alone is `removeRitual`.
    ///
    /// The deletion is written down as a fact, not just as an absence. An
    /// account that has never signed in will never do anything with that fact,
    /// and it costs a few bytes — but whether somebody signs in later is not
    /// knowable at the moment they press delete, and an activity that comes
    /// back from the dead on a new phone is not a bug anybody can explain away.
    func deleteCustomRitual(_ id: String) {
        removeRitual(id)
        withAnimation { customRituals.removeAll { $0.id == id } }
        SyncLedger().recordTombstone(id)
    }

    /// User-made activities not currently in the day — what the picker
    /// offers to put back.
    var unusedCustomRituals: [Ritual] {
        customRituals.filter { !activeRitualIDs.contains($0.id) }
    }

    /// When the blade actually came free, not when the label happened to be
    /// drawn — the free state is on screen for the rest of the day.
    var finishTime: String {
        ForgeViewModel.clockFormat.string(from: progress.today.extractedAt ?? progress.now)
    }

    private static let clockFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    // MARK: - The summary

    /// What to say once the blade has settled, or nil while there is nothing to
    /// say. Held rather than derived so the sentence cannot change under the
    /// user while they are reading it — finishing a sixth activity behind the
    /// overlay must not renumber the day mid-sentence.
    private(set) var summary: DaySummary?

    /// The resting version of the summary's second line, kept on the freed panel
    /// for the rest of the day.
    ///
    /// Deliberately the same sentence rather than a second one written for the
    /// same job. The overlay is three seconds long; this is what it settles into,
    /// and hearing it twice in two voices would make both sound composed.
    ///
    /// The standard is deliberately *not* read here. A line about having been up
    /// before the world was true at the moment it was earned and would quietly
    /// become false by the afternoon, so it belongs to the beat and not to the
    /// panel that outlives it.
    var identityLine: String {
        DaySummary.make(daysKept: progress.daysKept).line
    }

    /// Never during the first run. That sequence closes with a beat of its own,
    /// and two closing screens in ninety seconds is one too many.
    ///
    /// `moment` is what was just finished, and it is handed in rather than
    /// worked out here: whether today's challenge was completed is the challenge
    /// store's business, and this object has stayed free of any opinion about
    /// challenges. What it contributes is the day's own leaning — see
    /// `ChallengeContext.leaning` — which is the same reading the challenge was
    /// chosen with this morning.
    func presentSummary(challengeFocus: ChallengeFocus? = nil) {
        guard hasCompletedFirstRun else { return }
        withAnimation(.easeOut(duration: 0.5)) {
            summary = DaySummary.make(
                daysKept: progress.daysKept,
                quote: reflection(challengeFocus: challengeFocus)
            )
        }
    }

    /// The line the finished day earned, for as long as it is that day.
    ///
    /// **The same sentence the summary shows, from the same expression**, which
    /// is the entire reason this is a method rather than two call sites building
    /// an `EarnedMoment` each. The summary takes itself away after three seconds
    /// and most people miss it; the resting panel then shows this until the day
    /// turns over. Two readings of "what did today earn" that could differ would
    /// mean the sentence somebody half-read in the overlay and the one they
    /// found later were different quotations, which reads as a bug in the one
    /// place the app is trying to sound deliberate.
    ///
    /// Deterministic and derived: it is arithmetic on the civil date and what
    /// the day was made of — see `ForgeQuotes` — so it is the same on two
    /// devices, survives a relaunch, and is not stored anywhere.
    ///
    /// Nil until the day is actually earned. The blade can be out on a day that
    /// was not finished — the first pull is given rather than earned — and a
    /// reflection on a day nobody completed would be the app congratulating
    /// somebody for the grace it handed them.
    func reflection(challengeFocus: ChallengeFocus? = nil) -> AttributedQuote? {
        guard progress.isTodayEarned else { return nil }
        let moment: EarnedMoment = challengeFocus.map(EarnedMoment.challenge)
            ?? .day(leaning: challengeContext.leaning)
        return ForgeQuotes.quote(for: moment, on: progress.currentDay)
    }

    func dismissSummary() {
        withAnimation(.easeIn(duration: 0.34)) { summary = nil }
    }

    // MARK: - Tomorrow

    /// The evening's one deliberate act, if it has been made.
    private(set) var commitment: DayCommitment? {
        didSet { persistCommitment() }
    }

    /// The day being settled — the one after whichever day the app is in.
    var tomorrow: ForgeDay { progress.currentDay.adding(days: 1) }

    /// Whether the evening is open for it. Read off the same clock the rest of
    /// the app uses, so a debug day offset moves this with everything else.
    ///
    /// Not observable, deliberately. Six o'clock arriving while somebody is
    /// staring at the panel will not make the row appear under them — it appears
    /// the next time anything redraws, which includes every return to the
    /// foreground. A timer that ticked all day to catch the one person holding
    /// the app open across the hour would cost more than the case is worth.
    var isEveningOpen: Bool {
        EveningCommitment.isOpen(now: progress.now, dayStartHour: progress.dayStartHour)
    }

    var isTomorrowSet: Bool { commitment?.day == tomorrow }

    /// Somebody looked at tomorrow and said yes.
    ///
    /// Writes down the fact and nothing else. Whatever they reordered or swapped
    /// while they were in there has already been saved, because it was the real
    /// day they were editing.
    func setTomorrow() {
        withAnimation(.smooth(duration: 0.4)) {
            commitment = DayCommitment(day: tomorrow, at: progress.now)
        }
    }

    private func persistCommitment() {
        guard isLoaded else { return }
        guard let commitment, let data = try? JSONEncoder().encode(commitment) else {
            ForgeShared.defaults.removeObject(forKey: Key.commitment)
            return
        }
        ForgeShared.defaults.set(data, forKey: Key.commitment)
    }
}

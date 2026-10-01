import StoreKit
import SwiftUI
import UserNotifications

struct ContentView: View {
    @State private var selectedTab: AppTab = .forge
    /// Whether one of the three things the app can ask for is on screen.
    ///
    /// In memory only, and deliberately: none of them is a fact about the
    /// practice, and a review dismissed on one launch being offered again on the
    /// next is the correct behaviour for a return screen (the gap is still
    /// there) and prevented for the review by its own stored row. See
    /// `offerWhatIsDue()`.
    @State private var isReturning = false
    @State private var showReview = false
    @State private var showChapterClose = false
    /// Settings, opened from the gear in the Becoming and Blade navigation
    /// bars. Held here, at the root, so a notification or a widget landing on
    /// Forge can put it away like every other sheet — see `landOnHome`.
    @State private var showSettings = false
    /// The history every other object reads. Built first and handed down, so
    /// there is one answer to "what have I done" for the whole app.
    @State private var progress: ProgressStore
    @State private var forgeVM: ForgeViewModel
    @State private var bladeVM: BladeViewModel
    @State private var settingsVM: SettingsViewModel
    /// Owned here, and handed to every screen that draws a sword, so the
    /// collection and the sword in the stone can never disagree.
    @State private var swords: SwordStore
    /// What has been bought. Built here and read wherever the answer matters, so
    /// there is one entitlement in the app and no screen can form a second
    /// opinion about it.
    ///
    /// No default value, deliberately. A property with one is initialised before
    /// the body of `init` runs and then overwritten by it — which would build
    /// two of these and leave the first one's `Transaction.updates` listener
    /// running forever, in a class whose own comment explains why it never
    /// cancels one.
    @State private var store: ForgeStore
    /// When Forge may ask for a rating: at most twice, never in the first run,
    /// never over the day. See `RatingPrompt`.
    private let ratings = RatingPrompt()
    @Environment(\.requestReview) private var requestReview
    /// Whether somebody has allowed Forge's AI. Read by the consent screen and
    /// Settings through the environment, and by `RemoteForgeAI` straight from
    /// the suite before anything else. See `AIConsentStore`.
    @State private var aiConsent: AIConsentStore
    /// Which world the app is dressed in. Owned here alongside the other
    /// stores, because a Path changes what every screen looks like and there
    /// has to be exactly one answer to that for the whole process.
    /// Who the user says they are becoming. Owned here alongside the other
    /// stores for the reason all of them are: an identity is read by anything
    /// that draws a day, a record or a direction, and there has to be exactly
    /// one answer to "who is this person becoming" for the whole process.
    ///
    /// Deliberately not part of `ProgressStore`. What
    /// somebody is working toward is a statement of intent; what they did is a
    /// fact. Mixing the two would put an editable sentence inside the one file
    /// whose contents people would actually grieve losing.
    @State private var identities: IdentityStore
    /// What somebody is in the middle of. Owned here with the other stores for
    /// the same reason: a chapter is a window over the whole record, and two
    /// answers to "what am I inside" would be no answer. See `ChapterStore`.
    @State private var chapters: ChapterStore
    /// What somebody wrote about their weeks. Owned here because the review is
    /// offered above the whole app rather than from a tab — it is about the week
    /// and not about any one screen. See `ReviewStore`.
    @State private var reviews: ReviewStore
    /// Today's challenge, for everybody. Owned here for the same reason the
    /// others are: it turns over at four in the morning with the rest of the
    /// app, and there has to be one answer to "what is today's" for the process.
    @State private var challenges: ChallengeStore
    /// The Arcs somebody has joined (DIRECTION_1_1 §5). Owned here for the
    /// reason the chapters are: an Arc is a window over the whole record, read
    /// by the day, the Arcs tab, the Blade tab and the morning notification,
    /// and there has to be one answer to "which Arc am I in". See `ArcStore`.
    @State private var arcs: ArcStore
    // **There is no cloud half, and no account.** A `ForgeBackend` used to be
    // built here — last, because it read the five stores above and nothing read
    // it — and the doc comment promised that deleting it would leave every
    // screen working exactly as it does now. 1.0 took the promise up on itself:
    // there is no sign-in control anywhere in the app, nothing is gated on a
    // session, and the day, the record, the Shape and the widgets all read the
    // App Group and nothing else.
    //
    // The `Backend/` folder is still in the target and still compiles, because
    // 1.1's line is sync and rebuilding a verified merge engine would be the
    // actual waste — but nothing in the running app constructs any of it, and
    // `Forge/Info.plist` carries no project for it to reach even if something
    // did. See `BackendRegressionTests.theAppShipsWithNoAccount`.

    /// Not owned — it belongs to the app, which claimed the notification
    /// centre's delegate before this view existed.
    private let notifications = ForgeNotifications.shared

    /// What sits behind the AI screens.
    ///
    /// A protocol rather than a concrete type, and the promise that made was
    /// kept: connecting the real model was this one property and nothing else.
    /// `RemoteForgeAI` posts to Forge's own backend — never to a model endpoint,
    /// and never with a key in the binary — and falls back to `LocalForgeAI`
    /// whenever it cannot, which is a phone in a tunnel, somebody without
    /// Premium, a build with no project configured, or an answer that did not
    /// survive being checked. Nothing in the app is worse for any of those.
    ///
    /// The generated archetype is the one thing reached on the concrete type
    /// rather than through the protocol: writing a world is not something every
    /// implementation can do, and the arithmetic should not pretend otherwise.
    private let remote: RemoteForgeAI
    private var ai: ForgeAI { remote }

    @Environment(\.scenePhase) private var scenePhase

    init() {
        let progress = ProgressStore()
        let forge = ForgeViewModel(progress: progress)
        let swords = SwordStore(progress: progress)
        let store = ForgeStore()
        let identities = IdentityStore()
        // Built as locals first rather than defaulted on the properties: a
        // default initialiser runs before the body of `init` and would then be
        // overwritten by it, which builds two of everything.
        let chapters = ChapterStore()
        let reviews = ReviewStore()
        _aiConsent = State(initialValue: AIConsentStore())
        _chapters = State(initialValue: chapters)
        _reviews = State(initialValue: reviews)
        _progress = State(initialValue: progress)
        _forgeVM = State(initialValue: forge)
        _identities = State(initialValue: identities)
        // Two lookups the record cannot do for itself, both weak and both for
        // the same reason: an activity somebody invented — and which identity it
        // is evidence for — only resolve through the day's own view model, and
        // nothing about the Blade tab is allowed to keep the day alive.
        _bladeVM = State(
            initialValue: BladeViewModel(
                progress: progress,
                resolve: { [weak forge] id in forge?.ritual(id) },
                tagged: { [weak forge] id in forge?.activityIDs(taggedTo: id) ?? [] }
            )
        )
        _settingsVM = State(initialValue: SettingsViewModel(progress: progress))
        _swords = State(initialValue: swords)
        _store = State(initialValue: store)
        // The challenge leans on what the day is already made of, and only the
        // day's own view model knows that. Weak, and the same shape the trends
        // page uses to resolve an activity — nothing about a challenge is
        // allowed to keep the day alive.
        _challenges = State(
            initialValue: ChallengeStore(progress: progress) { [weak forge] in
                forge?.challengeContext ?? ChallengeContext()
            }
        )
        // The Arcs reach the week the way the challenge reaches the day:
        // through the day's own view model, weakly, and only through the doors
        // it already has — `apply` for a plan somebody has read, and taking
        // activities off for somebody leaving.
        _arcs = State(
            initialValue: ArcStore(
                progress: progress,
                week: { [weak forge] in forge?.activeRituals ?? [] },
                find: { [weak forge] id in forge?.ritual(id) ?? Ritual.find(id) },
                write: { [weak forge] plan in forge?.apply(plan) ?? 0 },
                takeOff: { [weak forge] ids in forge?.removeRituals(ids) }
            )
        )
        // No visible account, and none is added here (§2n, §2q). A model
        // request is made under an invisible anonymous identity and carries
        // the StoreKit proof of purchase. `RemoteForgeAI` checks, in order:
        // the switch, the person's consent, the purchase, and only then the
        // identity — so nobody without Pro, or who has not pressed Allow, ever
        // has one created, and nothing here runs at launch (§2r).
        //
        // In this build none of it runs. There is no project in `Info.plist`,
        // so `fromBundle()` answers nil and no endpoint can be built; and
        // `RemoteForgeAI.isModelEnabled` is false, which forces the same
        // answer a second time. Neither closure below is ever called, and
        // `RemoteForgeAI` is a passthrough to `LocalForgeAI`.
        let config = SupabaseConfig.fromBundle()
        let identity = AnonymousIdentity(
            api: config.map { SupabaseAuthAPI(client: HTTPClient(config: $0)) }
        )
        remote = RemoteForgeAI(
            config: config,
            token: { await identity.accessToken() },
            entitlement: { await ForgeStore.entitlementProof() }
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(AppTab.forge.label, systemImage: AppTab.forge.symbol, value: .forge) {
                forgeTab
            }
            Tab(AppTab.arcs.label, systemImage: AppTab.arcs.symbol, value: .arcs) {
                arcsTab
            }
            // The one tab drawn from the catalogue rather than from SF Symbols.
            // See `AppTab.image`.
            Tab(AppTab.becoming.label, image: AppTab.becoming.image ?? AppTab.becoming.symbol, value: .becoming) {
                becomingTab
            }
            Tab(AppTab.blade.label, systemImage: AppTab.blade.symbol, value: .blade) {
                bladeTab
            }
        }
        // Settings is no longer a tab; it is one sheet, opened from the gear in
        // the Becoming and Blade bars. Inside `ForgeProModifier` below like the
        // other sheets, so the store reaches it.
        .sheet(isPresented: $showSettings) { settingsTab }
        // The world, handed to every screen at once. Pushed into the environment
        // rather than passed down, so a view is themed without having heard of
        // Paths — which is what keeps the fifth world from being a week of work
        // in files that have nothing to do with worlds.
        // Today's sentence, resolved here because this is the one place that
        // holds both the world and the day. Recomputed when either changes,
        // which is also what makes it correct across midnight without a timer.
        // For the few screens that have to name the world rather than merely be
        // dressed by it. See `EnvironmentValues.activePath`.
        // Who the user is becoming, handed to every screen at once. Active
        // only: a retired identity still explains history and is looked up by
        // id where that matters, but nothing should offer it as somewhere to
        // put today's work. See `IdentityStore.active`.
        .environment(\.identities, identities.active)
        // The world the day is being kept in, handed to the one object that
        // knows when a day is banked. Set here and on every change rather than
        // read out of a store the view model holds, so nothing on the day's
        // path keeps a reference to Paths — deleting the feature would still
        // leave every screen working, which is the promise the tab was built on.
        // The same shape, for the same reason: the day's view model reads
        // identities for the challenge's aim and the review's facts, and holds
        // no reference to the store that owns them.
        .task(id: identities.active.map(\.id)) {
            forgeVM.identities = identities.active
        }
        // The accent every native control picks up. One colour, applied once at
        // the root — it briefly asked the active world what it should be, which
        // went with the worlds.
        .tint(ForgeTheme.accent)
        // Native Liquid Glass tab bar shrinks to a pill as content scrolls up.
        .tabBarMinimizeBehavior(.onScrollDown)
        // Three ways the day can turn over under the app, and it has to survive
        // all of them: opening it fresh, coming back to it after midnight, and
        // the system announcing a clock or timezone change while it is running.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                progress.rollOver()
                // Straight after the day, and before anything draws: the
                // panel's challenge action reports today's state, and a phone
                // opened at half past four would otherwise show yesterday's for
                // a frame.
                challenges.rollOver()
                // A "Start Monday" waiting for its Monday is written into the
                // week on the first open of that day.
                arcs.applyIfDue()
                syncAmbient()
                // A free week that ended, or a subscription that lapsed, while
                // the app was away says nothing on `Transaction.updates`; the
                // entitlement is read again whenever the app comes forward.
                Task { await store.refreshEntitlement() }
            default:
                break
            }
        }
        // `onChange` does not fire for the value a view launches with, so this
        // is the launch pass. Every later one comes from the scene phase above.
        .task {
            arcs.applyIfDue()
            syncAmbient()
            // How old the install is, for every signal: read off the oldest
            // record each time rather than stored anywhere.
            let store = progress
            ForgeTelemetry.readInstallAge { [weak store] in store?.daysSinceFirstRecord }
            // A launch that opens into the first run on the day of the first
            // record. A relaunch mid-onboarding on that day counts again, which
            // the dashboard reads as unique users rather than as signals.
            if !forgeVM.hasCompletedFirstRun {
                if progress.daysSinceFirstRecord == 0 {
                    ForgeTelemetry.send(.appFirstOpen)
                }
                // The first beat is the one the stage starts on, so its
                // `didSet` never fires for it.
                if forgeVM.firstRunStage == .coldOpen {
                    ForgeTelemetry.send(.onboardingStep(.coldOpen))
                }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.significantTimeChangeNotification
            )
        ) { _ in
            progress.rollOver()
            challenges.rollOver()
        }
        // The things that can change the answer while the app is open: the day
        // moving, the day turning over under it, and either of the two
        // settings. Anything already pending is cancelled and re-decided.
        .onChange(of: progress.today) { _, _ in
            syncAmbient()
        }
        // Midnight, or a timezone the phone woke up in. The day's denominator
        // depends on the weekday now that activities can repeat, so it has to be
        // written down again before anything reads it — see
        // `ForgeViewModel.publishPlanned`.
        .onChange(of: progress.currentDay) { _, _ in
            forgeVM.publishPlanned()
            challenges.rollOver()
            arcs.applyIfDue()
            syncAmbient()
        }
        .onChange(of: notifications.isEnabled) { _, _ in syncAmbient() }
        .onChange(of: notifications.wakeMinutes) { _, _ in syncAmbient() }
        // The schedule itself, which is the input the notifications are made
        // from and the one thing nothing above was watching.
        //
        // `progress.today` catches a change to *today's* list, and caught
        // everything back when a notification was one reminder at one time. It
        // catches none of what matters now: an hour moved, an activity taken off
        // Thursday, a repeat rule narrowed, a day copied onto another. Every one
        // of those leaves today untouched and every one of them changes what
        // should be pending — see `ForgeNotificationPlan.make`, which is
        // rebuilt whole each time this fires.
        .onChange(of: forgeVM.scheduledActivities) { _, _ in syncAmbient() }
        // Opened from a notification. All three are about the same thing, so
        // there is one place to land and no second tap to get there.
        .onChange(of: notifications.opened) { _, opened in
            guard let opened else { return }
            ForgeTelemetry.send(.notificationOpened(opened))
            landOnHome()
            notifications.opened = nil
        }
        // Opened from a widget or the Live Activity. Every one of them links to
        // the same place for the same reason a notification does: they are all
        // about this day, and arriving anywhere else would need a tap to
        // undo.
        .onOpenURL { url in
            guard ForgeLink.isForge(url) else { return }
            landOnHome()
        }
        // Presented over the whole app rather than from a tab: a blade is
        // earned by pulling the sword on the Forge tab, but what follows
        // belongs to the app, and it has to cover the tab bar to land.
        .overlay { earnedSummary }
        .overlay { unlockCelebration }
        // The three things the app can ask for, in one modifier.
        //
        // Grouped rather than chained here for a mundane reason worth writing
        // down: six more modifiers on this body took the type checker past its
        // budget and the whole file stopped compiling. A modifier that owns its
        // own presentation is also the honest shape — these three are one
        // decision, taken in one place, and `offerWhatIsDue` is that decision.
        .modifier(
            MomentsModifier(
                isReturning: $isReturning,
                showReview: $showReview,
                showChapterClose: $showChapterClose,
                currentDay: progress.currentDay,
                scenePhase: scenePhase,
                offer: { offerWhatIsDue() },
                returning: { returning },
                review: { weeklyReview },
                chapterClose: { chapterClose }
            )
        )
        // An overlay rather than a cover or a sheet, for the same reason the
        // celebration above is one: this is app-owned full-screen content with
        // no dismissal of its own, and driving a presentation modifier from
        // state the user cannot change means fighting the presentation system
        // for nothing.
        .overlay { firstRun }
        // The blade tore free. Everything that follows a pull is sequenced from
        // here, in one place, so the summary, the blade and the end of the first
        // run cannot arrive on top of each other.
        .onChange(of: forgeVM.isOut) { wasOut, isOut in
            guard !wasOut, isOut else { return }
            Task { @MainActor in await settleThenSpeak() }
        }
        // Last, and it has to be: it puts the store into the environment, and
        // the environment only reaches what is *inside* the modifier that sets
        // it — the review and chapter sheets above included.
        .modifier(
            ForgeProModifier(
                store: store, consent: aiConsent, notifications: notifications
            ) { publishSnapshot() }
        )
    }

    // MARK: - After the pull

    /// Wait for the scene, then say one thing.
    ///
    /// The scene spends 2.4s settling the blade, the stone and the light after
    /// the break, and putting anything over the top of that would step on the
    /// one moment the whole screen exists for. Nothing is presented until it has
    /// very nearly finished.
    @MainActor
    private func settleThenSpeak() async {
        try? await Task.sleep(for: .milliseconds(1900))
        // The blade can be sent back inside that window by undoing a ritual. If
        // it has been, the day was not finished after all.
        guard forgeVM.isOut else { return }
        // A day that also carried a finished challenge is a different day, and
        // the sentence that closes it should know that. Everything else falls
        // back to what the day itself was about.
        forgeVM.presentSummary(
            challengeFocus: challenges.today.state == .completed
                ? challenges.today.challenge.focus
                : nil
        )
        // A first run has no summary of its own — `presentSummary` declines —
        // so nothing was raised and there is nothing to wait for.
        if forgeVM.summary == nil { finishEarnedSequence() }
    }

    /// What happens once the summary has had its three seconds.
    ///
    /// The rare day that also earns a blade gets the celebration here rather
    /// than alongside, so the two are never on screen together. Everything else
    /// goes straight back to the app, which is the whole point of the beat.
    @MainActor
    private func finishEarnedSequence() {
        forgeVM.dismissSummary()
        let earnedBlade = swords.claimBlades()
        // The first run ends on whichever of the two came last.
        if forgeVM.firstRunStage == .pull, !earnedBlade {
            forgeVM.firstRunStage = .closing
        }
    }

    // MARK: - The AI's view of the day

    /// Everything Forge would tell a model about the person asking, built in the
    /// one place that holds the day, the world and the clock at once.
    ///
    /// Assembled here rather than reached for inside the AI screens, so what
    /// leaves the app is a list somebody can read in ten lines — see `AIBrief`
    /// for what is deliberately not in it.
    private var aiBrief: AIBrief {
        AIBrief(
            daysKept: progress.daysKept,
            streak: progress.currentStreak,
            // The whole week, not just today. A planner asked to arrange three
            // sessions across a week cannot do it from one day's list, and the
            // Monday-only activity it could not see is exactly the one it would
            // schedule on top of.
            activities: forgeVM.scheduledActivities,
            parts: forgeVM.dayParts.map(\.name).filter { !$0.isEmpty },
            wakeMinutes: notifications.isEnabled ? notifications.wakeMinutes : nil,
            // The statements, never the ids. An id is a join key that means
            // nothing off this device; the sentence is the only part of an
            // identity a planner can actually use, and it is also the most
            // personal thing Forge holds — which is why it is listed on the
            // disclosure screen rather than described there.
            identities: identities.active.map(\.statement),
            chapterIntention: chapters.current?.intention ?? ""
        )
    }

    /// The same brief with a week attached, for the one call that reads the
    /// record back. Nothing else sends this — see `AIBrief.week`.
    private func readingBrief(_ facts: ReviewFacts) -> AIBrief {
        var brief = aiBrief
        brief.week = facts
        return brief
    }

    // MARK: - Outside the app

    /// One reading of the day, handed to everything that shows it elsewhere.
    ///
    /// Notifications, widgets and the Live Activity all answer the same question
    /// about the same day, so they are fed from one place at one moment. Two
    /// functions on two sets of triggers is how a Lock Screen ends up
    /// disagreeing with the notification that woke somebody up.
    private func syncAmbient() {
        refreshNotifications()
        publishSnapshot()
    }

    /// What the widgets and the Live Activity draw.
    ///
    /// Names and done flags, and nothing else about *today*. Everything a
    /// widget might be tempted to show later — subtitles, targets,
    /// verification — is deliberately not in the snapshot, so it cannot reach a
    /// Lock Screen by accident.
    ///
    /// The one thing that was added is the **record behind** today, because the
    /// large family is a grid of it. It travels already bucketed
    /// (`ProgressStore.heatTrail`), for the same reason everything else here is
    /// flattened: the extension deriving a level from a fraction would be a
    /// second opinion about a square somebody can see on both screens at once.
    private func publishSnapshot() {
        // Six months and a bit. The grid draws twenty-six weeks ending in the
        // week today falls in, which reaches at most 181 days back — the slack
        // is so a Sunday-first calendar and a Monday-first one both land inside
        // what was written.
        let trail = progress.heatTrail(days: 190)

        ForgePresence.shared.publish(
            ForgeSnapshot(
                day: progress.currentDay,
                dayStartHour: progress.dayStartHour,
                daysKept: progress.daysKept,
                isEarned: progress.isTodayEarned,
                // Today's, not the whole day's. A Lock Screen showing an
                // activity that is not being asked for today would be the one
                // surface in the app that disagrees with the app.
                activities: forgeVM.todayRituals.map {
                    ForgeSnapshot.Activity(
                        id: $0.id,
                        name: $0.label,
                        isDone: forgeVM.isDone($0.id)
                    )
                },
                // The one thing about the interface that is a taste, carried
                // across so the widgets are the same app. See `ForgeSnapshot`.
                accent: ForgeAppearance.shared.accent.rawValue,
                history: trail.marks,
                historyStart: trail.start
            )
        )
    }

    /// Hand the scheduler one reading of the day and let it decide.
    ///
    /// Built here rather than inside the scheduler so there is still exactly one
    /// answer in the app to "what has been done today" — the same reason nothing
    /// else keeps a copy of it either.
    private func refreshNotifications() {
        Task { [state = notificationState] in await notifications.refresh(for: state) }
    }

    /// One reading of the day, as the scheduler sees it.
    ///
    /// Extracted so the notification primer can be handed the same value: it
    /// draws the three sentences Forge would actually send, and the only way to
    /// guarantee that is for both to be built from one fact. See
    /// `NotificationPrimerView`, whose hand-written copies of those sentences
    /// had gone stale.
    private var notificationState: ForgeNotificationState {
        ForgeNotificationState(
            now: progress.now,
            currentDay: progress.currentDay,
            dayStartHour: progress.dayStartHour,
            wakeMinutes: notifications.wakeMinutes,
            completedToday: progress.today.completedCount,
            plannedToday: isPracticeLocked ? 0 : progress.today.plannedCount,
            isTodayEarned: progress.isTodayEarned,
            streak: progress.currentStreak,
            // The count, which is what the morning names. See
            // `ForgeNotificationPlan.standing` for why it is not the streak.
            daysKept: progress.daysKept,
            // The whole week, not just today: every notification Forge has is
            // about a time somebody put on a day, and six of those seven days
            // are not today.
            //
            // Nothing at all while new days are locked. A reminder to do
            // something the app will not let you keep is the app nagging for
            // money; the weekly review, which is about the record, still comes.
            schedule: isPracticeLocked ? [] : forgeVM.scheduledActivities,
            completedIDs: forgeVM.doneIDs,
            // Joined here rather than carried on the activity, so a sentence
            // about who somebody is reaches their own lock screen and nothing
            // else. See `ForgeNotificationState.identities`.
            identities: Dictionary(
                identities.active.map { ($0.id, $0.statement) },
                uniquingKeysWith: { first, _ in first }
            ),
            // Nil until there is a week worth reviewing. A weekly notification
            // arriving on somebody's second Sunday, about four days they were
            // present for, is the app talking about itself.
            reviewWeekday: progress.records.count >= 7 ? reviews.reviewWeekday : nil,
            // "Day 12 of 90" on the mornings of a running Arc, and its phase
            // changes and its last day. See `ForgeNotificationPlan.arcMornings`.
            arc: arcNotice
        )
    }

    /// Put the user in front of today's day and nothing else.
    ///
    /// Every notification Forge sends is about the same screen, so arriving from
    /// one should never need a tap to get there — including out of whatever
    /// sheet happened to be open when the app was last put down.
    private func landOnHome() {
        selectedTab = .forge
        showSettings = false
        forgeVM.showEditRituals = false
        forgeVM.honorRitualID = nil
    }

    /// The first run's own screens. The fourth is not here — it is the home
    /// screen itself, with the blade loose on it, so the first pull happens
    /// exactly where every pull after it will.
    @ViewBuilder
    private var firstRun: some View {
        if forgeVM.isFirstRunCovering {
            FirstRunView(vm: forgeVM, arcs: arcs)
                .transition(.opacity)
                .zIndex(2)
        } else if forgeVM.firstRunStage == .closing {
            FirstRunClosingView(
                remaining: max(0, forgeVM.totalActive - forgeVM.totalDone),
                firstActivity: forgeVM.scheduledActivities.first {
                    forgeVM.todayRitualIDs.contains($0.id)
                },
                openingMinute: notifications.wakeMinutes,
                notificationState: notificationState,
                // What they said they wanted to build, in the app's own order
                // so the sentence reads the same way the Shape does. Empty for
                // anybody who skipped the question, and the line falls back to
                // what it always said.
                focus: RitualCategory.dimensions.filter(forgeVM.focus.contains),
                // And of that, only what tomorrow has something for: the plan
                // has its own days now.
                tomorrow: forgeVM.focusTomorrow
            ) { finishFirstRun() }
                .transition(.opacity)
                .zIndex(2)
        }
    }

    // MARK: - What the app has to say, and when

    /// Decide what — if anything — is owed, and offer exactly one of it.
    ///
    /// **One at a time, in this order**, and the order is a claim about which
    /// matters most to the person holding the phone:
    ///
    /// 1. **Coming back**, which is about right now and is the only one that
    ///    can lose somebody entirely.
    /// 2. **The chapter**, which is six weeks of their life and worth
    ///    interrupting for.
    /// 3. **The week**, which is offered on Sunday evening and stays offerable
    ///    until it is dealt with, so nothing is lost by ignoring it once.
    ///
    /// Never during the first run, never over an earned day's summary, and never
    /// two at once. A user who dismisses all of them forever loses nothing: none
    /// of these writes anything, blocks anything, or is counted anywhere.
    @MainActor
    private func offerWhatIsDue() {
        guard forgeVM.hasCompletedFirstRun, !forgeVM.isFirstRunCovering else { return }
        guard !showReview, !showChapterClose, !isReturning else { return }

        if forgeVM.isReturning {
            isReturning = true
            ForgeTelemetry.send(.reentryShown)
            return
        }
        if isChapterDue {
            showChapterClose = true
            return
        }
        if isReviewDue { showReview = true }
    }

    /// Whether the open chapter has run its six weeks.
    ///
    /// Read on demand rather than scheduled: a chapter has no deadline and
    /// nothing happens *at* week six — the app simply starts offering to close
    /// it, and goes on offering until somebody does. See `Chapter.defaultWeeks`.
    private var isChapterDue: Bool {
        // Suspended while an Arc runs: one time-boxed stretch at a time, and
        // the Arc is the one with an end day. The chapter is untouched — its
        // window goes on covering the record — and is offered again once the
        // Arc is over. See `BladeTabView.chapter`.
        guard !isArcRunning else { return false }
        guard let chapter = chapters.current else { return false }
        return chapter.progress(
            dayStartHour: progress.dayStartHour, today: progress.currentDay
        ) >= 1
    }

    private var isReviewDue: Bool {
        let window = reviews.currentWindow(on: progress.currentDay)
        return reviews.isDue(
            on: progress.currentDay,
            hour: Calendar.current.component(.hour, from: progress.now),
            askedDays: progress.daysAsking(from: window.start, to: window.end),
            firstTracked: progress.records.first?.day
        )
    }

    // MARK: - The week

    @ViewBuilder
    private var weeklyReview: some View {
        let window = reviews.currentWindow(on: progress.currentDay)
        let facts = forgeVM.reviewFacts(
            from: window.start, to: window.end, identities: identities.active
        )
        return WeeklyReviewView(
            facts: facts,
            days: forgeVM.days(from: window.start, to: window.end),
            window: Self.span(window.start, window.end),
            existing: reviews.review(for: window.start),
            // The week before this one, if they wrote about it. Read here
            // rather than inside the view for the reason every other fact on
            // that screen is: the store is the root's, and a review screen that
            // could reach the store could also write to it.
            previous: reviews.answered.first { $0.weekStart < window.start },
            onAnswer: { happened, next in
                reviews.answer(
                    week: window.start, whatHappened: happened, whatNext: next,
                    at: progress.now
                )
                showReview = false
            },
            onDismiss: {
                reviews.dismiss(week: window.start, at: progress.now)
                showReview = false
            },
            // **Nil until AI is activated (§2r)**, and even then called only
            // from the review's "Read my week" button — never on opening, so
            // opening a review cannot create an anonymous identity.
            //
            // The history of why this was nil in 1.0:
            //
            // Every other AI path in Forge is behind a button. This one is not:
            // the review used to ask for a written reading from `.task`, the
            // moment the screen appeared, which made it the only request the app
            // could make without anybody pressing anything — and the widest one,
            // because a reading carries `ReviewFacts` on top of the brief.
            //
            // With the model off, handing the closure over anyway would still
            // "work": `RemoteForgeAI.reading` would fall to the arithmetic, come
            // back with `isModelWritten == false`, and the view would drop it on
            // the next line. That is a call that exists only to be thrown away,
            // and the honest wiring is not to make it. See
            // `RemoteForgeAI.isModelEnabled`, which is the one line to change.
            betterReading: remote.isConnected
                ? { [remote] in try? await remote.reading(brief: readingBrief(facts)) }
                : nil,
            // The Weekly Reading is AI: a subscription or a free week, not a
            // founder. Offered at all only where a model is reachable — see
            // `WeeklyReviewReading`.
            hasAI: store.access.hasAI,
            consentBriefs: AIDisclosureBriefs(brief: aiBrief, readingBrief: readingBrief(facts))
        )
    }

    /// "25 May – 31 May".
    private static func span(_ first: ForgeDay, _ last: ForgeDay) -> String {
        let format = DateFormatter()
        format.setLocalizedDateFormatFromTemplate("d MMM")
        return "\(format.string(from: first.startOfDay())) – \(format.string(from: last.startOfDay()))"
    }

    // MARK: - The chapter

    @ViewBuilder
    private var chapterClose: some View {
        if let chapter = chapters.current {
            let first = chapter.firstDay(dayStartHour: progress.dayStartHour)
            let last = chapter.lastDay(
                dayStartHour: progress.dayStartHour, today: progress.currentDay
            )
            ChapterCloseView(
                chapter: chapter,
                reading: bladeVM.reading(for: chapter),
                weeks: weekRows(from: first, to: last),
                // The identities the chapter was actually about, falling back to
                // whatever is active now — somebody who named none when it
                // opened should still be asked the question about the ones they
                // have since named.
                evidence: chapterIdentities(chapter).map {
                    ($0, bladeVM.evidence(for: $0, in: chapter))
                },
                reviews: reviews.answered(from: first, to: last),
                daysKept: progress.daysKept,
                onClose: { name, intention in
                    chapters.close(at: progress.now)
                    if !Chapter.trimmed(name, to: Chapter.nameLimit).isEmpty {
                        chapters.open(
                            name: name,
                            identityIDs: identities.active.map(\.id),
                            intention: intention,
                            at: progress.now
                        )
                    }
                    showChapterClose = false
                },
                onRetire: { identity in
                    identities.retire(identity.id, at: progress.now)
                },
                onLater: { showChapterClose = false }
            )
        }
    }

    private func chapterIdentities(_ chapter: Chapter) -> [Identity] {
        let named = chapter.identityIDs.compactMap(identities.identity)
        return named.isEmpty ? identities.active : named
    }

    /// The chapter's days, cut into weeks of seven from the day it opened.
    private func weekRows(from first: ForgeDay, to last: ForgeDay) -> [[ProgressStore.WeekDay]] {
        let span = max(0, last.days(since: first))
        return stride(from: 0, through: span, by: 7).map { start in
            (0..<7).compactMap { offset in
                let index = start + offset
                guard index <= span else { return nil }
                return progress.weekDay(first.adding(days: index))
            }
        }
    }

    // MARK: - Coming back

    @ViewBuilder
    private var returning: some View {
        if isReturning {
            ReturnView(
                daysKept: progress.daysKept,
                daysAway: forgeVM.daysAway,
                activity: forgeVM.returnActivity,
                onBegin: {
                    isReturning = false
                    landOnHome()
                },
                onDismiss: { isReturning = false }
            )
            .transition(.opacity)
            .zIndex(3)
        }
    }

    /// The first run is over, and the first chapter opens.
    ///
    /// Here rather than inside `finishFirstRun`, because `ForgeViewModel` knows
    /// nothing about chapters and should not start — this is the one place that
    /// holds both. Opening it automatically is the right default for exactly one
    /// moment in somebody's life: they have just named who they are becoming and
    /// done the first day of it, which is the only time the app can name a
    /// stretch of practice without presuming. It is theirs to rename, and
    /// `openFirst` never fires again for anybody who has ever had one.
    @MainActor
    private func finishFirstRun() {
        chapters.openFirst(identityIDs: identities.active.map(\.id))
        forgeVM.finishFirstRun()
    }

    /// One short sentence, and then the app back. It takes itself away.
    @ViewBuilder
    private var earnedSummary: some View {
        if let summary = forgeVM.summary {
            DaySummaryView(summary: summary) { finishEarnedSequence() }
                .transition(.opacity)
                .zIndex(1)
        }
    }

    @ViewBuilder
    private var unlockCelebration: some View {
        if let earned = swords.pendingUnlock {
            SwordUnlockOverlay(
                sword: earned,
                currentName: swords.equipped.name,
                daysKept: swords.daysKept,
                onEquip: {
                    ForgeHaptics.shared.tap()
                    swords.equip(earned.id)
                    dismissCelebration()
                },
                // Declining deliberately leaves the NEW badge on. The blade is
                // still unseen *in the collection*, and the badge is what walks
                // the user over to it — clearing it here would mean the newly
                // unlocked card state could never actually be reached.
                onKeep: { dismissCelebration() }
            )
            .transition(.opacity)
            .zIndex(1)
        }
    }

    private func dismissCelebration() {
        let celebrated = swords.pendingUnlock
        // The store marks the blade celebrated on the way out, so neither button
        // can leave it queued to play again tomorrow.
        swords.dismissCelebration()
        // The blade they just earned was the last beat of the first run. It
        // asks for nothing: never a rating in the first run, and nothing is
        // owed from it (`RatingPrompt`).
        if forgeVM.firstRunStage == .pull {
            forgeVM.firstRunStage = .closing
        } else if let celebrated {
            offerRating(after: celebrated)
        }
    }

    // MARK: - The rating

    /// Whether anything that is the day rather than a pause in it is on screen.
    private var isDayMomentOnScreen: Bool {
        forgeVM.isFirstRunCovering
            || forgeVM.summary != nil
            || swords.pendingUnlock != nil
            || forgeVM.pull > 0.01
            || forgeVM.honorRitualID != nil
            || isReturning
            || showReview
            || showChapterClose
    }

    /// A blade's celebration has closed. Ask for a rating if `RatingPrompt`
    /// says this is one of its two moments.
    ///
    /// After the celebration's own fade, so the two are never on screen
    /// together, and the moment is read again then — a pull started in that
    /// half-second, or a sheet that came up, lets this one pass.
    private func offerRating(after blade: Sword) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            let moment = RatingPrompt.Moment(
                isFirstRun: !forgeVM.hasCompletedFirstRun,
                isDayInProgress: isDayMomentOnScreen
            )
            guard ratings.claim(closing: blade, now: progress.now, moment: moment) != nil else { return }
            requestReview()
        }
    }

    // MARK: - The Arc

    /// Whether an Arc is running today — the one thing that suspends the
    /// chapter.
    private var isArcRunning: Bool { arcs.currentReading?.isRunning == true }

    /// What the morning notification is told about the running Arc. Nil when
    /// there is none, and nil while new days are locked: an Arc that cannot be
    /// kept is not counted at somebody.
    private var arcNotice: ArcNotice? {
        guard !isPracticeLocked, let current = arcs.current, current.isApplied,
              let reading = arcs.currentReading, reading.isRunning
        else { return nil }
        let program = current.program
        return ArcNotice(
            name: program.name,
            startDay: current.startDay,
            length: program.length,
            phases: program.phases.dropFirst().map { ArcNotice.Phase(name: $0.name, firstDay: $0.firstDay) }
        )
    }

    // MARK: - Forge Pro

    /// New days are locked: lapsed, or never subscribed, after onboarding.
    /// Read for the notifications, which stop talking about the day.
    private var isPracticeLocked: Bool {
        forgeVM.hasCompletedFirstRun && PremiumGate.isLocked(.dayControls, for: store.access)
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}

// MARK: - The four tabs, and Settings

extension ContentView {

    /// Each tab's content, lifted out of `body`.
    ///
    /// Mechanical rather than architectural: four `Tab` closures inline took the
    /// type checker past its budget for the whole file, and the same expression
    /// split across four properties compiles in a fraction of the time. The
    /// arguments are unchanged.
    fileprivate var forgeTab: some View {
        ForgeTabView(
            vm: forgeVM,
            swords: swords,
            challenges: challenges,
            arcs: arcs,
            brief: aiBrief,
            ai: ai,
            onArcs: { selectedTab = .arcs }
        )
    }

    fileprivate var arcsTab: some View {
        ArcsTabView(arcs: arcs, forge: forgeVM, swords: swords)
    }

    fileprivate var bladeTab: some View {
        BladeTabView(
            vm: bladeVM, swords: swords,
            identities: identities, chapters: chapters,
            arcs: arcs,
            onSettings: { showSettings = true }
        )
    }

    fileprivate var becomingTab: some View {
        BecomingTabView(
            forge: forgeVM, identities: identities, reviews: reviews,
            onSettings: { showSettings = true }
        )
    }

    fileprivate var settingsTab: some View {
        SettingsTabView(
            vm: settingsVM,
            progress: progress,
            forge: forgeVM,
            notifications: notifications,
            reviews: reviews,
            store: store,
            identities: identities,
            // The same two values the AI is actually handed, from the same
            // builder. A screen that promises to show what is sent has to be
            // reading the thing that is sent.
            aiBrief: aiBrief,
            aiReadingBrief: readingBrief(
                forgeVM.reviewFacts(
                    from: reviews.currentWindow(on: progress.currentDay).start,
                    to: reviews.currentWindow(on: progress.currentDay).end,
                    identities: identities.active
                )
            ),
            isAIConnected: remote.isConnected,
            aiConsent: aiConsent,
            notificationState: notificationState,
            arcs: arcs,
            onDone: { showSettings = false }
        )
    }
}

// MARK: - Forge Pro, at the root

/// The store, the trial reminder and the accent gate, applied as one.
///
/// A modifier for the reason `MomentsModifier` is one: the root's body is at
/// the edge of what the type checker will do in reasonable time.
private struct ForgeProModifier: ViewModifier {
    let store: ForgeStore
    let consent: AIConsentStore
    let notifications: ForgeNotifications
    /// The accent was put back; the widgets have to hear about it.
    let onAccentReset: () -> Void

    /// When the trial reminder should go off, or nil — re-derived from
    /// StoreKit every time, so a cancellation or a conversion takes it away.
    private var trialReminder: Date? {
        TrialReminder.fireDate(
            access: store.access,
            willAutoRenew: store.willAutoRenew,
            isWanted: TrialReminder.isWanted(),
            now: .now
        )
    }

    /// What the reminder depends on, including whether iOS lets it be heard,
    /// so permission given a moment after a free week starts schedules it —
    /// and whether StoreKit has answered yet. Without that, a relaunch after a
    /// trial ended read "no reminder" both before the answer (when nothing may
    /// be decided) and after it (when the reminder must go), the task never ran
    /// a second time, and a reminder for a trial that was over stayed pending.
    private var trialReminderState: String {
        TrialReminder.syncKey(
            hasAnswered: store.hasReadEntitlement,
            fireDate: trialReminder,
            authorization: notifications.authorization.rawValue
        )
    }

    func body(content: Content) -> some View {
        content
            // Accents 2–8 go with new days. Once StoreKit has actually
            // answered — never on the `.unknown` placeholder it starts with —
            // a lapsed install is put back on the free accent.
            .task(id: store.access) {
                guard store.hasReadEntitlement else { return }
                let appearance = ForgeAppearance.shared
                let wearable = PremiumGate.wearable(appearance.accent, for: store.access)
                guard wearable != appearance.accent else { return }
                appearance.accent = wearable
                onAccentReset()
            }
            // "Day 5: we remind you." Only once StoreKit has answered: until
            // then the trial is not known, and a reminder already pending must
            // not be taken away on a placeholder.
            .task(id: trialReminderState) {
                guard store.hasReadEntitlement else { return }
                await notifications.syncTrialReminder(at: trialReminder)
            }
            // One entitlement for every screen, including the sheets that open
            // the paywall from inside themselves. Outermost, so it reaches all
            // of them.
            .environment(store)
            // AI consent, for the consent sheet and Settings, the same way.
            .environment(consent)
    }
}

// MARK: - The three moments

/// The return screen, the chapter close and the weekly review, presented as one.
///
/// Everything about *when* each is due lives in `ContentView.offerWhatIsDue()`;
/// this only carries them onto the screen. It exists as a modifier rather than
/// six more lines on the root's body because the root's body is already at the
/// edge of what the type checker will do in reasonable time — and because these
/// three genuinely are one thing: at most one of them is ever on screen, and the
/// rule that says so is a single function.
private struct MomentsModifier<Returning: View, Review: View, Close: View>: ViewModifier {
    @Binding var isReturning: Bool
    @Binding var showReview: Bool
    @Binding var showChapterClose: Bool
    let currentDay: ForgeDay
    let scenePhase: ScenePhase
    let offer: () -> Void
    @ViewBuilder let returning: () -> Returning
    @ViewBuilder let review: () -> Review
    @ViewBuilder let chapterClose: () -> Close

    func body(content: Content) -> some View {
        content
            // Coming back goes above everything else the app might have wanted
            // to say. Somebody returning after three weeks must not meet a
            // review of a week they were not here for, or a chapter that ran
            // out while they were away — see `ReEntry`.
            .overlay { returning() }
            // Sheets rather than overlays: both are genuinely dismissible and
            // both have a keyboard in them.
            .sheet(isPresented: $showReview) { review() }
            .sheet(isPresented: $showChapterClose) { chapterClose() }
            // Checked when the app comes forward and when the day turns over,
            // which between them are every moment any of these can become due
            // without the user doing anything. Never on a timer, never mid-day,
            // and never while one is already up.
            .task { offer() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                offer()
            }
            .onChange(of: currentDay) { _, _ in offer() }
    }
}

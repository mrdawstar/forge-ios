import StoreKit
import SwiftUI

struct SettingsTabView: View {
    @Bindable var vm: SettingsViewModel
    @Bindable var progress: ProgressStore
    var forge: ForgeViewModel
    @Bindable var notifications: ForgeNotifications
    /// Which day the week is reviewed on. Read and written here and nowhere
    /// else in Settings — see `reviewSection`.
    var reviews: ReviewStore
    @Bindable var store: ForgeStore
    /// Only the DEBUG first-run replay uses this — the sequence writes real
    /// identities, so putting the app back to a fresh install has to clear them
    /// or the replay starts with three sentences already answered.
    var identities: IdentityStore

    /// What would be sent to a model, taken at the moment this screen is drawn.
    ///
    /// Handed in rather than assembled here, and that is the whole guarantee
    /// the disclosure screen makes: it shows *the same value the AI is given*,
    /// built by the same line of `ContentView`, not a second reconstruction of
    /// it that could quietly fall out of step. See `AIBrief`.
    var aiBrief: AIBrief
    var aiReadingBrief: AIBrief
    var isAIConnected: Bool
    /// Whether Forge's AI has been allowed — shown, and revocable, under
    /// Planning. See `AIConsentStore`.
    var aiConsent: AIConsentStore
    /// The scheduler's own reading of the day, handed in for the same reason
    /// `aiBrief` is: the primer draws the sentences Forge would actually send,
    /// and it can only do that from the value the scheduler is given.
    var notificationState: ForgeNotificationState
    /// Only the DEBUG section reads this: starting any Arc as if it had begun
    /// days ago, so every phase and the ending can be walked.
    var arcs: ArcStore
    /// Settings is a sheet since Arcs took its tab; this closes it.
    var onDone: (() -> Void)? = nil

    /// The permission explanation, raised the first time somebody turns the
    /// switch on here without iOS ever having been asked.
    @State private var showPrimer = false
    /// The Apple Health primer, from its one door in Settings.
    @State private var showHealthPrimer = false
    @State private var paywallDoor: ForgeTelemetry.PaywallDoor?
    /// What Restore found, said under the section. Nil until somebody taps it.
    @State private var restoreNote: String?

    #if DEBUG
    @State private var pending: [String] = []
    @State private var debugArc: ArcID = .winter
    @State private var debugArcDaysAgo = 14
    #endif

    var body: some View {
        NavigationStack {
            List {
                proSection

                restDaySection

                appearanceSection

                reviewSection

                notificationSection

                if ForgeFeatures.current.health {
                    healthSection
                }

                ForEach(vm.groups) { group in
                    Section {
                        ForEach(group.rows) { row in
                            settingRow(row)
                        }
                    } header: {
                        Text(group.title)
                    } footer: {
                        if !group.hint.isEmpty {
                            Text(group.hint)
                        }
                    }
                }

                planningSection

                privacySection

                legalSection

                #if DEBUG
                debugSection
                #endif

                Section {
                    EmptyView()
                } footer: {
                    // Unconditional again, and it is the plainest true sentence
                    // the app can end on: 1.0 has no account, so there is
                    // nowhere else a copy could be. It briefly had two
                    // answers — one for a signed-in account and one for
                    // everybody else — and the second is now the only one.
                    //
                    // The version is read out of the bundle rather than typed.
                    // It said "Forge 2.1" against a marketing version of 1.0 for
                    // long enough that nobody noticed, which is what a
                    // hand-written version string always eventually does.
                    Text("\(Self.versionLine) · Your practice stays on your phone.")
                }
            }
            .navigationTitle("Settings")
            .scrollIndicators(.hidden)
            .toolbar {
                if let onDone {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onDone)
                    }
                }
            }
            .sheet(isPresented: $showPrimer) { primer }
            .sheet(isPresented: $showHealthPrimer) {
                HealthPrimerView(
                    activities: { forge.healthActivityNames(for: $0) },
                    onAnswer: { allow in await forge.answerHealthPrimer(allow: allow) }
                )
            }
            .paywall($paywallDoor)
        }
    }

    private static var versionLine: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "Forge \(version ?? "1.0")"
    }

    // MARK: - Forge Pro

    /// What somebody has, and the things they may need to do about it.
    ///
    /// Near the top because it is the one row people come to Settings
    /// specifically to find — to check they have what they paid for, to bring
    /// it back on a new phone, or to cancel. Restore and Manage are required
    /// wherever a subscription is sold, and they are here rather than only on
    /// the paywall because somebody who has already paid never sees that.
    ///
    /// **Lifetime is sold here and nowhere else** (DIRECTION_1_1 §1). Not on
    /// the paywall, where it would sit beside the free week as the thing a
    /// first-time visitor is invited to weigh; here it is for somebody who
    /// already knows Forge and wants never to be asked again.
    private var proSection: some View {
        Section {
            LabeledContent("Status") {
                Text(PremiumCopy.status(store.access) { $0.formatted(date: .abbreviated, time: .omitted) })
            }

            if !store.access.hasAI {
                Button("See Forge Pro") { paywallDoor = .settings }
            }

            Button {
                ForgeTelemetry.send(.restoreTapped)
                restoreNote = nil
                Task {
                    let restored = await store.restore()
                    restoreNote = restored ? "Forge Pro is on." : store.failure
                }
            } label: {
                HStack {
                    Text("Restore Purchases")
                    if store.isRestoring {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(store.isRestoring)

            if store.access.hasSubscription {
                Button("Manage Subscription") {
                    Task { await manageSubscriptions() }
                }
            }

            if store.entitlement != .lifetime, let lifetime = store.lifetime {
                Button {
                    buyLifetime(lifetime)
                } label: {
                    LabeledContent {
                        if store.pending == lifetime.id {
                            ProgressView()
                        } else {
                            Text(lifetime.displayPrice)
                        }
                    } label: {
                        Text("Lifetime")
                    }
                }
                .disabled(store.pending != nil || store.isRestoring)
                .accessibilityLabel(Text("Lifetime, \(PremiumCopy.lifetimeLine(price: lifetime.displayPrice))"))
            }
        } header: {
            Text("Forge Pro")
        } footer: {
            Text(restoreNote ?? proFooter)
        }
    }

    private var proFooter: String {
        let lifetime = store.lifetime.map { " Lifetime: \(PremiumCopy.lifetimeLine(price: $0.displayPrice))" } ?? ""
        switch store.access {
        case .unknown:
            return "Asking the App Store."
        case .pro(.lifetime):
            return "Yours for good. It never renews and is never charged again."
        case .pro, .trial:
            return "Renews automatically. Cancel any time in Manage Subscription; your record stays exactly as it is either way." + (store.lifetime != nil ? " Buying Lifetime does not cancel a subscription; cancel it there." : "")
        case .founder:
            return "You ran Forge before 1.1, so everything but Forge's AI stays free for good. Forge Pro adds the AI." + lifetime
        case .lapsed, .none:
            return "New days need Forge Pro. Your record stays readable whatever you decide." + lifetime
        }
    }

    /// Lifetime, bought from its row. StoreKit's own sheet confirms the price.
    private func buyLifetime(_ product: Product) {
        restoreNote = nil
        Task {
            if case .bought = await store.purchase(product) {
                ForgeTelemetry.send(.purchaseCompleted(.lifetime))
                ForgeHaptics.shared.ritualVerified()
            }
        }
    }

    /// Apple's own sheet, in this window. Cancelling, switching plans and
    /// refunds all happen there — Forge never handles any of them itself.
    @MainActor
    private func manageSubscriptions() async {
        let scene = UIApplication.shared.connectedScenes
            .first { $0.activationState == .foregroundActive } as? UIWindowScene
        guard let scene else { return }
        try? await AppStore.showManageSubscriptions(in: scene)
        await store.refreshEntitlement()
    }

    // MARK: - Rest days

    /// The one setting nobody could work out from its own label.
    ///
    /// It had a seven-circle picker and a single line — "Rest days are not
    /// misses. Nothing counts them and nothing is lost." — which answers a
    /// question somebody can only ask *after* they already know what a rest day
    /// is. Read cold, the control says "pick some days" and the footer says
    /// "nothing happens", and the obvious conclusion is that this does nothing
    /// at all.
    ///
    /// So the footer now says the three things in order: **what it is for**
    /// (a day you have decided in advance not to keep), **what it changes** (the
    /// chain steps over it instead of breaking), and **what it does not change**
    /// (the list is still there, and finishing it still earns the day). The
    /// summary line above it reads the picker back in words, so the setting can
    /// be checked without counting circles.
    private var restDaySection: some View {
        Section {
            DayPicker(days: $vm.restDays,
                      onDescription: "Rest day",
                      offDescription: "Ritual day")
                .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))

            Label(vm.restDaySummary, systemImage: ForgeIcons.symbol(for: "moon"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Rest Days")
        } footer: {
            Text("A rest day is a day you have decided in advance not to keep — a Sunday, a training rest, the day you work late. Your streak steps over it instead of breaking on it.\n\nEverything else is unchanged: today's list is still there, and if you do finish it the day is earned like any other. A rest day can only ever help.")
        }
    }

    // MARK: - Appearance

    /// One row, and it opens the whole of it.
    ///
    /// The current colour is shown as a disc on the row rather than only as a
    /// name, because "Ember" means nothing to somebody who has not opened the
    /// screen yet — and because a settings row that shows its own value is the
    /// difference between a list of doors and a list of answers.
    private var appearanceSection: some View {
        Section {
            NavigationLink {
                AppearanceView()
            } label: {
                LabeledContent {
                    HStack(spacing: 8) {
                        Text(ForgeAppearance.shared.accent.label)
                        Circle()
                            .fill(ForgeTheme.accent)
                            .frame(width: 16, height: 16)
                            .overlay { Circle().strokeBorder(.white.opacity(0.14), lineWidth: 0.5) }
                    }
                } label: {
                    Label("Accent", systemImage: "paintpalette")
                }
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("The colour Forge uses for anything you have chosen, done or own. The room, the stone and the blade are the scene and never change.")
        }
    }

    // MARK: - The week

    /// Which day the review is offered on.
    ///
    /// One row, and only the day is configurable. The hour is not — evening is
    /// the only time a review of a day that is still going is not a review of a
    /// guess, and a second picker would be two decisions in front of somebody
    /// who wanted one. See `ReviewStore`.
    ///
    /// There is deliberately **no switch to turn it off**. The review is already
    /// declinable every single week, at no cost and with nothing recorded, which
    /// is a better off switch than one that has to be found in Settings — and a
    /// toggle here would make the thing look like a subscription to something.
    @ViewBuilder
    private var reviewSection: some View {
        Section {
            Picker("Offered on", selection: Binding(
                get: { reviews.reviewWeekday },
                set: { reviews.reviewWeekday = $0 }
            )) {
                ForEach(1...7, id: \.self) { weekday in
                    Text(Self.weekdayName(weekday)).tag(weekday)
                }
            }
        } header: {
            Text("The Week")
        } footer: {
            Text("Ninety seconds on the week that just ended: what the record says, and two questions. Skipping one costs nothing and nothing counts them.")
        }
    }

    private static func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        guard symbols.indices.contains(weekday - 1) else { return "" }
        return symbols[weekday - 1]
    }

    // MARK: - Notifications

    /// One switch and one time, and there is deliberately nothing else to set.
    ///
    /// Once the system has been told no the section stays exactly where it was,
    /// reading off, with the door to iOS Settings next to it. The wording is a
    /// statement of where the switch now lives rather than an argument for
    /// flipping it — Forge does not ask twice, but it should not pretend the
    /// setting stopped existing either.
    @ViewBuilder
    private var notificationSection: some View {
        Section {
            Toggle("Notifications", isOn: Binding(
                // Blocked is off, whatever was last chosen in here. A switch
                // reading on while nothing can arrive is the one state worse
                // than no switch at all.
                get: { notifications.isEnabled && !notifications.isBlocked },
                set: { on in
                    // Turning it on before iOS has ever been asked explains
                    // itself first. This is the other door into the permission
                    // prompt — the first run's is the closing beat — and both
                    // go through the same screen, so nobody meets the system
                    // dialog without having seen what it is for.
                    guard on, notifications.authorization == .notDetermined else {
                        notifications.isEnabled = on
                        return
                    }
                    showPrimer = true
                }
            ))
            .disabled(notifications.isBlocked)

            if notifications.isBlocked {
                if let settings = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open Settings", destination: settings)
                }
            } else if notifications.isEnabled {
                DatePicker(
                    "Start of day",
                    selection: $notifications.wakeTime,
                    displayedComponents: .hourAndMinute
                )
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text(
                notifications.isBlocked
                    ? "Notifications are turned off for Forge in iOS Settings."
                    // Says what actually arrives now that the schedule drives
                    // it, and what the one time setting is still for: a day of
                    // activities with no hour on them opens here.
                    : "Your day opens on its first activity, and each activity speaks at its own time. This is when a day with no set hours begins."
            )
        }
    }

    // MARK: - Apple Health

    /// What Forge reads from Health, and where that is changed.
    ///
    /// HealthKit never tells an app whether reading was allowed, so this does
    /// not claim to know: after Continue it says what Forge asks to read and
    /// that the Health app is where the answer lives. After "Keep it Your
    /// Word" it says so, and it is the one door back: the primer, opened by
    /// the person, never by Forge.
    @ViewBuilder
    private var healthSection: some View {
        Section {
            switch forge.healthLedger.decision {
            case .undecided:
                LabeledContent("Apple Health", value: "Not asked yet")
            case .asked:
                LabeledContent("Apple Health", value: "Read only")
                if let health = URL(string: "x-apple-health://") {
                    Link("Open the Health App", destination: health)
                }
            case .declined:
                LabeledContent("Apple Health", value: "Your Word")
                Button("Let Apple Health Check Activities") { showHealthPrimer = true }
            }
        } header: {
            Text("Apple Health")
        } footer: {
            switch forge.healthLedger.decision {
            case .undecided:
                Text("Forge asks the first time an activity Apple Health can check enters your day: steps, workouts, sleep or mindful minutes.")
            case .asked:
                Text("Forge reads steps, workouts, sleep and mindful minutes on this iPhone, and never writes to Health. To change what it can read, open the Health app, tap your picture, then Apps, then Forge.")
            case .declined:
                Text("You kept these activities Your Word. Apple Health is not asked unless you choose it here.")
            }
        }
    }

    /// The permission explanation.
    ///
    /// Presented from the screen rather than from the section it belongs to: a
    /// `Section` is a list's way of grouping rows, not a view that can put
    /// anything on screen, and a `sheet` attached to one silently never opens.
    @ViewBuilder
    private var primer: some View {
        NotificationPrimerView(
            firstActivity: forge.scheduledActivities.first {
                forge.todayRitualIDs.contains($0.id)
            },
            openingMinute: notifications.wakeMinutes,
            state: notificationState,
            onDecision: { granted in notifications.isEnabled = granted }
        )
    }

    // MARK: - Planning

    /// One row, and it is not a toggle.
    ///
    /// There is deliberately nothing to turn off: no request leaves this phone
    /// unless somebody presses a button that says what it does. A switch would
    /// imply background traffic that does not exist, and would be the app
    /// confessing to something it does not do.
    ///
    /// What the row does instead is answer the question a switch is usually
    /// standing in for: *what would ever be sent about me*. See
    /// `AIDisclosureView`, which renders the value rather than describing it.
    ///
    /// The heading used to read "AI", and the whole section was written as
    /// though the model were the feature. It is not: Plan works entirely on
    /// this phone, and a model — if one is ever connected — only widens the
    /// sentences it can understand. The heading now names what somebody
    /// actually uses, and the footer describes what actually happens.
    private var planningSection: some View {
        Section {
            NavigationLink {
                AIDisclosureView(
                    brief: aiBrief, readingBrief: aiReadingBrief,
                    isConnected: isAIConnected,
                    consent: aiConsent
                )
            } label: {
                Label(
                    isAIConnected ? "What is sent to the model" : "What Plan can see",
                    systemImage: "doc.text.magnifyingglass"
                )
            }

            // The consent, revocable in one tap. Shown whenever there is a
            // choice to show: always once the model is reachable, and in this
            // build only if an answer was somehow already recorded.
            if isAIConnected || aiConsent.hasDecided {
                LabeledContent("Forge's AI") {
                    Text(AIDisclosureView.label(for: aiConsent.state))
                }
                if aiConsent.isAllowed {
                    Button("Turn off Forge's AI", role: .destructive) { aiConsent.revoke() }
                }
            }
        } header: {
            Text("Planning")
        } footer: {
            Text(
                isAIConnected
                    ? "Plan opens from the week, under the More button. It works out its moves on this phone; when you type a request in your own words it is sent by Forge's own server, never by this app, and only at the moment you ask."
                    : "Plan opens from the week, under the More button. It reads your own week, your history and the six parts of your Shape, and works every move out on this phone. Forge's AI is not switched on in this version, so nothing is sent."
            )
        }
    }

    /// The one thing Forge sends about itself, and the switch for it.
    ///
    /// On by default and said plainly underneath. What the sentence promises is
    /// held by `ForgeTelemetry.Event`, which has no case that could carry
    /// anything somebody wrote or did by name — see `FORGE_CONTEXT.md` §2p.
    private var privacySection: some View {
        Section {
            Toggle("Share anonymous usage", isOn: $vm.shareUsage)
        } header: {
            Text("Privacy")
        } footer: {
            Text("Sends anonymous counts of which features are used, with basic device details, but never your activities, your words or your health data.")
        }
    }

    /// The documents, and nothing else.
    ///
    /// Restore Purchases and Manage Subscription left this section in 1.0,
    /// when nothing was sold, and came back with Forge Pro — at the top of the
    /// screen, in `proSection`, rather than here.
    ///
    /// The links stay because they are required whether or not anything is sold,
    /// and they remain absent rather than broken if a URL is ever unset.
    ///
    /// **Support leads.** The other two are documents somebody reads once at
    /// most; this is the row a person opens when the app has done something
    /// wrong, and it is the only one on the screen that reaches a human.
    @ViewBuilder
    private var legalSection: some View {
        if ForgeLinks.support != nil || ForgeLinks.privacy != nil || ForgeLinks.terms != nil {
            Section {
                if let support = ForgeLinks.support {
                    Link("Support", destination: support)
                }
                if let privacy = ForgeLinks.privacy {
                    Link("Privacy Policy", destination: privacy)
                }
                if let terms = ForgeLinks.terms {
                    Link("Terms of Use", destination: terms)
                }
            } header: {
                Text("About")
            }
        }
    }
    // MARK: - Debug

    #if DEBUG
    /// The week as it stands, or the shipped default day for an empty one.
    private var seedWeek: [String] {
        forge.activeRitualIDs.isEmpty ? Ritual.defaultActive : forge.activeRitualIDs
    }

    /// Never shipped. Streak and rollover logic cannot be exercised by waiting
    /// a month for it, so the date and the history are both drivable from here.
    private var debugSection: some View {
        Section {
            Stepper(value: $progress.debugDayOffset, in: -400...400) {
                LabeledContent("Day offset") {
                    Text("\(progress.debugDayOffset > 0 ? "+" : "")\(progress.debugDayOffset)")
                        .monospacedDigit()
                }
            }

            // Apple Health: forget the primer's answer and the offers, so the
            // primer and "Let Apple Health check this" can be walked again.
            // iOS keeps its own answer; reset that in the Health app.
            Button("Reset Apple Health Answer") { forge.resetHealth() }

            Stepper(value: $progress.dayStartHour, in: 0...12) {
                LabeledContent("Day starts at") {
                    Text("\(progress.dayStartHour):00")
                        .monospacedDigit()
                }
            }

            LabeledContent("Today") {
                // Built by hand rather than interpolated: a year run through
                // the default formatter comes out grouped, as "2,026".
                Text(verbatim: String(
                    format: "%04d-%02d-%02d",
                    progress.currentDay.year,
                    progress.currentDay.month,
                    progress.currentDay.day
                ))
                .monospacedDigit()
            }

            // Seeded from the week somebody keeps now, so the six on Becoming
            // read the seeded days (a record of ids nobody keeps any more
            // feeds no dimension). A year reaches all nine blades; two years
            // reach the temper marks past Enduring.
            Button("Seed 12 Weeks of History") {
                progress.seedSyntheticHistory(planned: seedWeek)
            }
            Button("Seed a Year of History") {
                progress.seedSyntheticHistory(days: 365, planned: seedWeek)
            }
            Button("Seed Two Years of History") {
                progress.seedSyntheticHistory(days: 730, planned: seedWeek)
            }

            // Every one of the first week's five tips, eligible again now, and
            // TipKit's whole datastore cleared on the next launch.
            Button("Reset Tips") {
                Task { await ForgeTips.resetAll() }
            }

            Button("Clear History", role: .destructive) {
                progress.clearHistory()
            }

            Button("Run First Launch Again", role: .destructive) {
                // The Arcs go with the run that started them: a replay is a
                // fresh install, and a fresh install is in no Arc.
                arcs.debugClear()
                forge.resetFirstRun(identities: identities)
            }

            // Every state somebody can be in, without a Sandbox account or a
            // 1.0 install to hand. StoreKit hands the answer back.
            Picker("Forge Pro", selection: Binding(
                get: { store.debugAccess },
                set: { store.debugAccess = $0 }
            )) {
                Text("StoreKit").tag(ForgeStore.SimulatedAccess?.none)
                ForEach(ForgeStore.SimulatedAccess.allCases) { simulated in
                    Text(simulated.rawValue.capitalized).tag(Optional(simulated))
                }
            }

            Button("Reset Exit Offer") { ExitOffer().reset() }
            Button("Reset Rating Prompts") { RatingPrompt().reset() }

            // Any Arc, as if joined N days ago: every phase change, a trial
            // week and the ending can be reached without living through them.
            // Past the Arc's length it lands finished, mark and all.
            Picker("Arc", selection: $debugArc) {
                ForEach(ArcID.allCases) { arc in
                    Text(ArcCatalog.program(arc).name).tag(arc)
                }
            }
            Stepper(value: $debugArcDaysAgo, in: 0...120) {
                LabeledContent("Started days ago") {
                    Text("\(debugArcDaysAgo)").monospacedDigit()
                }
            }
            Button("Start Arc \(debugArcDaysAgo) Days Ago") {
                arcs.debugStart(debugArc, daysAgo: debugArcDaysAgo)
            }
            Button("Clear Arcs", role: .destructive) { arcs.debugClear() }

            // The consent can be walked, but nothing can be sent: the model is
            // switched off in this build (§2r) whatever this says.
            LabeledContent("AI consent") {
                Text(AIDisclosureView.label(for: aiConsent.state))
            }
            Button("Reset AI Consent") { aiConsent.reset() }

            LabeledContent("Founder record") {
                Text(Founder.isRecorded(in: ForgeShared.defaults) ? "yes" : "no")
            }

            // Not onboarding: that door has no way out but a purchase, and
            // the first run is where it is walked — Run First Launch Again.
            Menu("Open Paywall As…") {
                ForEach(ForgeTelemetry.PaywallDoor.allCases.filter { $0 != .onboarding }) { door in
                    Button(door.rawValue) { paywallDoor = door }
                }
            }

            // Read back out of the system rather than reported by the app, so
            // this can actually catch a cancel that did not happen.
            Button("Read Pending Notifications") {
                Task { pending = await notifications.pendingDescriptions() }
            }

            LabeledContent("Pending") {
                Text(pending.isEmpty ? "none" : pending.joined(separator: "\n"))
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            }
        } header: {
            Text("Debug")
        } footer: {
            Text("Debug builds only. Seeding replaces every day except today. Running first launch again clears history and restores the default day.")
        }
    }
    #endif

    // MARK: - Rows

    @ViewBuilder
    private func settingRow(_ row: SettingsViewModel.SettingsRow) -> some View {
        switch row.kind {
        case .toggle(let isOn):
            Toggle(isOn: Binding(
                get: { isOn },
                set: { _ in vm.toggleSetting(row.key) }
            )) {
                rowLabel(row)
            }

        case .value(let val):
            LabeledContent {
                Text(val)
            } label: {
                rowLabel(row)
            }

        case .chevron:
            Button {
                // Destinations are wired up by the account layer.
            } label: {
                HStack {
                    rowLabel(row)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func rowLabel(_ row: SettingsViewModel.SettingsRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.key)
                .foregroundStyle(row.isDestructive ? ForgeTheme.destructive : .primary)
            if !row.sub.isEmpty {
                Text(row.sub)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

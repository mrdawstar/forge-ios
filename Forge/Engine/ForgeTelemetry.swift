import Foundation
import TelemetryDeck

/// Anonymous product telemetry, and the only file in Forge that knows
/// TelemetryDeck exists.
///
/// # What it is for
///
/// Which beats of the first run people leave on, whether the pull is found,
/// whether a re-entry brings anybody back. Questions about the *app*, answered
/// in counts. Nothing here can answer a question about a *person*.
///
/// # What it may carry
///
/// **An event name and a handful of closed values.** Every parameter is drawn
/// from an enum in this file or from `ForgeTelemetry.daysSinceInstall` — never
/// from a `String` the user typed or picked. There is no case that takes an
/// activity's name, an identity statement, a chapter's name, a review's words,
/// a quote, a time of day somebody chose, or anything read from HealthKit, and
/// `Event` is shaped so that adding one would mean writing it in here, where
/// it will be read. See `FORGE_CONTEXT.md` §2p.
///
/// # When it is silent
///
/// - The user turned **Share anonymous usage** off in Settings. On by default.
/// - The process is a test run. `send` returns before anything is built, so no
///   test can reach the network through here.
///
/// A signal that is dropped is dropped: nothing is queued for later, so turning
/// the switch back on does not send what happened while it was off.
///
/// # One seam
///
/// Callers never import the SDK and never name a signal as a string. Swapping
/// TelemetryDeck for anything else — or for nothing — is this file.
enum ForgeTelemetry {

    /// The TelemetryDeck app this build reports to.
    static let appID = "5E5C19F4-B785-4F97-A6AE-68E6FDFE47C5"

    /// The ingest host the SDK posts to. Named here so the network allowlist
    /// has exactly one entry and it is this one — see `ForgeNetwork`.
    static let host = "nom.telemetrydeck.com"

    /// Where the Settings switch is kept. The App Group suite, like every other
    /// preference, so there is one answer for the whole install.
    static let sharingKey = "forge.shareUsage.v1"

    // MARK: - The events

    /// Every signal Forge can send. **Only these.**
    enum Event: Equatable, Sendable {
        case appFirstOpen
        /// A first-run step came on screen. Was `onboarding_beat_view{beat}`
        /// until 1.1 rebuilt the beats (§17.1); the old name reads the 1.0
        /// sequence, which no longer exists.
        case onboardingStep(Step)
        case onboardingFocusChosen(count: Int)
        /// The seven questions were answered — in the first run, or from the
        /// Becoming tab. **No parameters**: never an answer, never a baseline.
        case assessmentCompleted
        case onboardingCompleted
        case firstPullCompleted
        case activityCompleted(VerificationMethod)
        case dayEarned
        case pullAbandoned
        case challengeAccepted
        case challengeCompleted
        case activityAdded(ActivitySource)
        case notificationOpened(ForgeNotification)
        case weeklyReviewCompleted
        case reentryShown
        case reentryRecovered
        case chapterClosed
        // The paywall's. `paywallView` when it appears, `paywallDismissed`
        // when it is closed without buying, both carrying the door it was
        // opened from. A trial and a sale are separate events so a trial is
        // never counted as revenue.
        case paywallView(PaywallDoor)
        case paywallDismissed(PaywallDoor)
        case trialStarted(PremiumProduct)
        case purchaseCompleted(PremiumProduct)
        case restoreTapped
        /// A model wrote a Weekly Reading and it failed
        /// `ReviewObservation.validate`, so the phone's own sentence was used.
        /// No parameters: never the text, never a reason written by the model.
        case readingFellBack

        /// The signal's name on the wire.
        var name: String {
            switch self {
            case .appFirstOpen: "app_first_open"
            case .onboardingStep: "onboarding_step"
            case .onboardingFocusChosen: "onboarding_focus_chosen"
            case .assessmentCompleted: "assessment_completed"
            case .onboardingCompleted: "onboarding_completed"
            case .firstPullCompleted: "first_pull_completed"
            case .activityCompleted: "activity_completed"
            case .dayEarned: "day_earned"
            case .pullAbandoned: "pull_abandoned"
            case .challengeAccepted: "challenge_accepted"
            case .challengeCompleted: "challenge_completed"
            case .activityAdded: "activity_added"
            case .notificationOpened: "notification_opened"
            case .weeklyReviewCompleted: "weekly_review_completed"
            case .reentryShown: "reentry_shown"
            case .reentryRecovered: "reentry_recovered"
            case .chapterClosed: "chapter_closed"
            case .paywallView: "paywall_view"
            case .paywallDismissed: "paywall_dismissed"
            case .trialStarted: "trial_started"
            case .purchaseCompleted: "purchase_completed"
            case .restoreTapped: "restore_tapped"
            case .readingFellBack: "reading_fell_back"
            }
        }

        /// The event's own parameters, before `days_since_install` is added.
        /// Every value is a closed-set raw value or a count.
        var parameters: [String: String] {
            switch self {
            case .onboardingStep(let step): ["step": step.rawValue]
            case .onboardingFocusChosen(let count): ["count": String(max(0, count))]
            case .activityCompleted(let method): ["method": method.rawValue]
            case .activityAdded(let source): ["source": source.rawValue]
            case .notificationOpened(let kind): ["kind": kind.rawValue]
            case .paywallView(let door), .paywallDismissed(let door): ["door": door.rawValue]
            case .trialStarted(let plan), .purchaseCompleted(let plan): ["plan": plan.telemetryName]
            default: [:]
            }
        }
    }

    /// A first-run step, as it is named in the data. One per screen, each
    /// question its own, so the funnel shows which question somebody left on
    /// — and never what they answered.
    enum Step: String, CaseIterable, Sendable {
        case coldOpen = "cold_open"
        case questionTraining = "question_training"
        case questionPlanning = "question_planning"
        case questionScreenTime = "question_screen_time"
        case questionSleep = "question_sleep"
        case questionReading = "question_reading"
        case questionFriends = "question_friends"
        case questionBuilding = "question_building"
        case build, drawing, transformation, science, plan
        case pullToBegin = "pull_to_begin"
        case doOne = "do_one"
        case pull, closing

        init?(_ stage: ForgeViewModel.FirstRunStage) {
            switch stage {
            case .coldOpen: self = .coldOpen
            case .question(let index):
                guard Assessment.Question.allCases.indices.contains(index) else { return nil }
                self.init(Assessment.Question.allCases[index])
            case .build: self = .build
            case .drawing: self = .drawing
            case .transformation: self = .transformation
            case .science: self = .science
            case .plan: self = .plan
            case .metaphor: self = .pullToBegin
            case .doOne: self = .doOne
            case .pull: self = .pull
            case .closing: self = .closing
            case .finished: return nil
            }
        }

        init(_ question: Assessment.Question) {
            switch question {
            case .training: self = .questionTraining
            case .planning: self = .questionPlanning
            case .screenTime: self = .questionScreenTime
            case .sleep: self = .questionSleep
            case .reading: self = .questionReading
            case .friends: self = .questionFriends
            case .building: self = .questionBuilding
            }
        }
    }

    /// Which door an activity came into the day through.
    enum ActivitySource: String, CaseIterable, Sendable {
        /// Picked from the library in the add sheet.
        case library
        /// Made in the composer.
        case custom
        /// Offered on the Becoming tab.
        case becoming
        /// A change applied from Plan.
        case plan
    }

    /// Where the paywall was opened from.
    ///
    /// The first three are the unprompted doors, each shown at most once —
    /// see `PremiumInvitation`. The rest are somebody tapping something
    /// locked, or asking for it in Settings.
    enum PaywallDoor: String, CaseIterable, Sendable {
        /// After the first blade celebration closes.
        case firstBlade = "first_blade"
        /// The locked Weekly Reading row in the weekly review.
        case weeklyReading = "weekly_reading"
        /// The invitation at a chapter close.
        case chapterClose = "chapter_close"
        /// A locked accent in Appearance.
        case accent
        /// Plan's locked free-text field.
        case plan
        /// The Forge Pro section in Settings.
        case settings
    }

    // MARK: - The switch

    /// The Settings switch. On unless somebody has turned it off.
    static var isSharingEnabled: Bool {
        get { ForgeShared.defaults.object(forKey: sharingKey) as? Bool ?? true }
        set {
            ForgeShared.defaults.set(newValue, forKey: sharingKey)
            // The SDK's own off switch as well as ours, so nothing it would
            // send by itself goes out either while this is off.
            onMain { state.configuration?.analyticsDisabled = !newValue }
            if newValue { start() }
        }
    }

    /// A test run, hosted or not. Checked before anything else, every time.
    static let isRunningTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || NSClassFromString("XCTestCase") != nil
    }()

    /// Whether a `send` right now would leave the phone.
    static var isActive: Bool { !isRunningTests && isSharingEnabled }

    // MARK: - Starting

    /// Called once from `ForgeApp.init`, and again if the switch is turned on.
    ///
    /// The SDK's own automatic session signal is off: the list above is the
    /// whole of what Forge sends by name. There is no way to un-initialise the
    /// SDK, so turning the switch off later sets its `analyticsDisabled`
    /// instead — see `isSharingEnabled`.
    static func start() {
        guard isActive, state.claimStart() else { return }
        onMain {
            let config = TelemetryDeck.Config(appID: appID)
            config.sendNewSessionBeganSignal = false
            state.configuration = config
            TelemetryDeck.initialize(config: config)
        }
    }

    /// How old the install is, read from the record rather than stored — see
    /// `ProgressStore.firstRecordedDay`. Handed in by `ContentView`, which is
    /// the one place holding the store.
    static func readInstallAge(from provider: @escaping () -> Int?) {
        state.setInstallAge(provider)
    }

    // MARK: - Sending

    /// The one way anything is sent.
    static func send(_ event: Event) {
        guard isActive else { return }
        start()
        let parameters = payload(for: event, daysSinceInstall: state.installAge())
        let name = event.name
        onMain {
            TelemetryDeck.signal(name, parameters: parameters)
        }
    }

    /// Straight through on the main thread, which is where nearly every event
    /// starts; hopped there from anywhere else. Either way the SDK is only ever
    /// touched from the main actor, and in the order things happened.
    private static func onMain(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { body() }
        } else {
            Task { @MainActor in body() }
        }
    }

    /// What goes on the wire for one event. Pure, so the tests can read it.
    static func payload(for event: Event, daysSinceInstall: Int?) -> [String: String] {
        var parameters = event.parameters
        parameters["days_since_install"] = String(max(0, daysSinceInstall ?? 0))
        return parameters
    }

    // MARK: - State

    private static let state = State()

    /// What this file remembers for the life of the process. None of it is
    /// written to disk.
    private final class State: @unchecked Sendable {
        /// The SDK's configuration, once started. Only touched on the main
        /// actor.
        var configuration: TelemetryDeck.Config?

        private let lock = NSLock()
        private var started = false
        private var provider: (() -> Int?)?

        /// True exactly once.
        func claimStart() -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard !started else { return false }
            started = true
            return true
        }

        func setInstallAge(_ provider: @escaping () -> Int?) {
            lock.lock(); defer { lock.unlock() }
            self.provider = provider
        }

        func installAge() -> Int? {
            lock.lock()
            let provider = self.provider
            lock.unlock()
            return provider?()
        }
    }
}

extension PremiumProduct {
    /// The plan as it is named in the data — not the App Store product id.
    var telemetryName: String {
        switch self {
        case .monthly: "monthly"
        case .annual: "annual"
        case .lifetime: "lifetime"
        }
    }
}

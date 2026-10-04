import Foundation
import StoreKit

// MARK: - What is sold

/// The four things somebody can buy.
///
/// # A hard paywall with a free week (1.1)
///
/// 1.0 sold nothing, and 1.1's first pass sold "a reading of the record" behind
/// three rationed doors. **Both are gone, on purpose** (DIRECTION_1_1 §1,
/// `FORGE_CONTEXT.md` §6): a new install finishes onboarding and meets the
/// paywall, and the ongoing practice — keeping new days, the Arcs, the daily
/// challenge, the AI — is what is sold. Nothing that has already happened is
/// sold back: the record stays readable to everybody, forever (`PremiumGate`).
///
/// - **Annual** is the default: preselected, and the plan with the free week.
/// - **Monthly** has no trial.
/// - **The annual offer** is a lower annual price with the same free week,
///   shown once, ever, to somebody who declines the onboarding paywall
///   (`ExitOffer`).
/// - **Lifetime** is never on the paywall. It is sold in Settings → Forge Pro
///   and nowhere else.
///
/// The identifiers are a contract with App Store Connect, `Forge.storekit`,
/// `supabase/functions/forge-ai/storekit.ts` (`PREMIUM_PRODUCTS`) and the table
/// in `docs/APP_STORE.md` §7. `PremiumTests.productsAgree` reads all four files
/// and fails the moment one of them names something else.
enum PremiumProduct: String, CaseIterable, Sendable {
    case annual = "com.dawid.forge.premium.annual"
    case annualOffer = "com.dawid.forge.premium.annual.offer"
    case monthly = "com.dawid.forge.premium.monthly"
    case lifetime = "com.dawid.forge.premium.lifetime"

    static var identifiers: [String] { allCases.map(\.rawValue) }

    init?(id: String) {
        guard let match = Self(rawValue: id) else { return nil }
        self = match
    }

    /// The two plans the paywall offers, annual first and chosen. The offer has
    /// a screen of its own, once; lifetime is Settings' alone.
    static let paywallPlans: [PremiumProduct] = [.annual, .monthly]

    /// Whether it renews. Lifetime is a non-consumable and cannot lapse.
    var isSubscription: Bool { self != .lifetime }

    /// What the plan is called on screen. Never a price — prices only ever come
    /// from `Product.displayPrice`. The offer is an annual plan at another
    /// price, and Settings names it as one.
    var planName: String {
        switch self {
        case .annual, .annualOffer: "Annual"
        case .monthly: "Monthly"
        case .lifetime: "Lifetime"
        }
    }
}

/// What StoreKit says is owned, before founders and trials are considered.
enum PremiumEntitlement: Equatable, Sendable {
    case free
    case subscribed
    case lifetime

    var isPremium: Bool { self != .free }

    /// The entitlement a set of live, verified, unrevoked purchases adds up to.
    ///
    /// Lifetime outranks a subscription: somebody who bought it once should
    /// never be told they are on a plan that could lapse. Anything that is not
    /// a Forge Pro product is ignored.
    static func resolve(_ owned: [PremiumProduct]) -> PremiumEntitlement {
        if owned.contains(.lifetime) { return .lifetime }
        if owned.contains(where: { $0.isSubscription }) { return .subscribed }
        return .free
    }

    /// Which plan to name for the same set. Lifetime first, then the annual
    /// plans, then monthly — the longest commitment is the one that is true.
    static func plan(among owned: [PremiumProduct]) -> PremiumProduct? {
        let longestFirst: [PremiumProduct] = [.lifetime, .annual, .annualOffer, .monthly]
        return longestFirst.first { owned.contains($0) }
    }
}

// MARK: - Who has what

/// The live subscription, as StoreKit described it.
struct ActiveSubscription: Equatable, Sendable {
    let plan: PremiumProduct
    /// When the current period — or the free week — ends.
    let expires: Date?
    /// The current period is an introductory free trial.
    let isTrial: Bool
}

/// Everything deciding `ProAccess` depends on, read at one moment.
struct EntitlementFacts: Equatable, Sendable {
    /// StoreKit has answered at least once since launch. Until it has, nothing
    /// may be taken away on the strength of a placeholder (`ForgeStore`).
    var hasAnswered: Bool
    /// Live, verified, unrevoked purchases.
    var owned: [PremiumProduct] = []
    /// The live subscription, when there is one.
    var subscription: ActiveSubscription? = nil
    /// Forge Pro was bought or tried on this Apple Account at some point.
    var hadPurchase: Bool = false
    /// Ran 1.0 or 1.0.1 — see `Founder`.
    var isFounder: Bool = false
}

/// Who has what. Every gate in the app reads this, through `PremiumGate`.
///
/// | | New days, Arcs, challenge | AI | The record |
/// |---|---|---|---|
/// | `unknown` | yes | yes | yes |
/// | `pro`, `trial` | yes | yes | yes |
/// | `founder` | yes | **no** | yes |
/// | `lapsed`, `none` | **no** | **no** | yes |
///
/// **`unknown` is treated as Pro**, exactly as `hasReadEntitlement` always
/// was: until StoreKit has answered, nothing is locked and nothing is asked
/// for. An unknown answer is never a reason to ask somebody for money.
enum ProAccess: Equatable, Sendable {
    case unknown
    case pro(PremiumProduct)
    case trial(PremiumProduct, ends: Date)
    case founder
    case lapsed
    case none

    /// New days, the Arcs and the daily challenge.
    var keepsNewDays: Bool {
        switch self {
        case .unknown, .pro, .trial, .founder: true
        case .lapsed, .none: false
        }
    }

    /// Ask Forge, the Weekly Reading and Plan in your own words. Founders keep
    /// everything else free; the AI costs money to run and is not theirs.
    var hasAI: Bool {
        switch self {
        case .unknown, .pro, .trial: true
        case .founder, .lapsed, .none: false
        }
    }

    /// A subscription is live — trial included — so Manage Subscription has
    /// something to manage.
    var hasSubscription: Bool {
        switch self {
        case .pro(let plan): plan.isSubscription
        case .trial: true
        default: false
        }
    }

    /// The answer, given what StoreKit and the founder record say.
    ///
    /// Lifetime beats a subscription; a subscription — trial or paid — beats
    /// the founder rule, because somebody who pays for the AI should have it;
    /// a founder is never lapsed; and lapsed is only ever said of somebody who
    /// had Forge Pro once.
    static func resolve(_ facts: EntitlementFacts) -> ProAccess {
        guard facts.hasAnswered else { return .unknown }
        if facts.owned.contains(.lifetime) { return .pro(.lifetime) }
        if let live = facts.subscription {
            if live.isTrial, let ends = live.expires { return .trial(live.plan, ends: ends) }
            return .pro(live.plan)
        }
        // Listed, but without the details to say which kind of period it is in.
        if let plan = PremiumEntitlement.plan(among: facts.owned) { return .pro(plan) }
        if facts.isFounder { return .founder }
        return facts.hadPurchase ? .lapsed : .none
    }
}

// MARK: - Founders

/// Everybody who ran 1.0 or 1.0.1 keeps the whole app free forever, except the
/// AI (DIRECTION_1_1 §1).
///
/// # Two ways to know, and neither is asked
///
/// 1. **The record, on the first launch of this build.** Before anything else
///    in the app writes, the App Group is read once: a completed first run, or
///    any history at all, can only have been left by 1.0 or 1.0.1. The answer
///    is written down under `key` and never re-decided — `true` is never unset,
///    and `false` only means "checked" (a later `AppTransaction` can still
///    turn it into `true`).
/// 2. **The App Store's own receipt of the first download**: a verified
///    `AppTransaction` from `.production` whose `originalAppVersion` — the
///    *build number* on iOS — is no greater than `lastFounderBuild`. This is
///    the one that survives a new phone.
///
/// # Never in Sandbox or Xcode
///
/// The record only counts while the App Store says this is production, or has
/// not said yet (`counts(recorded:environment:)`), so App Review and TestFlight
/// — both Sandbox — always meet the paywall, whatever a test device remembers.
enum Founder {

    /// `CURRENT_PROJECT_VERSION` of the last 1.0.1 build.
    ///
    /// From the git history of `Forge.xcodeproj/project.pbxproj`: it is 2 in
    /// "1.0 as submitted" (`2d8d865`) and was never changed again, through the
    /// 1.0.1 hygiene release (`65734ba`), until 1.1 raised it to 3. A build of
    /// 1.1 must therefore carry a number above this one, or every new install
    /// would read as a founder — `PremiumTests.buildIsAboveFounders` holds it.
    static let lastFounderBuild = 2

    /// `true` for a founder, `false` once checked and not one; absent before
    /// the check has run.
    static let key = "forge.founder.v1"

    /// The two keys 1.0 and 1.0.1 left behind. Spelled out rather than read
    /// from their stores, because this runs before any store exists.
    static let firstRunKey = "forge.hasCompletedFirstRun.v1"
    static let historyKey = "forge.history.v1"

    /// Whether this install is recorded as a founder.
    static func isRecorded(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: key)
    }

    /// The check on the first launch of this build. Runs once; returns true only
    /// the one time it finds a founder.
    ///
    /// Called from `ForgeApp.init`, straight after the App Group migration and
    /// before `ContentView` builds a single store — `ProgressStore` writes
    /// today's record the first time it opens, and after that every install
    /// "holds history".
    @discardableResult
    static func recordOnFirstLaunch(in defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: key) == nil else { return false }
        let founder = ranBefore(in: defaults)
        defaults.set(founder, forKey: key)
        return founder
    }

    /// A completed first run, or any day on the record.
    static func ranBefore(in defaults: UserDefaults) -> Bool {
        if defaults.bool(forKey: firstRunKey) { return true }
        guard let data = defaults.data(forKey: historyKey),
              let days = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else { return false }
        return !days.isEmpty
    }

    /// Write down a founder the App Store vouched for. Returns true the first
    /// time. Never writes `false`: `true` is never unset.
    @discardableResult
    static func record(in defaults: UserDefaults) -> Bool {
        guard !defaults.bool(forKey: key) else { return false }
        defaults.set(true, forKey: key)
        return true
    }

    /// The App Store's rule: production, and first downloaded as build 2 or
    /// earlier.
    static func isFounder(environment: AppStore.Environment, originalAppVersion: String) -> Bool {
        guard environment == .production, let build = buildNumber(originalAppVersion) else { return false }
        return build <= lastFounderBuild
    }

    /// Whether the record counts here. Not in Sandbox or Xcode; in production,
    /// and before the App Store has said which it is — a founder opening the app
    /// offline must not meet a lock.
    static func counts(recorded: Bool, environment: AppStore.Environment?) -> Bool {
        guard recorded else { return false }
        guard let environment else { return true }
        return environment == .production
    }

    /// "2" → 2, "2.1" → 2. Anything else is not a build number.
    static func buildNumber(_ version: String) -> Int? {
        let lead = version.trimmingCharacters(in: .whitespaces).split(separator: ".").first
        return lead.flatMap { Int($0) }
    }
}

// MARK: - What this build has

/// Which of the features Forge Pro names exist in this build.
///
/// A paywall row only names a feature in the build (DIRECTION_1_1 §1), so the
/// paywall reads this rather than a list of promises. Session S5 turned
/// `health` on and S6 turned `askForge` on, each row appearing with its
/// feature, as `arcs` did in S3. The ones that exist are flags too, so the rule
/// is one rule.
struct ForgeFeatures: Equatable, Sendable {
    /// Lock In 7, Monk Mode 30, Discipline 66, Winter Arc. Built in session S3
    /// (FORGE_CONTEXT §17.3).
    var arcs = true
    /// The six, scored from what is actually done. Built.
    var stats = true
    /// A blade for every stretch of days kept. Built.
    var blades = true
    /// Apple Health ticking off steps, workouts, sleep and mindful minutes.
    /// Built in session S5 (FORGE_CONTEXT §17.5).
    var health = true
    /// Ask Forge, a coach that reads the record. Built in session S6
    /// (FORGE_CONTEXT §17.6).
    var askForge = true

    /// This build.
    static let current = ForgeFeatures()
}

/// One row of "what you get": an icon and one line.
enum PaywallRow: CaseIterable, Sendable {
    case arcs, stats, blades, health, askForge

    var line: String {
        switch self {
        case .arcs: "The Arcs: Winter Arc, Monk Mode 30, Discipline 66."
        case .stats: "Six stats, scored on what you actually do."
        case .blades: "A blade earned for every stretch of days you keep."
        case .health: "Apple Health checks your steps, workouts and sleep."
        case .askForge: "Ask Forge, a coach that reads your record."
        }
    }

    var symbol: String {
        switch self {
        // The Arcs tab's own mark, so the row and the tab say one thing.
        case .arcs: "mountain.2"
        case .stats: "hexagon"
        case .blades: "flame"
        case .health: "heart"
        case .askForge: "text.bubble"
        }
    }

    func isAvailable(in features: ForgeFeatures) -> Bool {
        switch self {
        case .arcs: features.arcs
        case .stats: features.stats
        case .blades: features.blades
        case .health: features.health
        case .askForge: features.askForge
        }
    }

    /// The rows the paywall shows, in this order, and only the built ones.
    static func rows(in features: ForgeFeatures = .current) -> [PaywallRow] {
        allCases.filter { $0.isAvailable(in: features) }
    }
}

// MARK: - The AI, locked

/// The AI features, as a locked control names them. Tapping one opens the
/// paywall every time — that is somebody asking, and it is never rationed.
enum ProFeature: String, CaseIterable, Sendable {
    case weeklyReading
    case planInWords

    var title: String {
        switch self {
        case .weeklyReading: "Weekly Reading"
        case .planInWords: "Plan in your own words"
        }
    }

    /// One line each.
    ///
    /// ⚠️ **Release blocker (§2r):** the Weekly Reading is model-written and
    /// only exists once remote AI is activated, which is why its locked row is
    /// shown only where a model is reachable (`WeeklyReviewReading`).
    var detail: String {
        switch self {
        case .weeklyReading: "Each week, a written reading of what held and what slipped, from Forge's AI — checked against your own record before you see it."
        case .planInWords: "Tell Plan the hours you cannot move and what you want fitted around them."
        }
    }

    var symbol: String {
        switch self {
        case .weeklyReading: "text.book.closed"
        case .planInWords: "text.bubble"
        }
    }
}

// MARK: - Every gate, in one place

/// Everything somebody can reach, as the gates see it.
enum ProSurface: CaseIterable, Sendable {
    // The record. Readable forever, whatever is owned (§5 #1, amended in 1.1).
    case history, blade, blades, becoming, reviews, proofCard, widgets
    // The practice.
    case dayControls, arcs, dailyChallenge
    // The AI.
    case askForge, weeklyReading, planInWords

    /// What has already happened, and everything that shows it.
    var isRecord: Bool {
        switch self {
        case .history, .blade, .blades, .becoming, .reviews, .proofCard, .widgets: true
        default: false
        }
    }

    var isAI: Bool {
        switch self {
        case .askForge, .weeklyReading, .planInWords: true
        default: false
        }
    }
}

/// Every Pro gate in the app, in one place, so a test can hold all of them.
enum PremiumGate {
    /// Accent 1. The only one a lapsed install can wear.
    static let freeAccent: ForgeThemeAccent = .forge

    /// Whether this is locked for somebody with this access.
    ///
    /// **The record is never locked.** History, the Blade tab, every blade,
    /// Becoming, the reviews, the Proof Card and the widgets are readable to a
    /// lapsed install exactly as they were the day before it lapsed. Nothing is
    /// deleted, hidden or blurred; only what makes *new* days is sold.
    static func isLocked(_ surface: ProSurface, for access: ProAccess) -> Bool {
        if surface.isRecord { return false }
        if surface.isAI { return !access.hasAI }
        return !access.keepsNewDays
    }

    /// Whether the one locked state ("New days need Forge Pro.") is on screen.
    ///
    /// Never during the first run — a new install meets the paywall there
    /// instead — and never over a summary, a pull or a celebration: it waits
    /// for the moment to finish, so it can never land on top of one.
    static func showsLockedState(
        for access: ProAccess, hasCompletedFirstRun: Bool, isMomentOnScreen: Bool
    ) -> Bool {
        hasCompletedFirstRun && !isMomentOnScreen && isLocked(.dayControls, for: access)
    }

    /// Whether the first run walks straight past the paywall: somebody who
    /// already has the practice — a subscriber, a free week, a founder.
    ///
    /// **Not `unknown`.** Everywhere else an unanswered StoreKit counts as Pro,
    /// because nothing may be taken away on a placeholder. Here the opposite is
    /// the safe side: the paywall is shown, it waits for StoreKit with
    /// everybody else, and it continues by itself the moment the answer is yes.
    static func passesOnboardingPaywall(_ access: ProAccess) -> Bool {
        switch access {
        case .pro, .trial, .founder: true
        case .unknown, .lapsed, .none: false
        }
    }

    /// Accents 2–8 go with new days: a founder, a trial or a subscriber wears
    /// any of the eight; a lapsed install wears Forge blue.
    static func isLocked(accent: ForgeThemeAccent, for access: ProAccess) -> Bool {
        !access.keepsNewDays && accent != freeAccent
    }

    /// What should actually be worn, given what was chosen.
    static func wearable(_ chosen: ForgeThemeAccent, for access: ProAccess) -> ForgeThemeAccent {
        isLocked(accent: chosen, for: access) ? freeAccent : chosen
    }
}

// MARK: - The weekly review's two sentences

/// What sits in the weekly review's card, in order.
///
/// **The observation comes first and is free** — the rules' sentence, for
/// everybody, whenever the record supports one. The Weekly Reading is AI and
/// only ever goes *under* it. **It exists only where a model is reachable**
/// (§2r), so in a build with the model off nobody is offered it — not even
/// locked: a locked row would be selling something the build does not have.
enum WeeklyReviewReading {
    enum Part: Equatable, Sendable {
        case observation
        case locked
        case readButton
        case written
    }

    static func parts(
        hasObservation: Bool,
        hasAI: Bool,
        canReachModel: Bool,
        hasWritten: Bool
    ) -> [Part] {
        // A week the record says nothing about has nothing to read further
        // either: no observation, no Weekly Reading, no offer.
        guard hasObservation else { return [] }
        var parts: [Part] = [.observation]
        guard canReachModel else { return parts }
        if !hasAI {
            parts.append(.locked)
        } else if hasWritten {
            parts.append(.written)
        } else {
            parts.append(.readButton)
        }
        return parts
    }
}

// MARK: - Shown once, ever

/// The lower annual price, offered to somebody who declines the onboarding
/// paywall — the first time they decline, and never again
/// (`forge.exitOffer.v1`).
///
/// No timer, no "you will never see this again", no invented discount: the
/// screen states the price and that it is offered once, which is true.
struct ExitOffer {
    static let key = "forge.exitOffer.v1"

    let defaults: UserDefaults

    init(defaults: UserDefaults = ForgeShared.defaults) {
        self.defaults = defaults
    }

    var hasBeenShown: Bool { defaults.bool(forKey: Self.key) }

    /// Show it if it never has been, and spend it in the same step.
    @discardableResult
    func claim() -> Bool {
        guard !hasBeenShown else { return false }
        defaults.set(true, forKey: Self.key)
        return true
    }

    #if DEBUG
    func reset() { defaults.removeObject(forKey: Self.key) }
    #endif
}

// MARK: - The reminder before the trial ends

/// "Day 5: we remind you." — and the notification that keeps the promise.
///
/// Scheduled for two days before the free week ends — the transaction's own
/// `expirationDate`, read while its offer is introductory — and only while
/// that is still the future, the subscription is still set to renew, and the
/// person left "Remind me before the trial ends" on. Cancelled or converted,
/// the reminder goes: `fireDate` is re-derived on every refresh and nothing
/// else decides it.
enum TrialReminder {
    /// Whether somebody asked for it, from the paywall's toggle. On unless
    /// they turned it off.
    static let key = "forge.trialReminder.v1"

    static let daysBefore = 2

    static let body = "Your free week ends in two days. Keep Forge or cancel in Settings. Either takes one tap."

    static func isWanted(in defaults: UserDefaults = ForgeShared.defaults) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    static func setWanted(_ wanted: Bool, in defaults: UserDefaults = ForgeShared.defaults) {
        defaults.set(wanted, forKey: key)
    }

    /// When it should go off, or nil when it should not exist.
    ///
    /// `willAutoRenew` nil means StoreKit has not said yet, and the reminder is
    /// kept: only a known cancellation removes it.
    ///
    /// **On the day two days before the end, at the start of the person's
    /// day** — `morning`, in minutes after midnight, the time Settings calls
    /// "Start of day". It used to be the exact moment two days before the end,
    /// which carried the minute the free week began: started at 1:16 at night,
    /// the reminder was due at 1:16 at night, with a sound (FORGE_CONTEXT
    /// §17.7). Whatever the hour, the reminder still comes more than a whole
    /// day before the charge, and it says "in two days" of a day that is two
    /// days away. Without a `morning` it is the exact moment, as before.
    ///
    /// Once that morning has passed there is no reminder rather than a later
    /// one: by then it has gone off, and syncing again on the same day must not
    /// schedule it twice.
    static func fireDate(
        access: ProAccess,
        willAutoRenew: Bool?,
        isWanted: Bool,
        now: Date,
        morning: Int? = nil,
        calendar: Calendar = .current
    ) -> Date? {
        guard isWanted, willAutoRenew != false, case .trial(_, let ends) = access else { return nil }
        guard var fire = calendar.date(byAdding: .day, value: -daysBefore, to: ends) else { return nil }
        if let morning {
            let minute = ((morning % 1440) + 1440) % 1440
            // A start of day that does not exist on that date — the hour the
            // clocks skip — keeps the exact moment rather than losing the
            // reminder.
            fire = calendar.date(
                bySettingHour: minute / 60, minute: minute % 60, second: 0, of: fire
            ) ?? fire
        }
        return fire > now ? fire : nil
    }

    /// What the reminder is re-synced on (`ContentView`): its date, whether iOS
    /// lets it be heard, and whether StoreKit has answered at all — so the
    /// answer arriving after a relaunch always runs the sync once, even when
    /// it says "no reminder" exactly as the moment before it did.
    static func syncKey(hasAnswered: Bool, fireDate: Date?, authorization: Int) -> String {
        "\(hasAnswered)·\(fireDate?.timeIntervalSince1970 ?? 0)·\(authorization)"
    }

    /// The trial day the reminder lands on, as the timeline counts days: the
    /// fifth of seven.
    static func reminderDay(trialDays: Int) -> Int? {
        let day = trialDays - daysBefore
        return day >= 1 ? day : nil
    }
}

// MARK: - Words built from StoreKit's own values

/// Every sentence the paywall, the exit offer, the locked state and Settings
/// say about money.
///
/// **Every price comes from StoreKit**: `Product.displayPrice` for the price
/// itself, and `Product.price` in the product's own `priceFormatStyle` for a
/// per-week or per-month equivalent. Nothing here knows what anything costs,
/// so no price can be typed into the interface by accident and every
/// storefront gets its own currency.
///
/// **When the free week is not on offer, every trial word goes**: the
/// headline, the timeline, "Nothing is charged today", the badge, the reminder
/// and the button all read eligibility rather than assuming it.
enum PremiumCopy {

    // MARK: The paywall

    static func headline(trialDays: Int?) -> String {
        guard let trialDays else { return "Keep the practice going." }
        return "\(ForgeCount.spelled(trialDays)) days free. Then decide."
    }

    /// "7 days free" — the badge on the annual plan. Digits, like a price.
    static func trialBadge(days: Int) -> String {
        days == 1 ? "1 day free" : "\(days) days free"
    }

    /// "a year", "a month", "a week", "every 3 months".
    static func per(value: Int, unit: Product.SubscriptionPeriod.Unit) -> String {
        let noun = periodNoun(unit)
        return value == 1 ? "a \(noun)" : "every \(value) \(noun)s"
    }

    /// "the year", "the month" — for "Day 7: $49.99 for the year".
    static func forThe(value: Int, unit: Product.SubscriptionPeriod.Unit) -> String {
        let noun = periodNoun(unit)
        return value == 1 ? "the \(noun)" : "\(value) \(noun)s"
    }

    private static func periodNoun(_ unit: Product.SubscriptionPeriod.Unit) -> String {
        switch unit {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        case .year: "year"
        default: "period"
        }
    }

    /// "$49.99 a year".
    static func price(_ displayPrice: String, value: Int, unit: Product.SubscriptionPeriod.Unit) -> String {
        "\(displayPrice) \(per(value: value, unit: unit))"
    }

    /// A trial's length in days, as people count a trial. Nil for anything
    /// that is not whole days or weeks.
    static func trialDays(value: Int, unit: Product.SubscriptionPeriod.Unit) -> Int? {
        switch unit {
        case .day: value
        case .week: value * 7
        default: nil
        }
    }

    /// What one year (or one month) costs per week (or per month), computed
    /// from StoreKit's own price in its own format.
    ///
    /// A year is fifty-two weeks here, as a price tag counts one.
    static func perWeek(
        price: Decimal, value: Int, unit: Product.SubscriptionPeriod.Unit,
        format: Decimal.FormatStyle.Currency
    ) -> String? {
        let weeks: Decimal
        switch unit {
        case .year: weeks = Decimal(52 * value)
        case .month: weeks = Decimal(value) * Decimal(52) / Decimal(12)
        case .week: weeks = Decimal(value)
        default: return nil
        }
        return "\((price / weeks).formatted(format)) a week"
    }

    static func perMonth(
        price: Decimal, value: Int, unit: Product.SubscriptionPeriod.Unit,
        format: Decimal.FormatStyle.Currency
    ) -> String? {
        let months: Decimal
        switch unit {
        case .year: months = Decimal(12 * value)
        case .month: months = Decimal(value)
        default: return nil
        }
        return "\((price / months).formatted(format)) a month"
    }

    /// The three steps under the headline.
    struct Step: Equatable, Sendable {
        let when: String
        let what: String
    }

    /// Today: everything unlocked. Day 5: we remind you. Day 7: $49.99 for the
    /// year, unless you cancel before.
    static func timeline(
        trialDays: Int, renewal: String, value: Int, unit: Product.SubscriptionPeriod.Unit,
        reminds: Bool
    ) -> [Step] {
        var steps = [Step(when: "Today", what: "Everything unlocked.")]
        if let day = TrialReminder.reminderDay(trialDays: trialDays) {
            steps.append(Step(when: "Day \(day)", what: reminds ? "We remind you." : "Two days left."))
        }
        steps.append(Step(
            when: "Day \(trialDays)",
            what: "\(renewal) for \(forThe(value: value, unit: unit)), unless you cancel before."
        ))
        return steps
    }

    /// "Cancel anytime in Settings. Nothing is charged today." — the second
    /// sentence only while a free week is what is being started.
    static func cancelLine(startsFreeWeek: Bool) -> String {
        startsFreeWeek
            ? "Cancel anytime in Settings. Nothing is charged today."
            : "Cancel anytime in Settings."
    }

    static let recordLine = "If you ever stop, your record stays readable."

    static let reminderToggle = "Remind me before the trial ends"

    static func buttonTitle(startsFreeWeek: Bool) -> String {
        startsFreeWeek ? "Start my free week" : "Continue"
    }

    /// Said under the button once the offer has been declined, and the paywall
    /// stays.
    static let declinedLine = "Forge needs Forge Pro to keep new days."

    // MARK: The offer, once

    static let offerTitle = "One lower price, offered once."

    /// "$29.99 a year, $2.50 a month, still with seven days free."
    static func offerLine(price: String, perMonth: String?, trialDays: Int?) -> String {
        var line = "\(price) a year"
        if let perMonth { line += ", \(perMonth)" }
        if let trialDays {
            line += ", still with \(ForgeCount.spelled(trialDays).lowercased()) days free."
        } else {
            line += "."
        }
        return line
    }

    static func offerButton(price: String, startsFreeWeek: Bool) -> String {
        startsFreeWeek ? "Start my free week at \(price)" : "Continue at \(price)"
    }

    static let offerDecline = "No thanks"

    // MARK: The locked state

    static let lockedTitle = "New days need Forge Pro."
    static let lockedLine = "Your record stays yours."

    // MARK: Settings

    /// Founder · Trial, ends [date] · Forge Pro, [plan] · Not subscribed.
    static func status(_ access: ProAccess, date: (Date) -> String) -> String {
        switch access {
        case .unknown: "Checking"
        case .pro(let plan): "Forge Pro, \(plan.planName)"
        case .trial(_, let ends): "Trial, ends \(date(ends))"
        case .founder: "Founder"
        case .lapsed, .none: "Not subscribed"
        }
    }

    /// "$129.99, once. Never renews."
    static func lifetimeLine(price: String) -> String { "\(price), once. Never renews." }

    // MARK: What renewing means

    /// The auto-renewal terms for the plan about to be bought, with its own
    /// price and period — what App Review looks for beside the button.
    static func renewalTerms(
        planName: String, price: String, value: Int, unit: Product.SubscriptionPeriod.Unit,
        trialDays: Int?
    ) -> String {
        var text = "\(planName) renews at \(price) \(per(value: value, unit: unit)) until you cancel."
        if let trialDays {
            text += " The first \(trialDays) days are free; payment is charged to your Apple Account when they end unless you cancel at least 24 hours before."
        } else {
            text += " Payment is charged to your Apple Account when you confirm."
        }
        text += " Renewal is charged within the 24 hours before each period ends. Manage or cancel in your Apple Account settings."
        return text
    }
}

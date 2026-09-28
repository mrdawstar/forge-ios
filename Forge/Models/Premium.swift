import Foundation
import StoreKit

// MARK: - What is sold

/// The three things somebody can buy.
///
/// # Monthly is back, and that is a decision rather than a drift
///
/// 1.0's version of this file said *"No monthly plan"* and argued it: Forge keeps
/// everything on the phone, costs almost nothing per person, and a practice
/// measured in years should not be re-decided twelve times a year. **That
/// decision has been reversed on purpose for Forge Pro (1.1)**, and the reversal
/// is final — see `FORGE_CONTEXT.md` §6. What changed is what is being sold: Pro
/// is a reading of the record, and somebody deciding whether that reading is
/// worth anything should be able to find out for a month without committing to
/// a year. Annual stays the default and the one with the trial; lifetime stays
/// for anybody who wants never to be asked again.
///
/// The identifiers are a contract with App Store Connect, `Forge.storekit` and
/// `supabase/functions/forge-ai/storekit.ts` (`PREMIUM_PRODUCTS`). All four
/// must name the same three strings; `PremiumTests` reads the `.storekit` file
/// to hold the first two together.
enum PremiumProduct: String, CaseIterable, Sendable {
    case monthly = "com.dawid.forge.premium.monthly"
    case annual = "com.dawid.forge.premium.annual"
    case lifetime = "com.dawid.forge.premium.lifetime"

    static var identifiers: [String] { allCases.map(\.rawValue) }

    init?(id: String) {
        guard let match = Self(rawValue: id) else { return nil }
        self = match
    }

    /// The order the paywall lists them in: annual first and selected, then
    /// monthly, then lifetime.
    static let displayOrder: [PremiumProduct] = [.annual, .monthly, .lifetime]

    /// Whether it renews. Lifetime is a non-consumable and cannot lapse.
    var isSubscription: Bool { self != .lifetime }

    /// What the plan is called on screen. Never a price — prices only ever come
    /// from `Product.displayPrice`.
    var planName: String {
        switch self {
        case .monthly: "Monthly"
        case .annual: "Annual"
        case .lifetime: "Lifetime"
        }
    }
}

/// What somebody currently has.
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

    /// Which plan to name in Settings for the same set. Lifetime first, then
    /// annual, then monthly — the longest commitment is the one that is true.
    static func plan(among owned: [PremiumProduct]) -> PremiumProduct? {
        let longestFirst: [PremiumProduct] = [.lifetime, .annual, .monthly]
        return longestFirst.first { owned.contains($0) }
    }
}

// MARK: - What Pro is

/// The three things Pro adds, and there are only three.
///
/// **Everything that is the user's record stays free**: the day, the pull, the
/// history, the heatmap, the streak, blades, milestones, chapters, the weekly
/// review's marks, count and questions, every answer they ever wrote, the
/// Becoming tab, Plan's own moves, the widgets. Pro is a *reading* of that
/// record and a way to ask for things in words — never the record itself. That
/// line is §5 rule #1 and it is not moved by this file.
enum ProFeature: String, CaseIterable, Sendable {
    case weeklyReading
    case planInWords
    case accents

    var title: String {
        switch self {
        case .weeklyReading: "Weekly Reading"
        case .planInWords: "Plan in your own words"
        case .accents: "Eight accents"
        }
    }

    /// One line each.
    ///
    /// ⚠️ **Release blocker (§2r):** the Weekly Reading line describes the
    /// model-written reading, which only exists once remote AI is activated.
    /// While `RemoteForgeAI.isModelEnabled` is false, Pro adds no Weekly Reading
    /// beyond the free observation — so a build that sells Pro must not ship
    /// before the activation PR, or this line must change.
    var detail: String {
        switch self {
        case .weeklyReading: "Each week, a written reading of what held and what slipped, from Forge's AI — checked against your own record before you see it."
        case .planInWords: "Tell Plan the hours you cannot move and what you want fitted around them."
        case .accents: "Dress the app in any of the eight. Forge blue stays free."
        }
    }

    var symbol: String {
        switch self {
        case .weeklyReading: "text.book.closed"
        case .planInWords: "text.bubble"
        case .accents: "paintpalette"
        }
    }
}

/// Every Pro gate in the app, in one place, so a test can hold all of them.
enum PremiumGate {
    /// Accent 1. The only one a free install can wear.
    static let freeAccent: ForgeThemeAccent = .forge

    /// Accents 2–8 need Pro.
    static func isLocked(_ accent: ForgeThemeAccent, isPremium: Bool) -> Bool {
        !isPremium && accent != freeAccent
    }

    /// What should actually be worn, given what was chosen. A lapsed Pro
    /// install falls back to the free accent rather than keeping a paid one.
    static func wearable(_ chosen: ForgeThemeAccent, isPremium: Bool) -> ForgeThemeAccent {
        isLocked(chosen, isPremium: isPremium) ? freeAccent : chosen
    }

    /// Plan's free-text field. Plan's own moves stay free.
    static func canPlanInWords(isPremium: Bool) -> Bool { isPremium }

    /// The Weekly Reading — the model-written reading under the observation.
    /// The rules' observation itself, the week's marks, its count, last week's
    /// line and both questions stay free (§2r).
    static func showsWeeklyReading(isPremium: Bool) -> Bool { isPremium }
}

// MARK: - The weekly review's two sentences

/// What sits in the weekly review's card, in order.
///
/// **The observation comes first and is free** — the rules' sentence, for
/// everybody, whenever the record supports one. The Weekly Reading is the Pro
/// half and only ever goes *under* it: locked for somebody without Pro (door
/// 2, once), a "Read my week" button for Pro when a model is reachable, the
/// model's validated reading once it has answered — and nothing at all for
/// Pro while the model is switched off (§2r), because nothing may be invented
/// to fill the space.
enum WeeklyReviewReading {
    enum Part: Equatable, Sendable {
        case observation
        case locked
        case readButton
        case written
    }

    static func parts(
        hasObservation: Bool,
        isPremium: Bool,
        isOfferingLocked: Bool,
        canReachModel: Bool,
        hasWritten: Bool
    ) -> [Part] {
        // A week the record says nothing about has nothing to read further
        // either: no observation, no Weekly Reading, no upsell.
        guard hasObservation else { return [] }
        var parts: [Part] = [.observation]
        if !PremiumGate.showsWeeklyReading(isPremium: isPremium) {
            if isOfferingLocked { parts.append(.locked) }
        } else if hasWritten {
            parts.append(.written)
        } else if canReachModel {
            parts.append(.readButton)
        }
        return parts
    }
}

// MARK: - When Forge asks

/// The three doors, and the rule that each opens at most once, in order.
///
/// # This replaces §5 rule #8, deliberately
///
/// The rule was *"Forge asks about money once, ever … only after 5 days kept,
/// on the Blade tab"*, and `PremiumInvitation` was the one-flag type that kept
/// it. **Forge Pro changes that rule on purpose** (see `FORGE_CONTEXT.md` §5 and
/// §6): there are now three unprompted doors, each at a moment somebody has
/// already stopped, each shown at most once, and never out of order.
///
/// 1. **`firstBlade`** — after the first blade celebration *closes*. If that
///    happens inside the first run, it waits until the first run is over.
/// 2. **`weeklyReading`** — the first weekly review with a reading in it shows a
///    locked Weekly Reading row. Tapping it opens the paywall; not tapping it
///    still spends the door.
/// 3. **`chapterClose`** — the first chapter close shows the invitation card.
///
/// # What never opens a door
///
/// Launch, the day flow (anything between the first activity and the end of
/// an earned day's summary), the pull itself, the first run, or a Pro install.
/// Tapping a locked feature is not a door — that is somebody asking — and is
/// never limited.
///
/// # Once, and in order
///
/// A door that has been passed is gone. A later door opening first retires the
/// earlier ones: somebody who reached a chapter close before a blade (an
/// upgrade from 1.0 with every blade already earned) is never shown the blade
/// door afterwards. Three asks is the ceiling, not the target.
///
/// Stored in the App Group suite as a list of door names, and nothing else.
struct PremiumInvitation {

    enum Door: String, CaseIterable, Comparable, Sendable {
        case firstBlade = "first_blade"
        case weeklyReading = "weekly_reading"
        case chapterClose = "chapter_close"

        var order: Int {
            switch self {
            case .firstBlade: 0
            case .weeklyReading: 1
            case .chapterClose: 2
            }
        }

        static func < (lhs: Door, rhs: Door) -> Bool { lhs.order < rhs.order }

        /// The same door, as the paywall's telemetry names it.
        var telemetry: ForgeTelemetry.PaywallDoor {
            switch self {
            case .firstBlade: .firstBlade
            case .weeklyReading: .weeklyReading
            case .chapterClose: .chapterClose
            }
        }
    }

    /// Everything the decision depends on, taken at the moment of asking.
    struct Moment: Equatable, Sendable {
        var isPremium: Bool
        var hasCompletedFirstRun: Bool
        /// The first run, a pull in progress, an earned day's summary, a blade
        /// celebration, an honor activity's moment — anything that is the day
        /// rather than a pause in it.
        var isDayInProgress: Bool
    }

    static let key = "forge.paywallDoors.v1"

    let defaults: UserDefaults

    init(defaults: UserDefaults = ForgeShared.defaults) {
        self.defaults = defaults
    }

    /// Doors already shown, oldest first.
    var shown: [Door] {
        (defaults.array(forKey: Self.key) as? [String] ?? []).compactMap(Door.init(rawValue:))
    }

    /// Whether this door may open now. Reads only — see `claim`.
    func isOpen(_ door: Door, at moment: Moment) -> Bool {
        guard !moment.isPremium,
              moment.hasCompletedFirstRun,
              !moment.isDayInProgress
        else { return false }
        let past = shown
        guard !past.contains(door) else { return false }
        // Never behind a door already passed.
        return past.allSatisfy { $0 < door }
    }

    /// Open it if it may be opened, and spend it in the same step.
    @discardableResult
    func claim(_ door: Door, at moment: Moment) -> Bool {
        guard isOpen(door, at: moment) else { return false }
        markShown(door)
        return true
    }

    /// Spend a door. Idempotent.
    func markShown(_ door: Door) {
        var past = shown
        guard !past.contains(door) else { return }
        past.append(door)
        defaults.set(past.map(\.rawValue), forKey: Self.key)
    }

    #if DEBUG
    /// Puts all three back, so App Review builds and a developer can walk them
    /// again. Never compiled into a release build.
    func reset() { defaults.removeObject(forKey: Self.key) }
    #endif
}

// MARK: - Words built from StoreKit's own values

/// The sentences the paywall prints under each plan.
///
/// **Every price comes from `Product.displayPrice`**, handed in as a string —
/// nothing here knows what anything costs, so no price can be hard-coded into
/// the interface by accident and every storefront gets its own currency.
enum PremiumCopy {

    /// "/year", "/month". Nil for anything that is not one whole period.
    static func perPeriod(value: Int, unit: Product.SubscriptionPeriod.Unit) -> String? {
        guard value == 1 else { return nil }
        switch unit {
        case .day: return "/day"
        case .week: return "/week"
        case .month: return "/month"
        case .year: return "/year"
        default: return nil
        }
    }

    /// "year", "month" — for the sentence spelling out the renewal.
    static func periodNoun(value: Int, unit: Product.SubscriptionPeriod.Unit) -> String {
        let noun: String
        switch unit {
        case .day: noun = "day"
        case .week: noun = "week"
        case .month: noun = "month"
        case .year: noun = "year"
        default: noun = "period"
        }
        return value == 1 ? noun : "\(value) \(noun)s"
    }

    /// "7 days", "1 month" — a trial's length as somebody would say it. A one-week
    /// trial is said in days because that is how people count a trial.
    static func trialLength(value: Int, unit: Product.SubscriptionPeriod.Unit) -> String {
        var days: Int?
        if unit == .day { days = value }
        if unit == .week { days = value * 7 }
        if let days { return days == 1 ? "1 day" : "\(days) days" }
        return value == 1 ? "1 \(periodNoun(value: 1, unit: unit))" : periodNoun(value: value, unit: unit)
    }

    /// "$49.99/year", or "7 days free, then $49.99/year" when a free trial is on
    /// offer to this Apple Account.
    static func subscriptionLine(
        price: String,
        value: Int,
        unit: Product.SubscriptionPeriod.Unit,
        freeTrial: (value: Int, unit: Product.SubscriptionPeriod.Unit)? = nil
    ) -> String {
        let per = perPeriod(value: value, unit: unit) ?? " every \(periodNoun(value: value, unit: unit))"
        let recurring = "\(price)\(per)"
        guard let freeTrial else { return recurring }
        return "\(trialLength(value: freeTrial.value, unit: freeTrial.unit)) free, then \(recurring)"
    }

    /// "$99.99 once".
    static func lifetimeLine(price: String) -> String { "\(price) once" }
}

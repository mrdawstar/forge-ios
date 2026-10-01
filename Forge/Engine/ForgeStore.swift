import Foundation
import StoreKit

/// Everything Forge knows about what has been bought, and who has what.
///
/// The only thing in the app that talks to StoreKit. Nothing is banked here that
/// the system already knows: the entitlement is read back out of
/// `Transaction.currentEntitlements` on every refresh rather than written down
/// when a purchase succeeds, for the same reason `ProgressStore` computes the
/// streak instead of storing it. A receipt cached in `UserDefaults` is a second
/// answer to "has this person paid", and the first time it disagrees with the
/// App Store it does so on a phone nobody can reach.
///
/// The one thing written down is the founder record (`Founder`), because it is
/// a fact about the install's past that StoreKit cannot be asked for offline.
///
/// `access` is the answer every screen reads — see `ProAccess`.
@MainActor
@Observable
final class ForgeStore {

    // MARK: State

    enum Status: Equatable {
        /// Asking the App Store what the products are.
        case loading
        case ready
        /// The App Store could not be reached, or knows nothing about these
        /// identifiers. Everything already bought still works.
        case unavailable
    }

    private(set) var status: Status = .loading
    private(set) var annual: Product?
    private(set) var annualOffer: Product?
    private(set) var monthly: Product?
    private(set) var lifetime: Product?
    /// What StoreKit says is owned. Founders and trials are `access`'s job.
    private(set) var entitlement: PremiumEntitlement = .free
    /// Which plan the entitlement comes from. Nil without one.
    private(set) var activePlan: PremiumProduct?
    /// The live subscription — its plan, its end, whether it is the free week.
    private(set) var subscription: ActiveSubscription?
    /// Whether the live subscription renews at the end of its period. Nil when
    /// StoreKit has not said, which keeps the trial reminder rather than
    /// guessing it away (`TrialReminder.fireDate`).
    private(set) var willAutoRenew: Bool?
    /// Forge Pro was bought or tried on this Apple Account at some point —
    /// the difference between lapsed and never subscribed.
    private(set) var hadPurchase = false
    /// Whether the entitlement has been read at least once since launch.
    ///
    /// Until it has, `access` is `.unknown`, which is treated as Pro: nothing
    /// that takes something *away* — the lock, the accent falling back to
    /// Forge blue — may act on a placeholder. See `ContentView`.
    private(set) var hasReadEntitlement = false
    /// Whether this Apple Account can still take a free trial in the group.
    ///
    /// Asked of StoreKit rather than assumed: somebody who has already had a
    /// trial in this subscription group is not offered a second one, and no
    /// screen may print a trial word to them (`PremiumCopy`).
    private(set) var isTrialEligible = false

    /// The founder record, read once at launch (`Founder.recordOnFirstLaunch`
    /// wrote it before this existed) and raised if the App Store vouches for
    /// an original download of 1.0 or 1.0.1.
    private(set) var isFounderRecorded: Bool
    /// Production, Sandbox or Xcode, from the app's own transaction. Nil until
    /// it has answered.
    private(set) var appEnvironment: AppStore.Environment?

    /// The purchase currently in flight, so exactly one button can show a
    /// spinner and no button can be pressed twice.
    private(set) var pending: Product.ID?
    /// Set when something went wrong in a way worth saying out loud. Cancelling
    /// is not one of those things.
    private(set) var failure: String?

    /// Whether a restore is running. Separate from `pending` because it belongs
    /// to no product.
    private(set) var isRestoring = false

    /// A purchase StoreKit has confirmed and does not list yet.
    ///
    /// `Product.purchase()` hands back the verified transaction a moment before
    /// `Transaction.currentEntitlements` lists it: measured on the iOS 26.5
    /// Simulator, a quarter of a second later the index, `Transaction.latest`
    /// and the subscription status were all still empty, and half a second
    /// later all three had it. Reading only the index at that moment answered
    /// "free" to somebody who had just paid, which on a paywall is a locked app
    /// straight after the purchase. So the transaction StoreKit returned counts
    /// until the index lists it, and not a moment longer — see
    /// `owned(listed:recent:now:)`. In memory only: never written down, and
    /// gone on the next launch.
    private var recentPurchase: RecentPurchase?

    /// Held so it is not deallocated out from under the app. There is no
    /// `deinit` cancelling it on purpose: one store is built at launch and lives
    /// as long as the process, so the only thing a teardown path would add is a
    /// nonisolated hop for a case that never happens.
    private var updates: Task<Void, Never>?

    /// Where the founder record lives. The App Group, except under test.
    private let defaults: UserDefaults

    // MARK: Reading

    /// Who has what. See `ProAccess`.
    var access: ProAccess {
        #if DEBUG
        if let simulated { return simulated }
        #endif
        return ProAccess.resolve(facts)
    }

    /// What `access` is decided from.
    var facts: EntitlementFacts {
        EntitlementFacts(
            hasAnswered: hasReadEntitlement,
            owned: owned,
            subscription: subscription,
            hadPurchase: hadPurchase,
            isFounder: isFounder
        )
    }

    /// Live purchases, by product.
    private(set) var owned: [PremiumProduct] = []

    /// A founder the record or the App Store vouches for — and never one in
    /// Sandbox or Xcode. See `Founder.counts`.
    var isFounder: Bool { Founder.counts(recorded: isFounderRecorded, environment: appEnvironment) }

    /// The paywall's plans that loaded, annual first.
    var offerings: [Product] { PremiumProduct.paywallPlans.compactMap(product(for:)) }

    func product(for plan: PremiumProduct) -> Product? {
        switch plan {
        case .annual: annual
        case .annualOffer: annualOffer
        case .monthly: monthly
        case .lifetime: lifetime
        }
    }

    /// The free week on this plan, in the terms the App Store gave rather than
    /// words of our own. Nil when it is not on offer — somebody who has already
    /// had one, a plan without one, or a product that did not load.
    func freeTrial(for plan: PremiumProduct) -> Product.SubscriptionOffer? {
        guard isTrialEligible,
              let offer = product(for: plan)?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial
        else { return nil }
        return offer
    }

    /// The annual plan's free week. See `freeTrial(for:)`.
    var trial: Product.SubscriptionOffer? { freeTrial(for: .annual) }

    // MARK: Lifetime of the object

    /// - Parameters:
    ///   - defaults: where the founder record is read and raised.
    ///   - readsAppTransaction: off under test, where the App Store's own
    ///     transaction for the host app is not the thing being tested.
    init(defaults: UserDefaults = ForgeShared.defaults, readsAppTransaction: Bool = true) {
        self.defaults = defaults
        isFounderRecorded = Founder.isRecorded(in: defaults)
        #if DEBUG
        // A simulated state survives a relaunch, so a debug build can be walked
        // across one — a first run past its paywall, a day reopened at noon —
        // without a purchase the Simulator cannot complete (FORGE_CONTEXT §17.3).
        // Observers do not run in an initialiser, so both halves are set here.
        if let raw = defaults.string(forKey: Self.debugAccessKey),
           let restored = SimulatedAccess(rawValue: raw) {
            debugAccess = restored
            simulated = restored.access(now: .now)
        }
        #endif
        // Claimed before anything is loaded. A purchase approved on another
        // device, a renewal, a refund or a family-sharing change all arrive
        // here, and the listener has to be running before the first await or
        // one of them can land in the gap.
        updates = listenForUpdates()
        Task { await refresh() }
        if readsAppTransaction {
            Task { await readAppTransaction() }
        }
    }

    /// Load the products and re-read what is owned. Safe to call again — the
    /// paywall's retry runs exactly this, and so does every return to the app.
    func refresh() async {
        await loadProducts()
        await refreshEntitlement()
    }

    // MARK: Products

    private func loadProducts() async {
        do {
            let loaded = try await Product.products(for: PremiumProduct.identifiers)
            for product in loaded {
                switch PremiumProduct(id: product.id) {
                case .annual: annual = product
                case .annualOffer: annualOffer = product
                case .monthly: monthly = product
                case .lifetime: lifetime = product
                case nil: break
                }
            }
            // Eligibility is the group's, so any of its plans can answer it.
            if let subscription = (annual ?? annualOffer ?? monthly)?.subscription {
                isTrialEligible = await subscription.isEligibleForIntroOffer
            }
            // An empty answer is not an error from StoreKit's point of view, but
            // it is one from the screen's: there would be nothing to tap.
            status = offerings.isEmpty ? .unavailable : .ready
        } catch {
            // Offline, or the App Store is having a day. Anything already bought
            // keeps working, because entitlements are read separately and are
            // cached by the system on the device.
            status = .unavailable
        }
    }

    // MARK: Entitlement

    /// What the App Store currently says is owned.
    ///
    /// `currentEntitlements` only yields transactions that are live right now —
    /// expired subscriptions and refunded purchases are already gone from it —
    /// so this is a straight read rather than a set of date comparisons. The
    /// revocation check is belt and braces for a refund that has been recorded
    /// but not yet dropped.
    ///
    /// Everything is read into locals first and assigned together at the end,
    /// so `access` never passes through a half-read state on the way.
    func refreshEntitlement() async {
        var listed: [PremiumProduct] = []
        var live: [ActiveSubscription] = []

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? verified(result) else { continue }
            guard transaction.revocationDate == nil else { continue }
            guard let product = PremiumProduct(id: transaction.productID) else { continue }
            listed.append(product)
            if product.isSubscription {
                live.append(ActiveSubscription(
                    plan: product,
                    expires: transaction.expirationDate,
                    isTrial: Self.isFreeTrial(transaction)
                ))
            }
        }

        let reading = Self.owned(listed: listed, recent: recentPurchase, now: .now)
        // A subscription still being carried has no listing to read its
        // details from yet; the transaction StoreKit returned has them.
        if let carried = reading.recent, carried.product.isSubscription,
           !live.contains(where: { $0.plan == carried.product }) {
            live.append(ActiveSubscription(
                plan: carried.product, expires: carried.expirationDate, isTrial: carried.isTrial
            ))
        }
        let current = live.max { ($0.expires ?? .distantPast) < ($1.expires ?? .distantPast) }
        let renews = await Self.willAutoRenew(current, product: current.flatMap { product(for: $0.plan) })
        let past = await Self.hasEverBought()

        recentPurchase = reading.recent
        owned = reading.owned
        subscription = current
        willAutoRenew = renews
        hadPurchase = past || !reading.owned.isEmpty
        // Lifetime outranks a subscription — see `PremiumEntitlement.resolve`.
        entitlement = PremiumEntitlement.resolve(reading.owned)
        activePlan = PremiumEntitlement.plan(among: reading.owned)
        hasReadEntitlement = true
    }

    /// What is owned, given what `currentEntitlements` listed and a purchase it
    /// may not list yet; and whether that purchase still needs carrying.
    ///
    /// The purchase stops counting the moment the index lists its product —
    /// the index is the answer again — or the moment it would have expired.
    nonisolated static func owned(
        listed: [PremiumProduct], recent: RecentPurchase?, now: Date
    ) -> (owned: [PremiumProduct], recent: RecentPurchase?) {
        guard let recent, !listed.contains(recent.product) else { return (listed, nil) }
        if let expires = recent.expirationDate, expires <= now { return (listed, nil) }
        return (listed + [recent.product], recent)
    }

    /// The current period is an introductory free trial.
    nonisolated static func isFreeTrial(_ transaction: Transaction) -> Bool {
        transaction.offer?.type == .introductory && transaction.offer?.paymentMode == .freeTrial
    }

    /// Whether the live subscription renews, from its renewal info. Nil when
    /// there is none, or StoreKit cannot say.
    private static func willAutoRenew(_ live: ActiveSubscription?, product: Product?) async -> Bool? {
        guard live != nil, let subscription = product?.subscription,
              let statuses = try? await subscription.status
        else { return nil }
        for status in statuses {
            switch status.state {
            case .subscribed, .inGracePeriod, .inBillingRetryPeriod:
                guard case .verified(let renewal) = status.renewalInfo else { continue }
                return renewal.willAutoRenew
            default:
                continue
            }
        }
        return nil
    }

    /// Whether anything Forge Pro was ever bought or tried on this account —
    /// expired, refunded or live.
    private static func hasEverBought() async -> Bool {
        for await result in Transaction.all {
            guard case .verified(let transaction) = result else { continue }
            if PremiumProduct(id: transaction.productID) != nil { return true }
        }
        return false
    }

    /// Everything the App Store tells us after the fact: a renewal, a refund, a
    /// purchase approved by a parent, a plan bought on another device.
    private func listenForUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                guard let transaction = try? self.verified(result) else { continue }
                // A refund of the purchase still being carried ends the carry
                // at once, rather than when the index next looks.
                if transaction.revocationDate != nil,
                   self.recentPurchase?.product.rawValue == transaction.productID {
                    self.recentPurchase = nil
                }
                await transaction.finish()
                await self.refreshEntitlement()
            }
        }
    }

    // MARK: Founders

    /// The App Store's receipt of this install's first download.
    ///
    /// Read once, at launch, with no prompt — `AppTransaction.shared`, never
    /// `refresh()`, which asks for a password. Failure (offline, or no App
    /// Store account in the Simulator) leaves `appEnvironment` nil, and the
    /// record then stands on its own.
    private func readAppTransaction() async {
        guard let result = try? await AppTransaction.shared,
              case .verified(let transaction) = result
        else { return }
        appEnvironment = transaction.environment
        guard Founder.isFounder(
            environment: transaction.environment,
            originalAppVersion: transaction.originalAppVersion
        ) else { return }
        if Founder.record(in: defaults) {
            ForgeTelemetry.send(.founderDetected)
        }
        isFounderRecorded = true
    }

    // MARK: Buying

    enum Outcome: Equatable {
        /// Paid for, or — with `startedTrial` — the free trial has begun and
        /// nothing has been charged yet. The two are told apart so telemetry
        /// never counts a trial as a sale.
        case bought(startedTrial: Bool)
        case cancelled
        /// Ask-to-buy, or a card that needs the bank. Nothing to do but wait —
        /// the update listener will catch it whenever it lands.
        case waiting
        case failed
    }

    @discardableResult
    func purchase(_ product: Product) async -> Outcome {
        guard pending == nil else { return .cancelled }
        pending = product.id
        failure = nil
        defer { pending = nil }

        do {
            switch try await product.purchase() {
            case .success(let result):
                let transaction = try verified(result)
                let startedTrial = Self.isFreeTrial(transaction)
                if transaction.revocationDate == nil,
                   let bought = PremiumProduct(id: transaction.productID) {
                    recentPurchase = RecentPurchase(
                        product: bought,
                        expirationDate: transaction.expirationDate,
                        isTrial: startedTrial
                    )
                }
                if startedTrial { isTrialEligible = false }
                // Finished only after the entitlement has been re-read, so the
                // screen is never dismissed a frame before it is true. The
                // read counts this transaction even if the index does not list
                // it yet — see `recentPurchase`.
                await refreshEntitlement()
                await transaction.finish()
                return .bought(startedTrial: startedTrial)

            case .userCancelled:
                // Not a failure and not worth a word on screen.
                return .cancelled

            case .pending:
                return .waiting

            @unknown default:
                return .failed
            }
        } catch {
            failure = "That didn't go through. Nothing has been charged."
            return .failed
        }
    }

    /// Bring back a purchase made on another device, or on this one before it
    /// was wiped.
    ///
    /// `AppStore.sync()` prompts for a password, so it is only ever run from a
    /// deliberate tap. The entitlement is re-read either way — most "lost"
    /// purchases are already on the device and only need looking at.
    @discardableResult
    func restore() async -> Bool {
        guard !isRestoring else { return false }
        isRestoring = true
        failure = nil
        defer { isRestoring = false }

        try? await AppStore.sync()
        await refreshEntitlement()

        if !entitlement.isPremium {
            failure = "Nothing to restore on this Apple Account."
        }
        return entitlement.isPremium
    }

    // MARK: Verification

    enum StoreError: Error { case unverified }

    /// The App Store signs every transaction; anything that fails the check is
    /// treated as though it never arrived.
    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw StoreError.unverified
        case .verified(let safe): return safe
        }
    }

    // MARK: Proof of purchase, for the model

    /// `jwsRepresentation` of the current Premium entitlement, for
    /// `X-Forge-Transaction` — or nil for somebody without one.
    ///
    /// The JWS exactly as StoreKit holds it: Apple signed it, and `forge-ai`
    /// verifies that signature offline against Apple Root CA G3 rather than
    /// believing this app. Only transactions StoreKit itself verified on this
    /// device are considered, so an unverified one is never even sent. A
    /// founder without a subscription has nothing to send, which is the rule:
    /// the AI is not theirs (§6).
    ///
    /// `nonisolated` because it reads nothing on this object; it is called from
    /// `RemoteForgeAI`'s closure, off the main actor.
    nonisolated static func entitlementProof(now: Date = .now) async -> String? {
        var candidates: [EntitlementCandidate] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            candidates.append(
                EntitlementCandidate(
                    productID: transaction.productID,
                    expirationDate: transaction.expirationDate,
                    revocationDate: transaction.revocationDate,
                    jws: result.jwsRepresentation
                )
            )
        }
        return bestProof(among: candidates, now: now)
    }

    /// Which one to send. Lifetime first — it cannot lapse, so it is the one
    /// least likely to be refused. Otherwise the unrevoked subscription that
    /// runs longest. Never a revoked, expired or non-Premium transaction: the
    /// server would refuse it (402), and sending it would only cost a request.
    nonisolated static func bestProof(among candidates: [EntitlementCandidate], now: Date) -> String? {
        let premium = candidates.filter {
            PremiumProduct(id: $0.productID) != nil && $0.revocationDate == nil
        }
        if let lifetime = premium.first(where: { PremiumProduct(id: $0.productID) == .lifetime }) {
            return lifetime.jws
        }
        return premium
            .filter { ($0.expirationDate ?? .distantPast) > now }
            .max { ($0.expirationDate ?? .distantPast) < ($1.expirationDate ?? .distantPast) }?
            .jws
    }

    // MARK: Debug

    #if DEBUG
    /// Each state somebody can be in, without a Sandbox account or a 1.0
    /// install to hand. Nil hands the answer back to StoreKit. Never compiled
    /// into a release build.
    enum SimulatedAccess: String, CaseIterable, Identifiable {
        case pro, trial, founder, lapsed, none

        var id: String { rawValue }

        func access(now: Date) -> ProAccess {
            switch self {
            case .pro: .pro(.annual)
            // Five days left, so the reminder two days before the end is
            // still in the future and can be seen pending.
            case .trial: .trial(.annual, ends: now.addingTimeInterval(5 * 86_400))
            case .founder: .founder
            case .lapsed: .lapsed
            case .none: .none
            }
        }
    }

    /// Which state is being simulated. The trial's end is fixed at the moment
    /// it is chosen, so `access` is one value until the choice changes. Kept
    /// in `defaults` until it is handed back to StoreKit.
    var debugAccess: SimulatedAccess? {
        didSet {
            simulated = debugAccess?.access(now: .now)
            defaults.set(debugAccess?.rawValue, forKey: Self.debugAccessKey)
        }
    }

    static let debugAccessKey = "forge.debug.simulatedAccess.v1"

    private(set) var simulated: ProAccess?
    #endif
}

/// A purchase StoreKit has just verified, reduced to what the entitlement needs.
/// See `ForgeStore.recentPurchase`.
struct RecentPurchase: Equatable, Sendable {
    let product: PremiumProduct
    /// Nil for lifetime, which does not lapse.
    let expirationDate: Date?
    /// Whether it began the free week.
    var isTrial: Bool = false
}

/// One entitlement StoreKit vouched for, reduced to what choosing needs.
struct EntitlementCandidate: Equatable, Sendable {
    let productID: String
    let expirationDate: Date?
    let revocationDate: Date?
    let jws: String
}

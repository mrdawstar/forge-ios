import Foundation
import StoreKit

/// Everything Forge knows about what has been bought.
///
/// The only thing in the app that talks to StoreKit. Nothing is banked here that
/// the system already knows: the entitlement is read back out of
/// `Transaction.currentEntitlements` on every refresh rather than written down
/// when a purchase succeeds, for the same reason `ProgressStore` computes the
/// streak instead of storing it. A receipt cached in `UserDefaults` is a second
/// answer to "has this person paid", and the first time it disagrees with the
/// App Store it does so on a phone nobody can reach.
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
    private(set) var monthly: Product?
    private(set) var annual: Product?
    private(set) var lifetime: Product?
    private(set) var entitlement: PremiumEntitlement = .free
    /// Which plan the entitlement comes from, for Settings to name. Nil for
    /// somebody on the free tier.
    private(set) var activePlan: PremiumProduct?
    /// Whether the entitlement has been read at least once since launch.
    ///
    /// `entitlement` starts at `.free` before StoreKit has answered, and
    /// nothing that takes something *away* — the accent falling back to Forge
    /// blue — may act on that placeholder. See `ContentView`.
    private(set) var hasReadEntitlement = false
    /// Whether this Apple Account can still take the annual plan's free trial.
    ///
    /// Asked of StoreKit rather than assumed: somebody who has already had a
    /// trial in this subscription group is not offered a second one, and the
    /// paywall must not print "7 days free" to them.
    private(set) var isTrialEligible = false

    /// The purchase currently in flight, so exactly one button can show a
    /// spinner and no button can be pressed twice.
    private(set) var pending: Product.ID?
    /// Set when something went wrong in a way worth saying out loud. Cancelling
    /// is not one of those things.
    private(set) var failure: String?

    /// Whether a restore is running. Separate from `pending` because it belongs
    /// to no product.
    private(set) var isRestoring = false

    /// Held so it is not deallocated out from under the app. There is no
    /// `deinit` cancelling it on purpose: one store is built at launch and lives
    /// as long as the process, so the only thing a teardown path would add is a
    /// nonisolated hop for a case that never happens.
    private var updates: Task<Void, Never>?

    // MARK: Reading

    var isPremium: Bool {
        #if DEBUG
        if let debugPremium { return debugPremium }
        #endif
        return entitlement.isPremium
    }

    /// Every product that loaded, in the order the paywall shows them:
    /// annual, monthly, lifetime.
    var offerings: [Product] { PremiumProduct.displayOrder.compactMap(product(for:)) }

    func product(for plan: PremiumProduct) -> Product? {
        switch plan {
        case .monthly: monthly
        case .annual: annual
        case .lifetime: lifetime
        }
    }

    /// The trial, in the terms the App Store gave us rather than words of our
    /// own. Nil when the offer is not there — somebody who has already used it,
    /// or a build whose product could not be loaded.
    var trial: Product.SubscriptionOffer? {
        guard isTrialEligible,
              let offer = annual?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial
        else { return nil }
        return offer
    }

    // MARK: Lifetime of the object

    init() {
        // Claimed before anything is loaded. A purchase approved on another
        // device, a renewal, a refund or a family-sharing change all arrive
        // here, and the listener has to be running before the first await or
        // one of them can land in the gap.
        updates = listenForUpdates()
        Task { await refresh() }
    }

    /// Load the products and re-read what is owned. Safe to call again — the
    /// paywall's retry runs exactly this.
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
                case .monthly: monthly = product
                case .annual: annual = product
                case .lifetime: lifetime = product
                case nil: break
                }
            }
            if let subscription = annual?.subscription {
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
    func refreshEntitlement() async {
        var owned: [PremiumProduct] = []

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? verified(result) else { continue }
            guard transaction.revocationDate == nil else { continue }
            guard let product = PremiumProduct(id: transaction.productID) else { continue }
            owned.append(product)
        }

        // Lifetime outranks a subscription — see `PremiumEntitlement.resolve`.
        entitlement = PremiumEntitlement.resolve(owned)
        activePlan = PremiumEntitlement.plan(among: owned)
        hasReadEntitlement = true
    }

    /// Everything the App Store tells us after the fact: a renewal, a refund, a
    /// purchase approved by a parent, a plan bought on another device.
    private func listenForUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                guard let transaction = try? self.verified(result) else { continue }
                await transaction.finish()
                await self.refreshEntitlement()
            }
        }
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
                // Finished only after the entitlement has been re-read, so the
                // screen is never dismissed a frame before it is true.
                await refreshEntitlement()
                await transaction.finish()
                let startedTrial = transaction.offer?.type == .introductory
                    && transaction.offer?.paymentMode == .freeTrial
                if startedTrial { isTrialEligible = false }
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

        if !isPremium {
            failure = "Nothing to restore on this Apple Account."
        }
        return isPremium
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
    /// device are considered, so an unverified one is never even sent.
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
    /// Forces the entitlement on or off, so both sides of every gate can be
    /// looked at without a sandbox account. Nil hands the answer back to
    /// StoreKit. Never compiled into a release build.
    var debugPremium: Bool?
    #endif
}

/// One entitlement StoreKit vouched for, reduced to what choosing needs.
struct EntitlementCandidate: Equatable, Sendable {
    let productID: String
    let expirationDate: Date?
    let revocationDate: Date?
    let jws: String
}

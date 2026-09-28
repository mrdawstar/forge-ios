import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import Forge

/// Forge Pro: what is sold, what it unlocks, and when Forge is allowed to ask.
///
/// Three promises are held here and nowhere else:
///
/// - **Each door opens at most once, in order, and never over the day.** See
///   `PremiumInvitation`, which replaces 1.0's "asks once, ever" on purpose.
/// - **Only the reading is sold, never the record.** The gates are exactly
///   three — accents 2–8, Plan in words, the Weekly Reading — and Forge blue is
///   free.
/// - **The products are the same three strings everywhere.** `Premium.swift`,
///   `Forge.storekit` and (in `supabase/`) `PREMIUM_PRODUCTS`.
@MainActor
@Suite("Forge Pro: doors")
struct PremiumDoorTests {

    private func makeInvitation() -> PremiumInvitation {
        PremiumInvitation(
            defaults: UserDefaults(suiteName: "forge.doors.\(UUID().uuidString)") ?? .standard
        )
    }

    /// Free, past the first run, and between days.
    private let quiet = PremiumInvitation.Moment(
        isPremium: false, hasCompletedFirstRun: true, isDayInProgress: false
    )

    @Test("Each door opens once and never again")
    func once() {
        let invitation = makeInvitation()
        for door in PremiumInvitation.Door.allCases {
            let fresh = makeInvitation()
            #expect(fresh.claim(door, at: quiet))
            #expect(!fresh.claim(door, at: quiet))
            #expect(!fresh.isOpen(door, at: quiet))
        }
        // Asking is not spending.
        #expect(invitation.isOpen(.firstBlade, at: quiet))
        #expect(invitation.isOpen(.firstBlade, at: quiet))
        #expect(invitation.shown.isEmpty)
    }

    @Test("The three doors open in order: blade, reading, chapter")
    func inOrder() {
        let invitation = makeInvitation()
        #expect(invitation.claim(.firstBlade, at: quiet))
        #expect(invitation.claim(.weeklyReading, at: quiet))
        #expect(invitation.claim(.chapterClose, at: quiet))
        #expect(invitation.shown == [.firstBlade, .weeklyReading, .chapterClose])
        #expect(PremiumInvitation.Door.allCases.sorted() == [.firstBlade, .weeklyReading, .chapterClose])
    }

    /// An upgrade from 1.0 with every blade already earned reaches a review
    /// before any blade. The blade door must not open behind it.
    @Test("A later door retires the earlier ones; nothing opens out of order")
    func neverBackwards() {
        let invitation = makeInvitation()
        #expect(invitation.claim(.weeklyReading, at: quiet))
        #expect(!invitation.isOpen(.firstBlade, at: quiet))
        #expect(invitation.isOpen(.chapterClose, at: quiet))

        let skipped = makeInvitation()
        #expect(skipped.claim(.chapterClose, at: quiet))
        #expect(!skipped.isOpen(.firstBlade, at: quiet))
        #expect(!skipped.isOpen(.weeklyReading, at: quiet))
    }

    @Test("No door opens during the day, the first run, or for Pro — and none is spent trying")
    func neverDuringTheDay() {
        let invitation = makeInvitation()
        let busy = PremiumInvitation.Moment(isPremium: false, hasCompletedFirstRun: true, isDayInProgress: true)
        let onboarding = PremiumInvitation.Moment(isPremium: false, hasCompletedFirstRun: false, isDayInProgress: false)
        let pro = PremiumInvitation.Moment(isPremium: true, hasCompletedFirstRun: true, isDayInProgress: false)

        for door in PremiumInvitation.Door.allCases {
            #expect(!invitation.claim(door, at: busy))
            #expect(!invitation.claim(door, at: onboarding))
            #expect(!invitation.claim(door, at: pro))
        }
        #expect(invitation.shown.isEmpty)
        // Still there for a quiet moment afterwards.
        #expect(invitation.claim(.firstBlade, at: quiet))
    }

    @Test("Doors are remembered in the App Group suite, and the key migrates")
    func persisted() {
        let defaults = UserDefaults(suiteName: "forge.doors.\(UUID().uuidString)") ?? .standard
        PremiumInvitation(defaults: defaults).markShown(.firstBlade)
        PremiumInvitation(defaults: defaults).markShown(.firstBlade)
        #expect(PremiumInvitation(defaults: defaults).shown == [.firstBlade])
        #expect(defaults.array(forKey: PremiumInvitation.key) as? [String] == ["first_blade"])
        #expect(ForgeShared.ownedKeys.contains(PremiumInvitation.key))

        // Anything unrecognised is ignored rather than trusted.
        defaults.set(["first_blade", "somewhere_else"], forKey: PremiumInvitation.key)
        #expect(PremiumInvitation(defaults: defaults).shown == [.firstBlade])
    }

    @Test("Each door reports itself under its own name")
    func telemetryNames() {
        #expect(PremiumInvitation.Door.firstBlade.telemetry == .firstBlade)
        #expect(PremiumInvitation.Door.weeklyReading.telemetry == .weeklyReading)
        #expect(PremiumInvitation.Door.chapterClose.telemetry == .chapterClose)
        #expect(ForgeTelemetry.PaywallDoor.allCases.map(\.rawValue) == [
            "first_blade", "weekly_reading", "chapter_close", "accent", "plan", "settings",
        ])
        #expect(ForgeTelemetry.Event.paywallView(.weeklyReading).parameters == ["door": "weekly_reading"])
        #expect(ForgeTelemetry.Event.paywallDismissed(.chapterClose).parameters == ["door": "chapter_close"])
        #expect(ForgeTelemetry.Event.trialStarted(.annual).name == "trial_started")
        #expect(ForgeTelemetry.Event.purchaseCompleted(.monthly).parameters == ["plan": "monthly"])
    }
}

@Suite("Forge Pro: gates")
struct PremiumGateTests {

    @Test("Accent 1 is free; accents 2–8 need Pro")
    func accents() {
        #expect(ForgeThemeAccent.allCases.count == 8)
        #expect(ForgeThemeAccent.allCases.first == PremiumGate.freeAccent)
        #expect(PremiumGate.freeAccent == .forge)

        let locked = ForgeThemeAccent.allCases.filter { PremiumGate.isLocked($0, isPremium: false) }
        #expect(locked.count == 7)
        #expect(!locked.contains(.forge))
        #expect(ForgeThemeAccent.allCases.allSatisfy { !PremiumGate.isLocked($0, isPremium: true) })
    }

    @Test("A lapsed install falls back to Forge blue; Pro keeps its choice")
    func wearable() {
        #expect(PremiumGate.wearable(.ember, isPremium: false) == .forge)
        #expect(PremiumGate.wearable(.forge, isPremium: false) == .forge)
        #expect(PremiumGate.wearable(.ember, isPremium: true) == .ember)
    }

    @Test("Plan in words and the Weekly Reading are Pro, and nothing else is gated")
    func features() {
        #expect(!PremiumGate.canPlanInWords(isPremium: false))
        #expect(PremiumGate.canPlanInWords(isPremium: true))
        #expect(!PremiumGate.showsWeeklyReading(isPremium: false))
        #expect(PremiumGate.showsWeeklyReading(isPremium: true))
        #expect(ProFeature.allCases.map(\.title) == ["Weekly Reading", "Plan in your own words", "Eight accents"])
    }
}

@Suite("Forge Pro: products and entitlement")
struct PremiumProductTests {

    @Test("Three products, monthly included, in paywall order")
    func products() {
        #expect(Set(PremiumProduct.identifiers) == [
            "com.dawid.forge.premium.monthly",
            "com.dawid.forge.premium.annual",
            "com.dawid.forge.premium.lifetime",
        ])
        #expect(PremiumProduct.displayOrder == [.annual, .monthly, .lifetime])
        #expect(PremiumProduct.monthly.isSubscription)
        #expect(PremiumProduct.annual.isSubscription)
        #expect(!PremiumProduct.lifetime.isSubscription)
        #expect(PremiumProduct(id: "com.dawid.forge.tip") == nil)
    }

    @Test("Lifetime outranks a subscription; either subscription is Pro")
    func resolve() {
        #expect(PremiumEntitlement.resolve([]) == .free)
        #expect(PremiumEntitlement.resolve([.monthly]) == .subscribed)
        #expect(PremiumEntitlement.resolve([.annual]) == .subscribed)
        #expect(PremiumEntitlement.resolve([.monthly, .lifetime]) == .lifetime)
        #expect(!PremiumEntitlement.free.isPremium)
        #expect(PremiumEntitlement.subscribed.isPremium)

        #expect(PremiumEntitlement.plan(among: []) == nil)
        #expect(PremiumEntitlement.plan(among: [.monthly]) == .monthly)
        #expect(PremiumEntitlement.plan(among: [.monthly, .annual]) == .annual)
        #expect(PremiumEntitlement.plan(among: [.annual, .lifetime]) == .lifetime)
    }

    @Test("A live monthly subscription is proof of purchase for the model")
    func monthlyProof() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let monthly = EntitlementCandidate(
            productID: PremiumProduct.monthly.rawValue,
            expirationDate: now.addingTimeInterval(86_400),
            revocationDate: nil,
            jws: "monthly"
        )
        #expect(ForgeStore.bestProof(among: [monthly], now: now) == "monthly")
    }

    /// Every figure is handed in, as StoreKit's `displayPrice` would be. The
    /// copy never owns a number.
    @Test("The price lines are built from StoreKit's values")
    func copy() {
        #expect(PremiumCopy.subscriptionLine(
            price: "$49.99", value: 1, unit: .year, freeTrial: (value: 1, unit: .week)
        ) == "7 days free, then $49.99/year")
        #expect(PremiumCopy.subscriptionLine(price: "$49.99", value: 1, unit: .year) == "$49.99/year")
        #expect(PremiumCopy.subscriptionLine(price: "$9.99", value: 1, unit: .month) == "$9.99/month")
        #expect(PremiumCopy.subscriptionLine(price: "€5", value: 3, unit: .month) == "€5 every 3 months")
        #expect(PremiumCopy.lifetimeLine(price: "$99.99") == "$99.99 once")
        #expect(PremiumCopy.trialLength(value: 3, unit: .day) == "3 days")
        #expect(PremiumCopy.trialLength(value: 1, unit: .month) == "1 month")
    }

    /// The StoreKit configuration Xcode runs the app against, read as the file
    /// it is. If a price, a period or the trial drifts from what was decided,
    /// this is where it shows.
    @Test("Forge.storekit sells exactly what Premium.swift declares")
    func storekitFile() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Forge/Forge.storekit")
        let json = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )

        let products = try #require(json["products"] as? [[String: Any]])
        let groups = try #require(json["subscriptionGroups"] as? [[String: Any]])
        let subscriptions = try #require(groups.first?["subscriptions"] as? [[String: Any]])
        #expect(groups.count == 1)

        func find(_ plan: PremiumProduct, in list: [[String: Any]]) -> [String: Any]? {
            list.first { $0["productID"] as? String == plan.rawValue }
        }

        let lifetime = try #require(find(.lifetime, in: products))
        #expect(lifetime["type"] as? String == "NonConsumable")
        #expect(lifetime["displayPrice"] as? String == "99.99")

        let annual = try #require(find(.annual, in: subscriptions))
        #expect(annual["displayPrice"] as? String == "49.99")
        #expect(annual["recurringSubscriptionPeriod"] as? String == "P1Y")
        let intro = try #require(annual["introductoryOffer"] as? [String: Any])
        #expect(intro["paymentMode"] as? String == "free")
        #expect(intro["subscriptionPeriod"] as? String == "P1W")

        let monthly = try #require(find(.monthly, in: subscriptions))
        #expect(monthly["displayPrice"] as? String == "9.99")
        #expect(monthly["recurringSubscriptionPeriod"] as? String == "P1M")
        #expect(!(monthly["introductoryOffer"] is [String: Any]))

        let every = (products + subscriptions).compactMap { $0["productID"] as? String }
        #expect(Set(every) == Set(PremiumProduct.identifiers))
        #expect(every.count == PremiumProduct.allCases.count)
    }
}

/// The real StoreKit path, against `Forge.storekit` in an `SKTestSession`.
///
/// Serialized: StoreKit's test environment is one per process, and two suites
/// buying at once would read each other's transactions.
@MainActor
@Suite("Forge Pro: StoreKit", .serialized)
struct ForgeStoreKitTests {

    private func makeSession() throws -> SKTestSession {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Forge/Forge.storekit")
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    @Test("All three products load, with the annual trial")
    func loads() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let store = ForgeStore()
        await store.refresh()

        #expect(store.status == .ready)
        #expect(store.offerings.map(\.id) == PremiumProduct.displayOrder.map(\.rawValue))
        #expect(store.monthly?.price == Decimal(string: "9.99"))
        #expect(store.annual?.price == Decimal(string: "49.99"))
        #expect(store.lifetime?.price == Decimal(string: "99.99"))
        #expect(store.monthly?.subscription?.subscriptionPeriod.unit == .month)
        #expect(store.annual?.subscription?.subscriptionPeriod.unit == .year)

        let trial = try #require(store.trial)
        #expect(trial.paymentMode == .freeTrial)
        #expect(PremiumCopy.trialLength(value: trial.period.value, unit: trial.period.unit) == "7 days")
        #expect(store.entitlement == .free)
        #expect(store.hasReadEntitlement)
    }

    @Test("Monthly is a subscription entitlement")
    func monthly() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        _ = try await session.buyProduct(identifier: PremiumProduct.monthly.rawValue)

        let store = ForgeStore()
        await store.refresh()
        #expect(store.entitlement == .subscribed)
        #expect(store.activePlan == .monthly)
        #expect(store.isPremium)
    }

    @Test("Lifetime outranks a subscription bought alongside it")
    func lifetime() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        _ = try await session.buyProduct(identifier: PremiumProduct.annual.rawValue)
        _ = try await session.buyProduct(identifier: PremiumProduct.lifetime.rawValue)

        let store = ForgeStore()
        await store.refresh()
        #expect(store.entitlement == .lifetime)
        #expect(store.activePlan == .lifetime)
    }

    @Test("Buying annual through the store starts the trial, and says so")
    func annualTrial() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let store = ForgeStore()
        await store.refresh()
        let annual = try #require(store.annual)

        let outcome = await store.purchase(annual)
        #expect(outcome == .bought(startedTrial: true))
        #expect(store.entitlement == .subscribed)
        #expect(store.activePlan == .annual)
        // Taken once, and not offered again.
        #expect(store.trial == nil)
    }

    @Test("An expired subscription is free again")
    func expiry() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let transaction = try await session.buyProduct(identifier: PremiumProduct.monthly.rawValue)
        try session.expireSubscription(productIdentifier: transaction.productID)

        let store = ForgeStore()
        await store.refresh()
        #expect(store.entitlement == .free)
        #expect(store.activePlan == nil)
    }
}

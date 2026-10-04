import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import Forge

/// Forge Pro (1.1): a hard paywall with a free week.
///
/// The promises held here and nowhere else:
///
/// - **The products are the same four strings everywhere**: `Premium.swift`,
///   `Forge.storekit`, `PREMIUM_PRODUCTS` in the backend and the table in
///   `APP_STORE.md`.
/// - **The record is never locked.** Only what makes new days is sold, and
///   the AI; history, blades, Becoming, the reviews, the Proof Card and the
///   widgets are readable to everybody, whatever they own.
/// - **A founder is a founder in production only**, and a build of 1.1 can
///   never be mistaken for one of theirs.
/// - **Every trial word depends on StoreKit's eligibility**, and every price on
///   StoreKit's own values.
@Suite("Forge Pro: products")
struct PremiumProductTests {

    private func repository(_ path: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path)
    }

    @Test("Four products, two of them on the paywall, annual first")
    func products() {
        #expect(Set(PremiumProduct.identifiers) == [
            "com.dawid.forge.premium.annual",
            "com.dawid.forge.premium.annual.offer",
            "com.dawid.forge.premium.monthly",
            "com.dawid.forge.premium.lifetime",
        ])
        #expect(PremiumProduct.paywallPlans == [.annual, .monthly])
        #expect(!PremiumProduct.paywallPlans.contains(.lifetime), "lifetime is sold in Settings only")
        #expect(PremiumProduct.allCases.filter(\.isSubscription) == [.annual, .annualOffer, .monthly])
        #expect(PremiumProduct.annualOffer.planName == "Annual")
        #expect(PremiumProduct(id: "com.dawid.forge.tip") == nil)
        #expect(PremiumProduct.allCases.map(\.telemetryName) == ["annual", "annual_offer", "monthly", "lifetime"])
    }

    /// The four places the identifiers live, read as the files they are.
    @Test("The product ids agree in Premium.swift, Forge.storekit, storekit.ts and APP_STORE.md")
    func productsAgree() throws {
        let declared = Set(PremiumProduct.identifiers)

        // Forge.storekit.
        let storekit = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: repository("Forge/Forge.storekit"))) as? [String: Any]
        )
        let products = try #require(storekit["products"] as? [[String: Any]])
        let groups = try #require(storekit["subscriptionGroups"] as? [[String: Any]])
        let subscriptions = groups.flatMap { $0["subscriptions"] as? [[String: Any]] ?? [] }
        let inStoreKit = (products + subscriptions).compactMap { $0["productID"] as? String }
        #expect(Set(inStoreKit) == declared)
        #expect(inStoreKit.count == declared.count)

        // supabase/functions/forge-ai/storekit.ts, PREMIUM_PRODUCTS.
        let server = try String(contentsOf: repository("supabase/functions/forge-ai/storekit.ts"), encoding: .utf8)
        let table = try #require(server.components(separatedBy: "export const PREMIUM_PRODUCTS").last?
            .components(separatedBy: "};").first)
        var kinds: [String: String] = [:]
        for line in table.split(separator: "\n") {
            let parts = line.split(separator: "\"").map(String.init)
            guard parts.count >= 4, parts[1].hasPrefix("com.dawid.forge.") else { continue }
            kinds[parts[1]] = parts[3]
        }
        #expect(Set(kinds.keys) == declared)
        for plan in PremiumProduct.allCases {
            #expect(kinds[plan.rawValue] == (plan.isSubscription ? "renewable" : "lifetime"), Comment(rawValue: plan.rawValue))
        }

        // docs/APP_STORE.md: every product id the document names.
        let document = try String(contentsOf: repository("docs/APP_STORE.md"), encoding: .utf8)
        let named = Set(
            document.components(separatedBy: "`")
                .filter { $0.hasPrefix("com.dawid.forge.premium.") && !$0.contains(" ") }
        )
        #expect(named == declared)
    }

    /// The configuration Xcode runs the app against. If a price, a period or a
    /// free week drifts from what was decided, this is where it shows.
    @Test("Forge.storekit: $49.99 a year with a free week, the offer at $29.99 with one, $12.99 a month, $129.99 once")
    func storekitFile() throws {
        let json = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: repository("Forge/Forge.storekit"))) as? [String: Any]
        )
        let products = try #require(json["products"] as? [[String: Any]])
        let groups = try #require(json["subscriptionGroups"] as? [[String: Any]])
        #expect(groups.count == 1)
        #expect(groups.first?["name"] as? String == "Forge Pro")
        let subscriptions = try #require(groups.first?["subscriptions"] as? [[String: Any]])

        func find(_ plan: PremiumProduct, in list: [[String: Any]]) -> [String: Any]? {
            list.first { $0["productID"] as? String == plan.rawValue }
        }
        func freeWeek(_ product: [String: Any]) -> Bool {
            let intro = product["introductoryOffer"] as? [String: Any]
            return intro?["paymentMode"] as? String == "free" && intro?["subscriptionPeriod"] as? String == "P1W"
        }

        let lifetime = try #require(find(.lifetime, in: products))
        #expect(lifetime["type"] as? String == "NonConsumable")
        #expect(lifetime["displayPrice"] as? String == "129.99")

        let annual = try #require(find(.annual, in: subscriptions))
        #expect(annual["displayPrice"] as? String == "49.99")
        #expect(annual["recurringSubscriptionPeriod"] as? String == "P1Y")
        #expect(freeWeek(annual))

        let offer = try #require(find(.annualOffer, in: subscriptions))
        #expect(offer["displayPrice"] as? String == "29.99")
        #expect(offer["recurringSubscriptionPeriod"] as? String == "P1Y")
        #expect(freeWeek(offer))

        let monthly = try #require(find(.monthly, in: subscriptions))
        #expect(monthly["displayPrice"] as? String == "12.99")
        #expect(monthly["recurringSubscriptionPeriod"] as? String == "P1M")
        #expect(!(monthly["introductoryOffer"] is [String: Any]))

        // One group, one level: switching between the three is a crossgrade.
        #expect(Set(subscriptions.compactMap { $0["groupNumber"] as? Int }) == [1])
    }

    /// `AppTransaction.originalAppVersion` is the build number on iOS. If this
    /// build were numbered at or below the last 1.0.1 build, every new install
    /// would read as a founder.
    @Test("This build is numbered above the last founder build")
    func buildIsAboveFounders() throws {
        let version = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
        let build = try #require(Founder.buildNumber(version))
        #expect(build > Founder.lastFounderBuild)
        #expect(Founder.lastFounderBuild == 2)
    }

    /// What an upload checks before anybody reads the app (§17.7): the widget
    /// extension carries the app's own version and build — a mismatch is
    /// refused at upload — and the app says it uses only exempt encryption
    /// (HTTPS through the system; the one hash is SHA-256 in the dormant
    /// account code), so a build is not held at "Missing Compliance".
    @Test("The widget extension's version and build are the app's, and the encryption answer is in the build")
    func uploadable() throws {
        let app = try #require(Bundle.main.infoDictionary)
        let widgets = try #require(Bundle(url: Bundle.main.bundleURL
            .appendingPathComponent("PlugIns/ForgeWidgets.appex"))?.infoDictionary)
        #expect(app["CFBundleShortVersionString"] as? String == widgets["CFBundleShortVersionString"] as? String)
        #expect(app["CFBundleVersion"] as? String == widgets["CFBundleVersion"] as? String)
        #expect(app["ITSAppUsesNonExemptEncryption"] as? Bool == false)
    }

    @Test("Lifetime outranks a subscription; the plan named is the longest")
    func entitlement() {
        #expect(PremiumEntitlement.resolve([]) == .free)
        #expect(PremiumEntitlement.resolve([.monthly]) == .subscribed)
        #expect(PremiumEntitlement.resolve([.annualOffer]) == .subscribed)
        #expect(PremiumEntitlement.resolve([.monthly, .lifetime]) == .lifetime)
        #expect(PremiumEntitlement.plan(among: []) == nil)
        #expect(PremiumEntitlement.plan(among: [.monthly, .annualOffer]) == .annualOffer)
        #expect(PremiumEntitlement.plan(among: [.annual, .lifetime]) == .lifetime)
    }

    /// `Product.purchase()` returns before `currentEntitlements` lists what it
    /// sold. The purchase counts until the list has it, and no longer.
    @Test("A purchase counts until StoreKit lists it, and not after it lapses")
    func recentPurchaseCarries() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let trial = RecentPurchase(product: .annual, expirationDate: now.addingTimeInterval(7 * 86_400), isTrial: true)

        // Nothing just bought: the list is the answer.
        let nothing = ForgeStore.owned(listed: [], recent: nil, now: now)
        #expect(nothing.owned.isEmpty)
        #expect(nothing.recent == nil)
        #expect(ForgeStore.owned(listed: [.monthly], recent: nil, now: now).owned == [.monthly])

        // Bought, not listed yet: counted, and still carried.
        let unlisted = ForgeStore.owned(listed: [], recent: trial, now: now)
        #expect(unlisted.owned == [.annual])
        #expect(unlisted.recent == trial)
        #expect(PremiumEntitlement.resolve(unlisted.owned) == .subscribed)

        // Listed: the list is the answer again, and the carry ends.
        let listed = ForgeStore.owned(listed: [.annual], recent: trial, now: now)
        #expect(listed.owned == [.annual])
        #expect(listed.recent == nil)

        // Past its expiry without ever being listed: it no longer counts.
        let later = now.addingTimeInterval(8 * 86_400)
        let lapsed = ForgeStore.owned(listed: [], recent: trial, now: later)
        #expect(lapsed.owned.isEmpty)
        #expect(lapsed.recent == nil)

        // Lifetime does not lapse, and outranks what is listed beside it.
        let lifetime = RecentPurchase(product: .lifetime, expirationDate: nil)
        let both = ForgeStore.owned(listed: [.monthly], recent: lifetime, now: later)
        #expect(PremiumEntitlement.resolve(both.owned) == .lifetime)
        #expect(both.recent == lifetime)
    }

    /// `Forge/ForgeSimulator.entitlements` exists for one reason: storekitd
    /// accepts an `SKTestSession` only from an app carrying get-task-allow
    /// (FORGE_CONTEXT §14). Anything else that differed from the shipping
    /// entitlements would be the Simulator testing a different app.
    @Test("The Simulator build's entitlements are the shipping ones plus get-task-allow")
    func simulatorEntitlements() throws {
        func read(_ name: String) throws -> [String: Any] {
            let data = try Data(contentsOf: repository("Forge/\(name)"))
            return try #require(
                try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            )
        }
        let shipping = try read("Forge.entitlements")
        var simulator = try read("ForgeSimulator.entitlements")

        #expect(shipping["get-task-allow"] == nil, "a shipping build must never ask for it")
        #expect(simulator.removeValue(forKey: "get-task-allow") as? Bool == true)
        #expect(NSDictionary(dictionary: simulator).isEqual(to: shipping))
    }

    @Test("A live subscription, the offer included, is proof of purchase for the model")
    func subscriptionProof() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        for plan in [PremiumProduct.monthly, .annualOffer] {
            let candidate = EntitlementCandidate(
                productID: plan.rawValue,
                expirationDate: now.addingTimeInterval(86_400),
                revocationDate: nil,
                jws: plan.rawValue
            )
            #expect(ForgeStore.bestProof(among: [candidate], now: now) == plan.rawValue)
        }
    }

    @Test("Every key Forge Pro writes is listed in the App Group, and the doors' key is gone")
    func keys() {
        for key in [Founder.key, ExitOffer.key, TrialReminder.key, RatingPrompt.key] {
            #expect(ForgeShared.ownedKeys.contains(key), Comment(rawValue: key))
        }
        #expect(!ForgeShared.ownedKeys.contains("forge.paywallDoors.v1"))
    }
}

// MARK: - Who has what

@Suite("Forge Pro: who has what")
struct ProAccessTests {

    private let ends = Date(timeIntervalSince1970: 2_000_000)

    private func access(
        answered: Bool = true,
        owned: [PremiumProduct] = [],
        subscription: ActiveSubscription? = nil,
        hadPurchase: Bool = false,
        founder: Bool = false
    ) -> ProAccess {
        ProAccess.resolve(EntitlementFacts(
            hasAnswered: answered, owned: owned, subscription: subscription,
            hadPurchase: hadPurchase, isFounder: founder
        ))
    }

    @Test("Until StoreKit has answered, nothing is decided — and nothing is locked")
    func unknown() {
        #expect(access(answered: false, founder: true) == .unknown)
        #expect(access(answered: false) == .unknown)
        #expect(ProAccess.unknown.keepsNewDays)
        #expect(ProAccess.unknown.hasAI)
    }

    @Test("Lifetime beats a subscription")
    func lifetimeFirst() {
        let annual = ActiveSubscription(plan: .annual, expires: ends, isTrial: false)
        #expect(access(owned: [.annual, .lifetime], subscription: annual) == .pro(.lifetime))
    }

    @Test("A free week is a trial with its end; a paid period is Pro")
    func trialAndPro() {
        let trial = ActiveSubscription(plan: .annual, expires: ends, isTrial: true)
        #expect(access(owned: [.annual], subscription: trial) == .trial(.annual, ends: ends))
        let offer = ActiveSubscription(plan: .annualOffer, expires: ends, isTrial: true)
        #expect(access(owned: [.annualOffer], subscription: offer) == .trial(.annualOffer, ends: ends))
        let paid = ActiveSubscription(plan: .monthly, expires: ends, isTrial: false)
        #expect(access(owned: [.monthly], subscription: paid) == .pro(.monthly))
        // Listed, but without the details: Pro, never a guess at a trial.
        #expect(access(owned: [.monthly]) == .pro(.monthly))
    }

    @Test("A founder is a founder until they subscribe, and is never lapsed")
    func founder() {
        #expect(access(founder: true) == .founder)
        #expect(access(hadPurchase: true, founder: true) == .founder)
        let paid = ActiveSubscription(plan: .annual, expires: ends, isTrial: false)
        #expect(access(owned: [.annual], subscription: paid, founder: true) == .pro(.annual))
        #expect(ProAccess.founder.keepsNewDays)
        #expect(!ProAccess.founder.hasAI, "the AI is not a founder's")
    }

    @Test("Lapsed is only said of somebody who had it; never subscribed is none")
    func lapsedAndNone() {
        #expect(access(hadPurchase: true) == .lapsed)
        #expect(access() == .none)
        for locked in [ProAccess.lapsed, .none] {
            #expect(!locked.keepsNewDays)
            #expect(!locked.hasAI)
            #expect(!locked.hasSubscription)
        }
    }

    @Test("Manage Subscription has something to manage only with a live subscription")
    func subscriptionToManage() {
        #expect(ProAccess.trial(.annual, ends: ends).hasSubscription)
        #expect(ProAccess.pro(.monthly).hasSubscription)
        #expect(!ProAccess.pro(.lifetime).hasSubscription)
        #expect(!ProAccess.founder.hasSubscription)
    }
}

// MARK: - Founders

@Suite("Forge Pro: founders")
struct FounderTests {

    private func suite() -> UserDefaults {
        UserDefaults(suiteName: "forge.founder.\(UUID().uuidString)") ?? .standard
    }

    private func history(_ days: Int) throws -> Data {
        try JSONSerialization.data(withJSONObject: Array(repeating: ["day": "2026-09-01"], count: days))
    }

    @Test("A completed first run left by 1.0 makes a founder, once")
    func fromFirstRun() {
        let defaults = suite()
        defaults.set(true, forKey: Founder.firstRunKey)
        #expect(Founder.recordOnFirstLaunch(in: defaults))
        #expect(Founder.isRecorded(in: defaults))
        #expect(!Founder.recordOnFirstLaunch(in: defaults), "once")
    }

    @Test("Any history makes a founder; an empty history does not")
    func fromHistory() throws {
        let kept = suite()
        kept.set(try history(3), forKey: Founder.historyKey)
        #expect(Founder.recordOnFirstLaunch(in: kept))

        let empty = suite()
        empty.set(try history(0), forKey: Founder.historyKey)
        #expect(!Founder.recordOnFirstLaunch(in: empty))
        #expect(!Founder.isRecorded(in: empty))
    }

    /// The check runs before anything writes. After it, every install holds
    /// history — so history arriving later must not make a founder.
    @Test("A new install is checked once, and its own history never makes it a founder")
    func newInstall() throws {
        let defaults = suite()
        #expect(!Founder.recordOnFirstLaunch(in: defaults))
        #expect(defaults.object(forKey: Founder.key) as? Bool == false, "checked, and not one")
        defaults.set(try history(9), forKey: Founder.historyKey)
        defaults.set(true, forKey: Founder.firstRunKey)
        #expect(!Founder.recordOnFirstLaunch(in: defaults))
        #expect(!Founder.isRecorded(in: defaults))
    }

    @Test("A founder is never unset; the App Store can still raise one")
    func neverUnset() {
        let defaults = suite()
        #expect(!Founder.recordOnFirstLaunch(in: defaults))
        #expect(Founder.record(in: defaults), "the App Store vouched")
        #expect(!Founder.record(in: defaults))
        #expect(!Founder.recordOnFirstLaunch(in: defaults))
        #expect(Founder.isRecorded(in: defaults))
    }

    @Test("The App Store's rule: production, and first downloaded as build 2 or earlier")
    func appTransaction() {
        #expect(Founder.isFounder(environment: .production, originalAppVersion: "2"))
        #expect(Founder.isFounder(environment: .production, originalAppVersion: "1"))
        #expect(!Founder.isFounder(environment: .production, originalAppVersion: "3"))
        #expect(!Founder.isFounder(environment: .production, originalAppVersion: "12"))
        #expect(!Founder.isFounder(environment: .production, originalAppVersion: "not a build"))
    }

    @Test("Never a founder in Sandbox or Xcode — App Review and TestFlight always meet the paywall")
    func neverInSandbox() {
        for environment in [AppStore.Environment.sandbox, .xcode] {
            // Sandbox always reports "1.0" as the original version.
            #expect(!Founder.isFounder(environment: environment, originalAppVersion: "1.0"))
            #expect(!Founder.isFounder(environment: environment, originalAppVersion: "2"))
            #expect(!Founder.counts(recorded: true, environment: environment))
        }
        #expect(Founder.counts(recorded: true, environment: .production))
        #expect(Founder.counts(recorded: true, environment: nil), "offline, the record stands")
        #expect(!Founder.counts(recorded: false, environment: .production))
    }

    @Test("A build number is the part before the first dot")
    func buildNumbers() {
        #expect(Founder.buildNumber("2") == 2)
        #expect(Founder.buildNumber("2.1") == 2)
        #expect(Founder.buildNumber(" 3 ") == 3)
        #expect(Founder.buildNumber("") == nil)
        #expect(Founder.buildNumber("one") == nil)
    }
}

// MARK: - The gates

@Suite("Forge Pro: the gates")
struct PremiumGateTests {

    private let every: [ProAccess] = [
        .unknown, .pro(.annual), .pro(.lifetime), .trial(.annual, ends: .now), .founder, .lapsed, .none,
    ]

    @Test("The record is never locked, for anybody, whatever they own")
    func recordStaysReadable() {
        let record = ProSurface.allCases.filter(\.isRecord)
        #expect(Set(record) == [.history, .blade, .blades, .becoming, .reviews, .proofCard, .widgets])
        for access in every {
            for surface in record {
                #expect(!PremiumGate.isLocked(surface, for: access), Comment(rawValue: "\(surface) for \(access)"))
            }
        }
    }

    @Test("New days, the Arcs and the challenge lock only for somebody lapsed or never subscribed")
    func practice() {
        for surface in [ProSurface.dayControls, .arcs, .dailyChallenge] {
            for access in every {
                let locked = access == .lapsed || access == .none
                #expect(PremiumGate.isLocked(surface, for: access) == locked, Comment(rawValue: "\(surface) for \(access)"))
            }
        }
    }

    @Test("The AI is a subscription's or a free week's — never a founder's")
    func ai() {
        for surface in [ProSurface.askForge, .weeklyReading, .planInWords] {
            #expect(PremiumGate.isLocked(surface, for: .founder))
            #expect(PremiumGate.isLocked(surface, for: .lapsed))
            #expect(PremiumGate.isLocked(surface, for: .none))
            #expect(!PremiumGate.isLocked(surface, for: .pro(.monthly)))
            #expect(!PremiumGate.isLocked(surface, for: .trial(.annual, ends: .now)))
            #expect(!PremiumGate.isLocked(surface, for: .unknown))
        }
    }

    @Test("The locked state never appears in the first run, or over a moment of the day")
    func lockedState() {
        #expect(PremiumGate.showsLockedState(for: .lapsed, hasCompletedFirstRun: true, isMomentOnScreen: false))
        #expect(PremiumGate.showsLockedState(for: .none, hasCompletedFirstRun: true, isMomentOnScreen: false))
        for access in [ProAccess.lapsed, .none] {
            #expect(!PremiumGate.showsLockedState(for: access, hasCompletedFirstRun: false, isMomentOnScreen: false))
            #expect(!PremiumGate.showsLockedState(for: access, hasCompletedFirstRun: true, isMomentOnScreen: true))
        }
        for access in [ProAccess.unknown, .founder, .pro(.annual), .trial(.annual, ends: .now)] {
            #expect(!PremiumGate.showsLockedState(for: access, hasCompletedFirstRun: true, isMomentOnScreen: false))
        }
    }

    @Test("The first run walks past the paywall only for somebody who already has the practice")
    func onboardingPaywall() {
        #expect(PremiumGate.passesOnboardingPaywall(.founder))
        #expect(PremiumGate.passesOnboardingPaywall(.pro(.annual)))
        #expect(PremiumGate.passesOnboardingPaywall(.trial(.annual, ends: .now)))
        #expect(!PremiumGate.passesOnboardingPaywall(.unknown), "it waits for StoreKit on the paywall")
        #expect(!PremiumGate.passesOnboardingPaywall(.none))
        #expect(!PremiumGate.passesOnboardingPaywall(.lapsed))
    }

    @Test("Accents go with new days; a lapsed install wears Forge blue")
    func accents() {
        #expect(ForgeThemeAccent.allCases.count == 8)
        #expect(PremiumGate.freeAccent == .forge)
        #expect(ForgeThemeAccent.allCases.filter { PremiumGate.isLocked(accent: $0, for: .lapsed) }.count == 7)
        #expect(ForgeThemeAccent.allCases.allSatisfy { !PremiumGate.isLocked(accent: $0, for: .founder) })
        #expect(PremiumGate.wearable(.ember, for: .lapsed) == .forge)
        #expect(PremiumGate.wearable(.ember, for: .unknown) == .ember, "never on a placeholder")
        #expect(PremiumGate.wearable(.ember, for: .trial(.annual, ends: .now)) == .ember)
    }
}

// MARK: - What the build has

@Suite("Forge Pro: what this build has")
struct FeatureAvailabilityTests {

    @Test("This build names the Arcs, the six stats, the blades, Apple Health and Ask Forge — everything is built")
    func current() {
        let features = ForgeFeatures.current
        #expect(features.arcs, "built in session S3")
        #expect(features.health, "built in session S5")
        #expect(features.askForge, "built in session S6")
        #expect(PaywallRow.rows() == [.arcs, .stats, .blades, .health, .askForge])
        #expect(PaywallRow.rows() == PaywallRow.allCases)
    }

    @Test("Each flag brings its own row, in the paywall's order")
    func flags() {
        var features = ForgeFeatures.current
        features.health = false
        features.arcs = false
        features.askForge = false
        #expect(PaywallRow.rows(in: features) == [.stats, .blades])
        features.arcs = true
        #expect(PaywallRow.rows(in: features) == [.arcs, .stats, .blades])
        features.health = true
        features.askForge = true
        #expect(PaywallRow.rows(in: features) == PaywallRow.allCases)
        features.stats = false
        #expect(!PaywallRow.rows(in: features).contains(.stats))
    }

    @Test("Each row is one line with no exclamation mark")
    func lines() {
        #expect(PaywallRow.stats.line == "Six stats, scored on what you actually do.")
        #expect(PaywallRow.blades.line == "A blade earned for every stretch of days you keep.")
        #expect(PaywallRow.arcs.line.contains("Monk Mode 30"))
        for row in PaywallRow.allCases {
            #expect(!row.line.contains("!"))
            #expect(!row.line.contains("\n"))
        }
    }
}

// MARK: - The words

@Suite("Forge Pro: the paywall's words")
struct PaywallCopyTests {

    private let usd = Decimal.FormatStyle.Currency(code: "USD", locale: Locale(identifier: "en_US"))

    @Test("With the free week on offer, the paywall says so — and the timeline promises the reminder")
    func eligible() {
        #expect(PremiumCopy.headline(trialDays: 7) == "Seven days free. Then decide.")
        #expect(PremiumCopy.trialBadge(days: 7) == "7 days free")
        #expect(PremiumCopy.buttonTitle(startsFreeWeek: true) == "Start my free week")
        #expect(PremiumCopy.cancelLine(startsFreeWeek: true) == "Cancel anytime in Settings. Nothing is charged today.")
        #expect(PremiumCopy.timeline(trialDays: 7, renewal: "$49.99", value: 1, unit: .year, reminds: true) == [
            PremiumCopy.Step(when: "Today", what: "Everything unlocked."),
            PremiumCopy.Step(when: "Day 5", what: "We remind you."),
            PremiumCopy.Step(when: "Day 7", what: "$49.99 for the year, unless you cancel before."),
        ])
        // Turned off, the reminder is not promised.
        #expect(PremiumCopy.timeline(trialDays: 7, renewal: "$49.99", value: 1, unit: .year, reminds: false)[1]
            == PremiumCopy.Step(when: "Day 5", what: "Two days left."))
    }

    @Test("Without it, every trial word goes")
    func notEligible() {
        let headline = PremiumCopy.headline(trialDays: nil)
        #expect(headline == "Keep the practice going.")
        #expect(PremiumCopy.buttonTitle(startsFreeWeek: false) == "Continue")
        #expect(PremiumCopy.cancelLine(startsFreeWeek: false) == "Cancel anytime in Settings.")
        let terms = PremiumCopy.renewalTerms(planName: "Annual", price: "$49.99", value: 1, unit: .year, trialDays: nil)
        let offer = PremiumCopy.offerLine(price: "$29.99", perMonth: "$2.50 a month", trialDays: nil)
        let button = PremiumCopy.offerButton(price: "$29.99", startsFreeWeek: false)
        for words in [headline, terms, offer, button, PremiumCopy.cancelLine(startsFreeWeek: false)] {
            for trial in ["free", "trial", "Nothing is charged today", "week"] {
                #expect(!words.contains(trial), Comment(rawValue: "\(trial) in: \(words)"))
            }
        }
    }

    @Test("Per week and per month are computed from StoreKit's price, in its own format")
    func computedPrices() {
        #expect(PremiumCopy.perWeek(price: Decimal(string: "49.99")!, value: 1, unit: .year, format: usd) == "$0.96 a week")
        #expect(PremiumCopy.perMonth(price: Decimal(string: "29.99")!, value: 1, unit: .year, format: usd) == "$2.50 a month")
        #expect(PremiumCopy.perMonth(price: Decimal(string: "12.99")!, value: 1, unit: .month, format: usd) == "$12.99 a month")
        let euros = Decimal.FormatStyle.Currency(code: "EUR", locale: Locale(identifier: "de_DE"))
        #expect(PremiumCopy.perWeek(price: Decimal(string: "52")!, value: 1, unit: .year, format: euros)?.contains("1,00") == true)
        #expect(PremiumCopy.price("$12.99", value: 1, unit: .month) == "$12.99 a month")
        #expect(PremiumCopy.price("€5", value: 3, unit: .month) == "€5 every 3 months")
    }

    /// The annual card leads with what it comes to per month and what it
    /// saves against Monthly (release polish, §17). Both from StoreKit's
    /// prices: the figure rounded up and the saving rounded down, so neither
    /// says the plan is cheaper than it is.
    @Test("Annual's per-month figure and saving are computed, and never flatter it")
    func annualComparison() {
        #expect(PremiumCopy.monthlyEquivalent(price: Decimal(string: "49.99")!, value: 1, unit: .year, format: usd) == "$4.17")
        // 59.95 / 12 = 4.9958…, and 4.995 / month would be less than the price.
        #expect(PremiumCopy.monthlyEquivalent(price: Decimal(string: "59.95")!, value: 1, unit: .year, format: usd) == "$5.00")
        #expect(PremiumCopy.monthlyEquivalent(price: Decimal(string: "48")!, value: 1, unit: .year, format: usd) == "$4.00")
        #expect(PremiumCopy.monthlyEquivalent(price: Decimal(string: "1")!, value: 1, unit: .week, format: usd) == nil)

        // 1 − 49.99 / (12 × 12.99) = 67.93…%: said as 67, never 68.
        #expect(PremiumCopy.savingPercent(
            annual: Decimal(string: "49.99")!, annualValue: 1, annualUnit: .year,
            monthly: Decimal(string: "12.99")!, monthlyValue: 1, monthlyUnit: .month
        ) == 67)
        #expect(PremiumCopy.savingBadge(percent: 67) == "Save 67%")
        // No saving, no badge.
        #expect(PremiumCopy.savingPercent(
            annual: Decimal(string: "155.88")!, annualValue: 1, annualUnit: .year,
            monthly: Decimal(string: "12.99")!, monthlyValue: 1, monthlyUnit: .month
        ) == nil)
        #expect(PremiumCopy.savingPercent(
            annual: Decimal(string: "49.99")!, annualValue: 1, annualUnit: .year,
            monthly: Decimal(string: "1")!, monthlyValue: 1, monthlyUnit: .week
        ) == nil)

        #expect(PremiumCopy.billed("$49.99", value: 1, unit: .year) == "Billed annually at $49.99")
        #expect(PremiumCopy.buttonLine(trialDays: 7, price: "$49.99", value: 1, unit: .year)
            == "7 days free, then $49.99 a year.")
        let noTrial = PremiumCopy.buttonLine(trialDays: nil, price: "$12.99", value: 1, unit: .month)
        #expect(noTrial == "$12.99 a month. Cancel anytime.")
        for trial in ["free", "trial", "week"] { #expect(!noTrial.contains(trial)) }
    }

    @Test("The exit offer: one lower price, offered once, with or without the free week")
    func exitOffer() {
        #expect(PremiumCopy.offerTitle == "One lower price, offered once.")
        #expect(PremiumCopy.offerLine(price: "$29.99", perMonth: "$2.50 a month", trialDays: 7)
            == "$29.99 a year, $2.50 a month, still with seven days free.")
        #expect(PremiumCopy.offerLine(price: "$29.99", perMonth: "$2.50 a month", trialDays: nil)
            == "$29.99 a year, $2.50 a month.")
        #expect(PremiumCopy.offerButton(price: "$29.99", startsFreeWeek: true) == "Start my free week at $29.99")
        #expect(PremiumCopy.offerDecline == "No thanks")
    }

    @Test("A trial is counted in days, as people count one")
    func trialDays() {
        #expect(PremiumCopy.trialDays(value: 1, unit: .week) == 7)
        #expect(PremiumCopy.trialDays(value: 3, unit: .day) == 3)
        #expect(PremiumCopy.trialDays(value: 1, unit: .month) == nil)
    }

    @Test("Settings names the four states")
    func status() {
        let date: (Date) -> String = { _ in "Oct 8" }
        #expect(PremiumCopy.status(.founder, date: date) == "Founder")
        #expect(PremiumCopy.status(.trial(.annual, ends: .now), date: date) == "Trial, ends Oct 8")
        #expect(PremiumCopy.status(.pro(.annualOffer), date: date) == "Forge Pro, Annual")
        #expect(PremiumCopy.status(.pro(.lifetime), date: date) == "Forge Pro, Lifetime")
        #expect(PremiumCopy.status(.lapsed, date: date) == "Not subscribed")
        #expect(PremiumCopy.status(.none, date: date) == "Not subscribed")
    }

    @Test("The voice: no exclamation marks, no loss, and the locked state says the record is theirs")
    func voice() {
        let words = [
            PremiumCopy.headline(trialDays: 7), PremiumCopy.headline(trialDays: nil),
            PremiumCopy.recordLine, PremiumCopy.reminderToggle, PremiumCopy.declinedLine,
            PremiumCopy.offerTitle, PremiumCopy.lockedTitle, PremiumCopy.lockedLine, TrialReminder.body,
        ]
        for line in words {
            #expect(!line.contains("!"), Comment(rawValue: line))
            #expect(!line.lowercased().contains("lose"), Comment(rawValue: line))
            #expect(!line.lowercased().contains("never see"), Comment(rawValue: line))
        }
        #expect(PremiumCopy.lockedTitle == "New days need Forge Pro.")
        #expect(PremiumCopy.lockedLine == "Your record stays yours.")
        #expect(PremiumCopy.declinedLine == "Forge needs Forge Pro to keep new days.")
        #expect(PremiumCopy.recordLine == "If you ever stop, your record stays readable.")
    }
}

// MARK: - Once, ever

@Suite("Forge Pro: the exit offer")
struct ExitOfferTests {

    @Test("The offer is shown once, ever, and remembered across launches")
    func once() {
        let defaults = UserDefaults(suiteName: "forge.exit.\(UUID().uuidString)") ?? .standard
        #expect(!ExitOffer(defaults: defaults).hasBeenShown)
        #expect(ExitOffer(defaults: defaults).claim())
        #expect(!ExitOffer(defaults: defaults).claim())
        #expect(ExitOffer(defaults: defaults).hasBeenShown)
        #expect(defaults.bool(forKey: "forge.exitOffer.v1"))
    }
}

// MARK: - The reminder

@Suite("Forge Pro: the trial reminder")
struct TrialReminderTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test("Two days before the free week ends")
    func twoDaysBefore() {
        let ends = date(2026, 10, 8)
        let fire = TrialReminder.fireDate(
            access: .trial(.annual, ends: ends), willAutoRenew: true, isWanted: true,
            now: date(2026, 10, 1), calendar: calendar
        )
        #expect(fire == date(2026, 10, 6))
        #expect(TrialReminder.reminderDay(trialDays: 7) == 5)
        #expect(TrialReminder.reminderDay(trialDays: 2) == nil)
    }

    /// Daylight saving ends on 1 November 2026 in New York. Two days before
    /// 10:00 on the 3rd is 10:00 on the 1st on the clock, not 09:00.
    @Test("Across a clock change, two days before is the same time on the clock")
    func clockChange() throws {
        let fire = try #require(TrialReminder.fireDate(
            access: .trial(.annual, ends: date(2026, 11, 3)), willAutoRenew: nil, isWanted: true,
            now: date(2026, 10, 27), calendar: calendar
        ))
        #expect(calendar.component(.hour, from: fire) == 10)
        #expect(calendar.component(.day, from: fire) == 1)

        // And at the start of the person's day on that date, the clock change
        // notwithstanding.
        let morning = try #require(TrialReminder.fireDate(
            access: .trial(.annual, ends: date(2026, 11, 3)), willAutoRenew: nil, isWanted: true,
            now: date(2026, 10, 27), morning: 6 * 60 + 30, calendar: calendar
        ))
        #expect(calendar.dateComponents([.day, .hour, .minute], from: morning)
            == DateComponents(day: 1, hour: 6, minute: 30))
    }

    /// Found walking the paywall at 1:16 at night (§17.7): the free week began
    /// then, so the reminder was due at 1:16 at night five days later, with a
    /// sound. It lands at the start of the person's day on that date instead.
    @Test("A free week begun at night is reminded about in the morning, still more than a day ahead")
    func remindsInTheMorning() throws {
        let begun = date(2026, 10, 4, 1)
        let ends = try #require(calendar.date(byAdding: .day, value: 7, to: begun))
        let fire = try #require(TrialReminder.fireDate(
            access: .trial(.annual, ends: ends), willAutoRenew: true, isWanted: true,
            now: begun, morning: 6 * 60 + 30, calendar: calendar
        ))
        #expect(calendar.dateComponents([.month, .day, .hour, .minute], from: fire)
            == DateComponents(month: 10, day: 9, hour: 6, minute: 30))

        // Whatever the start of day — the earliest and the latest a day has —
        // it is on the fifth day and leaves more than a whole day to cancel.
        for morning in [0, 6 * 60 + 30, 23 * 60 + 59] {
            for hour in [0, 1, 12, 23] {
                let start = date(2026, 10, 4, hour)
                let end = try #require(calendar.date(byAdding: .day, value: 7, to: start))
                let reminder = try #require(TrialReminder.fireDate(
                    access: .trial(.annual, ends: end), willAutoRenew: true, isWanted: true,
                    now: start, morning: morning, calendar: calendar
                ))
                #expect(calendar.component(.day, from: reminder) == 9)
                #expect(end.timeIntervalSince(reminder) > 24 * 3_600)
            }
        }

        // That morning gone, there is no reminder rather than a second one.
        #expect(TrialReminder.fireDate(
            access: .trial(.annual, ends: ends), willAutoRenew: true, isWanted: true,
            now: date(2026, 10, 9, 10), morning: 6 * 60 + 30, calendar: calendar
        ) == nil)
    }

    @Test("No reminder once it is past, unwanted, cancelled, converted or not a trial")
    func gone() {
        let ends = date(2026, 10, 8)
        let trial = ProAccess.trial(.annual, ends: ends)
        // Past.
        #expect(TrialReminder.fireDate(access: trial, willAutoRenew: true, isWanted: true, now: date(2026, 10, 7), calendar: calendar) == nil)
        // Turned off on the paywall.
        #expect(TrialReminder.fireDate(access: trial, willAutoRenew: true, isWanted: false, now: date(2026, 10, 1), calendar: calendar) == nil)
        // Cancelled: it will not renew, so there is nothing to remind about.
        #expect(TrialReminder.fireDate(access: trial, willAutoRenew: false, isWanted: true, now: date(2026, 10, 1), calendar: calendar) == nil)
        // Converted, founder, lapsed.
        for access in [ProAccess.pro(.annual), .founder, .lapsed, .none, .unknown] {
            #expect(TrialReminder.fireDate(access: access, willAutoRenew: true, isWanted: true, now: date(2026, 10, 1), calendar: calendar) == nil)
        }
        // Not known to renew yet is not known to be cancelled: kept.
        #expect(TrialReminder.fireDate(access: trial, willAutoRenew: nil, isWanted: true, now: date(2026, 10, 1), calendar: calendar) != nil)
    }

    /// Found in the Simulator: relaunched after a trial ended, the reminder
    /// read nil before StoreKit answered and nil after, the sync never ran a
    /// second time, and the reminder for a finished trial stayed pending.
    @Test("StoreKit answering always re-syncs the reminder, even to say there is none")
    func syncKey() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        #expect(TrialReminder.syncKey(hasAnswered: false, fireDate: nil, authorization: 2)
            != TrialReminder.syncKey(hasAnswered: true, fireDate: nil, authorization: 2))
        #expect(TrialReminder.syncKey(hasAnswered: true, fireDate: date, authorization: 2)
            != TrialReminder.syncKey(hasAnswered: true, fireDate: nil, authorization: 2))
        #expect(TrialReminder.syncKey(hasAnswered: true, fireDate: date, authorization: 0)
            != TrialReminder.syncKey(hasAnswered: true, fireDate: date, authorization: 2))
    }

    @Test("Wanted unless turned off, and the words are the promise")
    func wanted() {
        let defaults = UserDefaults(suiteName: "forge.reminder.\(UUID().uuidString)") ?? .standard
        #expect(TrialReminder.isWanted(in: defaults))
        TrialReminder.setWanted(false, in: defaults)
        #expect(!TrialReminder.isWanted(in: defaults))
        #expect(TrialReminder.body == "Your free week ends in two days. Keep Forge or cancel in Settings. Either takes one tap.")
        #expect(ForgeNotification(identifier: ForgeNotifications.trialReminderIdentifier) == .trial)
    }
}

// MARK: - The rating

@Suite("Forge Pro: the rating prompt")
struct RatingPromptTests {

    private func blade(days: Int) -> Sword { Sword.collection.first { $0.requirement == days }! }
    private let quiet = RatingPrompt.Moment(isFirstRun: false, isDayInProgress: false)
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("The first blade celebration after the first run asks, once")
    func first() {
        #expect(RatingPrompt.decide(closing: blade(days: 3), asked: [], now: now, moment: quiet) == .first)
        #expect(RatingPrompt.decide(closing: blade(days: 3), asked: [now], now: now, moment: quiet) == nil)
    }

    @Test("Never in the first run, never over a day in progress — and nothing is owed")
    func never() {
        let firstRun = RatingPrompt.Moment(isFirstRun: true, isDayInProgress: false)
        let busy = RatingPrompt.Moment(isFirstRun: false, isDayInProgress: true)
        #expect(RatingPrompt.decide(closing: blade(days: 1), asked: [], now: now, moment: firstRun) == nil)
        #expect(RatingPrompt.decide(closing: blade(days: 3), asked: [], now: now, moment: busy) == nil)
    }

    @Test("Folded asks once more, only if the first ask was more than a day earlier")
    func folded() {
        let folded = blade(days: 7)
        #expect(folded.name == "Folded")
        let threeDaysAgo = now.addingTimeInterval(-3 * 86_400)
        #expect(RatingPrompt.decide(closing: folded, asked: [threeDaysAgo], now: now, moment: quiet) == .second)
        #expect(RatingPrompt.decide(closing: folded, asked: [now.addingTimeInterval(-3_600)], now: now, moment: quiet) == nil)
        // Not a third time, and not at any other blade.
        #expect(RatingPrompt.decide(closing: folded, asked: [threeDaysAgo, now], now: now, moment: quiet) == nil)
        #expect(RatingPrompt.decide(closing: blade(days: 14), asked: [threeDaysAgo], now: now, moment: quiet) == nil)
        // If Folded is the first chance, it is the first ask.
        #expect(RatingPrompt.decide(closing: folded, asked: [], now: now, moment: quiet) == .first)
    }

    @Test("Asking is written down; a moment that passes is not")
    func claim() {
        let defaults = UserDefaults(suiteName: "forge.rating.\(UUID().uuidString)") ?? .standard
        let prompt = RatingPrompt(defaults: defaults)
        let busy = RatingPrompt.Moment(isFirstRun: false, isDayInProgress: true)
        #expect(prompt.claim(closing: blade(days: 3), now: now, moment: busy) == nil)
        #expect(prompt.asked.isEmpty)
        #expect(prompt.claim(closing: blade(days: 3), now: now, moment: quiet) == .first)
        #expect(prompt.asked == [now])
        let fourDaysLater = now.addingTimeInterval(4 * 86_400)
        #expect(prompt.claim(closing: blade(days: 7), now: fourDaysLater, moment: quiet) == .second)
        #expect(prompt.claim(closing: blade(days: 7), now: fourDaysLater, moment: quiet) == nil)
        #expect(RatingPrompt(defaults: defaults).asked.count == 2)
    }
}

// MARK: - The real StoreKit path

/// The real StoreKit path, against `Forge.storekit` in an `SKTestSession`.
///
/// Serialized: StoreKit's test environment is one per process, and two suites
/// buying at once would read each other's transactions. Every store here gets
/// a suite of its own for the founder record and never reads the host app's
/// `AppTransaction`, so the host's own history cannot make it a founder.
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

    private func makeStore(founder: Bool = false) -> ForgeStore {
        let defaults = UserDefaults(suiteName: "forge.storekit.\(UUID().uuidString)") ?? .standard
        if founder { defaults.set(true, forKey: Founder.key) }
        return ForgeStore(defaults: defaults, readsAppTransaction: false)
    }

    /// StoreKit's index catches up with a purchase within a second; refresh
    /// until it has, or give up.
    private func settle(_ store: ForgeStore, until condition: () -> Bool) async {
        for _ in 0..<20 where !condition() {
            try? await Task.sleep(for: .milliseconds(150))
            await store.refreshEntitlement()
        }
    }

    @Test("All four products load, with a free week on annual and on the offer")
    func loads() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let store = makeStore()
        await store.refresh()

        #expect(store.status == .ready)
        #expect(store.offerings.map(\.id) == PremiumProduct.paywallPlans.map(\.rawValue))
        #expect(store.annual?.price == Decimal(string: "49.99"))
        #expect(store.annualOffer?.price == Decimal(string: "29.99"))
        #expect(store.monthly?.price == Decimal(string: "12.99"))
        #expect(store.lifetime?.price == Decimal(string: "129.99"))
        #expect(store.annual?.subscription?.subscriptionPeriod.unit == .year)
        #expect(store.monthly?.subscription?.subscriptionPeriod.unit == .month)

        // The free week as configured, whoever is asking...
        for plan in [PremiumProduct.annual, .annualOffer] {
            let offer = try #require(store.product(for: plan)?.subscription?.introductoryOffer)
            #expect(offer.paymentMode == .freeTrial)
            #expect(PremiumCopy.trialDays(value: offer.period.value, unit: offer.period.unit) == 7)
        }
        #expect(store.monthly?.subscription?.introductoryOffer == nil)
        // ...and offered exactly when StoreKit says this account may take it.
        // A Simulator that has already had a trial (a manual walk-through,
        // say) is not eligible however its transactions were cleared, and the
        // screen must then offer none.
        #expect((store.freeTrial(for: .annual) != nil) == store.isTrialEligible)
        #expect((store.freeTrial(for: .annualOffer) != nil) == store.isTrialEligible)
        #expect(store.freeTrial(for: .monthly) == nil)
        #expect(store.access == .none)
        #expect(store.hasReadEntitlement)
    }

    @Test("Monthly is Pro, with nothing in it called a trial")
    func monthly() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        _ = try await session.buyProduct(identifier: PremiumProduct.monthly.rawValue)

        let store = makeStore()
        await store.refresh()
        await settle(store) { store.access == .pro(.monthly) }
        #expect(store.entitlement == .subscribed)
        #expect(store.access == .pro(.monthly))
    }

    @Test("Lifetime outranks a subscription bought alongside it")
    func lifetime() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        _ = try await session.buyProduct(identifier: PremiumProduct.annual.rawValue)
        _ = try await session.buyProduct(identifier: PremiumProduct.lifetime.rawValue)

        let store = makeStore()
        await store.refresh()
        await settle(store) { store.access == .pro(.lifetime) }
        #expect(store.entitlement == .lifetime)
        #expect(store.access == .pro(.lifetime))
    }

    @Test("Starting the free week unlocks at once, ends in seven days, and is not offered again")
    func annualTrial() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let store = makeStore()
        await store.refresh()
        let annual = try #require(store.annual)

        let outcome = await store.purchase(annual)
        #expect(outcome == .bought(startedTrial: true))
        guard case .trial(let plan, let ends) = store.access else {
            Issue.record("expected a trial, got \(store.access)")
            return
        }
        #expect(plan == .annual)
        #expect(abs(ends.timeIntervalSinceNow - 7 * 86_400) < 3_600)
        #expect(store.freeTrial(for: .annual) == nil, "taken once")
        #expect(PremiumGate.passesOnboardingPaywall(store.access))
    }

    @Test("The offer is a trial of its own plan")
    func offerTrial() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let store = makeStore()
        await store.refresh()
        let offer = try #require(store.annualOffer)

        #expect(await store.purchase(offer) == .bought(startedTrial: true))
        guard case .trial(.annualOffer, _) = store.access else {
            Issue.record("expected the offer's trial, got \(store.access)")
            return
        }
    }

    @Test("A free week set not to renew loses its reminder")
    func cancelledTrial() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let store = makeStore()
        await store.refresh()
        _ = await store.purchase(try #require(store.annual))
        await settle(store) { store.willAutoRenew == true }
        #expect(store.willAutoRenew == true)
        #expect(TrialReminder.fireDate(access: store.access, willAutoRenew: store.willAutoRenew, isWanted: true, now: .now) != nil)

        let transaction = try #require(await Transaction.latest(for: PremiumProduct.annual.rawValue))
        guard case .verified(let bought) = transaction else {
            Issue.record("unverified")
            return
        }
        try session.disableAutoRenewForTransaction(identifier: UInt(bought.id))
        await settle(store) { store.willAutoRenew == false }
        #expect(store.willAutoRenew == false)
        #expect(TrialReminder.fireDate(access: store.access, willAutoRenew: store.willAutoRenew, isWanted: true, now: .now) == nil)
    }

    @Test("An expired subscription is lapsed, and lapsed locks new days and nothing else")
    func expiry() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let transaction = try await session.buyProduct(identifier: PremiumProduct.monthly.rawValue)
        try session.expireSubscription(productIdentifier: transaction.productID)

        let store = makeStore()
        await store.refresh()
        await settle(store) { store.access == .lapsed }
        #expect(store.entitlement == .free)
        #expect(store.access == .lapsed)
        #expect(PremiumGate.isLocked(.dayControls, for: store.access))
        #expect(!PremiumGate.isLocked(.history, for: store.access))
    }

    @Test("A founder with nothing bought is a founder; with a subscription, Pro")
    func founder() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let store = makeStore(founder: true)
        await store.refresh()
        #expect(store.access == .founder)

        _ = try await session.buyProduct(identifier: PremiumProduct.monthly.rawValue)
        let subscriber = makeStore(founder: true)
        await subscriber.refresh()
        await settle(subscriber) { subscriber.access == .pro(.monthly) }
        #expect(subscriber.access == .pro(.monthly))
    }
}

// MARK: - A session held open for walking the paywall by hand

/// Not a check: Xcode's local StoreKit server, held open while the app is
/// driven by hand.
///
/// The server lives exactly as long as the `xcodebuild` run that started it.
/// After an ordinary test run a simctl-installed build still shows
/// `Forge.storekit`'s prices, but every purchase fails (`AMSErrorDomain` 10,
/// FORGE_CONTEXT §17.2), so the paywall could only ever be walked as far as
/// its prices. This test is skipped unless the run asks for it, and then it
/// opens a session against `Forge.storekit` and waits, with the real purchase
/// sheet, while the hosting app — Forge, launched as it always is — is used:
///
/// ```
/// TEST_RUNNER_FORGE_HOLD_STOREKIT=1800 xcodebuild test -project Forge.xcodeproj \
///   -scheme Forge -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///   -only-testing:'ForgeTests/StoreKitHold/hold()'
/// ```
///
/// `TEST_RUNNER_FORGE_STOREKIT_RATE=minute` (or `tenSeconds`) shortens every
/// subscription period, the free week included, so a lapse can be watched;
/// `TEST_RUNNER_FORGE_STOREKIT_KEEP=1` keeps the transactions of the last
/// hold instead of starting from none. FORGE_CONTEXT §14.
@MainActor
@Suite("QA: StoreKit held open by hand")
struct StoreKitHold {

    nonisolated static var seconds: Int? {
        ProcessInfo.processInfo.environment["FORGE_HOLD_STOREKIT"].flatMap(Int.init)
    }

    @Test("Hold a StoreKit session open while the app is walked", .enabled(if: StoreKitHold.seconds != nil))
    func hold() async throws {
        let environment = ProcessInfo.processInfo.environment
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Forge/Forge.storekit")
        let session = try SKTestSession(contentsOf: url)
        if environment["FORGE_STOREKIT_KEEP"] == nil {
            session.resetToDefaultState()
            session.clearTransactions()
        }
        // The purchase sheet, as somebody sees it.
        session.disableDialogs = false
        switch environment["FORGE_STOREKIT_RATE"] {
        case "minute": session.timeRate = .oneRenewalEveryMinute
        case "tenSeconds": session.timeRate = .oneRenewalEveryTenSeconds
        default: session.timeRate = .realTime
        }
        try await Task.sleep(for: .seconds(Self.seconds ?? 0))
    }
}

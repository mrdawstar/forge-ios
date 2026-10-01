import StoreKit
import SwiftUI

/// Forge Pro: seven days free, then a decision. The only screen in the app
/// that sells anything.
///
/// # Two kinds of door
///
/// - **Onboarding — the hard paywall** (DIRECTION_1_1 §1). After the pull is
///   rehearsed and before the first thing is done. There is no close button.
///   A quiet "Not now" at the foot opens the exit offer the first time it is
///   pressed (`ExitOffer`, once ever); after that it is replaced by one line —
///   "Forge needs Forge Pro to keep new days." — and the paywall stays. A
///   purchase, a restore, or the App Store recognising a founder continues
///   into the app.
/// - **Everywhere else** — the locked state, Settings, a locked AI control.
///   The same screen, and "Not now" closes it.
///
/// # What is on it, top to bottom
///
/// The sword in the stone, on black. The headline. One row per feature that is
/// in this build (`PaywallRow`, `ForgeFeatures`). The free week as a timeline —
/// today, the reminder, the charge. Annual, chosen, with its price per week;
/// Monthly. What cancelling costs (nothing) and what stopping costs (nothing:
/// the record stays readable). The reminder toggle. The button, pinned.
/// Restore, the Terms of Use and the Privacy Policy, and the renewal terms.
///
/// # What it will not do
///
/// - **Print a price it was not given.** Every price is `Product.displayPrice`;
///   per-week and per-month figures are `Product.price` in the product's own
///   `priceFormatStyle`. The words around them are `PremiumCopy`.
/// - **Offer a free week somebody cannot take.** Eligibility is StoreKit's
///   (`ForgeStore.freeTrial(for:)`); without it every trial word goes — the
///   headline, the timeline, the badge, "Nothing is charged today", the
///   reminder and the button's wording.
/// - **Sell lifetime.** It is sold in Settings → Forge Pro, and only there.
/// - **Hurry anybody.** No timer, no scarcity, no invented saving, nothing that
///   blinks; the only price struck through is the storefront's real annual one.
struct PaywallView: View {
    let door: ForgeTelemetry.PaywallDoor
    @Bindable var store: ForgeStore
    /// Called once: when what this door was opened for is true — bought,
    /// restored, a founder recognised — and, on any door but onboarding, when
    /// somebody says not now.
    let onClose: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selected: PremiumProduct = .annual
    /// "Remind me before the trial ends". On unless somebody turned it off.
    @State private var remind = TrialReminder.isWanted()
    @State private var isShowingOffer = false
    /// The offer has been seen and declined, or could not be shown: the line
    /// takes the place of "Not now".
    @State private var hasDeclined = false
    @State private var hasReportedView = false
    /// Ask-to-buy, or a bank still thinking about it.
    @State private var isWaiting = false
    /// A purchase or restore this screen started is being settled. The
    /// entitlement arriving does not close the screen while it is, so the
    /// reminder can be asked about first.
    @State private var isSettling = false
    @State private var isClosed = false
    /// The free weeks as they stood when a purchase began. StoreKit marks the
    /// week as taken the moment it starts, and without this the screen
    /// rewrote itself into its no-trial wording behind the notification
    /// prompt, a second before it closed. Nil whenever nothing is settling.
    @State private var trialsAtPurchase: [PremiumProduct: Int]?

    private var isHard: Bool { door == .onboarding }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isShowingOffer {
                offerPage.transition(.opacity)
            } else {
                plansPage.transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: isShowingOffer)
        .preferredColorScheme(.dark)
        .onAppear {
            // Somebody who already has it is not shown it: a founder, a
            // subscriber, a restore that landed a moment ago.
            if isDone { close(); return }
            guard !hasReportedView else { return }
            hasReportedView = true
            ForgeTelemetry.send(.paywallView(door))
            if store.product(for: selected) == nil, let first = availablePlans.first {
                selected = first
            }
        }
        .task {
            // The retry, and the first load for anybody who arrives before the
            // launch request came back.
            if store.status != .ready { await store.refresh() }
        }
        // Bought here, restored here, approved on another device, or a founder
        // the App Store vouched for while this was open.
        .onChange(of: store.access) { _, _ in
            guard !isSettling, isDone else { return }
            close()
        }
        .onChange(of: availablePlans) { _, plans in
            if store.product(for: selected) == nil, let first = plans.first { selected = first }
        }
    }

    /// Whether what this door was opened for is now true.
    private var isDone: Bool {
        switch store.access {
        case .pro, .trial: true
        // A founder has everything a new day needs. The AI door, and Settings,
        // are about what a founder does not have, and stay open.
        case .founder: door == .onboarding || door == .locked
        case .unknown, .lapsed, .none: false
        }
    }

    private func close() {
        guard !isClosed else { return }
        isClosed = true
        onClose()
    }

    // MARK: - The plans

    private var plansPage: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    hero(height: typeSize.isAccessibilitySize ? 100 : 136)
                    headline
                    features
                    if showsTimeline { timeline }
                    plans
                    notes
                    if showsTimeline { reminder }
                    documents
                    Text(renewalTerms(for: selected))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, ForgeTheme.Space.row)
                }
                .padding(.horizontal, ForgeTheme.Space.gutter)
                .padding(.bottom, ForgeTheme.Space.section)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            pinned(
                title: PremiumCopy.buttonTitle(startsFreeWeek: startsFreeWeek),
                isEnabled: store.product(for: selected) != nil,
                action: { purchase(selected) }
            ) {
                if isHard && hasDeclined {
                    quiet(PremiumCopy.declinedLine)
                } else {
                    Button("Not now") { notNow() }
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(minHeight: 44)
                        .accessibilityHint(Text(isHard ? "" : "Closes Forge Pro. Nothing changes."))
                }
            }
        }
    }

    /// The sword in the stone. `hero-plate` rather than `hero`: its empty space
    /// is true black, so on this black there is no box around it.
    private func hero(height: CGFloat) -> some View {
        Image("hero-plate")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxHeight: height)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private var headline: some View {
        VStack(spacing: ForgeTheme.Space.tight) {
            Text("FORGE PRO")
                .font(ForgeTheme.overline)
                .kerning(ForgeTheme.overlineKerning)
                .foregroundStyle(ForgeTheme.cream.opacity(0.75))

            Text(PremiumCopy.headline(trialDays: trialDays(for: .annual)))
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, ForgeTheme.Space.hair)
        .padding(.bottom, ForgeTheme.Space.gutter)
    }

    /// What you get: one row per feature this build has.
    private var features: some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Space.inner) {
            ForEach(PaywallRow.rows(), id: \.self) { row in
                HStack(alignment: .firstTextBaseline, spacing: ForgeTheme.Space.inner) {
                    // Capped, so at the accessibility sizes the glyph stays in
                    // its column instead of growing into the words beside it.
                    Image(systemName: row.symbol)
                        .font(.body.weight(.medium))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundStyle(ForgeTheme.cream)
                        .frame(width: 26)
                        .accessibilityHidden(true)
                    Text(row.line)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.bottom, ForgeTheme.Space.gutter)
    }

    // MARK: The free week

    /// Only for the annual plan, and only while the free week is on offer.
    private var showsTimeline: Bool { selected == .annual && trialDays(for: .annual) != nil }

    /// Today: everything unlocked. Day 5: we remind you. Day 7: the charge,
    /// unless cancelled before.
    @ViewBuilder
    private var timeline: some View {
        if let annual = store.annual, let days = trialDays(for: .annual),
           let period = annual.subscription?.subscriptionPeriod {
            let steps = PremiumCopy.timeline(
                trialDays: days, renewal: annual.displayPrice,
                value: period.value, unit: period.unit, reminds: remind
            )
            // One line a step — the day, then what happens — so the plans
            // below are on the first screen of a standard phone.
            VStack(alignment: .leading, spacing: ForgeTheme.Space.tight) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: ForgeTheme.Space.inner) {
                        Image(systemName: Self.timelineSymbols[min(index, Self.timelineSymbols.count - 1)])
                            .font(.subheadline.weight(.medium))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .foregroundStyle(index == 0 ? ForgeTheme.cream : .white.opacity(0.55))
                            .frame(width: 26)
                            .accessibilityHidden(true)
                        (Text(step.when).fontWeight(.semibold).foregroundStyle(.white)
                            + Text("  ")
                            + Text(step.what).foregroundStyle(.white.opacity(0.7)))
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, ForgeTheme.Space.row)
            .padding(.vertical, ForgeTheme.Space.inner)
            .background(
                RoundedRectangle(cornerRadius: ForgeTheme.Radius.control, style: .continuous)
                    .fill(.white.opacity(0.04))
            )
            .padding(.bottom, ForgeTheme.Space.gutter)
        }
    }

    private static let timelineSymbols = ["lock.open", "bell", "calendar"]

    // MARK: The two plans

    private var availablePlans: [PremiumProduct] {
        PremiumProduct.paywallPlans.filter { store.product(for: $0) != nil }
    }

    @ViewBuilder
    private var plans: some View {
        switch store.status {
        case .loading where availablePlans.isEmpty:
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, minHeight: 120)
        case .unavailable where availablePlans.isEmpty:
            VStack(spacing: ForgeTheme.Space.tight) {
                Text("The App Store can't be reached right now.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                Button("Try again") { Task { await store.refresh() } }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ForgeTheme.cream)
                    .frame(minHeight: 44)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        default:
            VStack(spacing: ForgeTheme.Space.tight) {
                ForEach(availablePlans, id: \.self) { plan in
                    if let product = store.product(for: plan) {
                        planRow(plan, product: product)
                    }
                }
            }
        }
    }

    /// One plan. Chosen is unmistakable: a filled mark, a cream border and a
    /// lighter card, all three at once.
    private func planRow(_ plan: PremiumProduct, product: Product) -> some View {
        let isChosen = selected == plan
        let period = product.subscription?.subscriptionPeriod
        let price = period.map {
            PremiumCopy.price(product.displayPrice, value: $0.value, unit: $0.unit)
        } ?? product.displayPrice
        // The weekly figure is the annual plan's: a month is already small.
        let perWeek = plan == .annual ? period.flatMap {
            PremiumCopy.perWeek(price: product.price, value: $0.value, unit: $0.unit, format: product.priceFormatStyle)
        } : nil
        let badge = trialDays(for: plan).map(PremiumCopy.trialBadge(days:))

        return Button {
            guard !isChosen else { return }
            ForgeHaptics.shared.detent()
            withAnimation(.forgeSelection) { selected = plan }
        } label: {
            HStack(alignment: .top, spacing: ForgeTheme.Space.inner) {
                Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isChosen ? ForgeTheme.cream : .white.opacity(0.35))
                    .padding(.top, 1)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: ForgeTheme.Space.tight) {
                            planName(plan)
                            if let badge { trialBadge(badge) }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            planName(plan)
                            if let badge { trialBadge(badge) }
                        }
                    }
                    Text(price)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                    if let perWeek {
                        Text(perWeek)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(ForgeTheme.Space.row)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ForgeTheme.Radius.control, style: .continuous)
                    .fill(.white.opacity(isChosen ? 0.10 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ForgeTheme.Radius.control, style: .continuous)
                    .strokeBorder(
                        isChosen ? ForgeTheme.cream : .white.opacity(0.12),
                        lineWidth: isChosen ? 1.5 : 1
                    )
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([plan.planName, badge, price, perWeek].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }

    private func planName(_ plan: PremiumProduct) -> some View {
        Text(plan.planName)
            .font(.headline)
            .foregroundStyle(.white)
    }

    private func trialBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(ForgeTheme.cream)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(ForgeTheme.cream.opacity(0.14)))
    }

    private var notes: some View {
        VStack(spacing: 6) {
            Text(PremiumCopy.cancelLine(startsFreeWeek: startsFreeWeek))
            Text(PremiumCopy.recordLine)
        }
        .font(.footnote)
        .foregroundStyle(.white.opacity(0.65))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, ForgeTheme.Space.row)
    }

    private var reminder: some View {
        Toggle(isOn: $remind) {
            Text(PremiumCopy.reminderToggle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .tint(ForgeTheme.cream)
        .padding(.horizontal, ForgeTheme.Space.row)
        .padding(.vertical, ForgeTheme.Space.inner)
        .background(
            RoundedRectangle(cornerRadius: ForgeTheme.Radius.control, style: .continuous)
                .fill(.white.opacity(0.04))
        )
        .padding(.top, ForgeTheme.Space.row)
    }

    /// Restore, and the two documents.
    private var documents: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: ForgeTheme.Space.row) { documentLinks }
            VStack(spacing: ForgeTheme.Space.tight) { documentLinks }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white.opacity(0.8))
        .padding(.top, ForgeTheme.Space.section)
    }

    @ViewBuilder
    private var documentLinks: some View {
        Button("Restore Purchases") { restore() }
            .disabled(store.isRestoring || store.pending != nil)
            .frame(minHeight: 44)
        if let terms = ForgeLinks.appleEULA {
            Link("Terms of Use", destination: terms)
                .frame(minHeight: 44)
        }
        if let privacy = ForgeLinks.privacy {
            Link("Privacy Policy", destination: privacy)
                .frame(minHeight: 44)
        }
    }

    // MARK: - The offer, once

    /// "One lower price, offered once." Reached only from the onboarding
    /// paywall's first "Not now"; "No thanks" goes back to the plans.
    private var offerPage: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: ForgeTheme.Space.row) {
                    hero(height: typeSize.isAccessibilitySize ? 100 : 150)

                    Text(PremiumCopy.offerTitle)
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    if let struck = struckAnnualPrice {
                        Text(struck)
                            .font(.subheadline)
                            .strikethrough()
                            .foregroundStyle(.white.opacity(0.45))
                            .accessibilityLabel(Text("The annual plan is \(struck)"))
                    }

                    if let line = offerLine {
                        Text(line)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 6) {
                        Text(PremiumCopy.cancelLine(startsFreeWeek: trialDays(for: .annualOffer) != nil))
                        Text(PremiumCopy.recordLine)
                    }
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                    documents
                    Text(renewalTerms(for: .annualOffer))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, ForgeTheme.Space.gutter)
                .padding(.bottom, ForgeTheme.Space.section)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            pinned(
                title: offerButtonTitle,
                isEnabled: store.annualOffer != nil,
                action: { purchase(.annualOffer) }
            ) {
                Button(PremiumCopy.offerDecline) { isShowingOffer = false }
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(minHeight: 44)
            }
        }
    }

    /// The storefront's own annual price, struck through — and only when it
    /// is what the annual plan really costs here, and more than the offer.
    private var struckAnnualPrice: String? {
        guard let annual = store.annual, let offer = store.annualOffer, annual.price > offer.price,
              let period = annual.subscription?.subscriptionPeriod
        else { return nil }
        return PremiumCopy.price(annual.displayPrice, value: period.value, unit: period.unit)
    }

    private var offerLine: String? {
        guard let offer = store.annualOffer, let period = offer.subscription?.subscriptionPeriod else { return nil }
        return PremiumCopy.offerLine(
            price: offer.displayPrice,
            perMonth: PremiumCopy.perMonth(
                price: offer.price, value: period.value, unit: period.unit, format: offer.priceFormatStyle
            ),
            trialDays: trialDays(for: .annualOffer)
        )
    }

    private var offerButtonTitle: String {
        guard let offer = store.annualOffer else { return PremiumCopy.buttonTitle(startsFreeWeek: false) }
        return PremiumCopy.offerButton(
            price: offer.displayPrice, startsFreeWeek: trialDays(for: .annualOffer) != nil
        )
    }

    // MARK: - The button, pinned

    /// The one action, and what is said under it. Pinned beneath the scroll,
    /// so at the largest text sizes everything above scrolls and this stays
    /// where a thumb expects it.
    private func pinned<Below: View>(
        title: String, isEnabled: Bool, action: @escaping () -> Void,
        @ViewBuilder below: () -> Below
    ) -> some View {
        VStack(spacing: ForgeTheme.Space.tight) {
            if isWaiting {
                quiet("Waiting for approval. Forge Pro turns on by itself when it goes through.")
            } else if let failure = store.failure {
                quiet(failure)
            }

            ForgePrimaryButton(title: title, isBusy: store.pending != nil || store.isRestoring, action: action)
                .disabled(!isEnabled)

            below()
        }
        .padding(.horizontal, ForgeTheme.Space.gutter)
        .padding(.top, ForgeTheme.Space.inner)
        .padding(.bottom, ForgeTheme.Space.tight)
        .background(alignment: .top) {
            Color.black
                .overlay(alignment: .top) {
                    Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func quiet(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.7))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 44)
    }

    // MARK: - Reading StoreKit

    /// The free week on this plan, in days, while it is on offer — or as it
    /// was when the purchase being settled began.
    private func trialDays(for plan: PremiumProduct) -> Int? {
        if let trialsAtPurchase { return trialsAtPurchase[plan] }
        return offeredTrialDays(for: plan)
    }

    private func offeredTrialDays(for plan: PremiumProduct) -> Int? {
        store.freeTrial(for: plan).flatMap {
            PremiumCopy.trialDays(value: $0.period.value, unit: $0.period.unit)
        }
    }

    private var startsFreeWeek: Bool { trialDays(for: selected) != nil }

    private func renewalTerms(for plan: PremiumProduct) -> String {
        guard let product = store.product(for: plan), let period = product.subscription?.subscriptionPeriod else {
            return "Subscriptions renew automatically until cancelled. Manage or cancel in your Apple Account settings."
        }
        return PremiumCopy.renewalTerms(
            planName: plan.planName, price: product.displayPrice,
            value: period.value, unit: period.unit, trialDays: trialDays(for: plan)
        )
    }

    // MARK: - Acting

    private func notNow() {
        guard isHard else { close(); return }
        // The offer once, ever — and only if it is there to be bought.
        if store.annualOffer != nil, ExitOffer().claim() {
            ForgeTelemetry.send(.exitOfferView)
            ForgeHaptics.shared.tap()
            isShowingOffer = true
        } else {
            hasDeclined = true
        }
    }

    private func purchase(_ plan: PremiumProduct) {
        guard let product = store.product(for: plan), !isSettling else { return }
        let freeWeek = trialDays(for: plan) != nil
        if freeWeek { TrialReminder.setWanted(remind) }
        isWaiting = false
        isSettling = true
        trialsAtPurchase = Dictionary(uniqueKeysWithValues: PremiumProduct.allCases.compactMap { each in
            offeredTrialDays(for: each).map { (each, $0) }
        })
        Task {
            switch await store.purchase(product) {
            case .bought(let startedTrial):
                ForgeTelemetry.send(startedTrial ? .trialStarted(plan) : .purchaseCompleted(plan))
                if plan == .annualOffer { ForgeTelemetry.send(.exitOfferAccepted) }
                ForgeHaptics.shared.ritualVerified()
                // The reminder was asked for with the free week: permission is
                // asked now, if iOS has never been asked, and the reminder is
                // scheduled by `ContentView` the moment it is given.
                if startedTrial, remind {
                    await ForgeNotifications.shared.allowTrialReminder()
                }
                isSettling = false
                close()
            case .waiting:
                isWaiting = true
                isSettling = false
                trialsAtPurchase = nil
            case .cancelled, .failed:
                isSettling = false
                trialsAtPurchase = nil
            }
        }
    }

    private func restore() {
        ForgeTelemetry.send(.restoreTapped)
        isSettling = true
        Task {
            await store.restore()
            isSettling = false
            if isDone { close() }
        }
    }
}

// MARK: - Presenting it

extension ForgeTelemetry.PaywallDoor: Identifiable {
    var id: String { rawValue }
}

/// Puts the paywall over whatever this is attached to, when `door` is set.
///
/// Reads the store from the environment, so a screen deep inside the app —
/// Plan, the weekly review, Appearance, the Forge tab's locked state — can open
/// the paywall without having to be handed a `ForgeStore` it has no other use
/// for. The onboarding paywall is not presented this way: it is a beat of the
/// first run (`FirstRunView`).
private struct PaywallPresenter: ViewModifier {
    @Binding var door: ForgeTelemetry.PaywallDoor?
    @Environment(ForgeStore.self) private var store: ForgeStore?

    func body(content: Content) -> some View {
        content.fullScreenCover(item: $door) { door in
            if let store {
                PaywallView(door: door, store: store) { self.door = nil }
            } else {
                // No store in the environment is a wiring mistake, not a state
                // anybody should be stuck in.
                Color.black.onAppear { self.door = nil }
            }
        }
    }
}

extension View {
    /// Presents Forge Pro whenever `door` is non-nil, and clears it on close.
    func paywall(_ door: Binding<ForgeTelemetry.PaywallDoor?>) -> some View {
        modifier(PaywallPresenter(door: door))
    }
}

// MARK: - The locked state

/// The one calm thing somebody without Forge Pro meets where new days are made:
/// the Forge tab's day controls, the daily challenge — and, from session S3,
/// the Arcs.
///
/// Two sentences and a button. It replaces the controls and nothing else: the
/// sword, the Blade tab, Becoming, the reviews, the widgets — the record — stay
/// exactly as they were (`PremiumGate.isLocked`). Never shown during the first
/// run, and never over a summary, a pull or a celebration
/// (`PremiumGate.showsLockedState`).
struct ProLockedState: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: ForgeTheme.Space.tight) {
            Text(PremiumCopy.lockedTitle)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(PremiumCopy.lockedLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForgeButton(title: "Continue") {
                ForgeHaptics.shared.tap()
                onContinue()
            }
            .padding(.top, ForgeTheme.Space.tight)
            .accessibilityHint(Text("Opens Forge Pro"))
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(ForgeTheme.Space.gutter)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - A locked control

/// An AI feature somebody has reached without it. Tapping it is asking, and
/// opens the paywall every time.
struct ProLockedRow: View {
    let feature: ProFeature
    let action: () -> Void

    var body: some View {
        Button {
            ForgeHaptics.shared.tap()
            action()
        } label: {
            HStack(spacing: ForgeTheme.Space.inner) {
                Image(systemName: feature.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(feature.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(feature.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: ForgeTheme.Space.tight)
                ProBadge()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .forgeCard(radius: ForgeTheme.Radius.control)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens Forge Pro"))
    }
}

/// "PRO", with a lock. The one mark every locked control wears.
struct ProBadge: View {
    var body: some View {
        Label("PRO", systemImage: "lock.fill")
            .font(.caption2.weight(.bold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("Forge Pro"))
    }
}

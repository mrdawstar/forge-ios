import StoreKit
import SwiftUI

/// Forge Pro, and the only screen in the app that sells anything.
///
/// # What is on it, top to bottom
///
/// The sword in the stone, on black. One sentence that says the deal plainly —
/// *Forge is free. Pro reads your record back to you.* — and then the three
/// things Pro adds (`ProFeature`), no more. The three plans with annual chosen,
/// the one button, what renewing means, Restore, and the two documents.
///
/// # What it will not do
///
/// - **Print a price it was not given.** Every figure is `Product.displayPrice`
///   and every period is the product's own; the words around them are built by
///   `PremiumCopy`. A storefront in another currency gets its own numbers.
/// - **Offer a trial somebody cannot take.** "7 days free" is printed only when
///   StoreKit says this Apple Account is eligible — see `ForgeStore.trial`.
/// - **Hide the way out.** "Not now" is pinned above the scroll and never
///   moves, never fades in late, and never needs a second tap.
/// - **Open itself.** Something else decides when this appears — a door in
///   `PremiumInvitation`, or somebody tapping a locked control — and nothing
///   here can re-present it.
struct PaywallView: View {
    let door: ForgeTelemetry.PaywallDoor
    @Bindable var store: ForgeStore
    let onClose: () -> Void

    @State private var selected: PremiumProduct = .annual
    @State private var hasReportedView = false
    /// Set when the screen closes because somebody now owns Pro, so the close
    /// is not also counted as a dismissal.
    @State private var didUnlock = false
    /// Ask-to-buy, or a bank still thinking about it.
    @State private var isWaiting = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    hero
                    headline
                    benefits
                    plans
                    buy
                    fine
                }
                .padding(.horizontal, ForgeTheme.Space.gutter)
                .padding(.bottom, ForgeTheme.Space.chapter)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) { topBar }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !hasReportedView else { return }
            hasReportedView = true
            ForgeTelemetry.send(.paywallView(door))
            // Annual is the default, unless it is the one that did not load.
            if store.product(for: selected) == nil, let first = availablePlans.first {
                selected = first
            }
        }
        .task {
            // The retry, and the first load for anybody who opened this before
            // the launch request came back.
            if store.status != .ready { await store.refresh() }
        }
        // Bought here, restored here, or approved on another device while this
        // was open: the screen has nothing left to say.
        .onChange(of: store.isPremium) { _, isPremium in
            guard isPremium else { return }
            didUnlock = true
            onClose()
        }
    }

    // MARK: - The way out

    private var topBar: some View {
        HStack {
            Button("Not now") { dismiss() }
                .font(.body.weight(.medium))
                .foregroundStyle(ForgeTheme.cream.opacity(0.85))
                .padding(.vertical, 10)
                .contentShape(.rect)
                .accessibilityHint(Text("Closes Forge Pro. Nothing changes."))
            Spacer()
        }
        .padding(.horizontal, ForgeTheme.Space.gutter)
        .background(Color.black.opacity(0.85))
    }

    private func dismiss() {
        if !didUnlock { ForgeTelemetry.send(.paywallDismissed(door)) }
        onClose()
    }

    // MARK: - The sword, and the sentence

    private var hero: some View {
        Image("hero")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(height: 260)
            .frame(maxWidth: .infinity)
            .clipped()
            // Faded into the black at the foot, so the stone sits in the page
            // rather than on it.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.72),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .accessibilityHidden(true)
    }

    private var headline: some View {
        VStack(spacing: ForgeTheme.Space.tight) {
            Text("FORGE PRO")
                .font(ForgeTheme.overline)
                .kerning(ForgeTheme.overlineKerning)
                .foregroundStyle(ForgeTheme.cream.opacity(0.75))

            Text("Forge is free. Pro reads your record back to you.")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, ForgeTheme.Space.row)
        .padding(.bottom, ForgeTheme.Space.section)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Space.row) {
            ForEach(ProFeature.allCases, id: \.self) { feature in
                HStack(alignment: .top, spacing: ForgeTheme.Space.inner) {
                    Image(systemName: feature.symbol)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(ForgeTheme.cream)
                        .frame(width: 26)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(feature.detail)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.bottom, ForgeTheme.Space.section)
    }

    // MARK: - The three plans

    private var availablePlans: [PremiumProduct] {
        PremiumProduct.displayOrder.filter { store.product(for: $0) != nil }
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
                Button("Try again") { Task { await store.refresh() } }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ForgeTheme.cream)
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

    private func planRow(_ plan: PremiumProduct, product: Product) -> some View {
        let isChosen = selected == plan
        return Button {
            guard !isChosen else { return }
            ForgeHaptics.shared.detent()
            withAnimation(.forgeSelection) { selected = plan }
        } label: {
            HStack(spacing: ForgeTheme.Space.inner) {
                Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isChosen ? ForgeTheme.cream : .white.opacity(0.35))

                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.planName)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(priceLine(plan, product: product))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(ForgeTheme.Space.row)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ForgeTheme.Radius.control, style: .continuous)
                    .fill(.white.opacity(isChosen ? 0.10 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ForgeTheme.Radius.control, style: .continuous)
                    .strokeBorder(isChosen ? ForgeTheme.cream.opacity(0.8) : .white.opacity(0.12), lineWidth: 1)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }

    /// "7 days free, then $49.99/year", "$9.99/month", "$99.99 once" — every
    /// figure from StoreKit.
    private func priceLine(_ plan: PremiumProduct, product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else {
            return PremiumCopy.lifetimeLine(price: product.displayPrice)
        }
        let trial = plan == .annual ? store.trial : nil
        return PremiumCopy.subscriptionLine(
            price: product.displayPrice,
            value: period.value,
            unit: period.unit,
            freeTrial: trial.map { (value: $0.period.value, unit: $0.period.unit) }
        )
    }

    // MARK: - The button

    private var buy: some View {
        VStack(spacing: ForgeTheme.Space.tight) {
            ForgePrimaryButton(
                title: buyTitle,
                isBusy: store.pending != nil || store.isRestoring
            ) {
                purchase()
            }
            .disabled(store.product(for: selected) == nil)
            .padding(.top, ForgeTheme.Space.section)

            if isWaiting {
                Text("Waiting for approval. Forge Pro turns on by itself when it goes through.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            } else if let failure = store.failure {
                Text(failure)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            Button("Restore purchases") { restore() }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.75))
                .frame(minHeight: 44)
                .disabled(store.isRestoring || store.pending != nil)
        }
    }

    private var buyTitle: String {
        switch selected {
        case .annual:
            if let trial = store.trial {
                return "Start \(PremiumCopy.trialLength(value: trial.period.value, unit: trial.period.unit)) free"
            }
            return "Subscribe yearly"
        case .monthly:
            return "Subscribe monthly"
        case .lifetime:
            return "Buy once"
        }
    }

    private func purchase() {
        guard let product = store.product(for: selected) else { return }
        let plan = selected
        isWaiting = false
        Task {
            switch await store.purchase(product) {
            case .bought(let startedTrial):
                ForgeTelemetry.send(startedTrial ? .trialStarted(plan) : .purchaseCompleted(plan))
                ForgeHaptics.shared.ritualVerified()
                didUnlock = true
                onClose()
            case .waiting:
                isWaiting = true
            case .cancelled, .failed:
                break
            }
        }
    }

    private func restore() {
        ForgeTelemetry.send(.restoreTapped)
        Task {
            if await store.restore() {
                didUnlock = true
                onClose()
            }
        }
    }

    // MARK: - What renewing means, and the documents

    private var fine: some View {
        VStack(spacing: ForgeTheme.Space.row) {
            Text(disclosure)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: ForgeTheme.Space.row) {
                if let terms = ForgeLinks.appleEULA {
                    Link("Terms of Use (EULA)", destination: terms)
                }
                if let privacy = ForgeLinks.privacy {
                    Link("Privacy Policy", destination: privacy)
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.top, ForgeTheme.Space.row)
    }

    /// The auto-renewal terms for the plan that is chosen, with its own price
    /// and period — what App Review checks for beside the button.
    private var disclosure: String {
        guard let product = store.product(for: selected) else {
            return "Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel them in your Apple Account settings."
        }
        guard let period = product.subscription?.subscriptionPeriod else {
            return "\(selected.planName) is a one-time purchase of \(product.displayPrice). It never renews and is never charged again."
        }
        let length = PremiumCopy.periodNoun(value: period.value, unit: period.unit)
        var text = "\(selected.planName) is an auto-renewing subscription at \(product.displayPrice) per \(length)."
        if selected == .annual, let trial = store.trial {
            let free = PremiumCopy.trialLength(value: trial.period.value, unit: trial.period.unit)
            text += " The first \(free) are free; payment is charged to your Apple Account when the trial ends unless you cancel before then."
        } else {
            text += " Payment is charged to your Apple Account when you confirm the purchase."
        }
        text += " It renews automatically for the same price and length unless cancelled at least 24 hours before the end of the current period, and renewal is charged within the 24 hours before that. Manage or cancel any time in your Apple Account settings."
        return text
    }
}

// MARK: - Presenting it

extension ForgeTelemetry.PaywallDoor: Identifiable {
    var id: String { rawValue }
}

/// Puts the paywall over whatever this is attached to, when `door` is set.
///
/// Reads the store from the environment, so a sheet deep inside the app —
/// the weekly review, a chapter close, Plan, Appearance — can open the paywall
/// without having to be handed a `ForgeStore` it has no other use for.
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

// MARK: - The chapter-close door

/// Door 3: the invitation at the close of a chapter.
///
/// This is where 1.0's `PremiumInvitation` used to put its one card, and the
/// argument for the moment is unchanged: somebody has deliberately stopped,
/// read six weeks back, and is deciding what the next six are for. It is one
/// card at the foot of the screen, below everything they came to read, and it
/// is shown once — see `PremiumInvitation.Door.chapterClose`.
struct PremiumInvitationView: View {
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Space.tight) {
            Text("FORGE PRO")
                .font(ForgeTheme.overline)
                .kerning(ForgeTheme.overlineKerning)
                .foregroundStyle(.tertiary)

            Text("Six weeks is a record worth reading.")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            Text("Forge stays free. Pro reads it back to you: a Weekly Reading every week, Plan in your own words, and eight accents.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("See Forge Pro") {
                ForgeHaptics.shared.tap()
                onOpen()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ForgeTheme.accent)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ForgeTheme.Space.row)
        .forgeCard(radius: ForgeTheme.Radius.card)
    }
}

// MARK: - A locked control

/// A Pro feature somebody has reached without Pro. Tapping it is asking, and
/// opens the paywall every time — only the unprompted doors are rationed.
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

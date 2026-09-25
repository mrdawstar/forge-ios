import SwiftUI

/// What happens when a marker somebody set for themselves comes true.
///
/// Deliberately the same shape and the same length as the day summary: a dark
/// field, one glyph, two lines, and it goes away on its own. Forge already has
/// a vocabulary for "something happened" — `DaySummaryView` and
/// `SwordUnlockOverlay` — and a third one with confetti in it would be a
/// different app arriving for ten seconds.
///
/// **No reward.** Nothing is unlocked, nothing is credited, and there is no
/// share sheet. The milestone was the point; being told it landed is the whole
/// of what is owed. That restraint is the same one `Milestone` is written
/// under, and it is why this can be shown at all — a celebration that hands out
/// a prize turns the marker into a thing to farm.
struct MilestoneCelebration: View {
    let milestone: CustomMilestone
    let subtitle: String
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    var body: some View {
        ZStack {
            // The same scrim `SwordUnlockOverlay` uses, and for a reason worth
            // writing down: a translucent *black* scrim does almost nothing on
            // this app. Forge is black, so 60% black over it separates nothing
            // — the heatmap and the rows behind read straight through the
            // sentence sitting on top of them. A material blurs rather than
            // darkens, which is the only thing that actually pushes a dark
            // screen back behind another one.
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            VStack(spacing: 0) {
                Image(systemName: milestone.symbol)
                    .font(.system(size: 40, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(ForgeTheme.accent)
                    .frame(width: 108, height: 108)
                    .glassEffect(.regular.tint(ForgeTheme.accent.opacity(0.18)), in: .circle)
                    .scaleEffect(landed || reduceMotion ? 1 : 0.86)
                    .opacity(landed || reduceMotion ? 1 : 0)

                Text(milestone.name)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)
                    .padding(.horizontal, 32)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.horizontal, 32)

                Button(action: dismiss) {
                    Text("Good")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(ForgeTheme.cream)
                .foregroundStyle(Color(red: 0.063, green: 0.063, blue: 0.078))
                .padding(.horizontal, 40)
                .padding(.top, 34)
            }
            .opacity(landed || reduceMotion ? 1 : 0)
        }
        .onAppear {
            ForgeHaptics.shared.ritualVerified()
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { landed = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(Text("\(milestone.name). \(subtitle)"))
    }

    private func dismiss() {
        ForgeHaptics.shared.tap()
        onDismiss()
    }
}

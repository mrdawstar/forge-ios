import SwiftUI

/// What an honor activity gets instead of a checkbox.
///
/// The whole tier rests on this screen. A tick in a list says *the app recorded
/// something*; this says *you said so, and that is enough* — which is the only
/// honest thing an app can offer about a prayer or four minutes of sitting
/// still. There is no camera, no progress bar, and nothing that implies anyone
/// is checking, because nobody is.
struct HonorPromptView: View {
    let ritual: Ritual
    let onKept: () -> Void
    /// "Let Apple Health check this", on an activity that was in the week
    /// before 1.1 made it measurable and so stayed Your Word (`HealthLedger`).
    /// Read once, when the prompt opens. Shown once: `onOfferShown` writes
    /// that down, and the parent then passes false.
    /// The line under the name. On an activity Apple Health checks, the
    /// prompt only appears when Health has not ticked it off, so the honest
    /// sentence there is a different one (`ForgeTabView`).
    var subtitle = "No one is checking this one."
    var offersHealth = false
    var onLetHealthCheck: () -> Void = {}
    var onOfferShown: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    /// Decided when the prompt opens and held, so writing down that the offer
    /// was shown does not take the button away while it is on screen.
    @State private var showsOffer: Bool?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            RitualGlyph(ritual: ritual, size: 34)
                .frame(width: 96, height: 96)
                .glassEffect(.regular, in: .circle)

            Text(ritual.label)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.top, 22)
                .padding(.horizontal, 32)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 32)

            Spacer(minLength: 0)

            Button {
                ForgeHaptics.shared.ritualVerified()
                onKept()
            } label: {
                Text("I kept my promise")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(ForgeTheme.cream)
            .foregroundStyle(Color(red: 0.063, green: 0.063, blue: 0.078))
            .padding(.horizontal, 24)

            // Deliberately quiet, and deliberately not "Cancel" — leaving is not
            // a failure, and the wording should not make it feel like one.
            Button("Not yet") { dismiss() }
                .font(.footnote.weight(.medium))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.top, 16)
                .padding(.bottom, 8)

            // Asked once, here, where the activity is in front of somebody:
            // their own activity never changes how it is checked unasked.
            if showsOffer == true {
                Button {
                    ForgeHaptics.shared.tap()
                    onLetHealthCheck()
                } label: {
                    Label("Let Apple Health check this", systemImage: "heart")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ForgeTheme.accent)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            guard showsOffer == nil else { return }
            showsOffer = offersHealth
            if offersHealth { onOfferShown() }
        }
        .padding(.vertical, 28)
        // A second detent, because the first is a fixed height. At accessibility
        // text sizes the label and the button outgrow 400pt, and a sheet that
        // cannot be dragged taller would simply clip the only button on it.
        .presentationDetents([.height(400), .large])
        .presentationCornerRadius(ForgeTheme.Radius.sheet)
        .presentationDragIndicator(.visible)
    }
}

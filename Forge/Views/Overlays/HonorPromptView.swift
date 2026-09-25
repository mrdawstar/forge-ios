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
    @Environment(\.dismiss) private var dismiss

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

            Text("No one is checking this one.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

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

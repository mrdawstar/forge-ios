import SwiftUI

/// The screen somebody sees when they come back.
///
/// The whole argument is in `ReEntry`. What this file has to get right is the
/// restraint: three short lines, one button, and nothing else on screen. Every
/// addition considered here — the heatmap, the identity, what they used to do on
/// a Tuesday, an encouraging line — makes it a screen about the absence rather
/// than a screen about today.
///
/// **The count is the loudest thing on it**, because the count is the argument.
/// Somebody who has been away for three weeks is deciding whether they are still
/// a person who does this, and two hundred and six days kept is the only
/// evidence in the app that says yes.
struct ReturnView: View {
    let daysKept: Int
    let daysAway: Int
    /// The one small thing on offer. Nil for a day with nothing on it, and the
    /// screen simply loses its button rather than inventing an activity.
    let activity: Ritual?
    let onBegin: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            // Forge's own dark rather than a colour of its own. This is the app
            // opening, not a modal about a mistake.
            ForgeTheme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: ForgeTheme.Space.row) {
                    // The absence, named once and never characterised. See
                    // `ReEntry.absence(days:)`.
                    Text(ReEntry.absence(days: daysAway))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Spelled, because a figure is a score and a sentence is a
                    // fact about a person. `ForgeCount` hands back digits past a
                    // hundred, which is where the words get longer than the line.
                    Text(count)
                        .font(.system(size: 40, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(ReEntry.reassurance(daysKept: daysKept))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 34)

                Spacer(minLength: 0)

                offer
                    .padding(.horizontal, ForgeTheme.Space.gutter)
                    .padding(.bottom, ForgeTheme.Space.row)
            }
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
        }
        .onAppear {
            guard !reduceMotion else { shown = true; return }
            withAnimation(.reveal(0.6).delay(0.1)) { shown = true }
        }
    }

    /// "Two hundred and six days kept." One sentence, and the only number on
    /// the screen. Nothing here can go down: days kept is cumulative by
    /// construction, which is exactly why it is the thing being shown.
    private var count: String {
        daysKept == 1 ? "One day kept." : "\(ForgeCount.spelled(daysKept)) days kept."
    }

    /// One thing, small, today.
    ///
    /// Not the day they had before they left — see `ForgeViewModel.returnActivity`.
    /// The button names the activity out loud so the ask is legible before it is
    /// accepted: "Do one thing" is a commitment to something unspecified, and
    /// "Drink water" is a commitment somebody can make in the two seconds they
    /// are giving this screen.
    @ViewBuilder
    private var offer: some View {
        VStack(spacing: ForgeTheme.Space.tight) {
            if let activity {
                Button {
                    ForgeHaptics.shared.tap()
                    onBegin()
                } label: {
                    Text("Start with \(activity.label.lowercased())")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .contentShape(.rect)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(ForgeTheme.cream)
                .foregroundStyle(ForgeTheme.bg)
            }

            // Always available and never the loud option. Somebody who opened
            // the app to look at their history is entitled to do that without
            // agreeing to anything.
            Button("Just open Forge") { onDismiss() }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
        }
    }
}

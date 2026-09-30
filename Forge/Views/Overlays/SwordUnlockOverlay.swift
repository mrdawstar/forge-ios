import SwiftUI

/// A blade has been earned.
///
/// Staged rather than presented all at once — the scrim settles, the blade
/// rises and catches the light, the name arrives, and only then do the choices
/// appear. The blade is *not* equipped behind the user's back: carrying a
/// different sword is a decision they may have made deliberately, so equipping
/// is the primary action here, one tap away, and declining keeps what they have.
struct SwordUnlockOverlay: View {
    let sword: Sword
    /// Name of the blade currently carried, for the decline action.
    let currentName: String
    /// Days kept, for the Proof Card. Read off the record by the caller.
    var daysKept: Int = 0
    var onEquip: () -> Void
    var onKeep: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var bladeIn = false
    @State private var textIn = false
    @State private var actionsIn = false
    @State private var sheen: Double = 0

    var body: some View {
        ZStack {
            scrim
            content
        }
        .task { await stage() }
    }

    // MARK: Backdrop

    private var scrim: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            // A bloom behind the blade so it reads as lit from within the
            // scene rather than pasted on top of a blur.
            RadialGradient(
                colors: [ForgeTheme.cream.opacity(0.13), .clear],
                center: UnitPoint(x: 0.5, y: 0.38),
                startRadius: 0,
                endRadius: 300
            )
            .ignoresSafeArea()
            .opacity(bladeIn ? 1 : 0)
            .allowsHitTesting(false)
        }
    }

    // MARK: Content

    private var content: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            // The art gives way at the accessibility sizes, where the name and
            // the note need the room and the blade carries no words. At 280
            // points the note under the name was cut to one line and an
            // ellipsis on a standard phone.
            SwordArt(
                assetName: sword.asset,
                width: typeSize.isAccessibilitySize ? 100 : 146,
                height: typeSize.isAccessibilitySize ? 190 : 280,
                solid: 0.58,
                sheen: reduceMotion ? nil : sheen
            )
            .scaleEffect(bladeIn ? 1 : 0.84)
            .offset(y: bladeIn ? 0 : 26)
            .opacity(bladeIn ? 1 : 0)

            VStack(spacing: 9) {
                // Not "unlocked". Nothing here was locked and nothing was won —
                // the days happened and this is what they add up to.
                Text("A NEW BLADE")
                    .font(.caption2.weight(.semibold))
                    .tracking(2.4)
                    .foregroundStyle(ForgeTheme.cream.opacity(0.9))

                Text(sword.title)
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(sword.note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 280)
            }
            .padding(.top, 26)
            .opacity(textIn ? 1 : 0)
            .offset(y: textIn ? 0 : 14)

            Spacer(minLength: 24)

            VStack(spacing: 10) {
                ForgeButton(title: "Carry it") { onEquip() }

                ForgeButton(title: "Keep \(currentName)", style: .secondary) { onKeep() }

                // The Proof Card: a quiet third action, arriving with the other
                // two once the celebration has staged — never over the pull and
                // never before the blade has landed. It does not close the
                // overlay and opens nothing until a format is picked.
                ProofCardButton(occasion: .blade(name: sword.title), daysKept: daysKept)
                    .allowsHitTesting(actionsIn)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 36)
            .opacity(actionsIn ? 1 : 0)
            .offset(y: actionsIn ? 0 : 12)
        }
    }

    // MARK: Staging

    private func stage() async {
        ForgeHaptics.shared.swordUnlocked()
        ForgeAudio.shared.ring()

        guard !reduceMotion else {
            withAnimation(.easeOut(duration: 0.3)) {
                bladeIn = true
                textIn = true
                actionsIn = true
            }
            return
        }

        withAnimation(.spring(response: 0.78, dampingFraction: 0.78)) { bladeIn = true }

        try? await Task.sleep(for: .milliseconds(180))
        withAnimation(.smooth(duration: 0.5)) { textIn = true }

        // The light travels the blade once it has arrived, not while it is
        // still moving — two motions at once reads as noise.
        try? await Task.sleep(for: .milliseconds(150))
        withAnimation(.timingCurve(0.3, 0.7, 0.4, 1, duration: 1.25)) { sheen = 1 }

        try? await Task.sleep(for: .milliseconds(120))
        withAnimation(.smooth(duration: 0.45)) { actionsIn = true }
    }
}

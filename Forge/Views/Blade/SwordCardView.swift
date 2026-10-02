import SwiftUI

/// A sword portrait for the collection: the sprite anchored at the **top**, so
/// the pommel, grip and crossguard are always fully in frame, with the blade
/// dissolving into nothing instead of being cut off at the card's edge.
///
/// Every sprite is 483×1771 — three and a half times taller than it is wide —
/// so a card-shaped crop can only ever hold the top half of one. The old card
/// centred the sprite inside a 120pt box and clipped it, which put the crop
/// window over the *middle* of the blade: the hilt was off the top of the card
/// and the blade ended on a hard horizontal line at the bottom.
struct SwordArt: View {
    let assetName: String
    var width: CGFloat
    var height: CGFloat
    /// Fraction of the frame held fully opaque before the blade starts to go.
    var solid: Double = 0.52
    /// Cross-fade when `assetName` changes rather than swapping on one frame.
    var crossfade: Bool = false
    /// 0…1 position of a highlight travelling the blade, or nil for none. Uses
    /// the same `SheenMask` as the forge, so a blade catches the light the same
    /// way wherever it is drawn.
    var sheen: Double?

    private static let aspect: CGFloat = 1771.0 / 483.0
    private var spriteHeight: CGFloat { width * Self.aspect }

    var body: some View {
        content
            .frame(width: width, height: height, alignment: .top)
            // Masking to the frame is what crops the blade — and because the
            // mask reaches zero before the frame's edge, the crop has no edge.
            .mask(
                LinearGradient(
                    stops: Self.fadeStops(solid: solid),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    @ViewBuilder
    private var content: some View {
        if crossfade {
            // A single-element ForEach keyed by the asset name: changing the
            // name removes one child and inserts another, which is what gives
            // us a real cross-fade instead of an image swapping on one frame.
            ZStack {
                ForEach([assetName], id: \.self) { name in
                    sprite(name).transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.42), value: assetName)
        } else {
            sprite(assetName)
        }
    }

    private func sprite(_ name: String) -> some View {
        Image(name)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: width, height: spriteHeight)
            .overlay { sheenPass(name) }
    }

    /// A brightened copy of the sprite behind the travelling mask. Being the
    /// sprite, it can never spill outside the blade's silhouette.
    @ViewBuilder
    private func sheenPass(_ name: String) -> some View {
        if let sheen, sheen > 0, sheen < 1 {
            Image(name)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: width, height: spriteHeight)
                .brightness(0.36)
                .saturation(0.45)
                .mask(SheenMask(progress: sheen, width: width, height: spriteHeight))
                .opacity(SheenMask.opacity(for: sheen) * 0.95)
                .allowsHitTesting(false)
        }
    }

    /// Held solid over the hilt, then feathered across several stops so the
    /// blade thins out rather than stopping.
    static func fadeStops(solid: Double) -> [Gradient.Stop] {
        let tail = 1 - solid
        return [
            .init(color: .black, location: 0),
            .init(color: .black, location: solid),
            .init(color: .black.opacity(0.72), location: solid + tail * 0.28),
            .init(color: .black.opacity(0.34), location: solid + tail * 0.56),
            .init(color: .black.opacity(0.10), location: solid + tail * 0.80),
            .init(color: .clear, location: 1),
        ]
    }
}

// MARK: - Card

struct SwordCardView: View {
    let sword: Sword
    let isEquipped: Bool
    let isNew: Bool
    let onTap: () -> Void

    private static let cardWidth: CGFloat = 112
    private static let artHeight: CGFloat = 138
    private static let radius: CGFloat = 22

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                art
                caption
            }
            .frame(width: Self.cardWidth)
            .forgeInteractiveCard(radius: Self.radius)
            .overlay { stateRing }
            .overlay(alignment: .topTrailing) { unseenMark }
            .contentShape(.rect(cornerRadius: Self.radius, style: .continuous))
        }
        .buttonStyle(SwordCardPress())
        .accessibilityLabel(Text(sword.title))
        .accessibilityValue(Text(accessibilityState))
        .accessibilityHint(Text(sword.isUnlocked ? "Double tap to carry it" : ""))
    }

    // MARK: Art

    private var art: some View {
        ZStack {
            SwordArt(
                assetName: sword.asset,
                width: 72,
                height: Self.artHeight
            )
            .saturation(sword.isUnlocked ? 1 : 0)
            .brightness(sword.isUnlocked ? 0 : -0.16)
            .opacity(sword.isUnlocked ? 1 : 0.3)

            if !sword.isUnlocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .glassEffect(.regular, in: .circle)
            }
        }
        .frame(width: Self.cardWidth, height: Self.artHeight)
        .padding(.top, 12)
        .animation(.smooth(duration: 0.5), value: sword.isUnlocked)
    }

    // MARK: Caption

    private var caption: some View {
        VStack(spacing: 3) {
            Text(sword.name)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(sword.isUnlocked ? .primary : .secondary)

            status
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .padding(.horizontal, 8)
        .padding(.top, 9)
        .padding(.bottom, 13)
        .animation(.smooth(duration: 0.4), value: isEquipped)
    }

    @ViewBuilder
    private var status: some View {
        if !sword.isUnlocked {
            Text(sword.requirementLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        } else if isEquipped {
            // The carrying mark is a word and a dot, not a badge stack — the
            // ring below is already carrying most of the signal.
            HStack(spacing: 3.5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9.5))
                Text("Carrying")
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(ForgeTheme.cream)
        } else {
            Text("Yours")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: State marks

    /// One ring, three weights. Equipped is a clear hairline, newly earned is a
    /// whisper of the same colour, everything else is nothing at all — so the
    /// three states read at a glance without three different decorations.
    private var stateRing: some View {
        RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
            .strokeBorder(
                ForgeTheme.cream.opacity(isEquipped ? 0.85 : (isNew ? 0.34 : 0)),
                lineWidth: isEquipped ? 1.3 : 1
            )
            .animation(.smooth(duration: 0.45), value: isEquipped)
            .animation(.smooth(duration: 0.45), value: isNew)
            .allowsHitTesting(false)
    }

    /// A blade you have not looked at yet.
    ///
    /// A dot rather than the "NEW" capsule this used to be. The job is to walk
    /// somebody over to a card they have not seen, which a mark in the corner
    /// does perfectly well — a shouted word turns the same cue into a badge, and
    /// Forge does not hand out badges.
    private var unseenMark: some View {
        Circle()
            .fill(ForgeTheme.cream)
            .frame(width: 7, height: 7)
            .padding(11)
            .opacity(isNew ? 1 : 0)
            .scaleEffect(isNew ? 1 : 0.4, anchor: .topTrailing)
            .animation(.spring(response: 0.42, dampingFraction: 0.68), value: isNew)
            .allowsHitTesting(false)
    }

    private var accessibilityState: String {
        if !sword.isUnlocked { return "Not yet. \(sword.requirementLabel)." }
        if isEquipped { return "Carrying" }
        return isNew ? "Yours, not seen yet" : "Yours"
    }
}

/// A press that reads as the card being pushed into the glass rather than a
/// button being clicked.
private struct SwordCardPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.962 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

// MARK: - Temper marks

/// The blade's temper marks: one notch for every ninety days kept past
/// Enduring (`Ladder.temperMarks`), drawn under the blade on the Blade tab and
/// on every Proof Card.
///
/// **Notches, in fives**, the way a count is kept on anything that is cut:
/// short vertical marks, a wider gap after every fifth, a new row after six
/// groups. A ten-year practice is thirty-eight of them, so the drawing has to
/// stay legible at any count rather than at the first few — and a tally reads
/// as a record of time where a row of stars or pips would read as a score.
///
/// In the room's cream, quieter than the type around it. It draws nothing at
/// all for nought, so the card it sits on is unchanged for everybody short of
/// two hundred and seventy days.
struct TemperMarks: View {
    let count: Int
    /// The height of one notch; everything else is proportional to it.
    var tick: CGFloat = 9

    private static let perGroup = 5
    private static let groupsPerRow = 6

    private var groups: [Int] {
        guard count > 0 else { return [] }
        return stride(from: 0, to: count, by: Self.perGroup).map { min(Self.perGroup, count - $0) }
    }

    private var rows: [[Int]] {
        stride(from: 0, to: groups.count, by: Self.groupsPerRow).map {
            Array(groups[$0..<min($0 + Self.groupsPerRow, groups.count)])
        }
    }

    var body: some View {
        if count > 0 {
            VStack(spacing: tick * 0.55) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: tick * 0.9) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, marks in
                            HStack(spacing: tick * 0.42) {
                                ForEach(0..<marks, id: \.self) { _ in
                                    Capsule()
                                        .fill(ForgeTheme.cream.opacity(0.72))
                                        .frame(width: max(1.2, tick * 0.17), height: tick)
                                }
                            }
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(Ladder.temperLabel(count) ?? ""))
            .accessibilityHint(Text("One for every ninety days kept past Enduring"))
        }
    }
}

import SwiftUI

/// One marker of practice.
///
/// There is nothing to claim on this row and nothing is paid out by it — no
/// reward column, no seal, no trophy. A reached milestone is marked with the
/// same quiet tick the day list uses, and an unreached one shows how far along
/// it is because that is a true thing about somebody's practice rather than a
/// bar to be filled.
///
/// The row says three things about an unfinished one and they are deliberately
/// three, not one: **how far** (the bar), **how far as a number** (the
/// percentage), and **how much is left** (the count). They are the same fact in
/// three registers because people read progress in different ones — a bar is
/// felt, a percentage is compared, and "eighteen days to go" is the only one of
/// the three you can act on. The old row showed a bar and "12/30" and left the
/// arithmetic to the reader.
struct MilestoneRow: View {
    let milestone: Milestone
    /// Whether tapping the row opens it. True only for the ones somebody made:
    /// nothing about the shipped ladder is theirs to change — a world renames
    /// it, and that is all — so those rows are text, and announce themselves as
    /// text rather than as a button that does nothing.
    var isEditable = false

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            glyph

            VStack(alignment: .leading, spacing: 5) {
                header
                Text(milestone.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if !milestone.isReached { meter }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .forgeCard()
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(spokenValue))
        .accessibilityAddTraits(isEditable ? .isButton : [])
        .accessibilityHint(Text(isEditable ? "Double tap to change or delete it" : ""))
    }

    // MARK: - Pieces

    private var glyph: some View {
        Group {
            if let symbol = milestone.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(milestone.isReached ? ForgeTheme.accent : Color.secondary)
            } else {
                ForgeIconView(
                    key: milestone.iconKey,
                    size: 18,
                    color: milestone.isReached ? ForgeTheme.accent : .secondary
                )
            }
        }
        .frame(width: 38, height: 38)
        .glassEffect(
            milestone.isReached ? .regular.tint(ForgeTheme.accent.opacity(0.15)) : .regular,
            in: .circle
        )
    }

    /// The name, and the one mark that says it is done.
    ///
    /// The tick moved up here from the trailing edge of the row. It used to sit
    /// opposite the icon with the whole card between them, which read as a
    /// column of ticks down the right-hand side — a checklist, which is exactly
    /// what a milestone is not. Beside the name it is punctuation on a sentence.
    private var header: some View {
        HStack(spacing: 7) {
            Text(milestone.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)

            if milestone.isReached {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, ForgeTheme.accent)
                    .transition(.scale.combined(with: .opacity))
            }

            Spacer(minLength: 0)
        }
    }

    /// The bar, and the two numbers that read it out.
    private var meter: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: milestone.progress)
                .progressViewStyle(.linear)
                .tint(ForgeTheme.accent)
                .animation(.forgeRow, value: milestone.progress)

            // One line at ordinary sizes, two when the words need the room.
            // A percentage and a countdown squeezed onto one line at an
            // accessibility size was the pair that broke first — and a `Spacer`
            // shared between the two layouts would have grown vertically in the
            // stacked one, so each spells out its own spacing.
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    percentText
                    remainingText
                }
            } else {
                HStack(spacing: 8) {
                    percentText
                    Spacer(minLength: 0)
                    remainingText
                }
            }
        }
        .padding(.top, 3)
    }

    private var percentText: some View {
        Text("\(milestone.percent)%")
            .font(ForgeTheme.mono(10))
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
    }

    private var remainingText: some View {
        Text(milestone.remainingLabel)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var spokenValue: String {
        guard !milestone.isReached else { return "Reached" }
        return "\(milestone.percent) percent. \(milestone.remainingLabel)."
    }
}

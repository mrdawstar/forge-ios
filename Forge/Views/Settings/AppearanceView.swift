import SwiftUI

/// Choosing the colour the app is drawn in.
///
/// # Why this is not a colour picker
///
/// A `ColorPicker` is a tool, and a tool is the wrong object here. It offers an
/// infinity of answers to a question with eight good ones, it can produce a
/// tint that fails against dark glass, and — the part that actually matters —
/// it shows the colour as a square in a dialog rather than as the thing it is
/// about to become. Somebody choosing a theme is not choosing a colour; they
/// are choosing what their app looks like, and the only honest way to ask that
/// is to show them.
///
/// So: a live piece of the real interface at the top, and eight named swatches
/// under it. The preview is built from the same components the Forge tab uses —
/// `ProgressSegments`, the activity row's completion mark, the app's primary
/// button — rather than from shapes drawn to look like them, so it cannot
/// quietly stop being true.
///
/// # Why the choice applies instantly and there is no Done button
///
/// Because there is nothing to confirm. Nothing is destroyed, nothing is
/// computed, and the change is its own preview — a modal with Apply and Cancel
/// in front of a colour would make a two-second decision feel like a
/// transaction. Going back is one tap on the swatch that was there before, and
/// the previous choice is still on screen while the new one is being looked at.
struct AppearanceView: View {

    /// Read straight off the singleton. See `ForgeAppearance` — this is the one
    /// piece of state in the app that is not handed down, and the reason is
    /// written there.
    private var appearance: ForgeAppearance { ForgeAppearance.shared }

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Four across on a normal phone, two at the accessibility sizes, where a
    /// name under a swatch needs the whole half-width to stay on one line.
    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: ForgeTheme.Space.inner),
            count: typeSize.isAccessibilitySize ? 2 : 4
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ForgeTheme.Space.section) {
                preview

                VStack(alignment: .leading, spacing: ForgeTheme.Space.row) {
                    SectionHeading("Accent", detail: appearance.accent.note)

                    LazyVGrid(columns: columns, spacing: ForgeTheme.Space.row) {
                        ForEach(ForgeThemeAccent.allCases) { option in
                            swatch(option)
                        }
                    }
                }

                Text("The accent is the one colour Forge uses to mean *chosen*, *done* and *yours*. It never touches the room, the stone or the blade — those are the scene, and the scene is not a preference.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, ForgeTheme.Space.gutter)
            .padding(.top, ForgeTheme.Space.tight)
            .padding(.bottom, ForgeTheme.Space.chapter)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - What it looks like

    /// A real fragment of the Forge tab, tinted live.
    ///
    /// Three states in one card, because the accent means three different
    /// things and somebody choosing one should see all of them: it is the
    /// progress that has been made, the mark on a finished activity, and the
    /// fill of the button that commits something.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("2 OF 3")
                    .font(.caption2.weight(.semibold))
                    .tracking(2.4)
                    .foregroundStyle(.secondary)
                ProgressSegments(total: 3, done: 2)
            }
            .padding(.bottom, ForgeTheme.Space.row)

            previewRow("Walk outside", symbol: "sun.max", isDone: true)
            Rectangle()
                .fill(ForgeTheme.separator)
                .frame(height: 0.5)
                .padding(.leading, 34)
            previewRow("Read", symbol: "book", isDone: false)

            Text("Keep going")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    ForgeTheme.accent,
                    in: RoundedRectangle(cornerRadius: ForgeTheme.Radius.control, style: .continuous)
                )
                .padding(.top, ForgeTheme.Space.row)
        }
        .padding(ForgeTheme.Space.row)
        .forgeCard(radius: ForgeTheme.Radius.card)
        // The colour crossfades rather than snapping, so a run down the grid
        // reads as one surface changing its mind rather than as eight redraws.
        .animation(.easeInOut(duration: 0.28), value: appearance.accent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Preview, in \(appearance.accent.label)"))
    }

    private func previewRow(_ label: String, symbol: String, isDone: Bool) -> some View {
        HStack(spacing: ForgeTheme.Space.inner) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isDone ? .secondary : .primary)
                .strikethrough(isDone, color: .secondary)

            Spacer(minLength: 8)

            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .symbolRenderingMode(isDone ? .palette : .monochrome)
                .foregroundStyle(
                    isDone ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary),
                    AnyShapeStyle(ForgeTheme.accent)
                )
        }
        .padding(.vertical, 10)
    }

    // MARK: - The eight

    /// One colour, named.
    ///
    /// The ring sits *outside* the disc with a gap rather than as a border on
    /// it, which is the difference between "selected" and "this one has an
    /// outline": a stroke drawn on the swatch changes the colour somebody is
    /// trying to judge.
    private func swatch(_ option: ForgeThemeAccent) -> some View {
        let isChosen = appearance.accent == option
        return Button {
            guard !isChosen else { return }
            ForgeHaptics.shared.detent()
            withAnimation(.forgeSelection) { appearance.accent = option }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .strokeBorder(option.color, lineWidth: 2)
                        .opacity(isChosen ? 1 : 0)
                        .frame(width: 54, height: 54)

                    Circle()
                        .fill(option.color)
                        .frame(width: isChosen ? 38 : 44, height: isChosen ? 38 : 44)
                        .overlay {
                            // A hairline, so `bone` on a dark card and `forge`
                            // on a bright one both still read as a disc rather
                            // than as a hole.
                            Circle().strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
                        }
                }
                .frame(height: 54)

                Text(option.label)
                    .font(.caption2.weight(isChosen ? .semibold : .regular))
                    .foregroundStyle(isChosen ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(option.label))
        .accessibilityValue(Text(option.note))
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }
}

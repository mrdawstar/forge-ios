import SwiftUI

/// Which reading the panel is showing.
///
/// Two, and there will not be a third. Month lives on the Blade tab, where the
/// grid and the trends already are — putting it here would make the home screen
/// a second analytics screen, and the home screen is about what you are doing.
enum PanelMode: String, CaseIterable, Identifiable {
    case today, week

    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
    var spoken: String { self == .today ? "Today" : "This week" }
}

/// The one control layer, floating above the task panel.
///
/// # Why it is not on the panel
///
/// It was, and that was the mistake. Sitting inside the panel it became a second
/// header above the day's own header — two rows of chrome, four controls and a
/// grab handle stacked over three activities — and the list the whole screen
/// exists for was the smallest thing on it. Chrome that lives *inside* the thing
/// it controls always reads as part of the content.
///
/// So it is a separate surface with air around it. That air is doing real work:
/// it says the bar and the panel are different kinds of thing, it lets the panel
/// go back to exactly the geometry it was measured for, and it keeps the sword
/// visible between them.
///
/// # One navigation control, one action
///
/// Today/Week is navigation and is drawn as such — a real segmented control, the
/// only thing here with a filled state. The challenge is the **one** action, and
/// it is drawn as one: a named capsule, not a bare glyph among others.
///
/// **Plan used to sit beside it and no longer does.** It was a second glyph of
/// equal weight on a bar with room for one decision, and — the part that decided
/// it — everything Plan proposes is a change to *the week*: an hour moved, a
/// frequency eased, an activity taken off a Tuesday. It now opens from the
/// week's own menu, which is both where its output lands and the only screen on
/// which its output is legible. The home screen is left with what the home
/// screen is for: today, the week, and the one thing being offered.
///
/// It holds no state. Which mode is on and how the challenge is going are facts
/// held elsewhere and handed in, so this can never be the thing that disagrees
/// with the app.
struct ForgeControlBar: View {
    @Binding var mode: PanelMode
    /// How today's challenge is going, so the action can say so without a card
    /// on the home screen.
    var challengeState: ChallengeState
    var onChallenge: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    /// The bar's inner height. 38 leaves a 44pt bar once the 3pt of padding
    /// either side is on, which is the smallest a comfortable target gets.
    private let inner: CGFloat = 38

    /// How far apart two pieces of glass have to be before they stop reaching
    /// for each other.
    ///
    /// `GlassEffectContainer`'s spacing is the distance at which sibling shapes
    /// merge into one blob. Set to zero, so the two controls below stay two
    /// controls no matter how wide the phone is — while still being rendered in
    /// one pass, which is what lets them refract the scene consistently instead
    /// of looking like two unrelated cut-outs.
    private let mergeDistance: CGFloat = 0

    var body: some View {
        GlassEffectContainer(spacing: mergeDistance) {
            HStack(spacing: 0) {
                modePicker
                    .padding(3)
                    .glass()

                // The gap. Big enough that nobody reads the two as one control,
                // and it is the only thing in this file doing that job —
                // navigation and an action are different kinds of thing and the
                // space between them is what says so.
                Spacer(minLength: 12)

                challenge
                    .padding(3)
                    .glass()
            }
        }
    }

    // MARK: - Today / Week

    /// A hand-built segmented control rather than a `Picker`.
    ///
    /// `.segmented` draws its own opaque background, which on glass reads as a
    /// grey slab pasted onto it — the same reason `DayPicker` is custom. The
    /// behaviour is a picker's in every way that matters: one of two, always one
    /// selected, and the whole capsule is the target.
    private var modePicker: some View {
        HStack(spacing: 3) {
            ForEach(PanelMode.allCases) { option in
                Button {
                    guard mode != option else { return }
                    ForgeHaptics.shared.detent()
                    withAnimation(.forgeSelection) { mode = option }
                } label: {
                    Text(option.label)
                        .font(.caption2.weight(.semibold))
                        .tracking(1.3)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 14)
                        .frame(height: inner)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .foregroundStyle(mode == option ? AnyShapeStyle(.black) : AnyShapeStyle(.secondary))
                .background {
                    if mode == option {
                        Capsule()
                            .fill(ForgeTheme.cream)
                            // One shared geometry, so the pill slides between the
                            // two words instead of fading out and in somewhere
                            // else. This is the whole animation of the control.
                            .matchedGeometryEffect(id: "panelMode", in: selection)
                    }
                }
                .accessibilityLabel(Text(option.spoken))
                .accessibilityAddTraits(mode == option ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    @Namespace private var selection

    // MARK: - The one action

    /// The challenge, named.
    ///
    /// It was a bare glyph beside a second bare glyph, which is what a toolbar
    /// looks like — three seventeen-point marks of equal weight and no
    /// indication that one of them is the thing on offer today. With Plan moved
    /// to the week, there is exactly one action here and it can afford its own
    /// word: a mark, a label, and a state that reads at arm's length.
    ///
    /// **The colour is the state and there is no badge.** Unanswered, the mark
    /// takes the accent and the word takes the foreground — the one lit thing on
    /// a dark screen, which is all a dot was ever trying to say. Answered, both
    /// go quiet. Done, the mark fills. Nothing counts, nothing pulses and
    /// nothing is ever red.
    private var challenge: some View {
        Button {
            ForgeHaptics.shared.tap()
            onChallenge()
        } label: {
            HStack(spacing: 6) {
                ChallengeMark(size: 15, isFilled: challengeState == .completed)
                    .foregroundStyle(markStyle)

                // The word goes when the words elsewhere need the room. The mark
                // alone is still a target and still says what it does to anybody
                // who has pressed it once — and it is still a 44pt capsule,
                // because the padding is on the button and not on the label.
                if !typeSize.isAccessibilitySize {
                    Text("CHALLENGE")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.9)
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(labelStyle)
                }
            }
            .padding(.horizontal, 12)
            .frame(minWidth: inner)
            .frame(height: inner)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .animation(.forgeSelection, value: challengeState)
        .accessibilityLabel(Text("Daily challenge"))
        .accessibilityValue(Text(spokenChallenge))
        .accessibilityHint(Text("Today's challenge"))
    }

    private var markStyle: AnyShapeStyle {
        switch challengeState {
        case .offered, .completed: AnyShapeStyle(ForgeTheme.accent)
        case .accepted, .skipped: AnyShapeStyle(.secondary)
        }
    }

    private var labelStyle: AnyShapeStyle {
        challengeState == .offered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
    }

    private var spokenChallenge: String {
        switch challengeState {
        case .offered: "Waiting for you"
        case .accepted: "Taken on"
        case .skipped: "Skipped today"
        case .completed: "Done"
        }
    }
}

private extension View {
    /// One capsule of Liquid Glass, written once because there are two of them
    /// and they must be identical.
    ///
    /// `.regular` rather than `.clear`: these sit over a photographic scene, and
    /// clear glass over a bright patch of stone leaves the labels unreadable at
    /// exactly the moment somebody reaches for them. The hairline is what stops
    /// a capsule dissolving into a light part of that scene — one stroke, at the
    /// opacity of a system separator, because any more reads as a drawn border
    /// rather than a lit edge.
    func glass() -> some View {
        glassEffect(.regular, in: .capsule)
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
    }
}

/// The challenge's mark: one thing, aimed.
///
/// # What it replaces, and why the swords went
///
/// A pair of crossed swords, drawn as a 660pt vector and scaled down to
/// seventeen. Two objections, and the second is the fatal one. It was *thin* —
/// a hairline outline beside SF Symbols set at medium weight, so on a glass
/// capsule it read as a smudge rather than as a control, and at Lock Screen
/// contrast it barely read at all. And it was **medieval dressing**: Forge has
/// exactly one object in it, the blade in the stone, and it earns its place by
/// being the thing the day is about. A second, unrelated piece of weaponry
/// standing in for "today's challenge" is a costume — the same objection that
/// deleted the characters (see FORGE_CONTEXT §2c), in a smaller coat.
///
/// So the mark says what the thing actually is: **something set for today that
/// you can take on.** A flag is that and nothing else — not a trophy, not a
/// score, not a weapon — and it has the one property the swords never had, which
/// is that it fills. Taken and finished is `flag.fill`, in the accent, which is
/// the same grammar every completed thing in Forge is drawn with.
///
/// **`target` was tried first and is wrong**, for a reason worth recording so
/// nobody reaches for it again: `RitualCategory.ambition` already *is* `target`.
/// The sheet would have carried the challenge's mark at the top and the same
/// glyph inside the AMBITION tag six points below it, meaning two different
/// things on one card. The six dimensions own their glyphs and everything else
/// works around them.
///
/// One view rather than an `Image(...)` at each call site, so the mark is named
/// in exactly one place and the app cannot end up with two of them.
struct ChallengeMark: View {
    var size: CGFloat = 17
    /// Whether the challenge is behind them.
    var isFilled: Bool = false

    var body: some View {
        Image(systemName: isFilled ? "flag.fill" : "flag")
            .font(.system(size: size, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }
}

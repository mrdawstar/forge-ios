import SwiftUI

/// Where somebody is now, and where the same arithmetic says they would be in
/// seven days, in thirty, and with all six built.
///
/// # One screen, four stops
///
/// A four-segment control across the top and a Next button pinned at the
/// foot; the content between them scrolls when it has to, which at the
/// accessibility sizes it does. Each stop is the blade that stage earns with
/// its name, OVR large with the state word under it, the hexagon, and the six
/// as tiles. Moving between stops counts the numbers and morphs the polygon —
/// under Reduce Motion both cross-fade instead.
///
/// # Every number is computed
///
/// See `Transformation`: the four frames are `BlendedShape.read` over days held
/// in memory, the same function the Becoming tab draws from, and the
/// assumption behind stops two and three is printed under them word for word.
/// Nothing here is a promise; nothing says "will".
struct TransformationBeat: View {
    let frames: [Transformation.Frame]
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var stop: Transformation.Stop = .now
    @State private var scrollHeight: CGFloat = 0

    private var frame: Transformation.Frame? {
        frames.first { $0.stop == stop } ?? frames.first
    }

    private var motion: Animation {
        reduceMotion ? .easeInOut(duration: 0.3) : .smooth(duration: 0.6)
    }

    var body: some View {
        VStack(spacing: 0) {
            StopPicker(selection: Binding(
                get: { stop },
                set: { next in
                    ForgeHaptics.shared.detent()
                    withAnimation(motion) { stop = next }
                }
            ))
            .padding(.horizontal, 20)
            .padding(.top, 6)

            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if let frame { content(frame) }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: scrollHeight)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scrollHeight = $0 }

            ForgeButton(title: stop == .potential ? "Continue" : "Next") { next() }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .padding(.bottom, 20)
    }

    private func next() {
        ForgeHaptics.shared.tap()
        guard let following = Transformation.Stop(rawValue: stop.rawValue + 1) else {
            onContinue()
            return
        }
        withAnimation(motion) { stop = following }
    }

    // MARK: - One stop

    @ViewBuilder
    private func content(_ frame: Transformation.Frame) -> some View {
        VStack(spacing: 18) {
            Text(frame.stop.title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .accessibilityAddTraits(.isHeader)

            hero(frame)

            StatTiles(dimensions: frame.shape.dimensions)

            Text(frame.stop.footnote)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .padding(.horizontal, 8)
        }
    }

    /// The blade beside the hexagon, or above it once the type is too large
    /// for the two to share a row.
    @ViewBuilder
    private func hero(_ frame: Transformation.Frame) -> some View {
        let hexagon = StatHexagon(values: frame.shape.dimensions.map(\.fraction)) {
            OverallCore(
                overall: frame.shape.overall,
                state: frame.shape.state,
                size: typeSize.isAccessibilitySize ? 34 : 42
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Overall \(frame.shape.overall), \(frame.shape.state.label)"))

        if typeSize.isAccessibilitySize {
            VStack(spacing: 14) {
                BladeStage(frame: frame, height: 150)
                hexagon.frame(maxWidth: 240)
            }
        } else {
            HStack(alignment: .center, spacing: 10) {
                BladeStage(frame: frame, height: 206)
                    .frame(width: 84)
                hexagon
            }
        }
    }
}

// MARK: - The four segments

/// Now · 7 days · 30 days · Full. Short labels, because the stop's full name
/// is the title right under them — which is also why the control stops growing
/// at the largest standard type size: the words it would squeeze are said in
/// full, at any size, one line below.
private struct StopPicker: View {
    @Binding var selection: Transformation.Stop

    @Namespace private var marker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Transformation.Stop.allCases) { stop in
                let isOn = stop == selection
                Button {
                    guard !isOn else { return }
                    selection = stop
                } label: {
                    Text(stop.segment)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(isOn
                                         ? AnyShapeStyle(Color(red: 0.063, green: 0.063, blue: 0.078))
                                         : AnyShapeStyle(.secondary))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if isOn {
                                Capsule()
                                    .fill(ForgeTheme.cream)
                                    .matchedGeometryEffect(id: "marker", in: marker, isSource: !reduceMotion)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(stop.title))
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

// MARK: - The blade for the stage

/// The blade a stage earns, its name, and — where there is a count behind it —
/// how many days kept, said in words.
private struct BladeStage: View {
    let frame: Transformation.Frame
    let height: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            Image(frame.blade.asset)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: height)
                .mask(
                    LinearGradient(colors: [.black, .black, .clear],
                                   startPoint: .top, endPoint: .bottom)
                )
                .id(frame.blade.id)
                .transition(.opacity)

            Text(frame.blade.name.uppercased())
                .font(ForgeTheme.overline)
                .kerning(ForgeTheme.overlineKerning)
                .foregroundStyle(ForgeTheme.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.opacity)

            if let kept {
                Text(kept)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(
            [frame.blade.title, kept].compactMap { $0 }.joined(separator: ". ")
        ))
    }

    /// "Five days kept", on the two stops that are counts of days. The first is
    /// nothing yet and the last is not a count, so both are silent.
    private var kept: String? {
        switch frame.stop {
        case .week, .month:
            let days = FirstWeek.days(frame.daysKept)
            return days.prefix(1).uppercased() + days.dropFirst() + " kept"
        case .now, .potential:
            return nil
        }
    }
}

// MARK: - The six, as tiles

/// The six as tiles, three across and two down: the dimension's glyph and a
/// bar in its colour, the number large in monospaced digits so it does not
/// jitter as it counts, and the name.
///
/// Two across at the accessibility sizes, where "Relationship" at that size
/// does not fit a third of the screen and a clipped name is worse than a
/// taller grid.
struct StatTiles: View {
    let dimensions: [BlendedShape.Dimension]

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 10),
            count: typeSize.isAccessibilitySize ? 2 : 3
        )
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(dimensions) { dimension in
                StatTile(dimension: dimension)
            }
        }
    }
}

struct StatTile: View {
    let dimension: BlendedShape.Dimension

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: dimension.category.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(dimension.category.color)
                .accessibilityHidden(true)

            Text(dimension.hasScore ? "\(dimension.score)" : "—")
                .font(.title.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(dimension.score)))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(ForgeTheme.cream.opacity(0.12))
                    Capsule()
                        .fill(dimension.category.color)
                        .frame(width: max(3, proxy.size.width * dimension.fraction))
                }
            }
            .frame(height: 3)

            Text(dimension.category.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeCard(radius: ForgeTheme.Radius.control)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(dimension.category.label))
        .accessibilityValue(Text(dimension.hasScore ? "\(dimension.score)" : "Nothing recorded yet"))
    }
}

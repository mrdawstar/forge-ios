import SwiftUI

// MARK: - Six values SwiftUI can animate

/// Six numbers, 0…1, as one animatable value.
///
/// A hexagon drawn as a `Path` inside a view body does not animate: SwiftUI
/// cannot interpolate a path, so a change of shape arrives as a cut however the
/// parent is animated. A `Shape` whose `animatableData` is the six values does —
/// the vertices travel — and that travel is what the drawing beat, the
/// transformation's four stops and the Becoming tab all show.
struct SixValues: VectorArithmetic, Equatable, Sendable {
    /// Always six, in `RitualCategory.dimensions` order.
    private(set) var values: [Double]

    init(_ values: [Double]) {
        let six = Array(values.prefix(6))
        self.values = six + Array(repeating: 0, count: max(0, 6 - six.count))
    }

    static var zero: SixValues { SixValues([]) }

    static func + (lhs: SixValues, rhs: SixValues) -> SixValues {
        SixValues(zip(lhs.values, rhs.values).map { $0 + $1 })
    }

    static func - (lhs: SixValues, rhs: SixValues) -> SixValues {
        SixValues(zip(lhs.values, rhs.values).map { $0 - $1 })
    }

    mutating func scale(by rhs: Double) {
        values = values.map { $0 * rhs }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }

    subscript(index: Int) -> Double { values.indices.contains(index) ? values[index] : 0 }
}

/// Where vertex `index` of a hexagon sits, clockwise from the top.
enum HexagonGeometry {
    static let sides = 6

    static func point(_ index: Int, radius: CGFloat, centre: CGPoint) -> CGPoint {
        let angle = (Double(index) / Double(sides)) * 2 * .pi - .pi / 2
        return CGPoint(
            x: centre.x + cos(angle) * radius,
            y: centre.y + sin(angle) * radius
        )
    }
}

/// The polygon itself. `floor` keeps a nought drawn as a point just off the
/// centre rather than collapsing the side, the same floor `ForgeShapeView`
/// always had.
struct HexagonShape: Shape {
    var values: SixValues
    var floor: Double = 0.04

    var animatableData: SixValues {
        get { values }
        set { values = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        for index in 0..<HexagonGeometry.sides {
            let reach = max(floor, min(1, values[index]))
            let point = HexagonGeometry.point(index, radius: radius * reach, centre: centre)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - The hexagon, in the six colours

/// The six as a lit polygon: an engraved instrument behind, the shape in the
/// six colours in front, a dot at each vertex and the dimension's glyph beyond
/// it, and whatever the caller puts in the middle.
///
/// # Why the fill is an angular gradient
///
/// Each vertex sits in its own dimension's colour and the edge between two
/// vertices runs from one colour to the next, so the shape reads as six parts
/// of one thing rather than as a blue stain. The instrument behind stays in the
/// room's cream: it is the edge of what can be measured, not a part of anyone.
///
/// `lit` exists for the drawing beat, where the vertices come on one at a
/// time; everywhere else all six are lit.
struct StatHexagon<Core: View>: View {
    /// Six values, 0…1, in `RitualCategory.dimensions` order.
    let values: [Double]
    /// Which vertices are lit. Nil is all of them.
    var lit: Set<RitualCategory>? = nil
    /// Which vertex is being inspected, drawn larger.
    var highlighted: RitualCategory? = nil
    /// Room kept outside the polygon for the glyphs, or none.
    var showsGlyphs: Bool = true
    /// How long a change of shape takes to travel.
    var animation: Animation? = .smooth(duration: 0.55)
    @ViewBuilder var core: () -> Core

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dimensions: [RitualCategory] { RitualCategory.dimensions }

    private func isLit(_ dimension: RitualCategory) -> Bool {
        lit?.contains(dimension) ?? true
    }

    /// The six colours around the circle, each at its vertex's angle, closing
    /// back on the first.
    private var gradient: AngularGradient {
        var stops = dimensions.enumerated().map { index, dimension in
            Gradient.Stop(
                color: isLit(dimension) ? dimension.color : ForgeTheme.cream.opacity(0.35),
                location: Double(index) / Double(dimensions.count)
            )
        }
        stops.append(Gradient.Stop(color: stops[0].color, location: 1))
        return AngularGradient(
            gradient: Gradient(stops: stops),
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(270)
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let inset: CGFloat = showsGlyphs ? max(18, side * 0.1) : 4
            let radius = max(0, side / 2 - inset)
            let centre = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let current = SixValues(values)

            ZStack {
                instrument(radius: radius, centre: centre)

                HexagonShape(values: current)
                    .fill(gradient)
                    .opacity(0.30)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(centre)

                HexagonShape(values: current)
                    .stroke(gradient, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                    .shadow(color: .white.opacity(0.18), radius: 6)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(centre)

                ForEach(Array(dimensions.enumerated()), id: \.element) { index, dimension in
                    let reach = max(0.04, min(1, current[index]))
                    let big = highlighted == dimension
                    Circle()
                        .fill(isLit(dimension) ? dimension.color : ForgeTheme.cream.opacity(0.3))
                        .frame(width: big ? 8 : 5, height: big ? 8 : 5)
                        .shadow(color: dimension.color.opacity(isLit(dimension) ? 0.9 : 0), radius: big ? 7 : 4)
                        .position(HexagonGeometry.point(index, radius: radius * reach, centre: centre))

                    if showsGlyphs {
                        Image(systemName: dimension.symbol)
                            .font(.system(size: max(9, min(13, side * 0.045)), weight: .semibold))
                            .foregroundStyle(isLit(dimension) ? AnyShapeStyle(dimension.color) : AnyShapeStyle(.quaternary))
                            .position(HexagonGeometry.point(index, radius: radius + inset * 0.62, centre: centre))
                    }
                }

                core()
                    .position(centre)
            }
            .animation(reduceMotion ? nil : animation, value: values)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: lit)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// The edge of what can be measured: the outer hexagon, two rings and a
    /// spoke to each vertex, in the room's cream and quiet enough to read as
    /// engraving.
    private func instrument(radius: CGFloat, centre: CGPoint) -> some View {
        let full = SixValues(Array(repeating: 1, count: 6))
        return ZStack {
            ForEach([0.34, 0.67], id: \.self) { ring in
                HexagonShape(values: full, floor: 0)
                    .stroke(ForgeTheme.cream.opacity(0.08), lineWidth: 0.5)
                    .frame(width: radius * 2 * ring, height: radius * 2 * ring)
                    .position(centre)
            }
            ForEach(0..<HexagonGeometry.sides, id: \.self) { index in
                Path { path in
                    path.move(to: centre)
                    path.addLine(to: HexagonGeometry.point(index, radius: radius, centre: centre))
                }
                .stroke(ForgeTheme.cream.opacity(0.08), lineWidth: 0.5)
            }
            HexagonShape(values: full, floor: 0)
                .stroke(ForgeTheme.cream.opacity(0.22), lineWidth: 1)
                .frame(width: radius * 2, height: radius * 2)
                .position(centre)
        }
    }
}

extension StatHexagon where Core == EmptyView {
    init(
        values: [Double],
        lit: Set<RitualCategory>? = nil,
        highlighted: RitualCategory? = nil,
        showsGlyphs: Bool = true,
        animation: Animation? = .smooth(duration: 0.55)
    ) {
        self.init(
            values: values, lit: lit, highlighted: highlighted,
            showsGlyphs: showsGlyphs, animation: animation
        ) { EmptyView() }
    }
}

// MARK: - The number in the middle

/// OVR and the word under it, the way the Becoming tab has always drawn them:
/// the number large, in monospaced digits so it does not jitter as it counts,
/// and the state word small and spaced beneath.
struct OverallCore: View {
    let overall: Int
    let state: ForgeShape.Direction
    var size: CGFloat = 46

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Text("\(overall)")
                .font(.system(size: size, weight: .semibold))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(overall)))
                .foregroundStyle(.primary)

            Text(state.label.uppercased())
                .font(.system(size: max(9, size * 0.22), weight: .semibold))
                .kerning(1.6)
                .foregroundStyle(ForgeTheme.cream.opacity(0.75))
                .contentTransition(.opacity)
                .padding(.top, 2)
        }
        // A pool of the room's dark behind the number. The polygon is drawn
        // through the middle of the instrument, and without it an edge or a
        // vertex ran straight through the state word — the one small line of
        // type on the screen, crossed out by the shape it describes.
        .background {
            Circle()
                .fill(ForgeTheme.bg.opacity(0.72))
                .frame(width: size * 2.4, height: size * 2.4)
                .blur(radius: size * 0.3)
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.25) : .smooth(duration: 0.6), value: overall)
        .animation(.easeInOut(duration: 0.25), value: state)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Overall \(overall), \(state.label)"))
    }
}

import SwiftUI
import UIKit

// MARK: - The cover

/// An Arc's cover: the artwork in the catalogue, or a typographic plate where
/// there is none.
///
/// The four images (`arc-winter`, `arc-monk`, `arc-66`, `arc-lockin`) are
/// 3:2 photographs of the room the app is drawn in, and they are shown as they
/// are — cropped to the frame, never regraded. The fallback exists so a
/// missing image can never leave a blank card: the name, large, on the room's
/// dark, which is what every cover would be without its picture.
struct ArcCover: View {
    let program: ArcProgram
    /// Whether the name is laid over the image. The Arc's own screen sets its
    /// title in the text below instead.
    var showsName = true
    var height: CGFloat = 180

    private var image: UIImage? { UIImage(named: program.cover) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipped()
                    .accessibilityHidden(true)
            } else {
                typographic
            }

            if showsName {
                // The name sits on the darkest part of the picture, which the
                // covers keep at the foot; the gradient is only there to hold
                // the type on a brighter one.
                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .center, endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 3) {
                    Text(program.name)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(ForgeTheme.cream)
                    Text(program.lengthLabel.uppercased())
                        .font(ForgeTheme.overline)
                        .kerning(ForgeTheme.overlineKerning)
                        .foregroundStyle(ForgeTheme.cream.opacity(0.75))
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: ForgeTheme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(program.name), \(program.lengthLabel)"))
    }

    /// The name, set large on the room, with the Arc's mark — what a cover is
    /// without its picture.
    private var typographic: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.11), Color(white: 0.04)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            ArcMarkShape(arc: program.id)
                .stroke(ForgeTheme.cream.opacity(0.16), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: height * 0.62, height: height * 0.62)
                .offset(x: 70, y: -10)
            if !showsName {
                Text(program.name.uppercased())
                    .font(.system(size: 26, weight: .bold))
                    .kerning(3)
                    .foregroundStyle(ForgeTheme.cream.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}

// MARK: - The marks

/// Each Arc's mark, drawn in code: what a finished one leaves on the record.
///
/// Thin strokes in the room's cream — engraving, not badges. Winter Arc's is
/// the one cut into the blade itself (`WinterEngraving`); the others are drawn
/// beside the record of the Arc that earned them.
struct ArcMarkShape: Shape {
    let arc: ArcID

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = side / 2
        switch arc {
        case .winter: return Self.snowflake(centre: centre, radius: radius)
        case .lockIn: return Self.seven(centre: centre, radius: radius)
        case .monk: return Self.enso(centre: centre, radius: radius)
        case .discipline: return Self.tally(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: side, height: side))
        }
    }

    /// Six arms, each with a pair of branches two thirds of the way out.
    static func snowflake(centre: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        for arm in 0..<6 {
            let angle = Double(arm) * .pi / 3 - .pi / 2
            let tip = point(centre, radius, angle)
            path.move(to: centre)
            path.addLine(to: tip)
            let joint = point(centre, radius * 0.6, angle)
            for side in [-1.0, 1.0] {
                path.move(to: joint)
                path.addLine(to: point(joint, radius * 0.3, angle + side * .pi / 4))
            }
        }
        return path
    }

    /// Seven short strokes round most of a ring: the week.
    static func seven(centre: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        for tick in 0..<7 {
            let angle = -Double.pi / 2 + Double(tick) * (2 * .pi / 7)
            path.move(to: point(centre, radius * 0.55, angle))
            path.addLine(to: point(centre, radius, angle))
        }
        return path
    }

    /// One open circle, left unclosed.
    static func enso(centre: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        path.addArc(
            center: centre, radius: radius * 0.86,
            startAngle: .degrees(-60), endAngle: .degrees(250), clockwise: false
        )
        return path
    }

    /// Two tallies of five crossed, and a sixth stroke: counting, by hand.
    static func tally(in rect: CGRect) -> Path {
        var path = Path()
        let top = rect.minY + rect.height * 0.18
        let bottom = rect.maxY - rect.height * 0.18
        let step = rect.width / 11
        var x = rect.minX + step
        for group in 0..<2 {
            let start = x
            for _ in 0..<4 {
                path.move(to: CGPoint(x: x, y: top))
                path.addLine(to: CGPoint(x: x, y: bottom))
                x += step
            }
            path.move(to: CGPoint(x: start - step * 0.4, y: bottom - rect.height * 0.08))
            path.addLine(to: CGPoint(x: x - step * 0.6, y: top + rect.height * 0.08))
            x += group == 0 ? step : 0
        }
        return path
    }

    private static func point(_ origin: CGPoint, _ length: CGFloat, _ angle: Double) -> CGPoint {
        CGPoint(x: origin.x + cos(angle) * length, y: origin.y + sin(angle) * length)
    }
}

/// An Arc's mark at a size, in cream.
struct ArcMark: View {
    let arc: ArcID
    var size: CGFloat = 22
    var opacity: Double = 0.85

    var body: some View {
        ArcMarkShape(arc: arc)
            .stroke(
                ForgeTheme.cream.opacity(opacity),
                style: StrokeStyle(lineWidth: max(1, size / 14), lineCap: .round, lineJoin: .round)
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - The winter, on the blade

/// The mark a finished Winter Arc cuts into the blade (DIRECTION_1_1 §5).
///
/// Drawn in code on the sprite rather than painted into seven new pieces of
/// art: a snowflake on the flat of the blade a little below the guard, in pale
/// steel, masked by the sprite itself so it can only ever be on the metal. A
/// second winter cuts a second one beneath it, and so on — a record, like
/// everything else on the blade.
struct WinterEngraving: ViewModifier {
    /// How many winters have been finished.
    let count: Int
    /// The sprite's width and the height its full art is drawn at.
    let width: CGFloat
    let spriteHeight: CGFloat

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if count > 0 {
                VStack(spacing: width * 0.05) {
                    ForEach(0..<min(count, 3), id: \.self) { _ in
                        ArcMarkShape(arc: .winter)
                            .stroke(
                                Color(red: 0.86, green: 0.93, blue: 1.0).opacity(0.9),
                                style: StrokeStyle(lineWidth: max(0.8, width / 60), lineCap: .round)
                            )
                            .frame(width: width * 0.13, height: width * 0.13)
                            .shadow(color: .white.opacity(0.55), radius: width / 80)
                    }
                }
                // The flat of the blade, just under the guard: 36% of the
                // sprite's height on every one of the seven, which all put the
                // guard at about 28%.
                .padding(.top, spriteHeight * 0.36)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    /// Cut a finished winter into a sword sprite. See `WinterEngraving`.
    func winterEngraving(_ count: Int, width: CGFloat, spriteHeight: CGFloat) -> some View {
        modifier(WinterEngraving(count: count, width: width, spriteHeight: spriteHeight))
    }
}

// MARK: - The line on the Forge tab

/// "Winter Arc · Day 12 of 90 · Trial 3 of 7" — the one line the running Arc
/// gets on the home screen, above the day it is part of.
///
/// One slim line rather than a card: the home screen is the day, and an Arc is
/// a reading of days, so it says where somebody is and takes them to the Arcs
/// tab if they want the rest. The challenge capsule below it stays exactly
/// where it was.
struct ArcLine: View {
    let program: ArcProgram
    let reading: ArcReading
    let action: () -> Void

    static func text(_ program: ArcProgram, _ reading: ArcReading) -> String {
        var parts = [program.name, reading.counter]
        if let trial = reading.trial { parts.append(trial.line) }
        return parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                ArcMark(arc: program.id, size: 12, opacity: 0.8)
                Text(Self.text(program, reading))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(ForgeTheme.cream.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .capsule)
        .accessibilityLabel(Text(Self.text(program, reading)))
        .accessibilityHint(Text("Opens the Arcs tab"))
    }
}

// MARK: - Small pieces

/// A small caps heading with an optional detail on the right, the register
/// every section on the Arcs tab opens with.
struct ArcHeading: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(ForgeTheme.overline)
                .kerning(ForgeTheme.overlineKerning)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if let detail {
                Text(detail.uppercased())
                    .font(ForgeTheme.overline)
                    .kerning(ForgeTheme.overlineKerning)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One change, as a row: what it does, before and after.
struct ArcChangeRow: View {
    let change: ScheduleChange

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: change.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ForgeTheme.accent)
                .frame(width: 16)
            Text(change.diffLine ?? change.summary)
                .font(.subheadline)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A week's trial as a row of marks, one per day it asks for.
struct TrialMarks: View {
    let progress: ArcTrialProgress

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(1, progress.target), id: \.self) { index in
                Capsule()
                    .fill(index < progress.count ? AnyShapeStyle(ForgeTheme.accent) : AnyShapeStyle(.quaternary))
                    .frame(height: 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(progress.count) of \(progress.target)"))
    }
}

import SwiftUI

/// How much of today's list is behind you, as one mark per activity — until
/// there are too many activities for that to mean anything.
///
/// # Why it stops being segments
///
/// One segment per activity is the right reading for the days Forge is written
/// for: five marks, two filled, and you can see the shape of the day without
/// counting. It degrades badly though, and it degraded silently. The row is
/// about 300pt wide on a phone, so at sixteen activities each segment is 15pt,
/// at twenty-four it is 8.7 — narrower than the 4pt gap beside it — and past
/// forty the arithmetic gives every segment less than a point. What that draws
/// is a dotted line that says nothing, and then a row of hairlines.
///
/// So past the point where a segment stops being legible the row becomes a
/// single bar. It is the same fact drawn the way that many of them can be read:
/// a proportion. The threshold is measured against the width it actually has
/// rather than against a guessed count, because the same list is a different
/// shape on an iPhone 17e and on a Pro Max.
struct ProgressSegments: View {
    let total: Int
    let done: Int

    /// The narrowest a segment may be and still read as a segment rather than
    /// as noise. Below this the row switches to one bar.
    private static let minSegment: CGFloat = 9
    private static let gap: CGFloat = 4
    private static let barHeight: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            if fitsSegments(in: proxy.size.width) {
                segments
            } else {
                bar(width: proxy.size.width)
            }
        }
        .frame(height: Self.barHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Today's progress"))
        .accessibilityValue(Text("\(done) of \(total)"))
    }

    private func fitsSegments(in width: CGFloat) -> Bool {
        guard total > 1 else { return true }
        let available = width - Self.gap * CGFloat(total - 1)
        return available / CGFloat(total) >= Self.minSegment
    }

    private var segments: some View {
        HStack(spacing: Self.gap) {
            ForEach(0..<total, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(.quaternary)
                    // Filled by a second bar fading in over the track, rather
                    // than by swapping the fill style: two `ShapeStyle`s do not
                    // interpolate, so the old version could only ever snap.
                    .overlay {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.primary)
                            .opacity(i < done ? 1 : 0)
                    }
                    .frame(height: Self.barHeight)
                    .animation(.smooth(duration: 0.4).delay(Double(i) * 0.03), value: done)
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// The same reading as one proportion. No stagger: there are no marks left
    /// to stagger, and a bar that grows on a delay is a bar that lags.
    private func bar(width: CGFloat) -> some View {
        let fraction = total > 0 ? min(1, max(0, Double(done) / Double(total))) : 0
        return ZStack(alignment: .leading) {
            Capsule().fill(.quaternary)
            Capsule()
                .fill(.primary)
                .frame(width: max(0, width * fraction))
        }
        .frame(height: Self.barHeight)
        .frame(maxHeight: .infinity)
        .animation(.smooth(duration: 0.4), value: done)
    }
}

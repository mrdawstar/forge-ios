import SwiftUI

/// The grid, a column to a week.
///
/// **Every cell is filled.** It used to draw a rested day as an outline and a
/// missed one as a near-invisible wash, which meant the grid was three different
/// kinds of mark — a stroke, a tint and a hole — and the eye had to learn all
/// three before it could read a season at a glance. A contribution graph works
/// because it is one mark at five weights: the shape of a practice arrives
/// before any single square does.
///
/// So there is one shape here now, always filled, and the only thing that varies
/// is how much of the accent is in it. Nothing is drawn as absent, because no
/// day is absent — a day nobody kept is still a day, and the faintest step says
/// exactly that.
struct HeatmapView: View {
    let data: [[Double]]
    /// The same grid, marking days a banked rest covered.
    var rest: [[Bool]] = []
    var cell: CGFloat = 13
    var spacing: CGFloat = 3

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<data.count, id: \.self) { column in
                VStack(spacing: spacing) {
                    ForEach(0..<data[column].count, id: \.self) { row in
                        HeatCell(
                            level: HeatLevel.of(data[column][row], isRest: isRest(column, row)),
                            size: cell
                        )
                    }
                }
            }
        }
    }

    private func isRest(_ column: Int, _ row: Int) -> Bool {
        guard column < rest.count, row < rest[column].count else { return false }
        return rest[column][row]
    }
}

/// How full one square is.
///
/// **The enum moved to `Shared/ForgePalette.swift`** and this is an alias for
/// it. Nothing about the buckets or the ramp changed; what changed is who can
/// see them. The large widget draws this same grid off the same five shades, and
/// the extension compiles `Shared/` and nothing else — so a second copy of the
/// bucketing over there would have been a second opinion about what a
/// half-finished Tuesday looks like, on the one surface where both are on screen
/// at once.
///
/// The name stays because the Blade tab, the analytics sheet and
/// `AnalyticsTests` all say it, and none of them care where it is declared.
typealias HeatLevel = ForgeHeatLevel

extension ForgeHeatLevel {
    /// The square, in the app's own accent.
    ///
    /// Built on the accent so the grid is the same colour as the rest of the
    /// app — and so a change of accent redresses the grid with it, rather than
    /// leaving one screen in Forge's own blue. The widget passes its snapshot's
    /// accent to the same table; see `ForgeHeatLevel.style(accent:)`.
    var style: AnyShapeStyle { style(accent: ForgeTheme.accent) }
}

private struct HeatCell: View {
    let level: HeatLevel
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: max(2, size * 0.23), style: .continuous)
            .fill(level.style)
            .frame(height: size)
            // The lightest step of the ramp is close enough to the unkept step
            // to be lost on a bright screen at an angle, so every filled square
            // carries a hairline of its own colour. It costs nothing on the
            // dark ones and rescues the pale ones.
            .overlay {
                RoundedRectangle(cornerRadius: max(2, size * 0.23), style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
            }
    }
}

/// Less → More, in the four steps the grid actually uses.
///
/// Only shown where there is room for it — the twelve-week card has none, and a
/// legend is worth less than the two rows of grid it would cost there.
struct HeatmapLegend: View {
    var cell: CGFloat = 9

    var body: some View {
        HStack(spacing: 5) {
            Text("Less")
            HStack(spacing: 3) {
                ForEach(HeatLevel.ramp, id: \.rawValue) { level in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(level.style)
                        .frame(width: cell, height: cell)
                }
            }
            Text("More")
        }
        .font(ForgeTheme.mono(9))
        .foregroundStyle(.tertiary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shading runs from no activities finished to the whole day")
    }
}

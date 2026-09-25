import SwiftUI

/// Six months of practice, read back.
///
/// Three findings and no more. A trends screen wants to become a dashboard —
/// every number is another number somebody could add — so this one is capped at
/// what fits on a card without scrolling: the shape of the last six months, the
/// day of the week that holds up, and the activity that actually survives.
///
/// None of it is framed as a target. There is no "you're down 12% on last
/// month", no arrow, no red. A month with fewer days in it was a month with
/// other things in it.
struct TrendsCard: View {
    var vm: BladeViewModel

    var body: some View {
        let trends = vm.trends

        // No header of its own. It had one — "TRENDS · Last six months" — from
        // when this was a card on the Blade tab's carousel and had to introduce
        // itself. It lives inside a section called TRENDS now, so it was
        // printing the word twice, eleven points apart, in two type styles. The
        // sheet's section carries both halves; see `AnalyticsSheet.trends`.
        return VStack(alignment: .leading, spacing: 0) {
            months(trends.months)

            Spacer(minLength: 12)

            findings
        }
    }

    // MARK: - Months

    /// Bars rather than a line. A line between six points implies a trajectory
    /// somebody is on, which is a story the data cannot carry; six separate bars
    /// are six separate months, which is what they are.
    private func months(_ months: [ProgressStore.Trends.Month]) -> some View {
        let peak = max(months.map(\.kept).max() ?? 0, 1)

        return HStack(alignment: .bottom, spacing: 7) {
            ForEach(months) { month in
                bar(month, peak: peak)
            }
        }
        .frame(maxHeight: 78, alignment: .bottom)
    }

    private func bar(_ month: ProgressStore.Trends.Month, peak: Int) -> some View {
        // Held to a floor so an empty month is still a mark on the page rather
        // than a gap that reads as missing data.
        let height: CGFloat = max(3, 62 * CGFloat(month.kept) / CGFloat(peak))
        let fill: AnyShapeStyle = month.kept == 0
            ? AnyShapeStyle(.quaternary)
            : AnyShapeStyle(ForgeTheme.cream.opacity(0.75))

        return VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(fill)
                .frame(height: height)
                .frame(maxHeight: 62, alignment: .bottom)

            // No `minimumScaleFactor`: a three-letter month always fits, and
            // leaving one on let SwiftUI shrink whichever column happened to be
            // tightest, so one label in six came out a size smaller than its
            // neighbours.
            Text(month.label)
                .font(ForgeTheme.mono(9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(month.label), \(month.kept) days"))
    }

    // MARK: - Findings

    /// Two sentences at most, and only the ones that are true yet. A finding
    /// that needs more history simply is not printed — a placeholder saying "not
    /// enough data" is a row whose only content is what somebody has not done.
    @ViewBuilder
    private var findings: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let day = vm.steadiestDay {
                Text("\(day)s hold up best.")
            }
            if let best = vm.mostKept {
                Text("\(best.name), \(Self.share(best.rate)) of the time.")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Rounded to whole percent. A decimal place here would be precision the
    /// sample does not have.
    private static func share(_ rate: Double) -> String {
        "\(Int((rate * 100).rounded()))%"
    }
}

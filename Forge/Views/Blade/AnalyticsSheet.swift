import SwiftUI

/// Everything the card on the Blade tab has no room for.
///
/// The argument for a sheet rather than more cards is the one the Blade tab has
/// always been built on: the screen somebody opens should say a few true things
/// well, and the twenty other true things should be one tap behind it. A
/// dashboard is what you get when every one of those twenty wins its own
/// argument for being on the front page.
///
/// So the tab keeps three pages and a row, and this holds the whole record:
/// where the rate actually comes from, which habits hold and which do not, the
/// chain in full, a season of weeks, a year of months, and any year on file.
///
/// Nothing on it is a target. There are no deltas, no arrows and no red — see
/// `Analytics` for why that is a rule rather than a preference.
struct AnalyticsSheet: View {
    var vm: BladeViewModel
    @Environment(\.dismiss) private var dismiss

    /// Which year the bottom half is showing. Starts on the one we are in.
    @State private var year: Int

    init(vm: BladeViewModel) {
        self.vm = vm
        _year = State(initialValue: vm.currentYear)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if vm.summary.isEmpty {
                        emptyState
                    } else {
                        overview
                        habits
                        // Moved here off the Blade tab's carousel, where it was
                        // the fourth of four swipeable cards on a screen that is
                        // meant to be a portrait. Every reading on it needs
                        // months behind it to mean anything, which makes it
                        // exactly the kind of thing that belongs behind a door
                        // somebody opened on purpose.
                        trends
                        chain
                        weeks
                        yearSection
                    }
                }
                .padding(.horizontal, ForgeTheme.Space.gutter)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(ForgeTheme.Radius.sheet)
        .presentationDragIndicator(.visible)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing To Read Yet", systemImage: "chart.bar")
        } description: {
            Text("Keep a few days and this fills in on its own.")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Overview

    /// Three numbers, and the two that are rates carry what they were drawn from
    /// underneath. A percentage with no denominator is the easiest number in an
    /// app to mislead somebody with.
    ///
    /// A fourth used to sit beside the current chain: the longest one ever run.
    /// It is gone from the app entirely — not hidden, deleted, down to the field
    /// in `ProgressStore.StreakState` — because a personal best is a number whose
    /// only job is to be beaten and which spends most of its life describing
    /// somebody the user no longer is. It had already been taken off the front
    /// page for that reason and then went on living back here, which is how a
    /// removed idea survives: one screen further in.
    ///
    /// **"Activities done, since the first day" went the same way, and for the
    /// same reason.** It was deleted from the front card because it only ever
    /// goes up, so it said what "days kept" says in a bigger font — and then it
    /// turned up here, one screen further in, exactly as the longest streak had.
    /// What stands in its place is the thing the three rates beside it are all
    /// fractions *of*: where the record starts and how much of it there is. It
    /// is the only figure on this card that makes the other three checkable.
    private var overview: some View {
        let summary = vm.summary
        return section("OVERVIEW") {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    figure(
                        "\(summary.completionPercent)%",
                        label: "Completion",
                        detail: "\(summary.activitiesCompleted) of \(summary.activitiesPlanned) activities"
                    )
                    figure(
                        "\(summary.dayPercent)%",
                        label: "Days kept",
                        detail: "\(summary.daysKept) of \(summary.daysPossible) days"
                    )
                }
                Divider()
                HStack(spacing: 12) {
                    figure("\(vm.streak)", label: "Current chain", detail: dayWord(vm.streak))
                    figure(
                        recordSpan.value,
                        label: "Record begins",
                        detail: recordSpan.detail
                    )
                }
            }
            .padding(16)
            .forgeCard()
        }
    }

    // MARK: - Trends

    /// A card that fills in by itself.
    ///
    /// Every reading on it needs months behind it to mean anything, so for
    /// somebody three weeks in it is mostly bars and no sentences — which is the
    /// honest state of a short history, and a better thing to show than a locked
    /// door with a price on it. It prints a finding when there is one and stays
    /// quiet when there is not.
    private var trends: some View {
        section("TRENDS", detail: "Last six months") {
            TrendsCard(vm: vm)
                .padding(16)
                .forgeCard()
        }
    }

    private func figure(_ value: String, label: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: 28, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(label), \(value), \(detail)"))
    }

    private func dayWord(_ count: Int) -> String { count == 1 ? "day" : "days" }

    /// Where the history starts, and how many days of it there are. Both halves
    /// are needed: the date says how far back the sheet can see, and the count
    /// says how much of that stretch is actually on file.
    private var recordSpan: (value: String, detail: String) {
        guard let start = vm.recordStart else { return ("—", "nothing on file yet") }
        let days = vm.summary.daysPossible
        return (
            BladeViewModel.shortDate(start),
            "\(days) \(dayWord(days)) on file"
        )
    }

    // MARK: - Habits

    /// Every habit with enough behind it, best first.
    ///
    /// Ranked rather than split into a "best" list and a "worst" list, because
    /// those are the same list read from both ends and printing it twice would
    /// be the app making a table into a league. The top and bottom rows are
    /// marked so the two questions people actually have — *what holds, what
    /// doesn't* — are answerable at a glance.
    ///
    /// **A third question needed marking too**, and only shows up once somebody
    /// keeps a long day: *which of these do I actually do?* A rate cannot answer
    /// it — four out of four beats sixty out of ninety — so the row with the
    /// most days behind it carries a mark of its own. See
    /// `BladeViewModel.mostKeptHabit`.
    @ViewBuilder
    private var habits: some View {
        let rates = vm.habitRates
        if !rates.isEmpty {
            section("HABITS", detail: "Of the days each was asked for") {
                VStack(spacing: 0) {
                    ForEach(Array(rates.enumerated()), id: \.element.id) { index, rate in
                        habitRow(
                            rate,
                            tag: tag(at: index, of: rates.count, id: rate.id)
                        )
                        if index < rates.count - 1 {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .padding(.vertical, 4)
                .forgeCard()
            }
        } else {
            section("HABITS") {
                note("A few more days and this will have something to say. Each activity needs about a week behind it before its rate means anything.")
            }
        }
    }

    /// One mark to a row, and only where it says something.
    ///
    /// "Most often" is checked first: on a long day it is the more useful of the
    /// two, and an activity that is both the top rate and the most kept only
    /// needs telling about once.
    private func tag(at index: Int, of count: Int, id: String) -> String? {
        if vm.mostKeptHabit?.id == id { return "Most often" }
        guard count >= 2, vm.habitExtremes != nil else { return nil }
        if index == 0 { return "Holds best" }
        if index == count - 1 { return "Slips most" }
        return nil
    }

    private func habitRow(_ rate: Analytics.HabitRate, tag: String?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(vm.habitName(rate))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                if let tag {
                    Text(tag.uppercased())
                        .font(ForgeTheme.overline)
                        .kerning(0.6)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 8)

                Text("\(rate.percent)%")
                    .font(ForgeTheme.mono(11))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: rate.rate)
                .progressViewStyle(.linear)
                .tint(ForgeTheme.accent)

            Text("\(rate.completed) of \(rate.planned) days")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("\(vm.habitName(rate)), \(rate.percent) percent, \(rate.completed) of \(rate.planned) days")
        )
    }

    // MARK: - The chain

    /// Every run, longest first.
    ///
    /// A history rather than a personal best. See `Analytics.StreakRun` — the
    /// point of showing several is that a practice which has started over four
    /// times is a normal practice, and a screen that only ever shows the best
    /// one quietly says the opposite.
    @ViewBuilder
    private var chain: some View {
        let runs = vm.streakRuns
        if !runs.isEmpty {
            section("THE CHAIN", detail: runs.count == 1 ? "One run" : "\(runs.count) runs") {
                VStack(spacing: 0) {
                    ForEach(Array(runs.prefix(6).enumerated()), id: \.element.id) { index, run in
                        runRow(run)
                        if index < min(runs.count, 6) - 1 {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .padding(.vertical, 4)
                .forgeCard()
            }
        }
    }

    private func runRow(_ run: Analytics.StreakRun) -> some View {
        HStack(spacing: 12) {
            Text("\(run.length)")
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .frame(minWidth: 34, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(dayWord(run.length).capitalized)
                    .font(.subheadline)
                Text("\(BladeViewModel.shortDate(run.start)) – \(BladeViewModel.shortDate(run.end))")
                    .font(ForgeTheme.mono(9))
                    .tracking(0.8)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            if run.isCurrent {
                Text("RUNNING")
                    .font(ForgeTheme.overline)
                    .kerning(0.8)
                    .foregroundStyle(ForgeTheme.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Consistency

    private var weeks: some View {
        let periods = vm.weekly(12)
        return section("WEEK BY WEEK", detail: consistencyDetail(periods)) {
            VStack(alignment: .leading, spacing: 10) {
                PeriodBars(periods: periods, labelEvery: 3)
                note("Days kept out of the days there were to keep. Weekdays you set aside in Settings are not counted against you.")
            }
            .padding(16)
            .forgeCard()
        }
    }

    /// The average of the periods that have anything in them — an empty week at
    /// the start of a history would otherwise drag the figure down for something
    /// that had not begun yet.
    private func consistencyDetail(_ periods: [Analytics.Period]) -> String? {
        let live = periods.filter { !$0.isEmpty }
        guard !live.isEmpty else { return nil }
        let mean = live.reduce(0.0) { $0 + $1.rate } / Double(live.count)
        return "\(Int((mean * 100).rounded()))% on average"
    }

    // MARK: - The year

    private var yearSection: some View {
        let reading = vm.year(year)
        return section("THE YEAR", detail: yearDetail(reading)) {
            VStack(alignment: .leading, spacing: 16) {
                if vm.availableYears.count > 1 { yearPicker }

                yearGrid

                Divider()

                // The monthly breakdown, and only the one. A row of twelve bars
                // sat here as well and was drawing the same twelve rates from
                // the same twelve months — the list below already carries a bar
                // *and* the count, so the chart was the same picture with less
                // in it. Two views of one fact is how a sheet turns into a
                // dashboard.
                monthList(reading)
            }
            .padding(16)
            .forgeCard()
        }
    }

    /// What the year reads, and — when the list does not start in January —
    /// where it starts. Without the second half the trimmed list looks like a
    /// year with months missing rather than one that began in September.
    private func yearDetail(_ reading: Analytics.Year) -> String {
        let base = "\(reading.percent)% of \(year)"
        guard let first = reading.months.first, reading.months.count < 12 else { return base }
        return "\(base) · from \(first.label)"
    }

    private var yearPicker: some View {
        Picker("Year", selection: $year) {
            ForEach(vm.availableYears, id: \.self) { option in
                Text(String(option)).tag(option)
            }
        }
        .pickerStyle(.segmented)
    }

    /// Fifty-three columns will not fit on a phone, so the year scrolls
    /// sideways — which is what GitHub does with the same grid and the same
    /// constraint, and it keeps every square the size it is on the card above.
    private var yearGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal) {
                HeatmapView(
                    data: vm.yearHeatmap(year).columns,
                    rest: vm.yearHeatmap(year).restColumns,
                    cell: 10,
                    spacing: 2.5
                )
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            // The grid is the one thing on this sheet where a reader has to
            // know what the shading means, and it is the one place with room
            // to say so.
            HeatmapLegend()
        }
    }

    private func monthList(_ reading: Analytics.Year) -> some View {
        VStack(spacing: 8) {
            ForEach(reading.months) { month in
                HStack(spacing: 12) {
                    Text(month.label)
                        .font(ForgeTheme.mono(11))
                        .foregroundStyle(month.isEmpty ? .tertiary : .secondary)
                        .frame(width: 34, alignment: .leading)

                    ProgressView(value: month.rate)
                        .progressViewStyle(.linear)
                        .tint(month.isEmpty ? Color.secondary : ForgeTheme.accent)

                    // A month that has not happened says so with a dash rather
                    // than with "0%", which would read as a month somebody
                    // failed rather than one they have not reached. The months
                    // *before* the record began are not here at all — see
                    // `ProgressStore.year(_:)`.
                    Text(month.isEmpty ? "–" : "\(month.kept)")
                        .font(ForgeTheme.mono(11))
                        .foregroundStyle(.tertiary)
                        .frame(width: 26, alignment: .trailing)
                }
                .opacity(month.isFuture ? 0.55 : 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    Text(month.isFuture
                         ? "\(month.label), still ahead"
                         : month.isEmpty
                             ? "\(month.label), nothing yet"
                             : "\(month.label), \(month.kept) of \(month.possible) days")
                )
            }
        }
    }

    // MARK: - Furniture

    private func section<Content: View>(
        _ title: String, detail: String? = nil, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, detail: detail)
            content()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Bars

/// A row of periods as bars.
///
/// Bars rather than a line, for the reason `TrendsCard` gives: a line between
/// points implies a trajectory somebody is on, which is a story this data cannot
/// carry. Twelve weeks are twelve weeks.
struct PeriodBars: View {
    let periods: [Analytics.Period]
    /// Label every nth column. Twelve labels across a phone is unreadable, and
    /// none at all leaves the bars floating.
    var labelEvery: Int = 3
    var height: CGFloat = 64

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(periods.enumerated()), id: \.element.id) { index, period in
                bar(period, showLabel: index % labelEvery == 0)
            }
        }
        .frame(maxHeight: height + 16, alignment: .bottom)
    }

    private func bar(_ period: Analytics.Period, showLabel: Bool) -> some View {
        // Held to a floor so an empty period is still a mark on the page rather
        // than a gap that reads as missing data.
        let filled: CGFloat = max(3, height * CGFloat(period.rate))

        return VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(.quaternary)
                    .frame(height: height)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(period.isEmpty ? AnyShapeStyle(.quaternary) : AnyShapeStyle(ForgeTheme.accent))
                    .frame(height: period.isEmpty ? 0 : filled)
            }
            .frame(height: height, alignment: .bottom)

            Text(showLabel ? period.label : " ")
                .font(ForgeTheme.mono(8))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(period.isEmpty
                 ? "\(period.label), nothing yet"
                 : "\(period.label), \(period.kept) of \(period.possible) days")
        )
    }
}

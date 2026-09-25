import SwiftUI
import WidgetKit

// MARK: - Shared parts

/// A thin rule that fills as the day does.
///
/// One shape, used by every family that has room for it, because the day's
/// progress is one fact and three drawings of it would drift. It is a **rule and
/// not a bar chart**: hairline height, full width, and no ticks — the day list
/// inside the app segments progress per activity, and repeating that on a
/// hundred-point widget would be a chart nobody can read at arm's length.
///
/// Empty of colour until something has been done. A rail already showing the
/// accent at nothing-done would be the widget being optimistic on somebody's
/// behalf, which is the one register Forge does not have.
struct DayRail: View {
    let fraction: Double
    let tint: Color
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.14))
                if fraction > 0 {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(height, proxy.size.width * min(1, fraction)))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// The small tracked line every Home Screen family opens with.
///
/// Uppercase, tracked, tertiary — the one typographic convention this target
/// keeps, because it is what puts a date or a count at the top of a widget
/// without it competing with the sentence underneath. It is the same treatment
/// the app uses for a section's kicker.
struct WidgetKicker: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.9)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// Today, as a widget says it: "WED 3 SEP".
///
/// Built from `ForgeSnapshot.day` rather than from `Date.now`, and that is not
/// pedantry — Forge's day starts at four in the morning, so at 01:30 the date on
/// the clock and the day the app is in are different days, and the widget has to
/// say the one the rest of it is counting.
func widgetDayLabel(_ day: ForgeDay, calendar: Calendar = .current) -> String {
    var parts = DateComponents()
    parts.year = day.year
    parts.month = day.month
    parts.day = day.day
    guard let date = calendar.date(from: parts) else { return "" }
    return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        .uppercased()
}

/// The days kept, said the way the app says it everywhere else.
func keptLabel(_ count: Int) -> String {
    count == 1 ? "1 day kept" : "\(count) days kept"
}

// MARK: - Small

/// The small Home Screen widget: **what today still asks for.**
///
/// # What went, and why
///
/// It was a drawn sword in a stone taking two thirds of the card, with the
/// day's progress squeezed into the line underneath. Two things were wrong with
/// that. The picture never changed — the same illustration fifteen times a day,
/// carrying one bit of information (in the stone, or out of it) at the size of a
/// hero image. And it was a *screenshot of the app* sitting on a Home Screen
/// between Weather and Calendar, which is the one thing a widget must not look
/// like.
///
/// So the whole card is now the answer to the question somebody actually opens
/// their phone with: **the date, the next thing, and how much of the day is
/// left.** Nothing is illustrated, nothing is centred, and the largest type on
/// the card is the name of the activity — because that is the only line on it
/// anybody acts on.
struct SmallView: View {
    let snapshot: ForgeSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                WidgetKicker(text: widgetDayLabel(snapshot.day))
                Spacer(minLength: 4)
                if snapshot.isEarned {
                    // The one state that earns a colour on this card. It
                    // replaces the count rather than joining it: an earned day
                    // has nothing outstanding to report.
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(snapshot.tint)
                        .widgetAccentable()
                } else if snapshot.total > 0 {
                    Text("\(snapshot.done)/\(snapshot.total)")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, 10)

            Text(headline)
                .font(.system(.title3, design: .default, weight: .semibold))
                .foregroundStyle(snapshot.isEarned ? AnyShapeStyle(snapshot.tint) : AnyShapeStyle(.primary))
                .lineLimit(3)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 6)

            DayRail(fraction: snapshot.fraction, tint: snapshot.tint)
                .padding(.bottom, 7)

            Text(footer)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Forge")
        .accessibilityValue("\(headline). \(footer)")
    }

    /// The next thing today asks for, and the three states where there is not
    /// one. Never a number — the count is on the line above and the rail below,
    /// and this line is the only one on the card with a verb in it.
    private var headline: String {
        if snapshot.isEarned { return "The day is yours" }
        if snapshot.total == 0 { return "Today is open" }
        if let next = snapshot.activities.first(where: { !$0.isDone })?.name, !next.isEmpty {
            return next
        }
        return "Ready to pull"
    }

    private var footer: String {
        if snapshot.isEarned { return keptLabel(snapshot.daysKept) }
        if snapshot.total == 0 { return keptLabel(snapshot.daysKept) }
        let left = snapshot.remaining
        return "\(left == 1 ? "1 left" : "\(left) left") · \(snapshot.daysKept) kept"
    }
}

// MARK: - Medium

/// The medium widget: **today on the left, the week on the right.**
///
/// The extra width over the small family is not an excuse for more of the same
/// list. It buys exactly one thing the small card cannot show — *where today
/// sits in the week* — so the right-hand column is seven marks and a count, and
/// the left is the same three facts the small card carries with room to breathe.
///
/// The list is names and marks. No subtitles, no targets, no Health glyphs:
/// everything the day list carries to help you *decide* is noise here, because a
/// widget is read by somebody who has already decided and wants to know what is
/// still open.
struct MediumView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let snapshot: ForgeSnapshot

    /// Two rows at ordinary sizes, one once the text is large. A third fits on
    /// paper and reads as a wall in practice — the point of this widget is what
    /// is left, not the whole list, and the count carries the rest.
    private var visibleLimit: Int { typeSize.isAccessibilitySize ? 1 : 2 }

    private var pending: [ForgeSnapshot.Activity] {
        snapshot.activities.filter { !$0.isDone }
    }

    private var visible: [ForgeSnapshot.Activity] {
        Array((pending + snapshot.activities.filter(\.isDone)).prefix(visibleLimit))
    }

    private var overflow: Int { max(0, snapshot.total - visible.count) }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            today
            // A drawn rule rather than a `Divider`: a divider inside an `HStack`
            // takes its height from the layout around it, and this one sits
            // beside two columns that size themselves — so it collapsed to a
            // few points on a day with one activity on it.
            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            week
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Forge")
        .accessibilityValue(spoken)
    }

    private var today: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetKicker(text: widgetDayLabel(snapshot.day))
                .padding(.bottom, 8)

            if snapshot.isEarned {
                Text("The day is yours")
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(snapshot.tint)
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else if snapshot.total == 0 {
                Text("Today is open")
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(visible) { activity in
                        row(activity)
                    }
                    if overflow > 0 {
                        Text(overflow == 1 ? "and one more" : "and \(overflow) more")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 16)
                    }
                }
            }

            Spacer(minLength: 8)

            DayRail(fraction: snapshot.fraction, tint: snapshot.tint, height: 2.5)
                .padding(.bottom, 6)

            Text(progressLine)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The last seven days, oldest first, with today at the end.
    ///
    /// Marks rather than a chart, and the same five shades as the grid on the
    /// large family and the heatmap on the Blade tab — see `ForgeHeatLevel`.
    /// The weekday letters sit under them so the column somebody is standing in
    /// is findable without counting.
    private var week: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetKicker(text: "LAST 7 DAYS")
                .padding(.bottom, 10)

            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { offset in
                    let day = snapshot.day.adding(days: offset - 6)
                    VStack(spacing: 5) {
                        HeatSquare(
                            mark: snapshot.mark(on: day),
                            tint: snapshot.tint,
                            size: 15,
                            isToday: offset == 6
                        )
                        Text(weekdayInitial(day))
                            .font(.system(size: 9, weight: offset == 6 ? .bold : .medium))
                            .foregroundStyle(offset == 6 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                    }
                }
            }

            Spacer(minLength: 8)

            Text(keptLine)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func row(_ activity: ForgeSnapshot.Activity) -> some View {
        HStack(spacing: 8) {
            Circle()
                .strokeBorder(.secondary.opacity(0.55), lineWidth: 1.2)
                .background { if activity.isDone { Circle().fill(snapshot.tint) } }
                .frame(width: 8, height: 8)
                .widgetAccentable(activity.isDone)

            Text(activity.name)
                .font(.subheadline)
                .foregroundStyle(activity.isDone ? .secondary : .primary)
                .strikethrough(activity.isDone, color: .secondary.opacity(0.6))
                .lineLimit(1)
        }
    }

    private var progressLine: String {
        if snapshot.isEarned { return keptLabel(snapshot.daysKept) }
        if snapshot.total == 0 { return keptLabel(snapshot.daysKept) }
        return "\(snapshot.done) of \(snapshot.total) done"
    }

    private var keptLine: String { "\(snapshot.daysKept(inLast: 7)) of 7 kept" }

    private var spoken: String {
        var parts = [progressLine, keptLine + " this week"]
        if let next = pending.first?.name, !next.isEmpty { parts.insert("Next: \(next)", at: 0) }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Large

/// The large widget: **six months of the practice, at a glance.**
///
/// This is the one family that is not about today. Its whole job is the sentence
/// somebody should be able to say two seconds after looking at it — *this is how
/// I am doing* — and the only honest way to answer that is with the record
/// itself rather than with a number somebody has to interpret.
///
/// So: twenty-six weeks as columns of seven, in the same five shades as the
/// heatmap on the Blade tab (`ForgeHeatLevel`), months labelled along the top,
/// and three counts underneath. Nothing is invented — every square is a day out
/// of `ForgeSnapshot.history`, which the app bucketed, and the days before
/// somebody's first are left empty rather than drawn as failures.
///
/// It is deliberately not a dashboard. One picture, one row of counts, and the
/// same header the other families carry.
struct LargeView: View {
    let snapshot: ForgeSnapshot

    /// Twenty-six columns is a season and a half and it is also what fits: at
    /// the large family's ~329pt of content width, twenty-six squares plus their
    /// gaps land at about 11pt a side, which is the smallest a filled square can
    /// be and still read as a step on a ramp rather than as a dot.
    private let weeks = 26

    /// The Sunday (or Monday) the grid opens on, so every row is one weekday.
    private var gridStart: ForgeDay {
        let lead = (snapshot.day.weekday - Calendar.current.firstWeekday + 7) % 7
        return snapshot.day.adding(days: -lead - (weeks - 1) * 7)
    }

    /// One `GeometryReader` over the whole card, and the square size falls out of
    /// its width.
    ///
    /// It has to be measured rather than fixed: twenty-six columns across a
    /// 6.1" phone's large widget is about 9.7pt a side and across a 6.9" phone's
    /// about 10.9, and a constant would either overflow the narrow one or leave
    /// a stripe of empty card on the wide one. Everything else on the card is
    /// laid out around the number that comes out of it, so the grid, the month
    /// strip and the footer can never disagree about where a column is.
    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 2.5
            let side = max(6, (proxy.size.width - spacing * CGFloat(weeks - 1)) / CGFloat(weeks))

            VStack(alignment: .leading, spacing: 0) {
                header

                Spacer(minLength: 10)

                monthStrip(side: side, spacing: spacing)
                    .padding(.bottom, 5)
                gridRows(side: side, spacing: spacing)

                Spacer(minLength: 10)

                footer
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Forge")
        .accessibilityValue(spoken)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                WidgetKicker(text: widgetDayLabel(snapshot.day))
                Text(headline)
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(snapshot.isEarned ? AnyShapeStyle(snapshot.tint) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(snapshot.daysKept)")
                    .font(.system(size: 28, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text(snapshot.daysKept == 1 ? "DAY KEPT" : "DAYS KEPT")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Months across the top. The label sits over the column its month starts
    /// in, which is the only placement that does not drift as the window slides
    /// — a month is not a whole number of weeks, so anything evenly spaced would
    /// be a column out within a season.
    private func monthStrip(side: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(0..<weeks, id: \.self) { column in
                Text(monthLabel(column) ?? "")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    // The label is wider than its column and is meant to be:
                    // it runs on over the two or three columns after it, the
                    // way every contribution grid draws one. Months are at
                    // least four columns apart, so two can never collide.
                    .frame(width: side, alignment: .leading)
            }
        }
    }

    /// Twenty-six columns of seven. Column-major, so a row is one weekday all
    /// the way across and the eye can follow a Tuesday for six months.
    private func gridRows(side: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(0..<weeks, id: \.self) { column in
                VStack(spacing: spacing) {
                    ForEach(0..<7, id: \.self) { row in
                        let day = gridStart.adding(days: column * 7 + row)
                        HeatSquare(
                            mark: snapshot.mark(on: day),
                            tint: snapshot.tint,
                            size: side,
                            isToday: day == snapshot.day,
                            isFuture: day > snapshot.day
                        )
                    }
                }
            }
        }
    }

    /// Three counts, and they are the three windows a person actually thinks in.
    /// Every one of them is read off the same trail the grid is drawn from — see
    /// `ForgeSnapshot.daysKept(inLast:)` — so the picture and the numbers under
    /// it can never disagree.
    private var footer: some View {
        HStack(spacing: 0) {
            stat("\(snapshot.daysKept(inLast: 7))/7", "THIS WEEK")
            Spacer(minLength: 8)
            stat("\(snapshot.daysKept(inLast: 30))/30", "THIS MONTH")
            Spacer(minLength: 8)
            stat("\(snapshot.done)/\(max(snapshot.total, snapshot.done))", "TODAY")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var headline: String {
        if snapshot.isEarned { return "The day is yours" }
        if snapshot.total == 0 { return "Today is open" }
        if let next = snapshot.activities.first(where: { !$0.isDone })?.name, !next.isEmpty {
            return next
        }
        return "Ready to pull"
    }

    /// The month's abbreviation, on the first column that starts inside it —
    /// and never twice, and never on the first column, which is almost always a
    /// stub of the month before.
    private func monthLabel(_ column: Int) -> String? {
        guard column > 0 else { return nil }
        let start = gridStart.adding(days: column * 7)
        let previous = gridStart.adding(days: (column - 1) * 7)
        guard start.month != previous.month else { return nil }
        var parts = DateComponents()
        parts.year = start.year
        parts.month = start.month
        parts.day = 1
        guard let date = Calendar.current.date(from: parts) else { return nil }
        return date.formatted(.dateTime.month(.abbreviated))
    }

    private var spoken: String {
        "\(headline). \(snapshot.daysKept(inLast: 7)) of the last seven days kept, "
        + "\(snapshot.daysKept(inLast: 30)) of the last thirty. \(keptLabel(snapshot.daysKept)) in all."
    }
}

// MARK: - One square

/// One day of the record.
///
/// The lightest step of the ramp is close enough to the unkept step to be lost
/// on a bright screen at an angle, so every square carries a hairline — it costs
/// nothing on the dark ones and rescues the pale ones. The same hairline is what
/// the Blade tab's grid uses.
///
/// # Three kinds of square, and the difference is load-bearing
///
/// - **A day**, filled at one of five weights. What somebody did.
/// - **An empty slot** — outline, no fill — for a day *earlier than this
///   person's record*. It must not be filled at the ramp's lowest step, because
///   that step means "a day you had and did not keep", and these are days Forge
///   was not installed for. Drawn as an outline it reads as the frame of the
///   window rather than as a verdict, which is the whole distinction.
/// - **Nothing at all**, for a day still ahead. The current week's remaining
///   days sit in the grid's last column and have not happened.
///
/// The empty slot is why this is not simply `if let mark`. The first build drew
/// nothing for both, and on a fresh install the large family was a black card
/// with one blue square in it and the medium's week strip was six weekday
/// letters under a gap — both of which read as a widget that had failed to load
/// rather than as a record that has not started.
struct HeatSquare: View {
    let mark: ForgeHeatMark?
    let tint: Color
    let size: CGFloat
    var isToday: Bool = false
    /// A day that has not happened. Nothing is drawn for one — not even the
    /// slot — so the grid ends where the record does rather than promising a
    /// week nobody has lived yet.
    var isFuture: Bool = false

    private var radius: CGFloat { max(2, size * 0.23) }

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(mark?.level.style(accent: tint) ?? AnyShapeStyle(.clear))
            .frame(width: size, height: size)
            .overlay {
                if !isFuture {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(border, lineWidth: isToday ? 1.1 : 0.5)
                }
            }
            .accessibilityHidden(true)
    }

    /// Today is ringed rather than recoloured: a square that changed colour to
    /// mark the date would be saying something about the day's progress, which
    /// is what its fill is already for.
    private var border: Color {
        if isToday { return .primary.opacity(0.55) }
        // An empty slot is nothing but its outline, so the outline has to carry
        // it — twice the weight of the hairline a filled square wears.
        return .primary.opacity(mark == nil ? 0.11 : 0.05)
    }
}

/// The first letter of a weekday, in the reader's own locale.
func weekdayInitial(_ day: ForgeDay, calendar: Calendar = .current) -> String {
    let symbols = calendar.veryShortStandaloneWeekdaySymbols
    let index = day.weekday - 1
    guard symbols.indices.contains(index) else { return "" }
    return symbols[index]
}

import SwiftUI
import WidgetKit

/// The Lock Screen circle. The first thing a day person sees.
///
/// One number: how many are left. Not how many are done, not a fraction, not a
/// percentage — "two left" is the only form of this fact anybody acts on before
/// they are properly awake. The ring carries the same fact a second way for the
/// people who read shapes faster than digits.
///
/// **Nothing here is tinted.** Accessory widgets are rendered by the system in
/// one vibrant material whatever a view asks for, so an accent applied here
/// would be a colour the person never sees and a promise the file could not
/// keep. The accent's job is on the Home Screen; see `SmallView`.
///
/// **And nothing here is drawn.** The empty state used to put a vector sword in
/// a stone inside the ring — an illustration at twenty points across, on the one
/// surface in the product with the least room and the shortest look. It is the
/// day's own number now, or a dash where there is no day yet.
struct CircularView: View {
    let snapshot: ForgeSnapshot

    var body: some View {
        Gauge(value: snapshot.fraction) {
            // Never shown by the capacity style, but it is what VoiceOver reads.
            Text(label)
        } currentValueLabel: {
            if snapshot.isEarned {
                Image(systemName: "checkmark")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
            } else if snapshot.total == 0 {
                // Nothing set. A dash rather than a zero: zero left is what a
                // finished day says, and this is a day that has not been made
                // yet.
                Text(verbatim: "\u{2013}")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
            } else {
                Text("\(snapshot.remaining)")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .minimumScaleFactor(0.6)
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .accessibilityLabel("Forge")
        .accessibilityValue(label)
    }

    private var label: String {
        if snapshot.isEarned { return "The blade is free" }
        if snapshot.total == 0 { return "Nothing set" }
        return snapshot.remaining == 1 ? "One activity left" : "\(snapshot.remaining) activities left"
    }
}

/// The Lock Screen rectangle. Room for a sentence, so it spends the room on the
/// one thing a lock screen can usefully answer: **what is next.**
///
/// # What went, and why
///
/// First it said FORGE in a tracked overline with "Two left" under it — a third
/// of the widget spent printing the app's own name beside the app's own mark, on
/// a surface the person chose to put there. Then the name went and the mark
/// stayed, and the mark was a drawn sword in a stone twenty-two points wide,
/// which at that size is a grey smudge that costs a fifth of the width. Both are
/// gone.
///
/// What is left is three lines of type in the space three lines of type need:
/// the state, the thing to do about it, and a rule carrying the fraction. That
/// is the difference between a status and a prompt, and a prompt is the only
/// thing worth a Lock Screen at seven in the morning.
struct RectangularView: View {
    let snapshot: ForgeSnapshot

    /// The first thing today still asks for, in the order the app draws them.
    private var next: String? {
        snapshot.activities.first { !$0.isDone }.map(\.name).flatMap { $0.isEmpty ? nil : $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(headline)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .widgetAccentable()

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            if !snapshot.isEarned, snapshot.total > 0 {
                DayRail(fraction: snapshot.fraction, tint: .primary, height: 2)
                    .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Forge")
        .accessibilityValue([headline, detail].compactMap { $0 }.joined(separator: ". "))
    }

    /// The state, in as few words as it takes.
    private var headline: String {
        if snapshot.isEarned { return "The blade is free" }
        if snapshot.total == 0 { return "Today is open" }
        return snapshot.remaining == 1 ? "One left" : "\(snapshot.remaining) left"
    }

    /// What to do about it. The next thing when there is one, the count behind
    /// them when there is not — an earned day has nothing outstanding to name,
    /// and the days kept is the fact that belongs to a finished one.
    private var detail: String? {
        if snapshot.isEarned { return keptLabel(snapshot.daysKept) }
        if snapshot.total == 0 { return "Nothing planned yet" }
        return next
    }
}

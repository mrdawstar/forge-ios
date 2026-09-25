import ActivityKit
import SwiftUI
import WidgetKit

/// The day, while it is happening.
///
/// Runs from the first activity finished until the blade comes out or the day
/// turns over. It is the one Forge surface that appears without being asked
/// for, so it carries the least: how far through, and whether the blade is
/// free. No activity names, no streak, no buttons.
///
/// **The drawn sword is gone from here too.** It stood in four places — the
/// expanded leading region, the compact leading, the minimal, and the Lock
/// Screen presentation — at sixteen to thirty-four points across, which is a
/// grey smudge rather than a picture. Every one of them is a ring carrying the
/// day's fraction now: the same fact the bar underneath already shows, in the
/// one form that is legible at sixteen points, and the only mark the system
/// renders properly inside the Dynamic Island.
struct DayLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ForgeActivityAttributes.self) { context in
            LockScreenLiveView(state: context.state)
                .activityBackgroundTint(nil)
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DayRing(fraction: context.state.fraction, isEarned: context.state.isEarned)
                        .frame(width: 30, height: 30)
                        .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.isEarned
                         ? "Free"
                         : "\(context.state.done)/\(context.state.total)")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    // The bar is the whole point of the expanded view: it is the
                    // only place with room to show the shape of the day
                    // rather than a number standing in for it.
                    Gauge(value: context.state.fraction) {
                        Text(context.state.summary)
                    }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(.primary)
                    .accessibilityLabel("Your day")
                    .accessibilityValue(context.state.summary)
                }
            } compactLeading: {
                DayRing(fraction: context.state.fraction, isEarned: context.state.isEarned)
                    .frame(width: 16, height: 16)
            } compactTrailing: {
                if context.state.isEarned {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                } else {
                    Text("\(context.state.remaining)")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                }
            } minimal: {
                // One glyph, and it has to carry the entire state on its own.
                // A ring is the only thing at this size that can: it is the
                // fraction, so it says both how much is done and — once it
                // closes — that the day is finished.
                DayRing(fraction: context.state.fraction, isEarned: context.state.isEarned)
            }
            .widgetURL(ForgeLink.today)
            .keylineTint(.primary)
        }
    }
}

/// The Lock Screen presentation, which is the one most people actually see.
struct LockScreenLiveView: View {
    let state: ForgeActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            DayRing(fraction: state.fraction, isEarned: state.isEarned)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 5) {
                Text("TODAY")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(.secondary)

                Text(state.summary)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Gauge(value: state.fraction) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(.primary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your day")
        .accessibilityValue(state.summary)
    }
}

/// The day as a ring, at any size the system asks for.
///
/// Deliberately not a `Gauge`: the accessory gauge styles carry their own
/// padding and their own idea of a track, and inside the Dynamic Island at
/// sixteen points that padding is most of the glyph. This is two strokes and
/// nothing else, so it stays legible from the minimal presentation up to the
/// Lock Screen's thirty-four.
///
/// It closes completely on an earned day whatever the list says, which is the
/// same rule `ForgeSnapshot.fraction` follows — the first pull is granted with
/// the list unfinished, and a ring three-quarters closed under a freed blade
/// would be contradicting the blade.
struct DayRing: View {
    let fraction: Double
    let isEarned: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.primary.opacity(0.22), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: isEarned ? 1 : max(0.001, min(1, fraction)))
                .stroke(.primary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                // From the top, clockwise, like every progress ring iOS draws.
                .rotationEffect(.degrees(-90))
                .padding(1.25)
                .opacity(isEarned || fraction > 0 ? 1 : 0)
        }
        .accessibilityHidden(true)
    }
}

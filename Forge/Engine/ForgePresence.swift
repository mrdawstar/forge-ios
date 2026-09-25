import ActivityKit
import Foundation
import WidgetKit

/// Everything Forge shows while nobody is looking at Forge.
///
/// One writer. The widgets and the Live Activity never read the model — they
/// read a `ForgeSnapshot` that this class publishes — so there is no second
/// place in the system deriving a streak or a completion count, and no way for
/// the Lock Screen to disagree with the app about the same day.
///
/// Everything here is best-effort. A widget that fails to reload and a Live
/// Activity that will not start are both things the user finds out about by
/// looking, and neither is worth an error in front of somebody's day.
@MainActor
final class ForgePresence {

    static let shared = ForgePresence()

    private var activity: Activity<ForgeActivityAttributes>?
    /// The last thing written. Publishing is called on every state change in
    /// the app, and most of those change nothing a widget can see.
    private var lastPublished: ForgeSnapshot?

    private init() {}

    /// Adopt whatever survived the app being killed.
    ///
    /// A Live Activity outlives its process. Without this, force-quitting
    /// mid-day would leave one on the Lock Screen that nothing could update
    /// or end, and the next launch would start a second one beside it.
    func adoptRunningActivity() {
        activity = Activity<ForgeActivityAttributes>.activities.first
    }

    /// The single entry point. Called wherever the day can have moved.
    func publish(_ snapshot: ForgeSnapshot) {
        guard snapshot != lastPublished else { return }
        lastPublished = snapshot

        snapshot.write()
        WidgetCenter.shared.reloadAllTimelines()

        Task { await syncActivity(with: snapshot) }
    }

    // MARK: - Live Activity

    /// Start it the moment the day starts, keep it in step, and end it the
    /// moment it stops being about anything.
    ///
    /// "The day has started" is one activity finished. Forge has no notion
    /// of an activity being *begun* — finishing one is the atomic act — so the
    /// first completion is the earliest honest moment to say a day is under
    /// way.
    private func syncActivity(with snapshot: ForgeSnapshot) async {
        let state = ForgeActivityAttributes.ContentState(
            done: snapshot.done,
            total: snapshot.total,
            isEarned: snapshot.isEarned
        )

        // Earned, or nothing done yet. The second covers the day rolling over
        // as well as somebody taking their last activity back: both leave a
        // day that has not started, and neither is worth a Lock Screen.
        guard !snapshot.isEarned, snapshot.done > 0 else {
            await end(with: state, earned: snapshot.isEarned)
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let content = ActivityContent(state: state, staleDate: staleDate(for: snapshot))

        if let activity {
            await activity.update(content)
        } else {
            // A refusal here is a settings choice, not an error worth raising.
            activity = try? Activity.request(
                attributes: ForgeActivityAttributes(),
                content: content,
                pushType: nil
            )
        }
    }

    /// The blade coming out is the payoff, so it is allowed to sit there for a
    /// minute before it goes. Everything else disappears at once — a day
    /// that never happened should leave nothing behind.
    private func end(with state: ForgeActivityAttributes.ContentState, earned: Bool) async {
        guard let running = activity else { return }
        activity = nil
        await running.end(
            ActivityContent(state: state, staleDate: nil),
            dismissalPolicy: earned ? .after(.now.addingTimeInterval(60)) : .immediate
        )
    }

    /// When the system should stop trusting this content on its own.
    ///
    /// The next rollover: after it, the activity is about a day that is
    /// over, and a stale Live Activity is dimmed rather than wrong.
    private func staleDate(for snapshot: ForgeSnapshot) -> Date? {
        Calendar.current.nextDate(
            after: .now,
            matching: DateComponents(hour: snapshot.dayStartHour, minute: 0),
            matchingPolicy: .nextTime
        )
    }

    #if DEBUG
    /// Ends anything running, whatever state it is in. Only for walking the
    /// lifecycle by hand.
    func endEverything() async {
        for running in Activity<ForgeActivityAttributes>.activities {
            await running.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        lastPublished = nil
    }
    #endif
}

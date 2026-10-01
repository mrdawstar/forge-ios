import SwiftUI

/// What Forge will say, before iOS asks whether it may.
///
/// # Why this exists
///
/// The system prompt is one line of Apple's words and two buttons, and it is
/// shown once ever. An app that raises it cold is asking somebody to decide
/// something they have no information about, and the honest answer to a question
/// you cannot evaluate is no. So the decision is made here, where the question
/// is answerable, and iOS is only asked once the user has already said yes.
///
/// # Why it shows the day rather than describing it
///
/// The three rows are not features, they are the actual notifications — the same
/// sentences, in the same order they would arrive, carrying the user's own first
/// activity and its hour where there is one. Somebody can look at that and know
/// whether they want it, which is the whole point of asking first. A bulleted
/// list of benefits could not be checked against anything.
///
/// **And they are now literally the same sentences.** They used to be three
/// string literals written out here, and the day the notification copy was
/// rewritten they silently stopped matching it: this screen went on promising
/// "Your day starts now.", "Time to begin." and "Keep the promise you made to
/// yourself." — none of which Forge sends any more. A permission prompt that
/// shows work the app will not do is the worst possible place for a copy drift,
/// so the rows call `ForgeNotificationPlan`'s own functions and there is nothing
/// left here to drift.
///
/// A refusal here is final: `declineReminders` writes down that the offer was
/// made, and nothing in Forge raises this a second time on its own.
struct NotificationPrimerView: View {
    /// The first thing on the day, if there is one, so the examples are the
    /// user's rather than ours.
    var firstActivity: ScheduledActivity?
    /// The hour the day would open on, in minutes past midnight.
    var openingMinute: Int
    /// The same reading the scheduler is handed, so the rows below are the
    /// scheduler's own output rather than a description of it.
    var state: ForgeNotificationState
    var onDecision: (Bool) -> Void

    @State private var isAsking = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Image(systemName: "bell.badge")
                .font(.system(size: 34, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Forge will say one thing at a time.")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.top, 18)
                .padding(.horizontal, 24)

            Text("At the hours you planned, and nowhere else.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 32)

            VStack(spacing: 10) {
                // By position: two rows can share a minute's label, and an id
                // that repeats draws the first row twice.
                ForEach(Array(examples.enumerated()), id: \.offset) { _, example in
                    ExampleRow(time: example.time, title: example.title, message: example.body)
                }
            }
            .padding(.top, 26)
            .padding(.horizontal, 20)

            Spacer(minLength: 0)

            Button {
                guard !isAsking else { return }
                isAsking = true
                Task {
                    let granted = await ForgeNotifications.shared.offerReminders()
                    finish(granted)
                }
            } label: {
                Text("Turn on reminders")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(ForgeTheme.cream)
            .foregroundStyle(Color(red: 0.063, green: 0.063, blue: 0.078))
            .disabled(isAsking)
            .padding(.horizontal, 24)
            .padding(.top, 24)

            // A no is a real answer and is taken as one. Nothing asks again.
            Button("Not now") {
                ForgeNotifications.shared.declineReminders()
                finish(false)
            }
            .font(.footnote.weight(.medium))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.top, 16)
            .padding(.bottom, 8)
        }
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ForgeTheme.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationCornerRadius(ForgeTheme.Radius.sheet)
    }

    private func finish(_ granted: Bool) {
        ForgeHaptics.shared.tap()
        onDecision(granted)
        dismiss()
    }

    // MARK: - The three, in the user's own day

    /// Internal, and a value rather than three inline literals, so a test can
    /// hold it against `ForgeNotificationPlan` — see `NotificationPlanTests`.
    struct Example: Equatable {
        let time: String
        let title: String
        let body: String
    }

    /// The real notifications, filled in with the real day where there is one.
    ///
    /// A day with nothing on it yet falls back to a plausible one rather than
    /// showing blanks — somebody deciding this during onboarding has not planned
    /// anything, and three empty rows would say Forge has nothing to offer.
    private var examples: [Example] {
        Self.examples(firstActivity: firstActivity, openingMinute: openingMinute, state: state)
    }

    static func examples(
        firstActivity: ScheduledActivity?,
        openingMinute: Int,
        state: ForgeNotificationState
    ) -> [Example] {
        let activity = firstActivity
        let name = activity?.name ?? "Read"
        let start = activity?.startMinute
        let minutes = activity?.minutes ?? 0
        let identity = activity.flatMap(state.identity)

        // The same three arithmetic rules the plan uses: the day opens on
        // whichever comes first, an activity speaks at its own hour, and the
        // follow-up lands a whole activity's length after it started.
        let opens = min(openingMinute, start ?? openingMinute)
        let speaks = start ?? openingMinute + 90
        let follows = speaks + max(minutes, ForgeNotificationPlan.missedGrace)

        let morning = Example(
            time: ClockMinute.label(opens),
            title: identity ?? ForgeNotificationPlan.standing(daysKept: state.daysKept),
            body: ForgeNotificationPlan.opening(
                first: activity,
                firstTimed: start == nil ? nil : activity,
                at: opens
            )
        )
        let begins = Example(
            time: ClockMinute.label(speaks),
            title: name,
            body: ForgeNotificationPlan.begin(identity, minutes: minutes)
        )
        // The plan never speaks twice at one minute: an activity at the hour
        // the day opens is said by the morning alone (`ForgeNotificationPlan.day`).
        // A wake-up at the wake time — every Arc that asks for one — is that day.
        return (speaks == opens ? [morning] : [morning, begins]) + [
            Example(
                time: ClockMinute.label(follows),
                title: name,
                body: ForgeNotificationPlan.waiting(
                    identity,
                    done: state.completedToday,
                    planned: state.plannedToday
                )
            ),
        ]
    }
}

/// One notification, drawn as it would arrive.
private struct ExampleRow: View {
    let time: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(time)
                .font(ForgeTheme.mono(11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 52, alignment: .leading)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: ForgeTheme.Radius.control))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(time). \(title) \(message)"))
    }
}

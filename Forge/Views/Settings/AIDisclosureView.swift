import SwiftUI

/// Exactly what leaves the phone when Forge asks a model something.
///
/// # Why this screen exists
///
/// Every app with a model in it has a paragraph somewhere saying "we may share
/// certain information with third-party providers to deliver AI features". That
/// sentence is technically true of practically any transmission, tells nobody
/// anything, and is the reason people assume the worst — correctly, most of the
/// time.
///
/// So this screen is not a policy. It is **the actual value**, rendered. It
/// reads `AIBrief` — the one struct in the codebase through which anything can
/// reach a model — and draws every field it holds, filled in with this person's
/// own data as it stands right now. If a field is added to `AIBrief` and not to
/// this screen, the screen is wrong; if it is added here and not there, it
/// cannot be filled in, because there is nothing to read it from.
///
/// The list of what is *absent* is as load-bearing as the list of what is
/// present, and it is written from the same struct's documentation rather than
/// from a marketing intention.
///
/// # It is also the consent (§2r)
///
/// The same screen, with **Allow** and **Not now** under it, is what somebody
/// reads before the first request Forge's AI would ever make for them —
/// `decision` is set and the buttons appear. It is never shown at launch: it is
/// raised by pressing something that would reach the model (see
/// `View.aiConsent`), and only in a build where the model is switched on. From
/// Settings it shows the choice already made, and takes it back.
struct AIDisclosureView: View {

    /// The brief as it would be sent this minute, for the ordinary calls.
    let brief: AIBrief
    /// The brief as it would be sent for a weekly reading, which is the widest
    /// one and the only one carrying counts.
    let readingBrief: AIBrief
    /// Whether a model is reachable at all from this build.
    let isConnected: Bool
    /// What Ask Forge sends on top of the brief, the widest of the three.
    /// Nil only in a preview; the section then says nothing yet.
    var coachBrief: CoachBrief? = nil
    /// The consent, to show and to take back. Nil in a preview.
    var consent: AIConsentStore? = nil
    /// Set when this screen *is* the consent: `true` for Allow, `false` for
    /// Not now. Nil when it is opened from Settings to be read.
    var decision: ((Bool) -> Void)? = nil

    var body: some View {
        List {
            Section {
                Text(opening)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 2)
            }

            howItWorksSection
            practiceSection
            activitiesSection
            identitiesSection
            weekSection
            coachSection
            typedSection
            absentSection
            whereSection
            if decision == nil { choiceSection }
        }
        .safeAreaInset(edge: .bottom) {
            if let decision { decisionBar(decision) }
        }
        // The title has to agree with the first sentence under it. "What is
        // sent" over "nothing below is ever sent" is the screen contradicting
        // itself in the space of two lines.
        .navigationTitle(isConnected ? "What is sent" : "What would be sent")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var opening: String {
        if decision != nil {
            return "Before Forge's AI answers for the first time, this is exactly what it would send, where it goes, and what it is used for. Nothing is sent unless you allow it."
        }
        return isConnected
            ? "Forge sends the following to its own server, which asks a model on your behalf. Nothing else about you is included, and nothing is kept."
            : "No model is connected in this build, so nothing below is ever sent. It is shown so you can see what would be."
    }

    // MARK: - What the AI is, before what it is sent

    /// The five things somebody has to know before saying yes, in plain
    /// sentences: what, to whom, who processes it, that their own words are in
    /// it, and what it is never used for. Held by `AIConsentTests` so none can
    /// be dropped quietly.
    private var howItWorksSection: some View {
        Section {
            ForEach(Self.explanations, id: \.self) { line in
                Text(line)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("How Forge's AI works")
        } footer: {
            Text(isConnected
                 ? "Only with Forge Pro, only when you press a button that asks for it, and only after you allow it here."
                 : "Forge's AI is not switched on in this version of the app. Until it is, everything is worked out on this phone and none of this is sent.")
        }
    }

    static let explanations: [String] = [
        "What is sent: the values listed below — your practice in counts, your week's activities and what you said you are becoming; for the Weekly Reading, one week's counts; for Ask Forge, your six stats and OVR, your Arc, today's list and the conversation.",
        "Where it goes: to Forge's own backend (run on Supabase), under an anonymous identifier with no name or email, together with Apple's proof of your Forge Pro purchase.",
        "Who processes it: the Forge backend asks OpenAI to write the answer. The app never talks to OpenAI directly and holds no OpenAI key.",
        "Your own words: anything you typed that the feature needs — activity names, what you said you are becoming, a chapter's intention, a request you type into Plan, and what you write to Ask Forge — may be processed to answer it.",
        "What it is never used for: advertising or tracking. It is not sold, not linked to you, and OpenAI does not train on it.",
    ]

    /// What is typed at the moment of asking rather than read from the record:
    /// Plan's request, and Ask Forge's messages.
    private var typedSection: some View {
        Section {
            Text("The request you type into Plan, as you typed it — for example “I work 9 to 17 and want to read every evening”.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Text("What you write to Ask Forge, with the conversation before it: at most the last eight messages, yours and its replies.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("When you ask in your own words, also")
        } footer: {
            Text("Sent only when you press Work it out or send a message. Plan's own suggestions are worked out on this phone and never sent. The Ask Forge conversation is kept on this phone; Forge's server keeps none of it.")
        }
    }

    /// Ask Forge's additions (`CoachBrief`): everything on Becoming, the
    /// Arc's card and the Forge tab that the coach is told, drawn as it would
    /// be sent this minute.
    @ViewBuilder
    private var coachSection: some View {
        if let coach = coachBrief {
            Section {
                ForEach(coach.scores, id: \.category) { score in
                    row(score.category.label, score.score.map(String.init) ?? "No score yet")
                }
                if let overall = coach.overall {
                    row("OVR", "\(overall)")
                }
                if let arc = coach.arc {
                    row(arc.name, "Day \(arc.day) of \(arc.length) · \(arc.phase)")
                } else {
                    row("Arc", "None running")
                }
                if coach.today.isEmpty {
                    row("Today", "Nothing today")
                } else {
                    ForEach(Array(coach.today.enumerated()), id: \.offset) { _, item in
                        row(item.name, item.isDone ? "Done today" : "Not yet today")
                    }
                }
            } header: {
                Text("When you use Ask Forge, also")
            } footer: {
                Text("The numbers on Becoming, where you are in your Arc, and today's list with what is done. Only the Arc's id, day and phase are sent, and only today: no other day's record.")
            }
        }
    }

    // MARK: - The choice

    /// Allow, or Not now. Both close the sheet; only one ever sends anything.
    private func decisionBar(_ decision: @escaping (Bool) -> Void) -> some View {
        VStack(spacing: ForgeTheme.Space.tight) {
            ForgePrimaryButton(title: "Allow") { decision(true) }
            Button("Not now") { decision(false) }
                .font(.body.weight(.medium))
                .frame(minHeight: 44)
            Text("Not now keeps everything on this phone. You can change this any time in Settings → Planning.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, ForgeTheme.Space.gutter)
        .padding(.top, ForgeTheme.Space.inner)
        .padding(.bottom, ForgeTheme.Space.tight)
        .background(.bar)
    }

    /// From Settings: what was chosen, and the way to change it. Revoking is
    /// one tap and takes effect before the next request.
    @ViewBuilder
    private var choiceSection: some View {
        if let consent {
            Section {
                LabeledContent("Forge's AI") {
                    Text(Self.label(for: consent.state))
                }
                switch consent.state {
                case .allowed:
                    Button("Turn off Forge's AI", role: .destructive) { consent.revoke() }
                case .undecided, .declined:
                    Button("Allow Forge's AI") { consent.allow() }
                }
            } header: {
                Text("Your choice")
            } footer: {
                Text("Turning it off stops every request from the next one on. Forge goes on answering from this phone.")
            }
        }
    }

    static func label(for state: AIConsentStore.State) -> String {
        switch state {
        case .undecided: "Not asked yet"
        case .allowed: "Allowed"
        case .declined: "Off"
        }
    }

    // MARK: - The four blocks, in the order they widen

    private var practiceSection: some View {
        Section {
            // The "Archetype" row went with the archetypes. It had been
            // reading `None` for every user in the world, which is a row whose
            // only remaining job was to raise a question the app can no longer
            // answer.
            row("Days kept", ForgeCount.spelled(brief.daysKept))
            row("Current run", ForgeCount.spelled(brief.streak))
            row(
                "Wake time",
                brief.wakeMinutes.map(ClockMinute.label) ?? "Not sent"
            )
            if !brief.parts.isEmpty {
                row("Parts of the day", brief.parts.joined(separator: ", "))
            }
        } header: {
            Text("The practice")
        } footer: {
            Text("Counts and clock times. Not the days themselves — no date on which you did or did not keep one ever leaves this phone for this.")
        }
    }

    private var activitiesSection: some View {
        Section {
            if brief.activities.isEmpty {
                Text("Nothing yet").foregroundStyle(.secondary)
            } else {
                ForEach(brief.activities) { activity in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activity.name)
                        Text(shape(of: activity))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            Text("Your week")
        } footer: {
            Text("The name, the time, the length and the days. Not whether you did any of them, except today's list for Ask Forge, below.")
        }
    }

    private var identitiesSection: some View {
        Section {
            if brief.identities.isEmpty && brief.chapterIntention.isEmpty {
                Text("Nothing yet").foregroundStyle(.secondary)
            } else {
                ForEach(brief.identities, id: \.self) { Text($0) }
                if !brief.chapterIntention.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(brief.chapterIntention)
                        Text("This chapter's intention")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            Text("What you said you are becoming")
        } footer: {
            Text("Sentences you wrote yourself, sent as you wrote them. These are the most personal thing here, and they are why this screen exists.")
        }
    }

    /// The widest one, and the only one that carries how the week actually went.
    private var weekSection: some View {
        Section {
            if let week = readingBrief.week {
                row("Days kept this week", "\(ForgeCount.spelled(week.kept)) of \(ForgeCount.spelled(week.asked).lowercased())")
                ForEach(week.habits) { habit in
                    row(habit.name, "\(habit.completed) of \(habit.planned)")
                }
                ForEach(week.identities) { identity in
                    row(identity.statement, "\(identity.days) days")
                }
            } else {
                Text("Nothing yet").foregroundStyle(.secondary)
            }
        } header: {
            Text("When you open a weekly review, also")
        } footer: {
            Text("Counts for one week, so the sentence Forge writes back can be checked against them. Every number a model writes is verified against these before you see it — one that does not match is thrown away and Forge's own sentence is used instead.")
        }
    }

    private var absentSection: some View {
        Section {
            ForEach(Self.absent, id: \.self) { Text($0) }
        } header: {
            Text("Never sent")
        } footer: {
            Text("Not by policy — there is no field on the value that carries them, so there is nothing to send.")
        }
    }

    /// Everything `AIBrief` deliberately has no field for. Kept in step with
    /// that struct's documentation by hand, and by `AIDisclosureTests`, which
    /// fails if the brief grows a property this screen does not draw.
    static let absent: [String] = [
        "Your name, email, or account",
        "Your device, or anything that identifies it",
        "Any past day's record",
        "Any date at all",
        "Any reading from Apple Health: steps, minutes or sleep",
        "Anything you wrote in a weekly review",
        "Photographs, location, or contacts",
    ]

    /// Where it goes — and in this build, the answer is nowhere.
    ///
    /// This section used to name Forge's server and the model provider's API
    /// unconditionally, two screens' worth of scrolling below a first sentence
    /// saying nothing is ever sent. Both cannot be true, and in 1.0 it is the
    /// second: `RemoteForgeAI.isModelEnabled` is false, there is no project in
    /// `Info.plist`, and no object in the process can form the request. A screen
    /// whose whole purpose is to be checkable cannot end on a description of
    /// traffic the binary is incapable of.
    ///
    /// So it follows `isConnected`, exactly as the title and the opening
    /// sentence already did. The connected wording is kept rather than deleted
    /// for the same reason the rest of the seam is: flipping the constant has to
    /// remain a one-line change, and that includes the sentence that tells
    /// somebody the truth changed.
    @ViewBuilder
    private var whereSection: some View {
        Section(isConnected ? "Where it goes" : "Where it would go") {
            VStack(alignment: .leading, spacing: ForgeTheme.Space.tight) {
                if isConnected {
                    Text("Forge's own server, and then OpenAI's API.")
                    Text("The app holds no model key and never talks to a model directly. Requests are made by Forge's backend, which is the only place a key exists, only while you have Forge Pro, only after you allow it, and under an anonymous identifier with no name or email. It is not used for advertising or tracking. OpenAI does not train on API data by default, and Forge asks it not to keep the response.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Nowhere. Everything above stays on this phone.")
                    Text("This version has Forge's AI switched off. When it is switched on, requests will go to Forge's own backend and be processed by OpenAI, only with Forge Pro and only after you allow it. Until then Plan and the weekly review work everything out on this device, and nothing above is sent.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)

            if let privacy = ForgeLinks.privacy {
                Link("Privacy policy", destination: privacy)
            }
        }
    }

    // MARK: -

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: ForgeTheme.Space.row)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func shape(of activity: ScheduledActivity) -> String {
        var parts: [String] = []
        if let start = activity.startMinute { parts.append(ClockMinute.label(start)) }
        if activity.minutes > 0, let length = ClockMinute.duration(activity.minutes) {
            parts.append(length)
        }
        parts.append(RitualRepeat(weekdays: activity.weekdays).label.lowercased())
        return parts.joined(separator: " · ")
    }
}

// MARK: - Asking, at the moment it matters

/// The two briefs the disclosure renders, handed in by whoever is about to ask.
struct AIDisclosureBriefs {
    let brief: AIBrief
    let readingBrief: AIBrief
    /// Ask Forge's additions, when Ask Forge is the one asking — and from
    /// Settings, so the screen there shows all three.
    var coach: CoachBrief? = nil
}

/// Presents the disclosure as a consent — Allow / Not now — and records the
/// answer in `AIConsentStore` before telling the caller.
///
/// Attached to the screens that can reach the model (Plan, the weekly review)
/// and raised only from a button press there. Nothing presents it at launch.
private struct AIConsentPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let briefs: AIDisclosureBriefs?
    let onDecision: (Bool) -> Void
    @Environment(AIConsentStore.self) private var consent: AIConsentStore?

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            NavigationStack {
                AIDisclosureView(
                    brief: briefs?.brief ?? AIBrief(),
                    readingBrief: briefs?.readingBrief ?? AIBrief(),
                    isConnected: true,
                    coachBrief: briefs?.coach,
                    decision: { allowed in
                        if allowed { consent?.allow() } else { consent?.decline() }
                        isPresented = false
                        onDecision(allowed)
                    }
                )
                .navigationTitle("Forge's AI")
            }
            // Answered with a button, not a swipe: a swipe is neither yes nor
            // no, and the caller is waiting to know which.
            .interactiveDismissDisabled()
        }
    }
}

extension View {
    /// Ask for AI consent when `isPresented` becomes true. `onDecision` is
    /// called with the answer after it has been stored.
    func aiConsent(
        isPresented: Binding<Bool>,
        briefs: AIDisclosureBriefs?,
        onDecision: @escaping (Bool) -> Void
    ) -> some View {
        modifier(AIConsentPresenter(isPresented: isPresented, briefs: briefs, onDecision: onDecision))
    }
}

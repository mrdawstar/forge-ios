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
struct AIDisclosureView: View {

    /// The brief as it would be sent this minute, for the ordinary calls.
    let brief: AIBrief
    /// The brief as it would be sent for a weekly reading, which is the widest
    /// one and the only one carrying counts.
    let readingBrief: AIBrief
    /// Whether a model is reachable at all from this build.
    let isConnected: Bool

    var body: some View {
        List {
            Section {
                Text(opening)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 2)
            }

            practiceSection
            activitiesSection
            identitiesSection
            weekSection
            absentSection
            whereSection
        }
        // The title has to agree with the first sentence under it. "What is
        // sent" over "nothing below is ever sent" is the screen contradicting
        // itself in the space of two lines.
        .navigationTitle(isConnected ? "What is sent" : "What would be sent")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var opening: String {
        isConnected
            ? "Forge sends the following to its own server, which asks a model on your behalf. Nothing else about you is included, and nothing is kept."
            : "No model is connected in this build, so nothing below is ever sent. It is shown so you can see what would be."
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
            Text("The name, the time, the length and the days. Not whether you did any of them.")
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
        "Any single day's record",
        "Any date at all",
        "Health or workout data",
        "Anything you wrote in a weekly review",
        "Photographs, location, or contacts",
    ]

    /// Where it goes — and in this build, the answer is nowhere.
    ///
    /// This section used to name Forge's server and Anthropic's API
    /// unconditionally, two screens' worth of scrolling below a first sentence
    /// saying nothing is ever sent. Both cannot be true, and in 1.0 it is the
    /// second: `ClaudeForgeAI.isModelEnabled` is false, there is no project in
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
                    Text("Forge's own server, and then Anthropic's model API.")
                    Text("The app holds no model key and never talks to a model directly. Requests are made by Forge's backend, which is the only place a key exists. Anthropic does not train on it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Nowhere. Everything above stays on this phone.")
                    Text("This build has no model connected and no account to connect one with. Plan works out every move on this device from your own record, and Forge makes no network request of any kind.")
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

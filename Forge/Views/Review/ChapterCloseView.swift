import SwiftUI

/// Six weeks, closed.
///
/// # Why this is the screen that matters at month nine
///
/// A practice with no endings has no moment to look back from. Days accumulate,
/// the number goes up, and the question the whole app is about — *is this still
/// who I am becoming?* — never gets asked, because there is never a natural
/// place to ask it. A chapter closing is that place, and it is the only one.
///
/// Four things, in this order, and the order is the argument:
///
/// 1. **The weeks, side by side.** Six rows of seven marks. Not a chart — a
///    shape, read in two seconds, that says what the six weeks actually looked
///    like rather than what somebody remembers.
/// 2. **The evidence, per identity.** The days that were *for* something,
///    counted inside this chapter only. This is the payoff for the tag added in
///    the identity spine: a sentence somebody wrote six weeks ago, with the
///    number of days that back it up.
/// 3. **Their own sentences, read back.** Every weekly review they answered,
///    oldest first. Nobody remembers what they wrote in week two, and reading it
///    at week six is the single most useful thing in this screen — it is the
///    only place in the app where a user is confronted with their own words from
///    a person they have since stopped being.
/// 4. **One question.** "Is this still who you're becoming?"
///
/// # What the question may do
///
/// Re-affirm, rewrite, or retire — and **retire, never delete**. An identity
/// pursued for six weeks explains six weeks of history; see `Identity.retiredAt`
/// for why the destructive one is a separate act with a different name. Nothing
/// here can lose a day of the record either way: a chapter is a window over the
/// history and closing one takes nothing out of it.
///
/// # Skippable
///
/// "Close it later" leaves the chapter open and offers again tomorrow. There is
/// no penalty for a chapter that runs to nine weeks, because six is a suggestion
/// and nothing was ever late.
struct ChapterCloseView: View {
    let chapter: Chapter
    let reading: ChapterReading
    /// Six rows of seven, oldest first.
    let weeks: [[ProgressStore.WeekDay]]
    /// The identities this chapter was about, with days of evidence inside it.
    let evidence: [(identity: Identity, days: Int)]
    /// Every weekly review they answered inside the chapter, oldest first.
    let reviews: [WeeklyReview]
    let daysKept: Int

    /// Close it, keeping these identities active and opening the next chapter.
    let onClose: (String, String) -> Void
    /// Retire one, from the question at the foot.
    let onRetire: (Identity) -> Void
    let onLater: () -> Void
    /// Door 3: the Forge Pro invitation, at the foot of the screen. Decided by
    /// `PremiumInvitation` before the sheet opens and latched on appear.
    var offersPro: Bool = false
    /// The invitation has been seen; the door is spent.
    var onProOffered: () -> Void = {}

    @State private var nextName = ""
    @State private var nextIntention = ""
    @State private var isOpening = false
    @State private var isOfferingPro = false
    @State private var paywallDoor: ForgeTelemetry.PaywallDoor?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ForgeTheme.Space.section) {
                    headline
                    weekRows
                    if !evidence.isEmpty { evidenceSection }
                    if !reviews.isEmpty { saidSection }
                    question
                    if isOpening { next }
                    // Last, below everything somebody came here to read. The
                    // chapter is theirs; this is an offer beside it.
                    if isOfferingPro {
                        PremiumInvitationView {
                            paywallDoor = PremiumInvitation.Door.chapterClose.telemetry
                        }
                    }
                }
                .padding(.horizontal, ForgeTheme.Space.gutter)
                .padding(.top, ForgeTheme.Space.row)
                .padding(.bottom, ForgeTheme.Space.chapter)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(chapter.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close it later") { onLater() }
                }
            }
            .safeAreaInset(edge: .bottom) { commit }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(ForgeTheme.Radius.sheet)
        .presentationDragIndicator(.visible)
        .onAppear {
            guard offersPro, !isOfferingPro else { return }
            isOfferingPro = true
            onProOffered()
        }
        .paywall($paywallDoor)
    }

    // MARK: - What it was

    private var headline: some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Space.tight) {
            Text(count)
                .font(.system(size: 34, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)

            if !chapter.intention.isEmpty {
                // What they said it was for, six weeks ago. Shown without
                // comment: nothing here scores an intention against what
                // happened, because an intention is not a target.
                Text("You said it was for: \(chapter.intention)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ArtifactShareButton(
                artifact: PracticeArtifact(
                    occasion: .chapter(name: chapter.name),
                    daysKept: daysKept,
                    identity: evidence.first?.identity.statement,
                    date: .now
                )
            )
            .padding(.top, ForgeTheme.Space.tight)
        }
    }

    /// Two cumulative figures and no verdict — a chapter cannot be failed, so
    /// nothing on it may read as a mark.
    private var count: String {
        guard reading.daysKept > 0 else { return "Nothing was kept in it." }
        let word = reading.daysKept == 1 ? "day" : "days"
        return "\(ForgeCount.spelled(reading.daysKept)) \(word) kept, of \(reading.daysElapsed)."
    }

    // MARK: - 1. The weeks

    private var weekRows: some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Space.row) {
            SectionHeading("Week by week")

            VStack(spacing: 6) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                    HStack(spacing: 5) {
                        Text("\(index + 1)")
                            .font(ForgeTheme.mono(10))
                            .foregroundStyle(.tertiary)
                            .frame(width: 14, alignment: .leading)

                        ForEach(week) { day in
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(day.isEarned
                                      ? AnyShapeStyle(ForgeTheme.accent)
                                      : day.isRest
                                        ? AnyShapeStyle(ForgeTheme.accent.opacity(0.28))
                                        : AnyShapeStyle(.quaternary))
                                .frame(height: 20)
                        }
                    }
                }
            }
            .padding(ForgeTheme.Space.row)
            .forgeCard(radius: ForgeTheme.Radius.card)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Six weeks, \(reading.daysKept) days kept")
        }
    }

    // MARK: - 2. The evidence

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Space.row) {
            SectionHeading("What the days were for")

            VStack(spacing: 9) {
                ForEach(evidence, id: \.identity.id) { row in
                    HStack(alignment: .firstTextBaseline, spacing: ForgeTheme.Space.inner) {
                        Image(systemName: row.identity.symbol)
                            .font(.caption)
                            .foregroundStyle(row.identity.accent.palette.accent)
                            .frame(width: 20)
                            .accessibilityHidden(true)

                        Text(row.identity.statement)
                            .font(.subheadline.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: ForgeTheme.Space.tight)

                        Text(days(row.days))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(14)
                    .forgeCard(radius: ForgeTheme.Radius.control)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func days(_ count: Int) -> String {
        switch count {
        case 0: "No days"
        case 1: "One day"
        default: "\(ForgeCount.spelled(count)) days"
        }
    }

    // MARK: - 3. What they said

    /// Their own sentences, oldest first, with the week they belong to.
    ///
    /// Read back verbatim and never summarised. The whole value of this section
    /// is that it is not the app's account of six weeks, it is theirs — and an
    /// app that paraphrased somebody's own writing back at them would have
    /// stolen the one thing on this screen it did not produce.
    private var saidSection: some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Space.row) {
            SectionHeading("What you said", detail: "\(reviews.count) weeks")

            VStack(spacing: 9) {
                ForEach(reviews) { review in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Self.weekLabel(review.weekStart).uppercased())
                            .font(ForgeTheme.overline)
                            .kerning(ForgeTheme.overlineKerning)
                            .foregroundStyle(.tertiary)

                        if !review.whatHappened.isEmpty {
                            Text(review.whatHappened)
                                .font(.footnote)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if !review.whatNext.isEmpty {
                            Text("→ \(review.whatNext)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .forgeCard(radius: ForgeTheme.Radius.control)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: - 4. The question

    /// The one question, asked of each identity this chapter was about.
    ///
    /// Plain rows rather than a control, because retiring one is not a setting
    /// — it ends something somebody has been carrying for six weeks, and the
    /// row that does it should look like a decision.
    ///
    /// **Only for somebody who has identities.** It used to draw an empty state
    /// — "You named nobody in particular for this one" — under a heading asking
    /// whether that nobody was still who they were becoming, which is two
    /// sentences of the app talking to itself on a screen somebody reaches once
    /// every six weeks. The chapter's own intention is asked about below either
    /// way; see `next`.
    @ViewBuilder
    private var question: some View {
        if !evidence.isEmpty {
            VStack(alignment: .leading, spacing: ForgeTheme.Space.row) {
                SectionHeading("Is this still who you're becoming?")

                VStack(spacing: 9) {
                    ForEach(evidence, id: \.identity.id) { row in
                        HStack(spacing: ForgeTheme.Space.inner) {
                            Text(row.identity.statement)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: ForgeTheme.Space.tight)

                            // Retire, never delete. The days stay explained.
                            Button("Retire") {
                                ForgeHaptics.shared.detent()
                                onRetire(row.identity)
                            }
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                        }
                        .padding(14)
                        .forgeCard(radius: ForgeTheme.Radius.control)
                    }
                }

                Text("Retiring one keeps every day it explains. Nothing is deleted and no count changes.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - The next one

    private var next: some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Space.row) {
            SectionHeading("The next six weeks")

            TextField("Name it", text: $nextName)
                .textFieldStyle(.plain)
                .font(.body)
                .padding(ForgeTheme.Space.inner)
                .forgeCard(radius: ForgeTheme.Radius.control)

            TextField("What is it for?", text: $nextIntention, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.plain)
                .font(.body)
                .padding(ForgeTheme.Space.inner)
                .forgeCard(radius: ForgeTheme.Radius.control)
        }
    }

    private var commit: some View {
        VStack(spacing: ForgeTheme.Space.tight) {
            Button {
                ForgeHaptics.shared.ritualVerified()
                if isOpening {
                    onClose(nextName, nextIntention)
                } else {
                    // Reduce Motion turns the panel reveal into a cut. The
                    // panel still appears and the flow is identical; what goes
                    // is the slide, which is the part that costs somebody with
                    // vestibular sensitivity.
                    withAnimation(reduceMotion ? nil : .sheetPanel) { isOpening = true }
                }
            } label: {
                Text(isOpening ? openTitle : "Close this chapter")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .contentShape(.rect)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(ForgeTheme.accent)
            .foregroundStyle(.white)

            Text(isOpening
                 ? "A name is enough. Everything about it is editable afterwards."
                 : "Closing changes nothing about your record. The days stay exactly as they are.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, ForgeTheme.Space.gutter)
        .padding(.top, ForgeTheme.Space.inner)
        .padding(.bottom, ForgeTheme.Space.tight)
        .background(.bar)
    }

    /// Naming the next chapter is optional. Somebody who wants to close this one
    /// and think about the next later is allowed to — being between chapters is
    /// a real state and `ChapterStore` supports it.
    private var openTitle: String {
        Chapter.trimmed(nextName, to: Chapter.nameLimit).isEmpty
            ? "Close without starting another"
            : "Open it"
    }

    private static func weekLabel(_ day: ForgeDay) -> String {
        weekFormat.string(from: day.startOfDay())
    }

    private static let weekFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }()
}

import SwiftUI

/// Ninety seconds, once a week.
///
/// # The shape, and why it is this short
///
/// The week, one sentence from Forge, two from the user. That is the entire
/// screen, and every temptation to add a third thing has to be measured against
/// the only number that matters here: **a review that takes five minutes is done
/// twice and abandoned in week three.** Charts, comparisons with last week, a
/// score out of ten and a mood picker are all things a reasonable person would
/// suggest, and every one of them costs more than it returns.
///
/// # The order
///
/// 1. **The week, and the one thing in it worth saying.** Seven marks exactly as
///    the home screen draws them, the count under them, and — below a hairline
///    in the same card — one sentence, stated flatly, never flattering, and only
///    ever a fact from the record (see `ReviewObservation`). Somebody has to be
///    able to see the week before being asked about it, and the observation is
///    the thing they could not have said themselves.
/// 2. **What they said last week was for**, read back. One line, never scored.
/// 3. **Two questions**, in their own words, both skippable.
///
/// Beats one and two are the two additions this screen has taken since it was
/// written, and both were subtractive in effect: one merged two objects into
/// one, and the other is the only thing on the screen that makes doing this
/// fifty times different from doing it once. Everything else that was suggested
/// — a score, a comparison, a mood — is still refused.
///
/// # Skippable, and it costs nothing
///
/// "Not now" writes the week down as dealt with and never mentions it again.
/// There is no count of reviews done, no streak of them, and nothing anywhere
/// marks a week nobody wrote about. Somebody who dismisses every review for a
/// year has exactly the app they would have had if this had never been built.
struct WeeklyReviewView: View {
    let facts: ReviewFacts
    let days: [ProgressStore.WeekDay]
    /// What the week is called, for the heading — "25 May – 31 May".
    let window: String
    /// Anything they wrote last time, so re-opening a review is editing it
    /// rather than starting again.
    var existing: WeeklyReview?
    /// The last week they answered, so this one can begin by reading back what
    /// they said it was for. Nil for a first review, and for anybody whose
    /// previous week was dismissed rather than written.
    var previous: WeeklyReview?

    let onAnswer: (String, String) -> Void
    let onDismiss: () -> Void

    /// Asks whoever owns the model for a better sentence about this same week.
    ///
    /// Optional, and every caller that does not supply one gets the rules —
    /// which is what the whole screen ran on before a model existed and what it
    /// still runs on for anybody offline, signed out or not paying.
    var betterReading: (() async -> PracticeReading?)?

    @State private var whatHappened = ""
    @State private var whatNext = ""
    @FocusState private var focus: Field?

    /// What is on screen right now. Seeded from the rules **synchronously**, so
    /// the review never opens on a spinner or an empty space that fills in
    /// later: a ninety-second ritual cannot afford to begin with a wait, and a
    /// sentence that appears after the eye has moved on is a sentence nobody
    /// reads. If a model answers and its answer survives validation, this is
    /// replaced; if it does not, nothing happens and nobody is told.
    @State private var reading: PracticeReading?

    private enum Field { case happened, next }

    /// The phone's own answer. Always available, never wrong.
    private var ruled: PracticeReading? {
        ReviewObservation.make(from: facts).map { PracticeReading(observation: $0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ForgeTheme.Space.section) {
                    week
                    lastWeek
                    questions
                }
                .padding(.horizontal, ForgeTheme.Space.gutter)
                .padding(.top, ForgeTheme.Space.row)
                .padding(.bottom, ForgeTheme.Space.chapter)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("The week")
            .navigationSubtitle(window)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // "Not now", never "Skip". Skipping is something you do to a
                    // task; this is an offer, and declining one is ordinary.
                    Button("Not now") { onDismiss() }
                }
                ToolbarItem(placement: .keyboard) {
                    Spacer()
                }
            }
            .safeAreaInset(edge: .bottom) { commit }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(ForgeTheme.Radius.sheet)
        .presentationDragIndicator(.visible)
        .onAppear {
            whatHappened = existing?.whatHappened ?? ""
            whatNext = existing?.whatNext ?? ""
            reading = ruled
        }
        .task {
            // Silent on every failure. A model that is unreachable, unpaid for,
            // slow, or wrong leaves the phone's own sentence exactly where it
            // already is — and there is nothing for the user to notice, because
            // nothing has gone wrong from where they are sitting.
            guard let betterReading, let written = await betterReading() else { return }
            guard written.isModelWritten, !written.observation.isEmpty else { return }
            reading = written
        }
    }

    // MARK: - 1. The week, and what Forge noticed about it

    /// One object, not two.
    ///
    /// The seven marks were a card and the observation was a heading and a
    /// paragraph floating under it, which made the top of a ninety-second screen
    /// two separate things to take in before the first question. They are one
    /// fact — *here is your week, and here is the one thing in it worth saying*
    /// — so they are one card, divided by a hairline, and the observation is set
    /// as the sentence it is rather than as a section.
    private var week: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach(days) { day in
                    DayMark(day: day)
                }
            }
            .frame(maxWidth: .infinity)

            Text(kept)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, ForgeTheme.Space.row)

            noticed
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ForgeTheme.Space.row)
        .forgeCard(radius: ForgeTheme.Radius.card)
    }

    // MARK: - 2. What you said last week was for

    /// The loop closed, in one line.
    ///
    /// This is the change that makes a review mean something in week four. Two
    /// questions asked fifty times a year, with nothing ever read back, is a
    /// form; the same two questions asked *after* being shown what you said the
    /// week was for is the only moment in the app where an intention meets what
    /// happened to it.
    ///
    /// It is a line rather than a card, and it is never scored. Forge does not
    /// say whether the week matched the sentence — nothing here knows, and a
    /// phone marking somebody's own intention right or wrong is exactly the
    /// thing this app does not do. It says what they said, and stops.
    @ViewBuilder
    private var lastWeek: some View {
        if let previous, !previous.whatNext.isEmpty {
            VStack(alignment: .leading, spacing: ForgeTheme.Space.tight) {
                Text("LAST WEEK YOU SAID")
                    .font(ForgeTheme.overline)
                    .kerning(ForgeTheme.overlineKerning)
                    .foregroundStyle(.tertiary)

                Text("“\(previous.whatNext)”")
                    .font(.callout)
                    .italic()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    /// The count, spelled, with no verdict attached. Days that asked for nothing
    /// are not in the denominator — an empty day is not a failed one.
    private var kept: String {
        guard facts.asked > 0 else { return "Nothing was asked for this week." }
        // Capitalised, and agreeing in number. It read "one of one days kept."
        // on a first week — lower case because both halves were lower-cased for
        // the middle of a sentence this is not in, and "one days" because the
        // noun never looked at the number in front of it.
        let kept = ForgeCount.spelled(facts.kept)
        let asked = ForgeCount.spelled(facts.asked).lowercased()
        return "\(kept) of \(asked) \(facts.asked == 1 ? "day" : "days") kept."
    }

    /// One sentence, and nothing at all when the record does not support one.
    ///
    /// The silent case is deliberate and it is what keeps the loud case worth
    /// reading: a first week has no pattern in it, and an app that produced an
    /// insight anyway would teach somebody by week two that the insights are
    /// decoration.
    @ViewBuilder
    private var noticed: some View {
        if let reading {
            VStack(alignment: .leading, spacing: ForgeTheme.Space.tight) {
                Rectangle()
                    .fill(ForgeTheme.separator)
                    .frame(height: 0.5)
                    .padding(.vertical, ForgeTheme.Space.row)

                Text(reading.observation)
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                // Said only when it is true, and never the other way round.
                // A missing line does not claim the phone wrote it; a present
                // one is the only thing in the app that says a model did.
                // See `ForgeAI` — no screen may imply authorship it does not
                // have, and this is where that rule is actually kept.
                if reading.isModelWritten {
                    Text("Written by a model from the numbers on this screen.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - 3. The two questions

    /// Two, and there will never be a third.
    ///
    /// One backward and one forward, which is the smallest pair that makes a
    /// week into a direction rather than a report. Neither asks how it *felt*:
    /// a mood is not a thing this app records, and a question about feelings on
    /// a bad week is an invitation to write something somebody will regret
    /// having on file.
    private var questions: some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Space.section) {
            question(
                "What actually happened this week?",
                hint: "The real reason, not the tidy one.",
                text: $whatHappened,
                field: .happened
            )

            question(
                "What is next week for?",
                hint: "One thing. It is allowed to be small.",
                text: $whatNext,
                field: .next
            )
        }
    }

    private func question(
        _ title: String, hint: String, text: Binding<String>, field: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Space.inner) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            TextField("", text: text, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($focus, equals: field)
                .padding(ForgeTheme.Space.inner)
                .frame(maxWidth: .infinity, alignment: .leading)
                .forgeCard(radius: ForgeTheme.Radius.control)
                .onChange(of: text.wrappedValue) { _, new in
                    // Clamped where it is typed as well as where it is stored,
                    // so the limit is something somebody meets rather than
                    // something that silently truncates them later.
                    if new.count > WeeklyReview.answerLimit {
                        text.wrappedValue = String(new.prefix(WeeklyReview.answerLimit))
                    }
                }
        }
    }

    // MARK: - Done

    private var commit: some View {
        VStack(spacing: ForgeTheme.Space.tight) {
            Button {
                ForgeHaptics.shared.ritualVerified()
                onAnswer(whatHappened, whatNext)
            } label: {
                Text(isBlank ? "Close the week" : "Save")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .contentShape(.rect)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(ForgeTheme.accent)
            .foregroundStyle(.white)

            // Answering nothing is a real answer, and the button says so rather
            // than being disabled. A screen that will not let you leave until
            // you have written something is a screen people stop opening.
            //
            // It used to say "read back at the end of the chapter", which was
            // true and was six weeks away. They are on the Becoming tab now, a
            // tap from the moment they are written — see `WeeklyReviewHistory`.
            Text("Kept on your phone. Read them back on Becoming.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, ForgeTheme.Space.gutter)
        .padding(.top, ForgeTheme.Space.inner)
        .padding(.bottom, ForgeTheme.Space.tight)
        .background(.bar)
    }

    private var isBlank: Bool {
        WeeklyReview.trimmed(whatHappened).isEmpty && WeeklyReview.trimmed(whatNext).isEmpty
    }
}

// MARK: - One day of the week

/// A single mark: kept, missed, rested, set aside, or not yet lived.
///
/// Five states and no numbers. The week is meant to be read as a shape in half a
/// second, and a row of percentages is a row of things to compare.
struct DayMark: View {
    let day: ProgressStore.WeekDay

    var body: some View {
        VStack(spacing: 6) {
            Text(Self.letter(day.day.weekday))
                .font(ForgeTheme.mono(9))
                .foregroundStyle(.tertiary)

            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(fill)
                .frame(height: 34)
                .overlay {
                    if day.isToday {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(ForgeTheme.accent.opacity(0.7), lineWidth: 1.5)
                    }
                }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken))
    }

    private var fill: AnyShapeStyle {
        if day.isEarned { return AnyShapeStyle(ForgeTheme.accent) }
        // A rested day is drawn as its own thing rather than as a hole: the
        // chain is unbroken and a gap in the row would be the app contradicting
        // itself. The same rule the heatmap follows.
        if day.isRest { return AnyShapeStyle(ForgeTheme.accent.opacity(0.28)) }
        if day.isSetAside || day.isFuture { return AnyShapeStyle(.quaternary) }
        if day.fraction > 0 { return AnyShapeStyle(ForgeTheme.accent.opacity(0.14)) }
        return AnyShapeStyle(.quaternary)
    }

    private var spoken: String {
        let name = Calendar.current.weekdaySymbols[safe: day.day.weekday - 1] ?? "Day"
        if day.isFuture { return "\(name), not yet" }
        if day.isEarned { return "\(name), kept" }
        if day.isRest { return "\(name), rested" }
        if day.isSetAside { return "\(name), set aside" }
        return "\(name), not kept"
    }

    private static func letter(_ weekday: Int) -> String {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        return symbols[safe: weekday - 1] ?? ""
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}


// MARK: - The weeks, read back

/// Everything somebody has written about their own weeks, newest first.
///
/// # Why this exists
///
/// Because the app was asking two open questions fifty times a year and putting
/// the answers somewhere the person who wrote them could not go. They were read
/// back exactly once, at a chapter close six weeks later, and never again. That
/// is the shape of a form rather than of a practice, and it quietly makes the
/// weekly review the least trustworthy thing in an app whose whole position is
/// that it does not lose what you did.
///
/// # Why it is a sheet off one row rather than a section
///
/// Ten weeks of two-sentence answers is more screen than the Becoming tab has,
/// and it is the past — this is the tab about the direction. So the tab spends a
/// single row on the pile and the reading happens here, at full height, where a
/// long answer is a paragraph rather than a truncation.
///
/// # What it is not
///
/// **Not editable.** A review is what somebody said at the end of a particular
/// week, and a week is not a document. Letting April be rewritten in June is how
/// a record of what you thought becomes a record of what you would prefer to
/// have thought — the same reason `PastDay` is read-only in the planner and a
/// lived Tuesday cannot be re-planned.
///
/// **Not counted.** No streak of reviews, no total, no gaps marked. The weeks
/// somebody skipped are simply not here, exactly as `ReviewStore.dismiss` always
/// promised.
struct WeeklyReviewHistory: View {
    var reviews: ReviewStore

    @Environment(\.dismiss) private var dismiss

    private var answered: [WeeklyReview] { reviews.answered }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: ForgeTheme.Space.section) {
                    ForEach(answered) { review in
                        entry(review)
                    }
                }
                .padding(.horizontal, ForgeTheme.Space.gutter)
                .padding(.top, ForgeTheme.Space.row)
                .padding(.bottom, ForgeTheme.Space.chapter)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Your weeks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .overlay { if answered.isEmpty { empty } }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(ForgeTheme.Radius.sheet)
        .presentationDragIndicator(.visible)
    }

    /// One week.
    ///
    /// The two answers are drawn as what they are — the person's own sentences —
    /// so they are set in the reading face at body size with the question above
    /// them as a small label. The alternative, a card per answer, would have put
    /// four surfaces on the screen for every week and turned somebody's own
    /// writing into form fields they cannot fill in.
    private func entry(_ review: WeeklyReview) -> some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Space.inner) {
            Text(Self.span(review.weekStart).uppercased())
                .font(ForgeTheme.overline)
                .kerning(ForgeTheme.overlineKerning)
                .foregroundStyle(ForgeTheme.accent)

            if !review.whatHappened.isEmpty {
                answer("WHAT HAPPENED", review.whatHappened)
            }
            if !review.whatNext.isEmpty {
                answer("WHAT IT WAS FOR", review.whatNext)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ForgeTheme.Space.row)
        .forgeCard(radius: ForgeTheme.Radius.card)
        .accessibilityElement(children: .combine)
    }

    private func answer(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(ForgeTheme.label(9))
                .kerning(1.2)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("Nothing Written Yet", systemImage: "text.quote")
        } description: {
            Text("Forge asks two questions at the end of each week. What you answer is kept here.")
        }
    }

    /// "25 May – 31 May". The same span the review itself is titled with, so a
    /// week is recognisable between the two screens.
    private static func span(_ start: ForgeDay) -> String {
        let end = start.adding(days: 6)
        return "\(formatter.string(from: start.startOfDay())) – \(formatter.string(from: end.startOfDay()))"
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }()
}

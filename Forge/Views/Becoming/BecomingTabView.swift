import SwiftUI

/// The direction, as opposed to the record.
///
/// The tab this replaces was called Paths and held one thing: a shelf of worlds
/// to dress the app in. That was a tab spent on the smallest question the
/// feature could answer. The app now knows who somebody says they are becoming —
/// see `Identity` — and "which world am I in" is a detail of that, not a peer of
/// it.
///
/// So the tab bar reads **Forge · Blade · Becoming · Settings**, and the middle
/// two are a pair: Blade is the record, which is entirely about days that have
/// already happened, and Becoming is the direction, which is entirely about days
/// that have not. Every number in this app used to answer the first question.
///
/// Three sections, in this order, and the order is the argument:
///
/// 1. **Who you are becoming**, with what the record says about it. The
///    identities come first because they are the user's own words and everything
///    below is in service of them.
/// 2. **Where the days go** — the five areas every activity is already filed
///    under, read off the history. It needs nothing to have been named, so it is
///    the one section that speaks to the majority who skipped the identity beat.
/// 3. **The world you are in**, or the plain statement that you are in none.
/// 4. **The shelf**, ordered by what they named.
/// 5. **One written for you**, which is the only thing here that costs money.
///
/// Reading downward: here is who you said you are, here is the shape you are
/// walking it in, here are the others. Any other order makes the catalog the
/// subject and the person the filter, which is the tab this one replaced.
///
/// **The offer goes last, and that is a correction.** `ownPath` used to sit
/// third, between the identities and the shelf — so a free account read its own
/// sentences, and then, before reaching a single thing it could actually use,
/// met a button saying "See what this is" whose only behaviour is to open the
/// paywall. An upsell wedged between somebody's own words and the free content
/// they came for is an advertisement in the middle of a paragraph. Moved to the
/// foot, it is the last thing on a screen that has already given them
/// everything else, which is the only position from which an offer reads as an
/// offer.
///
/// **It stays declinable.** Somebody who never opens this tab has an app that
/// works exactly as it always did: no identity is required, no world is
/// required, and nothing on the Forge or Blade tabs changes for want of either.
struct BecomingTabView: View {
    var forge: ForgeViewModel
    var identities: IdentityStore
    /// Every week somebody has written about. Read only — nothing on this tab
    /// answers a review, it only keeps them where they can be found.
    var reviews: ReviewStore

    /// Which dimension is open on the list, and lit on the polygon.
    @State private var inspecting: RitualCategory?
    /// Which dimension's suggestions are open, if any.
    @State private var offering: RitualCategory?
    /// The focus editor, which is the only route to changing what somebody said
    /// they wanted to build after the first run.
    @State private var isChoosing = false
    /// The weeks somebody has written about, if they have asked to see them.
    @State private var isReadingWeeks = false


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ForgeTheme.Space.section) {
                    hero
                    dimensionList
                    focusRow
                    nextStep
                    suggested
                    weeks
                    who
                }
                .padding(.horizontal, ForgeTheme.Space.gutter)
                .padding(.top, ForgeTheme.Space.hair)
                .padding(.bottom, ForgeTheme.Space.chapter)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Becoming")
            .sheet(isPresented: $isChoosing) { FocusEditor(forge: forge) }
            .sheet(isPresented: $isReadingWeeks) { WeeklyReviewHistory(reviews: reviews) }
        }
    }

    /// What somebody said they wanted to build, as one row rather than as a
    /// section.
    ///
    /// # Why the section went
    ///
    /// "What you're building" was a card of its own under the hexagon, one row
    /// per chosen dimension, each carrying that dimension's name, its score and
    /// a sentence about its direction. Every one of those facts is in **The Six**
    /// eight points further down, for all six rather than for three, in the same
    /// order and the same words. It was a filter of the list below it, drawn as
    /// though it were a different reading — and a screen that says the same
    /// number twice invites somebody to check whether the two agree.
    ///
    /// What was *not* redundant is the choosing: the focus aims what Forge
    /// offers and what `DayPlanner` proposes, and the first run is the only
    /// other place it can be set. So the reading is folded into The Six — a
    /// chosen dimension is marked there — and what is left here is the door,
    /// one row of it, stating the answer in words.
    ///
    /// # Why it moved under the six
    ///
    /// It sat directly beneath the hexagon, which put a sentence *counting* the
    /// choice above the six rows that *are* the choice — so the screen opened on
    /// a tally of something the reader had not been shown yet, and the two rows
    /// of type between the polygon and the list pushed the list itself below the
    /// fold on a small phone.
    ///
    /// The order the tab reads in now is the order the thing actually works in:
    /// **the shape you have, then the six it is made of, then how many of them
    /// you said you were building.** A progress line belongs after the thing it
    /// is progress through — it is the summary of the list above it and the door
    /// to changing it, and neither of those is a heading.
    ///
    /// Its height still does not depend on the count: two lines for the
    /// sentence and two for the note, reserved. That was the fix for the screen
    /// moving under a finger mid-choice (see `headline`) and it matters more
    /// down here, not less — everything below it would shift instead.
    private var focusRow: some View {
        Button {
            ForgeHaptics.shared.tap()
            isChoosing = true
        } label: {
            HStack(alignment: .top, spacing: ForgeTheme.Space.inner) {
                Image(systemName: "hexagon")
                    .font(.system(size: 15, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(chosen.isEmpty
                                     ? AnyShapeStyle(.secondary)
                                     : AnyShapeStyle(ForgeTheme.accent))
                    // Top-aligned against a block that reserves four lines, so
                    // the mark sits beside the sentence it belongs to rather
                    // than floating between the two.
                    .frame(width: 30, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        // Two lines, always. See the note on `headline`.
                        .lineLimit(2, reservesSpace: true)

                    Text("Forge aims what it offers at these. It never hides anything else.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2, reservesSpace: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.quaternary)
                    .padding(.top, 4)
            }
            .padding(ForgeTheme.Space.row)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .forgeInteractiveCard(radius: ForgeTheme.Radius.card)
        .accessibilityLabel(Text(
            chosen.isEmpty
                ? "Choose what you're building"
                : "You're building \(named). Double tap to change."
        ))
        .animation(.forgeSelection, value: headline)
    }

    private var chosen: [RitualCategory] {
        RitualCategory.dimensions.filter(forge.focus.contains)
    }

    /// What they chose, said the way a person would say it — and **at a height
    /// that does not depend on how many they chose.**
    ///
    /// # The screen was moving under people
    ///
    /// This row used to carry one accent glyph per chosen dimension followed by
    /// the full list in words, both unbounded. Choosing a fourth put six glyphs
    /// in a strip that had been sized for three, which squeezed the sentence
    /// beside them; choosing a fifth wrapped the sentence onto a third line. So
    /// the card grew by about twenty points, and **the hexagon above it and
    /// every one of the six rows below it moved** — while the finger was still
    /// on a row in the editor that had just closed. What that reads as is the
    /// app losing its place.
    ///
    /// Both halves are fixed now. One hexagon, lit or not, in place of a strip
    /// that counted; and the sentence bounded to the two lines it is given,
    /// which is why all six is said as **"all six"** rather than enumerated. The
    /// enumeration was never the useful reading anyway — the six rows underneath
    /// name every one of them and mark the chosen ones.
    private var headline: String {
        switch chosen.count {
        case 0: "Choose what you're building"
        case RitualCategory.dimensions.count: "You're building all six."
        case 1, 2, 3: "You're building \(named)."
        // Spelled, like every other count Forge says out loud below a hundred.
        default: "You're building \(ForgeCount.spelled(chosen.count).lowercased()) of the six."
        }
    }

    private var named: String {
        let names = chosen.map { $0.label.lowercased() }
        guard names.count > 1 else { return names.first ?? "" }
        var rest = names
        let last = rest.removeLast()
        return "\(rest.joined(separator: ", ")) and \(last)"
    }

    // MARK: - 1. Who you are becoming

    /// **Shown only to somebody who has one**, which after the first run was
    /// rebuilt means somebody who named one before it was.
    ///
    /// The identity spine is not going anywhere — it is what `Ritual.identityID`
    /// tags, what the challenge aims at, what the notifications speak in, and
    /// what months of somebody's history is already filed under. What went is
    /// the *question*: "Who are you becoming?" was the first thing the app
    /// asked a stranger, and it is a sentence people arrive at after months of
    /// a practice rather than before their first day of one. It is replaced by
    /// the six, which anybody can answer by pointing — see
    /// `FirstRunView.build`.
    ///
    /// So this section is history-only. An empty section headed "Who you're
    /// becoming", on a tab that no longer asks the question and offers no way
    /// to answer it, is exactly the kind of remnant that makes a product feel
    /// like a pile of features — so for the overwhelming majority of installs
    /// it simply is not there, and for the people who have identities nothing
    /// they wrote has been taken away.
    @ViewBuilder
    private var who: some View {
        if !identities.active.isEmpty {
            VStack(alignment: .leading, spacing: ForgeTheme.Space.row) {
                SectionHeading(
                    "Who you're becoming",
                    detail: "In your own words, and what the record says"
                )

                VStack(spacing: 1) {
                    ForEach(identities.active) { identity in
                        IdentityEvidenceRow(identity: identity, forge: forge)
                    }
                }
                .background(ForgeTheme.separator)
                .clipShape(ForgeTheme.cardShape(ForgeTheme.Radius.card))
            }
        }
    }

    // MARK: - 1. The Shape

    /// The hero, and the first thing on the tab.
    ///
    /// Everything about the ordering of this screen follows from one fact: the
    /// Shape is the only thing here that is true for **every** user on their
    /// second week, with nothing named, nothing chosen and no world taken. The
    /// identities below it are opt-in and most people skip them; the shelf is a
    /// catalogue. Leading with either meant the tab opened on an empty state or
    /// on somebody else's content.
    ///
    /// Under the polygon: one sentence saying what the thing *is*. It is there
    /// because a hexagon with numbers on it is a chart until somebody is told
    /// what feeds it, and the whole claim of this feature is that it is fed by
    /// what you actually did.
    ///
    /// # The first week
    ///
    /// Until the record has a week behind it *and* enough to read, the hero is
    /// the first-week contract instead (`FirstWeek`): when the shape will draw
    /// itself, and how many of the seven have been kept. It gives way to the
    /// polygon on its own the first time both are true — nothing is stored to
    /// decide that.
    @ViewBuilder
    private var hero: some View {
        let shape = forge.shape
        VStack(spacing: ForgeTheme.Space.row) {
            if let contract = forge.firstWeek {
                FirstWeekCard(contract: contract)
            } else {
                ForgeShapeView(shape: shape, highlighted: inspecting)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)

                Text("Six parts of you, scored on the last four weeks of your own record.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 1b. The six, inspectable

    /// One row per dimension: what it is, what it scores, which way it is going,
    /// and whether somebody said they were building it.
    ///
    /// Tapping a row lights its vertex on the polygon above and opens its
    /// meaning. That is the whole of the interaction — there is no detail screen
    /// behind a dimension, because there is nothing on one that is not already
    /// here, and a push to a page holding one sentence is a page nobody returns
    /// to.
    ///
    /// **The chosen ones are marked here rather than listed again above.** See
    /// `focusRow`: a second card repeating three of these six rows, with the
    /// same scores in the same order, was two readings of one fact.
    ///
    /// # All six, from the first day
    ///
    /// The list used to sit behind `shape.isReadable` — two measured dimensions
    /// and five kept days — on the argument that a column of six "Nothing here"
    /// is not a reading. That argument is right about the *hexagon* and wrong
    /// about the list, and the difference is what a person came here to find
    /// out. A polygon drawn on three days is a shape the app made up. A list of
    /// six names, each saying what it means and whether anything is pointing at
    /// it, is the truth on day one and it is the only place in the app that says
    /// what the six actually are.
    ///
    /// What it cost to hide them: somebody who chose two dimensions in the first
    /// run opened this tab and found the two they had already picked, and no
    /// indication that there were six, or what the other four were, or that
    /// anything could be added to them. The one screen about direction showed
    /// only the direction already taken.
    ///
    /// So: always six, always in order, marked where somebody said they were
    /// building one, and honest about the ones with nothing behind them yet.
    private var dimensionList: some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Space.row) {
            SectionHeading("The Six", detail: "Every activity builds one of them")

            let starters = forge.starters
            VStack(spacing: 1) {
                ForEach(forge.shape.dimensions) { dimension in
                    DimensionRow(
                        dimension: dimension,
                        isChosen: forge.focus.contains(dimension.category),
                        isInspecting: inspecting == dimension.category,
                        starter: starters[dimension.category],
                        onAdd: { ritual in
                            ForgeHaptics.shared.ritualVerified()
                            BecomingOffer.add(ritual, to: forge)
                        }
                    ) {
                        ForgeHaptics.shared.tap()
                        withAnimation(.forgeSelection) {
                            inspecting = inspecting == dimension.category ? nil : dimension.category
                        }
                    }
                }
            }
            .background(ForgeTheme.separator)
            .clipShape(ForgeTheme.cardShape(ForgeTheme.Radius.card))

            Text("Tap one to see what it means, and the arithmetic behind its score.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 1c. What to do about it

    /// One row, and only when there is something true to say.
    ///
    /// The rules are in `ForgeShape`: a dimension is only named when somebody
    /// keeps something in it, the record can speak about it, and it is at least
    /// fifteen points behind their best. Everything level means no row —
    /// manufacturing a weakest link on a balanced shape would be the app
    /// inventing a problem so that it has something to say, which is how a
    /// calm product becomes a nagging one.
    @ViewBuilder
    private var nextStep: some View {
        // Waits with the shape: during the first week the contract is the
        // reading, and naming a weakest side before the shape is drawn would
        // be a verdict on a week that has not happened yet.
        if forge.firstWeek == nil, let suggestion {
            Button {
                ForgeHaptics.shared.tap()
                withAnimation(.forgeSelection) {
                    offering = offering == suggestion.category ? nil : suggestion.category
                }
            } label: {
                HStack(spacing: ForgeTheme.Space.inner) {
                    Image(systemName: suggestion.category.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(ForgeTheme.accent)
                        .frame(width: 30, height: 30)
                        .background(ForgeTheme.separator, in: RoundedRectangle(
                            cornerRadius: ForgeTheme.Radius.glyph - 4, style: .continuous
                        ))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.headline)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(suggestion.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: offering == suggestion.category ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .padding(ForgeTheme.Space.row)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .forgeInteractiveCard(radius: ForgeTheme.Radius.card)
            .accessibilityLabel(Text("\(suggestion.headline). \(suggestion.detail)"))
            .accessibilityHint("Shows things you could add here")
        }
    }

    /// What the next-step row should say, or nil for a shape with nothing to
    /// point at.
    ///
    /// Two cases, in order. A dimension nothing is filed under is the stronger
    /// offer — it is a whole part of somebody's life the practice does not touch
    /// — and it is offered before a merely weaker one.
    ///
    /// A dimension nothing is filed under no longer gets this row: it carries
    /// its own starter in The Six (`BecomingStarter`), one tap from being on
    /// the day. Offering it here as well would be the same suggestion twice.
    private var suggestion: (category: RitualCategory, headline: String, detail: String)? {
        let shape = forge.shape
        if let weak = shape.needsAttention {
            return (
                weak.category,
                "\(weak.category.label) has had the least of you",
                "Add something here, or move an activity you already keep into it."
            )
        }
        return nil
    }

    // MARK: - 1d. Three things that would help

    /// Concrete activities for the dimension the row above just named.
    ///
    /// Opened by that row rather than shown permanently, and that is the whole
    /// of why this is not a catalogue: it appears when somebody has asked about
    /// one specific weak side, it offers three things, and each one goes onto
    /// the day in a single tap without leaving the screen. Naming a gap and then
    /// sending somebody to a picker to find something to fill it is advice, not
    /// a control.
    @ViewBuilder
    private var suggested: some View {
        if let offering {
            let options = forge.suggestions(for: offering)
            if !options.isEmpty {
                VStack(alignment: .leading, spacing: ForgeTheme.Space.row) {
                    SectionHeading(
                        "Add to your day",
                        detail: "Small, and specific to \(offering.label.lowercased())"
                    )

                    VStack(spacing: 1) {
                        ForEach(options) { ritual in
                            SuggestionRow(ritual: ritual) {
                                ForgeHaptics.shared.ritualVerified()
                                BecomingOffer.add(ritual, to: forge)
                                // Closes on its own. The offer was answered, and
                                // a list that stays open with one row now
                                // greyed out is a list asking whether you would
                                // like the other two as well.
                                withAnimation(.forgeSelection) { self.offering = nil }
                            }
                        }
                    }
                    .background(ForgeTheme.separator)
                    .clipShape(ForgeTheme.cardShape(ForgeTheme.Radius.card))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - 1e. The weeks you wrote about

    /// One row, and behind it every week somebody has answered.
    ///
    /// # Why it is on this tab and not the Blade
    ///
    /// Because a weekly review is not a record of what happened — that is the
    /// Blade's job and it is drawn in marks and rates. A review is the two
    /// sentences somebody wrote about *where this is going*: what actually
    /// happened, and what next week is for. That is the only thing in Forge the
    /// user themselves said about the direction, and the direction is what this
    /// tab is.
    ///
    /// It is also the answer to the thing the review was quietly missing.
    /// Everything written was stored and none of it was readable until a chapter
    /// closed, six weeks later — so the honest reading of the app's own promise
    /// ("Kept on your phone") was that the sentences went somewhere the person
    /// who wrote them could not follow.
    ///
    /// **One row, not a section.** Ten weeks of answers is a lot of screen, and
    /// this tab is about the present. So the tab spends a single row on it and
    /// the reading happens on a sheet — which is also what lets the row say the
    /// most useful thing about the pile, which is what the last one said next
    /// week was for.
    @ViewBuilder
    private var weeks: some View {
        let answered = reviews.answered
        if !answered.isEmpty {
            Button {
                ForgeHaptics.shared.tap()
                isReadingWeeks = true
            } label: {
                HStack(spacing: ForgeTheme.Space.inner) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 15, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(answered.count == 1
                             ? "One week, in your own words"
                             : "\(ForgeCount.spelled(answered.count)) weeks, in your own words")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)

                        Text(latest)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2, reservesSpace: true)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.quaternary)
                }
                .padding(ForgeTheme.Space.row)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .forgeInteractiveCard(radius: ForgeTheme.Radius.card)
            .accessibilityHint("Read what you wrote at the end of each week")
        }
    }

    /// The most recent forward-looking sentence, which is the one still in play.
    ///
    /// `whatNext` before `whatHappened`, deliberately: "what is next week for"
    /// is the half of a review that is still true when it is read back, and a
    /// row summarising a pile of reviews with an account of a fortnight ago
    /// would be a row about the past on a tab about the direction.
    private var latest: String {
        guard let last = reviews.answered.first else { return "Read them back." }
        if !last.whatNext.isEmpty { return "“\(last.whatNext)”" }
        if !last.whatHappened.isEmpty { return "“\(last.whatHappened)”" }
        return "Read them back."
    }

}

// MARK: - One identity, and what the record says about it

/// An identity with its evidence read off the history.
///
/// Every figure here is **derived on read** — days of evidence, the rate, the
/// count of activities — and none of it is stored anywhere. That is the same
/// rule the streak and the heatmap follow, and it is why an identity cannot
/// develop a number that disagrees with the days behind it. See `ProgressStore`.
///
/// It counts **days, not completions**: three tagged activities finished on one
/// Tuesday is one day of evidence. Counting otherwise turns an identity into a
/// score, which is the one thing this type exists not to be.
struct IdentityEvidenceRow: View {
    let identity: Identity
    var forge: ForgeViewModel

    private var activities: Set<String> { forge.activityIDs(taggedTo: identity.id) }
    private var days: Int { forge.daysOfEvidence(for: identity.id) }
    private var rate: Double { forge.evidenceRate(for: identity.id) }

    var body: some View {
        HStack(alignment: .top, spacing: ForgeTheme.Space.inner) {
            Image(systemName: identity.symbol)
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(identity.accent.palette.accent)
                .frame(width: 30, height: 30)
                .background(ForgeTheme.separator, in: RoundedRectangle(
                    cornerRadius: ForgeTheme.Radius.glyph - 4, style: .continuous
                ))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(identity.statement)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(reading)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ForgeTheme.Space.row)
        .background(.regularMaterial)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(identity.statement). \(reading)"))
    }

    /// What the record honestly supports, and nothing more.
    ///
    /// Three states, and the first two are the ones that matter. An identity
    /// with no activities tagged to it says so plainly rather than reporting a
    /// confident zero — "no days" and "nothing points at this yet" are different
    /// facts, and only the second one is true. An identity with activities but
    /// no completed day yet is at the start, which is also not a failure.
    ///
    /// Nothing congratulates. "Fourteen days of evidence" is a fact about
    /// somebody; "Great work — 14 days!" is an app with an opinion about a
    /// person's life.
    private var reading: String {
        guard !activities.isEmpty else {
            return "Nothing in your day is tagged to this yet."
        }
        guard days > 0 else {
            return "\(ForgeCount.spelled(activities.count)) \(activities.count == 1 ? "activity" : "activities"), and no day of evidence yet."
        }
        let evidence = "\(ForgeCount.spelled(days)) \(days == 1 ? "day" : "days") of evidence"
        guard rate > 0 else { return "\(evidence)." }
        return "\(evidence), on \(Int((rate * 100).rounded())) per cent of the days it was asked for."
    }
}

// MARK: - The Forge Shape

/// The polygon, and the one number inside it.
///
/// # Why a hexagon and not the bar chart this replaced
///
/// The previous version drew six bars. Bars are honest and completely
/// forgettable: they rank, and ranking is the one thing a person already knows
/// about their own life. What nobody can see without being shown it is the
/// *silhouette* — that four sides are long and two are flat, that the whole
/// thing is smaller than it was a month ago, that there is a notch where a
/// dimension used to be.
///
/// # The outline behind the fill
///
/// The full hexagon is drawn behind the filled one at low opacity, and that is
/// the most important line in this file. Without it a filled shape is
/// unreadable — 60 and 90 look identical when there is nothing to be 60 *of*.
/// With it, the gap between the two is the entire message, and it needs no
/// legend, no axis and no explanation.
///
/// It is deliberately not labelled "potential" anywhere on screen. A hundred in
/// every dimension is not a life anybody should be aiming at — it would mean
/// planning something in all six areas nearly every day and never missing — and
/// an app that drew that as the target would be setting a standard it knows is
/// unreachable. The outline is the edge of the instrument, not a goal.
///
/// # Why it is not animated on appearance
///
/// A shape that grows out of the centre every time the tab is opened turns a
/// reading into a reveal, and the second time somebody sees it the animation is
/// just latency. It animates when the *value* changes, which is the only time
/// motion here carries information.
struct ForgeShapeView: View {
    let shape: ForgeShape
    /// Which dimension is being inspected, if any. Drawn with its vertex lit.
    var highlighted: RitualCategory?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How much of the radius the label ring sits outside the polygon.
    private let labelInset: CGFloat = 30

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = side / 2 - labelInset
            let centre = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

            ZStack {
                web(centre: centre, radius: radius)
                filled(centre: centre, radius: radius)
                vertices(centre: centre, radius: radius)
                labels(centre: centre, radius: radius)
                core
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Your Forge Shape"))
        .accessibilityValue(Text(spoken))
    }

    // MARK: - Geometry

    /// The unit position of one dimension, clockwise from the top.
    private func point(_ index: Int, radius: CGFloat, centre: CGPoint, at fraction: Double = 1) -> CGPoint {
        let count = Double(shape.dimensions.count)
        let angle = (Double(index) / count) * 2 * .pi - .pi / 2
        return CGPoint(
            x: centre.x + cos(angle) * radius * fraction,
            y: centre.y + sin(angle) * radius * fraction
        )
    }

    private func polygon(radius: CGFloat, centre: CGPoint, fractions: [Double]) -> Path {
        var path = Path()
        for (index, fraction) in fractions.enumerated() {
            let p = point(index, radius: radius, centre: centre, at: max(0.04, fraction))
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    // MARK: - Layers

    /// The instrument: the outer hexagon, two rings inside it, and a spoke to
    /// each vertex. Quiet enough to read as engraving rather than as chrome.
    private func web(centre: CGPoint, radius: CGFloat) -> some View {
        let full = [Double](repeating: 1, count: shape.dimensions.count)
        return ZStack {
            ForEach([0.34, 0.67], id: \.self) { ring in
                polygon(
                    radius: radius * ring, centre: centre,
                    fractions: full
                )
                .stroke(ForgeTheme.accent.opacity(0.10), lineWidth: 0.5)
            }

            ForEach(shape.dimensions.indices, id: \.self) { index in
                Path { path in
                    path.move(to: centre)
                    path.addLine(to: point(index, radius: radius, centre: centre))
                }
                .stroke(ForgeTheme.accent.opacity(0.10), lineWidth: 0.5)
            }

            polygon(radius: radius, centre: centre, fractions: full)
                .stroke(ForgeTheme.accent.opacity(0.28), lineWidth: 1)
        }
    }

    /// What the record actually says.
    private func filled(centre: CGPoint, radius: CGFloat) -> some View {
        let fractions = shape.dimensions.map(\.fraction)
        let path = polygon(radius: radius, centre: centre, fractions: fractions)

        return ZStack {
            path.fill(
                RadialGradient(
                    colors: [
                        ForgeTheme.accent.opacity(0.42),
                        ForgeTheme.accent.opacity(0.14),
                    ],
                    center: .center, startRadius: 0, endRadius: radius
                )
            )
            // The bright edge is what makes the shape read as an object rather
            // than as a stain. It carries a glow of its own, which is the only
            // ornament on this screen and the reason the thing looks lit from
            // inside rather than printed.
            path
                .stroke(ForgeTheme.accent, lineWidth: 1.5)
                .shadow(color: ForgeTheme.accent.opacity(0.55), radius: 7)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.55), value: fractions)
    }

    /// A dot at each vertex, lit when its dimension is being inspected.
    private func vertices(centre: CGPoint, radius: CGFloat) -> some View {
        ForEach(Array(shape.dimensions.enumerated()), id: \.element.id) { index, dimension in
            let isLit = highlighted == dimension.category
            Circle()
                .fill(isLit ? ForgeTheme.accent : ForgeTheme.accent.opacity(0.55))
                .frame(width: isLit ? 7 : 4, height: isLit ? 7 : 4)
                .shadow(color: ForgeTheme.accent.opacity(isLit ? 0.9 : 0), radius: 6)
                .position(
                    point(index, radius: radius, centre: centre, at: max(0.04, dimension.fraction))
                )
                .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: isLit)
        }
    }

    /// The name and score outside each vertex.
    private func labels(centre: CGPoint, radius: CGFloat) -> some View {
        ForEach(Array(shape.dimensions.enumerated()), id: \.element.id) { index, dimension in
            let anchor = point(index, radius: radius + labelInset * 0.62, centre: centre)
            VStack(spacing: 1) {
                Text(dimension.category.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(
                        highlighted == dimension.category ? .primary : .secondary
                    )
                Text(dimension.isMeasured ? "\(dimension.score)" : "—")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(
                        dimension.isMeasured
                            ? AnyShapeStyle(ForgeTheme.accent)
                            : AnyShapeStyle(.tertiary)
                    )
            }
            .fixedSize()
            .position(anchor)
        }
    }

    /// The overall reading, in the middle where the eye already is.
    private var core: some View {
        VStack(spacing: 0) {
            Text("\(shape.overall)")
                .font(.system(size: 46, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.primary)

            Text(shape.state.label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(1.6)
                .foregroundStyle(ForgeTheme.accent)
                .padding(.top, 2)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: shape.overall)
    }

    private var spoken: String {
        let parts = shape.dimensions.map { dimension in
            dimension.isMeasured
                ? "\(dimension.category.label) \(dimension.score)"
                : "\(dimension.category.label), nothing yet"
        }
        return "Overall \(shape.overall), \(shape.state.label). " + parts.joined(separator: ". ")
    }
}

// MARK: - One dimension, in a row

/// A dimension's score, its direction, and — when opened — what it means.
///
/// The score is set at readable size and the bar under it is hairline, which is
/// the opposite weighting a dashboard uses. Here the number is the fact and the
/// bar is only there to make six of them comparable at a glance.
///
/// **Direction is shown as a word, not only as an arrow.** An arrow alone is
/// unreadable to anybody who has not been told what it is measuring against, and
/// this one is measuring the last fortnight against the one before it — which no
/// glyph can say.
private struct DimensionRow: View {
    let dimension: ForgeShape.Dimension
    /// Whether this is one somebody said they were building. Marked rather than
    /// listed twice — see `BecomingTabView.focusRow`.
    let isChosen: Bool
    let isInspecting: Bool
    /// The smallest library activity that would start this dimension, when
    /// nothing is filed under it. See `BecomingStarter`.
    var starter: Ritual? = nil
    var onAdd: (Ritual) -> Void = { _ in }
    let action: () -> Void

    /// The row, and under it — outside the row's own button, so the two taps
    /// cannot be confused — the starter for an empty dimension.
    var body: some View {
        VStack(spacing: 0) {
            row
            if let starter {
                StarterLine(ritual: starter) { onAdd(starter) }
                    .padding(.horizontal, ForgeTheme.Space.row)
                    .padding(.bottom, ForgeTheme.Space.inner)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial)
            }
        }
    }

    private var row: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: ForgeTheme.Space.inner) {
                    Image(systemName: dimension.category.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isChosen ? AnyShapeStyle(ForgeTheme.accent) : AnyShapeStyle(.secondary))
                        .frame(width: 26)
                        .accessibilityHidden(true)

                    Text(dimension.category.label)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    // One word, and only on the ones somebody pointed at. It is
                    // the whole of what the deleted "What you're building" card
                    // said that this list did not.
                    if isChosen {
                        Text("BUILDING")
                            .font(ForgeTheme.label(8))
                            .kerning(0.9)
                            .foregroundStyle(ForgeTheme.accent)
                            .padding(.horizontal, 6)
                            .frame(height: 17)
                            .background(
                                ForgeTheme.accent.opacity(0.14),
                                in: Capsule()
                            )
                    }

                    Spacer(minLength: 8)

                    if dimension.isMeasured {
                        if let arrow = dimension.direction.symbol {
                            Image(systemName: arrow)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        Text(dimension.direction.label)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        Text("\(dimension.score)")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(ForgeTheme.accent)
                            .frame(minWidth: 26, alignment: .trailing)
                    } else if dimension.hasActivities {
                        // Something is filed here and its first day has not
                        // come round. Waiting, not missing.
                        Text("Starting")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(ForgeTheme.separator)
                        if dimension.fraction > 0 {
                            Capsule()
                                .fill(ForgeTheme.accent.opacity(0.85))
                                .frame(width: max(3, proxy.size.width * dimension.fraction))
                        }
                    }
                }
                .frame(height: 3)

                if isInspecting {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(dimension.category.meaning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        // The arithmetic, said out loud. A score somebody cannot
                        // check is a score they have to take on trust, and this
                        // app's whole position is that it does not ask for that.
                        if dimension.isMeasured {
                            Text(workings)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(ForgeTheme.Space.row)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(
            isChosen ? "\(dimension.category.label), building" : dimension.category.label
        ))
        .accessibilityValue(Text(
            dimension.isMeasured
                ? "\(dimension.score). \(dimension.direction.label). \(dimension.category.meaning)"
                : "Nothing recorded yet. \(dimension.category.meaning)"
        ))
    }

    /// "Kept on eleven of the fourteen days it was asked for."
    private var workings: String {
        let keptDays = ForgeShape.spokenDays(dimension.kept)
        let askedDays = ForgeShape.spokenDays(dimension.asked)
        let kept = ForgeCount.spelled(keptDays)
        let asked = ForgeCount.spelled(askedDays)
        let days = askedDays == 1 ? "day" : "days"
        return "Kept on \(kept) of the \(asked) \(days) it was asked for, these four weeks."
    }
}

// MARK: - The first week

/// The first-week contract: one sentence and a bar. See `FirstWeek`.
///
/// No congratulation and no pressure — a count and a day, the register of the
/// rest of the tab. The bar is time toward the draw day in the opening week,
/// and the last seven's kept days after it.
private struct FirstWeekCard: View {
    let contract: FirstWeek

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Space.row) {
            Text(contract.sentence)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(ForgeTheme.separator)
                    if contract.progress > 0 {
                        Capsule()
                            .fill(ForgeTheme.accent.opacity(0.85))
                            .frame(width: max(4, proxy.size.width * contract.progress))
                    }
                }
            }
            .frame(height: 4)
            .animation(.smooth(duration: 0.4), value: contract.progress)

            Text("Every activity builds one of six parts of you. The shape is drawn from what you actually keep.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ForgeTheme.Space.row)
        .forgeCard(radius: ForgeTheme.Radius.card)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text("\(Int((contract.progress * 100).rounded())) per cent of the way"))
    }
}

/// A dimension's starter, restrained: one line and one button, inside its row.
/// Nothing is added until the button is pressed.
private struct StarterLine: View {
    let ritual: Ritual
    let add: () -> Void

    var body: some View {
        HStack(spacing: ForgeTheme.Space.tight) {
            Text("Smallest start: \(ritual.label)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 8)

            Button("Add", action: add)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ForgeTheme.accent)
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Add \(ritual.label) to your day"))
        }
    }
}

// MARK: - One thing you could add

/// A suggested activity, and a single tap that puts it on the day.
///
/// The row shows what the library shows anywhere else — the act, its standard,
/// and what a day of it costs — because a suggestion that hid the commitment
/// would be a suggestion somebody agreed to without reading. The `+` is the
/// whole interaction: there is no detail screen, no confirmation and no "added"
/// state, because the activity appears on the Forge tab immediately and the
/// section closes behind it.
private struct SuggestionRow: View {
    let ritual: Ritual
    let add: () -> Void

    var body: some View {
        Button(action: add) {
            HStack(spacing: ForgeTheme.Space.inner) {
                RitualGlyph(ritual: ritual, size: 16, color: .secondary)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(ritual.label)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(ritual.sub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if !ritual.tail.isEmpty {
                    Text(ritual.tail)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }

                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, ForgeTheme.accent)
            }
            .padding(ForgeTheme.Space.row)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(ritual.label). \(ritual.sub)"))
        .accessibilityHint("Adds this to your day")
    }
}

// MARK: - Changing what you are building

/// The focus editor: the same six, the same rows, the same hexagon as the
/// first run.
///
/// # Why it is the same screen and not a settings row
///
/// Because it is the same decision, and somebody making it a second time is
/// making it with more information rather than differently. Rebuilding it as a
/// list of checkmarks in Settings would have been half the work and would have
/// taught the user that the thing they picked in the first ninety seconds was a
/// preference rather than a direction.
///
/// It also closes a real hole. Until this existed, what somebody chose in
/// onboarding could never be changed — which is the same gap the identities had
/// for months, where naming one was first-run-only and every screen afterwards
/// could read them and none could write one.
///
/// **It applies as it goes.** There is no Save: the focus is one to three
/// values, every screen that reads it reads it live, and nothing is destroyed
/// by a change — the Shape is derived from the record and does not move when
/// this does. A confirmation in front of a reversible choice is a dialog whose
/// only job is to make the choice feel expensive.
private struct FocusEditor: View {
    var forge: ForgeViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    /// No cap, the same as the first run — see `FirstRunView.build` for why the
    /// three went. Nobody wants to be weaker in three of the six, and the real
    /// constraint was always the day rather than the direction.

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: ForgeTheme.Space.row) {
                    if !typeSize.isAccessibilitySize {
                        FocusHexagon(chosen: forge.focus)
                            .frame(height: 190)
                            .padding(.top, 4)
                    }

                    Text("Forge aims what it suggests at these — the activities it offers, and the moves Plan proposes. It never hides anything else.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)

                    VStack(spacing: 8) {
                        ForEach(RitualCategory.dimensions, id: \.self) { dimension in
                            DimensionChoiceRow(
                                dimension: dimension,
                                isChosen: forge.focus.contains(dimension),
                                isDimmed: false
                            ) {
                                toggle(dimension)
                            }
                        }
                    }
                }
                .padding(.horizontal, ForgeTheme.Space.gutter)
                .padding(.bottom, ForgeTheme.Space.chapter)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("What you're building")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(ForgeTheme.Radius.sheet)
    }

    /// Taking one on and taking it back are both instant and both free.
    ///
    /// **No `withAnimation`.** It had one, and an explicit transaction animates
    /// every view that reads the focus — the scroll view these rows sit in, and
    /// on the Becoming tab the card behind the sheet as well. Each of those
    /// pieces now animates the one property of itself that should move (see
    /// `DimensionChoiceRow`, `FocusHexagon` and `BecomingTabView.headline`), so
    /// the choice lands where the finger is and nothing else on the screen
    /// shifts.
    private func toggle(_ dimension: RitualCategory) {
        if forge.focus.contains(dimension) {
            ForgeHaptics.shared.tap()
            _ = forge.focus.remove(dimension)
            return
        }
        ForgeHaptics.shared.detent()
        _ = forge.focus.insert(dimension)
    }
}

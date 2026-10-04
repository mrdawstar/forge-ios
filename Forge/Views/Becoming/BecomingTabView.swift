import SwiftUI
import TipKit

/// The direction, as opposed to the record — and since 1.1, the six at a
/// glance.
///
/// # Above the fold (1.1, session S4)
///
/// The tab opens on the numbers, all of them, without a scroll on any phone
/// at the default text size: the hexagon, with each score at its vertex in its
/// dimension's colour and OVR in the middle; one line under it with the blade
/// carried and the days kept ("Quenched · 23 days"); and directly under that a
/// 3 × 2 grid of tiles, one per dimension in the hexagon's order, each with its
/// score in large digits and how far it has moved in seven days. A tile opens
/// its dimension: what feeds it, what in the week is filed under it, three
/// things to add in one tap, and which way it is going.
///
/// That grid replaces **The Six**, the list of six rows that used to sit under
/// the hexagon. Everything the rows said is on a tile or behind one, and the
/// rows were the reason the numbers sat below the fold.
///
/// # Below the fold, in this order
///
/// Next move (`DayPlanner`'s first, opened into Plan's review — nothing writes
/// unread, §5 #9) → **Build your weakest**, three one-tap adds for the weakest
/// chosen dimension → the running Arc → the weeks somebody wrote about → the
/// identities, only for somebody who has them → the focus row. The order is
/// what somebody does after reading the numbers: change something, add
/// something, look at the stretch they are in, read back, and only last
/// revisit the choice. (Share your stats was taken out for 1.1, §17.)
///
/// # It does not move under a finger (§2j.4)
///
/// Every tile reserves the line its BUILDING mark sits on, so choosing in the
/// focus editor lights a word rather than growing a tile; the focus row keeps
/// its two reserved lines; and the lists below the fold are read once per visit
/// (`Visit`), so a row somebody just added gets a check where it is instead of
/// leaving the list under their thumb.
///
/// **It stays declinable.** Somebody who never opens this tab has an app that
/// works exactly as it always did: no identity is required, no choice is
/// required, and nothing on the Forge or Blade tabs changes for want of either.
struct BecomingTabView: View {
    var forge: ForgeViewModel
    var identities: IdentityStore
    /// Every week somebody has written about. Read only — nothing on this tab
    /// answers a review, it only keeps them where they can be found.
    var reviews: ReviewStore
    /// The blade carried, for the line under the hexagon.
    var swords: SwordStore
    /// The running Arc, for its card.
    var arcs: ArcStore
    /// What Plan is given when Next move opens it — the same brief the week's
    /// own Plan reads.
    var brief: AIBrief
    var ai: ForgeAI
    /// The Arc's card goes to the Arcs tab.
    var onArcs: () -> Void = {}
    /// Ask Forge, from the bar. Nil in a build with no model to reach, and
    /// then there is no button (§17.6).
    var onAskForge: (() -> Void)? = nil

    /// Which dimension's sheet is open.
    @State private var inspecting: DimensionChoice?
    /// The move Next move opened Plan on.
    @State private var planning: DayPlanner.Move?
    /// The focus editor, which is the only route to changing what somebody said
    /// they wanted to build after the first run.
    @State private var isChoosing = false
    /// The weeks somebody has written about, if they have asked to see them.
    @State private var isReadingWeeks = false
    /// The seven questions, taken from here by an install that has never
    /// answered them.
    @State private var isAssessing = false
    /// What this visit to the tab is offering. See `Visit`.
    @State private var visit = Visit()

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Read once each time the tab comes on screen.
    ///
    /// "Build your weakest" names a dimension and offers three things in it.
    /// Read live, adding the first would re-read the weakest — it has an
    /// activity now, it may have moved — and the section could change its
    /// subject, or vanish, between two taps. So the dimension is the one the
    /// tab opened on, and what was added here keeps its row, with a check,
    /// until the next visit reads the week again.
    struct Visit: Equatable {
        var weakest: RitualCategory?
        var added: Set<String> = []
    }

    /// The largest the hexagon is drawn, so the tiles fit under it on a 6.1"
    /// phone at the default text size. Below the cap it is the screen's width.
    private static let hexagonCap: CGFloat = 292

    var body: some View {
        let six = forge.blended
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ForgeTheme.Space.section) {
                    glance(six)
                    assessmentOffer
                    nextMove
                    buildWeakest
                    arcCard
                    weeks
                    who
                    focusRow
                }
                .padding(.horizontal, ForgeTheme.Space.gutter)
                .padding(.top, ForgeTheme.Space.hair)
                .padding(.bottom, ForgeTheme.Space.chapter)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Becoming")
            .toolbar {
                if let onAskForge {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Ask Forge", systemImage: "text.bubble", action: onAskForge)
                    }
                }
            }
            .sheet(isPresented: $isChoosing) { FocusEditor(forge: forge) }
            .sheet(isPresented: $isReadingWeeks) { WeeklyReviewHistory(reviews: reviews) }
            .sheet(item: $inspecting) { choice in
                DimensionSheet(forge: forge, category: choice.category)
            }
            .sheet(item: $planning) { move in
                PlanSheet(vm: forge, brief: brief, ai: ai, opening: move)
            }
            .fullScreenCover(isPresented: $isAssessing) { AssessmentSheet(forge: forge) }
        }
        .onAppear { visit = Visit(weakest: forge.weakestDimension) }
    }

    // MARK: - 1. The six, at a glance

    /// The hexagon, the blade line and the tiles: everything above the fold.
    ///
    /// # The first week
    ///
    /// Without an assessment, until the record has a week behind it *and*
    /// enough to read, the hexagon is the first-week contract instead
    /// (`FirstWeek`): when the shape will draw itself, and how many of the seven
    /// have been kept. **With an assessment the hexagon is drawn from day one** —
    /// that is what the answers are for (`BlendedShape`) — and the first week is
    /// the progress line under it. The tiles are there from the first day either
    /// way (§2j.4): six names, each saying what it is and whether anything feeds
    /// it, are the truth on day one.
    ///
    /// Every number here is `forge.blended`: with no assessment that is the
    /// record's own `ForgeShape`, number for number.
    private func glance(_ six: BlendedShape) -> some View {
        VStack(spacing: ForgeTheme.Space.inner) {
            if six.hasAssessment || forge.firstWeek == nil {
                ForgeShapeView(shape: six)
                    .frame(maxWidth: Self.hexagonCap)
                    .frame(maxWidth: .infinity)
                if six.hasAssessment, let contract = forge.firstWeek {
                    FirstWeekLine(contract: contract)
                }
            } else if let contract = forge.firstWeek {
                FirstWeekCard(contract: contract)
            }

            Text(Self.bladeLine(blade: swords.equipped.name, daysKept: forge.daysKept))
                .font(.footnote.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(ForgeTheme.cream.opacity(0.85))
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text(Self.spokenBladeLine(blade: swords.equipped.name, daysKept: forge.daysKept)))

            tiles(six)
                .padding(.top, ForgeTheme.Space.hair)

            // The third of the first week's tips, under the thing it is about.
            // Inline rather than a popover: a popover above the tiles would
            // cover the numbers it is talking about, and would take the first
            // tap on a tile to put itself away.
            if let tip = ForgeTips.current(BecomingTip.self) {
                TipView(tip, arrowEdge: .top)
            }

            // What the numbers are made of, once. A hexagon with numbers on it
            // is a chart until somebody is told what feeds it, and the claim of
            // this whole feature is that it is fed by what you actually did.
            Text(six.hasAssessment
                 ? "Your answers started them. What you keep moves them."
                 : "Scored on the last four weeks of what you keep.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
    }

    /// "Quenched · 23 days" — the blade carried and the days kept. Digits:
    /// it is a count beside a score, not a sentence (DIRECTION_1_1 §3). The one
    /// day that has no number is the one before anything is kept, which is
    /// said rather than scored, for the reason the home screen's badge says
    /// "DAY ONE" rather than "0 DAYS".
    static func bladeLine(blade: String, daysKept: Int) -> String {
        switch daysKept {
        case ..<1: "\(blade) \u{00B7} no days kept yet"
        case 1: "\(blade) \u{00B7} 1 day"
        default: "\(blade) \u{00B7} \(daysKept) days"
        }
    }

    static func spokenBladeLine(blade: String, daysKept: Int) -> String {
        switch daysKept {
        case ..<1: "\(blade) Sword. No days kept yet."
        case 1: "\(blade) Sword. 1 day kept."
        default: "\(blade) Sword. \(daysKept) days kept."
        }
    }

    /// Six tiles, three by two — two columns once the type is too large for
    /// three to hold a number and a name.
    private func tiles(_ six: BlendedShape) -> some View {
        let tiles = StatGlance.tiles(now: six, weekAgo: forge.weekAgo, focus: forge.focus)
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: ForgeTheme.Space.tight),
            count: typeSize.isAccessibilitySize ? 2 : 3
        )
        return LazyVGrid(columns: columns, spacing: ForgeTheme.Space.tight) {
            ForEach(tiles) { tile in
                StatTileView(tile: tile) {
                    ForgeHaptics.shared.tap()
                    BecomingTip().invalidate(reason: .actionPerformed)
                    inspecting = DimensionChoice(category: tile.category)
                }
            }
        }
    }

    // MARK: - 2. Next move

    /// The first move `DayPlanner` would make, opened straight into Plan's
    /// review of it — the changes, then the week as it would be, then one
    /// button that says how many changes it is about to make (§5 #9). Nothing
    /// here writes anything.
    ///
    /// Absent when there is no move worth making, which is the good outcome
    /// and is not announced: an app that always has advice is an app whose
    /// advice means nothing. Waits for the first run, like everything Plan
    /// says.
    @ViewBuilder
    private var nextMove: some View {
        if forge.hasCompletedFirstRun,
           let move = DayPlanner.moves(forge.planFacts(wakeMinutes: brief.wakeMinutes)).first {
            VStack(alignment: .leading, spacing: ForgeTheme.Space.row) {
                SectionHeading("Next move", detail: "Worked out from your week. Nothing changes until you say so.")

                Button {
                    ForgeHaptics.shared.tap()
                    planning = move
                } label: {
                    HStack(alignment: .top, spacing: ForgeTheme.Space.inner) {
                        Image(systemName: move.kind.symbol)
                            .font(.system(size: 15, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(ForgeTheme.accent)
                            .frame(width: 30, height: 30)
                            .background(ForgeTheme.separator, in: RoundedRectangle(
                                cornerRadius: ForgeTheme.Radius.glyph - 4, style: .continuous
                            ))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(move.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(move.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)
                    }
                    .padding(ForgeTheme.Space.row)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .forgeInteractiveCard(radius: ForgeTheme.Radius.card)
                .accessibilityLabel(Text("\(move.title). \(move.reason)"))
                .accessibilityHint("Shows every change before anything moves")
            }
        }
    }

    // MARK: - 3. Build your weakest

    /// Three concrete things for the weakest dimension somebody chose, each one
    /// tap from the day (`ForgeShape.suggestions`, `BecomingOffer`).
    ///
    /// Named only when it is honest to name it (`weakestDimension`): a chosen
    /// part with nothing filed under it, or one fifteen points behind the best
    /// of the six. A level shape gets no section, because a weakest link
    /// manufactured on a balanced one is the app inventing a problem so it has
    /// something to say (§5 #3). Adding appends and never removes (§5 #7), so
    /// there is no confirmation in front of it.
    @ViewBuilder
    private var buildWeakest: some View {
        if let weakest = visit.weakest {
            let held = Set(forge.activeRitualIDs).subtracting(visit.added)
            let options = ForgeShape.suggestions(for: weakest, avoiding: held)
            if !options.isEmpty {
                VStack(alignment: .leading, spacing: ForgeTheme.Space.row) {
                    SectionHeading(
                        "Build your weakest",
                        detail: "\(weakest.label). Small, and one tap each."
                    )

                    VStack(spacing: 1) {
                        ForEach(options) { ritual in
                            SuggestionRow(ritual: ritual, isAdded: visit.added.contains(ritual.id)) {
                                ForgeHaptics.shared.ritualVerified()
                                BecomingOffer.add(ritual, to: forge)
                                visit.added.insert(ritual.id)
                            }
                        }
                    }
                    .background(ForgeTheme.separator)
                    .clipShape(ForgeTheme.cardShape(ForgeTheme.Radius.card))
                }
            }
        }
    }

    // MARK: - 4. The Arc

    /// The running Arc, in one row: where somebody is in it and whether it is
    /// on track. The rest of it — the trial, a phase's changes, leaving — is on
    /// the Arcs tab, which this opens. Absent with no Arc.
    @ViewBuilder
    private var arcCard: some View {
        if let current = arcs.current {
            let reading = arcs.reading(current)
            Button {
                ForgeHaptics.shared.tap()
                onArcs()
            } label: {
                HStack(spacing: ForgeTheme.Space.inner) {
                    ArcMark(arc: current.arc, size: 20)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(.white.opacity(0.06)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(reading.status == .upcoming
                             ? current.program.name
                             : ArcLine.text(current.program, reading))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Text(reading.status == .upcoming ? Self.startsLine(current.startDay) : reading.paceLine)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(ForgeTheme.Space.row)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .forgeInteractiveCard(radius: ForgeTheme.Radius.card)
            .accessibilityHint(Text("Opens the Arcs tab"))
        }
    }

    private static func startsLine(_ day: ForgeDay) -> String {
        let format = DateFormatter()
        format.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return "Starts \(format.string(from: day.startOfDay()))"
    }

    // MARK: - 8. What you are building

    /// What somebody said they wanted to build, as one row rather than as a
    /// section.
    ///
    /// # Why the section went
    ///
    /// "What you're building" was a card of its own under the hexagon, one row
    /// per chosen dimension, each carrying that dimension's name, its score and
    /// a sentence about its direction. Every one of those facts is on the tiles,
    /// for all six rather than for three, in the same order. It was a filter of
    /// the grid, drawn as though it were a different reading — and a screen
    /// that says the same number twice invites somebody to check whether the
    /// two agree.
    ///
    /// What was *not* redundant is the choosing: the focus aims what Forge
    /// offers and what `DayPlanner` proposes, and the first run is the only
    /// other place it can be set. So the reading is folded into the tiles — a
    /// chosen dimension is marked BUILDING there — and what is left here is
    /// the door, one row of it, stating the answer in words.
    ///
    /// # Why it is last
    ///
    /// The order the tab reads in is the order the thing actually works in:
    /// **the six you have, what to do about them, and only then how many of
    /// them you said you were building.** It is the door to changing the
    /// choice, and a choice revisited a few times a year is not a heading.
    ///
    /// Its height still does not depend on the count: two lines for the
    /// sentence and two for the note, reserved. That was the fix for the screen
    /// moving under a finger mid-choice (see `headline`).
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

    // MARK: - 7. Who you are becoming

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

    // MARK: - The assessment, for an install without one

    /// The seven questions, for an install that has never answered them —
    /// every 1.0 install. One card, first under the tiles, until it is taken;
    /// it runs the questions and the drawing and comes back here
    /// (`AssessmentSheet`).
    ///
    /// Nothing is withheld from somebody who never takes it: the tab reads the
    /// record exactly as it always has.
    @ViewBuilder
    private var assessmentOffer: some View {
        if forge.assessment == nil {
            Button {
                ForgeHaptics.shared.tap()
                isAssessing = true
            } label: {
                HStack(alignment: .top, spacing: ForgeTheme.Space.inner) {
                    Image(systemName: "hexagon")
                        .font(.system(size: 15, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(ForgeTheme.accent)
                        .frame(width: 30, height: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Take the one-minute assessment")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Text("Seven questions give each of the six a starting number. From then on, what you keep moves them.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
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
            .accessibilityHint(Text("Seven questions, about a minute"))
        }
    }

    // MARK: - 6. The weeks you wrote about

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
    /// The six as every screen shows them. With no assessment this is the
    /// record's own `ForgeShape`, number for number — see `BlendedShape`.
    let shape: BlendedShape
    /// Which dimension is being inspected, if any. Drawn with its vertex lit.
    var highlighted: RitualCategory?

    /// How much of the radius the label ring sits outside the polygon.
    private let labelInset: CGFloat = 30

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = max(0, side / 2 - labelInset)
            let centre = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

            ZStack {
                // The instrument, the six colours and the vertices are the
                // same component the first run draws its shapes with, so the
                // hexagon somebody watched being projected is this one. It
                // animates when a *value* changes, and only then — see the note
                // on the type.
                StatHexagon(
                    values: shape.dimensions.map(\.fraction),
                    highlighted: highlighted,
                    showsGlyphs: false
                ) {
                    OverallCore(overall: shape.overall, state: shape.state)
                }
                .frame(width: radius * 2 + 8, height: radius * 2 + 8)
                .position(centre)

                labels(centre: centre, radius: radius)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Your Forge Shape"))
        .accessibilityValue(Text(spoken))
    }

    /// The name and score outside each vertex, both in the dimension's colour.
    private func labels(centre: CGPoint, radius: CGFloat) -> some View {
        ForEach(Array(shape.dimensions.enumerated()), id: \.element.id) { index, dimension in
            let anchor = HexagonGeometry.point(index, radius: radius + labelInset * 0.62, centre: centre)
            VStack(spacing: 1) {
                // The name in its dimension's colour as well as the number
                // (DIRECTION_1_1 §4), a step quieter so the number leads.
                Text(dimension.category.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(
                        dimension.category.color.opacity(highlighted == dimension.category ? 1 : 0.72)
                    )
                Text(dimension.hasScore ? "\(dimension.score)" : "\u{2014}")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(dimension.score)))
                    .foregroundStyle(
                        dimension.hasScore
                            ? AnyShapeStyle(dimension.category.color)
                            : AnyShapeStyle(.tertiary)
                    )
            }
            .fixedSize()
            .position(anchor)
        }
    }

    private var spoken: String {
        let parts = shape.dimensions.map { dimension in
            guard dimension.hasScore else { return "\(dimension.category.label), nothing yet" }
            return dimension.isFromAnswers
                ? "\(dimension.category.label) \(dimension.score), from your answers"
                : "\(dimension.category.label) \(dimension.score)"
        }
        return "Overall \(shape.overall), \(shape.state.label). " + parts.joined(separator: ". ")
    }
}

// MARK: - One dimension, as a tile

/// Which dimension's sheet is open. `RitualCategory` is a filter and a filing
/// system before it is a screen, so it is not made `Identifiable` for one
/// sheet; this is.
struct DimensionChoice: Identifiable, Equatable {
    let category: RitualCategory
    var id: String { category.rawValue }
}

/// One of the six: its glyph and its number in its own colour, its name, the
/// change over seven days, and BUILDING when somebody chose it.
///
/// **The colour says which part of a person this is** (`DimensionPalette`);
/// the accent is kept for BUILDING, which is something the person did. The
/// change is in the dimension's colour when it is up and quiet otherwise —
/// never red, because a number that went down is a reading, not an alarm.
///
/// **Fixed in height.** The BUILDING line is always laid out and only shown on
/// the chosen ones, and the change sits in the glyph's row, so nothing about a
/// tile grows when the focus changes or a week's change appears (§2j.4).
struct StatTileView: View {
    let tile: GlanceTile
    let action: () -> Void

    /// The score scales with the text around it. Fixed at 30 points, it was
    /// the smallest thing on the tile at AX5 — the week's change and the name
    /// outgrew the number they are about.
    @ScaledMetric(relativeTo: .title) private var scoreSize: CGFloat = 30
    @ScaledMetric(relativeTo: .caption) private var glyphSize: CGFloat = 12
    @Environment(\.dynamicTypeSize) private var typeSize

    private var dimension: BlendedShape.Dimension { tile.dimension }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: tile.category.symbol)
                        .font(.system(size: glyphSize, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(tile.category.color)
                    Spacer(minLength: 2)
                    if let change = tile.weekChange {
                        Text(StatGlance.label(change))
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(change > 0
                                             ? AnyShapeStyle(tile.category.color)
                                             : AnyShapeStyle(.tertiary))
                    }
                }

                Text(dimension.hasScore ? "\(dimension.score)" : "\u{2014}")
                    .font(.system(size: scoreSize, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(dimension.hasScore
                                     ? AnyShapeStyle(tile.category.color)
                                     : AnyShapeStyle(.tertiary))
                    .contentTransition(.numericText(value: Double(dimension.score)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // One line at every size, shrinking further at the
                // accessibility sizes, where "Relationship" no longer fits half
                // a phone's width: wrapped, it broke mid-word and made its tile
                // taller than the five beside it.
                Text(tile.category.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(typeSize.isAccessibilitySize ? 0.5 : 0.75)

                Text("BUILDING")
                    .font(ForgeTheme.label(8))
                    .kerning(0.9)
                    .foregroundStyle(ForgeTheme.accent)
                    .opacity(tile.isBuilding ? 1 : 0)
                    .accessibilityHidden(true)
            }
            // Its own height, always. The grid proposes each tile the row's
            // height, and with two shrinkable lines in it a tile settled that
            // by shrinking its score — so at AX5 one row drew 87 smaller than
            // the 86 beside it. Only the width may make anything smaller.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            // And the row's height for the card, so two tiles side by side are
            // one size even when one name had to shrink.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .forgeInteractiveCard(radius: ForgeTheme.Radius.control)
        .animation(.forgeSelection, value: tile.isBuilding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(tile.isBuilding ? "\(tile.category.label), building" : tile.category.label))
        .accessibilityValue(Text(spokenValue))
        .accessibilityHint("Shows what feeds it")
        .accessibilityAddTraits(.isButton)
    }

    private var spokenValue: String {
        guard dimension.hasScore else { return "Nothing recorded yet" }
        var parts = ["\(dimension.score)"]
        if dimension.isFromAnswers { parts.append("from your answers") }
        if let change = tile.weekChange { parts.append(StatGlance.spoken(change)) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - One dimension, opened

/// What a tile opens: what feeds the dimension, what in the week is filed
/// under it, three things to add, and which way it is going.
///
/// # Why there is a sheet now, when there was not before
///
/// The list it replaces argued that a push to a page holding one sentence is a
/// page nobody returns to. That was right about one sentence. A dimension now
/// has four things worth saying, and the grid that put the six above the fold
/// has room for none of them — so the tile is the reading and the sheet is the
/// working, one tap apart, and nothing on it is a second copy of a number on
/// the tab.
///
/// The three suggestions are the same effort-ranked filter of the library
/// everything in Becoming uses (`ForgeShape.suggestions`), and adding one is
/// the same one tap (`BecomingOffer`): appended, never replacing anything, no
/// confirmation in front of it (§5 #7). A row added here keeps its place with a
/// check on it, so a second tap cannot land on the next one.
private struct DimensionSheet: View {
    var forge: ForgeViewModel
    let category: RitualCategory

    @State private var added: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let six = forge.blended
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ForgeTheme.Space.section) {
                    if let dimension = six.dimension(category) {
                        header(dimension, change: StatGlance.change(of: category, now: six, weekAgo: forge.weekAgo))
                        feeds(dimension)
                    }
                    activities
                    suggestions
                }
                .padding(.horizontal, ForgeTheme.Space.gutter)
                .padding(.top, ForgeTheme.Space.tight)
                .padding(.bottom, ForgeTheme.Space.chapter)
            }
            .scrollIndicators(.hidden)
            .navigationTitle(category.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(ForgeTheme.Radius.sheet)
        .presentationDragIndicator(.visible)
    }

    // MARK: The number, and which way it is going

    private func header(_ dimension: BlendedShape.Dimension, change: Int?) -> some View {
        HStack(alignment: .center, spacing: ForgeTheme.Space.row) {
            Image(systemName: category.symbol)
                .font(.system(size: 22, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(category.color)
                .frame(width: 48, height: 48)
                .background(category.color.opacity(0.14), in: RoundedRectangle(
                    cornerRadius: ForgeTheme.Radius.glyph, style: .continuous
                ))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(dimension.hasScore ? "\(dimension.score)" : "\u{2014}")
                        .font(.system(size: 40, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(dimension.hasScore ? AnyShapeStyle(category.color) : AnyShapeStyle(.tertiary))
                    if let change {
                        Text(StatGlance.label(change))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(change > 0 ? AnyShapeStyle(category.color) : AnyShapeStyle(.secondary))
                    }
                }
                Text(direction(dimension, change: change))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// Which way it is going, in words, and over what.
    private func direction(_ dimension: BlendedShape.Dimension, change: Int?) -> String {
        var line: String
        if dimension.isFromAnswers {
            line = "From your answers. The first day something here is kept, the record starts to move it."
        } else {
            switch dimension.direction {
            case .rising: line = "Rising: the last two weeks against the two before."
            case .slipping: line = "Slipping: the last two weeks against the two before."
            case .steady: line = "Steady: the last two weeks against the two before."
            case .unknown: line = "Early: two weeks of record give it a direction."
            }
        }
        if let change { line += " \(StatGlance.spoken(change).prefix(1).uppercased())\(StatGlance.spoken(change).dropFirst())." }
        if forge.focus.contains(category) { line += " You're building this." }
        return line
    }

    // MARK: What feeds it

    private func feeds(_ dimension: BlendedShape.Dimension) -> some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Space.tight) {
            SectionHeading("What feeds it", detail: category.meaning)
            VStack(alignment: .leading, spacing: 6) {
                if let workings = workings(dimension) {
                    Text(workings)
                }
                Text("Every day something filed here is kept counts, and so does a finished daily challenge aimed at it. Days, not ticks: three in one day is one day.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What the number is made of, in words — nil where there is nothing to
    /// show the working of. A score somebody cannot check is a score they have
    /// to take on trust, and this app's whole position is that it does not ask
    /// for that.
    private func workings(_ dimension: BlendedShape.Dimension) -> String? {
        let record = dimension.record
        switch dimension.source {
        case .answers:
            return "\(dimension.score) is where your answers put it."
        case .blend(let days):
            let left = max(0, BlendedShape.blendDays - days)
            let unit = left == 1 ? "day" : "days"
            return "\(keptLine(record)) Your answers still count for part of it; in \(ForgeCount.spelled(left).lowercased()) \(unit) the record alone decides."
        case .record:
            guard record.isMeasured else { return nil }
            return "\(keptLine(record).dropLast()), these four weeks."
        }
    }

    /// "Kept on eleven of the fourteen days it was asked for."
    private func keptLine(_ record: ForgeShape.Dimension) -> String {
        let keptDays = ForgeShape.spokenDays(record.kept)
        let askedDays = ForgeShape.spokenDays(record.asked)
        let kept = ForgeCount.spelled(keptDays).lowercased()
        let asked = ForgeCount.spelled(askedDays).lowercased()
        let days = askedDays == 1 ? "day" : "days"
        return "Kept on \(kept) of the \(asked) \(days) it was asked for."
    }

    // MARK: What is in the week

    @ViewBuilder
    private var activities: some View {
        let filed = forge.activeRituals.filter { $0.category == category }
        VStack(alignment: .leading, spacing: ForgeTheme.Space.tight) {
            SectionHeading("In your week")
            if filed.isEmpty {
                Text("Nothing in your week is filed under \(category.label.lowercased()) yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 1) {
                    ForEach(filed) { ritual in
                        HStack(spacing: ForgeTheme.Space.inner) {
                            RitualGlyph(ritual: ritual, size: 16, color: .secondary)
                                .frame(width: 30, height: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ritual.label)
                                    .font(.subheadline.weight(.medium))
                                Text(ritual.scheduleLabel.map { "\(ritual.repeats.label) \u{00B7} \($0)" } ?? ritual.repeats.label)
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, ForgeTheme.Space.row)
                        .padding(.vertical, 10)
                        .background(.regularMaterial)
                        .accessibilityElement(children: .combine)
                    }
                }
                .clipShape(ForgeTheme.cardShape(ForgeTheme.Radius.card))
            }
        }
    }

    // MARK: Three to add

    @ViewBuilder
    private var suggestions: some View {
        let held = Set(forge.activeRitualIDs).subtracting(added)
        let options = ForgeShape.suggestions(for: category, avoiding: held)
        if !options.isEmpty {
            VStack(alignment: .leading, spacing: ForgeTheme.Space.tight) {
                SectionHeading("Add one", detail: "Small, and one tap each.")
                VStack(spacing: 1) {
                    ForEach(options) { ritual in
                        SuggestionRow(ritual: ritual, isAdded: added.contains(ritual.id)) {
                            ForgeHaptics.shared.ritualVerified()
                            BecomingOffer.add(ritual, to: forge)
                            added.insert(ritual.id)
                        }
                    }
                }
                .background(ForgeTheme.separator)
                .clipShape(ForgeTheme.cardShape(ForgeTheme.Radius.card))
            }
        }
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

/// The first week, as a progress line under a hexagon that is already drawn —
/// what `FirstWeekCard` becomes once there are answers to draw it from.
///
/// It keeps the card's count and bar and drops its promise: "your shape draws
/// itself on Sunday" is not true of a shape that is on the screen.
private struct FirstWeekLine: View {
    let contract: FirstWeek

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeTheme.Space.tight) {
            Text(contract.progressLine)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(ForgeTheme.separator)
                    if contract.progress > 0 {
                        Capsule()
                            .fill(ForgeTheme.cream.opacity(0.85))
                            .frame(width: max(4, proxy.size.width * contract.progress))
                    }
                }
            }
            .frame(height: 3)
            .animation(.smooth(duration: 0.4), value: contract.progress)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ForgeTheme.Space.tight)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text("\(Int((contract.progress * 100).rounded())) per cent of the way"))
    }
}

// MARK: - One thing you could add

/// A suggested activity, and a single tap that puts it on the day.
///
/// The row shows what the library shows anywhere else — the act, its standard,
/// and what a day of it costs — because a suggestion that hid the commitment
/// would be a suggestion somebody agreed to without reading. The `+` is the
/// whole interaction: no detail screen and no confirmation. Once added it stays
/// where it is with a check on it, inert, so the list does not close up under a
/// finger that is about to tap again; the next visit reads the week afresh.
///
/// The dimension's glyph sits beside the `+` in its colour, the same mark the
/// tiles carry — which part of somebody this feeds, said without a word.
private struct SuggestionRow: View {
    let ritual: Ritual
    var isAdded: Bool = false
    let add: () -> Void

    var body: some View {
        Button {
            guard !isAdded else { return }
            add()
        } label: {
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

                Image(systemName: ritual.category.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ritual.category.color)
                    .accessibilityHidden(true)

                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, ForgeTheme.accent)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(ForgeTheme.Space.row)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(ritual.label). \(ritual.sub)"))
        .accessibilityValue(Text(isAdded ? "Added to today" : ""))
        .accessibilityHint(isAdded ? "" : "Adds this to today")
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

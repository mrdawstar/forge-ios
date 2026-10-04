import SwiftUI

/// Today's challenge, and the three things anybody can do about it.
///
/// It opens from the one action on the control bar and it is deliberately not a
/// card on the home screen. The home screen is a list of promises somebody has
/// already made; a second, louder thing to do sitting above that list turns the
/// day into a menu, and the list is the app. So the challenge waits behind one
/// button and otherwise stays out of the way.
///
/// # One challenge a day, and a shelf you can walk
///
/// **Forge gives you a challenge.** That is this screen, it is the same one all
/// day, everybody gets one, and it is free — accept it, skip it, finish it,
/// nothing is scored either way.
///
/// **You can look at the others.** Sixty of them, aimed at the six parts of a
/// person, ten per part, and they are one horizontal gesture away. Nothing is
/// decided by swiping: the card under the finger is what the buttons act on, and
/// taking one is an explicit press.
///
/// # What used to be here and is not
///
/// A row at the foot reading "None of these", behind it a form — a weight
/// picker, a six-way aim grid and a free-text field — and behind *that* a model
/// that 1.0 does not connect. The screen it opened said so out loud, in a
/// sentence beginning "The model that writes new ones is not connected yet",
/// which is an app apologising for a feature it is showing you. Half of its
/// controls were dead code with `true ?` still standing where a premium check
/// used to be.
///
/// It is gone, and the pager is why it can be: the form's honest job was *show
/// me a different one*, and swiping answers that better than a form ever did —
/// with no aim to choose, no weight to set, and nothing to type. What the form
/// could do that this cannot is compose a challenge that is not in the
/// catalogue, and 1.0 has nothing behind that.
struct DailyChallengeSheet: View {
    var challenges: ChallengeStore

    @Environment(\.dismiss) private var dismiss
    /// The challenge is part of the practice: somebody lapsed meets the one
    /// locked state here too, rather than buttons that would keep nothing.
    /// Unreachable from the Forge tab while locked — this is for a sheet that
    /// was already open when the answer changed.
    @Environment(ForgeStore.self) private var store: ForgeStore?
    @State private var paywallDoor: ForgeTelemetry.PaywallDoor?

    private var isLocked: Bool {
        store.map { PremiumGate.isLocked(.dailyChallenge, for: $0.access) } ?? false
    }

    /// Which card is under the finger. Nil until the pager reports one, which
    /// is why every read of it falls back to today's.
    @State private var visible: Card.ID?

    /// The pager's height. See `pager` — it is fixed on purpose.
    @ScaledMetric(relativeTo: .title2) private var pagerHeight: CGFloat = 244

    /// The height the sheet opens at: the mark, the card, the rail and the two
    /// buttons under it, whole, above the home indicator. Measured rather than
    /// a fixed half screen — at `.medium` the buttons sat below the sheet's
    /// edge on every iPhone (release polish, §17). Nil until the first layout.
    @State private var openHeight: CGFloat?
    @State private var detent: PresentationDetent = .medium
    /// What sits above the content and below it — the navigation bar, and the
    /// home indicator — read off the scroll view.
    @State private var chromeTop: CGFloat = 0
    /// Where the buttons end, in the scroll's content.
    @State private var contentBottom: CGFloat = 0

    /// Room left under the buttons, so the primary is never against the edge.
    private static let belowButtons: CGFloat = ForgeTheme.Space.section

    /// How many rounds of the six have been drawn.
    ///
    /// One is what the sheet opens with; another is appended as the finger
    /// approaches the end. It never shrinks — a deck that got shorter behind
    /// somebody would move the card they are looking at.
    @State private var pages = 1

    private var today: ChallengeDay { challenges.today }
    private var challenge: DailyChallenge { today.challenge }

    /// One card in the browse.
    ///
    /// Its identity is **where it is**, not what it holds: sixty challenges over
    /// an unbounded scroll means the same challenge can legitimately come round
    /// again, and two views sharing an id in a `ForEach` collapse into one and
    /// take the scroll position with them. See `ChallengeCatalog.browse`, which
    /// deliberately does not mangle the challenge's own id to paper over this.
    struct Card: Identifiable {
        let id: String
        let challenge: DailyChallenge
        /// Whether this is the challenge the day actually holds.
        ///
        /// **Not "is it in the first round".** It was `page == 0 && id matches`,
        /// which is true of the slot today's challenge is drawn into and false
        /// of the identical card further down the deck — so taking a card from
        /// page two changed the store and left the screen still saying ANOTHER
        /// FOR TODAY, still offering "Take this one" for a challenge the day
        /// already held. The card under the finger is the one the buttons act
        /// on, so what it says about itself has to be a fact about the day
        /// rather than about where in the shelf it happens to sit.
        let isToday: Bool
    }

    /// The browse, as far as it has been drawn.
    ///
    /// Derived on read, like everything else here — see `ChallengeStore`. The
    /// first round holds today's own challenge in its dimension's slot, which is
    /// what makes the slots fixed: taking a card changes what the card in *that*
    /// slot says about itself and moves nothing.
    private var cards: [Card] {
        (0..<pages).flatMap { page in
            challenges.browsable(page: page).enumerated().map { slot, drawn in
                Card(
                    id: "\(page).\(slot)",
                    challenge: drawn,
                    isToday: drawn.id == challenge.id
                )
            }
        }
    }

    /// The card being looked at. Everything below the pager acts on this one,
    /// so there is never a moment where the buttons belong to a challenge that
    /// is not on screen.
    private var showing: Card {
        cards.first { $0.id == visible }
            ?? cards.first { $0.isToday }
            ?? Card(id: "today", challenge: challenge, isToday: true)
    }

    private var isShowingToday: Bool { showing.isToday }

    /// Where today's own card sits in the first round, so the sheet can open on
    /// it however far along the six it falls.
    private var todayCardID: Card.ID? { cards.first { $0.isToday }?.id }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    mark
                    if isLocked {
                        ProLockedState { paywallDoor = .locked }
                            .padding(.horizontal, ForgeTheme.Space.gutter)
                            .onGeometryChange(for: CGFloat.self) {
                                $0.frame(in: .named(Self.content)).maxY
                            } action: {
                                contentBottom = $0
                                refit()
                            }
                    } else {
                        pager
                        rail
                        actions
                        footnote
                    }
                }
                .padding(.bottom, 36)
                .coordinateSpace(.named(Self.content))
            }
            .scrollIndicators(.hidden)
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: {
                chromeTop = $0
                refit()
            }
            .navigationTitle("Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .onAppear { visible = todayCardID }
            // Drawn ahead of the finger rather than behind it. Appending when
            // the last card is *reached* means the scroll hits a wall and the
            // new page arrives after the bounce; two rounds of headroom means
            // the deck is always longer than anybody has scrolled and the pan
            // never stops.
            .onChange(of: visible) { _, id in
                guard let id, let index = cards.firstIndex(where: { $0.id == id }) else { return }
                if index >= cards.count - 6 { pages += 1 }
            }
        }
        // Opens at the height of one card and its two buttons, with the screen
        // behind still visible above it (`openHeight`). The pager scrolls, and
        // a drag takes it to full height for anybody browsing deeper into the
        // shelf. A text size too large for that opens it at full height.
        .presentationDetents(openHeight.map { [.height($0), .large] } ?? [.medium, .large], selection: $detent)
        .presentationCornerRadius(ForgeTheme.Radius.sheet)
        .presentationDragIndicator(.visible)
        .paywall($paywallDoor)
    }

    /// The scroll's content, for measuring where the buttons end.
    private static let content = "challenge.content"

    /// Sizes the opening detent to end `belowButtons` under `contentBottom`,
    /// the bottom of the buttons. The system adds the home indicator's inset
    /// to a `.height` detent itself. Whole points only, so a fraction of a
    /// point never resizes the sheet; a sheet somebody dragged to full height
    /// stays there.
    private func refit() {
        guard contentBottom > 0 else { return }
        let height = (chromeTop + contentBottom + Self.belowButtons).rounded(.up)
        guard height != openHeight else { return }
        openHeight = height
        if detent != .large { detent = .height(height) }
    }

    // MARK: - The challenge

    /// The one mark that does not swipe. It belongs to the day rather than to
    /// any one card, and moving it with the pager would make a shelf of sixty
    /// look like sixty challenges the user has been given.
    private var mark: some View {
        ChallengeMark(size: 32, isFilled: today.state == .completed)
            .foregroundStyle(
                today.state == .completed
                    ? AnyShapeStyle(ForgeTheme.accent)
                    : AnyShapeStyle(.primary.opacity(0.75))
            )
            .padding(.top, 16)
            .padding(.bottom, 18)
    }

    /// The shelf, laid out by dimension and effectively without an end.
    ///
    /// # Why a pager rather than a list
    ///
    /// The commonest want on this screen is *today's does not fit the day I am
    /// having, show me the others*. A person in that position is browsing, and
    /// browsing behind a form is not browsing.
    ///
    /// So the alternatives are one gesture away and they are laid out **by
    /// dimension** — the same six the Shape scores, in the same order, round
    /// after round. That is what stops it being a shuffle button: swiping is not
    /// asking for another roll of the dice, it is walking the six parts of
    /// yourself and seeing what each one would ask for today.
    ///
    /// # Why it does not end
    ///
    /// It ended at six, and six is one round of a shelf sixty deep. Somebody who
    /// had read all six and wanted a seventh had nowhere to go but the form. A
    /// round is appended as the finger nears the last card, so the pan is never
    /// interrupted and the deck is always longer than the scroll.
    ///
    /// `LazyHStack` is what makes that free: only the cards near the viewport
    /// are ever built, so the tenth round costs the same as the first.
    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(cards) { card in
                    ChallengeCard(
                        challenge: card.challenge,
                        isToday: card.isToday,
                        isCompleted: card.isToday && today.state == .completed
                    )
                    .padding(.horizontal, ForgeTheme.Space.gutter)
                    .containerRelativeFrame(.horizontal)
                    .id(card.id)
                }
            }
            .scrollTargetLayout()
        }
        // **A fixed height, and it is what makes the lazy stack safe.**
        //
        // A `LazyHStack` builds only what is near the viewport, and an `HStack`
        // is as tall as its tallest child — so without this the deck grew every
        // time a longer card was built, and the rail and the buttons under it
        // stepped down while the finger was mid-swipe. Sizing to content is
        // exactly what a pager must not do: every card is the same size by
        // definition, because they are the same card showing different words.
        //
        // Scaled with Dynamic Type and capped, so large text gets the room it
        // needs and AX5 does not ask for a card taller than the sheet.
        .frame(height: min(pagerHeight, 400))
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $visible, anchor: .center)
        .scrollIndicators(.hidden)
        // Never, rather than `.basedOnSize`. The deck grows under the finger, so
        // a bounce at the end is a bounce against a wall that is about to move —
        // and the one place it would still fire is the left edge, where it reads
        // as the shelf refusing rather than as the shelf beginning.
        .scrollBounceBehavior(.always, axes: .horizontal)
    }

    /// Which part of a person the card in front of you is aimed at.
    ///
    /// **Six marks, and they are the six** — not a page indicator. The deck has
    /// no length any more, so a row of dots counting cards would either grow
    /// forever or lie; and the useful fact about where you are was never the
    /// ordinal, it was which part of yourself this one is about. Every round
    /// walks the six in the same order, so the lit mark moves one step per swipe
    /// and comes back round, which is exactly what the shelf does.
    private var rail: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(ChallengeFocus.allCases) { focus in
                    let lit = focus == showing.challenge.focus
                    // Lit in the aim's own colour since 1.1: the rail is the
                    // six, and the six have colours (DIRECTION_1_1 §4).
                    Capsule()
                        .fill(lit ? AnyShapeStyle(focus.category.color) : AnyShapeStyle(.tertiary))
                        .frame(width: lit ? 16 : 5, height: 5)
                }
            }
            .animation(.forgeSelection, value: showing.challenge.focus)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Aimed at \(showing.challenge.focus.label)"))

            // Only while today's own card is up. An instruction that stays on
            // screen after it has been followed is an instruction nobody reads
            // the second time and everybody reads past every time.
            //
            // Hidden rather than removed: taking the line out of the layout
            // moved the buttons under it up by its height, so the primary
            // action jumped every time somebody swiped.
            //
            // The line is shared: on another card it says what taking that one
            // does, so the buttons under it are the same two on every card and
            // the sheet's measured height (`openHeight`) never changes under a
            // swipe.
            ZStack {
                Text("Swipe. There is one for every part of you.")
                    .opacity(isShowingToday ? 1 : 0)
                    .accessibilityHidden(!isShowingToday)
                Text("Taking it replaces today's. You still get one a day.")
                    .opacity(isShowingToday ? 0 : 1)
                    .accessibilityHidden(isShowingToday)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, ForgeTheme.Space.gutter)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .animation(.easeOut(duration: 0.2), value: isShowingToday)
    }

    // MARK: - The three answers

    /// What can be done, and what has been done, in one place.
    ///
    /// The state is never a badge beside a fixed row of buttons. Each state
    /// offers only the moves that exist in it, which is why there is no disabled
    /// control anywhere on this screen — a greyed-out "Complete" on a skipped
    /// challenge would be the app showing somebody a door and then holding it
    /// shut.
    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            if isShowingToday {
                todayActions
            } else {
                // The card under the finger is not the day's. There is exactly
                // one thing to do with it and one way back, and neither of them
                // touches the challenge until it is pressed.
                // The card stays exactly where it is and becomes today's —
                // the slots are fixed, so nothing moves under the finger that
                // pressed this. See `ChallengeCatalog.browse`.
                primary("Take this one") {
                    ForgeHaptics.shared.detent()
                    withAnimation(.forgeRow) { challenges.take(showing.challenge) }
                }
                secondary("Keep today's") {
                    ForgeHaptics.shared.tap()
                    withAnimation(.forgeRow) { visible = todayCardID }
                }
            }
        }
        .animation(.forgeRow, value: today.state)
        .animation(.forgeRow, value: isShowingToday)
        .padding(.horizontal, ForgeTheme.Space.gutter)
        // Where the sheet opens to: just under these, whatever the phone.
        .onGeometryChange(for: CGFloat.self) {
            $0.frame(in: .named(Self.content)).maxY
        } action: {
            contentBottom = $0
            refit()
        }
        .padding(.bottom, 8)
    }

    /// The one sentence the screen closes on, and the whole of what used to be a
    /// section. It said "nothing here is counted" until 1.1 made a finished
    /// challenge count (DIRECTION_1_1 §7): done, it is a kept day for its stat;
    /// skipped, it is still nothing.
    private var footnote: some View {
        Text("One challenge a day. Done, it counts toward its stat. Skipping costs nothing.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, ForgeTheme.Space.gutter)
            .padding(.top, 18)
    }

    @ViewBuilder
    private var todayActions: some View {
        switch today.state {
        case .offered:
            primary("Accept") { act { challenges.accept() } }
            secondary("Not today") { act { challenges.skip() } }

        case .accepted:
            primary("Mark it done") {
                ForgeHaptics.shared.ritualVerified()
                withAnimation(.forgeRow) { challenges.complete() }
            }
            secondary("Not today") { act { challenges.skip() } }

        case .completed:
            settled(
                "Done.",
                detail: "\(completedLine) It counts toward \(challenge.focus.label) today.",
                symbol: "checkmark",
                tint: ForgeTheme.accent
            )
            // The challenge's own closing beat. The blade has one — see
            // `DaySummaryView` — and until now the one thing in Forge
            // nobody has to do had nothing to say when it was finished.
            //
            // The same wall, the same theme, the same day: somebody who
            // finishes the challenge and then earns the day is not shown
            // the same line twice, because the day's is drawn from what the
            // day was about and this one from `.toughness`.
            earnedQuote
            // The way back. An activity is undone by tapping its row, and
            // this had no equivalent — one accidental press and the day was
            // wrong until four in the morning.
            secondary("I haven't done it yet") { act { challenges.undoCompletion() } }

        case .skipped:
            settled(
                "Skipped today.",
                detail: "It costs nothing. The chain does not know about this.",
                symbol: "moon",
                tint: .secondary
            )
            secondary("Take it back") { act { challenges.accept() } }
        }
    }

    private var completedLine: String {
        guard let at = today.completedAt else { return "One more than yesterday." }
        return "Finished at \(Self.clock.string(from: at))."
    }

    /// Somebody else's words, once the challenge is behind them.
    ///
    /// Quiet on purpose. It sits under the card rather than inside it, has no
    /// surface of its own, and never animates — the loud version of this moment
    /// belongs to the blade, and a challenge that celebrated itself as hard as
    /// the day would flatten the difference between them.
    private var earnedQuote: some View {
        let quote = ForgeQuotes.quote(for: .challenge(challenge.focus), on: today.day)
        return VStack(spacing: 8) {
            Text(quote.text)
                .font(.system(size: 15, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(quote.source.uppercased())
                .font(ForgeTheme.label(9))
                .kerning(1.3)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(quote.text) — \(quote.source)"))
    }

    /// The cream capsule every other primary action in Forge wears — see
    /// `ForgeButton`. This was the system's own prominent glass, which tints
    /// blue, and made the one sheet in the app with a different idea of what
    /// "the button to press" looks like.
    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        ForgeButton(title: title, action: action)
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: ForgeTheme.Radius.control))
        .tint(.secondary)
    }

    /// A state with nothing left to press, said as a sentence rather than as a
    /// disabled button.
    private func settled(
        _ title: String,
        detail: String,
        symbol: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeCard(radius: ForgeTheme.Radius.control)
        .accessibilityElement(children: .combine)
    }

    private func act(_ change: () -> Void) {
        ForgeHaptics.shared.tap()
        withAnimation(.forgeRow) { change() }
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
}

// MARK: - One card

/// One challenge, drawn the same whichever of the six it is.
///
/// The whole screen is one thing to do, so nothing on the card competes with
/// the title: a line saying where it came from, two small tags, the act, and
/// the sentence that says what doing it looks like.
///
/// **The dimension tag is the only coloured thing on it**, and only on the card
/// somebody is actually being offered. Six cards each glowing would turn a
/// browser into a carousel of adverts. Since 1.1 it glows in its dimension's
/// own colour (`DimensionPalette`) rather than the accent: the tag says which
/// part of a person the challenge is aimed at, and that is what the six colours
/// mean everywhere else — the accent's one job is to say which part of the
/// interface is answering you.
private struct ChallengeCard: View {
    let challenge: DailyChallenge
    /// Whether this is the challenge the day actually holds.
    let isToday: Bool
    let isCompleted: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(kicker)
                .font(ForgeTheme.overline)
                .kerning(ForgeTheme.overlineKerning)
                .foregroundStyle(isToday ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                .padding(.bottom, 14)

            HStack(spacing: 8) {
                tag(
                    challenge.focus.label.uppercased(),
                    symbol: challenge.focus.symbol,
                    lit: isToday,
                    tint: challenge.focus.category.color
                )
                tag(challenge.difficulty.label.uppercased())
            }
            .padding(.bottom, 16)

            // Bounded, because the card is a fixed height — see
            // `DailyChallengeSheet.pager`. The catalogue is written to fit
            // (short enough to say out loud), so these limits are a floor under
            // a bad string rather than something anybody meets.
            Text(challenge.title)
                .font(.system(size: 27, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)

            Text(challenge.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.horizontal, 6)


            // Why this one, when the day is why. It is the difference between a
            // challenge and a fortune cookie: the app read the day somebody had
            // already planned and aimed at it, and saying so out loud is what
            // turns "here is a challenge" into "here is *your* challenge".
            //
            // Absent when the day said nothing — which is most first weeks — and
            // that silence is the point. A line claiming the day was read on a
            // day it was not would cost more than it buys.
            //
            // **Which stat it feeds, on every card**, in that stat's colour: a
            // finished challenge is a kept day for its dimension in the Shape
            // (DIRECTION_1_1 §7), so "Counts toward Discipline" is true of
            // every card and said on every one. It took the place of the
            // dimension's meaning on the cards that are not today's — the tag
            // above already names the dimension, and what it is *for* now is
            // the more useful half — and it joins today's reason on one line,
            // so the card is no taller than it was (`pager` is a fixed height).
            caption
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .opacity(isToday ? 1 : 0.94)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(kicker). \(challenge.focus.label), \(challenge.difficulty.label). \(challenge.title). \(challenge.detail) \(ChallengeStore.countsToward(challenge))."))
    }

    /// "Chosen for a day of deep work. Counts toward Ambition." — the reason
    /// where there is one, and the stat always, in its colour.
    private var caption: Text {
        let counts = Text(ChallengeStore.countsToward(challenge) + ".")
            .foregroundStyle(challenge.focus.category.color.opacity(isToday ? 1 : 0.8))
        guard let reason = challenge.reason else { return counts }
        return Text("Chosen for \(reason). ").foregroundStyle(.tertiary) + counts
    }

    /// Where the card came from, said out loud — the question this screen exists
    /// to keep unambiguous.
    private var kicker: String {
        if !isToday { return "ANOTHER FOR TODAY" }
        if isCompleted { return "TODAY'S CHALLENGE \u{00B7} DONE" }
        return challenge.isPersonal ? "MADE FOR YOU" : "TODAY'S CHALLENGE"
    }

    /// The dimension's glyph is in its colour on every card — it says which
    /// part of a person this is, which is true of every card — while the word
    /// beside it lights only on today's, so the browser still has one card
    /// glowing rather than six.
    private func tag(
        _ text: String, symbol: String? = nil, lit: Bool = false, tint: Color? = nil
    ) -> some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint.map { AnyShapeStyle($0.opacity(lit ? 1 : 0.75)) }
                                     ?? AnyShapeStyle(.secondary))
            }
            Text(text)
                .font(ForgeTheme.label(9.5))
                .kerning(1.3)
        }
        .foregroundStyle(lit ? AnyShapeStyle(tint ?? ForgeTheme.accent) : AnyShapeStyle(.secondary))
        .padding(.horizontal, 9)
        .frame(height: 24)
        .glassEffect(.regular, in: .capsule)
        .accessibilityHidden(true)
    }
}


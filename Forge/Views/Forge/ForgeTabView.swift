import SwiftUI
import TipKit

struct ForgeTabView: View {
    @Bindable var vm: ForgeViewModel
    var swords: SwordStore
    /// Today's challenge. Everybody has one; see `ChallengeStore`.
    var challenges: ChallengeStore
    /// The Arc being run, for the one line above the day. See `ArcLine`.
    var arcs: ArcStore
    /// What Forge would tell a model about this person, built by the root — see
    /// `AIBrief`.
    var brief: AIBrief
    var ai: ForgeAI
    /// The line goes to the Arcs tab.
    var onArcs: () -> Void = {}

    @State private var isExpanded = false
    @State private var dragOffset: CGFloat = 0
    @State private var engine = SwordEngine()

    /// The line today earned, resolved here because this is the one screen that
    /// holds both the day and today's challenge.
    ///
    /// A day that also carried a finished challenge earned a different sentence,
    /// and it is the *same* expression the summary overlay used an hour earlier
    /// — see `ForgeViewModel.reflection(challengeFocus:)`. Two readings of what
    /// today earned would mean the line somebody half-read over the sword and
    /// the one they find on the panel are different quotations.
    private var reflection: AttributedQuote? {
        vm.reflection(
            challengeFocus: challenges.today.state == .completed
                ? challenges.today.challenge.focus
                : nil
        )
    }

    /// Which reading the panel is showing. In memory only: which of the two
    /// somebody was last looking at is a fact about a glance, not a preference,
    /// and a home screen that opens on last week is a home screen that has
    /// forgotten what it is for.
    @State private var mode: PanelMode = .today

    @State private var showChallenge = false
    /// What has been bought, for the one locked state. Optional so a preview
    /// without a store draws the day — unanswered StoreKit locks nothing.
    @Environment(ForgeStore.self) private var store: ForgeStore?
    @State private var paywallDoor: ForgeTelemetry.PaywallDoor?

    /// Whether new days are locked here and now.
    ///
    /// The day's controls give way to one calm state — "New days need Forge
    /// Pro." — for somebody lapsed or never subscribed, after the first run.
    /// The sword stays: it is the record, and the record is never locked.
    ///
    /// **Never over the day.** Not while a summary or a celebration is up, and
    /// not mid-pull; it waits for the moment to end. `isDragging` rather than
    /// the pull's position, which changes every frame and would redraw this
    /// whole tab with it.
    private var isLocked: Bool {
        guard let store else { return false }
        return PremiumGate.showsLockedState(
            for: store.access,
            hasCompletedFirstRun: vm.hasCompletedFirstRun,
            isMomentOnScreen: vm.summary != nil
                || swords.pendingUnlock != nil
                || engine.isDragging
                || vm.honorRitualID != nil
        )
    }
    /// The copy sheet, raised from an empty day. The planner has its own; this
    /// is the same sheet, reached from the one screen where filling today from a
    /// day somebody has already thought about is the fastest thing they can do.
    @State private var showCopyDay = false

    /// How much room the screen actually has, so the panel's tallest detent can
    /// be capped on a small phone rather than run off the top of it.
    @State private var available: CGFloat = 0

    /// Where the day list is parked, so the panel can send it home when it
    /// collapses — a collapsed list does not scroll, and one left halfway down
    /// would strand three arbitrary rows on screen.
    @State private var listPosition = ScrollPosition(edge: .top)

    /// The activity opened from the day list. See `RitualRowView` for why the
    /// row has two targets rather than one.
    @State private var editing: Ritual?

    /// Which row is swiped open, if any. Held here rather than inside the rows
    /// because the rule is about the list: opening one closes the others, the
    /// way it does in every system list.
    @State private var swipedID: String?

    /// Where each row of the day list sits in the panel, and where the one
    /// just tapped was when it was tapped — so the chip rises from the row that
    /// was kept even though that row has already started for the foot of the
    /// list. See `StatChip`.
    @State private var rowFrames: [String: CGRect] = [:]
    @State private var tappedFrames: [String: CGRect] = [:]
    /// The chip on screen: what the completion moved, and where it starts.
    @State private var chip: ChipPlacement?

    private struct ChipPlacement: Equatable {
        let gain: StatGain
        let frame: CGRect
    }

    private static let panelSpace = "forge.panel"

    @Environment(\.dynamicTypeSize) private var typeSize
    /// Only for the accent a finished part takes. The panel is otherwise
    /// untouched by which world is on, and should stay that way.

    /// Sized so three rows fit whole — including the third one's separator —
    /// rather than guessed.
    ///
    /// The sheet's fixed chrome is 69pt (24 grab handle, 45 header) and a row at
    /// the default text size is 65.4pt: 26 of padding around a 39.4pt
    /// label/subtitle stack. Three rows is 196.2, whose trailing separator lands
    /// clear of the 20pt fade at the foot of the list, leaving the fourth row to
    /// peek through it.
    ///
    /// These are the numbers the panel was measured with, restored. They were
    /// briefly carrying a control bar inside them, which meant every derivation
    /// above described a list 44pt taller than the one on screen — see
    /// `ForgeControlBar` for why the bar is a separate surface now.
    private let sheetMinH: CGFloat = 295
    private let baseMaxH: CGFloat = 579
    /// Freed detents (§6.1): the panel shrinks once the blade is out, and grows
    /// again only to hold the review list.
    /// The freed panel's resting height.
    ///
    /// Sized against its actual contents rather than guessed: the "Free." header
    /// (34), a quotation bounded to three lines (~66), its source line (14), the
    /// gaps between them (~24), the TODAY card (46) and the panel's own vertical
    /// padding (18). That is 202, and the 30 over it is the margin Dynamic Type
    /// eats first.
    ///
    /// It was 213, which was measured against a *one-line* quotation — so every
    /// reflection longer than that pushed the TODAY card out through the bottom
    /// of the panel, where it was clipped. Bounding the quotation is the other
    /// half of that fix; see `DailyLine`.
    private let sheetFreeH: CGFloat = 232
    /// What the evening's one row costs: a 46pt card and the 10 under it.
    private let sheetTomorrowH: CGFloat = 56
    /// The control bar and the air under it, which the panel's ceiling has to
    /// account for even though the bar is not part of the panel.
    private let controlBarH: CGFloat = 44 + 12
    /// The least sword worth keeping on screen.
    ///
    /// The stone and the blade are what the home screen is *of*. A panel that
    /// grows until they are a strip along the top has quietly turned Forge into
    /// a list app with a wallpaper, so the ceiling gives way before the scene
    /// does. On the phones this was designed on the cap never binds and the
    /// panel is exactly the 579 it always was; on a small one it binds instead
    /// of the panel running off the top.
    private let sceneFloor: CGFloat = 210

    private var sheetMaxH: CGFloat {
        guard available > 0 else { return baseMaxH }
        let arcLine = showsArcLine ? arcLineH : 0
        return max(sheetMinH, min(baseMaxH, available - controlBarH - arcLine - sceneFloor))
    }

    // MARK: - The Arc

    /// The Arc's line and the 8 under it, which come out of the scene's share
    /// rather than the panel's — the same accounting the control bar gets.
    private let arcLineH: CGFloat = 28 + 8

    /// The running Arc and how it stands, or nil.
    private var arcStanding: (program: ArcProgram, reading: ArcReading)? {
        guard let current = arcs.current else { return nil }
        let reading = arcs.reading(current)
        guard reading.isRunning else { return nil }
        return (current.program, reading)
    }

    /// One line, and only while an Arc runs and the day's controls are up —
    /// never over the first run's own pull, which has one thing to say.
    private var showsArcLine: Bool {
        vm.hasCompletedFirstRun && !isLocked && arcStanding != nil
    }

    /// What the panel is currently showing.
    ///
    /// One decision in one place, because four separate properties were each
    /// answering half of it — `canExpand`, `showsHeader`, `sheetHeight` and the
    /// `switch` in `sheet` all re-derived "which of the five states is this"
    /// from `isOut` / `allDone` / `isDayEmpty`, and they had to agree. They did
    /// not, once: a day that was **banked but not finished** — the first day
    /// anybody has, and any day where something is un-ticked after the pull —
    /// fell into the free state, which is a screen that says the day is over.
    ///
    /// **That is the bug the first run made unavoidable.** The first pull is
    /// granted with one of three done, so the very first thing a new user saw
    /// after the most important moment in the product was "Free.", a quotation
    /// and a closed list — with two activities they had just chosen sitting
    /// behind a disclosure that could only untick them. The blade being out is
    /// true and should stay true; it does not mean today is finished, and the
    /// panel now says so by simply carrying on showing the list.
    private enum PanelContent { case week, empty, list, loose, free }

    private var content: PanelContent {
        if mode == .week { return .week }
        // An earned day with nothing left in it is still an earned day. Asked
        // before `isDayEmpty` so somebody who clears their list after pulling is
        // not handed a screen offering to plan a day they have already kept.
        // **`isListFinished`, not `allDone`.** The first run's grace makes the
        // blade loose with the list unfinished, so `allDone` is true here for a
        // day that plainly is not — and this line is the one that decides
        // whether somebody is shown a closing screen. It was the free state's
        // own bug, reintroduced through the back door: for the length of the
        // closing beat an earned-but-unfinished first day resolved to `.free`
        // again. The pull prompt below keeps reading `allDone`, because being
        // *loose* is exactly what the grace is for.
        if vm.isOut && (vm.isDayEmpty || vm.isListFinished) { return .free }
        if vm.isDayEmpty { return .empty }
        if vm.allDone { return .loose }
        return .list
    }

    /// The list can only grow while there is a list to grow: the pull prompt and
    /// the free state are fixed-height readings, and an empty day has nothing to
    /// scroll. The week always has a list.
    private var canExpand: Bool {
        content == .week || content == .list
    }

    /// Whether the day header — and with it the one button that opens the
    /// editor — is on the panel.
    ///
    /// This used to be `canExpand`, which tied "can this list get taller" to
    /// "can this day be changed" and made the second one disappear with the
    /// first. Finishing the day took the `+` away, and from that moment the
    /// only route to adding or editing anything was the evening's Tomorrow
    /// card — so a day finished at nine in the morning could be *looked at* and
    /// nothing else, on the one screen the app is about.
    ///
    /// The free state keeps its own door instead of this one: `FreeStateView`
    /// already draws a "TODAY" heading, and a second heading above it would be
    /// the same word twice.
    ///
    /// An empty day keeps its own counsel too. "0 OF 0" over a screen that has
    /// just said the day is open is the app contradicting itself in the space of
    /// two lines, and the empty state carries its own way in.
    private var showsHeader: Bool { content == .list || content == .loose }

    private var sheetHeight: CGFloat {
        switch content {
        case .week, .list:
            let base = isExpanded ? sheetMaxH : sheetMinH
            return min(max(base + dragOffset, sheetMinH), sheetMaxH)
        case .free:
            let base = vm.reviewOpen ? sheetFreeReviewH : sheetFreeH
            return min(sheetMaxH, base + (vm.isEveningOpen ? sheetTomorrowH : 0))
        case .empty, .loose:
            return sheetMinH
        }
    }

    /// How tall the freed panel is with the day's review open.
    ///
    /// **Derived from the number of activities**, which it was not: it was a
    /// flat 421, measured against a day of five. Somebody keeping nine had four
    /// rows rendered past the bottom edge of the glass — clipped, untappable,
    /// and with no gesture that would reach them, because the freed panel does
    /// not resize and its contents did not scroll.
    ///
    /// Capped at the panel's own ceiling, which is the other half of the fix:
    /// past about a dozen activities the honest answer is a shorter panel with a
    /// scrolling list in it, not a panel that eats the sword. `FreeStateView`
    /// scrolls, so the cap costs nothing.
    private var sheetFreeReviewH: CGFloat {
        // 44 for the disclosure's own explanation line, 44 a row.
        sheetFreeH + 44 + CGFloat(vm.todayRituals.count) * 44
    }

    private var sheetSpring: Animation { .sheetPanel }

    /// How Today and Week trade places.
    ///
    /// A plain `.opacity` transition crossfades, which means both readings are
    /// on screen at once for the whole of it — and because the panel is also
    /// changing height at that moment (Week opens tall, Today opens short), the
    /// outgoing content is being stretched or squashed while it fades. What that
    /// looks like is the previous screen bleeding through and lingering, which is
    /// exactly what it is.
    ///
    /// Asymmetric fixes it by making the two halves consecutive rather than
    /// simultaneous: the outgoing reading is gone in 100ms, and the incoming one
    /// does not begin until it has left. Nothing is ever composited over
    /// anything else. The whole swap is 280ms, which is quicker than the
    /// crossfade it replaces despite being sequential — the old one only felt
    /// long because it spent its middle showing two screens at once.
    private static let modeSwap: AnyTransition = .asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.18).delay(0.10)),
        removal: .opacity.animation(.easeIn(duration: 0.10))
    )

    /// What a tap outside the panel would put away.
    ///
    /// A native sheet dims what it covers and takes a tap on the dimmed area as
    /// "close". The panel has two things that open inside it, and both behave
    /// that way now — the review used to be the exception, closable only by
    /// finding its own header again.
    private enum Backdrop {
        case list, review

        var dismissLabel: String {
            switch self {
            case .list: "Collapse the list"
            case .review: "Close the review"
            }
        }
    }

    private var backdrop: Backdrop? {
        // Nothing is open behind the locked state, so nothing dims.
        if isLocked { return nil }
        if mode == .today, vm.isOut, vm.reviewOpen { return .review }
        if isExpanded && canExpand { return .list }
        return nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Sword scene background
            SwordSceneView(vm: vm, engine: engine, swords: swords)

            // A native sheet dims what it covers, and that dimmed area doubles
            // as the target for putting it away again.
            if let backdrop {
                Color.black.opacity(0.24)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { dismiss(backdrop) }
                    .accessibilityLabel(backdrop.dismissLabel)
                    .accessibilityAddTraits(.isButton)
            }

            // The control layer and the panel, in that order and with air
            // between them. The gap is the whole reason the bar reads as a
            // separate thing — see `ForgeControlBar`.
            VStack(spacing: 12) {
                if isLocked {
                    ProLockedState { paywallDoor = .locked }
                        .glassEffect(.regular, in: .rect(cornerRadius: 32))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                } else {
                    // The second tip, on the scene, pointing up at the blade
                    // once it is loose. Inline for the reason the first is: a
                    // popover would eat the first drag to put itself away, and
                    // the drag is what it is asking for. It goes the moment a
                    // hand is on the grip (`ForgeTips.isQuiet`), and for good
                    // once the blade is out.
                    if mode == .today, content == .loose, let tip = ForgeTips.current(PullTip.self) {
                        TipView(tip, arrowEdge: .top)
                            .padding(.horizontal, 20)
                            .transition(.opacity)
                    }

                    // "Winter Arc · Day 12 of 90 · Trial 3 of 7", above the
                    // controls and the day it is made of. The challenge
                    // capsule stays exactly where it was.
                    if showsArcLine, let arc = arcStanding {
                        ArcLine(program: arc.program, reading: arc.reading, action: onArcs)
                            .padding(.horizontal, 20)
                            .padding(.bottom, -4)
                            .transition(.opacity)
                    }

                    ForgeControlBar(
                        mode: $mode,
                        challengeState: challenges.today.state,
                        onChallenge: { showChallenge = true }
                    )
                    .padding(.horizontal, 20)

                    sheet
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isLocked)
        }
        .paywall($paywallDoor)
        .ignoresSafeArea(edges: .top)
        // What the panel's tallest detent is capped against. Read rather than
        // assumed, so the same numbers behave on a phone this was not designed
        // on — see `sheetMaxH`.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            available = height
        }
        .onChange(of: canExpand) { _, can in
            // The blade came loose, or came out, while the list was open.
            //
            // Which of the two it was decides the curve. A day that merely
            // finished is a list closing, and that is `sheetPanel`'s job. A
            // blade that came *out* is the scene moving, and the panel is only
            // making room — so it leaves on the same curve the subjects settle
            // on. See `Animation.bladeFreed`.
            if !can && isExpanded { setExpanded(false, curve: vm.isOut ? .bladeFreed : sheetSpring) }
        }
        // The two readings want different amounts of screen, and neither should
        // have to be asked for.
        //
        // **Week opens tall.** It is the planning surface: seven days, a whole
        // day's schedule, and every action that changes what a day is. At the
        // short detent it showed two rows of Thursday through a letterbox, and
        // the first thing anybody had to do on a screen they had just arrived at
        // was resize it. Nothing is learned from that gesture.
        //
        // **Today opens short**, exactly as it always has: the day panel is a
        // glance, and the sword behind it is what the home screen is *of*.
        // Coming back from the week therefore lands on the day itself rather
        // than halfway down a list somebody left open.
        .onChange(of: mode) { _, mode in
            withAnimation(sheetSpring) {
                isExpanded = mode == .week
                dragOffset = 0
                listPosition.scrollTo(edge: .top)
            }
        }
        .onChange(of: vm.isOut) { _, _ in
            // The review is never inherited. It lives on the view model, so
            // without this a day opened for review on Tuesday would come
            // back already open on Wednesday's — the one way this panel could
            // present it without being asked.
            vm.reviewOpen = false
        }
        // "Edit day", from the panel's ⋯ menu. QuickAdd is pushed from inside
        // it rather than presented over it, so the two never contend for the
        // same presentation slot.
        .sheet(isPresented: $vm.showEditRituals) {
            DayEditorSheet(vm: vm, arcs: arcs)
        }
        // The `+`: one tap per activity, onto today. See `QuickAddSheet`.
        .sheet(isPresented: $vm.showQuickAdd) {
            QuickAddSheet(vm: vm, arcs: arcs)
        }
        // A completion just moved one of the six: the chip rises from the row
        // that was kept. See `StatChip` for when it does not.
        .onChange(of: vm.lastGain) { _, gain in
            guard let gain, let frame = tappedFrames[gain.ritualID] ?? rowFrames[gain.ritualID] else { return }
            tappedFrames[gain.ritualID] = nil
            chip = ChipPlacement(gain: gain, frame: frame)
            AccessibilityNotification.Announcement(gain.label).post()
        }
        .task(id: chip?.gain.id) {
            guard chip != nil else { return }
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled else { return }
            chip = nil
        }
        .sheet(isPresented: $vm.showTomorrow) {
            TomorrowSheet(vm: vm)
        }
        .sheet(isPresented: $showCopyDay) {
            CopyDaySheet(
                vm: vm,
                anchor: vm.progress.currentDay.weekday,
                direction: .incoming,
                onCopied: { _ in }
            )
        }
        .sheet(item: honorRitual) { token in
            if let ritual = vm.ritual(token.id) {
                HonorPromptView(ritual: ritual) { vm.keepPromise(token.id) }
            }
        }
        .sheet(item: $editing) { ritual in
            ActivitySheet(vm: vm, ritual: ritual) { editing = nil }
        }
        .sheet(isPresented: $showChallenge) {
            DailyChallengeSheet(challenges: challenges)
        }
    }

    // MARK: - Sheet

    private var sheet: some View {
        VStack(spacing: 0) {
            // Handle and header travel together. Dragging a 4pt capsule is a
            // dexterity test, so the whole top band of the sheet is the grip.
            VStack(spacing: 0) {
                grabHandle
                if showsHeader { ritualHeader }
            }
            .contentShape(.rect)
            .gesture(sheetDrag)

            switch mode {
            case .week:
                WeekPlannerView(
                    vm: vm,
                    progress: vm.progress,
                    // Plan lives on this screen now — see `ForgeControlBar`.
                    // Everything it proposes is a change to the week, so it
                    // opens from the week and lands on the week.
                    brief: brief,
                    ai: ai,
                    arcs: arcs,
                    canExpand: canExpand,
                    // The week's own chrome — the week bar, the day strip and
                    // the day header — is grip band too. Without it the only
                    // place to haul the panel from in Week would be the 24pt
                    // handle above it.
                    onGripChanged: { dragOffset = $0 },
                    onGripEnded: { settle(from: isExpanded ? sheetMaxH : sheetMinH, value: $0) }
                )
                .transition(Self.modeSwap)

            case .today:
                Group {
                    switch content {
                    case .free:
                        FreeStateView(vm: vm, reflection: reflection)
                    case .empty:
                        EmptyDayView(
                            onPlan: {
                                ForgeHaptics.shared.tap()
                                vm.showQuickAdd = true
                            },
                            onCopy: vm.hasAnyOtherDayPlanned
                                ? { ForgeHaptics.shared.tap(); showCopyDay = true }
                                : nil
                        )
                    case .loose:
                        LoosePromptView(
                            pull: engine.pos,
                            left: HomeCopy.leftLine(vm.leftToday.map(\.label))
                        )
                    case .list, .week:
                        ritualList
                    }
                }
                .transition(Self.modeSwap)
            }
        }
        .frame(height: sheetHeight)
        .coordinateSpace(.named(Self.panelSpace))
        // The chip rises inside the panel and never over the scene or the
        // pull: it is drawn only while the panel is showing the list.
        .overlay(alignment: .topLeading) {
            if let chip, mode == .today, content == .list {
                StatChip(gain: chip.gain)
                    .id(chip.gain.id)
                    .position(x: chip.frame.maxX - 66, y: chip.frame.midY)
                    .allowsHitTesting(false)
            }
        }
        // Suppressed mid-drag so the sheet sits under the finger with no lag,
        // and restored for the snap.
        // The height follows whatever moved it. A drag owns the panel outright
        // and must not be animated at all; a pull is the scene's event and
        // borrows its curve; everything else is the panel's own spring.
        .animation(
            dragOffset != 0 ? nil : (vm.isOut ? .bladeFreed : sheetSpring),
            value: sheetHeight
        )
        // Native Liquid Glass replaces the old four-layer stack of
        // .ultraThinMaterial + linear gradient + radial highlight + stroke.
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    /// Drag the sheet between its two detents.
    private var sheetDrag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard canExpand else { return }
                dragOffset = -value.translation.height
            }
            .onEnded { value in
                guard canExpand else { return }
                settle(from: isExpanded ? sheetMaxH : sheetMinH, value: value)
            }
    }

    /// How far a haul has to get before it is a decision rather than a nudge.
    ///
    /// This is the whole of "a short swipe should expand the panel". It used to
    /// take somebody past the midpoint between the two detents — 142pt of travel
    /// from the bottom one — which meant a normal, deliberate, unhurried swipe up
    /// the list moved the panel a hand's width and then dropped it back where it
    /// started. Nothing about that reads as a control; it reads as the app
    /// refusing.
    ///
    /// 44pt is roughly a thumb's comfortable travel and about two thirds of a
    /// row, so a swipe that clears one row commits. Anything shorter still
    /// settles by momentum — see `settle`.
    private let commitDistance: CGFloat = 44

    /// Decide which detent a drag was heading for.
    ///
    /// Two rules, in order, and the order matters:
    ///
    ///  1. **Distance.** A haul that has genuinely travelled — in either
    ///     direction — is a decision, whatever speed it ended at. This is what
    ///     makes a slow, deliberate swipe work, and it is the case the old rule
    ///     got wrong.
    ///  2. **Momentum.** A short flick has not travelled far but is plainly going
    ///     somewhere, so where it would land decides it. This is the old rule,
    ///     kept, because it is the right answer for a fast gesture.
    ///
    /// A tiny movement that is neither satisfies the second rule at rest and
    /// returns to where it came from, which is what it should do.
    private func settle(from base: CGFloat, value: DragGesture.Value) {
        let travel = -value.translation.height
        if travel >= commitDistance { setExpanded(true); return }
        if travel <= -commitDistance { setExpanded(false); return }
        let projected = base - value.predictedEndTranslation.height
        setExpanded(projected > (sheetMinH + sheetMaxH) / 2)
    }

    /// A sideways deflection on the way down a list is not a haul.
    static func isVertical(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.height) > abs(value.translation.width)
    }

    /// `curve` defaults to the panel's own spring; the pull hands in the scene's
    /// instead, so the two are one movement rather than two.
    private func setExpanded(_ expanded: Bool, curve: Animation? = nil) {
        if expanded != isExpanded { ForgeHaptics.shared.detent() }
        withAnimation(curve ?? sheetSpring) {
            isExpanded = expanded
            dragOffset = 0
            // A collapsed list does not scroll, so one left parked halfway down
            // would strand three arbitrary rows on screen with no gesture left
            // to get back to the top of the day.
            if !expanded { listPosition.scrollTo(edge: .top) }
        }
    }

    private func dismiss(_ backdrop: Backdrop) {
        switch backdrop {
        case .list:
            setExpanded(false)
        case .review:
            ForgeHaptics.shared.detent()
            // The same curve the disclosure's own header uses, so a tap outside
            // and a tap on the header put the review away identically.
            withAnimation(.sheetPanel) { vm.reviewOpen = false }
        }
    }

    // MARK: - Presentation

    /// Identity for the honor sheet.
    ///
    /// This replaces a `extension String: Identifiable` conformance that used
    /// the string itself as its id — a retroactive conformance on a stdlib
    /// type that leaked app-wide.
    private struct RitualToken: Identifiable {
        let id: String
    }

    private var honorRitual: Binding<RitualToken?> {
        Binding(
            get: { vm.honorRitualID.map(RitualToken.init) },
            set: { if $0 == nil { vm.cancelHonor() } }
        )
    }

    // MARK: - Pieces

    private var grabHandle: some View {
        Capsule()
            .fill(.secondary)
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .contentShape(.rect)
            // The drag lives on the band around this; a plain tap on the handle
            // is kept as the shortest possible way to the same thing.
            .onTapGesture { if canExpand { setExpanded(!isExpanded) } }
            .accessibilityLabel(isExpanded ? "Collapse the list" : "Expand the list")
            .accessibilityAddTraits(.isButton)
    }

    private var ritualHeader: some View {
        HStack(spacing: 10) {
            Text(vm.listLabel)
                .font(.caption2.weight(.semibold))
                .tracking(2.4)
                .foregroundStyle(.secondary)
                // Never broken across lines. Squeezed between the segments and
                // the button at an accessibility size it was hyphenating itself
                // into "THIS MOR-NING", three lines deep.
                .lineLimit(1)
                .fixedSize()
                // "0 OF 5" → "1 OF 5" crossfades instead of snapping.
                .contentTransition(.opacity)
                .animation(.smooth(duration: 0.3), value: vm.listLabel)

            // The segments are a second reading of what the label already says.
            // When the words need the room, the picture is the part that goes.
            if !typeSize.isAccessibilitySize {
                ProgressSegments(total: vm.totalActive, done: vm.totalDone)
            } else {
                Spacer(minLength: 0)
            }

            // The rest of changing the day — the order, taking things out, the
            // parts — behind one menu, the same shape the week's own header
            // has, so the two views put the same things in the same places.
            Menu {
                Button("Edit day", systemImage: "slider.horizontal.3") {
                    ForgeHaptics.shared.tap()
                    vm.showEditRituals = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.footnote.weight(.medium))
                    .frame(width: 34, height: 34)
                    .contentShape(.rect)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("More")
            .accessibilityHint("Edit today: reorder, take things out, change an activity")

            // Adding, in one tap per activity (`QuickAddSheet`). It used to
            // open the editor, and adding was three screens and a dismissal
            // each time; nothing is added without a tap on its own row, and
            // every add can be undone from the toast.
            Button {
                ForgeHaptics.shared.tap()
                AddTip().invalidate(reason: .actionPerformed)
                vm.showQuickAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.footnote.weight(.medium))
                    .frame(width: 34, height: 34)
                    .contentShape(.rect)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Add to today")
            .accessibilityHint("Adds an activity in one tap")
            // The last of the first week's tips.
            .popoverTip(ForgeTips.current(AddTip.self), arrowEdge: .top)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 11)
    }

    private var ritualList: some View {
        ScrollView {
            // A plain VStack, not Lazy: the list is a handful of rows and it
            // has to animate rows *moving past each other* when one is
            // finished. A lazy stack only builds what is on screen, so a row
            // travelling to the bottom of the list has nothing to travel to.
            VStack(spacing: 0) {
                bankedLine
                // The first of the first week's tips, pointing down at the
                // first row. Inline rather than a popover: a popover takes the
                // first touch outside it to put itself away, and the touch this
                // tip is asking for is a tap on that row.
                if let tip = ForgeTips.current(RowTip.self) {
                    TipView(tip, arrowEdge: .bottom)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                }
                // A day with one part is the flat list Forge has always drawn,
                // and that is the overwhelming majority of days: nobody who has
                // not taken a routine ever sees a heading. The parts are the
                // shape a world proposed and the user kept, so they appear only
                // for somebody who asked for them.
                // `isTodayShaped`, not `isDayShaped`: a day whose activities all
                // land in one movement today does not need three headings, two
                // of which would sit over nothing.
                if vm.isTodayShaped {
                    ForEach(vm.todayParts) { part in
                        partHeading(part)
                        // `displayed` rather than the part's own order: within a
                        // movement, what is left to do floats above what is
                        // done, exactly as the flat list has always behaved.
                        let rows = vm.displayed(part)
                        ForEach(rows) { ritual in
                            // Last in its own part, not last in the day: the
                            // heading underneath already separates it, and a
                            // hairline plus a heading is one divider too many.
                            row(ritual, isLast: ritual.id == rows.last?.id)
                        }
                    }
                } else {
                    ForEach(vm.orderedRituals) { ritual in
                        row(ritual, isLast: ritual.id == vm.orderedRituals.last?.id)
                    }
                }

                restingLine
            }
            // Editing lives behind the header's one button now, so the list is
            // only ever the day itself.
            .padding(.bottom, 6)
        }
        .scrollIndicators(.hidden)
        .scrollPosition($listPosition)
        .modifier(
            PanelListBehavior(
                isExpanded: isExpanded,
                canExpand: canExpand,
                onOverscrollCollapse: { setExpanded(false) }
            )
        )
        // Whatever the viewport cuts off dissolves rather than ending on a hard
        // edge, so the fourth row reads as "there is more" instead of as a
        // clipped row. The third row's separator sits clear of this.
        .mask {
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 20)
            }
        }
    }

    /// The day is banked and there is still a list, said once and quietly.
    ///
    /// Only ever true on the first day — where the pull is granted with one of
    /// three done — and on a day where something was un-ticked after the pull.
    /// Both are states where the blade is out and the day is *not over*, and
    /// without a line saying so the panel is a list of activities under a sword
    /// that has already been earned, which reads as the app having lost track.
    ///
    /// A line rather than a card, at the top of the scroll rather than pinned:
    /// it is a fact about today, not a control, and once it has been read once
    /// it should be able to scroll out of the way like anything else.
    @ViewBuilder
    private var bankedLine: some View {
        if vm.isOut {
            Text("Today is already yours. What is left is still worth doing.")
                .font(.caption)
                .foregroundStyle(ForgeTheme.accent.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
    }

    /// What is not being asked of you today, said once and quietly.
    ///
    /// This exists because repeat rules can make an activity disappear, and an
    /// activity that is silently absent is indistinguishable from one that was
    /// lost. In an app whose entire premise is a list of promises, that is the
    /// one ambiguity worth spending a line of screen on — and it is a line
    /// rather than a section, because the whole point of scheduling something
    /// for Mondays is not to think about it on a Tuesday.
    @ViewBuilder
    private var restingLine: some View {
        let resting = vm.restingTodayCount
        if resting > 0 {
            Text(resting == 1
                 ? "One more activity, not today."
                 : "\(ForgeCount.spelled(resting)) more activities, not today.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .accessibilityLabel(Text("\(resting) activities are not scheduled for today"))
        }
    }

    /// One row, and the two things that can be done to it without opening it.
    ///
    /// The swipe takes the activity off **today** rather than destroying it —
    /// something that also happens on Thursday keeps Thursday, and something
    /// that happened only today goes back to the library or to "Yours", a tap
    /// away from returning. That is why it needs no confirmation; throwing a
    /// custom activity away for good is still asked about, in the composer,
    /// where it belongs.
    ///
    /// The same sentence, and the same method, as the swipe on a week row. A
    /// list showing one day can only honestly mean that day — see
    /// `ForgeViewModel.removeFromDay`.
    private func row(_ ritual: Ritual, isLast: Bool) -> some View {
        let today = vm.progress.currentDay.weekday
        return SwipeToDelete(id: ritual.id, openID: $swipedID) {
            remove(ritual)
        } content: {
            RitualRowView(
                ritual: ritual,
                isDone: vm.isDone(ritual.id),
                onComplete: {
                    // Where the row is now, for the chip, before the list
                    // moves it — see `StatChip`.
                    tappedFrames[ritual.id] = rowFrames[ritual.id]
                    RowTip().invalidate(reason: .actionPerformed)
                    vm.tapRitual(ritual.id)
                },
                onOpen: { editing = ritual },
                onDelete: { remove(ritual) },
                // "Move" in the long press: off today and onto another day of
                // the week, the same edit the week planner's menu makes.
                moveTargets: WeekPlannerView.weekOrder.filter { $0 != today },
                onMove: { weekday in vm.moveActivity(ritual.id, from: today, to: weekday) }
            )
        }
        .overlay(alignment: .bottom) { separator(isLast: isLast) }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(Self.panelSpace))
        } action: { frame in
            rowFrames[ritual.id] = frame
        }
    }

    private func remove(_ ritual: Ritual) {
        vm.removeFromDay(ritual.id, weekday: vm.progress.currentDay.weekday)
    }

    /// The name of a part of the day, and nothing else.
    ///
    /// Deliberately the quietest thing on the panel — smaller than a row's
    /// subtitle, kerned, and in the same 9.5pt label the Path card uses for its
    /// movements, so the shape somebody read on the card is recognisably the
    /// same shape they now live in. It is a heading, not a section: no fill, no
    /// rule, no disclosure, nothing to tap. The day is still one list; these
    /// only say where in it you are.
    ///
    /// A finished part takes the accent. That is the one genuinely new thing
    /// parts made possible and the reason they are worth the pixels — "Before
    /// the world" going quietly gold at seven in the morning is a fact about the
    /// day the flat list could never show, and it is exactly what the Vigil's
    /// standard is about.
    ///
    /// Only for a heading the user wrote. A world's own movement name — "When it
    /// lets go" — reads as a line of poetry dropped between two activities by
    /// nobody, which is exactly how it was reported. See `DayPart.isUserNamed`.
    @ViewBuilder
    private func partHeading(_ part: ShapedPart) -> some View {
        if part.isUserNamed {
            Text(part.name.uppercased())
                .font(ForgeTheme.label(9.5))
                .kerning(1.3)
                .foregroundStyle(part.isComplete ? ForgeTheme.accent : Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 53)
                .padding(.top, 16)
                .padding(.bottom, 7)
                .animation(.easeOut(duration: 0.3), value: part.isComplete)
                .accessibilityLabel(
                    Text(part.isComplete ? "\(part.name), complete" : part.name)
                )
        }
    }

    /// Hairline between rows, inset to the label so it reads as a list rather
    /// than a stack of slabs. Suppressed under the last row, where it would be
    /// a line under nothing — and under the last row of a part, where the
    /// heading below already does the separating.
    @ViewBuilder
    private func separator(isLast: Bool) -> some View {
        if !isLast {
            Rectangle()
                .fill(ForgeTheme.separator)
                .frame(height: 0.5)
                .padding(.leading, 53)
        }
    }
}

// MARK: - What a kept activity moved

/// "+4 Physical", rising from the row that was just kept.
///
/// # What it says, and what it does not
///
/// The **real** change of the blended score, read before and after the write
/// (`StatGain`): the number the tile on Becoming moved by, in that
/// dimension's colour. Nothing about it is stored. No chip when the change
/// rounds to nought, and none that is not upward — a completion is never
/// answered with a minus (see `StatGain`).
///
/// # Where it is drawn
///
/// Inside the panel, at the row's trailing edge where the tap landed, rising
/// eighteen points and gone in a second and a half. It never covers the scene
/// or the pull: it is drawn only while the panel shows the list, so the
/// completion that makes the blade loose — when the panel becomes the pull's
/// prompt — draws no chip at all, and nothing here sits over the sword.
/// **Reduce Motion: a fade only**, with no travel. VoiceOver hears the same
/// words as an announcement.
struct StatChip: View {
    let gain: StatGain

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isIn = false
    @State private var isRisen = false
    @State private var isGone = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: gain.dimension.symbol)
                .font(.system(size: 10, weight: .bold))
            Text(gain.label)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(gain.dimension.color)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .glassEffect(.regular.tint(gain.dimension.color.opacity(0.16)), in: .capsule)
        .fixedSize()
        .offset(y: reduceMotion || !isRisen ? 0 : -18)
        .opacity(isGone ? 0 : (isIn ? 1 : 0))
        .accessibilityHidden(true)
        .task {
            withAnimation(.easeOut(duration: 0.2)) { isIn = true }
            if !reduceMotion {
                withAnimation(.easeOut(duration: 1.3)) { isRisen = true }
            }
            try? await Task.sleep(for: .milliseconds(1050))
            withAnimation(.easeIn(duration: 0.35)) { isGone = true }
        }
    }
}

// MARK: - How a list inside the panel behaves

/// How a list inside the panel scrolls, and where the panel takes over.
///
/// It is a modifier rather than code in one view because there are two lists in
/// the panel — the day and the week — and two copies of this would be two
/// answers to "what does a swipe up do", which is exactly the sort of thing
/// nobody notices until the two drift apart.
///
/// # The rule
///
/// **The list always scrolls**, expanded or not. That is the change: it used to
/// be frozen while the panel was short, so a collapsed panel showing three of
/// eight activities could not be read without first being enlarged. Freezing it
/// bought a clean gesture and paid for it with the most basic thing a list does.
///
/// **The panel is grown and shrunk from its grip band** — the handle and the day
/// header above the list, which take a drag and a tap — and, once expanded, by
/// hauling the list past the top of itself. That last one is the rubber band
/// below, and it is the same handoff a native sheet makes.
///
/// # Why the panel is not also grown from the list
///
/// Because it cannot be, not reliably. Once a `ScrollView`'s own pan is live it
/// claims the touch outright and a `simultaneousGesture` attached alongside it is
/// never called — which is precisely why the old version had to disable
/// scrolling to get its gesture. Reaching for a `UIGestureRecognizer` delegate to
/// arbitrate the two, the way `UISheetPresentationController` does internally, is
/// a real option and a large one; it is not what "the list should scroll" is
/// worth today.
///
/// So the grip band is the panel's handle, and it is a 69pt full-width target
/// sitting directly above the list rather than a 4pt capsule. Nothing about the
/// two gestures overlaps, which is the other thing that was asked for.
struct PanelListBehavior: ViewModifier {
    var isExpanded: Bool
    var canExpand: Bool
    var onOverscrollCollapse: () -> Void

    func body(content: Content) -> some View {
        content
            // Always, rather than `.basedOnSize`: the rubber band is
            // load-bearing. A list short enough not to scroll still has to be
            // able to report that it is being pulled downward, or an expanded
            // panel holding four rows would have no gesture that closes it.
            .scrollBounceBehavior(.always)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                // 64pt of overscroll is past anything a flick produces on its
                // own and well inside what a deliberate haul reaches.
                if isExpanded, canExpand, offset < -64 { onOverscrollCollapse() }
            }
    }
}

// MARK: - Opening one activity

/// The composer, presented over the day rather than pushed inside an editor.
///
/// One wrapper rather than the same `NavigationStack` written out at each of the
/// three places that now open an activity — the day list, the week and the day
/// editor — because the cancel button, the detent and the corner radius are
/// presentation decisions and there should be one of each.
struct ActivitySheet: View {
    @Bindable var vm: ForgeViewModel
    let ritual: Ritual
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            ActivityComposer(
                mode: .edit(id: ritual.id, draft: ritual.draft),
                suggest: { name, symbol in vm.suggestedVerification(name: name, symbol: symbol) },
                onCommit: { vm.editRitual(ritual.id, to: $0) },
                destructive: ritual.isCustom
                    ? .delete { vm.deleteCustomRitual(ritual.id) }
                    : (vm.isEdited(ritual.id) ? .reset { vm.resetRitual(ritual.id) } : nil)
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onClose)
                }
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(ForgeTheme.Radius.sheet)
    }
}

/// A day with nothing on it.
///
/// # Why this exists at all
///
/// Because an empty day used to be an *earned* one. "Everything planned is
/// done" is true of a list with nothing in it, so an unplanned day arrived with
/// the blade already loose: the room lit, the prompt said "Loose — press the
/// grip and drag up", and a day could be won having done nothing. That was
/// nearly unreachable while every activity repeated daily. It is the ordinary
/// case now that activities belong to the day they were put on, so it had to
/// stop being a state the app could enter — see `ForgeViewModel.allDone`.
///
/// # What it says instead
///
/// A mark, one sentence and one clear thing to do. It is deliberately the same
/// shape as the planner's own empty day, because they are the same moment
/// arriving from two directions, and somebody who has met one should recognise
/// the other. The second action is offered only when there is a day worth
/// copying: an empty state with a button that can do nothing is worse than an
/// empty state with one button.
struct EmptyDayView: View {
    var onPlan: () -> Void
    var onCopy: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Image(systemName: "calendar.day.timeline.left")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text("Today is open.")
                .font(.headline)
                .padding(.top, 14)

            Text("Nothing is planned yet.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)

            Button(action: onPlan) {
                Text("Plan today")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 40)
                    .padding(.horizontal, 24)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(ForgeTheme.cream)
            .foregroundStyle(Color(red: 0.063, green: 0.063, blue: 0.078))
            .padding(.top, 20)

            if let onCopy {
                Button("Copy another day here", action: onCopy)
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(ForgeTheme.accent)
                    .padding(.top, 12)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }
}

/// The sheet's loose state (§5.5, §5.7): a rising arrow and copy that tracks
/// the pull live. Short, physical, second person — no exclamation, no emoji.
struct LoosePromptView: View {
    let pull: Double
    /// "2 left · Deep work, Wake up", when the blade is loose with the list
    /// unfinished — the first run's grace. The prompt replaces the list, and
    /// without this line the two activities still on today vanished from the
    /// screen with nothing saying they were there.
    var left: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var title: String {
        if pull > 0.62 { return "Now" }
        if pull > 0.30 { return "Almost" }
        if pull > 0.05 { return "It gives" }
        return "Loose"
    }

    private var subtitle: String {
        if pull > 0.62 { return "Let go" }
        if pull > 0.30 { return "Keep pulling" }
        if pull > 0.05 { return "Steady" }
        return "Press the grip and drag up"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            TimelineView(.animation(paused: reduceMotion || pull > 0.02)) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate
                let cycle = (phase / 2.2).truncatingRemainder(dividingBy: 1)
                let wave = (1 - cos(cycle * .pi * 2)) / 2

                Image(systemName: "arrow.up")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.white)
                    // Once the hand is on it, the glyph stops hinting and
                    // simply fades out with the pull.
                    .opacity(pull > 0.02 ? max(0, 1 - pull) : 0.28 + wave * 0.62)
                    .offset(y: pull > 0.02 ? -pull * 10 : 3 - wave * 9)
            }
            .frame(height: 44)

            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.opacity)
                .padding(.top, 14)

            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.44))
                .contentTransition(.opacity)
                .padding(.top, 4)

            // One line, and it gives way to the pull: once a hand is on the
            // grip, the only thing the panel should be saying is the grip.
            if let left {
                Text(left)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.36))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                    .opacity(pull > 0.05 ? 0 : 1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.25), value: title)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text([title, subtitle, left].compactMap { $0 }.joined(separator: ". ")))
    }
}

/// Words the home screen says about the day, kept out of the views so they
/// can be tested.
enum HomeCopy {

    /// The days-kept capsule in the scene's corner, as its two halves.
    ///
    /// Before anything is kept it reads **DAY ONE**, not "0 DAYS". A zero is
    /// the first thing a new install saw on the home screen, and it is a
    /// score of nothing on the day somebody has only just begun — the one
    /// morning the app most needs to describe where they are rather than what
    /// they have not done.
    struct DaysBadge: Equatable, Sendable {
        /// The figure, or nil when the word says it all.
        let count: String?
        let word: String
        let accessibility: String
    }

    static func daysBadge(daysKept: Int) -> DaysBadge {
        guard daysKept > 0 else {
            return DaysBadge(count: nil, word: "DAY ONE", accessibility: "Day one")
        }
        return DaysBadge(
            count: "\(daysKept)",
            word: daysKept == 1 ? "DAY" : "DAYS",
            accessibility: daysKept == 1 ? "1 day kept" : "\(daysKept) days kept"
        )
    }

    /// "2 left · Deep work, Wake up" — or nil when nothing is left.
    static func leftLine(_ labels: [String]) -> String? {
        guard !labels.isEmpty else { return nil }
        return "\(labels.count) left \u{00B7} \(labels.joined(separator: ", "))"
    }
}

import SwiftUI

/// The first two minutes.
///
/// Not a tutorial and not a walkthrough — the actual product, run once, now.
/// Everything it writes is real: the answers are the assessment every screen
/// afterwards reads, what they choose to build is the focus, the plan becomes
/// **the day**, the one they finish goes into history, and the blade they pull
/// earns a real blade on a real streak. The only concession is that the blade
/// comes loose with one thing done instead of all of them, because the
/// alternative is asking somebody to come back in eighteen hours to find out
/// what the app does.
///
/// # What it shows, and why it changed (1.1)
///
/// The 1.0 sequence said what Forge was and asked somebody to pick three
/// activities. It never showed them what the practice would do to them, which
/// is the one thing a person deciding whether to pay for a practice wants to
/// see. So the sequence now **shows the transformation** (DIRECTION_1_1 §2):
///
/// 1. **Cold open.** The sword in the stone, and what keeping a day does to it.
/// 2. **Seven questions**, one tap each. The answers are the starting stats.
/// 3. **What you want to build**, preselected from the two lowest answers.
/// 4. **The drawing.** The starting shape draws itself, two and a half seconds.
/// 5. **The transformation.** Now, in seven days, in thirty and at full
///    potential — the six, OVR and the blade each stage earns, every number
///    computed by the same model the Becoming tab uses (`Transformation`).
/// 6. **Why it works.** Three cited findings.
/// 7. **Your plan.** An activity for each part being built, each on its own
///    days and at a time. This writes the day.
/// 8. **The pull**, rehearsed with nothing at stake.
/// 9. **Forge Pro** — seven days free, then a decision (`PaywallView`, the
///    hard paywall). Walked straight past by anybody who already has the
///    practice.
/// 10. **Do one now**, and the first pull on the real home screen. Unchanged.
///
/// # Skippable forward, never destructive
///
/// Every beat moves forward. The questions are answered by the tap that moves
/// on; building is skippable and skipping it still leaves a plan, drawn from
/// the lowest answers; the drawing skips on a tap. Nothing here can strand
/// somebody on a screen, and nothing is written that the next screen does not
/// read.
struct FirstRunView: View {
    @Bindable var vm: ForgeViewModel

    /// What has been bought, for the paywall beat. Optional so a preview with
    /// no store still runs — and walks past the beat.
    @Environment(ForgeStore.self) private var store: ForgeStore?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// What the reading area of a beat is allowed to fill before it scrolls.
    @State private var scrollHeight: CGFloat = 0

    /// The answers so far, by question. Written as the assessment when the
    /// seventh lands, and kept here until then so going back to a question
    /// shows what was answered.
    @State private var answers: [Assessment.Question: Int] = [:]
    /// Whether "what you want to build" has been given its suggestion in this
    /// run. Once: after that the choice is theirs.
    @State private var hasSuggested = false
    /// The plan being proposed, from the moment the build beat is left. The
    /// transformation projects it and the plan beat edits it, so both screens
    /// are about the same plan.
    @State private var plan: [PlanEntry] = []
    /// The four stops, computed once from the plan and the answers.
    @State private var frames: [Transformation.Frame] = []
    /// Which way the questions are going: forward on an answer, back on the
    /// back button. See `AnswerMotion`.
    @State private var answersForward = true

    /// The one activity the `doOne` beat asks for, held still.
    ///
    /// **It has to be frozen and it was not.** `vm.firstRunActivity` is the
    /// smallest thing on today's list that is *not done*, so the instant
    /// somebody kept the first one the property answered with the second — and
    /// the beat, which reads it every time it draws, swapped to a different
    /// activity for the four hundred milliseconds before the cover came off.
    /// A second task appearing and vanishing at the exact moment somebody
    /// completes their first is the app teaching, in the clearest possible
    /// terms, that it cannot be trusted to hold still. One thing is asked for,
    /// and it is the same thing until the screen is gone.
    @State private var firstTask: Ritual?
    /// Whether that one thing has been kept. The beat stays on screen after it
    /// is — see `handOverToTheBlade`.
    @State private var didKeep = false

    /// How tall the art may be on a beat that also carries words.
    ///
    /// It has to give way, and this is the cheap half of the fix. At the
    /// accessibility sizes two lines of title become five and the artwork is the
    /// only thing on the screen with no information in it — so it shrinks first,
    /// and `beat(...)` scrolls if that is still not enough. Without both, the
    /// subtitle ran underneath the button and the last line of the promise was
    /// unreadable at the sizes where reading is hardest.
    private var artHeight: CGFloat {
        typeSize.isAccessibilitySize ? 170 : 380
    }

    private var transition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .offset(y: 24)),
                removal: .opacity
            )
    }

    private var questions: [Assessment.Question] { Assessment.Question.allCases }

    var body: some View {
        ZStack {
            FirstRunAmbience()

            VStack(spacing: 0) {
                if let progress = barProgress {
                    OnboardingTopBar(progress: progress, onBack: backAction, onSkip: skipAction)
                        .transition(.opacity)
                }

                ZStack {
                    switch vm.firstRunStage {
                    case .coldOpen:
                        coldOpen.transition(transition)
                    case .question(let index):
                        question(index)
                            .id(index)
                            .transition(AnswerMotion.transition(
                                forward: answersForward, reduceMotion: reduceMotion
                            ))
                    case .build:
                        build.transition(transition)
                    case .drawing:
                        drawing.transition(transition)
                    case .transformation:
                        TransformationBeat(frames: frames) { advance(to: .science) }
                            .transition(transition)
                    case .science:
                        ScienceBeat { advance(to: .plan) }
                            .transition(transition)
                    case .plan:
                        PlanBeat(entries: $plan, today: vm.progress.currentDay.weekday) {
                            commitPlan()
                        }
                        .transition(transition)
                    case .metaphor:
                        metaphor.transition(transition)
                    case .paywall:
                        paywall.transition(.opacity)
                    case .doOne:
                        doOne.transition(transition)
                    default:
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.9), value: vm.firstRunStage)
    }

    private func advance(to stage: ForgeViewModel.FirstRunStage) {
        ForgeHaptics.shared.tap()
        // How many of the six were chosen — zero for a skip. The count, and
        // never which ones.
        if vm.firstRunStage == .build, stage == .drawing {
            ForgeTelemetry.send(.onboardingFocusChosen(count: vm.focus.count))
        }
        vm.firstRunStage = stage
    }

    // MARK: - The bar and the way back

    /// Where the bar stands: from the first question to the pull, one step a
    /// screen. Nil where there is no bar — the cold open, which has not started
    /// anything yet, and the do-one beat, which is the app rather than the
    /// sequence.
    private var barProgress: Double? {
        let steps = Double(questions.count + 6)
        let position: Int
        switch vm.firstRunStage {
        case .question(let index): position = index + 1
        case .build: position = questions.count + 1
        case .drawing: position = questions.count + 2
        case .transformation: position = questions.count + 3
        case .science: position = questions.count + 4
        case .plan: position = questions.count + 5
        case .metaphor: position = questions.count + 6
        default: return nil
        }
        return Double(position) / steps
    }

    /// Back, on the question beats only. The first question goes back to the
    /// cold open; every answer already given stays given, and shows as chosen
    /// when its question comes round again.
    ///
    /// The direction is set a turn before the move, so the question leaving
    /// has already been drawn with the transition that sends it right.
    private var backAction: (() -> Void)? {
        guard case .question(let index) = vm.firstRunStage else { return nil }
        return {
            answersForward = false
            DispatchQueue.main.async {
                guard vm.firstRunStage == .question(index) else { return }
                vm.firstRunStage = index > 0 ? .question(index - 1) : .coldOpen
            }
        }
    }

    /// Skip, on the build beat, once nothing is chosen.
    ///
    /// Skipping is a way past the question, not an answer to it, so it is a
    /// quiet word in the corner rather than the capsule — the capsule is the
    /// one primary action on every beat, and a cream "Skip for now" under six
    /// rows made declining look like the thing the screen wanted. It lives in
    /// the bar rather than in a row of its own because the row cost the list
    /// its last two dimensions on a standard phone — which, with the
    /// suggestion preselected from the lowest answers, were often the two it
    /// had just chosen.
    private var skipAction: (() -> Void)? {
        guard vm.firstRunStage == .build, vm.focus.isEmpty else { return nil }
        return { leaveBuild() }
    }

    /// One beat: something to read, centred, with its action pinned beneath it.
    ///
    /// The reading area scrolls and the button does not. That is the whole
    /// point — three of these screens are an image over two or three lines of
    /// type, and at the accessibility sizes the type grows until it runs under
    /// the button. A `Spacer` cannot solve that because a spacer's minimum is
    /// zero; the content has to be allowed to exceed the screen and be reachable
    /// when it does, while the one thing somebody needs to press stays exactly
    /// where they expect it.
    @ViewBuilder
    private func beat<Content: View, Action: View>(
        @ViewBuilder content: () -> Content,
        @ViewBuilder action: () -> Action
    ) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    content()
                    Spacer(minLength: 0)
                }
                // Fills the scroll view when the content is short, so a beat
                // with two lines on it is still vertically centred rather than
                // pinned to the top of a screen it does not fill.
                .frame(maxWidth: .infinity, minHeight: scrollHeight)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            // Measured on the scroll view rather than on the screen, which is
            // the whole difference between this working and not: the content is
            // centred inside the space it actually has, not inside the space the
            // button is also using. Measuring the outer stack made the content
            // exactly one button taller than its viewport, so the last line sat
            // under the button and had to be scrolled up to be read.
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                scrollHeight = height
            }

            action()
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
        .padding(.vertical, 32)
    }

    // MARK: - 1. The cold open

    /// The sword in the stone, and the whole mechanic in two sentences.
    ///
    /// It replaced a promise screen ("Forge is not a habit tracker"), which
    /// said what Forge was by saying what it was not. This says what it does:
    /// a day kept loosens the blade, and the person pulls it — the one act the
    /// product is built around, stated before anything is asked.
    private var coldOpen: some View {
        beat {
            BladePlate(height: artHeight)
                .rises(after: 0)

            Text(FirstRunCopy.coldOpenTitle)
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)
                .padding(.top, 22)
                .rises(after: 0.22)

            Text(FirstRunCopy.coldOpenLine)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
                .padding(.top, 10)
                .rises(after: 0.42)
        } action: {
            ForgeButton(title: FirstRunCopy.coldOpenButton) { advance(to: .question(0)) }
                .rises(after: 0.66)
        }
    }

    // MARK: - 2. Seven questions

    /// One of the seven. The tap that answers is the tap that moves on.
    private func question(_ index: Int) -> some View {
        let question = questions[index]
        return QuestionBeat(
            question: question,
            selected: answers[question],
            isFirst: index == 0
        ) { choice in
            answer(choice, at: index)
        }
    }

    /// Record the answer, let it be seen to land, and move on.
    ///
    /// The pause is `AnswerMotion.hold`, 140 ms: long enough for the chosen
    /// row to light, short enough that the next question is already arriving
    /// by the time a finger is off the glass. If somebody pressed back inside
    /// it, nothing moves — the stage is checked against the question that was
    /// answered.
    private func answer(_ choice: Int, at index: Int) {
        answers[questions[index]] = choice
        answersForward = true
        Task { @MainActor in
            try? await Task.sleep(for: AnswerMotion.hold)
            guard vm.firstRunStage == .question(index) else { return }
            if index + 1 < questions.count {
                vm.firstRunStage = .question(index + 1)
            } else {
                finishQuestions()
            }
        }
    }

    /// The seventh answer is in: keep the assessment, suggest what to build,
    /// and move on.
    ///
    /// Written now rather than at the end of the run, because it is complete
    /// now — and a first run abandoned later still leaves somebody whose
    /// Becoming tab can read what they said.
    private func finishQuestions() {
        let assessment = Assessment(day: vm.progress.currentDay, answers: answers)
        vm.assessment = assessment
        ForgeTelemetry.send(.assessmentCompleted)
        if !hasSuggested {
            hasSuggested = true
            vm.focus = Set(assessment.suggestedFocus)
        }
        vm.firstRunStage = .build
    }

    // MARK: - 3. What you want to build

    /// The first question the app asks that is about the future rather than
    /// the present, and it arrives with an answer already on it.
    ///
    /// # The suggestion
    ///
    /// The two lowest answers are chosen when the beat opens, with one quiet
    /// line saying so — "Suggested from your answers" — and one tap to change
    /// either. It is a suggestion because it is only arithmetic: the lowest
    /// numbers are where there is most room, which is not the same as what
    /// somebody wants, and the line goes the moment the choice is theirs.
    ///
    /// # Why this replaced "Who are you becoming?"
    ///
    /// The identity question is the better question and it is the wrong one to
    /// ask first. "Someone who reads" is a sentence a person arrives at *after*
    /// months of a practice — it is a conclusion, not a starting point — and put
    /// in front of a stranger in their first thirty seconds it mostly produced a
    /// Skip. *What do you want to build* is answerable by pointing.
    ///
    /// The old objection to the dimensions was that they are **derived** — read
    /// off what somebody actually does — so asking for them up front made the
    /// app ask for something it was about to work out anyway. That objection was
    /// right about the Shape and wrong about this: the Shape says what *is*, and
    /// this says what somebody *wanted*, and the two are different facts. The
    /// gap between them is the only place in the product where advice can
    /// honestly come from — see `ForgeViewModel.focus` and `DayPlanner.strengthen`.
    ///
    /// # How many
    ///
    /// **As many as somebody means.** It was capped at three once, on the
    /// argument that a person building everything is building nothing — which
    /// is a true sentence about a *day* and a false one about a direction.
    /// Nobody wants to be weaker in three of the six. The plan it produces is
    /// one activity per part, three to six, which is where the real constraint
    /// always was.
    private var build: some View {
        VStack(spacing: 0) {
            // One scroll area for the question, the polygon and the six, with
            // the button pinned under it. At the standard sizes all of it fits
            // on a 17e — the six rows are the answer, and the two the answers
            // suggested are as often the last two as not — and at the
            // accessibility sizes the whole question scrolls rather than the
            // rows scrolling under a heading that no longer fits.
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        Text("What do you want to build?")
                            .font(.title2.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        // Two lines, reserved. The subtitle changes on the first
                        // change of choice, and the sentences do not wrap to the
                        // same number of lines on every phone — so on a narrow
                        // one everything below it, hexagon and all, jumped by a
                        // line's height at the exact moment somebody's finger
                        // came off a row.
                        Text(buildSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                            .lineLimit(2, reservesSpace: true)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                    if !typeSize.isAccessibilitySize {
                        FocusHexagon(chosen: vm.focus)
                            .frame(height: 116)
                            .padding(.bottom, 10)
                    }

                    VStack(spacing: 6) {
                        ForEach(RitualCategory.dimensions, id: \.self) { dimension in
                            DimensionChoiceRow(
                                dimension: dimension,
                                isChosen: vm.focus.contains(dimension),
                                isDimmed: false,
                                minHeight: 56
                            ) {
                                toggle(dimension)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            ForgeButton(title: "Continue") {
                leaveBuild()
            }
            .disabled(vm.focus.isEmpty)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .padding(.bottom, 20)
        // **Not on the whole beat.** It was, and a `withAnimation` covering a
        // `ScrollView` animates the scroll view's own layout: choosing a row
        // near the bottom of six made the list settle, which reads as the
        // screen sliding under the finger that just chose. The two things that
        // should move on a choice are the polygon and the subtitle, and both
        // carry their own animation now.
        .animation(.forgeSelection, value: buildSubtitle)
    }

    /// Says what the screen is for, and then gets out of the way.
    ///
    /// While the choice is still exactly the suggestion, it says where the
    /// suggestion came from. It never counts: "two of six chosen" would tell
    /// somebody who has finished that they are a third of the way through
    /// something.
    private var buildSubtitle: String {
        if let suggestion = vm.assessment?.suggestedFocus,
           !suggestion.isEmpty, vm.focus == Set(suggestion) {
            return FirstRunCopy.suggested
        }
        return vm.focus.isEmpty
            ? "Pick every part you mean. One is enough to start."
            : "Change it whenever you like \u{2014} nothing here is locked in."
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
        if vm.focus.contains(dimension) {
            ForgeHaptics.shared.tap()
            _ = vm.focus.remove(dimension)
            return
        }
        ForgeHaptics.shared.detent()
        _ = vm.focus.insert(dimension)
    }

    /// The choice is made — or skipped, which leaves the focus empty and the
    /// plan drawn from the lowest answers alone. The plan and its projections
    /// are worked out once, here, so the next three screens are about the same
    /// plan.
    private func leaveBuild() {
        if let assessment = vm.assessment {
            plan = OnboardingPlan.propose(focus: vm.focus, assessment: assessment)
            frames = Transformation.frames(
                plan: plan.compactMap(\.ritual), assessment: assessment
            )
        }
        advance(to: .drawing)
    }

    // MARK: - 4. The drawing

    @ViewBuilder
    private var drawing: some View {
        if let assessment = vm.assessment {
            // It moves on by itself, so no haptic of its own on the way out —
            // the drawing has just played six.
            DrawingBeat(assessment: assessment) { vm.firstRunStage = .transformation }
        } else {
            // Not reachable — the questions write the assessment before the
            // build beat opens — and if it ever were, the drawing has nothing
            // to draw and the next screen is the right place to be.
            Color.clear.onAppear { vm.firstRunStage = .transformation }
        }
    }

    // MARK: - 7. Your plan

    /// The plan becomes the day: the activities, on their days, at their
    /// times. See `ForgeViewModel.adoptPlan`.
    private func commitPlan() {
        vm.adoptPlan(plan)
        advance(to: .metaphor)
    }

    // MARK: - 8. The sword

    /// The beat the whole app is named after, and the one that has to be felt
    /// rather than read.
    ///
    /// # What it says
    ///
    /// It used to say *the blade is what you are building*, which is an
    /// explanation — a sentence about a metaphor, delivered to somebody who has
    /// not yet done anything. What it says now is the claim the product is
    /// actually making, in the second person and the present tense: **you are
    /// shaping yourself.** The blade is the thing being shaped; the day is what
    /// strikes it; and both of those are on the screen while the words are read.
    ///
    /// # Why there is no button
    ///
    /// Because a Continue button here would be the app asking somebody to agree
    /// to a metaphor. The one gesture Forge owns — the only interaction in the
    /// product that no competitor has — is a blade being dragged out of stone
    /// under real resistance, and this is the moment it means the most: nothing
    /// has been earned yet, and the pull is the beginning rather than the
    /// reward.
    ///
    /// It also fixes something that was quietly wrong. The first *real* pull
    /// happens a minute later on the home screen, on the day somebody installs,
    /// and until this beat existed nobody had ever been shown the gesture — the
    /// app waited until the one moment that matters and hoped. Here it is
    /// rehearsed with nothing at stake, so the pull that banks the first day is
    /// a thing their hands already know.
    ///
    /// **VoiceOver gets it as an action**, not as a drag: the plate is one
    /// element, labelled, and double-tapping frees the blade. A gesture nobody
    /// can perform is a wall, and the only beat with no other way past it is the
    /// one that must not have one.
    private var metaphor: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Text("You are shaping yourself.")
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)
                .rises(after: 0.1)

            Text("This is the blade. Every day you keep is a strike on it, and nothing else moves it.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
                .padding(.top, 12)
                .rises(after: 0.32)

            Spacer(minLength: 12)

            // Smaller than the other beats' art at the accessibility sizes, and
            // for a harder reason than theirs: this is the one screen in the
            // sequence that cannot scroll, because a `ScrollView` around a
            // vertical drag takes the drag (§16). So the picture has to give
            // way far enough that five lines of title and six of subtitle still
            // fit above it.
            PullToBegin(height: typeSize.isAccessibilitySize ? 130 : 300) {
                leaveRehearsal()
            }
            .rises(after: 0.5)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 24)
    }

    // MARK: - 9. Forge Pro

    /// The pull is rehearsed. The paywall is next — unless the practice is
    /// already theirs, and then the first thing to do is.
    private func leaveRehearsal() {
        guard let store, !PremiumGate.passesOnboardingPaywall(store.access) else {
            advance(to: .doOne)
            return
        }
        advance(to: .paywall)
    }

    /// The hard paywall (DIRECTION_1_1 §1): after the pull is rehearsed and
    /// before the first thing is done. It has no way out but a free week, a
    /// plan, a restore, or the App Store recognising a founder — and every one
    /// of those continues to the first thing to do. See `PaywallView`.
    @ViewBuilder
    private var paywall: some View {
        if let store {
            PaywallView(door: .onboarding, store: store) { advance(to: .doOne) }
        } else {
            // A preview, or a wiring mistake: nothing to sell with, so nothing
            // is sold and the run carries on.
            Color.clear.onAppear { vm.firstRunStage = .doOne }
        }
    }

    // MARK: - 10. Do one now

    /// One thing, named as the first of something rather than as a task — and
    /// **one thing only**, from the moment the beat opens to the moment the
    /// cover comes off.
    ///
    /// # What was wrong with it
    ///
    /// The activity was read from `vm.firstRunActivity` on every draw, and that
    /// property answers with the smallest thing on today's list *that is not
    /// done*. So keeping the first one changed the answer, and the screen spent
    /// the four hundred milliseconds before the handover showing a second,
    /// different activity — appearing and disappearing at the exact moment
    /// somebody had just completed their first thing in the app. Whatever else
    /// that teaches, it does not teach the mechanic.
    ///
    /// So the activity is frozen in `firstTask`, and the beat does not leave the
    /// instant it is kept: the mark ticks, the line under it says what just
    /// happened and that everything in Forge works that way, and *then* the day
    /// arrives. The rest of today is a thing somebody meets having understood
    /// one row, rather than a list that appears over the top of the one they
    /// were reading.
    @ViewBuilder
    private var doOne: some View {
        if let ritual = firstTask ?? vm.firstRunActivity {
            beat {
                RitualGlyph(ritual: ritual, size: 38)
                    .frame(width: 108, height: 108)
                    .glassEffect(.regular, in: .circle)
                    .overlay {
                        Circle()
                            .strokeBorder(ForgeTheme.accent, lineWidth: 2)
                            .opacity(didKeep ? 1 : 0)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if didKeep {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 30))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, ForgeTheme.accent)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }

                Text(ritual.label)
                    .font(.title.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 24)
                    .padding(.horizontal, 32)

                if !didKeep, let evidence = evidenceLine(for: ritual) {
                    Text(evidence)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                        .padding(.horizontal, 32)
                }

                // Deliberately says now rather than tomorrow. The whole
                // sequence exists to move the first one to today.
                Text(didKeep
                     ? "Kept. That is the whole mechanic \u{2014} every activity on your day works exactly like that."
                     : "Go and do it. It takes a minute.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .padding(.horizontal, 32)
            } action: {
                // Same height either way, so the screen does not jump under the
                // finger that just pressed it.
                ZStack {
                    if didKeep {
                        Text("Now the rest of today.")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 52)
                            .transition(.opacity)
                    } else {
                        ForgeButton(title: "I kept my promise") {
                            ForgeHaptics.shared.ritualVerified()
                            vm.keepPromise(ritual.id)
                            withAnimation(.forgeRow) { didKeep = true }
                            handOverToTheBlade()
                        }
                        .transition(.opacity)
                    }
                }
            }
            .onAppear { if firstTask == nil { firstTask = ritual } }
            .animation(.forgeRow, value: didKeep)
        } else {
            // Nothing left to ask for — every choice is already done. Straight
            // to the blade.
            Color.clear.onAppear { vm.firstRunStage = .pull }
        }
    }

    /// Leave this beat and uncover the real home screen.
    ///
    /// # Why the two halves are not in the same runloop turn
    ///
    /// Completing the activity writes a `DayRecord`, and everything downstream
    /// of that fires synchronously off it: the snapshot is republished, the
    /// notification plan is rebuilt, and — the expensive one — the Live Activity
    /// is started, which makes the system re-specify the scene's frame. Taking
    /// the full-screen cover off in the *same* turn asks SwiftUI to hand a
    /// window back to a view hierarchy that has been idle behind an opaque
    /// overlay for ninety seconds, while the scene underneath it is being
    /// re-laid-out by the system.
    ///
    /// That combination is what produced the black home screen recorded in
    /// `FORGE_CONTEXT` §12 as an undiagnosed intermittent: the app stayed alive,
    /// the state was right, nothing was logged, and putting it in the background
    /// and bringing it forward again drew everything correctly. It reproduced
    /// reliably enough to watch once the first run got longer.
    ///
    /// # Why it is a second and a quarter rather than four hundred milliseconds
    ///
    /// The delay started life as the smallest one that fixed the black screen,
    /// and it read as a stutter: the tap was acknowledged, the beat blinked, and
    /// the whole day arrived. This is the first promise anybody has kept in
    /// Forge and the only moment in the sequence where the mechanic can be shown
    /// with exactly one thing on screen — so the mark ticks, the line explains
    /// what just happened, and the day comes after somebody has read it. It is
    /// still one turn later than the write, which is the part that was load
    /// bearing.
    private func handOverToTheBlade() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1250))
            withAnimation(.easeInOut(duration: 0.45)) { vm.firstRunStage = .pull }
        }
    }

    /// "The first one for Physical.", or nothing at all for somebody who did
    /// not choose what it builds. Silence is the correct output — a line
    /// naming a part they never pointed at would be the app showing its own
    /// plumbing. The words are `FirstRunCopy.evidence(for:)`.
    ///
    /// It names the *dimension* rather than an identity now. That is not a
    /// downgrade: this is the first activity somebody has ever completed in
    /// Forge, and the only claim worth making about it is the one they will see
    /// again on every screen afterwards — which part of them it built.
    private func evidenceLine(for ritual: Ritual) -> String? {
        guard vm.focus.contains(ritual.category) else { return nil }
        return FirstRunCopy.evidence(for: ritual.category)
    }
}

// MARK: - Entrances

private extension View {
    /// Fade up, once, after a delay. The first run's only staging.
    ///
    /// Every screen in the sequence is two or three lines over an image, and
    /// they used to arrive as a block — correct, and inert. Letting them land in
    /// reading order costs one modifier and is the difference between a screen
    /// appearing and a screen opening. Nothing waits on it: the button is
    /// pressable from the first frame, and Reduce Motion drops the offset and
    /// keeps a plain fade.
    func rises(after delay: Double) -> some View {
        modifier(RiseIn(delay: delay))
    }
}

private struct RiseIn: ViewModifier {
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 16)
            .onAppear {
                withAnimation(.easeOut(duration: 0.55).delay(delay)) { shown = true }
            }
    }
}

// MARK: - The room

/// The light the first run is lit by.
///
/// Every screen in the sequence used to be type on flat black, which is not the
/// app: Forge is one room lit from the upper left, and the sequence that
/// introduces it was the only part of the product that did not look like it. So
/// there is a warm source where the room's is, a cold counterweight low on the
/// other side so the warmth reads as light rather than as a stain, and the whole
/// thing breathes on a nine-second cycle — slow enough that nobody watching it
/// can tell it is moving, and slow enough not to compete with a word on the
/// screen.
///
/// Two gradients and no assets. Off under Reduce Motion, where it is the same
/// picture holding still rather than a faster version of the same drift.
///
/// Internal rather than private since 1.1: the assessment taken from the
/// Becoming tab (`AssessmentSheet`) is the same seven questions in the same
/// room, and a second copy of the light would be a second room.
struct FirstRunAmbience: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        ZStack {
            ForgeTheme.bg

            RadialGradient(
                colors: [Color(red: 1.0, green: 0.86, blue: 0.68).opacity(0.14), .clear],
                center: UnitPoint(x: 0.16, y: 0.06),
                startRadius: 0,
                endRadius: 540
            )
            // Never below one. It breathed between 0.94 and 1.10, and at the
            // small end the warm layer no longer covered the screen: the room's
            // black showed as a hard strip along the top and the left, where
            // the light is strongest — a frame drawn round every beat for half
            // of each cycle. Growing from full size keeps the same breath.
            .scaleEffect(drift ? 1.12 : 1)
            .opacity(drift ? 1 : 0.78)

            RadialGradient(
                colors: [ForgeTheme.accent.opacity(0.09), .clear],
                center: UnitPoint(x: 0.94, y: 1.0),
                startRadius: 0,
                endRadius: 460
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}

// MARK: - The pull

/// The blade, and the gesture that ends the sword beat.
///
/// # What it is not
///
/// It is **not** `SwordEngine`. That is a real physics simulation with catches,
/// slip-back, friction ticks and a stone that has to be beaten — and it is
/// correct there, because on the home screen the pull is the last thing between
/// somebody and a day they have earned. Here nothing is at stake and the pull is
/// a teaching move, so it is one continuous drag with weight on it: the blade
/// follows the finger, resists a little more the further it comes, ticks as it
/// goes, and leaves at the top.
///
/// Reusing the engine was tried in the head and rejected for one reason: the
/// engine can be *lost*. It is meant to be. A first run whose only exit is a
/// gesture somebody can fail at is a first run people close.
///
/// # Why it cannot be tapped
///
/// Because a tap is what a button is, and the whole point of the beat is that
/// the app asks for something of you before it gives you anything. The only
/// other way through is VoiceOver's action, which is not a shortcut — it is the
/// same act, performed by somebody who cannot drag.
private struct PullToBegin: View {
    let height: CGFloat
    let onFree: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far out of the stone the blade is, 0 to 1.
    @State private var pull: CGFloat = 0
    @State private var isFree = false
    @State private var breathe = false
    /// The last tenth the haptic fired on, so the ticks are evenly spaced in
    /// distance rather than in frames.
    @State private var lastTick = 0

    /// How far the finger has to travel. Long enough to be a pull rather than a
    /// swipe, short enough for one thumb on the smallest phone.
    private let distance: CGFloat = 150

    var body: some View {
        VStack(spacing: 16) {
            Image("sword1")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: height)
                .overlay { if !reduceMotion { edge } }
                .mask(
                    LinearGradient(colors: [.black, .black, .clear],
                                   startPoint: .top, endPoint: .bottom)
                )
                .offset(y: -pull * 90 + (breathe && !reduceMotion ? -4 : 0))
                .scaleEffect(isFree ? 1.04 : 1)
                .opacity(isFree ? 0 : 1)

            hint
        }
        .contentShape(.rect)
        .gesture(drag)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("The blade, in the stone"))
        .accessibilityHint(Text("Pull it free to begin"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { free() }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    /// The instruction, and it withdraws as the blade comes. Somebody who is
    /// already pulling does not need to be told to pull.
    private var hint: some View {
        VStack(spacing: 6) {
            Image(systemName: "chevron.up")
                .font(.system(size: 12, weight: .bold))
                .offset(y: breathe && !reduceMotion ? -3 : 0)

            Text("Pull the blade")
                .font(.footnote.weight(.semibold))
                .kerning(0.4)
        }
        .foregroundStyle(ForgeTheme.cream.opacity(0.75))
        .opacity(isFree ? 0 : 1 - Double(pull) * 1.4)
        .accessibilityHidden(true)
    }

    /// A hot line along the edge, brightening as the blade comes out. It is the
    /// same trick `BladePlate` uses and it is masked by the sprite for the same
    /// reason: an additive layer outside the silhouette is what makes a
    /// composited scene read as a cut-out.
    private var edge: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(0.5 * Double(pull)), location: 0.42),
                .init(color: .white.opacity(0.8 * Double(pull)), location: 0.5),
                .init(color: .clear, location: 0.58),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .rotationEffect(.degrees(-10))
        .blendMode(.screen)
        .allowsHitTesting(false)
        .mask {
            Image("sword1")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isFree else { return }
                let travelled = max(0, -value.translation.height)
                // Eased so the last third costs more than the first. A linear
                // drag reads as a slider; this reads as something heavy.
                let fraction = min(1, pow(travelled / distance, 1.35))
                pull = fraction
                tick(at: fraction)
                if fraction >= 1 { free() }
            }
            .onEnded { _ in
                guard !isFree else { return }
                // It goes back. Nothing is failed and nothing is said about it
                // — the same silence `SwordEngine.onSlipBack` keeps.
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { pull = 0 }
                lastTick = 0
            }
    }

    /// One tick per tenth of the way, so the resistance is felt as well as seen.
    private func tick(at fraction: CGFloat) {
        let step = Int(fraction * 10)
        guard step > lastTick else { return }
        lastTick = step
        ForgeHaptics.shared.frictionTick()
    }

    private func free() {
        guard !isFree else { return }
        isFree = true
        ForgeHaptics.shared.breakFree()
        withAnimation(.easeIn(duration: 0.3)) { pull = 1.9 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            onFree()
        }
    }
}

/// The blade, still, on the one beat that only shows it.
///
/// It used to carry a strike — a lift, a specular sweep down the edge, a settle
/// — because the beat under it said "every day you keep is a strike" and the
/// picture was doing none of the work the sentence was. That beat is now a real
/// pull (see `PullToBegin`), where the blade moves because a finger is moving
/// it, and an animation that plays *at* somebody two screens earlier would take
/// the edge off the one that answers them.
///
/// So what is left is what the opening screen always needed: a still picture,
/// faded out at its edges so it sits in the room rather than on the glass.
///
/// **Since 1.1 it is the sword in the stone** rather than the bare blade
/// sprite. The cold open says "every day you keep, the blade comes loose", and
/// a blade on its own is not in anything it could come loose from.
///
/// # Why it is `hero-plate` and not `hero`, and has no masks
///
/// It was `hero` — the plate the Proof Card is drawn from —
/// under two linear gradient masks, and on a phone it read as a picture in a
/// black box. Measured, the cause was not the edges: `hero`'s background is
/// near-black, 1 to 12 on 255, and the room behind it is not black where the
/// plate sits — `FirstRunAmbience` lights it warm from the upper left, 13 to 20
/// around the plate's top. Drawn over the room, the plate's black *covered*
/// that light, so the art was a darker patch in a lit room, and the two masks
/// gave the patch straight, rectangular contours (with Mach bands where their
/// linear ramps started). On an OLED the plate's 1-to-6 were lit pixels beside
/// unlit ones, so the box was there even where the room was pure black.
///
/// `hero-plate` treats the art's black as empty space rather than paint: a
/// matte of the stone and the sword, true zero in the empty space around them,
/// the ray and the dust kept as light over the room, and smooth fades where
/// that light reaches the frame. Nothing in the plate is darker than the room
/// except the stone and the sword themselves, and the plate's outer edge
/// differs from the room by under one level on 255. `docs/art/hero_plate.py`
/// makes it from `hero`, which is untouched.
///
/// The plate's light — the haze, the ray, the floor — fades in an oval round
/// the stone and the sword and is gone before the frame. Faded only at the
/// frame, it filled the plate and drew the rectangle the black no longer did.
private struct BladePlate: View {
    let height: CGFloat

    var body: some View {
        Image("hero-plate")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxHeight: height)
            .accessibilityHidden(true)
    }
}

/// One of the six, on offer. The whole row is the target, and selection reads
/// as weight rather than as a checkbox — this screen is a claim, not a form.
///
/// The meaning is on the row rather than behind an info button, and it is the
/// reason this is a 62pt row and not a chip. A six-way choice between single
/// nouns is a quiz: the difference between "Mental" and "Intellect" is not
/// self-evident to anybody who has not read `RitualCategory`, and getting it
/// wrong here quietly aims somebody's first week at the wrong thing.
/// Internal rather than private: the same row is the whole of the focus editor
/// on the Becoming tab. Two copies of a six-way choice would be two chances to
/// word the six differently, which is exactly the thing `RitualCategory.meaning`
/// exists to prevent.
struct DimensionChoiceRow: View {
    let dimension: RitualCategory
    let isChosen: Bool
    let isDimmed: Bool
    /// 62 by default. The first run's build beat sets it a little lower so
    /// all six fit above the button on a 17e; the meaning still has its line.
    var minHeight: CGFloat = 62
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            // At the accessibility sizes the glyph's column and the mark give
            // the name back the width it needs: left at their standard size
            // they hyphenated "Relationship" on a standard phone.
            HStack(spacing: typeSize.isAccessibilitySize ? 10 : 14) {
                // The dimension's own colour, never the accent. The row already
                // carries the accent twice — the tint behind it and the mark on
                // the right — and a third would be the screen shouting one word;
                // the glyph says *which* of the six this is, which is what the
                // six colours mean everywhere (`DimensionPalette`). Dimmed until
                // chosen, so the choice still reads at a glance.
                Image(systemName: dimension.symbol)
                    .font(.system(size: 18, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(dimension.color.opacity(isChosen ? 1 : 0.55))
                    .frame(width: typeSize.isAccessibilitySize ? 26 : 40, height: 40)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(dimension.label)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(dimension.meaning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(isChosen ? .palette : .monochrome)
                    .foregroundStyle(
                        isChosen ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary),
                        AnyShapeStyle(ForgeTheme.accent)
                    )
                    .contentTransition(.symbolEffect(.replace))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: minHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // A hairline and a mark, not a filled blue card.
        //
        // The cap on choosing was three, so at most three rows were ever tinted
        // and a solid accent fill read as emphasis. With the cap gone, six
        // chosen rows are six blue cards stacked on each other, which is the
        // accent doing scenery — the exact thing `ForgeTheme.accent` says it
        // must not do. A light tint under an accent border still reads as
        // chosen at a glance and survives all six being on.
        .glassEffect(
            isChosen
                ? .regular.tint(ForgeTheme.accent.opacity(0.12)).interactive()
                : .regular.interactive(),
            in: .rect(cornerRadius: ForgeTheme.Radius.control)
        )
        .overlay {
            if isChosen {
                RoundedRectangle(cornerRadius: ForgeTheme.Radius.control, style: .continuous)
                    .strokeBorder(ForgeTheme.accent.opacity(0.55), lineWidth: 1)
            }
        }
        .opacity(isDimmed ? 0.45 : 1)
        .animation(.easeOut(duration: 0.2), value: isDimmed)
        // The row animates itself. Its two callers used to wrap the whole
        // screen in a `withAnimation` on the focus, which also animated the
        // scroll view holding these — see `FirstRunView.build`. Scoped here it
        // is the tint and the border that cross-fade and nothing moves, which
        // is what "selecting a row" should look like at any number of rows.
        .animation(.forgeSelection, value: isChosen)
        .accessibilityLabel(Text("\(dimension.label). \(dimension.meaning)"))
        .accessibilityValue(Text(isChosen ? "Chosen" : "Not chosen"))
        .accessibilityHint(Text(isChosen ? "Double tap to remove" : "Double tap to choose"))
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }
}

/// The Shape, before there is one.
///
/// The same hexagon `ForgeShapeView` draws on the Becoming tab, with the
/// record swapped for the choice: a chosen dimension pushes its vertex out to
/// the edge and an unchosen one sits near the middle. It is the one place in
/// the product where the Shape can be explained without a paragraph — somebody
/// picking what they want to build watches the thing they are about to spend
/// weeks filling in take its outline under their finger.
///
/// **Not the real `ForgeShapeView`**, deliberately. That one draws scores and
/// is about the record; borrowing it here would put numbers on a screen where
/// nothing has happened yet, and a hexagon reading 0 on all six sides is the
/// app's first impression of a person being "you are nothing". This draws no
/// figures at all. It is a silhouette of an intention.
struct FocusHexagon: View {
    let chosen: Set<RitualCategory>

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dimensions: [RitualCategory] { RitualCategory.dimensions }

    /// How far out each vertex sits. The floor is what stops an empty choice
    /// collapsing to a dot: an unchosen dimension is still part of a person, it
    /// is simply not the part they are pointing at this month.
    ///
    /// **A chosen one reaches about half way, not the edge.** Choosing is an
    /// intention, not an achievement, and a vertex pinned to the outer ring
    /// on the first screen drew six choices as a finished shape — the one
    /// picture in the app that is supposed to be filled in by weeks of days.
    nonisolated static func reach(isChosen: Bool) -> Double {
        isChosen ? 0.55 : 0.22
    }

    private func reach(_ dimension: RitualCategory) -> Double {
        Self.reach(isChosen: chosen.contains(dimension))
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = side / 2 - 26
            let centre = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let fractions = dimensions.map(reach)

            ZStack {
                // The instrument is drawn in the room's own colour rather than
                // in the accent. A hexagon whose every line is blue makes the
                // accent scenery, and the accent's one job here is to say which
                // part of the six the finger has claimed — see `ForgeTheme`.
                polygon(radius: radius, centre: centre,
                        fractions: dimensions.map { _ in 1.0 })
                    .stroke(ForgeTheme.cream.opacity(0.20), lineWidth: 1)

                ForEach(dimensions.indices, id: \.self) { index in
                    Path { path in
                        path.move(to: centre)
                        path.addLine(to: point(index, radius: radius, centre: centre))
                    }
                    .stroke(ForgeTheme.cream.opacity(0.10), lineWidth: 0.5)
                }

                let filled = polygon(radius: radius, centre: centre, fractions: fractions)
                filled.fill(
                    RadialGradient(
                        colors: [
                            ForgeTheme.accent.opacity(0.42),
                            ForgeTheme.accent.opacity(0.12),
                        ],
                        center: .center, startRadius: 0, endRadius: radius
                    )
                )
                filled
                    .stroke(ForgeTheme.accent, lineWidth: 1.5)
                    .shadow(color: ForgeTheme.accent.opacity(0.45), radius: 8)

                ForEach(dimensions.indices, id: \.self) { index in
                    let isChosen = chosen.contains(dimensions[index])
                    Image(systemName: dimensions[index].symbol)
                        .font(.system(size: 11, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(
                            isChosen
                                ? AnyShapeStyle(dimensions[index].color)
                                : AnyShapeStyle(.tertiary)
                        )
                        .position(point(index, radius: radius + 16, centre: centre))
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: fractions)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func point(_ index: Int, radius: CGFloat, centre: CGPoint, at fraction: Double = 1) -> CGPoint {
        let angle = (Double(index) / Double(dimensions.count)) * 2 * .pi - .pi / 2
        return CGPoint(
            x: centre.x + cos(angle) * radius * fraction,
            y: centre.y + sin(angle) * radius * fraction
        )
    }

    private func polygon(radius: CGFloat, centre: CGPoint, fractions: [Double]) -> Path {
        var path = Path()
        for (index, fraction) in fractions.enumerated() {
            let p = point(index, radius: radius, centre: centre, at: fraction)
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - The closing beat

/// What comes after the blade is out, and the last thing the first run does.
///
/// One line to say the deal has changed, and one offer of a reminder. The offer
/// is made here and nowhere else, and it is the only place in Forge that raises
/// a notification prompt: a blade has just come out of the stone, so the thing
/// being offered is obvious. A no is taken as final and never asked again.
struct FirstRunClosingView: View {
    /// How much of today is still on the list, so the line can name it.
    var remaining: Int = 0
    /// The first thing on the day, so the primer's examples are the user's own.
    var firstActivity: ScheduledActivity? = nil
    /// The hour the day would open on, in minutes past midnight.
    var openingMinute: Int = 6 * 60 + 30
    /// Handed straight to the primer, which draws the scheduler's own sentences
    /// from it — see `NotificationPrimerView`.
    var notificationState: ForgeNotificationState
    /// What they said they wanted to build, if anything. The headline reads
    /// it; the line names what of it is on tomorrow.
    var focus: [RitualCategory] = []
    /// The part of `focus` tomorrow has something for
    /// (`ForgeViewModel.focusTomorrow`), which is all the line may promise.
    /// Nil is all of `focus` — what a plan with everything every day gives.
    var tomorrow: [RitualCategory]? = nil
    let onFinish: () -> Void

    @State private var isAsking = false
    @State private var showPrimer = false

    /// The headline names the act rather than the count.
    ///
    /// "That's one" was a fact about a checkbox. The sequence has just spent
    /// ninety seconds establishing that a day is what you strike the blade
    /// with, so the last thing it says is the same claim the metaphor screen
    /// made, now with one day actually behind it.
    ///
    /// Internal rather than private so the copy can be checked without a
    /// screen. These two sentences are the last thing the first run says, and a
    /// silent regression here is one nobody would notice until a user did.
    var headline: String {
        focus.isEmpty ? "That's one." : "That's one strike."
    }

    /// The one sentence that has to correct the thing a first run gets wrong.
    ///
    /// It says what is left of today, and what tomorrow holds. In 1.0 the three
    /// chosen activities were pinned to the day they were chosen on, so
    /// tomorrow was a day to plan ("Tomorrow, you choose again"). Since 1.1 the
    /// plan is a standing week — see `ForgeViewModel.adoptPlan` — so tomorrow
    /// is the same plan again, and the line says so rather than promising a
    /// choice the app has already made with them. It names only what of the
    /// focus tomorrow actually has something for (`tomorrow`).
    ///
    /// **The two halves are in that order on purpose.** What is left of today
    /// comes first, because the blade being out is about to make somebody think
    /// the day is over — and it is not. The panel says the same thing when they
    /// land on it; see `ForgeTabView.bankedLine`.
    var line: String {
        let tomorrow = named.map { "Tomorrow, more \($0)." } ?? "Tomorrow, the same plan again."
        guard remaining > 0 else { return tomorrow }
        return "\(ForgeCount.spelled(remaining)) more, today. \(tomorrow)"
    }

    /// What they chose and tomorrow holds, said the way a person would say it.
    private var named: String? {
        let names = (tomorrow ?? focus).map { $0.label.lowercased() }
        switch names.count {
        case 0: return nil
        case 1: return names[0]
        default:
            var rest = names
            let last = rest.removeLast()
            return "\(rest.joined(separator: ", ")) and \(last)"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Text(headline)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)

            Text(line)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .padding(.horizontal, 32)

            Spacer(minLength: 0)

            // Opens the explanation rather than the system prompt. The prompt is
            // one line of Apple's words shown once ever, and an app that raises
            // it cold is asking for a decision nobody has the information to
            // make — see `NotificationPrimerView`, which shows the actual
            // notifications before iOS is asked anything.
            Button {
                guard !isAsking else { return }
                isAsking = true
                showPrimer = true
            } label: {
                Text("Remind me each day")
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

            // A decline is the end of it. Nothing asks again.
            Button("No reminder") {
                ForgeNotifications.shared.declineReminders()
                finish()
            }
                .font(.footnote.weight(.medium))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.top, 16)
                .padding(.bottom, 8)
        }
        .padding(.vertical, 48)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Deliberately opaque rather than a dimmed scrim. The blade is out
        // behind this and the eye would go straight back to it; this beat is
        // three seconds long and it should have the screen.
        .background(ForgeTheme.bg.ignoresSafeArea())
        .sheet(isPresented: $showPrimer) {
            NotificationPrimerView(
                firstActivity: firstActivity,
                openingMinute: openingMinute,
                state: notificationState,
                // Either answer ends the first run. The primer has already
                // written down which it was.
                onDecision: { _ in finish() }
            )
        }
        // Backing out of the primer without answering leaves the beat as it
        // was, rather than stranding a disabled button.
        .onChange(of: showPrimer) { _, showing in
            if !showing { isAsking = false }
        }
    }

    private func finish() {
        ForgeHaptics.shared.tap()
        onFinish()
    }
}

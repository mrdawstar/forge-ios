import SwiftUI

/// Plan: what Forge would change about your week, and why.
///
/// # What this screen used to be, and why it is not that any more
///
/// It was "Forge AI": a heading, a text field, three example sentences, and a
/// button. Everything about it was well built and the shape of it was wrong.
/// It asked a stranger to type a request before the app had said a single
/// thing — and then, for most of what anybody would actually type, answered
/// *"the model is not connected"*. A screen that puts the work on the user and
/// then fails is worse than no screen.
///
/// So the order is inverted. Forge speaks first. It arrives already holding
/// three or four **moves** worked out from the record — a clash on Tuesday, four
/// activities with no hour on them, the part of the Shape that is getting
/// nothing, the thing asked for eleven times and kept four — each of which
/// states its own arithmetic and applies as a reviewable diff. The typing field
/// is still here, at the bottom, for the person who already knows what they
/// want. It is the shortcut now rather than the front door.
///
/// # Why every move is still a proposal
///
/// Nothing on this screen writes anything. A move is a `SchedulePlan`, it is
/// read line by line on a second screen, and `ForgeViewModel.apply` is reached
/// only from a button that says how many changes it is about to make. That rule
/// predates the planner and survives it unchanged: a thing that can rearrange a
/// routine somebody spent months building without a confirmation is a thing
/// nobody opens twice.
///
/// # What is real today
///
/// All of it, and none of it needs a network. `DayPlanner` is arithmetic over
/// the user's own week, Shape and history. The free-text field goes to
/// `ForgeAI`, which is `LocalForgeAI` unless a model is configured — it
/// genuinely lays a week out around stated hours, spreads "three times a week"
/// across days that are not consecutive, shifts everything by an offset and
/// moves one activity to another day, and refuses honestly at anything wider
/// rather than inventing.
///
/// # Forge Pro
///
/// **The free-text field is AI; the moves are not.** Everything Forge works
/// out from the record on its own goes with the week it plans. Asking in your
/// own words is one of the AI features (DIRECTION_1_1 §9) — a subscription or
/// a free week, not a founder — and without it the field is a locked row that
/// opens the paywall. See `PremiumGate`.
struct PlanSheet: View {
    @Bindable var vm: ForgeViewModel
    var brief: AIBrief
    var ai: ForgeAI
    /// Called once changes have actually landed, so the app can show the week
    /// they just built rather than leaving them on an empty composer.
    var onApplied: () -> Void = {}

    /// Opened on one move's review rather than on the list — Becoming's Next
    /// move, which has already said what the move is and why. Everything about
    /// consent is unchanged: the changes, the week as it would be, and one
    /// button that says how many changes it makes. Back is the full list.
    init(
        vm: ForgeViewModel, brief: AIBrief, ai: ForgeAI,
        opening move: DayPlanner.Move? = nil,
        onApplied: @escaping () -> Void = {}
    ) {
        self.vm = vm
        self.brief = brief
        self.ai = ai
        self.onApplied = onApplied
        _stage = State(initialValue: move.map { .proposal($0.plan) } ?? .offering)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(ForgeStore.self) private var store: ForgeStore?
    @Environment(AIConsentStore.self) private var consent: AIConsentStore?
    /// The disclosure, raised by "Work it out" the first time a request would
    /// actually leave the phone. See `AIConsentStore`.
    @State private var isAskingConsent = false
    @State private var paywallDoor: ForgeTelemetry.PaywallDoor?

    private var canAskInWords: Bool {
        !PremiumGate.isLocked(.planInWords, for: store?.access ?? .unknown)
    }

    @State private var request = ""
    @State private var stage: Stage = .offering
    @State private var failure: String?
    /// The moves, computed once when the sheet opens.
    ///
    /// Held rather than recomputed in `body`, and for a reason beyond cost:
    /// every `SchedulePlan` carries a fresh `UUID`, so a computed property
    /// would hand SwiftUI a different value on every redraw and the list would
    /// animate itself apart under a finger that had not moved.
    @State private var moves: [DayPlanner.Move] = []
    @State private var isReading = true
    @FocusState private var isTyping: Bool

    private enum Stage: Equatable {
        /// What Forge has to say, unasked.
        case offering
        case working
        case proposal(SchedulePlan)
    }

    /// The three things people actually type, in the order they think of them.
    ///
    /// Shown rather than described, because "you can ask it anything" is the
    /// least useful sentence an empty text field can be given — and because these
    /// three are, precisely, the three shapes of request that work today.
    private let examples = [
        "I work 9 to 17, want to train three times and read every evening",
        "Move my workout to Wednesday",
        "Everything an hour later",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch stage {
                    case .offering: offering
                    case .working: working
                    case .proposal(let plan): proposal(plan)
                    }
                }
                .padding(.horizontal, ForgeTheme.Space.gutter)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { footer }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(ForgeTheme.Radius.sheet)
        .presentationDragIndicator(.visible)
        .paywall($paywallDoor)
        // Asked only when the model is reachable and nobody has answered yet.
        // Either answer then runs the request: Allow reaches the model, Not now
        // is answered by `LocalForgeAI` exactly as before — `RemoteForgeAI`
        // reads the stored answer before it reads anything else.
        .aiConsent(
            isPresented: $isAskingConsent,
            briefs: AIDisclosureBriefs(brief: brief, readingBrief: brief)
        ) { _ in
            Task { await propose() }
        }
        .task {
            guard moves.isEmpty else { return }
            let computed = DayPlanner.moves(vm.planFacts(wakeMinutes: brief.wakeMinutes))
            // The arithmetic is instant and instant is the wrong feeling. See
            // `reading` — the beat is for legibility, not for work, and it is
            // short enough that nobody waits on it.
            try? await Task.sleep(for: .milliseconds(320))
            moves = computed
            withAnimation(.forgeRow) { isReading = false }
        }
    }

    // MARK: - What Forge has to say

    private var offering: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(headline)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .padding(.bottom, 5)

            Text(subhead)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

            if isReading {
                reading
            } else if moves.isEmpty {
                nothingToChange
            } else {
                ForEach(moves) { move in
                    moveCard(move)
                        .padding(.bottom, ForgeTheme.Space.inner)
                }
            }

            askInWords

            if let failure {
                Text(failure)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
        }
    }

    private var headline: String {
        if isReading { return "Reading your week." }
        if moves.isEmpty { return "Your week holds together." }
        return moves.count == 1 ? "One thing worth changing." : "\(ForgeCount.spelled(moves.count)) things worth changing."
    }

    private var subhead: String {
        if isReading { return "Your activities, your last four weeks, and the six parts of your Shape." }
        if moves.isEmpty {
            return "Nothing clashes, everything has an hour, and no part of you is being left out. Ask for something specific below if you want to change it anyway."
        }
        return "Worked out on this phone from what you already keep. Nothing changes until you say so."
    }

    /// The beat between opening the sheet and the moves arriving.
    ///
    /// A third of a second, and it is deliberate rather than latency. The
    /// arithmetic finishes before the sheet has finished presenting, and a
    /// screen already covered in conclusions at the moment it opens reads as
    /// canned — the conclusions look printed rather than reached. The line names
    /// what is actually being read, which is the part that makes the beat
    /// honest: it is a short pause in front of a true sentence, not a spinner
    /// pretending to work.
    private var reading: some View {
        HStack(spacing: ForgeTheme.Space.inner) {
            ProgressView()
            Text("Your week, four weeks of record, six dimensions")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 28)
    }

    /// The empty answer, and it must not read as a failure.
    ///
    /// A planner with nothing to say is the *good* outcome — it means the week
    /// is arranged, being kept, and pointed at every part of somebody. Saying so
    /// plainly is worth more than manufacturing a fourth-best suggestion, which
    /// is the moment a calm product becomes a nagging one.
    private var nothingToChange: some View {
        HStack(alignment: .top, spacing: ForgeTheme.Space.inner) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 15, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(ForgeTheme.accent)
                .frame(width: 30, height: 30)

            Text("Forge looks for four things: a clash, an activity with no hour, a part of you with nothing pointed at it, and something asked for far more often than it is kept. None of them is here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ForgeTheme.Space.row)
        .forgeCard(radius: ForgeTheme.Radius.card)
        .padding(.bottom, ForgeTheme.Space.section)
    }

    /// One move: what it would do, why, and how many changes it is.
    ///
    /// The reason is set at the same size as the title rather than as a caption
    /// under it. It is not supporting text — it is the entire claim the card is
    /// making, and burying it in tertiary grey would turn a piece of evidence
    /// back into a recommendation.
    private func moveCard(_ move: DayPlanner.Move) -> some View {
        Button {
            ForgeHaptics.shared.tap()
            isTyping = false
            withAnimation(.forgeRow) { stage = .proposal(move.plan) }
        } label: {
            VStack(alignment: .leading, spacing: ForgeTheme.Space.tight) {
                HStack(spacing: ForgeTheme.Space.inner) {
                    Image(systemName: move.kind.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(ForgeTheme.accent)
                        .frame(width: 26, height: 26)

                    Text(move.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                Text(move.reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(move.plan.changes.count == 1
                     ? "ONE CHANGE"
                     : "\(ForgeCount.spelled(move.plan.changes.count).uppercased()) CHANGES")
                    .font(ForgeTheme.overline)
                    .kerning(ForgeTheme.overlineKerning)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .padding(ForgeTheme.Space.row)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .forgeInteractiveCard(radius: ForgeTheme.Radius.card)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(move.title). \(move.reason)"))
        .accessibilityHint("Shows every change before anything moves")
    }

    // MARK: - Or say it yourself

    /// The old front door, now the back one.
    ///
    /// It is kept because it is the only route to the two things the moves above
    /// cannot know: an outside commitment ("I work 9 to 17") and a decision
    /// somebody has already made ("move my workout to Wednesday"). Neither is
    /// in the record, so no amount of reading it would produce them.
    @ViewBuilder
    private var askInWords: some View {
        if canAskInWords {
            wordsField
        } else {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading("Or ask for something")
                    .padding(.bottom, ForgeTheme.Space.inner)
                ProLockedRow(feature: .planInWords) { paywallDoor = .ai }
            }
            .padding(.top, ForgeTheme.Space.tight)
        }
    }

    private var wordsField: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(
                "Or ask for something",
                detail: "Hours you cannot move, and what you want fitted around them"
            )
            .padding(.bottom, ForgeTheme.Space.inner)

            TextField("Plan my week", text: $request, axis: .vertical)
                .lineLimit(2...5)
                .font(.body)
                .focused($isTyping)
                .padding(16)
                .forgeCard(radius: ForgeTheme.Radius.control)
                .padding(.bottom, 8)

            ForEach(examples, id: \.self) { example in
                Button {
                    ForgeHaptics.shared.tap()
                    request = example
                    isTyping = false
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .frame(width: 16)
                        Text(example)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 9)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, ForgeTheme.Space.tight)
    }

    private var working: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Working through your week")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
    }

    // MARK: - The proposal

    /// What would change, and what the week becomes.
    ///
    /// The changes come first and the resulting week second, because the changes
    /// are what somebody is being asked to agree to — a preview on its own is a
    /// picture with no accountability in it, and it is impossible to tell from
    /// one what the app is about to overwrite.
    @ViewBuilder
    private func proposal(_ plan: SchedulePlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(plan.summary)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .padding(.bottom, 20)

            overline(
                plan.changes.count == 1
                    ? "ONE CHANGE"
                    : "\(ForgeCount.spelled(plan.changes.count).uppercased()) CHANGES"
            )

            ForEach(plan.changes) { change in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: change.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18)

                    Text(change.activityName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    Spacer(minLength: 10)

                    Text(change.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 9)
                .accessibilityElement(children: .combine)
            }

            overline("YOUR WEEK")
                .padding(.top, 22)

            weekPreview(plan)

            // Never omitted. See the note at the top of this file — the app does
            // not get to imply a model wrote something the phone worked out.
            if !plan.isModelWritten {
                Text("Worked out on this phone from the week you already keep. Nothing was sent anywhere.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 22)
            }
        }
    }

    /// The seven days, as they would be. Days that would hold nothing are drawn
    /// as nothing rather than skipped — an empty Sunday is a fact about the plan
    /// and quietly omitting it would make the week look fuller than it is.
    private func weekPreview(_ plan: SchedulePlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(plan.week(onto: vm.scheduledActivities)) { day in
                HStack(alignment: .top, spacing: 14) {
                    Text(day.label.uppercased())
                        .font(ForgeTheme.label(10))
                        .kerning(1.2)
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .leading)
                        .padding(.top, 3)

                    if day.items.isEmpty {
                        Text("—")
                            .font(.footnote)
                            .foregroundStyle(.quaternary)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(day.items) { item in
                                HStack(spacing: 10) {
                                    Text(item.startMinute.map(ClockMinute.label) ?? "—")
                                        .font(ForgeTheme.mono(11))
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 58, alignment: .leading)
                                    Text(item.name)
                                        .font(.footnote)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func overline(_ text: String) -> some View {
        Text(text)
            .font(ForgeTheme.overline)
            .kerning(ForgeTheme.overlineKerning)
            .foregroundStyle(.tertiary)
            .padding(.bottom, 4)
    }

    // MARK: - The one bar at the foot

    /// Pinned rather than at the end of the scroll.
    ///
    /// A proposal can be twenty lines long, and burying "Apply" under all of it
    /// means the longer the plan the harder it is to accept — which is exactly
    /// backwards. It also means "Discard" is never more than a thumb away, which
    /// is what makes reading the thing feel safe.
    ///
    /// On the offering screen the bar is only there when something has been
    /// typed. A permanent primary button under a list of cards would compete
    /// with every one of them, and a stranger cannot tell which of the two the
    /// screen wants — so the field's button appears with the field's content.
    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 8) {
            switch stage {
            case .offering, .working:
                if canAskInWords,
                   !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || stage == .working
                {
                    Button {
                        ForgeHaptics.shared.tap()
                        isTyping = false
                        if needsConsent {
                            isAskingConsent = true
                        } else {
                            Task { await propose() }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Work it out")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.roundedRectangle(radius: ForgeTheme.Radius.control))
                    .disabled(stage == .working)
                    .transition(.opacity)
                }

            case .proposal(let plan):
                Button {
                    apply(plan)
                } label: {
                    Text(plan.changes.count == 1 ? "Make this change" : "Apply \(plan.changes.count) changes")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: ForgeTheme.Radius.control))

                Button("Back") {
                    ForgeHaptics.shared.tap()
                    withAnimation(.forgeRow) { stage = .offering }
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(height: 34)
            }
        }
        .padding(.horizontal, ForgeTheme.Space.gutter)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
        .animation(.forgeFade, value: request.isEmpty)
    }

    // MARK: - Doing it

    /// Whether pressing "Work it out" must first ask. Only in a build where
    /// the model is reachable — never in this one, where `ai.isConnected` is
    /// false and every request is answered on the phone.
    private var needsConsent: Bool {
        ai.isConnected && !(consent?.hasDecided ?? false)
    }

    private func propose() async {
        guard stage != .working, canAskInWords else { return }
        withAnimation(.forgeRow) { stage = .working }
        failure = nil

        let asked = request.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let plan = try await ai.plan(brief: brief, request: asked)
            withAnimation(.forgeRow) { stage = .proposal(plan) }
        } catch let error as ForgeAIError {
            failure = error.message
            withAnimation(.forgeRow) { stage = .offering }
        } catch {
            failure = ForgeAIError.failed.message
            withAnimation(.forgeRow) { stage = .offering }
        }
    }

    /// The one place anything is actually written.
    ///
    /// Everything before this is a proposal on a screen. Consent happens here
    /// and nowhere else, which is what makes the rest of the flow safe to build
    /// out — a planner that could rearrange months of somebody's routine without
    /// a confirmation is one nobody would open twice.
    private func apply(_ plan: SchedulePlan) {
        let applied = vm.apply(plan)
        guard applied > 0 else {
            failure = ForgeAIError.noChange.message
            withAnimation(.forgeRow) { stage = .offering }
            return
        }
        ForgeHaptics.shared.ritualVerified()
        onApplied()
        dismiss()
    }
}

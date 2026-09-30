import SwiftUI

// MARK: - The words

/// The first run's words, kept out of the views so they can be tested.
///
/// Every line here was read against the voice rules: no exclamation marks, no
/// congratulation, nothing about loss, and nothing that says "will". The
/// numbers in prose are words; the numbers that are scores are digits.
enum FirstRunCopy {
    static let coldOpenTitle = "Every day you keep, the blade comes loose."
    static let coldOpenLine = "You pull it free."
    static let coldOpenButton = "Begin"

    /// Above the first question only. It says what the answers are for and
    /// when they stop being the whole story, before anybody is asked anything.
    static let questionsCaption = "Seven questions. Your starting stats come from your answers. From tomorrow, from what you do."

    /// Under "What do you want to build?" while the choice is still the one the
    /// answers suggested.
    static let suggested = "Suggested from your answers."

    static let drawingTitle = "Drawing your starting shape."

    static let scienceTitle = "Why it works"

    static let planTitle = "Your plan"
    static let planSubtitle = "Every day, at these times. Tap one to swap it or change its time."

    /// Three findings, each ending on the part of Forge it explains. Only the
    /// papers DIRECTION_1_1 lists may be cited, paraphrased and never
    /// overstated — `FirstRunTests` holds the list.
    static let findings: [Finding] = [
        Finding(
            title: "Sixty-six days",
            body: "In one study, new daily habits took a median of sixty-six days to become automatic. Missing one day along the way did not materially affect the process.",
            mechanic: "Arcs are built around it.",
            citation: "Lally, van Jaarsveld, Potts & Wardle (2010). European Journal of Social Psychology 40(6), 998–1009."
        ),
        Finding(
            title: "Decide when",
            body: "Across ninety-four studies, if-then plans \u{2014} deciding in advance when and where to act \u{2014} had a medium-to-large effect on reaching goals.",
            mechanic: "Every activity gets a time.",
            citation: "Gollwitzer & Sheeran (2006). Advances in Experimental Social Psychology 38, 69–119."
        ),
        Finding(
            title: "Keep a record",
            body: "Across 138 studies, monitoring progress improved goal attainment, more so when the progress was physically recorded or made public.",
            mechanic: "That's why you pull the sword.",
            citation: "Harkin et al. (2016). Psychological Bulletin 142(2), 198–229."
        ),
    ]

    struct Finding: Equatable, Sendable {
        let title: String
        let body: String
        let mechanic: String
        let citation: String
    }
}

// MARK: - The bar along the top

/// How far through the first run somebody is, from the first question on.
///
/// A line rather than a count. "Step 4 of 13" is a form; a bar is a
/// sequence, and it says the one thing somebody wants to know — that it ends.
struct OnboardingProgress: View {
    /// 0…1.
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(ForgeTheme.cream.opacity(0.14))
                Capsule()
                    .fill(ForgeTheme.cream.opacity(0.85))
                    .frame(width: max(4, proxy.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: 3)
        .animation(.smooth(duration: 0.4), value: value)
        .accessibilityElement()
        .accessibilityLabel(Text("Progress"))
        .accessibilityValue(Text("\(Int((min(1, max(0, value)) * 100).rounded())) per cent"))
    }
}

/// The row above every beat from the first question on: back where going back
/// means something, the bar, and a way out where the flow was opened from
/// somewhere else.
struct OnboardingTopBar: View {
    let progress: Double
    var onBack: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            corner(symbol: "chevron.left", label: "Back", action: onBack)
            OnboardingProgress(value: progress)
            corner(symbol: "xmark", label: "Close", action: onClose)
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
    }

    /// The same width whether it is there or not, so the bar never moves.
    private func corner(symbol: String, label: String, action: (() -> Void)?) -> some View {
        Button {
            ForgeHaptics.shared.tap()
            action?()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(action == nil ? 0 : 1)
        .disabled(action == nil)
        .accessibilityHidden(action == nil)
        .accessibilityLabel(Text(label))
    }
}

// MARK: - One question

/// One question, four answers, one tap.
///
/// **No Continue button.** Tapping an answer records it and the next question
/// arrives, which is the whole of what makes seven questions take under a
/// minute. The chosen row lights before it goes, so the tap is seen to land.
///
/// Left-aligned where every other beat is centred: a question read as a
/// sentence with its answers under it is a list somebody scans top to bottom,
/// and at the accessibility sizes a centred four-line question is a shape
/// rather than a sentence.
struct QuestionBeat: View {
    let question: Assessment.Question
    /// What was answered before, if somebody came back to it.
    let selected: Int?
    let isFirst: Bool
    let onAnswer: (Int) -> Void

    /// The answer tapped on this appearance. Only the first tap counts, so two
    /// quick taps cannot record one answer and advance past the next question.
    @State private var picked: Int?
    @State private var scrollHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)

                if isFirst {
                    Text(FirstRunCopy.questionsCaption)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 16)
                }

                Text(question.prompt)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 28)

                VStack(spacing: 10) {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                        AnswerRow(label: option.label, isSelected: (picked ?? selected) == index) {
                            guard picked == nil else { return }
                            picked = index
                            ForgeHaptics.shared.answered()
                            onAnswer(index)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: scrollHeight, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scrollHeight = $0 }
    }
}

/// One answer. The whole row is the target, and a chosen one reads the way a
/// chosen dimension does — see `DimensionChoiceRow` — so the sequence has one
/// idea of what "chosen" looks like.
private struct AnswerRow: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(isSelected ? .palette : .monochrome)
                    .foregroundStyle(
                        isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary),
                        AnyShapeStyle(ForgeTheme.accent)
                    )
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected
                ? .regular.tint(ForgeTheme.accent.opacity(0.12)).interactive()
                : .regular.interactive(),
            in: .rect(cornerRadius: ForgeTheme.Radius.control)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: ForgeTheme.Radius.control, style: .continuous)
                    .strokeBorder(ForgeTheme.accent.opacity(0.55), lineWidth: 1)
            }
        }
        .animation(.forgeSelection, value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - The shape drawing itself

/// The starting shape, drawn from the answers: about two and a half seconds,
/// and a tap anywhere skips it.
///
/// The polygon grows out of the centre to the six baselines while the vertices
/// come on one at a time in their own colours, each with a haptic a little
/// stronger than the last. It is the one moment the sequence spends on showing
/// rather than telling, and it is short because it is only a transition: the
/// numbers themselves are on the next screen.
///
/// Under it, at most one line — a gain, chosen by the screen-time answer
/// (`Assessment.gainLine`). Never a fear number.
///
/// Under Reduce Motion the finished shape fades in whole and holds for the
/// same time; nothing grows and nothing lights in sequence.
struct DrawingBeat: View {
    let assessment: Assessment
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var values: [Double] = Array(repeating: 0, count: 6)
    @State private var lit: Set<RitualCategory> = []
    @State private var isFinished = false

    /// How long the beat holds before it moves on by itself.
    static let length: Duration = .milliseconds(2400)

    private var targets: [Double] {
        RitualCategory.dimensions.map { Double(assessment.baseline(for: $0) ?? 0) / 100 }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            StatHexagon(
                values: values,
                lit: lit,
                animation: reduceMotion ? nil : .easeOut(duration: 1.9)
            )
            .frame(maxWidth: typeSize.isAccessibilitySize ? 200 : 290)
            .padding(.horizontal, 32)
            .accessibilityHidden(true)

            Text(FirstRunCopy.drawingTitle)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .padding(.top, 28)

            if let line = assessment.gainLine {
                Text(line)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 40)
                    .padding(.top, 10)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .onTapGesture { finish() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Double tap to continue"))
        .accessibilityAction { finish() }
        .task { await draw() }
    }

    private func draw() async {
        let started = ContinuousClock.now
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.35)) {
                values = targets
                lit = Set(RitualCategory.dimensions)
            }
        } else {
            // The polygon travels on the hexagon's own animation; the vertices
            // are lit on a clock beside it, so the two finish together.
            values = targets
            for (step, dimension) in RitualCategory.dimensions.enumerated() {
                try? await Task.sleep(for: .milliseconds(step == 0 ? 150 : 300))
                guard !Task.isCancelled, !isFinished else { return }
                lit.insert(dimension)
                ForgeHaptics.shared.shapeRising(step: step, of: RitualCategory.dimensions.count)
            }
        }
        let elapsed = ContinuousClock.now - started
        if elapsed < Self.length {
            try? await Task.sleep(for: Self.length - elapsed)
        }
        guard !Task.isCancelled else { return }
        finish()
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        onFinish()
    }
}

// MARK: - The assessment on its own

/// The seven questions and the drawing, and nothing else — for every install
/// that has no assessment, which is every 1.0 install.
///
/// Opened from the Becoming tab's "Take the one-minute assessment" card and
/// closed by itself once the shape has drawn. It writes exactly what the first
/// run writes (`ForgeViewModel.assessment`) and sends the same
/// `assessment_completed`, with no answers in it. Nothing else changes: the
/// day, the focus and the record are untouched, and the hexagon on the tab it
/// returns to is readable from that moment.
struct AssessmentSheet: View {
    var forge: ForgeViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var index = 0
    @State private var answers: [Assessment.Question: Int] = [:]
    @State private var taken: Assessment?

    private let questions = Assessment.Question.allCases

    private var progress: Double {
        let steps = Double(questions.count + 1)
        return taken == nil ? Double(index + 1) / steps : 1
    }

    var body: some View {
        ZStack {
            FirstRunAmbience()

            VStack(spacing: 0) {
                OnboardingTopBar(
                    progress: progress,
                    onBack: taken == nil ? back : nil,
                    onClose: taken == nil ? { dismiss() } : nil
                )

                ZStack {
                    if let taken {
                        DrawingBeat(assessment: taken) { dismiss() }
                            .transition(.opacity)
                    } else {
                        QuestionBeat(
                            question: questions[index],
                            selected: answers[questions[index]],
                            isFirst: index == 0
                        ) { choice in
                            answer(choice)
                        }
                        .id(index)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .opacity.combined(with: .offset(x: 24)),
                            removal: .opacity
                        ))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.bottom, 16)
        }
        .preferredColorScheme(.dark)
    }

    private func back() {
        guard index > 0 else {
            dismiss()
            return
        }
        withAnimation(.smooth(duration: 0.35)) { index -= 1 }
    }

    private func answer(_ choice: Int) {
        let question = questions[index]
        answers[question] = choice
        Task { @MainActor in
            // Long enough to see the answer land, short enough not to wait.
            try? await Task.sleep(for: .milliseconds(220))
            if index + 1 < questions.count {
                withAnimation(.smooth(duration: 0.35)) { index += 1 }
                return
            }
            let assessment = Assessment(day: forge.progress.currentDay, answers: answers)
            forge.assessment = assessment
            ForgeTelemetry.send(.assessmentCompleted)
            withAnimation(.easeInOut(duration: 0.4)) { taken = assessment }
        }
    }
}

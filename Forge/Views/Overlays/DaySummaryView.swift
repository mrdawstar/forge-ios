import SwiftUI

/// What the day is worth, said once.
///
/// It arrives after the blade has settled and it leaves on its own. There is no
/// button to press, nothing to share, nothing to rate and no dashboard behind
/// it — the point of the sentence is that it was earned rather than presented,
/// and a screen you have to dismiss is a screen asking for something back.
///
/// A tap takes it away early, because somebody who has read it should not have
/// to wait out an animation to get on with their day.
struct DaySummaryView: View {
    let summary: DaySummary
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Long enough to read twice without hurrying, short enough that nobody
    /// waits for it. The quote is a second thing to read, so a day that has one
    /// holds a little longer.
    private static let holds: Duration = .seconds(3.2)
    private static let holdsWithQuote: Duration = .seconds(5.4)

    /// How long after the count the words arrive.
    ///
    /// The whole of the "I earned this" beat, and it is a pause rather than an
    /// effect. The count lands, the screen sits still for most of a second, and
    /// only then does somebody else's sentence come up underneath it. Playing
    /// them together would make the quotation part of the furniture; making it
    /// wait makes it a response.
    private static let quoteDelay: Duration = .milliseconds(900)

    @State private var shown = false
    @State private var quoteShown = false

    var body: some View {
        ZStack {
            // Fully opaque, like the first run's closing beat and for the same
            // reason: the blade is behind this and the eye would go straight
            // back to it. A near-opaque scrim also let the freed panel's own
            // copy of this sentence read faintly through the overlay, which put
            // the same line on screen twice.
            ForgeTheme.bg.ignoresSafeArea()

            VStack(spacing: 12) {
                Text(summary.headline)
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(summary.line)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let quote = summary.quote {
                    quoteBlock(quote)
                        .opacity(quoteShown ? 1 : 0)
                        .offset(y: quoteShown ? 0 : (reduceMotion ? 0 : 10))
                        .padding(.top, 22)
                }
            }
            .padding(.horizontal, 40)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : (reduceMotion ? 0 : 12))
        }
        .contentShape(.rect)
        .onTapGesture { onFinished() }
        // The whole thing is one announcement, and VoiceOver should read it
        // without the user having to find two labels inside a screen that is
        // about to take itself away.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(spoken))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Double tap to continue"))
        .task { await run() }
    }

    /// The line, and the name under it.
    ///
    /// Attribution is not a design detail here, it is the licence to show the
    /// sentence at all — see `AttributedQuote`. So it is drawn as part of the
    /// quotation rather than as a caption that could be laid out away.
    private func quoteBlock(_ quote: AttributedQuote) -> some View {
        VStack(spacing: 10) {
            // A hairline instead of quotation marks. The rule says "somebody
            // else is speaking now" without putting punctuation the size of a
            // headline on the most restrained screen in the app.
            Rectangle()
                .fill(.tertiary)
                .frame(width: 26, height: 0.5)

            Text(quote.text)
                .font(.system(size: 17, weight: .regular, design: .serif))
                .italic()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(quote.source.uppercased())
                .font(ForgeTheme.label(9.5))
                .kerning(1.4)
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.secondary)
    }

    private var spoken: String {
        var parts = [summary.headline, summary.line]
        if let quote = summary.quote {
            parts.append("\(quote.text) — \(quote.source)")
        }
        return parts.joined(separator: " ")
    }

    private func run() async {
        withAnimation(.smooth(duration: reduceMotion ? 0.2 : 0.55)) { shown = true }
        do {
            if summary.quote != nil {
                try await Task.sleep(for: Self.quoteDelay)
                // The one haptic on this screen, and it belongs to the words
                // rather than to the blade — the blade already had its own when
                // it tore free. A single soft tap as somebody else's sentence
                // arrives is the difference between reading it and being handed
                // it.
                ForgeHaptics.shared.detent()
                withAnimation(.smooth(duration: reduceMotion ? 0.2 : 0.7)) { quoteShown = true }
            }
            try await Task.sleep(for: summary.quote != nil ? Self.holdsWithQuote : Self.holds)
        } catch {
            // A tap took it away first: this view is already going, and the
            // cancellation is the only signal we get. Swallowing it with `try?`
            // and carrying on would finish the day twice.
            return
        }
        onFinished()
    }
}

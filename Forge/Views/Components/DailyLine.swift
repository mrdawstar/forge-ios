import SwiftUI

/// The one sentence on the freed panel.
///
/// # Three sources, one slot, in this order
///
/// 1. **The world's own line**, for somebody walking an archetype. It is not a
///    quotation, it is the world speaking — the thing that was actually chosen
///    when the archetype was chosen — so it outranks everything else here.
/// 2. **The reflection the day earned**: a real line by a real person, picked
///    for what today was made of. See `ForgeQuotes`.
/// 3. **Forge's own line** about the count, which is what shows before the day
///    is finished.
///
/// # Why the reflection is here at all
///
/// It was only ever shown on the summary overlay — three seconds, over a black
/// screen, immediately after a two-and-a-half second sword animation somebody
/// was still watching — and it took itself away. The one sentence in the app
/// written to be read after the work was the one sentence nobody read.
///
/// So it stays. It arrives in the place the day's last word already lived,
/// under the freed panel, and it is still there when the phone is picked up at
/// eleven — which is when somebody actually has room for it. It is replaced by
/// tomorrow's, not by a timer: the loop the whole app runs on is *practice →
/// evidence → blade → reflection*, and a reflection that evaporates leaves that
/// loop three-quarters built.
///
/// **Deliberately not a card.** A bordered, tinted, elevated quote box is what
/// every app reaches for and it would be the loudest object on a screen whose
/// job is to be quiet — the blade is out, the day is done, and this is the last
/// thing left to look at. Set as text, centred, in the space that was already
/// there. It is part of the day's completion state and must not read as a
/// widget that happens to live nearby.
struct DailyLine: View {
    /// What the finished day earned. Nil until it is actually finished.
    var reflection: AttributedQuote?
    /// Forge's own line about the count.
    let fallback: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        Group {
            if let reflection {
                said(reflection.text, source: reflection.source)
            } else {
                Text(fallback)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 10)
        // A fade, and **no offset**. It used to arrive from twelve points below,
        // which read as the sentence shifting downward into place — and in the
        // freed panel, where this sits between two `Spacer`s above the TODAY
        // card, a moving quotation is the one thing on screen that looks like
        // the layout is still deciding. The panel has just spent 2.4 seconds
        // settling a sword; the last thing it needs is a second, smaller thing
        // travelling after it.
        .opacity(shown ? 1 : 0)
        .onAppear {
            guard !reduceMotion else { shown = true; return }
            // A beat after the panel has finished resizing. Animating into a
            // view that is still changing height reads as a stutter, and this
            // screen has just spent 2.4 seconds settling a sword.
            withAnimation(.reveal(0.5).delay(0.18)) { shown = true }
        }
        // A change of world or of day is worth animating too: the sentence
        // crossfades rather than swapping, so switching archetypes and coming
        // back here does not look like a bug.
        .animation(.easeInOut(duration: 0.28), value: reflection?.id)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(spoken))
    }

    /// A sentence somebody else said, with its source under it where there is
    /// one.
    ///
    /// The name is set small and quiet rather than omitted: a quotation without
    /// its source is a quotation Forge made up, which is the rule
    /// `AttributedQuote` exists to enforce. A world's line has no name under it
    /// because there is nobody to name — the hairline says it has a source and
    /// leaves it at that.
    private func said(_ text: String, source: String?) -> some View {
        VStack(spacing: 10) {
            // **Bounded.** `fixedSize` alone lets a long quotation take as many
            // lines as it likes, and the freed panel is a fixed height — so a
            // four-line sentence pushed the TODAY card past the bottom of the
            // panel and it was clipped. The card underneath is the one thing on
            // this screen somebody might actually need to touch, so the
            // quotation is what gives way, not the control.
            Text("\u{201C}\(text)\u{201D}")
                .font(.body.italic())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)

            if let source {
                Text(source.uppercased())
                    .font(ForgeTheme.overline)
                    .kerning(ForgeTheme.overlineKerning)
                    .foregroundStyle(.tertiary)
            } else {
                // A hairline, sized to the words above it rather than to the
                // panel. It is there to say the sentence has a source, which
                // the quotation marks alone leave ambiguous.
                Capsule()
                    .fill(.tertiary)
                    .frame(width: 22, height: 1)
            }
        }
    }

    private var spoken: String {
        if let reflection { return "\(reflection.text). \(reflection.source)" }
        return fallback
    }
}

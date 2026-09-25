import Foundation

/// The one thing Forge says after the blade is out.
///
/// Two short lines and no numbers to study: what the day was worth is not a
/// figure, and a screen that added one would be asking to be compared with
/// yesterday's. The count is spelled out for the same reason — "Thirty
/// days" is a fact about somebody, "30" is a total on a scoreboard.
///
/// Read from days kept rather than the streak. This sentence arrives on the
/// day *after* a miss as often as any other, and it should say the same
/// thing then: nothing was lost, and this is still what you do.
struct DaySummary: Equatable {
    /// "Thirty days."
    let headline: String
    /// "This is just what you do now."
    let line: String
    /// Somebody else's words, about the day that was just finished.
    ///
    /// The third beat and the only one Forge did not write. It arrives last and
    /// on its own — see `DaySummaryView` — because a quotation shown *with* the
    /// count reads as decoration around a number, and shown after it reads as
    /// the thing the number earned.
    ///
    /// Nil on the resting panel: `identityLine` reads only `line`, and the
    /// sentence that stays on screen all day should be Forge's own.
    var quote: AttributedQuote? = nil

    /// The day, read by whichever world is on.
    ///
    /// The headline is not negotiable and no Path can reach it. It is a count of
    /// what somebody actually did, and a world that could restate the number
    /// would be a world that could flatter them about it. What a Path may supply
    /// is `reading` — the sentence underneath, which is an interpretation and is
    /// therefore the only part it is honest to hand over.
    static func make(
        daysKept kept: Int,
        reading: String? = nil,
        quote: AttributedQuote? = nil
    ) -> DaySummary {
        DaySummary(
            headline: kept == 1 ? "One day." : "\(ForgeCount.spelled(kept)) days.",
            line: reading ?? line(for: kept),
            quote: quote
        )
    }

    /// Four sentences across a lifetime of use, and each one holds for long
    /// enough that it stops being a message and starts being a description.
    ///
    /// None of them congratulates anybody. The furthest this goes is noticing
    /// out loud that a decision has stopped being made every day, which is
    /// the actual thing that happened.
    private static func line(for kept: Int) -> String {
        switch kept {
        case ..<2: "You have done it once."
        case ..<7: "Early days."
        case ..<30: "This is starting to look like you."
        case ..<100: "This is just what you do now."
        default: "You stopped deciding a while ago."
        }
    }
}

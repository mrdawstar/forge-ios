import Foundation
import Testing
@testable import Forge

/// The order the day list puts what is still to do in.
///
/// Worth its own suite because the rule has three halves that are easy to
/// collapse into two: times sort, no time sinks, and *neither* of those is
/// allowed to disturb the arrangement the user dragged into place. The third is
/// the one a naive `sorted(by:)` loses — see `Ritual.chronological`.
@Suite("Activity order")
struct ActivityOrderTests {

    private func made(_ name: String, at startMinute: Int? = nil) -> Ritual {
        var draft = ActivityDraft.blank(named: name)
        draft.symbol = "sparkle"
        draft.startMinute = startMinute
        return Ritual.makeCustom(draft)
    }

    private func names(_ rituals: [Ritual]) -> [String] { rituals.map(\.label) }

    // MARK: - Times

    @Test("Timed activities come out earliest first")
    func timedSortByClock() {
        let day = [
            made("Evening read", at: 21 * 60),
            made("Push-ups", at: 6 * 60 + 30),
            made("Lunch walk", at: 12 * 60 + 45),
        ]
        #expect(names(Ritual.chronological(day)) == ["Push-ups", "Lunch walk", "Evening read"])
    }

    @Test("Midnight sorts first, not last")
    func midnightIsTheStartOfTheDay() {
        let day = [made("Late", at: 23 * 60 + 59), made("Early", at: 0)]
        #expect(names(Ritual.chronological(day)) == ["Early", "Late"])
    }

    // MARK: - No times

    /// The overwhelmingly common case, and the one where a change of order
    /// would be somebody's carefully dragged morning silently rearranged.
    @Test("A day with no times is left exactly as it was arranged")
    func untimedIsUntouched() {
        let day = [made("Water"), made("Bed"), made("Teeth"), made("Read")]
        #expect(names(Ritual.chronological(day)) == names(day))
    }

    @Test("Untimed activities sink below timed ones, in the order arranged")
    func untimedGoesUnder() {
        let day = [
            made("Tidy"),
            made("Run", at: 7 * 60),
            made("Vitamins"),
            made("Journal", at: 6 * 60),
        ]
        #expect(names(Ritual.chronological(day)) == ["Journal", "Run", "Tidy", "Vitamins"])
    }

    // MARK: - Stability

    /// Two activities set to the same minute is not an edge case — "07:00" is
    /// what everybody picks — and the pair must not trade places between one
    /// redraw and the next.
    @Test("Activities sharing a minute keep the order they were arranged in")
    func tiesAreStable() {
        let day = [made("Second", at: 420), made("First", at: 419), made("Third", at: 420)]
        let once = names(Ritual.chronological(day))
        #expect(once == ["First", "Second", "Third"])
        #expect(names(Ritual.chronological(Ritual.chronological(day))) == once)
    }

    @Test("An empty day sorts to an empty day")
    func emptyIsFine() {
        #expect(Ritual.chronological([]).isEmpty)
    }

    // MARK: - What a time means

    /// The end time follows the start and the duration, so an activity that
    /// runs long cannot jump the queue — position is decided by when it begins.
    @Test("Order follows the start, not the finish")
    func lengthDoesNotDecidePlace() {
        var long = ActivityDraft.blank(named: "Deep work")
        long.symbol = "sparkle"
        long.startMinute = 9 * 60
        long.minutes = 180

        var short = ActivityDraft.blank(named: "Stretch")
        short.symbol = "sparkle"
        short.startMinute = 10 * 60
        short.minutes = 5

        let day = [Ritual.makeCustom(short), Ritual.makeCustom(long)]
        #expect(names(Ritual.chronological(day)) == ["Deep work", "Stretch"])
    }
}

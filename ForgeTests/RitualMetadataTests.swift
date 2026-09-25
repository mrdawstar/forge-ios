import Foundation
import Testing
@testable import Forge

/// The right-hand column of the day list.
///
/// Small enough to look obviously correct and branchy enough not to be: the
/// whole point of it is that no row is ever blank, and "no row" includes the
/// eight shipped activities that carry no target and every activity somebody
/// makes without giving it one.
@Suite("Row metadata")
struct RitualMetadataTests {

    private func library(_ id: String) throws -> Ritual {
        try #require(Ritual.find(id))
    }

    private func custom(
        goal: String,
        _ method: VerificationMethod = .honor
    ) -> Ritual {
        var draft = ActivityDraft.blank(named: "Something")
        draft.symbol = "sparkle"
        draft.goal = goal
        draft.verification = method
        return Ritual.makeCustom(draft)
    }

    // MARK: - Library

    @Test("A shipped target is shown as it was written")
    func libraryTarget() throws {
        #expect(try library("read").metadata == "10 pages")
        #expect(try library("water").metadata == "350 ml")
        #expect(try library("teeth").metadata == "2:00")
        #expect(try library("push").metadata == "20")
    }

    @Test("A shipped activity with no target falls back to the word")
    func libraryWithoutTarget() throws {
        #expect(try library("bed").metadata == "Honor")
        #expect(try library("nofeed").metadata == "Honor")
        #expect(try library("coffee").metadata == "Honor")
    }

    /// The guarantee the column rests on. Every shipped activity puts something
    /// in it, so the list can never show a row that looks like it lost its data.
    @Test("No shipped activity leaves the column empty")
    func libraryIsNeverBlank() {
        for ritual in Ritual.library {
            #expect(!ritual.metadata.isEmpty, "\(ritual.id) has nothing to show")
        }
    }

    // MARK: - Custom

    @Test("A goal given at creation is what the row shows")
    func customGoal() {
        #expect(custom(goal: "5 min").metadata == "5 min")
        #expect(custom(goal: "3 sets", .honor).metadata == "3 sets")
    }

    @Test("A user-made activity with no goal falls back to the word")
    func customWithoutGoal() {
        #expect(custom(goal: "").metadata == "Honor")
    }

    /// A checkbox is its own mark, so the word would be a second copy of it.
    @Test("A Basic Check activity with no goal leaves the word to the checkbox")
    func customBasicWithoutGoal() {
        #expect(custom(goal: "", .basic).metadata.isEmpty)
        #expect(custom(goal: "3 sets", .basic).metadata == "3 sets")
    }

    /// The whole of what the new tier changes about a tap.
    @Test("Only Your Word asks a question")
    func onlyHonorAsks() {
        #expect(VerificationMethod.honor.asksForConfirmation)
        #expect(!VerificationMethod.basic.asksForConfirmation)
    }

    /// Three methods, three glyphs, none of them shared — a row that draws
    /// `method.symbol` can then never show one method's mark beside another
    /// method's words.
    @Test("Every verification method has its own mark")
    func marksAreDistinct() {
        let symbols = Set(VerificationMethod.allCases.map(\.symbol))
        #expect(symbols.count == VerificationMethod.allCases.count)
    }

    /// `basic` is opt-in and stays that way. The classifier reads names, and
    /// no name tells you somebody wants less ceremony — that is a preference,
    /// so it is only ever reached by choosing it.
    @Test("Nothing is classified as Basic Check on its own")
    func basicIsNeverSuggested() {
        for ritual in Ritual.library {
            #expect(ActivityVerification.suggest(name: ritual.label) != .basic)
        }
        #expect(ActivityVerification.suggest(name: "Take the vitamins") != .basic)
        #expect(ActivityVerification.suggest(name: "Wibble the frobnicator") != .basic)
    }

    // MARK: - Round trip

    @Test("A goal survives being written down and read back")
    func goalRoundTrips() throws {
        let made = custom(goal: "12 laps")
        let data = try JSONEncoder().encode([made])
        let back = try JSONDecoder().decode([Ritual].self, from: data)
        #expect(back.first?.tail == "12 laps")
        #expect(back.first?.metadata == "12 laps")
    }

    /// The overlay a shipped activity's edits live in. An edit that only sets a
    /// goal still has to count as an edit, or it would be dropped on save.
    @Test("A goal alone is enough to make a library edit worth keeping")
    func goalMakesAnEditNonEmpty() {
        var edit = RitualEdit()
        #expect(edit.isEmpty)
        edit.tail = "12 laps"
        #expect(!edit.isEmpty)
    }

    /// Clearing a shipped activity's target is a real edit rather than an absent
    /// one, so the empty string has to survive as a value.
    @Test("Clearing a shipped target is stored, not forgotten")
    func clearingATargetIsAnEdit() {
        var edit = RitualEdit()
        edit.tail = ""
        #expect(!edit.isEmpty)
    }

    @Test("A library edit decodes from a version that had no goal")
    func legacyEditDecodes() throws {
        let legacy = #"{"label":"Read more"}"#.data(using: .utf8)!
        let edit = try JSONDecoder().decode(RitualEdit.self, from: legacy)
        #expect(edit.label == "Read more")
        #expect(edit.tail == nil)
        #expect(!edit.isEmpty)
    }
}

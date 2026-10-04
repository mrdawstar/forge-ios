import Foundation
import Testing
@testable import Forge

/// Every decoder 1.1 added meets missing keys, unknown values and garbage
/// (FORGE_CONTEXT §17.7).
///
/// The rule the codebase has paid for more than once (§16): **versioned keys
/// only, hand-written tolerant decoders only**. A stored value is read by a
/// later build, written by an earlier one, damaged, or — since 1.1 — imported
/// from a file somebody can edit. Each decoder here must, for any input,
/// return without crashing, keep what it can read, and drop only what it
/// cannot; and nothing it returns may hang a screen that walks the days.
///
/// The corpus is the same for every decoder: nothing, bytes that are not
/// text, text that is not JSON, every JSON shape that is not the one asked
/// for, a nesting deep enough to stop a parser, and a long list.
@MainActor
@Suite("Decoders: 1.1 meets garbage")
struct DecoderHardeningTests {

    // MARK: - The corpus

    static let garbage: [Data] = {
        var corpus: [Data] = [
            Data(),
            Data([0xFF, 0xFE, 0x00, 0x80, 0xC3, 0x28]),
            Data("not json at all".utf8),
            Data("null".utf8), Data("true".utf8), Data("0".utf8), Data("-1".utf8), Data("1e400".utf8),
            Data(#""a string""#.utf8), Data("[]".utf8), Data("{}".utf8), Data("[null]".utf8),
            Data("[{}]".utf8), Data(#"[[1],[2]]"#.utf8), Data(#"{"a":[{"b":{}}]}"#.utf8),
            Data(String(repeating: "[", count: 5_000).utf8),
            Data(("[" + Array(repeating: "{}", count: 5_000).joined(separator: ",") + "]").utf8),
            Data("\u{FEFF}{}".utf8),
        ]
        // Bytes from a fixed generator, so a failure reproduces.
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        for length in [1, 7, 64, 1_024] {
            var bytes: [UInt8] = []
            for _ in 0..<length {
                state ^= state << 13; state ^= state >> 7; state ^= state << 17
                bytes.append(UInt8(truncatingIfNeeded: state))
            }
            corpus.append(Data(bytes))
        }
        return corpus
    }()

    private func suite(_ name: String = #function) -> UserDefaults {
        let id = "forge.hardening.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: id)!
        defaults.removePersistentDomain(forName: id)
        return defaults
    }

    private let today = ForgeDay(year: 2026, month: 10, day: 4)
    private let impossibleDays = [
        #"{"year":1000000,"month":1,"day":1}"#, #"{"year":1,"month":1,"day":1}"#,
        #"{"year":2026,"month":0,"day":0}"#, #"{"year":"2026","month":1,"day":1}"#,
    ]

    // MARK: - Days

    @Test("A day no calendar holds, or no phone could date, is not a day")
    func plausibleDays() {
        #expect(today.isPlausible)
        #expect(ForgeDay(year: 1970, month: 1, day: 1).isPlausible)
        #expect(!ForgeDay(year: 1_000_000, month: 1, day: 1).isPlausible)
        #expect(!ForgeDay(year: 1, month: 1, day: 1).isPlausible)
        #expect(!ForgeDay(year: 2026, month: 13, day: 1).isPlausible)
        #expect(!ForgeDay(year: 2026, month: 1, day: 0).isPlausible)
        #expect(!ForgeDay(year: Int.max, month: Int.min, day: 1).isPlausible)
        // The year 1,000,000 cannot be stepped from at all: the hang.
        let stuck = ForgeDay(year: 1_000_000, month: 1, day: 1)
        #expect(stuck.adding(days: 1) == stuck)
    }

    // MARK: - The assessment (forge.assessment.v1)

    @Test("The assessment: garbage is none, a missing answer is one answer, an unknown one is dropped")
    func assessment() throws {
        let defaults = suite()
        for data in Self.garbage {
            defaults.set(data, forKey: Assessment.key)
            #expect(Assessment.read(from: defaults) == nil)
        }
        let partial = #"""
        {"day":{"year":2026,"month":10,"day":4},
         "answers":{"training":"three_four","sleep":5,"screen":"unheard_of","shoe_size":"nine"},
         "extra":[1,2,3]}
        """#
        defaults.set(Data(partial.utf8), forKey: Assessment.key)
        let read = try #require(Assessment.read(from: defaults))
        #expect(read.day == today)
        #expect(read.answers.count == 1)
        #expect(read.answers[.training] != nil)

        defaults.set(Data(#"{"day":{"year":2026,"month":10,"day":4},"answers":"none"}"#.utf8), forKey: Assessment.key)
        #expect(Assessment.read(from: defaults)?.answers.isEmpty == true)
        defaults.set(Data(#"{"answers":{"training":"three_four"}}"#.utf8), forKey: Assessment.key)
        #expect(Assessment.read(from: defaults) == nil, "no day, no assessment")
        for day in impossibleDays {
            defaults.set(Data(#"{"day":\#(day),"answers":{}}"#.utf8), forKey: Assessment.key)
            #expect(Assessment.read(from: defaults) == nil, Comment(rawValue: day))
        }
    }

    // MARK: - Arcs (forge.arcs.v1)

    @Test("The Arcs: garbage is none, a bad row costs only itself, and nothing read can hang the reading")
    func arcs() throws {
        for data in Self.garbage {
            #expect(ArcEnrollment.decodeAll(data).isEmpty)
        }
        let rows = #"""
        [
          {"id":"a","arc":"winter90","startDay":{"year":2026,"month":10,"day":1}},
          {"id":"b","arc":"someday-arc","startDay":{"year":2026,"month":10,"day":1}},
          {"arc":"monk30","startDay":{"year":2026,"month":10,"day":1}},
          {"id":"d","arc":"monk30","startDay":{"year":1000000,"month":1,"day":1}},
          {"id":"e","arc":"monk30","startDay":{"year":1,"month":1,"day":1}},
          {"id":"f","arc":"lockin7","startDay":{"year":2026,"month":9,"day":20},
           "wakeMinute":"early","picks":[1,2],"added":"all","isApplied":"yes",
           "phaseAnswers":{"x":true,"2":"maybe"},"tallies":{"1":-4,"2":3,"z":9},
           "leftOn":{"year":1000000,"month":1,"day":1},"joinedAt":"yesterday"},
          null, 7, "row"
        ]
        """#
        let read = ArcEnrollment.decodeAll(Data(rows.utf8))
        #expect(read.map(\.id) == ["a", "f"])
        let tolerant = try #require(read.last)
        #expect(tolerant.wakeMinute == nil)
        #expect(tolerant.picks.isEmpty && tolerant.added.isEmpty)
        #expect(tolerant.isApplied)
        #expect(tolerant.tallies == [2: 3])
        #expect(tolerant.leftOn == nil)

        // Read against a record, every one returns.
        for enrollment in read {
            let reading = ArcReading.read(
                enrollment, byDay: [:], today: today, restWeekdays: [1, 7],
                challengeDays: [], resolved: [:]
            )
            #expect(reading.day >= 0)
        }
        // And the count itself returns from a day no calendar can step on
        // from, which before §17.7 it walked for ever.
        let stuck = ForgeDay(year: 1_000_000, month: 1, day: 1)
        let counted = ArcReading.count(from: stuck, to: stuck, byDay: [:], today: today, rest: [])
        #expect(counted.kept == 0 && counted.counted == 0)
    }

    // MARK: - Challenges kept (forge.challengesKept.v1)

    @Test("Challenges kept: garbage is none, a row without a day or with no day anybody had is dropped")
    func challengesKept() {
        for data in Self.garbage {
            #expect(KeptChallenge.decodeAll(data).isEmpty)
        }
        let rows = #"""
        [
          {"day":{"year":2026,"month":10,"day":3},"id":"c1","focus":"discipline","at":800000000},
          {"day":{"year":2026,"month":10,"day":2},"focus":"no-such-focus"},
          {"id":"c3","focus":"mental"},
          {"day":{"year":1000000,"month":1,"day":1},"focus":"mental"},
          {"day":{"year":2026,"month":10,"day":1},"focus":"physical","at":"noon","id":42},
          "challenge"
        ]
        """#
        let read = KeptChallenge.decodeAll(Data(rows.utf8))
        #expect(read.map(\.day) == [
            ForgeDay(year: 2026, month: 10, day: 3), ForgeDay(year: 2026, month: 10, day: 2),
            ForgeDay(year: 2026, month: 10, day: 1),
        ])
        #expect(read.map(\.id) == ["c1", "", ""])
        #expect(read[1].focus == .discipline, "an aim this build does not know lands somewhere safe")
        #expect(read[2].at == ForgeDay(year: 2026, month: 10, day: 1).startOfDay())
        // ProgressStore reads them the same way, and its record is untouched.
        let defaults = suite()
        defaults.set(Data(rows.utf8), forKey: "forge.challengesKept.v1")
        defaults.set(Data("garbage".utf8), forKey: "forge.history.v1")
        let progress = ProgressStore(defaults: defaults)
        #expect(progress.records.count <= 1, "garbage history is an empty record, not a crash")
    }

    // MARK: - The record (forge.history.v1)

    /// The record is the one thing people would grieve, so it is read a day at
    /// a time: one day that does not read, or that no phone could have dated,
    /// costs that day and no other (§17.7).
    @Test("The record: a day that does not read costs that day only")
    func history() throws {
        let defaults = suite()
        for data in Self.garbage {
            defaults.set(data, forKey: "forge.history.v1")
            _ = ProgressStore(defaults: defaults).records
        }
        let rows = #"""
        [
          {"day":{"year":2026,"month":10,"day":1},"completions":[],"plannedIDs":["read"],"extractedAt":800000000},
          {"day":"Tuesday","completions":[],"plannedIDs":[]},
          {"day":{"year":1000000,"month":1,"day":1},"completions":[],"plannedIDs":[],"extractedAt":800000000},
          {"day":{"year":1,"month":1,"day":1},"completions":[],"plannedIDs":[],"extractedAt":800000000},
          {"day":{"year":2026,"month":10,"day":2},"completions":[],"plannedIDs":[],"extractedAt":800000000}
        ]
        """#
        defaults.set(Data(rows.utf8), forKey: "forge.history.v1")
        let progress = ProgressStore(defaults: defaults)
        let kept = progress.records.filter(\.isEarned).map(\.day)
        #expect(kept.contains(ForgeDay(year: 2026, month: 10, day: 1)))
        #expect(kept.contains(ForgeDay(year: 2026, month: 10, day: 2)))
        #expect(progress.records.allSatisfy { $0.day.isPlausible })
        // The streak and the ladder read it without walking to the year one.
        _ = progress.daysKept
        _ = progress.currentStreak
    }

    // MARK: - Apple Health's ledger (forge.health.v1)

    @Test("Apple Health's ledger: garbage is a fresh ledger, an unknown answer is no answer")
    func healthLedger() {
        let defaults = suite()
        for data in Self.garbage {
            defaults.set(data, forKey: HealthLedger.key)
            let ledger = HealthLedger.read(from: defaults)
            #expect(ledger.decision == .undecided)
            #expect(!ledger.observesAtLaunch)
        }
        let partial = #"""
        {"decision":"maybe","awaitingOffer":"walk","offered":["steps",3],"hasMigrated":"yes",
         "tickedDay":{"year":1000000,"month":1,"day":1},"ticked":["steps"],"later":true}
        """#
        defaults.set(Data(partial.utf8), forKey: HealthLedger.key)
        let ledger = HealthLedger.read(from: defaults)
        #expect(ledger.decision == .undecided)
        #expect(ledger.awaitingOffer.isEmpty)
        #expect(ledger.offered.isEmpty)
        #expect(!ledger.hasMigrated)
        #expect(ledger.tickedDay == nil)
        #expect(ledger.ticked == ["steps"])
        #expect(!ledger.hasTicked("steps", on: today))

        defaults.set(Data(#"{"decision":"asked"}"#.utf8), forKey: HealthLedger.key)
        #expect(HealthLedger.read(from: defaults).observesAtLaunch)
    }

    // MARK: - Ask Forge's conversation (forge.askForge.v1)

    /// Synthesised until 1.1's release pass: one line written by a later build
    /// or damaged emptied the whole conversation, and the next line saved
    /// overwrote it (§17.7).
    @Test("Ask Forge's history: a line that does not read costs that line, and a withheld line stays unsent")
    func coachHistory() throws {
        let defaults = suite()
        for data in Self.garbage {
            defaults.set(data, forKey: CoachHistory.key)
            #expect(CoachHistory.read(defaults).isEmpty)
        }
        let lines = #"""
        [
          {"id":"6B57D0ED-5821-4F86-9E84-F3A05B9F565D","role":"user","kind":"message","text":"one","at":800000000,"isWithheld":false},
          {"role":"forge","kind":"message","text":"two"},
          {"role":"forge","kind":"hologram","text":"a kind from a later build"},
          {"role":"robot","kind":"message","text":"no such role"},
          {"role":"forge","text":"a reply that does not say what wrote it"},
          {"role":"user","text":"no kind, the person's own"},
          {"role":"user","kind":"message","text":"heavy","isWithheld":"unclear"},
          {"role":"forge","kind":"message","text":"with a broken proposal","proposal":{"summary":7,"changes":"all"}},
          {"role":"user","kind":"message"},
          42
        ]
        """#
        defaults.set(Data(lines.utf8), forKey: CoachHistory.key)
        let read = CoachHistory.read(defaults)
        #expect(read.map(\.text) == ["one", "two", "no kind, the person's own", "heavy", "with a broken proposal"])
        #expect(read.first?.id.uuidString == "6B57D0ED-5821-4F86-9E84-F3A05B9F565D")
        let heavy = try #require(read.first { $0.text == "heavy" })
        #expect(heavy.isWithheld, "a withholding that cannot be read is a withholding")
        #expect(!heavy.isTransmittable)
        #expect(read.first { $0.text == "no kind, the person's own" }?.kind == .message)
        #expect(read.last?.proposal?.changes.isEmpty ?? true)
        // What a request would carry never includes the withheld line.
        #expect(!CoachHistory.turns(from: read).map(\.text).contains("heavy"))

        // Written by this build, read back exactly.
        let written = [
            CoachMessage(role: .user, text: "a"),
            CoachMessage(role: .forge, kind: .safety, text: "b"),
            CoachMessage(role: .forge, text: "c", proposal: CoachProposal(summary: "s", changes: [.init(kind: "time", id: "read", minute: 420)])),
        ]
        defaults.set(try JSONEncoder().encode(written), forKey: CoachHistory.key)
        #expect(CoachHistory.read(defaults) == written)
    }

    // MARK: - What comes back from the server

    @Test("A reply, a reading and a plan: garbage is no answer, and one bad change costs that change")
    func wire() throws {
        for data in Self.garbage {
            // Garbage at the top is an error the caller answers with its one
            // line; it must be an error, never a crash.
            _ = try? JSONDecoder().decode(AIWireCoachAnswer.self, from: data)
            _ = try? JSONDecoder().decode(AIWirePlan.self, from: data)
            _ = try? JSONDecoder().decode(AIWireReading.self, from: data)
        }
        let answer = try JSONDecoder().decode(AIWireCoachAnswer.self, from: Data(#"""
        {"reply":5,"proposal":{"summary":"Move read","changes":[
          {"kind":"time","id":"read","minute":420},
          {"kind":"time","id":"walk","minute":"seven"},
          {"id":"wake"},
          "change",
          {"kind":"days","id":"walk","weekdays":[2,4,9]}
        ]}}
        """#.utf8))
        #expect(answer.reply.isEmpty)
        #expect(answer.proposal?.changes.map(\.id) == ["read", "walk"])

        let plan = try JSONDecoder().decode(AIWirePlan.self, from: Data(#"""
        {"summary":["no"],"changes":[{"kind":"duration","id":"read","minutes":30},{"kind":7},{"kind":"time","id":"read","minute":-1}]}
        """#.utf8))
        #expect(plan.summary.isEmpty)
        #expect(plan.changes.count == 2)

        let reading = try JSONDecoder().decode(AIWireReading.self, from: Data(#"{"observation":{"a":1}}"#.utf8))
        #expect(reading.observation.isEmpty)
    }

    // MARK: - Activities, with 1.1's measure

    @Test("An activity whose 1.1 target does not read keeps everything else; the list keeps the rest")
    func activities() throws {
        let one = try JSONDecoder().decode(
            Ritual.self,
            from: Data(#"{"id":"custom.x","label":"Sauna","verificationOverride":"health","target":"lots"}"#.utf8)
        )
        #expect(one.label == "Sauna")
        #expect(one.target == nil)
        #expect(one.verificationOverride == .health)

        let unknown = try JSONDecoder().decode(
            Ritual.self, from: Data(#"{"id":"custom.y","verificationOverride":"telepathy"}"#.utf8)
        )
        #expect(unknown.verificationOverride == .honor)

        let edits = try JSONDecoder().decode(
            [String: RitualEdit].self, from: Data(#"{"steps":{"target":"many","minutes":20}}"#.utf8)
        )
        #expect(edits["steps"]?.target == nil)
        #expect(edits["steps"]?.minutes == 20)

        let list = try JSONDecoder().decode(LossyList<Ritual>.self, from: Data(#"""
        [{"id":"custom.a","label":"A"},{"label":"no id"},{"id":"custom.b","label":"B","minutes":"long"},"x"]
        """#.utf8))
        #expect(list.elements.map(\.id) == ["custom.a"])
    }

    // MARK: - The widgets' snapshot

    @Test("The widgets' snapshot: garbage is a day not yet begun")
    func snapshot() {
        let defaults = suite()
        for data in Self.garbage {
            defaults.set(data, forKey: "forge.snapshot.v1")
            let read = ForgeSnapshot.read(from: defaults)
            #expect(read.total == 0)
            #expect(!read.isLocked)
        }
    }
}

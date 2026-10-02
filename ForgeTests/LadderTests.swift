import Foundation
import Testing
@testable import Forge

/// The ladder with no cap (DIRECTION_1_1 §6, §17.4): Honed at ninety days,
/// Enduring at a hundred and eighty, a temper mark every ninety after — and
/// nothing an existing install already had moving an inch.
@MainActor
@Suite("The ladder has no cap")
struct LadderTests {

    private func makeProgress() -> ProgressStore {
        ProgressStore(defaults: UserDefaults(suiteName: "forge.tests.\(UUID().uuidString)") ?? .standard)
    }

    /// `count` earned days, ending yesterday.
    private func keep(_ count: Int, in progress: ProgressStore) {
        for back in 1...count {
            let day = progress.currentDay.adding(days: -back)
            progress.record(DayRecord(
                day: day,
                completions: [DayRecord.Completion(ritualID: "water", method: .honor, at: day.startOfDay())],
                plannedIDs: ["water"],
                extractedAt: day.startOfDay()
            ))
        }
    }

    /// A blade store reading a suite written the way 1.0 wrote it.
    private func store(
        _ progress: ProgressStore, equipped: Int, seen: [Int], celebrated: [Int]?
    ) -> SwordStore {
        let suite = UserDefaults(suiteName: "forge.swords.\(UUID().uuidString)") ?? .standard
        suite.set(equipped, forKey: "forge.equippedSword.v1")
        suite.set(seen, forKey: "forge.acknowledgedSwords.v1")
        if let celebrated { suite.set(celebrated, forKey: "forge.celebratedSwords.v1") }
        return SwordStore(progress: progress, defaults: suite)
    }

    // MARK: - The rungs

    @Test("Every rung that shipped keeps its id and its threshold")
    func shippedRungsUnchanged() {
        let shipped: [(String, Int)] = [
            ("start", 0), ("one", 1), ("three", 3), ("seven", 7), ("fourteen", 14),
            ("thirty", 30), ("sixty", 60), ("hundred", 100), ("oneeighty", 180),
            ("year", 365), ("fivehundred", 500), ("twoyears", 730), ("thousand", 1000),
        ]
        for (id, threshold) in shipped {
            #expect(Ladder.rungs.first { $0.id == id }?.threshold == threshold, Comment(rawValue: id))
        }
        #expect(Ladder.rungs.map(\.id) == [
            "start", "one", "three", "seven", "fourteen", "thirty", "sixty",
            "ninety", "hundred", "oneeighty", "year", "fivehundred", "twoyears", "thousand",
        ])
    }

    @Test("The seven blades that shipped keep their ids and their days")
    func shippedBladesUnchanged() {
        let first = Sword.collection.prefix(7)
        #expect(first.map(\.id) == Array(1...7))
        #expect(first.map(\.requirement) == [0, 1, 3, 7, 14, 30, 60])
        #expect(first.map(\.name) == ["Rough", "Struck", "Shaped", "Folded", "Quenched", "Edged", "Proven"])
    }

    @Test("Honed at ninety days and Enduring at a hundred and eighty, on the blades and the ladder")
    func theNewBlades() {
        #expect(Sword.collection.map(\.id) == Array(1...9))
        #expect(Sword.collection[7].name == "Honed")
        #expect(Sword.collection[7].requirement == 90)
        #expect(Sword.collection[8].name == "Enduring")
        #expect(Sword.collection[8].requirement == 180)
        #expect(Sword.collection.allSatisfy { !$0.note.contains("!") }, "no exclamation marks")

        // One progression: every blade is a rung at its own day, and nothing
        // else on the ladder is a blade.
        let blades = Ladder.rungs.compactMap { rung in rung.mark.bladeID.map { (id: $0, rung: rung) } }
        #expect(blades.map(\.id) == Array(1...9))
        for blade in blades {
            let sword = Sword.collection[blade.id - 1]
            #expect(blade.rung.threshold == sword.requirement)
            #expect(blade.rung.name == sword.title)
            #expect(blade.rung.note == sword.note, "the ladder and the collection say the same sentence")
        }

        #expect(Ladder.current(daysKept: 90).id == "ninety")
        #expect(Ladder.bladeID(daysKept: 89) == 7)
        #expect(Ladder.bladeID(daysKept: 90) == 8)
        #expect(Ladder.bladeID(daysKept: 179) == 8)
        #expect(Ladder.bladeID(daysKept: 180) == 9)
        #expect(Ladder.bladeID(daysKept: 5000) == 9)
        #expect(Ladder.rung(after: 60)?.id == "ninety")
        #expect(Ladder.rung(after: 100)?.id == "oneeighty")
    }

    @Test("No two rungs share a day or a name")
    func rungsAreDistinct() {
        let reached = Ladder.reached(daysKept: 4000)
        #expect(Set(reached.map(\.threshold)).count == reached.count)
        let names = reached.map { $0.name.lowercased() }
        #expect(Set(names).count == names.count, "a Honed Sword and a Honed state would be one name twice")
    }

    @Test("The blade's state past Enduring, and the grade that went with the name")
    func states() {
        #expect(Ladder.state(daysKept: 99) == .raw)
        #expect(Ladder.state(daysKept: 120) == .tempered)
        #expect(Ladder.state(daysKept: 200) == .tempered)
        #expect(Ladder.state(daysKept: 365) == .patina)
        #expect(Ladder.state(daysKept: 600) == .weathered)
        #expect(BladeState(rawValue: "honed") == nil)
        let decoded = try? JSONDecoder().decode(BladeState.self, from: Data(#""honed""#.utf8))
        #expect(decoded == .raw, "an old value lands on the blade as it ships")
    }

    // MARK: - Temper marks

    @Test("A temper mark for every ninety days kept past Enduring")
    func temperMarks() {
        let expected: [Int: Int] = [
            0: 0, 60: 0, 179: 0, 180: 0, 269: 0, 270: 1, 359: 1, 360: 2, 449: 2, 450: 3, 1000: 9,
        ]
        for (days, marks) in expected {
            #expect(Ladder.temperMarks(daysKept: days) == marks, Comment(rawValue: "\(days) days"))
            #expect(Ladder.temperMarks(daysKept: days) == max(0, (days - 180) / 90))
        }
        #expect(Ladder.temperLabel(0) == nil)
        #expect(Ladder.temperLabel(1) == "One temper mark")
        #expect(Ladder.temperLabel(3) == "Three temper marks")
    }

    @Test("Temper marks are read off the record, and cannot go down")
    func temperMarksAreDerived() {
        let progress = makeProgress()
        keep(275, in: progress)
        let blade = BladeViewModel(progress: progress, resolve: { _ in nil })
        #expect(blade.daysKept == 275)
        #expect(blade.temperMarks == 1)
        var previous = 0
        for days in stride(from: 0, through: 2000, by: 7) {
            let marks = Ladder.temperMarks(daysKept: days)
            #expect(marks >= previous)
            previous = marks
        }
    }

    // MARK: - An install from 1.0

    @Test("An install from 1.0 keeps the blade it carries and everything it has seen")
    func migrationKeepsBladeState() {
        let progress = makeProgress()
        keep(120, in: progress)
        let swords = store(progress, equipped: 5, seen: [2, 3, 4, 5], celebrated: [2, 3, 4, 5, 6, 7])

        #expect(swords.equippedID == 5)
        #expect(swords.acknowledgedIDs == [2, 3, 4, 5])
        #expect(swords.celebratedIDs == [2, 3, 4, 5, 6, 7])
        #expect(swords.swords.filter(\.isUnlocked).map(\.id) == [1, 2, 3, 4, 5, 6, 7, 8])
        #expect(swords.newIDs == [6, 7, 8])
        #expect(swords.ownedLabel == "7 of 8")

        // Honed is met once, on the next day kept, and never again — and it
        // is not carried behind their back.
        #expect(swords.claimBlades())
        #expect(swords.pendingUnlock?.id == 8)
        swords.dismissCelebration()
        #expect(!swords.claimBlades())
        #expect(swords.equippedID == 5)
    }

    @Test("A long practice meets Honed and Enduring as one moment, not two days running")
    func twoNewBladesAreOneMoment() {
        let progress = makeProgress()
        keep(200, in: progress)
        let swords = store(progress, equipped: 7, seen: Array(2...7), celebrated: Array(2...7))

        #expect(swords.claimBlades())
        #expect(swords.pendingUnlock?.id == 9, "the best of what is waiting")
        swords.dismissCelebration()
        #expect(swords.celebratedIDs.isSuperset(of: [8, 9]))
        #expect(!swords.claimBlades(), "Honed does not arrive the morning after Enduring")
        #expect(swords.newIDs == [8, 9], "both keep their unseen mark in the collection")
    }

    @Test("A suite written before celebrations were kept replays nothing, new blades included")
    func beforeTheSplitReplaysNothing() {
        let progress = makeProgress()
        keep(200, in: progress)
        let swords = store(progress, equipped: 7, seen: Array(2...7), celebrated: nil)
        #expect(!swords.claimBlades())
        #expect(swords.pendingUnlock == nil)
    }

    @Test("Carrying the new blades, and an id this build does not know")
    func equippingTheNewBlades() {
        let progress = makeProgress()
        keep(190, in: progress)
        let swords = store(progress, equipped: 9, seen: [], celebrated: Array(2...9))
        #expect(swords.equippedID == 9)
        #expect(swords.equippedSceneAsset == "sword9-lit")
        #expect(swords.equipped.asset == "sword9")

        let unknown = store(progress, equipped: 12, seen: [], celebrated: [])
        #expect(unknown.equippedID == 1, "an id no blade has falls back to the first")
    }

    @Test("The onboarding's full potential is the last blade there is")
    func fullPotentialIsEnduring() {
        #expect(Sword.collection.last?.name == "Enduring")
        #expect(Transformation.blade(forDaysKept: 10_000).name == "Enduring")
    }
}

import Foundation
import Testing
import UIKit
@testable import Forge

/// The first week on Becoming, the starters for empty dimensions, and the
/// Proof Card. Everything here is read off the local record — no network, no
/// model, no backend.
@Suite("First week")
struct FirstWeekTests {

    // A Sunday, so the week it opens ends on the next Sunday.
    private let sunday = ForgeDay(year: 2026, month: 9, day: 20)

    private func days(_ offsets: [Int], from start: ForgeDay) -> [ForgeDay] {
        offsets.map { start.adding(days: $0) }
    }

    // MARK: The threshold

    @Test("The contract stands through the first seven days, even if the shape could already be read")
    func contractHoldsForTheWeek() {
        for since in 0..<FirstWeek.length {
            let today = sunday.adding(days: since)
            let contract = FirstWeek.make(firstDay: sunday, today: today, earned: [], isShapeReadable: true)
            #expect(contract != nil, "day \(since)")
            #expect(contract?.isOpeningWeek == true)
        }
    }

    @Test("From the draw day on, a readable shape replaces the contract")
    func transitionToTheShape() {
        let drawDay = sunday.adding(days: 7)
        #expect(FirstWeek.make(firstDay: sunday, today: drawDay.adding(days: -1), earned: [], isShapeReadable: true) != nil)
        #expect(FirstWeek.make(firstDay: sunday, today: drawDay, earned: [], isShapeReadable: true) == nil)
        #expect(FirstWeek.make(firstDay: sunday, today: drawDay.adding(days: 40), earned: [], isShapeReadable: true) == nil)
    }

    @Test("A week without enough to read keeps the card, and stops promising a day")
    func lateWeekKeepsTheCard() throws {
        let today = sunday.adding(days: 9)
        let contract = try #require(
            FirstWeek.make(firstDay: sunday, today: today, earned: days([0, 8, 9], from: sunday), isShapeReadable: false)
        )
        #expect(!contract.isOpeningWeek)
        // The last seven only: days 3…9. Day 0 is outside it.
        #expect(contract.kept == 2)
        #expect(contract.sentence == "Your shape draws itself as the days add up. The last seven: two days kept.")
    }

    /// The same transition, driven by the real record and the real Shape.
    @Test("On a real record, the shape appears once there is a week behind it and enough to read")
    func transitionOnARealRecord() {
        let physical = Ritual.library.first { $0.category == .physical }!
        let intellect = Ritual.library.first { $0.category == .intellect }!
        let activities = [physical, intellect]

        func store(daysBack: Int) -> ProgressStore {
            let progress = ProgressStore(
                defaults: UserDefaults(suiteName: "forge.firstweek.\(UUID().uuidString)") ?? .standard
            )
            for back in 1...daysBack {
                let day = progress.currentDay.adding(days: -back)
                progress.record(DayRecord(
                    day: day,
                    completions: activities.map { .init(ritualID: $0.id, method: .honor, at: .now) },
                    plannedIDs: activities.map(\.id),
                    extractedAt: .now
                ))
            }
            return progress
        }

        let early = store(daysBack: 3)
        let earlyShape = early.forgeShape(of: activities)
        #expect(earlyShape.isReadable)
        let contract = early.firstWeek(isShapeReadable: earlyShape.isReadable)
        #expect(contract?.kept == 3)
        #expect(contract?.lived == 4)

        let later = store(daysBack: 8)
        let laterShape = later.forgeShape(of: activities)
        #expect(laterShape.isReadable)
        #expect(later.firstWeek(isShapeReadable: laterShape.isReadable) == nil)
    }

    // MARK: Words

    @Test("The contract, as written: on Sunday, three days kept of seven")
    func theExampleSentence() {
        let contract = FirstWeek.make(
            firstDay: sunday, today: sunday.adding(days: 3),
            earned: days([0, 1, 3], from: sunday), isShapeReadable: false
        )
        #expect(contract?.sentence == "Your shape draws itself on Sunday. Until then: three days kept of seven.")
    }

    @Test("Zero days is said as no days")
    func zeroDays() {
        let contract = FirstWeek.make(firstDay: sunday, today: sunday.adding(days: 2), earned: [], isShapeReadable: false)
        #expect(contract?.sentence == "Your shape draws itself on Sunday. Until then: no days kept of seven.")
        #expect(FirstWeek.days(0) == "no days")
    }

    @Test("One day is singular, never one days")
    func oneDay() {
        let contract = FirstWeek.make(
            firstDay: sunday, today: sunday.adding(days: 2), earned: [sunday], isShapeReadable: false
        )
        #expect(contract?.sentence == "Your shape draws itself on Sunday. Until then: one day kept of seven.")
        #expect(FirstWeek.days(1) == "one day")
    }

    @Test("Many days are plural and spelled; nothing ever reads 'one days'")
    func pluralDays() {
        #expect(FirstWeek.days(2) == "two days")
        #expect(FirstWeek.days(7) == "seven days")
        #expect(FirstWeek.days(21) == "twenty-one days")
        for count in 0...7 {
            let contract = FirstWeek.make(
                firstDay: sunday, today: sunday.adding(days: 6),
                earned: (0..<count).map { sunday.adding(days: $0) }, isShapeReadable: false
            )
            let sentence = contract?.sentence ?? ""
            #expect(!sentence.lowercased().contains("one days"))
            #expect(!sentence.contains("1 day"))
        }
    }

    @Test("The draw day is named the way a person would say it")
    func whenItDraws() {
        #expect(FirstWeek.make(firstDay: sunday, today: sunday, earned: [], isShapeReadable: false)?.when == "next Sunday")
        #expect(FirstWeek.make(firstDay: sunday, today: sunday.adding(days: 6), earned: [], isShapeReadable: false)?.when == "tomorrow")
        let wednesday = sunday.adding(days: 3)
        #expect(FirstWeek.make(firstDay: wednesday, today: wednesday.adding(days: 1), earned: [], isShapeReadable: false)?.when == "on Wednesday")
    }

    // MARK: Progress

    @Test("Progress is read off the record: days lived of seven, then the last seven's kept days")
    func progressFromTheRecord() {
        let opening = FirstWeek.make(
            firstDay: sunday, today: sunday.adding(days: 2), earned: [sunday], isShapeReadable: false
        )
        #expect(opening?.lived == 3)
        #expect(opening?.progress == 3.0 / 7.0)

        let late = FirstWeek.make(
            firstDay: sunday, today: sunday.adding(days: 10),
            earned: days([4, 5, 6, 9], from: sunday), isShapeReadable: false
        )
        #expect(late?.kept == 4)
        #expect(late?.progress == 4.0 / 7.0)

        // A day in the future, or counted twice, cannot inflate it.
        let noisy = FirstWeek.make(
            firstDay: sunday, today: sunday.adding(days: 2),
            earned: [sunday, sunday, sunday.adding(days: 5)], isShapeReadable: false
        )
        #expect(noisy?.kept == 1)
    }

    @Test("An empty record starts its week today")
    func emptyRecord() {
        let contract = FirstWeek.make(firstDay: nil, today: sunday, earned: [], isShapeReadable: false)
        #expect(contract?.start == sunday)
        #expect(contract?.lived == 1)
    }

    /// §5 rule #2. Reading the contract, the Shape and the starters writes
    /// nothing, and there is no key anywhere for a first week.
    @Test("No progress state is persisted — reading the first week writes nothing")
    func nothingIsStored() {
        let suite = UserDefaults(suiteName: "forge.firstweek.persist.\(UUID().uuidString)") ?? .standard
        let progress = ProgressStore(defaults: suite)
        progress.record(DayRecord(day: progress.currentDay.adding(days: -1), plannedIDs: ["water"], extractedAt: .now))
        let before = Set(suite.dictionaryRepresentation().keys)

        let shape = progress.forgeShape(of: [])
        _ = progress.firstWeek(isShapeReadable: shape.isReadable)
        _ = BecomingStarter.starters(in: shape, avoiding: [])

        #expect(Set(suite.dictionaryRepresentation().keys) == before)
        for key in ForgeShared.ownedKeys {
            let lowered = key.lowercased()
            #expect(!lowered.contains("firstweek") && !lowered.contains("first_week") && !lowered.contains("becoming"), Comment(rawValue: key))
        }
    }
}

// MARK: - Empty dimensions

@Suite("Becoming starters")
struct BecomingStarterTests {

    private func dimension(_ category: RitualCategory, activities: Int) -> ForgeShape.Dimension {
        ForgeShape.Dimension(
            category: category, score: 0, asked: 0, kept: 0,
            activityCount: activities, direction: .unknown
        )
    }

    @Test("An empty dimension is offered the smallest library activity filed under it")
    func smallestFromTheLibrary() throws {
        for category in RitualCategory.dimensions {
            guard let starter = BecomingStarter.starter(for: dimension(category, activities: 0), avoiding: []) else {
                continue
            }
            #expect(starter.category == category)
            #expect(Ritual.library.contains { $0.id == starter.id }, "never invented")
            let easiest = Ritual.library
                .filter { $0.category == category }
                .map { IdentityActivities.effort(of: $0.id) }
                .min()
            #expect(IdentityActivities.effort(of: starter.id) == easiest)
        }
        // Every one of the six has something to start with.
        #expect(RitualCategory.dimensions.allSatisfy {
            BecomingStarter.starter(for: dimension($0, activities: 0), avoiding: []) != nil
        })
    }

    @Test("A dimension with something filed under it gets no starter")
    func notForAStartedDimension() {
        #expect(BecomingStarter.starter(for: dimension(.physical, activities: 1), avoiding: []) == nil)
    }

    @Test("Something already kept is never offered")
    func avoidsWhatIsKept() throws {
        let first = try #require(BecomingStarter.starter(for: dimension(.mental, activities: 0), avoiding: []))
        let next = BecomingStarter.starter(for: dimension(.mental, activities: 0), avoiding: [first.id])
        #expect(next?.id != first.id)
    }

    @MainActor
    @Test("Adding from Becoming goes through the existing flow and reports source: becoming, and nothing else")
    func addReportsBecoming() throws {
        let progress = ProgressStore(
            defaults: UserDefaults(suiteName: "forge.becoming.add.\(UUID().uuidString)") ?? .standard
        )
        let forge = ForgeViewModel(progress: progress)
        // The day is set through the model's own API first. `ForgeViewModel`
        // reads the App Group suite every test shares (§14), and a suite that
        // had just put the whole library in the day (`CrowdedDayTests`) left
        // nothing here to add — an order-dependent failure, not a real one.
        forge.customRituals = []
        forge.libraryEdits = [:]
        forge.activeRitualIDs = Ritual.defaultActive
        let ritual = try #require(Ritual.library.first { !forge.activeRitualIDs.contains($0.id) })

        var sent: [ForgeTelemetry.Event] = []
        BecomingOffer.add(ritual, to: forge) { sent.append($0) }

        #expect(forge.activeRitualIDs.contains(ritual.id))
        #expect(sent == [.activityAdded(.becoming)])
        #expect(sent.first?.parameters == ["source": "becoming"])
        let payload = ForgeTelemetry.payload(for: .activityAdded(.becoming), daysSinceInstall: 0)
        #expect(!payload.values.contains(ritual.label))
        #expect(!payload.values.contains(ritual.id))
    }
}

// MARK: - The Proof Card

@Suite("Proof Card")
struct ProofCardTests {

    @Test("Days are said in words, and agree with their noun")
    func dayWords() {
        #expect(PracticeArtifact.dayWords(0) == "No days kept")
        #expect(PracticeArtifact.dayWords(1) == "One day kept")
        #expect(PracticeArtifact.dayWords(2) == "Two days kept")
        #expect(PracticeArtifact.dayWords(42) == "Forty-two days kept")
        // "Twenty-one days kept" is right; only a bare "one days" is wrong.
        for count in 0...120 {
            #expect(!PracticeArtifact.dayWords(count).lowercased().hasPrefix("one days"))
        }
    }

    @Test("Two formats: 1080 × 1920 and 1080 × 1080")
    func formats() {
        #expect(PracticeArtifact.Format.allCases.count == 2)
        #expect(PracticeArtifact.Format.portrait.size == CGSize(width: 1080, height: 1920))
        #expect(PracticeArtifact.Format.square.size == CGSize(width: 1080, height: 1080))
        #expect(PracticeArtifact.site == "forgebetter.app")
        #expect(ProofCardButton.title == "Save the proof")
    }

    @MainActor
    @Test("Each format renders a PNG at exactly its size")
    func rendersAtSize() throws {
        for format in PracticeArtifact.Format.allCases {
            let file = ProofCardFile(occasion: .chapter, daysKept: 12, date: .now, format: format)
            let image = try #require(UIImage(data: try file.png()))
            #expect(image.size.width * image.scale == format.size.width)
            #expect(image.size.height * image.scale == format.size.height)
        }
    }

    /// The Arc's card, in both shapes: "Winter Arc · Day 30 of 90", the blade,
    /// the six and OVR (DIRECTION_1_1 §5).
    @MainActor
    @Test("The Arc's card renders in 9:16 and 1:1")
    func arcCardRenders() throws {
        let proof = ArcProof(
            title: "Winter Arc \u{00B7} Day 30 of 90",
            scores: [62, 48, 71, nil, 55, 80],
            overall: 53,
            blade: "sword4",
            winters: 1
        )
        for format in PracticeArtifact.Format.allCases {
            let file = ProofCardFile(occasion: .arc(proof), daysKept: 30, date: .now, format: format)
            let image = try #require(UIImage(data: try file.png()))
            #expect(image.size.width * image.scale == format.size.width)
            #expect(image.size.height * image.scale == format.size.height)
        }
        #expect(PracticeArtifact.Occasion.arc(proof).line == "WINTER ARC \u{00B7} DAY 30 OF 90")
    }

    /// Exactly three doors. Reads the app's source: the Proof Card button is
    /// placed in the blade celebration, the chapter close and the running
    /// Arc's card and nowhere else, and nothing else in the app can open a
    /// share sheet.
    @Test("The Proof Card is offered at a blade unlock, a chapter close and an Arc, and nowhere else")
    func proofCardDoors() throws {
        let app = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Forge")
        var sources: [URL] = []
        let walker = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil)
        while let file = walker?.nextObject() as? URL {
            if file.pathExtension == "swift" { sources.append(file) }
        }
        #expect(sources.count > 20, "the source was not found — the check would pass vacuously")

        var doors: Set<String> = []
        var sharers: Set<String> = []
        for file in sources {
            let text = try String(contentsOf: file, encoding: .utf8)
            let name = file.lastPathComponent
            if name != "PracticeArtifact.swift", text.contains("ProofCardButton(") { doors.insert(name) }
            if text.contains("ShareLink(") || text.contains("UIActivityViewController") { sharers.insert(name) }
        }
        // The third, since 1.1: the running Arc's card (DIRECTION_1_1 §5). The
        // fourth: Becoming's Share your stats (§17.4).
        #expect(doors == [
            "SwordUnlockOverlay.swift", "ChapterCloseView.swift", "ArcsTabView.swift", "BecomingTabView.swift",
        ])
        #expect(sharers == ["PracticeArtifact.swift"])
    }
}

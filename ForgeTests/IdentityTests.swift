import Foundation
import Testing
@testable import Forge

/// Identity, and the three promises the spine makes.
///
/// The first is that it is **optional**: an install that never names one must be
/// exactly the app it was, and that has to be proven rather than asserted —
/// every activity on every phone is untagged today, and a migration that changed
/// anything for them would be the update breaking somebody's day.
///
/// The second is that **nothing is stored that can be derived**. Evidence is
/// counted out of the history on every read, so it cannot drift from it, and it
/// cannot go backwards on a bad week.
///
/// The third is that **retiring is not deleting**. An identity somebody pursued
/// for eight months explains eight months of their record, and the whole type is
/// shaped around never losing that.
@MainActor
@Suite("Identity")
struct IdentityTests {

    /// A store on its own scratch defaults, so tests never touch the
    /// simulator's — the same helper every other suite here uses.
    private func makeStore() -> IdentityStore {
        IdentityStore(
            defaults: UserDefaults(suiteName: "forge.identity.\(UUID().uuidString)") ?? .standard
        )
    }

    private func makeProgress() -> ProgressStore {
        ProgressStore(
            defaults: UserDefaults(suiteName: "forge.tests.\(UUID().uuidString)") ?? .standard
        )
    }

    /// A view model with a history of its own and nothing inherited.
    ///
    /// `ForgeViewModel` reads and writes the shared App Group suite that every
    /// test in the process has in common, so the day is cleared through the
    /// model's own properties on the way in. See `OnboardingDayTests`.
    private func makeViewModel() -> (ForgeViewModel, ProgressStore) {
        let progress = makeProgress()
        let vm = ForgeViewModel(progress: progress)
        vm.customRituals = []
        vm.libraryEdits = [:]
        vm.activeRitualIDs = Ritual.defaultActive
        return (vm, progress)
    }

    /// Writes a day into history: what was asked for, and what was done.
    private func record(
        _ store: ProgressStore, daysAgo back: Int, planned: [String], completed: [String]
    ) {
        let day = store.currentDay.adding(days: -back)
        store.record(
            DayRecord(
                day: day,
                completions: completed.map {
                    DayRecord.Completion(ritualID: $0, method: .honor, at: day.startOfDay())
                },
                plannedIDs: planned,
                extractedAt: day.startOfDay()
            )
        )
    }

    // MARK: - Optional, and off

    /// The whole of "nothing changes until you ask". If this drifts, every
    /// install in the world has quietly gained a feature nobody chose.
    @Test("A fresh install has no identities and no opinion about them")
    func defaultsToNone() {
        let store = makeStore()
        #expect(store.all.isEmpty)
        #expect(store.active.isEmpty)
        #expect(store.retired.isEmpty)
        #expect(store.isEmpty)
        #expect(store.canAddMore, "there is room from the first second")
    }

    @Test("Every shipped activity is untagged, and stays that way")
    func libraryShipsUntagged() {
        for ritual in Ritual.library {
            #expect(ritual.identityID == nil, "\(ritual.id) shipped carrying a tag")
        }
        #expect(ActivityDraft.blank().identityID == nil)
    }

    /// An untagged day is a complete day. This is the migration promise stated
    /// as arithmetic: somebody who never opens the feature earns days exactly as
    /// they did before it existed.
    @Test("An untagged day is earned exactly as it always was")
    func untaggedDayIsUnchanged() {
        let (vm, progress) = makeViewModel()
        let planned = vm.todayRitualIDs
        #expect(!planned.isEmpty)

        for id in planned {
            #expect(vm.ritual(id)?.identityID == nil)
            vm.keepPromise(id)
        }

        #expect(vm.allDone, "an untagged day still finishes")
        #expect(vm.totalDone == planned.count)
        #expect(progress.today.completedCount == planned.count)
    }

    // MARK: - Three, and no more

    /// Three is a product decision with a reason — see `Identity.activeLimit` —
    /// and a fourth has to be refused rather than silently dropped.
    @Test("Three may be pursued at once, and a fourth is refused")
    func activeLimitHolds() {
        let store = makeStore()
        #expect(store.add(statement: "Someone who trains") != nil)
        #expect(store.add(statement: "Someone who reads") != nil)
        #expect(store.add(statement: "Someone who builds things") != nil)

        #expect(!store.canAddMore)
        #expect(store.add(statement: "Someone who is up early") == nil, "a fourth got in")
        #expect(store.active.count == Identity.activeLimit)
    }

    /// The cap counts what is being pursued, not what has ever been named — or
    /// somebody whose life changed would be locked out by their own history.
    @Test("Retiring one makes room for another")
    func retiringFreesASlot() {
        let store = makeStore()
        let first = store.add(statement: "Someone who trains")
        _ = store.add(statement: "Someone who reads")
        _ = store.add(statement: "Someone who builds things")
        #expect(!store.canAddMore)

        store.retire(first!.id)

        #expect(store.canAddMore)
        #expect(store.add(statement: "Someone who is up early") != nil)
        #expect(store.active.count == 3)
        #expect(store.all.count == 4, "the retired one is still on file")
    }

    @Test("Restoring one is refused when three are already active")
    func restoreRespectsTheLimit() {
        let store = makeStore()
        let first = store.add(statement: "Someone who trains")!
        store.retire(first.id)
        _ = store.add(statement: "Someone who reads")
        _ = store.add(statement: "Someone who builds things")
        _ = store.add(statement: "Someone who is up early")

        store.restore(first.id)

        #expect(store.identity(first.id)?.isActive == false, "the cap was widened")
        #expect(store.active.count == 3)
    }

    @Test("A blank statement is refused rather than stored")
    func blankIsRefused() {
        let store = makeStore()
        #expect(store.add(statement: "   ") == nil)
        #expect(store.add(statement: "") == nil)
        #expect(store.all.isEmpty)
    }

    // MARK: - Retiring is not deleting

    /// The distinction the whole type is built around. A retired identity is
    /// still findable by id, because months of tagged history still refer to it.
    @Test("Retiring keeps the identity; deleting is a separate act")
    func retireKeepsAndDeleteRemoves() {
        let store = makeStore()
        let identity = store.add(statement: "Someone who trains")!

        store.retire(identity.id)
        #expect(store.identity(identity.id) != nil, "a retired identity must stay findable")
        #expect(store.identity(identity.id)?.isActive == false)
        #expect(store.identity(identity.id)?.retiredAt != nil)
        #expect(store.active.isEmpty)
        #expect(store.retired.count == 1)

        store.delete(identity.id, ledger: makeLedger())
        #expect(store.identity(identity.id) == nil)
        #expect(store.all.isEmpty)
    }

    /// Rewriting the sentence must not move the id, or every day of evidence
    /// behind it is orphaned — see `Identity.id`.
    @Test("Rewriting the statement keeps the id and the evidence")
    func rewritingKeepsTheID() {
        let store = makeStore()
        let identity = store.add(statement: "Someone who trains")!

        store.update(identity.id, statement: "Someone who is strong", accent: .gold)

        #expect(store.identity(identity.id)?.statement == "Someone who is strong")
        #expect(store.identity(identity.id)?.accent == .gold)
        #expect(store.all.count == 1, "a rewrite minted a second identity")
        #expect(store.all.first?.id == identity.id)
    }

    @Test("A deletion is written down so it can travel")
    func deletionLeavesATombstone() {
        let store = makeStore()
        let ledger = makeLedger()
        let identity = store.add(statement: "Someone who trains")!

        store.delete(identity.id, ledger: ledger)

        #expect(ledger.identityTombstones()[identity.id] != nil)
        // Retiring is not a deletion and must never reach the tombstones —
        // the other phone would throw away an identity somebody still has.
        let kept = store.add(statement: "Someone who reads")!
        store.retire(kept.id)
        #expect(ledger.identityTombstones()[kept.id] == nil)
    }

    private func makeLedger() -> SyncLedger {
        SyncLedger(
            defaults: UserDefaults(suiteName: "forge.ledger.\(UUID().uuidString)") ?? .standard
        )
    }

    // MARK: - Reading what is on disk

    /// One throw fails a whole array, and the array is the sentences somebody
    /// wrote about who they are. Only `id` may be required.
    @Test("A truncated payload decodes into something usable")
    func truncatedPayloadDecodes() throws {
        let json = Data(#"[{"id":"identity.abc"}]"#.utf8)
        let decoded = try JSONDecoder().decode([Identity].self, from: json)

        #expect(decoded.count == 1)
        #expect(decoded[0].id == "identity.abc")
        #expect(decoded[0].statement.isEmpty)
        #expect(decoded[0].symbol == ActivityIcons.fallback)
        #expect(decoded[0].accent == .forge)
        #expect(decoded[0].isActive)
    }

    /// A value written by a later build — an accent this one has never heard of
    /// — must land on something rather than throwing and taking the rest of the
    /// array with it.
    @Test("An accent from a future build reads as Forge's own")
    func foreignAccentDecodes() throws {
        let json = Data(
            #"""
            [{"id":"identity.a","statement":"Someone who trains","accent":"aurora","symbol":"flame"},
             {"id":"identity.b","statement":"Someone who reads","accent":"gold","symbol":"book"}]
            """#.utf8
        )
        let decoded = try JSONDecoder().decode([Identity].self, from: json)

        #expect(decoded.count == 2, "one unreadable accent cost the whole array")
        #expect(decoded[0].accent == .forge)
        #expect(decoded[1].accent == .gold)
    }

    @Test("An identity survives a round trip through disk")
    func roundTrips() throws {
        let original = Identity(
            statement: "Someone who finishes what they start",
            symbol: "checkmark.seal",
            accent: .ember,
            retiredAt: Date(timeIntervalSince1970: 1_000_000)
        )
        let data = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([Identity].self, from: data)

        #expect(decoded == [original])
        #expect(decoded[0].accent == .ember)
        #expect(decoded[0].isActive == false)
    }

    @Test("A statement longer than the limit is clamped rather than refused")
    func longStatementIsClamped() {
        let long = String(repeating: "a", count: Identity.statementLimit + 40)
        let identity = Identity(statement: long)
        #expect(identity.statement.count == Identity.statementLimit)
    }

    @Test("Identities persist across a relaunch")
    func persists() {
        let suite = UserDefaults(suiteName: "forge.identity.\(UUID().uuidString)") ?? .standard
        let first = IdentityStore(defaults: suite)
        let made = first.add(statement: "Someone who trains", accent: .gold)!

        let second = IdentityStore(defaults: suite)
        #expect(second.all.count == 1)
        #expect(second.identity(made.id)?.statement == "Someone who trains")
        #expect(second.identity(made.id)?.accent == .gold)
    }

    // MARK: - The prompts

    @Test("Every shipped prompt is a claim about a person")
    func promptsAreWellFormed() {
        for prompt in IdentityPrompt.allCases {
            #expect(prompt.statement.hasPrefix("Someone who"), "\(prompt.rawValue) is not a claim")
            #expect(prompt.statement.count <= Identity.statementLimit)
            #expect(!prompt.symbol.isEmpty)
        }
        #expect(Set(IdentityPrompt.allCases.map(\.statement)).count == IdentityPrompt.allCases.count)
    }

    @Test("Taking a prompt mints an ordinary identity the user owns")
    func promptsBecomeOrdinaryIdentities() {
        let store = makeStore()
        let made = store.add(.trains)!

        #expect(made.statement == IdentityPrompt.trains.statement)
        #expect(made.id.hasPrefix("identity."))
        // Editable immediately, and nothing records where it came from.
        store.update(made.id, statement: "Someone who lifts")
        #expect(store.identity(made.id)?.statement == "Someone who lifts")
    }

    // MARK: - Tagging

    @Test("Tagging an activity is an ordinary edit, and can be undone")
    func taggingIsAnOrdinaryEdit() {
        let (vm, _) = makeViewModel()

        vm.setIdentity("identity.a", on: "water")
        #expect(vm.ritual("water")?.identityID == "identity.a")
        #expect(vm.isEdited("water"), "the tag did not land as a library edit")

        vm.setIdentity(nil, on: "water")
        #expect(vm.ritual("water")?.identityID == nil)
        #expect(!vm.isEdited("water"), "untagging left the activity looking edited")
    }

    /// The double optional earning its keep. Without it there is no way to say
    /// "this was untagged on purpose" — see `RitualEdit.identityID`.
    @Test("A cleared tag is storable as a decision")
    func clearingIsExpressible() {
        var edit = RitualEdit()
        #expect(edit.isEmpty)

        edit.identityID = .some(nil)
        #expect(!edit.isEmpty, "an explicit untagging read as no edit at all")

        edit.identityID = .some("identity.a")
        #expect(edit.identityID == .some("identity.a"))
    }

    @Test("A tag survives a round trip through disk")
    func tagRoundTrips() throws {
        var edit = RitualEdit()
        edit.identityID = .some("identity.a")
        let data = try JSONEncoder().encode(["water": edit])
        let decoded = try JSONDecoder().decode([String: RitualEdit].self, from: data)
        #expect(decoded["water"]?.identityID == .some("identity.a"))

        let ritual = Ritual(
            id: "custom.x", label: "Lift", iconKey: "sparkle", sub: "", tail: "",
            isCustom: true, identityID: "identity.a"
        )
        let round = try JSONDecoder().decode(
            [Ritual].self, from: try JSONEncoder().encode([ritual])
        )
        #expect(round.first?.identityID == "identity.a")
    }

    /// A record written before tags existed has no such key, and must decode as
    /// untagged rather than throwing and taking every custom activity with it.
    @Test("An activity written before tags existed decodes untagged")
    func olderActivitiesDecode() throws {
        let json = Data(#"[{"id":"custom.old","label":"Read","iconKey":"book"}]"#.utf8)
        let decoded = try JSONDecoder().decode([Ritual].self, from: json)
        #expect(decoded.count == 1)
        #expect(decoded[0].identityID == nil)
    }

    @Test("Clearing an identity untags everything wearing it")
    func clearingIdentityUntagsTheDay() {
        let (vm, _) = makeViewModel()
        vm.setIdentity("identity.a", on: "water")
        vm.setIdentity("identity.a", on: "bed")
        vm.setIdentity("identity.b", on: "read")

        vm.clearIdentity("identity.a")

        #expect(vm.activityIDs(taggedTo: "identity.a").isEmpty)
        #expect(vm.activityIDs(taggedTo: "identity.b") == ["read"], "the wrong tag was cleared")
    }

    // MARK: - Evidence

    /// Days, not completions. Three activities finished on one Tuesday is one
    /// day of evidence — the unit of this app is a day, and counting otherwise
    /// would turn an identity into a score.
    @Test("Evidence counts days, not completions")
    func evidenceCountsDays() {
        let progress = makeProgress()
        record(progress, daysAgo: 1, planned: ["water", "bed", "read"],
               completed: ["water", "bed", "read"])
        record(progress, daysAgo: 2, planned: ["water", "bed"], completed: ["water"])

        #expect(progress.daysOfEvidence(taggedTo: ["water", "bed"]) == 2)
        #expect(progress.daysOfEvidence(taggedTo: ["read"]) == 1)
    }

    @Test("Nothing tagged is no evidence, and never a crash")
    func emptyTagSetIsZero() {
        let progress = makeProgress()
        record(progress, daysAgo: 1, planned: ["water"], completed: ["water"])

        #expect(progress.daysOfEvidence(taggedTo: []) == 0)
        #expect(progress.evidenceRate(taggedTo: []) == 0)
        #expect(progress.firstEvidence(taggedTo: []) == nil)
    }

    /// The same fairness rule `completionRate(for:)` follows: the denominator is
    /// days it was actually asked for, so an identity named last week is not
    /// punished for the months before it existed.
    @Test("The rate is measured over the days it was asked for")
    func rateIgnoresDaysItWasNotPlanned() {
        let progress = makeProgress()
        // Three days where it was asked for, met on two.
        record(progress, daysAgo: 1, planned: ["run"], completed: ["run"])
        record(progress, daysAgo: 2, planned: ["run"], completed: [])
        record(progress, daysAgo: 3, planned: ["run"], completed: ["run"])
        // A fortnight before it existed.
        record(progress, daysAgo: 10, planned: ["water"], completed: ["water"])
        record(progress, daysAgo: 11, planned: ["water"], completed: ["water"])

        let rate = progress.evidenceRate(taggedTo: ["run"])
        #expect(abs(rate - 2.0 / 3.0) < 0.0001)
    }

    /// Naming a thing is not the same as starting it. Somebody who has run for a
    /// year and writes the sentence today has a year of evidence, not none.
    @Test("Evidence starts where the record starts, not where the sentence does")
    func firstEvidencePredatesTheIdentity() {
        let progress = makeProgress()
        record(progress, daysAgo: 30, planned: ["run"], completed: ["run"])
        record(progress, daysAgo: 2, planned: ["run"], completed: ["run"])

        #expect(progress.firstEvidence(taggedTo: ["run"]) == progress.currentDay.adding(days: -30))
    }

    /// Derived, never stored — so it can be read twice and answer the same, and
    /// cannot go backwards on a bad week.
    @Test("Evidence is read out of the history rather than kept")
    func evidenceIsDerived() {
        let (vm, progress) = makeViewModel()
        vm.setIdentity("identity.a", on: "water")

        #expect(vm.daysOfEvidence(for: "identity.a") == 0)

        record(progress, daysAgo: 1, planned: ["water"], completed: ["water"])
        #expect(vm.daysOfEvidence(for: "identity.a") == 1, "the reading did not follow the record")

        record(progress, daysAgo: 2, planned: ["water"], completed: ["water"])
        #expect(vm.daysOfEvidence(for: "identity.a") == 2)
        #expect(vm.daysOfEvidence(for: "identity.a") == 2, "reading it twice changed the answer")

        // A day missed cannot take evidence away. Cumulative by construction.
        record(progress, daysAgo: 3, planned: ["water"], completed: [])
        #expect(vm.daysOfEvidence(for: "identity.a") == 2)
    }

    @Test("An identity with nothing tagged to it reads as no evidence")
    func untaggedIdentityHasNoEvidence() {
        let (vm, progress) = makeViewModel()
        record(progress, daysAgo: 1, planned: ["water"], completed: ["water"])

        #expect(vm.activityIDs(taggedTo: "identity.a").isEmpty)
        #expect(vm.daysOfEvidence(for: "identity.a") == 0)
        #expect(vm.firstEvidence(for: "identity.a") == nil)
    }

    // MARK: - Sync

    private func definition(
        _ id: String,
        statement: String = "Someone who trains",
        retiredAt: Date? = nil,
        isDeleted: Bool = false,
        at seconds: TimeInterval
    ) -> LocalPractice.IdentityDefinition {
        LocalPractice.IdentityDefinition(
            id: id,
            statement: statement,
            symbol: "flame",
            accent: "gold",
            createdAt: Date(timeIntervalSince1970: 0),
            retiredAt: retiredAt,
            isDeleted: isDeleted,
            updatedAt: Date(timeIntervalSince1970: seconds)
        )
    }

    @Test("The newer edit to an identity wins")
    func newerEditWins() {
        let outcome = SyncMerge.identities(
            local: [definition("identity.a", statement: "Someone who lifts", at: 200)],
            remote: [definition("identity.a", statement: "Someone who trains", at: 100)],
            pushedThrough: nil
        )
        #expect(outcome.merged.count == 1)
        #expect(outcome.merged[0].statement == "Someone who lifts")
        #expect(outcome.upload.count == 1, "the winning local version was not sent back")
    }

    /// Rule 2, applied here: every device sees the same server row, so deferring
    /// to it is the only tie-break that makes two phones converge.
    @Test("On an exact tie the server wins")
    func serverWinsATie() {
        let outcome = SyncMerge.identities(
            local: [definition("identity.a", statement: "Someone who lifts", at: 100)],
            remote: [definition("identity.a", statement: "Someone who trains", at: 100)],
            pushedThrough: nil
        )
        #expect(outcome.merged[0].statement == "Someone who trains")
        #expect(outcome.upload.isEmpty, "a settled row was echoed straight back")
    }

    /// The cap is the reason this is unioned rather than last-writer-wins. A
    /// device that was in a drawer must not resurrect a retired identity and
    /// leave the account holding four active ones.
    @Test("Retirement is unioned, so an old device cannot undo it")
    func retirementIsUnioned() {
        let retired = Date(timeIntervalSince1970: 50)
        let outcome = SyncMerge.identities(
            // The stale device: newer edit, but it never heard about the retirement.
            local: [definition("identity.a", statement: "Someone who lifts", at: 900)],
            remote: [definition("identity.a", retiredAt: retired, at: 100)],
            pushedThrough: nil
        )
        #expect(outcome.merged[0].retiredAt == retired, "a retirement was undone by a stale edit")
        #expect(outcome.merged[0].statement == "Someone who lifts", "the newer edit was lost")
    }

    @Test("The earlier of two retirements is the true one")
    func earliestRetirementWins() {
        let outcome = SyncMerge.identities(
            local: [definition("identity.a", retiredAt: Date(timeIntervalSince1970: 500), at: 900)],
            remote: [definition("identity.a", retiredAt: Date(timeIntervalSince1970: 200), at: 100)],
            pushedThrough: nil
        )
        #expect(outcome.merged[0].retiredAt == Date(timeIntervalSince1970: 200))
    }

    /// A deletion outranks an edit on either side, or an older device that
    /// merely changed a symbol hands a thrown-away identity straight back.
    @Test("A deletion is never undone by an edit that did not know about it")
    func deletionOutranksAnEdit() {
        let outcome = SyncMerge.identities(
            local: [definition("identity.a", statement: "Someone who lifts", at: 900)],
            remote: [definition("identity.a", isDeleted: true, at: 100)],
            pushedThrough: nil
        )
        #expect(outcome.merged[0].isDeleted)
        #expect(outcome.merged[0].identity == nil, "a tombstone resolved to a drawable identity")
    }

    @Test("An identity the phone has never seen arrives without being echoed")
    func unseenIdentityArrives() {
        let outcome = SyncMerge.identities(
            local: [],
            remote: [definition("identity.a", at: 100)],
            pushedThrough: nil
        )
        #expect(outcome.merged.count == 1)
        #expect(outcome.upload.isEmpty, "a row we just received was sent straight back")
    }

    /// Nothing has ever gone up from this install, so everything local is
    /// outstanding — the same rule that makes a first sign-in a migration
    /// rather than its own code path.
    @Test("With no watermark every local identity is offered")
    func firstSignInOffersEverything() {
        let outcome = SyncMerge.identities(
            local: [definition("identity.a", at: 100), definition("identity.b", at: 200)],
            remote: [],
            pushedThrough: nil
        )
        #expect(outcome.upload.count == 2)
    }

    @Test("A different account's identities do not take part")
    func foreignPracticeHandsOver() {
        var local = LocalPractice.empty()
        local.identities = [definition("identity.mine", at: 100)]
        var remote = RemotePractice()
        remote.identities = [definition("identity.theirs", at: 50)]

        let merge = SyncMerge.merge(
            local: local, remote: remote, pushedThrough: nil, localIsForeign: true
        )

        #expect(merge.practice.identities.map(\.id) == ["identity.theirs"])
        #expect(merge.upload.isEmpty, "one person's identity was offered to another's account")
    }

    /// The tag has to travel or the spine does not survive a new phone: the
    /// identities would arrive, every activity would land untagged, and every
    /// reading would honestly report zero for a year of practice.
    @Test("An activity's tag survives the wire")
    func activityTagTravels() throws {
        let definition = LocalPractice.ActivityDefinition(
            id: "water", label: "Water", isCustom: false, isDeleted: false,
            identityID: "identity.a", updatedAt: Date(timeIntervalSince1970: 100)
        )
        let row = ActivityRow(userID: "u", definition: definition)
        #expect(row.identityID == "identity.a")
        #expect(row.definition.identityID == "identity.a")
        // And it is part of what makes a definition look changed, or a tag
        // applied on one phone would never be noticed as dirty by the ledger.
        var untagged = definition
        untagged.identityID = nil
        #expect(untagged.fingerprint != definition.fingerprint)
    }

    /// A row written before the column existed. It must read as untagged rather
    /// than failing the pull and costing somebody every activity they own.
    @Test("An activity row from before the column decodes untagged")
    func olderActivityRowDecodes() throws {
        let json = Data(
            #"""
            {"user_id":"u","id":"water","is_custom":false,"is_deleted":false,
             "updated_at":"1970-01-01T00:00:00Z","synced_at":"1970-01-01T00:00:00Z"}
            """#.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let row = try decoder.decode(ActivityRow.self, from: json)
        #expect(row.id == "water")
        #expect(row.identityID == nil)
    }
}

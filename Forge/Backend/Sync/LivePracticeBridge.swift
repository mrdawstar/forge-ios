import Foundation

/// The only place the backend touches the app.
///
/// Everything below this file works on values; everything above it works on
/// `@Observable` stores. This is the seam, and keeping it to one type with two
/// methods is what stops "we added sync" from meaning "every store now has a
/// server in it".
///
/// It holds the stores weakly on purpose. `ContentView` owns them for the life
/// of the process and this object is owned by the backend, which the same view
/// also owns — a strong reference in both directions would be a cycle whose
/// only symptom is that a screenshot of the memory graph looks slightly wrong,
/// which is exactly the kind of bug that survives for years.
@MainActor
final class LivePracticeBridge: PracticeBridge {

    private weak var progress: ProgressStore?
    private weak var forge: ForgeViewModel?
    private weak var swords: SwordStore?
    private weak var identities: IdentityStore?
    /// The two stores added by the return loop. Weak and optional like the
    /// others: a missing store means an account with no chapters and no
    /// reviews, which is exactly what an install that has never had one has.
    private weak var chapters: ChapterStore?
    private weak var reviews: ReviewStore?
    private let ledger: SyncLedger

    /// `identities` is optional so that every existing construction site — and
    /// every test that only cares about days — keeps working unchanged. A
    /// missing store means an account with no identities, which is exactly what
    /// the great majority of them have.
    init(
        progress: ProgressStore,
        forge: ForgeViewModel,
        swords: SwordStore,
        identities: IdentityStore? = nil,
        chapters: ChapterStore? = nil,
        reviews: ReviewStore? = nil,
        ledger: SyncLedger
    ) {
        self.progress = progress
        self.forge = forge
        self.swords = swords
        self.identities = identities
        self.chapters = chapters
        self.reviews = reviews
        self.ledger = ledger
    }

    // MARK: - Reading

    func snapshot() -> LocalPractice {
        guard let progress, let forge, let swords else { return .empty() }

        var settings = LocalPractice.Settings(
            dayStartHour: progress.dayStartHour,
            restWeekdays: progress.restWeekdays,
            firstRunCompleted: forge.hasCompletedFirstRun,
            verificationMemory: forge.verificationMemory,
            updatedAt: .distantPast
        )
        settings.updatedAt = ledger.stamp(
            for: SyncLedger.StampKey.settings, fingerprint: settings.fingerprint
        )

        var arrangement = LocalPractice.Arrangement(
            activityIDs: forge.activeRitualIDs,
            updatedAt: .distantPast
        )
        arrangement.updatedAt = ledger.stamp(
            for: SyncLedger.StampKey.arrangement, fingerprint: arrangement.fingerprint
        )

        var blades = LocalPractice.Blades(
            equippedID: swords.equippedID,
            acknowledgedIDs: swords.acknowledgedIDs,
            celebratedIDs: swords.celebratedIDs,
            updatedAt: .distantPast
        )
        blades.updatedAt = ledger.stamp(
            for: SyncLedger.StampKey.blades, fingerprint: blades.fingerprint
        )

        let activities = definitions(from: forge)
        let identities = identityDefinitions()
        // Anything whose activity or identity no longer exists in any form is
        // dropped, so the ledger does not accumulate one entry per thing
        // anybody has ever made and abandoned.
        ledger.pruneStamps(
            keeping: Set(activities.map { SyncLedger.StampKey.activity($0.id) })
                .union(identities.map { SyncLedger.StampKey.identity($0.id) })
                .union([
                    SyncLedger.StampKey.settings,
                    SyncLedger.StampKey.arrangement,
                    SyncLedger.StampKey.blades,
                ])
        )

        return LocalPractice(
            settings: settings,
            activities: activities,
            arrangement: arrangement,
            days: progress.records,
            blades: blades,
            identities: identities,
            // Straight off the stores. Neither needs a ledger stamp: both carry
            // their own `updatedAt` and neither has a tombstone — a chapter is
            // closed rather than deleted and a review is dismissed rather than
            // removed, so there is no absence to distinguish from a deletion.
            chapters: chapters?.all ?? [],
            reviews: reviews?.reviews ?? []
        )
    }

    /// Every identity this account owns, tombstones included.
    ///
    /// The same three-source shape as `definitions` below — what exists, and
    /// what was thrown away — minus the library half, because there are no
    /// shipped identities to overlay edits onto. `IdentityPrompt` looks like one
    /// and is not: taking a prompt mints an ordinary identity the user owns, and
    /// nothing records which prompt it came from.
    private func identityDefinitions() -> [LocalPractice.IdentityDefinition] {
        var all: [LocalPractice.IdentityDefinition] = []

        for identity in identities?.all ?? [] {
            var definition = LocalPractice.IdentityDefinition(
                identity, updatedAt: .distantPast
            )
            definition.updatedAt = ledger.stamp(
                for: SyncLedger.StampKey.identity(identity.id),
                fingerprint: definition.fingerprint
            )
            all.append(definition)
        }

        // Deletions carry the moment somebody pressed delete rather than a
        // noticed-at stamp, because unlike everything else here the app knows
        // exactly when it happened.
        let live = Set(all.map(\.id))
        for (id, at) in ledger.identityTombstones() where !live.contains(id) {
            all.append(
                LocalPractice.IdentityDefinition(
                    id: id,
                    statement: "",
                    symbol: "",
                    accent: "",
                    createdAt: at,
                    retiredAt: nil,
                    isDeleted: true,
                    updatedAt: at
                )
            )
        }

        return all.sorted { $0.id < $1.id }
    }

    /// Every activity definition this account owns, in one list.
    ///
    /// Three sources and one shape: the activities somebody invented, the
    /// changes they made to ones Forge ships, and the ones they threw away. The
    /// third is why this cannot simply be `customRituals` — a deletion has to
    /// travel, and an activity that is merely absent is indistinguishable from
    /// one the other phone has not sent yet.
    private func definitions(from forge: ForgeViewModel) -> [LocalPractice.ActivityDefinition] {
        var all: [LocalPractice.ActivityDefinition] = []

        for ritual in forge.customRituals {
            var definition = LocalPractice.ActivityDefinition(
                id: ritual.id,
                label: ritual.label,
                symbol: ritual.symbolName,
                goal: ritual.tail,
                verification: ritual.verificationOverride,
                isCustom: true,
                isDeleted: false,
                identityID: ritual.identityID,
                updatedAt: .distantPast
            )
            definition.updatedAt = ledger.stamp(
                for: SyncLedger.StampKey.activity(ritual.id),
                fingerprint: definition.fingerprint
            )
            all.append(definition)
        }

        for (id, edit) in forge.libraryEdits where !edit.isEmpty {
            var definition = LocalPractice.ActivityDefinition(
                id: id,
                label: edit.label,
                symbol: edit.symbol,
                goal: edit.tail,
                verification: edit.verification,
                isCustom: false,
                isDeleted: false,
                // Flattened from the double optional. The wire carries "what is
                // the tag" and not "did somebody decide about the tag", so an
                // explicit untagging reads on the other device as never having
                // been tagged. That costs nothing — both states are untagged —
                // and it is the same flattening the four fields above already
                // do.
                identityID: edit.identityID ?? nil,
                updatedAt: .distantPast
            )
            definition.updatedAt = ledger.stamp(
                for: SyncLedger.StampKey.activity(id),
                fingerprint: definition.fingerprint
            )
            all.append(definition)
        }

        // Tombstones carry the moment of deletion rather than a noticed-at
        // stamp, because unlike everything else here the app knows exactly when
        // this happened: somebody pressed delete.
        let live = Set(all.map(\.id))
        for (id, at) in ledger.tombstones() where !live.contains(id) {
            all.append(
                LocalPractice.ActivityDefinition(
                    id: id,
                    label: nil, symbol: nil, goal: nil, verification: nil,
                    isCustom: id.hasPrefix("custom."),
                    isDeleted: true,
                    updatedAt: at
                )
            )
        }

        return all.sorted { $0.id < $1.id }
    }

    // MARK: - Writing

    func apply(_ practice: LocalPractice) {
        guard let progress, let forge, let swords else { return }

        progress.adopt(
            dayStartHour: practice.settings.dayStartHour,
            restWeekdays: practice.settings.restWeekdays
        )
        progress.adopt(practice.days)

        var customs: [Ritual] = []
        var edits: [String: RitualEdit] = [:]

        for definition in practice.activities {
            guard !definition.isDeleted else {
                // A deletion that arrived from another device. Recorded locally
                // too, so this phone will keep telling a third one about it.
                ledger.recordTombstone(definition.id, at: definition.updatedAt)
                continue
            }
            ledger.clearTombstone(definition.id)

            if definition.isCustom {
                customs.append(
                    Ritual(
                        id: definition.id,
                        label: definition.label ?? "",
                        // Custom activities have always resolved their glyph
                        // through `symbolName`; the key is what the row shape
                        // needs, not something the user ever chose.
                        iconKey: "sparkle",
                        sub: "",
                        tail: definition.goal ?? "",
                        symbolName: definition.symbol,
                        isCustom: true,
                        verificationOverride: definition.verification,
                        identityID: definition.identityID
                    )
                )
            } else {
                var edit = RitualEdit()
                edit.label = definition.label
                edit.symbol = definition.symbol
                edit.verification = definition.verification
                edit.tail = definition.goal
                // Only when there is one. Writing `.some(nil)` for every
                // untagged activity would mark the whole library as edited on
                // arrival, and "reset to default" would have a tag-shaped
                // nothing to undo on all of it.
                if let identityID = definition.identityID {
                    edit.identityID = .some(identityID)
                }
                if !edit.isEmpty { edits[definition.id] = edit }
            }
        }

        forge.adopt(
            firstRunCompleted: practice.settings.firstRunCompleted,
            verificationMemory: practice.settings.verificationMemory,
            customRituals: customs,
            libraryEdits: edits,
            activeRitualIDs: practice.arrangement.activityIDs
        )

        swords.adopt(
            equippedID: practice.blades.equippedID,
            acknowledgedIDs: practice.blades.acknowledgedIDs,
            celebratedIDs: practice.blades.celebratedIDs
        )

        adoptIdentities(practice.identities)
        chapters?.adopt(practice.chapters)
        reviews?.adopt(practice.reviews)
    }

    /// Take on the identities a merge decided.
    ///
    /// Tombstones are recorded locally rather than applied as absences, so this
    /// phone keeps telling a third device about a deletion it heard from a
    /// second — the same thing `apply` does for a deleted activity above.
    ///
    /// Ordered by when they were named, oldest first, because that is the order
    /// `IdentityStore` holds them in and the only one somebody can predict.
    private func adoptIdentities(_ definitions: [LocalPractice.IdentityDefinition]) {
        guard let identities else { return }

        var live: [Identity] = []
        for definition in definitions {
            guard let identity = definition.identity else {
                ledger.recordIdentityTombstone(definition.id, at: definition.updatedAt)
                continue
            }
            ledger.clearIdentityTombstone(definition.id)
            live.append(identity)
        }

        identities.adopt(live.sorted { $0.createdAt < $1.createdAt })
    }
}

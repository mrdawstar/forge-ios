import Foundation

/// Everything about a practice that is worth keeping, as one value.
///
/// The boundary between Forge and the cloud, and the reason the sync engine can
/// be reasoned about at all. Above this line are five `@Observable` stores that
/// own the app's behaviour; below it is a struct with no behaviour whatsoever,
/// which merges, encodes and compares. Nothing in `Sync` has a reference to
/// `ProgressStore`, and nothing in `ProgressStore` has heard of a server.
struct LocalPractice: Equatable, Sendable {

    var settings: Settings
    /// Definitions: the activities somebody invented, and the changes they made
    /// to the ones Forge ships. Both, because the app has one edit path for both
    /// and the difference is not the user's to notice.
    var activities: [ActivityDefinition]
    var arrangement: Arrangement
    var days: [DayRecord]
    var blades: Blades
    /// Who somebody says they are becoming. See `Identity`.
    ///
    /// Kept beside the activity definitions rather than inside `Settings`,
    /// because it is a list that grows and is edited per-item — the same shape
    /// as `activities`, and it wants the same per-id last-writer-wins merge
    /// rather than one timestamp covering the whole set.
    var identities: [IdentityDefinition] = []
    /// The six-week arcs, and what somebody wrote about their weeks.
    ///
    /// Practice data in exactly the sense the others are: a chapter is a window
    /// somebody named over their own history and a review is two sentences they
    /// wrote, and neither is recoverable from anything else. A new phone without
    /// them restores the days and loses the meaning that was put on them.
    ///
    /// Carried as the model types rather than as a wire-shaped `Definition`,
    /// which is the one place this differs from identities and activities: both
    /// are already `Codable` value types with a tolerant decoder and an
    /// `updatedAt`, so a second representation would be a second decoder to keep
    /// correct for no gain. See `Chapter.updatedAt`.
    var chapters: [Chapter] = []
    var reviews: [WeeklyReview] = []

    // MARK: - The parts

    /// What shapes a day, rather than what happened in one.
    struct Settings: Equatable, Sendable {
        var dayStartHour: Int
        /// 1 = Sunday.
        var restWeekdays: Set<Int>
        /// Monotonic: true never becomes false again. Arriving on a new phone
        /// and being walked through onboarding for a practice you have kept for
        /// a year would be the app failing to recognise you.
        var firstRunCompleted: Bool
        var verificationMemory: VerificationMemory
        var updatedAt: Date

        var fingerprint: String {
            let tokens = verificationMemory.tokenPreferences
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ",")
            let tally = verificationMemory.overrideTally
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ",")
            return "\(dayStartHour)|\(restWeekdays.sorted())|\(firstRunCompleted)|\(tokens)|\(tally)"
        }
    }

    struct ActivityDefinition: Equatable, Sendable, Identifiable {
        /// `custom.<uuid>` for one somebody made, or a library id like `water`.
        let id: String
        var label: String?
        var symbol: String?
        var goal: String?
        var verification: VerificationMethod?
        var isCustom: Bool
        /// A tombstone. Thrown-away activities are kept as a fact rather than
        /// as an absence, because an absence is what an activity that has not
        /// arrived yet also looks like.
        var isDeleted: Bool
        /// Who this activity is evidence for. See `Ritual.identityID`.
        ///
        /// It travels because without it the spine does not survive a new
        /// phone: the identities would arrive, every activity would land
        /// untagged, and every reading of evidence would honestly report zero
        /// for a practice somebody had kept for a year.
        var identityID: String?
        var updatedAt: Date

        var fingerprint: String {
            [
                id, label ?? "", symbol ?? "", goal ?? "",
                verification?.rawValue ?? "", "\(isCustom)", "\(isDeleted)",
                identityID ?? "",
            ].joined(separator: "|")
        }

        init(
            id: String,
            label: String? = nil,
            symbol: String? = nil,
            goal: String? = nil,
            verification: VerificationMethod? = nil,
            isCustom: Bool,
            isDeleted: Bool,
            identityID: String? = nil,
            updatedAt: Date
        ) {
            self.id = id
            self.label = label
            self.symbol = symbol
            self.goal = goal
            self.verification = verification
            self.isCustom = isCustom
            self.isDeleted = isDeleted
            self.identityID = identityID
            self.updatedAt = updatedAt
        }
    }

    /// One identity on the wire.
    ///
    /// Deliberately not `Identity` itself. `Identity` is a UI-facing value with
    /// a `ForgeAccent` on it; this is the row, and it carries the accent as the
    /// raw string the column actually holds — so a world's palette can be
    /// renumbered without a migration on somebody's identities.
    ///
    /// `isDeleted` is a tombstone for the reason `ActivityDefinition.isDeleted`
    /// is one: an identity that is merely absent is indistinguishable from one
    /// the other phone has not sent yet, so a deletion would be undone by the
    /// next sync. Retirement is **not** deletion and travels as `retiredAt`.
    struct IdentityDefinition: Equatable, Sendable, Identifiable {
        /// `identity.<uuid>`.
        let id: String
        var statement: String
        var symbol: String
        /// `ForgeAccent.rawValue`. Anything unrecognised reads as Forge's own on
        /// the way back in, which costs a tint and never a fact.
        var accent: String
        var createdAt: Date
        var retiredAt: Date?
        var isDeleted: Bool
        var updatedAt: Date

        var fingerprint: String {
            [
                id, statement, symbol, accent,
                retiredAt.map { "\($0.timeIntervalSince1970)" } ?? "",
                "\(isDeleted)",
            ].joined(separator: "|")
        }

        init(
            id: String,
            statement: String,
            symbol: String,
            accent: String,
            createdAt: Date,
            retiredAt: Date? = nil,
            isDeleted: Bool = false,
            updatedAt: Date
        ) {
            self.id = id
            self.statement = statement
            self.symbol = symbol
            self.accent = accent
            self.createdAt = createdAt
            self.retiredAt = retiredAt
            self.isDeleted = isDeleted
            self.updatedAt = updatedAt
        }

        init(_ identity: Identity, isDeleted: Bool = false, updatedAt: Date) {
            self.init(
                id: identity.id,
                statement: identity.statement,
                symbol: identity.symbol,
                accent: identity.accent.rawValue,
                createdAt: identity.createdAt,
                retiredAt: identity.retiredAt,
                isDeleted: isDeleted,
                updatedAt: updatedAt
            )
        }

        /// Back into the app's own value. Nil for a tombstone, which is a fact
        /// about a deletion rather than an identity to draw.
        var identity: Identity? {
            guard !isDeleted else { return nil }
            return Identity(
                id: id,
                statement: statement,
                symbol: symbol,
                accent: ForgeAccent(rawValue: accent) ?? .forge,
                createdAt: createdAt,
                retiredAt: retiredAt
            )
        }
    }

    /// The day itself: which activities, in which order.
    struct Arrangement: Equatable, Sendable {
        var activityIDs: [String]
        var updatedAt: Date

        var fingerprint: String { activityIDs.joined(separator: ",") }
    }

    struct Blades: Equatable, Sendable {
        var equippedID: Int
        var acknowledgedIDs: Set<Int>
        var celebratedIDs: Set<Int>
        var updatedAt: Date

        var fingerprint: String {
            "\(equippedID)|\(acknowledgedIDs.sorted())|\(celebratedIDs.sorted())"
        }
    }

    // MARK: - Noticing a change
    //
    // Everything except a day is a single small value with no timestamp of
    // its own — `ProgressStore` has never written down when somebody last
    // reordered their activities, and adding that to five stores to serve the
    // cloud would be the backend reaching up into the app.
    //
    // So the sync engine works it out by looking. Each of these renders the
    // fields that constitute a change, deliberately *without* the stamp, and
    // the ledger remembers what it last saw: same string, same moment; new
    // string, this moment. The stamp is therefore "when Forge first noticed",
    // which for a value the user edits inside the app is the same second they
    // edited it.

    // MARK: - The parts, fingerprinted

    /// A practice with nothing in it. The state a brand-new account pulls into.
    static func empty(at instant: Date = .distantPast) -> LocalPractice {
        LocalPractice(
            settings: Settings(
                dayStartHour: 4,
                restWeekdays: [],
                firstRunCompleted: false,
                verificationMemory: .empty,
                updatedAt: instant
            ),
            activities: [],
            arrangement: Arrangement(activityIDs: [], updatedAt: instant),
            days: [],
            blades: Blades(
                equippedID: 1, acknowledgedIDs: [], celebratedIDs: [], updatedAt: instant
            ),
            identities: []
        )
    }

    /// Whether there is anything here worth uploading. Read once, before the
    /// first sign-in, to decide whether migration has any work to do.
    var isEmpty: Bool {
        days.isEmpty && activities.isEmpty && arrangement.activityIDs.isEmpty
            && identities.isEmpty
    }
}

/// How the sync engine reaches the app.
///
/// A protocol with two methods, and the whole of the coupling between the
/// backend and everything that existed before it. `SyncService` is written
/// against this and tested against a struct that implements it in nine lines;
/// the real one hands out `ProgressStore`, `ForgeViewModel` and `SwordStore`.
@MainActor
protocol PracticeBridge: AnyObject {
    /// What the phone currently holds.
    func snapshot() -> LocalPractice
    /// Take on what the merge decided. Called on the main actor, and expected
    /// to be immediate: this is somebody's history changing under a screen they
    /// may be looking at.
    func apply(_ practice: LocalPractice)
}

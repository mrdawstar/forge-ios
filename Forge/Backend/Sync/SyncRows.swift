import Foundation

/// The wire.
///
/// One type per table, and they exist so that nothing else in Forge has to
/// spell a column name. If Supabase were swapped for something else tomorrow,
/// this file and the two in `Net` are what would be rewritten; `SyncMerge`,
/// `LocalPractice` and every store above them would not be touched.
///
/// Each row decodes `synced_at` and never encodes it. That is not fussiness:
/// the column is the server's own record of when a row arrived, it is `not
/// null`, and sending our idea of it would either be rejected or — worse —
/// accepted, and quietly corrupt the cursor every device pages through history
/// with.
protocol SyncedRow: Decodable {
    var syncedAt: Date? { get }
}

// MARK: - Days on the wire

extension ForgeDay {
    /// `2026-08-04`, which is what a Postgres `date` column is.
    ///
    /// Built by hand rather than through a `DateFormatter`, because a formatter
    /// would need a calendar and a timezone to render a value that has
    /// deliberately been stripped of both. There is nothing to get wrong here
    /// and no locale that spells this differently.
    var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    init?(isoString: String) {
        let parts = isoString.prefix(10).split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        self.init(year: year, month: month, day: day)
    }
}

// MARK: - profiles

struct ProfileRow: SyncedRow {
    let id: String
    let dayStartHour: Int
    let restWeekdays: [Int]
    let firstRunCompleted: Bool
    let verificationMemory: VerificationMemory
    let updatedAt: Date
    let syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case dayStartHour = "day_start_hour"
        case restWeekdays = "rest_weekdays"
        case firstRunCompleted = "first_run_completed"
        case verificationMemory = "verification_memory"
        case updatedAt = "updated_at"
        case syncedAt = "synced_at"
    }

    init(userID: String, settings: LocalPractice.Settings) {
        id = userID
        dayStartHour = settings.dayStartHour
        restWeekdays = settings.restWeekdays.sorted()
        firstRunCompleted = settings.firstRunCompleted
        verificationMemory = settings.verificationMemory
        updatedAt = settings.updatedAt
        syncedAt = nil
    }

    /// The row the signup trigger made, that no device has ever written to.
    ///
    /// `0001` dates it from `'epoch'` rather than `now()` precisely so it loses
    /// every comparison — but losing is not the same as being absent, and the
    /// difference costs somebody their settings. A person who has kept days
    /// on this phone for a year now dates their own untouched values from the
    /// beginning of time too, because until this sync the ledger had never been
    /// asked about them. Epoch beats the beginning of time, so the placeholder
    /// would win and reset the hour their day starts.
    ///
    /// It is not a value. It is the absence of one, and it is read as such.
    var isPlaceholder: Bool { updatedAt == Self.placeholder }

    /// Postgres `'epoch'`, exactly: `1970-01-01T00:00:00Z`. Compared for
    /// equality rather than with `<=`, so that a real row this app wrote and
    /// dated from the beginning of time is still a real row.
    static let placeholder = Date(timeIntervalSince1970: 0)

    var settings: LocalPractice.Settings {
        LocalPractice.Settings(
            dayStartHour: dayStartHour,
            restWeekdays: Set(restWeekdays),
            firstRunCompleted: firstRunCompleted,
            verificationMemory: verificationMemory,
            updatedAt: updatedAt
        )
    }
}

extension ProfileRow: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(dayStartHour, forKey: .dayStartHour)
        try container.encode(restWeekdays, forKey: .restWeekdays)
        try container.encode(firstRunCompleted, forKey: .firstRunCompleted)
        try container.encode(verificationMemory, forKey: .verificationMemory)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

// MARK: - devices

struct DeviceRow: SyncedRow, Encodable {
    let id: String
    let userID: String
    let name: String?
    let model: String?
    let systemVersion: String?
    let appVersion: String?
    let lastSeenAt: Date
    let updatedAt: Date
    let syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case model
        case systemVersion = "system_version"
        case appVersion = "app_version"
        case lastSeenAt = "last_seen_at"
        case updatedAt = "updated_at"
        case syncedAt = "synced_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(systemVersion, forKey: .systemVersion)
        try container.encodeIfPresent(appVersion, forKey: .appVersion)
        try container.encode(lastSeenAt, forKey: .lastSeenAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

// MARK: - activities

struct ActivityRow: SyncedRow, Encodable {
    let userID: String
    let id: String
    let label: String?
    let symbol: String?
    let goal: String?
    let verification: VerificationMethod?
    let isCustom: Bool
    let isDeleted: Bool
    let identityID: String?
    let updatedAt: Date
    let syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case id
        case label
        case symbol
        case goal
        case verification
        case isCustom = "is_custom"
        case isDeleted = "is_deleted"
        case identityID = "identity_id"
        case updatedAt = "updated_at"
        case syncedAt = "synced_at"
    }

    init(userID: String, definition: LocalPractice.ActivityDefinition) {
        self.userID = userID
        id = definition.id
        label = definition.label
        symbol = definition.symbol
        goal = definition.goal
        verification = definition.verification
        isCustom = definition.isCustom
        isDeleted = definition.isDeleted
        identityID = definition.identityID
        updatedAt = definition.updatedAt
        syncedAt = nil
    }

    /// Decoded by hand for the one key that is younger than the table.
    ///
    /// A row written before `identity_id` existed simply has no such key, and
    /// the synthesised decoder is fine with that for an `Optional` — but the
    /// column is also the first here that an older *client* will never send, so
    /// spelling the decode out keeps the tolerance visible rather than implied.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userID = try c.decode(String.self, forKey: .userID)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol)
        goal = try c.decodeIfPresent(String.self, forKey: .goal)
        verification = try c.decodeIfPresent(VerificationMethod.self, forKey: .verification)
        isCustom = try c.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
        isDeleted = try c.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        identityID = try c.decodeIfPresent(String.self, forKey: .identityID)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        syncedAt = try c.decodeIfPresent(Date.self, forKey: .syncedAt)
    }

    var definition: LocalPractice.ActivityDefinition {
        LocalPractice.ActivityDefinition(
            id: id,
            label: label,
            symbol: symbol,
            goal: goal,
            verification: verification,
            isCustom: isCustom,
            isDeleted: isDeleted,
            identityID: identityID,
            updatedAt: updatedAt
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(symbol, forKey: .symbol)
        try container.encodeIfPresent(goal, forKey: .goal)
        try container.encodeIfPresent(verification, forKey: .verification)
        try container.encode(isCustom, forKey: .isCustom)
        try container.encode(isDeleted, forKey: .isDeleted)
        try container.encode(identityID, forKey: .identityID)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

// MARK: - identities

struct IdentityRow: SyncedRow, Encodable {
    let userID: String
    let id: String
    let statement: String
    let symbol: String
    let accent: String
    let createdAt: Date
    let retiredAt: Date?
    let isDeleted: Bool
    let updatedAt: Date
    let syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case id
        case statement
        case symbol
        case accent
        case createdAt = "created_at"
        case retiredAt = "retired_at"
        case isDeleted = "is_deleted"
        case updatedAt = "updated_at"
        case syncedAt = "synced_at"
    }

    init(userID: String, definition: LocalPractice.IdentityDefinition) {
        self.userID = userID
        id = definition.id
        statement = definition.statement
        symbol = definition.symbol
        accent = definition.accent
        createdAt = definition.createdAt
        retiredAt = definition.retiredAt
        isDeleted = definition.isDeleted
        updatedAt = definition.updatedAt
        syncedAt = nil
    }

    var definition: LocalPractice.IdentityDefinition {
        LocalPractice.IdentityDefinition(
            id: id,
            statement: statement,
            symbol: symbol,
            accent: accent,
            createdAt: createdAt,
            retiredAt: retiredAt,
            isDeleted: isDeleted,
            updatedAt: updatedAt
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(id, forKey: .id)
        try container.encode(statement, forKey: .statement)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(accent, forKey: .accent)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(retiredAt, forKey: .retiredAt)
        try container.encode(isDeleted, forKey: .isDeleted)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

// MARK: - rituals

struct RitualRow: SyncedRow, Encodable {
    /// There is one day, and this is its id. A constant rather than a
    /// generated key, so the row upserts onto itself forever — and a name,
    /// because the day shared routines arrive they will need one and a column
    /// added later cannot be back-filled for anybody who has stopped opening
    /// the app.
    ///
    /// The value still spells the old name and has to. It is half of a primary
    /// key in a table that already has rows in it: changing it would not rename
    /// anybody's arrangement, it would strand it and silently write a second
    /// one beside it. What the id says has never been shown to anybody.
    static let dayRitualID = "morning"

    let userID: String
    let id: String
    let name: String
    let activityIDs: [String]
    let updatedAt: Date
    let syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case id
        case name
        case activityIDs = "activity_ids"
        case updatedAt = "updated_at"
        case syncedAt = "synced_at"
    }

    init(userID: String, arrangement: LocalPractice.Arrangement) {
        self.userID = userID
        id = Self.dayRitualID
        name = "Day"
        activityIDs = arrangement.activityIDs
        updatedAt = arrangement.updatedAt
        syncedAt = nil
    }

    var arrangement: LocalPractice.Arrangement {
        LocalPractice.Arrangement(activityIDs: activityIDs, updatedAt: updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(activityIDs, forKey: .activityIDs)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

// MARK: - days

struct DayRow: SyncedRow, Encodable {
    let userID: String
    let day: String
    let completions: [CompletionRow]
    let plannedIDs: [String]
    let extractedAt: Date?
    let updatedAt: Date
    let syncedAt: Date?

    struct CompletionRow: Codable, Equatable, Sendable {
        let ritualID: String
        let method: VerificationMethod
        let at: Date

        enum CodingKeys: String, CodingKey {
            case ritualID = "ritual_id"
            case method
            case at
        }
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case day
        case completions
        case plannedIDs = "planned_ids"
        case extractedAt = "extracted_at"
        case updatedAt = "updated_at"
        case syncedAt = "synced_at"
    }

    init(userID: String, record: DayRecord) {
        self.userID = userID
        day = record.day.isoString
        completions = record.completions.map {
            CompletionRow(ritualID: $0.ritualID, method: $0.method, at: $0.at)
        }
        plannedIDs = record.plannedIDs
        extractedAt = record.extractedAt
        // `stamp` rather than `updatedAt`, so a day recorded before this
        // column existed goes up dated from its own contents instead of as an
        // absence the merge would have to guess about.
        updatedAt = record.stamp
        syncedAt = nil
    }

    /// Nil for a row whose day the app cannot parse. A single unreadable date
    /// should cost that one day, not the whole pull.
    var record: DayRecord? {
        guard let day = ForgeDay(isoString: day) else { return nil }
        return DayRecord(
            day: day,
            completions: completions.map {
                DayRecord.Completion(ritualID: $0.ritualID, method: $0.method, at: $0.at)
            },
            plannedIDs: plannedIDs,
            extractedAt: extractedAt,
            updatedAt: updatedAt
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(day, forKey: .day)
        try container.encode(completions, forKey: .completions)
        try container.encode(plannedIDs, forKey: .plannedIDs)
        try container.encode(extractedAt, forKey: .extractedAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

// MARK: - blades

struct BladeRow: SyncedRow, Encodable {
    let userID: String
    let equippedID: Int
    let acknowledgedIDs: [Int]
    let celebratedIDs: [Int]
    let updatedAt: Date
    let syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case equippedID = "equipped_id"
        case acknowledgedIDs = "acknowledged_ids"
        case celebratedIDs = "celebrated_ids"
        case updatedAt = "updated_at"
        case syncedAt = "synced_at"
    }

    init(userID: String, blades: LocalPractice.Blades) {
        self.userID = userID
        equippedID = blades.equippedID
        acknowledgedIDs = blades.acknowledgedIDs.sorted()
        celebratedIDs = blades.celebratedIDs.sorted()
        updatedAt = blades.updatedAt
        syncedAt = nil
    }

    var blades: LocalPractice.Blades {
        LocalPractice.Blades(
            equippedID: equippedID,
            acknowledgedIDs: Set(acknowledgedIDs),
            celebratedIDs: Set(celebratedIDs),
            updatedAt: updatedAt
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(equippedID, forKey: .equippedID)
        try container.encode(acknowledgedIDs, forKey: .acknowledgedIDs)
        try container.encode(celebratedIDs, forKey: .celebratedIDs)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

// MARK: - premium_status

struct PremiumRow: SyncedRow, Encodable {
    let userID: String
    let entitlement: String
    let productID: String?
    let updatedAt: Date
    let syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case entitlement
        case productID = "product_id"
        case updatedAt = "updated_at"
        case syncedAt = "synced_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(entitlement, forKey: .entitlement)
        try container.encodeIfPresent(productID, forKey: .productID)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

// MARK: - chapters

/// One chapter on the wire.
///
/// Carries the model rather than a parallel `Definition`, for the reason
/// `LocalPractice.chapters` gives: `Chapter` is already a tolerant `Codable`
/// value with its own `updatedAt`, and a second shape would be a second decoder
/// to keep correct.
struct ChapterRow: SyncedRow, Encodable {
    let userID: String
    let id: String
    let name: String
    let identityIDs: [String]
    let intention: String
    let openedAt: Date
    let closedAt: Date?
    let updatedAt: Date
    let syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case id
        case name
        case identityIDs = "identity_ids"
        case intention
        case openedAt = "opened_at"
        case closedAt = "closed_at"
        case updatedAt = "updated_at"
        case syncedAt = "synced_at"
    }

    init(userID: String, chapter: Chapter) {
        self.userID = userID
        id = chapter.id
        name = chapter.name
        identityIDs = chapter.identityIDs
        intention = chapter.intention
        openedAt = chapter.openedAt
        closedAt = chapter.closedAt
        updatedAt = chapter.updatedAt
        syncedAt = nil
    }

    var chapter: Chapter {
        Chapter(
            id: id, name: name, identityIDs: identityIDs, intention: intention,
            openedAt: openedAt, closedAt: closedAt, updatedAt: updatedAt
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(identityIDs, forKey: .identityIDs)
        try container.encode(intention, forKey: .intention)
        try container.encode(openedAt, forKey: .openedAt)
        try container.encode(closedAt, forKey: .closedAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

// MARK: - reviews

/// One weekly review on the wire.
///
/// The week is the key, written as the same `yyyy-MM-dd` string the days table
/// uses so a row is legible in a database console — a fact worth the encoding
/// step the first time somebody has to answer a support question about it.
struct ReviewRow: SyncedRow, Encodable {
    let userID: String
    let weekStart: String
    let whatHappened: String
    let whatNext: String
    let completedAt: Date?
    let updatedAt: Date
    let syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case weekStart = "week_start"
        case whatHappened = "what_happened"
        case whatNext = "what_next"
        case completedAt = "completed_at"
        case updatedAt = "updated_at"
        case syncedAt = "synced_at"
    }

    init(userID: String, review: WeeklyReview) {
        self.userID = userID
        weekStart = review.weekStart.isoString
        whatHappened = review.whatHappened
        whatNext = review.whatNext
        completedAt = review.completedAt
        updatedAt = review.updatedAt
        syncedAt = nil
    }

    /// Nil for a row whose week cannot be read. One unparseable key must not
    /// take the rest of somebody's reviews with it — the same rule every
    /// decoder in this app follows.
    var review: WeeklyReview? {
        guard let day = ForgeDay(isoString: weekStart) else { return nil }
        return WeeklyReview(
            weekStart: day, whatHappened: whatHappened, whatNext: whatNext,
            completedAt: completedAt, updatedAt: updatedAt
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(weekStart, forKey: .weekStart)
        try container.encode(whatHappened, forKey: .whatHappened)
        try container.encode(whatNext, forKey: .whatNext)
        try container.encode(completedAt, forKey: .completedAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

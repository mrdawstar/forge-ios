import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Everything Forge keeps on this phone, as one file somebody can hold.
///
/// # Why there is a file at all
///
/// There is no account (§2n) and no server copy of the record: it lives in the
/// App Group and in the phone's own backup, and nowhere else. Settings → Your
/// Data can now write all of it to one JSON file through the share sheet —
/// Files, AirDrop, mail, anywhere the person chooses — and read one back
/// (FORGE_CONTEXT §17.7). It is the person's own copy; Forge never sends it
/// anywhere.
///
/// # What is in it, and what is never in it
///
/// Every versioned key Forge writes is either **carried** (`carried`) or
/// **left on the phone** (`left`), with the reason. A test reads the source
/// for every `"forge.….vN"` key and fails if one is in neither list, so a key
/// added later cannot be silently left out of a backup or silently put in one.
///
/// What stays on the phone is what a file must not decide: permissions that
/// iOS gave this iPhone (Apple Health, notifications), consent (Forge's AI,
/// anonymous usage), what this install is owed (the founder record — a file
/// must never make anybody a founder — the one exit offer, the trial reminder,
/// the rating prompt), bookkeeping that is rebuilt (the widgets' snapshot),
/// and anything that names an account or a device. None of it is user data.
///
/// # Reading one back replaces, and is checked first
///
/// `read` refuses anything that is not a Forge backup of a version this build
/// understands, any value whose type is not the type Forge stores under that
/// key, a record that does not decode with the record's own decoder, and a
/// file with no first run in it. Only then does Settings ask — with what the
/// file holds — and only after a yes does `apply` write: every carried key the
/// file has is written and every carried key it lacks is removed, so the phone
/// holds exactly the backup. What is left on the phone is not touched.
enum ForgeBackup {

    static let format = "forge-backup"
    static let version = 1

    /// Larger than any real record — two years of history is under a megabyte
    /// — and small enough that a wrong file is refused before it is parsed.
    static let maximumSize = 20 * 1_024 * 1_024

    // MARK: - The keys

    /// What a carried key holds, as `UserDefaults` stores it.
    enum Kind: Equatable, Sendable {
        case bool, int, string, strings, ints
        /// JSON bytes, as every store that writes `Codable` values keeps them.
        case json
        /// Anything a property list can hold. Only for keys nothing reads any
        /// more, kept so an old install's value still has a home.
        case any
    }

    /// Every key a backup carries, and what it holds.
    static let carried: [String: Kind] = [
        // The record.
        "forge.history.v1": .json,
        "forge.dayStartHour.v1": .int,
        "forge.restDays.v1": .ints,
        "forge.challengesKept.v1": .json,
        // What the day is made of.
        "forge.hasCompletedFirstRun.v1": .bool,
        "forge.activeRituals.v1": .strings,
        "forge.customRituals.v1": .json,
        "forge.verificationMemory.v1": .json,
        "forge.libraryEdits.v1": .json,
        "forge.commitment.v1": .json,
        "forge.dayShape.v1": .json,
        "forge.focus.v1": .strings,
        "forge.challenge.v1": .json,
        // What somebody said: answers, identities, chapters, weeks, markers,
        // Arcs, and the conversation with Ask Forge.
        "forge.assessment.v1": .json,
        "forge.identities.v1": .json,
        "forge.chapters.v1": .json,
        "forge.reviews.v1": .json,
        "forge.reviewWeekday.v1": .int,
        "forge.customMilestones.v1": .json,
        "forge.arcs.v1": .json,
        "forge.askForge.v1": .json,
        // Blades.
        "forge.equippedSword.v1": .int,
        "forge.acknowledgedSwords.v1": .ints,
        "forge.celebratedSwords.v1": .ints,
        // Preferences.
        "forge.notifications.wake.v1": .int,
        "forge.accent.v1": .string,
        "forge.sound.v1": .bool,
        "forge.haptics.v1": .bool,
        // 1.0's single paywall door; nothing reads it since 1.1.
        "forge.premiumInvited.v1": .any,
    ]

    /// Every key left on the phone, with the reason. Never written to a file,
    /// and never read from one.
    static let left: [String: String] = [
        "forge.founder.v1": "Founders are recognised from this phone's own history or by the App Store. A file never makes anybody one.",
        "forge.exitOffer.v1": "The one exit offer belongs to this install.",
        "forge.trialReminder.v1": "The reminder belongs to the free week started on this phone.",
        "forge.ratingAsked.v1": "The rating prompt is counted per install.",
        "forge.aiConsent.v1": "Forge's AI is allowed on each phone by the person, after reading what is sent.",
        "forge.shareUsage.v1": "This phone's choice about anonymous usage stays as it is.",
        "forge.health.v1": "Apple Health permission is this iPhone's, and so is the answer to it.",
        "forge.healthAsked.v1": "1.0's Apple Health question, this iPhone's.",
        "forge.notifications.enabled.v1": "Notification permission is this iPhone's; the switch stays with it.",
        "forge.notifications.asked.v1": "Whether iOS has been asked about notifications on this iPhone.",
        "forge.notifications.lastOpened.v1": "1.0 bookkeeping about this iPhone's notifications.",
        "forge.snapshot.v1": "The widgets' copy of today, rebuilt from the record.",
        "forge.migratedToAppGroup.v1": "This install's one-time move into the App Group.",
        "forge.debug.simulatedAccess.v1": "Debug builds only.",
        "forge.debug.resetTips.v1": "Debug builds only.",
        "forge.sync.owner.v1": "The dormant account's bookkeeping; it names an account.",
        "forge.sync.pullCursor.v1": "The dormant account's bookkeeping.",
        "forge.sync.pushedThrough.v1": "The dormant account's bookkeeping.",
        "forge.sync.migratedForUser.v1": "The dormant account's bookkeeping; it names an account.",
        "forge.sync.stamps.v1": "The dormant account's bookkeeping.",
        "forge.sync.tombstones.v1": "The dormant account's bookkeeping.",
        "forge.sync.identityTombstones.v1": "The dormant account's bookkeeping.",
        "forge.auth.anonymous.v1": "In the keychain, never in the App Group: a credential.",
        "forge.auth.session.v1": "In the keychain, never in the App Group: a credential.",
        "forge.device.id.v1": "In the keychain, never in the App Group: a device identifier.",
    ]

    /// The one key without which there is nothing to restore.
    static let historyKey = "forge.history.v1"
    static let firstRunKey = "forge.hasCompletedFirstRun.v1"

    // MARK: - The file

    /// One stored value, with its type said out loud. JSON alone cannot tell a
    /// `true` from a `1` or bytes from a string, and `UserDefaults` can.
    indirect enum Value: Codable, Equatable, Sendable {
        case bool(Bool)
        case int(Int)
        case double(Double)
        case string(String)
        case data(Data)
        case date(Date)
        case array([Value])
        case dictionary([String: Value])

        private enum CodingKeys: String, CodingKey {
            case bool, int, double, string, data, date, array, dictionary
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard c.allKeys.count == 1, let key = c.allKeys.first else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: c.codingPath, debugDescription: "One type per value."
                ))
            }
            switch key {
            case .bool: self = .bool(try c.decode(Bool.self, forKey: .bool))
            case .int: self = .int(try c.decode(Int.self, forKey: .int))
            case .double: self = .double(try c.decode(Double.self, forKey: .double))
            case .string: self = .string(try c.decode(String.self, forKey: .string))
            case .data:
                let encoded = try c.decode(String.self, forKey: .data)
                guard let bytes = Data(base64Encoded: encoded) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .data, in: c, debugDescription: "Not base64."
                    )
                }
                self = .data(bytes)
            case .date: self = .date(Date(timeIntervalSinceReferenceDate: try c.decode(Double.self, forKey: .date)))
            case .array: self = .array(try c.decode([Value].self, forKey: .array))
            case .dictionary: self = .dictionary(try c.decode([String: Value].self, forKey: .dictionary))
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .bool(let value): try c.encode(value, forKey: .bool)
            case .int(let value): try c.encode(value, forKey: .int)
            case .double(let value): try c.encode(value, forKey: .double)
            case .string(let value): try c.encode(value, forKey: .string)
            case .data(let value): try c.encode(value.base64EncodedString(), forKey: .data)
            case .date(let value): try c.encode(value.timeIntervalSinceReferenceDate, forKey: .date)
            case .array(let value): try c.encode(value, forKey: .array)
            case .dictionary(let value): try c.encode(value, forKey: .dictionary)
            }
        }

        /// What `UserDefaults` handed over, said as a value. Nil for anything
        /// a property list cannot hold, which `UserDefaults` never returns.
        init?(property: Any) {
            switch property {
            case let number as NSNumber:
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    self = .bool(number.boolValue)
                } else if CFNumberIsFloatType(number) {
                    self = .double(number.doubleValue)
                } else {
                    self = .int(number.intValue)
                }
            case let string as String: self = .string(string)
            case let data as Data: self = .data(data)
            case let date as Date: self = .date(date)
            case let array as [Any]:
                var values: [Value] = []
                for element in array {
                    guard let value = Value(property: element) else { return nil }
                    values.append(value)
                }
                self = .array(values)
            case let dictionary as [String: Any]:
                var values: [String: Value] = [:]
                for (key, element) in dictionary {
                    guard let value = Value(property: element) else { return nil }
                    values[key] = value
                }
                self = .dictionary(values)
            default:
                return nil
            }
        }

        /// What to hand `UserDefaults`.
        var property: Any {
            switch self {
            case .bool(let value): value
            case .int(let value): value
            case .double(let value): value
            case .string(let value): value
            case .data(let value): value
            case .date(let value): value
            case .array(let values): values.map(\.property)
            case .dictionary(let values): values.mapValues(\.property)
            }
        }

        /// Whether this is what a key of `kind` holds.
        func fits(_ kind: Kind) -> Bool {
            switch (kind, self) {
            case (.any, _), (.bool, .bool), (.int, .int), (.string, .string), (.json, .data):
                return true
            case (.strings, .array(let values)):
                return values.allSatisfy { if case .string = $0 { true } else { false } }
            case (.ints, .array(let values)):
                return values.allSatisfy { if case .int = $0 { true } else { false } }
            default:
                return false
            }
        }
    }

    /// The whole file.
    struct File: Codable, Equatable, Sendable {
        var format: String
        var version: Int
        var exportedAt: Date
        /// "1.1 (4)" — the build that wrote it, for a person reading the file.
        var app: String
        var values: [String: Value]
    }

    // MARK: - Writing one

    /// Everything carried, as this phone holds it now.
    ///
    /// A value that is not the type Forge stores under its key is one nothing
    /// on this phone can read either; it is left out rather than written into
    /// a file `read` would then refuse.
    static func export(from defaults: UserDefaults, now: Date = .now, app: String = appVersion) -> File {
        var values: [String: Value] = [:]
        for (key, kind) in carried {
            guard let stored = defaults.object(forKey: key),
                  let value = Value(property: stored), isReadable(value, as: kind)
            else { continue }
            values[key] = value
        }
        return File(format: format, version: version, exportedAt: now, app: app, values: values)
    }

    static func encode(_ file: File) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    /// "Forge backup 2026-10-04.json".
    static func fileName(at date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "Forge backup %04d-%02d-%02d.json", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0
        )
    }

    /// The version line from the bundle, never typed.
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// The type Forge stores under the key, and — for JSON — bytes that parse
    /// as JSON at all. Each store's own decoder is tolerant beyond that.
    ///
    /// **And every day in it is a day** (`ForgeDay.isPlausible`): a record,
    /// an Arc or a chapter dated in the year 1,000,000 decodes, and the first
    /// screen that walks the days to it never stops walking (§17.7). Every
    /// store writes a day as `{"year", "month", "day"}`, so one look at the
    /// JSON finds them all, whichever store they belong to.
    static func isReadable(_ value: Value, as kind: Kind) -> Bool {
        guard value.fits(kind) else { return false }
        if kind == .json, case .data(let bytes) = value {
            guard let object = try? JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed])
            else { return false }
            return !containsImpossibleDay(object)
        }
        return true
    }

    /// Whether anything shaped like a `ForgeDay` in this JSON is not one.
    static func containsImpossibleDay(_ object: Any) -> Bool {
        switch object {
        case let dictionary as [String: Any]:
            if Set(dictionary.keys) == ["year", "month", "day"] {
                guard let year = dictionary["year"] as? Int, let month = dictionary["month"] as? Int,
                      let day = dictionary["day"] as? Int
                else { return true }
                return !ForgeDay(year: year, month: month, day: day).isPlausible
            }
            return dictionary.values.contains(where: containsImpossibleDay)
        case let array as [Any]:
            return array.contains(where: containsImpossibleDay)
        default:
            return false
        }
    }

    // MARK: - Reading one

    /// Why a file was refused, in words for the person holding it.
    enum Problem: Error, Equatable, Sendable {
        case tooLarge
        case notABackup
        case newer(version: Int)
        case wrongType(key: String)
        case unreadableRecord
        case noRecord

        var message: String {
            switch self {
            case .tooLarge, .notABackup:
                "This file is not a Forge backup. Nothing was changed."
            case .newer:
                "This backup was made by a newer version of Forge. Update Forge, then import it. Nothing was changed."
            case .wrongType, .unreadableRecord:
                "This backup is damaged and cannot be read. Nothing was changed."
            case .noRecord:
                "This backup has no record in it. Nothing was changed."
            }
        }
    }

    /// What a file holds, said before anything is replaced.
    struct Summary: Equatable, Sendable {
        let exportedAt: Date
        let app: String
        let daysKept: Int
        let activities: Int
    }

    /// A file that passed every check, and what it holds.
    struct Checked: Equatable, Sendable {
        let file: File
        let summary: Summary
    }

    /// Every check, in order, before anything is written.
    static func read(_ data: Data) throws -> Checked {
        guard data.count <= maximumSize else { throw Problem.tooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(File.self, from: data), file.format == format else {
            throw Problem.notABackup
        }
        guard file.version <= version else { throw Problem.newer(version: file.version) }
        guard file.version >= 1 else { throw Problem.notABackup }

        for (key, value) in file.values {
            // A key this build does not carry — one left on the phone, or one a
            // later version added — is not read, so it cannot be wrong here.
            guard let kind = carried[key] else { continue }
            guard isReadable(value, as: kind) else { throw Problem.wrongType(key: key) }
        }

        guard case .bool(true) = file.values[firstRunKey] else { throw Problem.noRecord }
        // The record is read with the record's own decoder, which drops the
        // whole history if one day fails — so a file it cannot read is refused
        // here rather than emptying the record after the replace.
        guard case .data(let history) = file.values[historyKey] else { throw Problem.noRecord }
        guard let days = try? JSONDecoder().decode([DayRecord].self, from: history) else {
            throw Problem.unreadableRecord
        }

        var activities = 0
        if case .array(let ids) = file.values["forge.activeRituals.v1"] { activities = ids.count }
        return Checked(
            file: file,
            summary: Summary(
                exportedAt: file.exportedAt,
                app: file.app,
                daysKept: days.filter(\.isEarned).count,
                activities: activities
            )
        )
    }

    // MARK: - Replacing

    /// Make the phone hold exactly the backup: every carried key it has is
    /// written, every carried key it lacks is removed, and what is left on the
    /// phone (`left`) is not touched.
    ///
    /// Only ever called with a file `read` passed, after the person said yes.
    /// The app is rebuilt from the App Group straight afterwards
    /// (`didReplace`), so nothing in memory writes an older day back over it.
    static func apply(_ file: File, to defaults: UserDefaults) {
        for (key, kind) in carried {
            if let value = file.values[key], isReadable(value, as: kind) {
                defaults.set(value.property, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// Posted once a backup has replaced the App Group. `ForgeApp` rebuilds
    /// everything that read it.
    static let didReplace = Notification.Name("forge.backup.didReplace")

    /// What the confirmation says the file holds.
    static func describe(_ summary: Summary) -> String {
        let date = summary.exportedAt.formatted(date: .abbreviated, time: .omitted)
        let days = summary.daysKept == 1 ? "one day kept" : "\(ForgeCount.spelled(summary.daysKept).lowercased()) days kept"
        let activities = summary.activities == 1
            ? "one activity in the week"
            : "\(ForgeCount.spelled(summary.activities).lowercased()) activities in the week"
        return "This backup is from \(date): \(days) and \(activities). It replaces everything Forge keeps on this iPhone, and what is here now cannot be brought back. Permissions, Forge Pro and your privacy choices stay as they are."
    }
}

// MARK: - Through the share sheet

/// The backup as the share sheet takes it: written to a file at the moment it
/// is shared, so it is the record as it is then, under a name with its date.
struct ForgeBackupExport: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { _ in
            let now = Date.now
            let file = ForgeBackup.export(from: ForgeShared.defaults, now: now)
            let data = try ForgeBackup.encode(file)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(ForgeBackup.fileName(at: now))
            try data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

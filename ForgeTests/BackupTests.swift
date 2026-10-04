import Foundation
import Testing
@testable import Forge

/// Settings → Your Data: the whole record as one file, and back (§17.7).
///
/// The promises held here:
///
/// - **Every versioned key is decided.** Each `"forge.….vN"` key in the
///   source is either carried in a backup or left on the phone with a reason;
///   a new key in neither list fails the run.
/// - **A round trip is exact.** Export, encode, read and apply into an empty
///   phone gives back every carried value, type and all.
/// - **Importing replaces, and nothing else.** Carried keys the file lacks are
///   removed; what is left on the phone — permissions, consent, the founder
///   record, Forge Pro's own bookkeeping — is never touched, whatever a file
///   says.
/// - **A bad file changes nothing.** It is refused, with its reason, before a
///   single key is written.
@Suite("Your data: backup and import")
struct BackupTests {

    // MARK: - Scratch phones

    private func phone(_ name: String = #function) -> UserDefaults {
        let suite = "forge.backup.test.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func json<T: Encodable>(_ value: T) -> Data {
        try! JSONEncoder().encode(value)
    }

    private let day = ForgeDay(year: 2026, month: 10, day: 1)

    /// A record with two kept days and one that was not.
    private var history: [DayRecord] {
        (0..<3).map { back in
            let day = self.day.adding(days: -back)
            let at = day.startOfDay().addingTimeInterval(8 * 3_600)
            return DayRecord(
                day: day,
                completions: [DayRecord.Completion(ritualID: "read", method: .honor, at: at)],
                plannedIDs: ["read", "walk"],
                extractedAt: back < 2 ? at : nil
            )
        }
    }

    /// A phone holding a plausible value under every carried key, and under
    /// every key left on the phone.
    private func seeded(_ defaults: UserDefaults) {
        for (key, kind) in ForgeBackup.carried {
            switch kind {
            case .bool: defaults.set(true, forKey: key)
            case .int: defaults.set(4, forKey: key)
            case .string: defaults.set("ember", forKey: key)
            case .strings: defaults.set(["read", "walk", "wake"], forKey: key)
            case .ints: defaults.set([1, 7], forKey: key)
            case .json: defaults.set(json(["k": "v"]), forKey: key)
            case .any: defaults.set(true, forKey: key)
            }
        }
        defaults.set(json(history), forKey: ForgeBackup.historyKey)
        defaults.set(Date(timeIntervalSinceReferenceDate: 800_000_000), forKey: "forge.premiumInvited.v1")
        defaults.set(true, forKey: "forge.founder.v1")
        defaults.set("allowed", forKey: "forge.aiConsent.v1")
        defaults.set(true, forKey: "forge.notifications.enabled.v1")
        defaults.set(json(["decision": "asked"]), forKey: "forge.health.v1")
        defaults.set(false, forKey: "forge.shareUsage.v1")
    }

    private func file(_ defaults: UserDefaults) throws -> Data {
        try ForgeBackup.encode(ForgeBackup.export(from: defaults, now: Date(timeIntervalSince1970: 1_790_000_000), app: "1.1 (4)"))
    }

    // MARK: - Every key decided

    @Test("Every versioned key in the source is carried or left on the phone, never both and never neither")
    func everyKeyIsDecided() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        var found = Set<String>()
        let pattern = try NSRegularExpression(pattern: #""(forge\.[A-Za-z0-9_.]+\.v[0-9]+)""#)
        for folder in ["Forge", "ForgeWidgets"] {
            let files = FileManager.default.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil)
            while let url = files?.nextObject() as? URL {
                // The two lists themselves are not evidence that a key exists.
                guard url.pathExtension == "swift", url.lastPathComponent != "ForgeBackup.swift" else { continue }
                let text = try String(contentsOf: url, encoding: .utf8)
                for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    found.insert(String(text[Range(match.range(at: 1), in: text)!]))
                }
            }
        }
        #expect(found.count > 40, "the scan found the keys")
        let carried = Set(ForgeBackup.carried.keys)
        let left = Set(ForgeBackup.left.keys)
        #expect(carried.isDisjoint(with: left))
        for key in found.sorted() {
            #expect(carried.contains(key) || left.contains(key), Comment(rawValue: "\(key) is in neither list"))
        }
        // And neither list names a key nothing writes any more.
        for key in carried.union(left).sorted() {
            #expect(found.contains(key), Comment(rawValue: "\(key) is not in the source"))
        }
        // The founder record, consent and permissions are never carried.
        for key in ["forge.founder.v1", "forge.aiConsent.v1", "forge.shareUsage.v1", "forge.health.v1",
                    "forge.notifications.enabled.v1", "forge.snapshot.v1"] {
            #expect(ForgeBackup.left[key] != nil, Comment(rawValue: key))
        }
        // Every reason is a sentence.
        for (key, reason) in ForgeBackup.left {
            #expect(reason.hasSuffix(".") && !reason.contains("!"), Comment(rawValue: key))
        }
    }

    // MARK: - The round trip

    @Test("A backup round-trips every carried value exactly, types included, into an empty phone")
    func roundTrip() throws {
        let source = phone()
        seeded(source)
        let data = try file(source)

        let checked = try ForgeBackup.read(data)
        #expect(checked.summary.daysKept == 2)
        #expect(checked.summary.activities == 3)
        #expect(checked.summary.app == "1.1 (4)")

        let target = phone("target")
        ForgeBackup.apply(checked.file, to: target)
        for key in ForgeBackup.carried.keys.sorted() {
            let before = source.object(forKey: key) as? NSObject
            let after = target.object(forKey: key) as? NSObject
            #expect(before != nil, Comment(rawValue: key))
            #expect(before == after, Comment(rawValue: key))
        }
        // A Bool stays a Bool and a number a number: `true` and `1` are not
        // the same thing to `UserDefaults.object(forKey:)`.
        #expect(target.object(forKey: "forge.hasCompletedFirstRun.v1") as? Bool == true)
        #expect((target.object(forKey: "forge.dayStartHour.v1") as? NSNumber).map { CFGetTypeID($0) != CFBooleanGetTypeID() } == true)
        #expect(target.object(forKey: "forge.premiumInvited.v1") as? Date == Date(timeIntervalSinceReferenceDate: 800_000_000))

        // Nothing left on the phone travelled.
        for key in ForgeBackup.left.keys {
            #expect(target.object(forKey: key) == nil, Comment(rawValue: key))
        }
        // And a second export of the imported phone is the same file.
        #expect(try file(target) == data)
    }

    /// The record is what matters, so it is read back by the store that owns
    /// it, not only compared as bytes.
    @Test("The record imported is the record the store reads")
    func storeReadsTheImport() throws {
        let source = phone()
        let progress = ProgressStore(defaults: source)
        progress.seedSyntheticHistory(days: 60, planned: ["read", "walk", "wake"])
        source.set(true, forKey: ForgeBackup.firstRunKey)
        source.set(["read", "walk", "wake"], forKey: "forge.activeRituals.v1")

        let checked = try ForgeBackup.read(try file(source))
        #expect(checked.summary.daysKept == progress.daysKept)

        let target = phone("target")
        ForgeBackup.apply(checked.file, to: target)
        let restored = ProgressStore(defaults: target)
        #expect(restored.records == progress.records)
        #expect(restored.daysKept == progress.daysKept)
    }

    // MARK: - Replacing

    @Test("Importing replaces: what the backup lacks is removed, and what is left on the phone is untouched")
    func replaces() throws {
        let source = phone()
        source.set(true, forKey: ForgeBackup.firstRunKey)
        source.set(json(history), forKey: ForgeBackup.historyKey)
        source.set(["read"], forKey: "forge.activeRituals.v1")
        let checked = try ForgeBackup.read(try file(source))

        let target = phone("target")
        seeded(target)
        let left = ForgeBackup.left.keys.reduce(into: [String: NSObject]()) { all, key in
            all[key] = target.object(forKey: key) as? NSObject
        }
        ForgeBackup.apply(checked.file, to: target)

        #expect(target.object(forKey: "forge.arcs.v1") == nil, "an Arc the backup does not have is gone")
        #expect(target.stringArray(forKey: "forge.activeRituals.v1") == ["read"])
        for (key, value) in left {
            #expect(target.object(forKey: key) as? NSObject == value, Comment(rawValue: key))
        }
        #expect(target.bool(forKey: "forge.founder.v1"), "still this phone's founder")
        #expect(target.string(forKey: "forge.aiConsent.v1") == "allowed")
    }

    /// A file is only text: anybody can write `"forge.founder.v1"` into one.
    @Test("A file never makes a founder, allows the AI or changes a permission, whatever it says")
    func fileCannotGrant() throws {
        let source = phone()
        source.set(true, forKey: ForgeBackup.firstRunKey)
        source.set(json(history), forKey: ForgeBackup.historyKey)
        var exported = ForgeBackup.export(from: source)
        exported.values["forge.founder.v1"] = .bool(true)
        exported.values["forge.aiConsent.v1"] = .string("allowed")
        exported.values["forge.notifications.enabled.v1"] = .bool(true)
        exported.values["forge.debug.simulatedAccess.v1"] = .string("pro")
        exported.values["forge.someday.v9"] = .string("a key from a later build")

        let checked = try ForgeBackup.read(try ForgeBackup.encode(exported))
        let target = phone("target")
        target.set(false, forKey: "forge.founder.v1")
        ForgeBackup.apply(checked.file, to: target)

        #expect(target.bool(forKey: "forge.founder.v1") == false)
        #expect(target.object(forKey: "forge.aiConsent.v1") == nil)
        #expect(target.object(forKey: "forge.notifications.enabled.v1") == nil)
        #expect(target.object(forKey: "forge.debug.simulatedAccess.v1") == nil)
        #expect(target.object(forKey: "forge.someday.v9") == nil)
        // And an export never writes them in the first place.
        seeded(source)
        let fresh = ForgeBackup.export(from: source)
        for key in ForgeBackup.left.keys {
            #expect(fresh.values[key] == nil, Comment(rawValue: key))
        }
    }

    // MARK: - Refused, and nothing changes

    @Test("A file that is not a backup, a newer one, a damaged one or an empty one is refused with its reason")
    func refusals() throws {
        let good = phone()
        good.set(true, forKey: ForgeBackup.firstRunKey)
        good.set(json(history), forKey: ForgeBackup.historyKey)
        let valid = ForgeBackup.export(from: good)

        func refused(_ data: Data) -> ForgeBackup.Problem? {
            do { _ = try ForgeBackup.read(data); return nil } catch { return error as? ForgeBackup.Problem }
        }
        func refused(_ file: ForgeBackup.File) throws -> ForgeBackup.Problem? {
            refused(try ForgeBackup.encode(file))
        }

        #expect(refused(Data()) == .notABackup)
        #expect(refused(Data("garbage".utf8)) == .notABackup)
        #expect(refused(Data(#"[1,2,3]"#.utf8)) == .notABackup)
        #expect(refused(Data(#"{"format":"forge-backup"}"#.utf8)) == .notABackup)
        #expect(refused(Data(repeating: 0x20, count: ForgeBackup.maximumSize + 1)) == .tooLarge)

        var other = valid
        other.format = "something-else"
        #expect(try refused(other) == .notABackup)

        var newer = valid
        newer.version = ForgeBackup.version + 1
        #expect(try refused(newer) == .newer(version: ForgeBackup.version + 1))

        var zero = valid
        zero.version = 0
        #expect(try refused(zero) == .notABackup)

        // A value of the wrong type under a key the app reads.
        for (key, value) in [
            ("forge.history.v1", ForgeBackup.Value.string("not bytes")),
            ("forge.activeRituals.v1", .array([.int(1)])),
            ("forge.dayStartHour.v1", .string("four")),
            ("forge.restDays.v1", .array([.string("Sunday")])),
            ("forge.arcs.v1", .data(Data("not json".utf8))),
            ("forge.hasCompletedFirstRun.v1", .int(1)),
        ] {
            var damaged = valid
            damaged.values[key] = value
            #expect(try refused(damaged) == .wrongType(key: key), Comment(rawValue: key))
        }

        // A day no calendar holds, in any store: the first screen that walked
        // the days to it would never finish (§17.7).
        var impossible = valid
        impossible.values["forge.arcs.v1"] = .data(Data(
            #"[{"id":"a","arc":"winter","startDay":{"year":1000000,"month":1,"day":1}}]"#.utf8
        ))
        #expect(try refused(impossible) == .wrongType(key: "forge.arcs.v1"))
        var ancient = valid
        ancient.values[ForgeBackup.historyKey] = .data(Data(
            #"[{"day":{"year":1,"month":1,"day":1},"completions":[],"plannedIDs":[]}]"#.utf8
        ))
        #expect(try refused(ancient) == .wrongType(key: ForgeBackup.historyKey))

        // A record its own decoder cannot read.
        var unreadable = valid
        unreadable.values[ForgeBackup.historyKey] = .data(Data(#"[{"day":"Tuesday"}]"#.utf8))
        #expect(try refused(unreadable) == .unreadableRecord)

        // No first run, a first run not finished, or no record.
        var noRun = valid
        noRun.values[ForgeBackup.firstRunKey] = nil
        #expect(try refused(noRun) == .noRecord)
        var unfinished = valid
        unfinished.values[ForgeBackup.firstRunKey] = .bool(false)
        #expect(try refused(unfinished) == .noRecord)
        var noHistory = valid
        noHistory.values[ForgeBackup.historyKey] = nil
        #expect(try refused(noHistory) == .noRecord)

        // Every refusal says that nothing was changed, without an exclamation.
        for problem in [ForgeBackup.Problem.tooLarge, .notABackup, .newer(version: 2), .wrongType(key: "k"), .unreadableRecord, .noRecord] {
            #expect(problem.message.hasSuffix("Nothing was changed."))
            #expect(!problem.message.contains("!"))
        }
    }

    /// The decoder of a single value meets garbage too: a file is text that
    /// anybody can edit.
    @Test("A value with no type, two types or bad bytes does not decode")
    func valueGarbage() throws {
        for text in [#"{}"#, #"{"bool":true,"int":1}"#, #"{"data":"%%%"}"#, #"{"colour":"red"}"#, #"{"int":"one"}"#, #"null"#] {
            #expect(throws: (any Error).self, Comment(rawValue: text)) {
                try JSONDecoder().decode(ForgeBackup.Value.self, from: Data(text.utf8))
            }
        }
        let nested = ForgeBackup.Value.dictionary(["a": .array([.bool(true), .int(1), .double(1.5), .date(.distantPast), .data(Data([0, 1]))])])
        #expect(try JSONDecoder().decode(ForgeBackup.Value.self, from: JSONEncoder().encode(nested)) == nested)
    }

    // MARK: - Words

    @Test("The confirmation says what the file holds, in words, and that it replaces")
    func confirmation() {
        let summary = ForgeBackup.Summary(
            exportedAt: Date(timeIntervalSince1970: 1_790_000_000), app: "1.1 (4)", daysKept: 61, activities: 3
        )
        let text = ForgeBackup.describe(summary)
        #expect(text.contains("sixty-one days kept and three activities in the week"))
        #expect(text.contains("It replaces everything Forge keeps on this iPhone"))
        #expect(!text.contains("!"))
        let one = ForgeBackup.describe(.init(exportedAt: .now, app: "", daysKept: 1, activities: 1))
        #expect(one.contains("one day kept and one activity in the week"))
        // Past a hundred, digits.
        #expect(ForgeBackup.describe(.init(exportedAt: .now, app: "", daysKept: 412, activities: 6)).contains("412 days kept"))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 9))!
        #expect(ForgeBackup.fileName(at: date, calendar: calendar) == "Forge backup 2026-10-04.json")
    }
}

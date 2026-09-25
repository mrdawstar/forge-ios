import Foundation
import Testing
@testable import Forge

/// Decoding what earlier versions of Forge wrote to disk.
///
/// The stakes are specific: `customRituals` is stored as one encoded array, so a
/// single value the decoder refuses fails every activity in it, and somebody who
/// had built their own day would open the update to find it gone.
@Suite("Legacy decoding")
struct LegacyDecodingTests {

    /// A user-made activity exactly as Forge 2.0 wrote it — the removed
    /// verification tier, and all seven of the fields that used to describe what
    /// a camera should look for.
    private func legacyRitual(id: String, label: String, verification: String) -> String {
        """
        {
          "id": "\(id)",
          "label": "\(label)",
          "iconKey": "sparkle",
          "sub": "",
          "tail": "",
          "mode": "object",
          "verifyTitle": "Show me",
          "verifyHint": "Get it in frame. A glance is enough.",
          "readout": "✓",
          "readoutSub": "CONFIRMED",
          "verifiedNote": "\(label)",
          "telemetry": [],
          "reps": 0,
          "symbolName": "figure.walk",
          "isCustom": true,
          "verificationOverride": "\(verification)"
        }
        """
    }

    @Test("A legacy AI-verified activity survives and becomes honor")
    func aiVerifiedMigrates() throws {
        let json = legacyRitual(id: "custom.1", label: "Rinse the cafetière", verification: "aiVerified")
        let ritual = try JSONDecoder().decode(Ritual.self, from: Data(json.utf8))

        #expect(ritual.label == "Rinse the cafetière")
        #expect(ritual.isCustom)
        #expect(ritual.verification == .honor)
    }

    @Test("A legacy AI-assisted activity survives and becomes honor")
    func aiAssistedMigrates() throws {
        let json = legacyRitual(id: "custom.2", label: "Day pages", verification: "aiAssisted")
        let ritual = try JSONDecoder().decode(Ritual.self, from: Data(json.utf8))
        #expect(ritual.verification == .honor)
    }

    @Test("One legacy value does not take the whole array down with it")
    func mixedArraySurvives() throws {
        // The real failure mode: the array is stored under one key, so before
        // the tolerant decoder a single old value cost the user everything.
        let json = """
        [
          \(legacyRitual(id: "custom.1", label: "Rinse the cafetière", verification: "aiVerified")),
          \(legacyRitual(id: "custom.2", label: "Day pages", verification: "aiAssisted")),
          \(legacyRitual(id: "custom.3", label: "Walk the dog", verification: "health")),
          \(legacyRitual(id: "custom.4", label: "Say grace", verification: "honor"))
        ]
        """
        let rituals = try JSONDecoder().decode([Ritual].self, from: Data(json.utf8))

        #expect(rituals.count == 4, "every activity the user made has to come back")
        #expect(rituals.map(\.verification) == [.honor, .honor, .honor, .honor])
        #expect(rituals.map(\.label) == [
            "Rinse the cafetière", "Day pages", "Walk the dog", "Say grace",
        ])
    }

    @Test("Library edits carrying a legacy value survive too")
    func legacyLibraryEditMigrates() throws {
        // `libraryEdits` is a dictionary of the same enum and fails the same way.
        let json = """
        {"read": {"label": "Read a chapter", "verification": "aiAssisted"}}
        """
        let edits = try JSONDecoder().decode([String: RitualEdit].self, from: Data(json.utf8))

        #expect(edits["read"]?.label == "Read a chapter")
        #expect(edits["read"]?.verification == .honor)
    }

    @Test("A value from no version at all still decodes")
    func unknownValueIsSafe() throws {
        // Honor claims nothing was measured, which makes it the only safe place
        // to land a value we cannot interpret — including one written by a
        // future version somebody has downgraded from.
        let json = legacyRitual(id: "custom.9", label: "Something new", verification: "telepathy")
        let ritual = try JSONDecoder().decode(Ritual.self, from: Data(json.utf8))
        #expect(ritual.verification == .honor)
    }

    @Test("A migrated activity lands on honor")
    func migratedRitualHasNoHealthGoal() throws {
        // Named like a run, stored as the old camera tier. It must land on
        // honor and stay there rather than quietly becoming a measured activity.
        let json = legacyRitual(id: "custom.5", label: "Day run", verification: "aiVerified")
        let ritual = try JSONDecoder().decode(Ritual.self, from: Data(json.utf8))

        #expect(ritual.verification == .honor)
    }

    @Test("Current values still round-trip unchanged")
    func currentValuesRoundTrip() throws {
        for method in VerificationMethod.allCases {
            let data = try JSONEncoder().encode(method)
            #expect(try JSONDecoder().decode(VerificationMethod.self, from: data) == method)
        }
    }
}

import Foundation

/// Where the backend is, if there is one.
///
/// Deliberately optional. A build with nothing filled in is not a broken build
/// — it is Forge exactly as it was before any of this existed: every service
/// below reports `.unconfigured`, no request is ever made, and the day
/// works. That is the strongest possible statement of offline-first, and it is
/// also what makes the whole backend safe to review: if this returns nil, none
/// of the rest of the code can do anything at all.
struct SupabaseConfig: Equatable, Sendable {

    /// The project URL, e.g. `https://abcdefgh.supabase.co`.
    let url: URL
    /// The project's public API key. Public by design — it identifies the
    /// project and grants nothing on its own. Every table refuses `anon`
    /// outright, and an authenticated request is only ever allowed at the rows
    /// whose owner is the uuid inside its own signed token. The key is in the
    /// app bundle because that is where Supabase intends it to be; the security
    /// is in the row policies, not in hiding this.
    ///
    /// Either format works and the name is historical. Supabase's current keys
    /// are `sb_publishable_…`; the older ones were JWTs beginning `eyJ…` and
    /// were called the anon key, which is where this property and the
    /// Info.plist entry get their names. Both go in the same two headers and
    /// nothing downstream can tell them apart — verified against this project's
    /// PostgREST and GoTrue endpoints, which accept the publishable key in both
    /// the `apikey` and `Authorization: Bearer` positions.
    let anonKey: String

    // MARK: - Reading it

    private enum PlistKey {
        static let url = "ForgeSupabaseURL"
        static let anonKey = "ForgeSupabaseAnonKey"
    }

    /// Nil rather than a crash for anything missing or left as a placeholder.
    ///
    /// A developer who has not set the project up yet, a fork, and a build made
    /// before the keys were added all land here, and all of them get a working
    /// app rather than a launch-time trap.
    static func fromBundle(_ bundle: Bundle = .main) -> SupabaseConfig? {
        guard let raw = bundle.object(forInfoDictionaryKey: PlistKey.url) as? String,
              let key = bundle.object(forInfoDictionaryKey: PlistKey.anonKey) as? String
        else { return nil }
        return make(url: raw, anonKey: key)
    }

    /// Split out so the parsing rules can be checked without a bundle.
    static func make(url raw: String, anonKey key: String) -> SupabaseConfig? {
        let trimmedURL = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedKey.isEmpty else { return nil }
        // An unsubstituted build setting reaches Info.plist verbatim, and a
        // literal "$(FORGE_SUPABASE_URL)" would otherwise be treated as a host
        // and produce a stream of failing requests to nowhere.
        guard !trimmedURL.hasPrefix("$("), !trimmedKey.hasPrefix("$(") else { return nil }
        guard let url = URL(string: trimmedURL), url.scheme == "https" else { return nil }
        return SupabaseConfig(url: url, anonKey: trimmedKey)
    }

    // MARK: - Endpoints

    /// GoTrue. Everything about who somebody is.
    var authURL: URL { url.appendingPathComponent("auth/v1") }
    /// PostgREST. Everything about what they have done.
    var restURL: URL { url.appendingPathComponent("rest/v1") }

    /// Where an OAuth provider sends the browser back to.
    ///
    /// The scheme is already declared for widgets and the Live Activity, so
    /// this adds no new surface — but the host is its own, because a callback
    /// arriving on the same path as a widget tap would be indistinguishable
    /// from one.
    static let callbackScheme = "forge"
    static let callbackURL = "forge://auth-callback"
}

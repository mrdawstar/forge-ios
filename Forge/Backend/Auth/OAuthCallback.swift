import Foundation

/// What came back on `forge://auth-callback`.
///
/// Parsed as a value so the failure cases — a user who declined at Google's
/// consent screen, a provider that answered with an error instead of a code —
/// are handled by reading a struct rather than by unwrapping optionals at the
/// call site.
struct OAuthCallback: Equatable, Sendable {
    let code: String?
    let error: String?

    init(url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        // Supabase's PKCE flow answers in the query string. The fragment is
        // read too because the implicit flow answers there, and a project
        // misconfigured to use it should fail with the provider's own message
        // rather than with silence.
        var items = components?.queryItems ?? []
        if let fragment = components?.fragment {
            var parser = URLComponents()
            parser.query = fragment
            items += parser.queryItems ?? []
        }
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        code = value("code")
        error = value("error_description") ?? value("error")
    }
}

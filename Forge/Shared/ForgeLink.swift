import Foundation

/// The one thing a widget is allowed to do.
///
/// Widgets and Live Activities in Forge are passive — no buttons, no
/// checkboxes, nothing that completes an activity from outside the app. Ticking
/// a day off from the Lock Screen would make the ritual something you can do
/// without getting up, which is the one thing Forge is for.
///
/// So there is exactly one link, every surface uses it, and it lands on the
/// day.
enum ForgeLink {
    static let scheme = "forge"

    /// Deliberately not failable at the call site: the string is a literal, and
    /// an optional here would spread `if let` through every widget for a case
    /// that cannot happen.
    static let today = URL(string: "\(scheme)://today")!

    /// Whether an incoming URL is one of ours. Every one of ours means the same
    /// thing, so there is nothing to parse beyond the scheme.
    static func isForge(_ url: URL) -> Bool { url.scheme == scheme }
}

/// The three pages Forge points at from inside the app.
///
/// Spelled out here rather than in the rows that open them, because the App
/// Store review guidelines require the privacy policy to be reachable from
/// inside the app and a broken link is the sort of thing that is only noticed
/// by a reviewer.
///
/// Still optional, and still resolved through `url(_:)` rather than
/// force-unwrapped. These used to be `URL(string: "https://forge.app/\u{2026}")!`
/// for a domain that does not resolve, so the rows in Settings were there,
/// tappable, and opened nothing — which is worse than not having them, because
/// it looks finished. Keeping the optional means a typo removes the row instead
/// of shipping a dead one, and `areConfigured` is still the one thing to check
/// before a submission.
enum ForgeLinks {

    static let privacy: URL? = url("https://forgebetter.app/privacy")
    static let terms: URL? = url("https://forgebetter.app/terms")

    /// Where somebody writes to a human. Required by App Store Connect as a
    /// support URL, and worth a row in Settings for the same reason the other
    /// two have one: an app with no way to reach its author is one you cannot
    /// tell when it is wrong.
    static let support: URL? = url("https://forgebetter.app/support")

    /// Apple's Standard License Agreement, which is the Terms of Use Forge Pro
    /// is sold under. Linked from the paywall because App Review requires a
    /// functional link to the terms beside every auto-renewing subscription;
    /// `APP_STORE.md` §7 has the matching line for the App Store description.
    static let appleEULA: URL? = url("https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")

    /// Empty, whitespace and anything that is not a real https URL all mean the
    /// same thing: not configured yet.
    private static func url(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme == "https" else {
            return nil
        }
        return url
    }

    /// Whether the app is in a state it could be submitted in.
    static var areConfigured: Bool { privacy != nil && terms != nil && support != nil }
}

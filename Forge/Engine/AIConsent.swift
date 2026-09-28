import Foundation

/// Whether somebody has said yes to Forge's AI, and nothing else.
///
/// # The rule this file keeps
///
/// **No request reaches Forge's backend — and no anonymous identity is created
/// for one — until the person holding the phone has read what would be sent and
/// pressed Allow.** `RemoteForgeAI.connect` reads `isAllowed` before it reads
/// the purchase and before it asks for a token, so without a yes nothing about
/// the AI path runs at all: no StoreKit read, no sign-up, no socket.
///
/// # Three states, not two
///
/// - `undecided` — never asked. The disclosure is offered the first time
///   somebody *presses* something that would reach the model (Plan's "Work it
///   out", the Weekly Reading's "Read my week"), and never at launch, never on
///   opening Settings or a review.
/// - `allowed` — they read it and said yes.
/// - `declined` — "Not now", or a yes taken back in Settings. Forge keeps
///   answering on the phone and does not ask again on its own; the way back is
///   Settings → Planning, where it was switched off.
///
/// # Where it is kept
///
/// The App Group suite, like every other preference, so there is one answer for
/// the whole install. It is not synced and not sent anywhere: a consent is a
/// fact about this phone and the person using it.
@MainActor
@Observable
final class AIConsentStore {

    enum State: String, Sendable {
        case undecided, allowed, declined
    }

    static let key = "forge.aiConsent.v1"

    private let defaults: UserDefaults

    private(set) var state: State {
        didSet { defaults.set(state.rawValue, forKey: Self.key) }
    }

    init(defaults: UserDefaults = ForgeShared.defaults) {
        self.defaults = defaults
        state = Self.read(defaults)
    }

    var isAllowed: Bool { state == .allowed }
    var hasDecided: Bool { state != .undecided }

    /// "Allow", on the disclosure.
    func allow() { state = .allowed }

    /// "Not now", on the disclosure. Nothing is sent, nothing is asked again
    /// unprompted, and every answer keeps coming from the phone.
    func decline() { state = .declined }

    /// Taken back in Settings. The same state as "Not now", by design: there is
    /// no half-revoked consent.
    func revoke() { state = .declined }

    #if DEBUG
    /// Back to never-asked, so the disclosure can be walked again.
    func reset() {
        defaults.removeObject(forKey: Self.key)
        state = .undecided
    }
    #endif

    // MARK: - Read off the main actor

    /// The same answer, for `RemoteForgeAI`'s closure, which runs wherever the
    /// request does. A straight read of the suite: `UserDefaults` is safe to
    /// read from any thread, and nothing is cached that could go stale.
    nonisolated static func isAllowed(in defaults: UserDefaults = ForgeShared.defaults) -> Bool {
        read(defaults) == .allowed
    }

    nonisolated private static func read(_ defaults: UserDefaults) -> State {
        defaults.string(forKey: key).flatMap(State.init(rawValue:)) ?? .undecided
    }
}

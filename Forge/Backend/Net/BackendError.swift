import Foundation

/// Everything that can go wrong between the phone and the backend, sorted once.
///
/// The point of this type is the one property at the bottom. Offline-first is
/// not a feeling about the code, it is a decision about which failures are
/// worth waiting out and which are worth telling somebody about — and if that
/// decision is made at each call site it will eventually be made differently at
/// two of them. A dropped connection on a train and a malformed request are
/// both `Error`; only one of them should ever reach a person.
enum BackendError: Error, Equatable {

    /// No route to the network. The ordinary case, and never worth a word on
    /// screen.
    case offline
    case timedOut
    /// The request was abandoned, usually because the app went away.
    case cancelled

    /// The access token is dead. Refresh once, then this becomes a real
    /// sign-out.
    case unauthorized
    /// Row Level Security refused. Not retryable — it means the request asked
    /// for somebody else's rows, which is a bug in this app rather than a
    /// condition to wait out.
    case forbidden

    case rateLimited(retryAfter: TimeInterval?)
    /// The backend is having a day. Retryable.
    case server(status: Int)
    /// We asked wrong. Not retryable, and the message is kept for the log
    /// rather than for the user.
    case request(status: Int, message: String?)

    /// The shape on the wire was not the shape expected. A schema drift, which
    /// retrying cannot fix.
    case decoding
    /// No project URL and no key. Nothing was attempted.
    case notConfigured
    /// Somebody closed the browser sheet, or declined at the system prompt.
    /// Not a failure — an answer.
    case signInCancelled

    /// Whether waiting and trying again could plausibly work.
    ///
    /// Read by the sync engine to decide between "try later, quietly" and
    /// "stop, this will never succeed". Anything not listed here is treated as
    /// permanent, which is the safe default: a permanent failure retried
    /// forever is a battery drain, and a transient one given up on is a day
    /// that never reaches the cloud — but the second is recovered by the next
    /// foreground, and the first is not recovered by anything.
    var isRetryable: Bool {
        switch self {
        case .offline, .timedOut, .server, .rateLimited:
            true
        case .cancelled, .unauthorized, .forbidden, .request,
             .decoding, .notConfigured, .signInCancelled:
            false
        }
    }

    /// How long to wait before the next attempt, when the server said so.
    var retryHint: TimeInterval? {
        guard case .rateLimited(let after) = self else { return nil }
        return after
    }
}

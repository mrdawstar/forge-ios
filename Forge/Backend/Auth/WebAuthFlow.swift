import AuthenticationServices
import UIKit

/// Google, without Google's SDK.
///
/// `ASWebAuthenticationSession` is the system's own OAuth browser: a Safari
/// view Forge cannot read, with the user's existing Google session available to
/// it, and a consent sheet iOS presents before any of that happens. It is what
/// the Google SDK uses underneath, minus a dependency, minus an analytics
/// library, and minus a second copy of the keychain code.
///
/// Not ephemeral, deliberately. An ephemeral session shares no cookies, so
/// somebody already signed into Google on this phone would be made to type a
/// password Forge has no business making them type.
@MainActor
enum WebAuthFlow {

    /// Open the browser and wait for the scheme to come back.
    ///
    /// Cancelling is a normal outcome and comes back as `.signInCancelled`
    /// rather than an error worth showing — somebody who closed the sheet has
    /// already been told what happened, by closing the sheet.
    static func start(url: URL, callbackScheme: String) async throws -> URL {
        let anchor = PresentationAnchor()

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                    return
                }
                let failure = (error as? ASWebAuthenticationSessionError)
                    .map { $0.code == .canceledLogin
                        ? BackendError.signInCancelled
                        : BackendError.request(status: 0, message: $0.localizedDescription) }
                    ?? .signInCancelled
                continuation.resume(throwing: failure)
            }
            session.presentationContextProvider = anchor
            session.prefersEphemeralWebBrowserSession = false

            guard session.start() else {
                continuation.resume(throwing: BackendError.signInCancelled)
                return
            }
            // The session deallocates the moment nothing holds it, taking the
            // browser with it. The anchor is the only thing that outlives this
            // scope, so it carries the session until the callback fires.
            anchor.session = session
        }
    }

    /// The window the sheet hangs off.
    ///
    /// Found rather than injected: this is presented from Settings, from a
    /// single-scene app locked to portrait, and threading a window reference
    /// down through four view models to reach it would be four properties that
    /// exist to answer a question `UIApplication` already knows the answer to.
    private final class PresentationAnchor: NSObject,
                                            ASWebAuthenticationPresentationContextProviding {
        var session: ASWebAuthenticationSession?

        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }?
                .keyWindow
                ?? ASPresentationAnchor()
        }
    }
}

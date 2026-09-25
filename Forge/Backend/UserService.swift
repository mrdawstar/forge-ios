import Foundation
import UIKit

/// The account, and what is signed into it.
///
/// Small on purpose. There is no user profile in Forge — no display name, no
/// avatar, no bio, nothing to fill in — because none of that would make a
/// single day easier to keep. What is here is what an account genuinely
/// needs: a row that exists, and an honest answer to "which of my devices is
/// this practice on".
@MainActor
final class UserService {

    private let api: SupabaseDataAPI?
    private let auth: AuthService

    init(api: SupabaseDataAPI?, auth: AuthService) {
        self.api = api
        self.auth = auth
    }

    // MARK: - This device

    private static let deviceIDKey = "forge.device.id.v1"

    /// A stable name for this install, generated once and kept in the keychain.
    ///
    /// The keychain rather than `UserDefaults` for one reason: the id is
    /// `ThisDeviceOnly` alongside the session, so a phone restored from a backup
    /// arrives without one and generates a new one. That is correct — it *is* a
    /// new device — and it is the difference between a devices list that means
    /// something and one that slowly fills up with the same phone.
    static var deviceID: String {
        if let stored = Keychain.data(for: deviceIDKey),
           let id = String(data: stored, encoding: .utf8),
           !id.isEmpty {
            return id
        }
        let made = UUID().uuidString
        Keychain.set(Data(made.utf8), for: deviceIDKey)
        return made
    }

    // MARK: - Registering

    /// Say hello, and say when.
    ///
    /// Runs for anybody signed in, paid or not: it is the account's own record
    /// of itself rather than any part of a practice, and an account that cannot
    /// list its devices is an account nobody can be helped with.
    ///
    /// Failures are swallowed whole. This is bookkeeping — nothing anywhere in
    /// the app reads it back — and a device row that did not get written is not
    /// worth a retry, let alone a word on screen.
    func registerDevice() async {
        guard let api, let userID = auth.userID else { return }
        guard let token = try? await auth.validAccessToken() else { return }

        let now = Date()
        let row = DeviceRow(
            id: Self.deviceID,
            userID: userID,
            // On current iOS this is the model rather than whatever the phone
            // was named after, which is both what we want and one less piece of
            // somebody's life sitting in a database.
            name: UIDevice.current.name,
            model: UIDevice.current.model,
            systemVersion: UIDevice.current.systemVersion,
            appVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String,
            lastSeenAt: now,
            updatedAt: now,
            syncedAt: nil
        )
        try? await api.upsert([row], into: .devices, accessToken: token)
    }

    // MARK: - Ending it

    /// Delete the account and everything the server holds for it.
    ///
    /// Unlike everything else in this class, the failure is not swallowed. A
    /// device row that did not get written is bookkeeping nobody will miss; an
    /// account somebody asked to delete that is still there is the app having
    /// told them something untrue about their own data, so the caller is given
    /// the error and says so.
    func deleteAccount() async throws {
        guard let api else { throw BackendError.notConfigured }
        let token = try await auth.validAccessToken()
        try await api.deleteAccount(accessToken: token)
    }
}

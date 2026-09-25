import Foundation
import Security

/// Where the tokens live, and the reason they do not live anywhere else.
///
/// Everything else Forge keeps is in `UserDefaults`, which is a plist in the
/// app container: readable by anything that gets at the container, and copied
/// wholesale into an unencrypted backup. That is the right home for a history
/// of days and the wrong one for a credential that can read that history
/// from a server.
///
/// `ThisDeviceOnly` is deliberate. A session restored onto a new phone from a
/// backup would be a phone signed in as somebody who never signed in on it —
/// so the new phone asks once, which is exactly the moment the user is already
/// expecting to be asked.
enum Keychain {

    private static var service: String {
        (Bundle.main.bundleIdentifier ?? "com.dawid.forge") + ".auth"
    }

    @discardableResult
    static func set(_ data: Data, for account: String) -> Bool {
        // Delete-then-add rather than update: an update on a missing item is an
        // error, and branching on which case we are in is a race with anything
        // else touching the same account.
        remove(account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func data(for account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    static func remove(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Codable

    static func set(_ value: some Encodable, for account: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        set(data, for: account)
    }

    static func value<T: Decodable>(_ type: T.Type, for account: String) -> T? {
        guard let data = data(for: account) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

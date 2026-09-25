import Foundation

/// Writes down what the App Store told this device, and reads nothing back.
///
/// The important sentence in this file is the one about what it does *not* do.
/// The entitlement is `ForgeStore`'s, it comes from StoreKit, it is signed by
/// Apple, and it already follows an Apple Account onto every device somebody
/// owns. Nothing here grants Premium, and nothing anywhere in the app asks the
/// server whether somebody has paid.
///
/// That is not laziness — it is the only correct design. `premium_status` is a
/// row a client writes, and Row Level Security guarantees only that the client
/// is writing its *own* row. It cannot guarantee the row is true. An app that
/// unlocked a paid feature because a row said so would be unlockable by anybody
/// willing to send one HTTP request, and it would still be wrong even if that
/// never happened, because it would mean the answer to "has this person paid"
/// lived in two places that could disagree.
///
/// So the row is a record: what support sees, what a future server-side receipt
/// check would write into, and what makes "this account has Premium on some
/// device" answerable at all.
@MainActor
final class PremiumService {

    private let api: SupabaseDataAPI?
    private let auth: AuthService

    init(api: SupabaseDataAPI?, auth: AuthService) {
        self.api = api
        self.auth = auth
    }

    /// Tell the account what this device's App Store says.
    ///
    /// Best effort and silent. Nothing on screen depends on it, and a failure
    /// costs nothing but a stale row.
    func record(_ entitlement: PremiumEntitlement) async {
        guard let api, let userID = auth.userID else { return }
        guard let token = try? await auth.validAccessToken() else { return }

        let row = PremiumRow(
            userID: userID,
            entitlement: Self.name(for: entitlement),
            productID: Self.product(for: entitlement)?.rawValue,
            updatedAt: Date(),
            syncedAt: nil
        )
        try? await api.upsert([row], into: .premiumStatus, accessToken: token)
    }

    /// The column is a `text` with a check constraint, so these three strings
    /// are a contract with the schema rather than a formatting choice.
    static func name(for entitlement: PremiumEntitlement) -> String {
        switch entitlement {
        case .free: "free"
        case .subscribed: "subscribed"
        case .lifetime: "lifetime"
        }
    }

    private static func product(for entitlement: PremiumEntitlement) -> PremiumProduct? {
        switch entitlement {
        case .free: nil
        case .subscribed: .annual
        case .lifetime: .lifetime
        }
    }
}

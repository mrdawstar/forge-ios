import Foundation

// MARK: - What is sold

/// The two things somebody can buy, and there are deliberately only two.
///
/// No monthly plan. Forge keeps everything on the phone and costs almost nothing
/// to run per person, so billing every thirty days would be charging rent on
/// something that is already theirs — and it would ask somebody to re-decide
/// twelve times a year about a practice measured in years.
enum PremiumProduct: String, CaseIterable, Sendable {
    case annual = "com.dawid.forge.premium.annual"
    case lifetime = "com.dawid.forge.premium.lifetime"

    static var identifiers: [String] { allCases.map(\.rawValue) }

    init?(id: String) {
        guard let match = Self(rawValue: id) else { return nil }
        self = match
    }
}

/// What somebody currently has.
enum PremiumEntitlement: Equatable, Sendable {
    case free
    case subscribed
    case lifetime

    var isPremium: Bool { self != .free }
}

// MARK: - What 1.0 does with all of this

/// **Nothing is behind a paywall in 1.0, and this file is the plan for 1.1.**
///
/// The archetypes were the only thing Premium had that shipped and worked, and
/// they are gone. What was left to sell was backup and sync — and a description
/// of the model-written features, none of which is deployed. Selling the second
/// would have been dishonest and selling the first alone would have been thin,
/// so 1.0 ships free: no paywall, no invitation, no locked control anywhere.
///
/// What survives above is deliberately only the part that is a *contract*: two
/// product identifiers that are already configured in App Store Connect, and the
/// three entitlement states `ForgeStore` reads out of StoreKit. Neither is
/// referenced by any screen today. They are here because 1.1 adds Premium back
/// around the AI — analyse the record, say what is holding, say what is
/// slipping, propose a plan against the activities somebody already keeps — and
/// rebuilding a verified StoreKit layer that already works would be the actual
/// waste.
///
/// The paywall copy that used to live here was deleted rather than kept, and
/// that is the difference: a product id is a fact that stays true, and a
/// sentence about what somebody is buying is a claim that has to be written
/// against whatever istrue on the day it ships.

import Foundation

/// When Forge asks for a rating, which is at most twice and never in the way
/// (DIRECTION_1_1 §10).
///
/// # The two moments
///
/// 1. **A blade celebration closes** — the first one outside the first run.
///    The celebration is the one moment the app already stops for, somebody
///    has just been shown what their days made, and closing it hands the
///    screen back with nothing else asking for it.
/// 2. **Folded** — the blade for day seven — **closes, and the first ask was
///    more than a day earlier.** Once more, and never again.
///
/// # Never
///
/// - **In the first run.** Struck, the first blade, is always earned on the
///   first pull, inside onboarding. Asking there would be asking somebody who
///   has used the app for three minutes, so that celebration asks nothing and
///   nothing is owed from it: for a new install the first ask is the next
///   blade, Shaped, on the third day kept.
/// - **Over a day in progress**: a summary, another celebration, a pull, an
///   honor prompt, a return screen or a sheet. The moment is checked after the
///   celebration's fade, and a moment that is not clear is simply passed.
///
/// What is stored is when it asked (`key`), so the Folded rule can read the
/// gap. SwiftUI's `requestReview` — StoreKit underneath — decides on its own
/// whether anything is actually shown; this only decides when Forge may ask.
struct RatingPrompt {

    /// The days it asked, as seconds since 1970, oldest first.
    static let key = "forge.ratingAsked.v1"

    /// Folded: the blade for day seven.
    static let secondBladeRequirement = 7

    enum Ask: Equatable, Sendable {
        case first
        case second
    }

    /// What is on screen when the celebration has faded.
    struct Moment: Equatable, Sendable {
        var isFirstRun: Bool
        var isDayInProgress: Bool
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = ForgeShared.defaults) {
        self.defaults = defaults
    }

    /// When it has asked, oldest first. Anything unreadable is ignored.
    var asked: [Date] {
        (defaults.array(forKey: Self.key) as? [Double] ?? []).map { Date(timeIntervalSince1970: $0) }
    }

    /// Whether to ask now that this blade's celebration has closed.
    static func decide(closing blade: Sword, asked: [Date], now: Date, moment: Moment) -> Ask? {
        guard !moment.isFirstRun, !moment.isDayInProgress else { return nil }
        guard let first = asked.first else { return .first }
        guard asked.count == 1,
              blade.requirement == secondBladeRequirement,
              now.timeIntervalSince(first) > 24 * 60 * 60
        else { return nil }
        return .second
    }

    /// Decide, and write it down if the answer is to ask.
    func claim(closing blade: Sword, now: Date, moment: Moment) -> Ask? {
        let past = asked
        guard let ask = Self.decide(closing: blade, asked: past, now: now, moment: moment) else { return nil }
        defaults.set((past + [now]).map(\.timeIntervalSince1970), forKey: Self.key)
        return ask
    }

    #if DEBUG
    func reset() { defaults.removeObject(forKey: Self.key) }
    #endif
}

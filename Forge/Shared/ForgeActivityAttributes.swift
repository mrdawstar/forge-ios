import ActivityKit
import Foundation

/// The day, as it appears on the Lock Screen and in the Dynamic Island.
///
/// Two numbers and a flag. A Live Activity is glanced at from a locked phone in
/// a corridor, so it carries progress and blade state and refuses everything
/// else — the activity names, the streak, the targets all live one tap away in
/// the app, and putting them here would make the island a second day list.
struct ForgeActivityAttributes: ActivityAttributes {

    /// Everything that moves during a day.
    public struct ContentState: Codable, Hashable {
        var done: Int
        var total: Int
        var isEarned: Bool

        var remaining: Int { max(0, total - done) }

        /// Whole once the blade is out, whatever the list says: the first pull
        /// is granted with the list unfinished, and a bar reading a third under
        /// a freed blade would be arguing with it.
        var fraction: Double {
            if isEarned { return 1 }
            guard total > 0 else { return 0 }
            return Double(done) / Double(total)
        }

        /// One short line, used by the Lock Screen presentation and by
        /// VoiceOver, so the two can never drift apart.
        var summary: String {
            if isEarned { return "The blade is free" }
            if remaining == 1 { return "One left" }
            return "\(remaining) left"
        }
    }

    /// Nothing static. The activity is only ever about today, and today is
    /// entirely `ContentState` — an attribute that never changes would just be a
    /// second place to keep the same fact.
    public init() {}
}

import Foundation

/// What actually happened on one day.
///
/// The only thing written down. Streaks, totals, milestones and the heatmap are
/// all read back out of a pile of these, because a stored streak is a number
/// that can disagree with its own history and there is no way afterwards to
/// tell which of the two is lying.
struct DayRecord: Codable, Identifiable, Equatable, Sendable {
    let day: ForgeDay
    /// One per activity finished, in the order they were finished.
    var completions: [Completion] = []
    /// What the day was made of on the day itself. Kept so that adding an
    /// activity next week cannot retroactively make last Tuesday incomplete.
    var plannedIDs: [String] = []
    /// When the blade came free, if it did. A day is only *earned* once
    /// this is set — finishing the list makes it loose, pulling it earns it.
    var extractedAt: Date?
    /// When this record last changed, on the device that changed it.
    ///
    /// Written by `ProgressStore` on every write and read by nothing else in
    /// the app. It exists so two phones can agree about one day: the merge
    /// has to know which of two versions of Tuesday is the more recent
    /// intention, and no amount of looking at the contents can answer that.
    ///
    /// Optional because every record ever written before this field existed
    /// does not have one, and a missing key must decode rather than throw —
    /// see `stamp` for what stands in.
    var updatedAt: Date?

    var id: ForgeDay { day }

    struct Completion: Codable, Equatable, Sendable {
        let ritualID: String
        let method: VerificationMethod
        let at: Date
    }

    var isEarned: Bool { extractedAt != nil }
    var completedCount: Int { completions.count }
    var plannedCount: Int { plannedIDs.count }
    var completedIDs: Set<String> { Set(completions.map(\.ritualID)) }

    /// 0…1 of the day as it was planned that day. Drives the heatmap, where
    /// a half-finished day should read as dimmer rather than absent.
    var fraction: Double {
        guard plannedCount > 0 else { return isEarned ? 1 : 0 }
        return min(1, Double(completedCount) / Double(plannedCount))
    }

    /// Nothing happened. Empty records are dropped rather than stored, so the
    /// history is a list of days rather than a list of days.
    var isEmpty: Bool { completions.isEmpty && extractedAt == nil }

    /// When this record last changed, with an answer for every record ever
    /// written.
    ///
    /// A history recorded before the cloud existed has no `updatedAt`, and the
    /// alternatives were both bad: stamping every old record on the launch
    /// after an update would rewrite a decade of history in one go and make it
    /// all look brand new, and treating them as undated would make them lose
    /// every conflict to anything.
    ///
    /// So the record dates itself from its own contents. A day is last
    /// touched when it is pulled, or failing that when its last activity was
    /// finished, or failing that on the day it belongs to — which is not
    /// exactly right, and is right enough to order a day against a day.
    var stamp: Date {
        updatedAt ?? extractedAt ?? completions.map(\.at).max() ?? day.startOfDay()
    }
}

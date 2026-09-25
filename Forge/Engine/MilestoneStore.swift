import Foundation
import Observation

/// The markers somebody set for themselves.
///
/// The only stateful thing on the Blade tab, and it holds as little as it can
/// get away with: the definitions, and nothing about progress. How far along a
/// milestone is gets read out of `ProgressStore` every time it is asked for,
/// exactly like the streak and the heatmap — so the one class of bug this
/// codebase keeps designing itself out of, a stored number disagreeing with the
/// history it came from, cannot happen here either.
///
/// The single exception is `reachedAt`, and it is not progress. It records that
/// the app has already celebrated something, which is a fact about the app and
/// is not recoverable from the record. Without it the confetti fires on every
/// launch for the rest of somebody's life.
@Observable
final class MilestoneStore {

    /// In the order they were made, oldest first — the order somebody built
    /// their own list in, which is the only ordering they can predict. Reached
    /// ones are floated to the bottom at the point of display rather than here,
    /// so nothing rearranges under a finger the moment a milestone lands.
    private(set) var custom: [CustomMilestone] = []

    /// Milestones reached but not yet congratulated, oldest first.
    ///
    /// A queue rather than one slot, because two can land on the same day —
    /// finishing a day is what moves most of them — and silently swallowing the
    /// second would make the app's acknowledgement look arbitrary.
    private(set) var celebrationQueue: [CustomMilestone] = []

    var pendingCelebration: CustomMilestone? { celebrationQueue.first }

    /// How many somebody may keep.
    ///
    /// A ceiling because a list of thirty markers is not a practice, it is a
    /// backlog — and the whole argument of this screen is that a milestone is a
    /// sentence worth reading rather than a thing to collect.
    static let limit = 12

    private let defaults: UserDefaults
    private let key = "forge.customMilestones.v1"
    /// Suppresses the write that loading would otherwise trigger.
    private var isLoaded = false

    /// `defaults` is injectable so tests get a scratch suite instead of
    /// scribbling on the simulator's real one.
    init(defaults: UserDefaults = ForgeShared.defaults) {
        self.defaults = defaults
        load()
    }

    var canAddMore: Bool { custom.count < Self.limit }

    // MARK: - Storage

    private func load() {
        defer { isLoaded = true }
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CustomMilestone].self, from: data)
        else { return }
        custom = decoded
    }

    private func persist() {
        guard isLoaded else { return }
        guard let data = try? JSONEncoder().encode(custom) else { return }
        defaults.set(data, forKey: key)
    }

    // MARK: - Editing

    @discardableResult
    func add(_ draft: MilestoneDraft) -> CustomMilestone? {
        guard canAddMore else { return nil }
        let made = CustomMilestone(
            name: name(from: draft),
            symbol: draft.symbol,
            subject: draft.subject,
            unit: draft.unit,
            target: draft.target
        )
        custom.append(made)
        persist()
        return made
    }

    func update(_ id: String, to draft: MilestoneDraft) {
        guard let index = custom.firstIndex(where: { $0.id == id }) else { return }
        let previousTarget = custom[index].target
        let target = min(
            max(draft.target, CustomMilestone.targetRange.lowerBound),
            CustomMilestone.targetRange.upperBound
        )

        custom[index].name = name(from: draft)
        custom[index].symbol = draft.symbol
        custom[index].subject = draft.subject
        custom[index].unit = draft.unit
        custom[index].target = target

        // Moving the goalposts outward puts it back in play, congratulation
        // included. `reachedAt` is normally never cleared — a thing that
        // happened stays happened — but somebody who reaches thirty days and
        // then raises the bar to a hundred has not reached a hundred, and a row
        // still wearing its tick would be the app disagreeing with its own bar.
        // Lowering the target is left alone: `refresh` will mark it on the next
        // pass if it is now met, and it was never marked if it was not.
        if target > previousTarget {
            custom[index].reachedAt = nil
            celebrationQueue.removeAll { $0.id == id }
        }
        persist()
    }

    func delete(_ id: String) {
        custom.removeAll { $0.id == id }
        celebrationQueue.removeAll { $0.id == id }
        persist()
    }

    /// A name is never stored empty. Somebody who clears the field gets the
    /// sentence the composer was suggesting anyway, which is always a true
    /// description of what they built — a blank row would not be.
    private func name(from draft: MilestoneDraft) -> String {
        let trimmed = draft.trimmedName
        guard trimmed.isEmpty else { return trimmed }
        return CustomMilestone.suggestedName(
            target: draft.target, unit: draft.unit, activityName: nil
        )
    }

    // MARK: - Reading

    /// How far along one is, right now, out of the history.
    func current(_ subject: MilestoneSubject, in progress: ProgressStore) -> Int {
        switch subject {
        case .daysKept: progress.daysKept
        case let .activity(id): progress.timesCompleted(id)
        }
    }

    /// Every custom milestone as the list draws it: unreached first in the order
    /// they were made, then reached ones, most recently reached last.
    ///
    /// `activityName` resolves an id to the name the user knows it by. Handed in
    /// rather than looked up, because an activity somebody invented lives on the
    /// Forge tab's view model and nothing here has any business knowing that.
    func measured(
        in progress: ProgressStore,
        activityName: (String) -> String?
    ) -> [Milestone] {
        let all = custom.map { milestone in
            milestone.measured(
                current: current(milestone.subject, in: progress),
                activityName: milestone.subject.activityID.flatMap(activityName)
            )
        }
        return all.filter { !$0.isReached } + all.filter(\.isReached)
    }

    // MARK: - Celebration

    /// Notice anything that has just been reached.
    ///
    /// Called when the screen appears and whenever the history moves under it.
    /// It is deliberately the only thing that writes `reachedAt`: marking is a
    /// side effect of *having noticed*, so a milestone crossed while the app was
    /// closed is still congratulated the next time somebody opens it, rather
    /// than being quietly marked by whatever happened to compute a total first.
    @discardableResult
    func refresh(against progress: ProgressStore) -> Bool {
        var found: [CustomMilestone] = []
        for index in custom.indices {
            let milestone = custom[index]
            guard milestone.reachedAt == nil else { continue }
            guard current(milestone.subject, in: progress) >= milestone.target else { continue }
            custom[index].reachedAt = progress.now
            found.append(custom[index])
        }
        guard !found.isEmpty else { return false }
        celebrationQueue.append(contentsOf: found)
        persist()
        return true
    }

    /// The congratulation has been seen.
    func dismissCelebration() {
        guard !celebrationQueue.isEmpty else { return }
        celebrationQueue.removeFirst()
    }
}

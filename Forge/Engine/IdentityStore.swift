import Foundation
import Observation

/// Who somebody says they are becoming, and the only place that answer lives.
///
/// Holds definitions and nothing else. How much evidence there is for an
/// identity is read out of `ProgressStore` every time it is asked for — exactly
/// like the streak, the heatmap and every milestone — so the one class of bug
/// this codebase keeps designing itself out of, a stored number disagreeing with
/// the history it came from, is not reachable here either.
///
/// There is deliberately no `reachedAt` equivalent and nothing to celebrate. An
/// identity is not completed, so there is no moment for the app to notice and
/// therefore nothing about it that has to be written down. See `Identity`.
@MainActor
@Observable
final class IdentityStore {

    /// In the order they were named, oldest first — the order somebody built
    /// their own list in, which is the only ordering they can predict.
    ///
    /// Retired ones stay in this array. They are filtered at the point of
    /// display rather than removed, because the record still refers to them and
    /// a lookup that returned nil for a retired identity would leave months of
    /// tagged history pointing at a blank.
    private(set) var all: [Identity] = []

    private let defaults: UserDefaults
    private let key = "forge.identities.v1"
    /// Suppresses the write that loading would otherwise trigger.
    private var isLoaded = false

    /// The App Group suite rather than `.standard`, so a widget could one day
    /// draw the identity a day is evidence for without the app handing it over.
    /// Nothing reads it there yet; putting it in the shared suite now costs
    /// nothing and saves a migration later.
    ///
    /// `defaults` is injectable so tests get a scratch suite instead of
    /// scribbling on the simulator's real one.
    init(defaults: UserDefaults = ForgeShared.defaults) {
        self.defaults = defaults
        load()
    }

    // MARK: - Storage

    private func load() {
        defer { isLoaded = true }
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Identity].self, from: data)
        else { return }
        all = decoded
    }

    private func persist() {
        guard isLoaded else { return }
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: key)
    }

    // MARK: - Reading

    /// The ones being worked toward now. What every screen shows.
    var active: [Identity] { all.filter(\.isActive) }

    /// The ones somebody has stopped pursuing, most recently retired first.
    /// Still real, still explaining whatever history is tagged to them.
    var retired: [Identity] {
        all.filter { !$0.isActive }
            .sorted { ($0.retiredAt ?? .distantPast) > ($1.retiredAt ?? .distantPast) }
    }

    var isEmpty: Bool { all.isEmpty }

    /// Whether there is room to name another. See `Identity.activeLimit`.
    var canAddMore: Bool { active.count < Identity.activeLimit }

    /// Resolves an id against everything ever named, retired included — see
    /// `all` for why a retired identity has to stay findable.
    func identity(_ id: String) -> Identity? {
        all.first { $0.id == id }
    }

    // MARK: - Naming one

    /// Name an identity. Nil when there is no room, or when the statement is
    /// blank after trimming.
    ///
    /// Refusing an empty statement rather than storing a placeholder: a
    /// milestone with no name can fall back to a true description of what it
    /// counts, and there is no equivalent here — the sentence *is* the whole
    /// object, and one Forge wrote would be the app telling somebody who they
    /// are.
    @discardableResult
    func add(
        statement: String,
        symbol: String = ActivityIcons.fallback,
        accent: ForgeAccent = .forge,
        at instant: Date = .now
    ) -> Identity? {
        guard canAddMore else { return nil }
        let clean = Identity.trimmed(statement)
        guard !clean.isEmpty else { return nil }
        let made = Identity(
            statement: clean, symbol: symbol, accent: accent, createdAt: instant
        )
        all.append(made)
        persist()
        return made
    }

    /// One of the shipped starting points, taken as-is. Editable immediately,
    /// and nothing records that it came from a prompt.
    @discardableResult
    func add(_ prompt: IdentityPrompt, at instant: Date = .now) -> Identity? {
        add(
            statement: prompt.statement,
            symbol: prompt.symbol,
            accent: prompt.accent,
            at: instant
        )
    }

    // MARK: - Changing one

    /// Rewrite what somebody said about themselves.
    ///
    /// The id never moves, which is the point — see `Identity.id`. Somebody who
    /// realises at month four that "Someone who trains" was really "Someone who
    /// is strong" keeps every day of evidence behind it.
    ///
    /// A blank statement is ignored rather than stored, for the reason `add`
    /// refuses one.
    func update(
        _ id: String,
        statement: String? = nil,
        symbol: String? = nil,
        accent: ForgeAccent? = nil
    ) {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        if let statement {
            let clean = Identity.trimmed(statement)
            if !clean.isEmpty { all[index].statement = clean }
        }
        if let symbol { all[index].symbol = symbol }
        if let accent { all[index].accent = accent }
        persist()
    }

    // MARK: - Stopping

    /// Stop pursuing this, and keep everything it explains.
    ///
    /// The ordinary way an identity ends, and the one the UI should offer. It
    /// frees a slot against `Identity.activeLimit` without touching a single day
    /// of history — see `Identity.retiredAt` for why deleting instead would cost
    /// somebody the meaning of work they actually did.
    func retire(_ id: String, at instant: Date = .now) {
        guard let index = all.firstIndex(where: { $0.id == id }), all[index].isActive
        else { return }
        all[index].retiredAt = instant
        persist()
    }

    /// Take it back up. Refused when three are already active, so restoring can
    /// never quietly widen the limit.
    func restore(_ id: String) {
        guard canAddMore else { return }
        guard let index = all.firstIndex(where: { $0.id == id }), !all[index].isActive
        else { return }
        all[index].retiredAt = nil
        persist()
    }

    /// Throw it away for good.
    ///
    /// Deliberately **not** what the UI should reach for first, and separate
    /// from `retire` rather than a parameter on it: they are different acts with
    /// different costs, and a boolean argument is how the expensive one gets
    /// passed by accident.
    ///
    /// Activities tagged to it are left alone. Their `identityID` becomes an id
    /// that resolves to nothing, which reads exactly as untagged everywhere —
    /// see `ForgeViewModel.identityID(of:)`. Clearing the tags here would be a
    /// second, silent edit to somebody's day on the way past.
    ///
    /// The deletion is written down as a fact rather than left as an absence,
    /// for the same reason a thrown-away activity is: whether somebody signs in
    /// later is not knowable at the moment they press delete, and an identity
    /// that comes back from the dead on a new phone is not a bug anybody can
    /// explain away.
    func delete(_ id: String, ledger: SyncLedger = SyncLedger(), at instant: Date = .now) {
        guard all.contains(where: { $0.id == id }) else { return }
        all.removeAll { $0.id == id }
        ledger.recordIdentityTombstone(id, at: instant)
        persist()
    }

    #if DEBUG
    /// Throw everything away, so the first run can be walked again.
    ///
    /// Debug only, and deliberately not reachable from the app: there is no
    /// product reason to delete every identity at once, and a method that can
    /// would be the one somebody eventually calls from a settings row labelled
    /// something reassuring. Tombstones are recorded, so a replay on a signed-in
    /// device does not resurrect them from the cloud.
    func deleteAll(ledger: SyncLedger = SyncLedger(), at instant: Date = .now) {
        for identity in all {
            ledger.recordIdentityTombstone(identity.id, at: instant)
        }
        all = []
        persist()
    }
    #endif

    // MARK: - Sync

    /// Take on what a merge decided, in one pass.
    ///
    /// A replacement rather than a union, because the merge has already done the
    /// uniting and handing it a second opinion here would be two answers again —
    /// the same reasoning `ProgressStore.adopt(_:)` is built on.
    func adopt(_ identities: [Identity]) {
        guard identities != all else { return }
        all = identities
        persist()
    }


}

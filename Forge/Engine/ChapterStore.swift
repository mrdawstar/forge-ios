import Foundation
import Observation

/// The chapters somebody has lived in, and the only place that answer lives.
///
/// Holds definitions and nothing else — the same shape as `IdentityStore`, and
/// deliberately so. How a chapter went is read out of `ProgressStore` every time
/// it is asked for (see `ChapterReading`), so the one bug this codebase keeps
/// designing itself out of — a stored number disagreeing with the history it
/// came from — is not reachable here either.
///
/// **One open at a time.** Not a storage limit but a product one: a chapter is
/// the answer to "what am I in the middle of", and two answers to that is the
/// same as no answer. Opening a new one closes the one before it, in a single
/// call, so the invariant cannot be broken by a caller forgetting a step.
@MainActor
@Observable
final class ChapterStore {

    /// In the order they were opened, oldest first. Closed ones stay: a chapter
    /// somebody lived through for six weeks explains six weeks of their history,
    /// and the review that reads it back has not been written yet.
    private(set) var all: [Chapter] = []

    private let defaults: UserDefaults
    private let key = "forge.chapters.v1"
    /// Suppresses the write that loading would otherwise trigger.
    private var isLoaded = false

    /// The App Group suite, and `defaults` is injectable so tests get a scratch
    /// suite rather than scribbling on the simulator's real one. The same call
    /// `IdentityStore` made.
    init(defaults: UserDefaults = ForgeShared.defaults) {
        self.defaults = defaults
        load()
    }

    // MARK: - Storage

    private func load() {
        defer { isLoaded = true }
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Chapter].self, from: data)
        else { return }
        all = decoded
    }

    private func persist() {
        guard isLoaded else { return }
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: key)
    }

    // MARK: - Reading

    /// The one being lived in, if any. Nil is ordinary and every reader has to
    /// be correct for it.
    var current: Chapter? { all.last { $0.isOpen } }

    /// The ones behind, most recently closed first.
    var closed: [Chapter] {
        all.filter { !$0.isOpen }
            .sorted { ($0.closedAt ?? .distantPast) > ($1.closedAt ?? .distantPast) }
    }

    var isEmpty: Bool { all.isEmpty }

    func chapter(_ id: String) -> Chapter? { all.first { $0.id == id } }

    // MARK: - Opening one

    /// Open a chapter, closing whatever was open.
    ///
    /// Returns the one that was opened, or nil for a blank name — the name is
    /// the whole handle somebody has on a stretch of their life, and one the app
    /// wrote would be Forge naming it for them.
    @discardableResult
    func open(
        name: String,
        identityIDs: [String] = [],
        intention: String = "",
        at instant: Date = .now
    ) -> Chapter? {
        let clean = Chapter.trimmed(name, to: Chapter.nameLimit)
        guard !clean.isEmpty else { return nil }
        close(at: instant)
        let opened = Chapter(
            name: clean, identityIDs: identityIDs,
            intention: intention, openedAt: instant, updatedAt: instant
        )
        all.append(opened)
        persist()
        return opened
    }

    /// Open the first chapter for somebody who has never had one.
    ///
    /// Called at the end of the first run, and it is a no-op for anybody who
    /// already has any chapter at all — including a closed one, because somebody
    /// who closed their last chapter deliberately has *chosen* to be between
    /// chapters and the app should not quietly put them back in one.
    ///
    /// The name is Forge's here and only here, which is the one place it can be
    /// without being presumptuous: there is nothing yet to name it after. It is
    /// editable from the moment it exists.
    @discardableResult
    func openFirst(
        identityIDs: [String] = [], at instant: Date = .now
    ) -> Chapter? {
        guard all.isEmpty else { return nil }
        return open(name: "The first six weeks", identityIDs: identityIDs, at: instant)
    }

    // MARK: - Changing one

    /// Rewrite what a chapter is called or what it is for. The id never moves,
    /// so nothing that refers to it is orphaned by a rename.
    func update(
        _ id: String,
        name: String? = nil,
        identityIDs: [String]? = nil,
        intention: String? = nil
    ) {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        if let name {
            let clean = Chapter.trimmed(name, to: Chapter.nameLimit)
            if !clean.isEmpty { all[index].name = clean }
        }
        if let identityIDs { all[index].identityIDs = identityIDs }
        if let intention {
            all[index].intention = Chapter.trimmed(intention, to: Chapter.intentionLimit)
        }
        all[index].updatedAt = .now
        persist()
    }

    // MARK: - Closing one

    /// Close whatever is open. Idempotent, and does nothing when nothing is.
    ///
    /// Closing is never destructive and is not a judgement: the days inside it
    /// are in the history exactly as they were, the count does not reset, and
    /// nothing about a chapter closed at week two is worth less than one closed
    /// at week six. It is a line drawn, not a result recorded.
    @discardableResult
    func close(at instant: Date = .now) -> Chapter? {
        guard let index = all.lastIndex(where: { $0.isOpen }) else { return nil }
        all[index].closedAt = instant
        all[index].updatedAt = instant
        persist()
        ForgeTelemetry.send(.chapterClosed)
        return all[index]
    }

    /// Throw one away for good.
    ///
    /// Separate from `close` rather than a parameter on it, for the reason
    /// `IdentityStore` keeps `retire` and `delete` apart: they are different
    /// acts with different costs, and a boolean argument is how the expensive
    /// one gets passed by accident. Nothing in the history is touched — a
    /// chapter never owned any of it.
    func delete(_ id: String) {
        guard all.contains(where: { $0.id == id }) else { return }
        all.removeAll { $0.id == id }
        persist()
    }

    /// Take on what a merge decided, in one pass. A replacement rather than a
    /// union, the same reasoning `IdentityStore.adopt(_:)` is built on.
    func adopt(_ chapters: [Chapter]) {
        guard chapters != all else { return }
        all = chapters
        persist()
    }

    #if DEBUG
    /// Throw everything away, so the first run can be walked again. Debug only,
    /// and deliberately not reachable from the app.
    func deleteAll() {
        all = []
        persist()
    }
    #endif
}

import Foundation

/// One challenge, for today, for everybody.
///
/// Everybody gets a challenge every day and can accept, skip and complete it,
/// because a locked daily challenge is the app withholding the one thing it is
/// for. Nothing here is behind anything.
///
/// Nothing is scored and nothing is punished. A skipped challenge costs nothing,
/// does not touch the streak, and is not counted anywhere — the chain is about
/// the day, and a challenge is a thing offered on top of it.
///
/// **It holds no model.** It used to take a `ForgeAI` and expose `generate`, for
/// a screen that asked a model to compose a challenge — a screen 1.0 shipped
/// with nothing behind it and which has since been deleted. The seam itself is
/// not gone: `ForgeAI.challenge` and the sixty-challenge matcher behind it are
/// exactly where they were, so the day 1.1 wants that screen back it is a screen
/// to write, not an architecture to rebuild.
@Observable
final class ChallengeStore {

    /// Read for the current day, and for nothing else. The challenge store has
    /// no history of its own: yesterday's challenge is gone, on purpose, because
    /// a scoreboard of challenges taken and missed is exactly the pressure this
    /// feature must not add.
    private let progress: ProgressStore

    /// Today's challenge and what has happened to it. Never nil — there is
    /// always one, which is what "every user gets one every day" means.
    private(set) var today: ChallengeDay

    private let defaults: UserDefaults

    /// What today is made of, asked for at the moment a challenge is chosen.
    ///
    /// A closure rather than a stored value because the day changes all day and
    /// this must not: the context is read **once**, when the day turns over, and
    /// the result is written down. Somebody who adds a run at four in the
    /// afternoon does not get a different challenge than the one they were
    /// offered at breakfast — see `rollOver`.
    private let context: () -> ChallengeContext

    private enum Key {
        static let today = "forge.challenge.v1"
    }

    /// `defaults` is injectable for the same reason `ProgressStore`'s is: tests
    /// get a scratch suite rather than scribbling on the real one.
    init(
        progress: ProgressStore,
        defaults: UserDefaults = ForgeShared.defaults,
        context: @escaping () -> ChallengeContext = { .init() }
    ) {
        self.progress = progress
        self.defaults = defaults
        self.context = context
        self.today = Self.load(from: defaults, for: progress.currentDay, context: context())
    }

    // MARK: - The day turning over

    /// Move on to whichever day it now is.
    ///
    /// Called from the root on the same triggers `publishPlanned` uses, rather
    /// than derived on read: choosing the challenge is a *write*, and doing it
    /// inside a getter would mean a view's body mutating the store it is reading.
    ///
    /// A no-op when the day has not moved, so it is safe on every foreground.
    func rollOver() {
        guard today.day != progress.currentDay else { return }
        today = ChallengeDay(
            day: progress.currentDay,
            challenge: ChallengeCatalog.challenge(for: progress.currentDay, context: context())
        )
        persist()
    }

    // MARK: - The three answers

    func accept() {
        today.state = .accepted
        today.completedAt = nil
        persist()
    }

    /// Not today. Reversible all day — somebody who skips at eight and changes
    /// their mind at four should not have to wait for midnight.
    func skip() {
        today.state = .skipped
        today.completedAt = nil
        persist()
    }

    func complete() {
        guard today.state != .completed else { return }
        today.state = .completed
        today.completedAt = progress.now
        persist()
    }

    /// Take it back.
    ///
    /// Lands on `accepted` rather than `offered`, because it is the truth: they
    /// took the challenge on and have not finished it. Dropping them back to
    /// "Accept / Not today" would ask a question they already answered.
    func undoCompletion() {
        guard today.state == .completed else { return }
        today.state = .accepted
        today.completedAt = nil
        persist()
    }

    // MARK: - Browsing the six

    /// One challenge for each of the six parts of a person, in the order the
    /// Shape draws them, with today's own in its dimension's slot.
    ///
    /// **Derived, never stored.** It is arithmetic on the date, so the six cards
    /// are the same six on both of somebody's phones and the same six when the
    /// app is reopened at four in the afternoon. See `ChallengeCatalog.browse`,
    /// which also records why today's does not simply lead the list.
    ///
    /// `page` is how far down the shelf the sheet has scrolled. Page zero is the
    /// six that carry today's own; every page after it is another round of the
    /// same six aims, drawn from the same arithmetic. There is no last page —
    /// see `DailyChallengeSheet.pager`.
    func browsable(page: Int = 0) -> [DailyChallenge] {
        ChallengeCatalog.browse(for: today.day, including: today.challenge, page: page)
    }

    /// Take one of the others as today's.
    ///
    /// Replaces rather than adds: one challenge a day is the promise, and a
    /// screen that turns it into a list is a different product. What the pager
    /// adds is a way to *choose which one*, which is the thing somebody actually
    /// wants when the day's challenge does not fit the day they are having.
    ///
    /// It lands `accepted`, because swiping to it and pressing the button is
    /// taking it on — asking somebody to press Accept immediately afterwards is
    /// a step that exists for nobody. A no-op for the one already showing, so
    /// the button cannot reset a challenge somebody has already finished.
    func take(_ challenge: DailyChallenge) {
        guard challenge.id != today.challenge.id else { return }
        today = ChallengeDay(day: today.day, challenge: challenge, state: .accepted)
        persist()
    }

    // MARK: - Storage

    /// Today's, or a fresh one for today. Yesterday's is discarded on sight
    /// rather than migrated: there is nothing in it worth carrying, and reading
    /// it back would be the one route by which a completed state could survive
    /// the day it belonged to.
    private static func load(
        from defaults: UserDefaults,
        for day: ForgeDay,
        context: ChallengeContext
    ) -> ChallengeDay {
        if let data = defaults.data(forKey: Key.today),
           let stored = try? JSONDecoder().decode(ChallengeDay.self, from: data),
           stored.day == day {
            return stored
        }
        return ChallengeDay(day: day, challenge: ChallengeCatalog.challenge(for: day, context: context))
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(today) else { return }
        defaults.set(data, forKey: Key.today)
    }
}

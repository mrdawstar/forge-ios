import Foundation

/// One challenge, for today, for everybody.
///
/// Everybody gets a challenge every day and can accept, skip and complete it,
/// because a locked daily challenge is the app withholding the one thing it is
/// for. Nothing here is behind anything.
///
/// Nothing is punished. A skipped challenge costs nothing, does not touch the
/// streak, and is not written anywhere — the chain is about the day, and a
/// challenge is a thing offered on top of it.
///
/// **A finished one counts** (DIRECTION_1_1 §7): it is a kept day for its
/// dimension in the Shape. This store does not keep that record itself — it
/// hands it to `ProgressStore` (`keepChallenge`) the moment the state reaches
/// `completed`, and takes it back (`releaseChallenge`) on every move away from
/// it, so the Shape can never be holding a finish the sheet no longer shows.
///
/// **It holds no model.** It used to take a `ForgeAI` and expose `generate`, for
/// a screen that asked a model to compose a challenge — a screen 1.0 shipped
/// with nothing behind it and which has since been deleted. The seam itself is
/// not gone: `ForgeAI.challenge` and the sixty-challenge matcher behind it are
/// exactly where they were, so the day 1.1 wants that screen back it is a screen
/// to write, not an architecture to rebuild.
@Observable
final class ChallengeStore {

    /// Read for the current day, and written to when a challenge is finished.
    /// The challenge store has no history of its own: yesterday's challenge is
    /// gone, on purpose, because a scoreboard of challenges taken and missed is
    /// exactly the pressure this feature must not add. What survives the day is
    /// only the fact of a finish, and it lives with every other fact about
    /// what somebody did — `ProgressStore.challengesKept`.
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
        // A challenge finished today on the build before this one was never
        // written down as kept. Today's state is the truth, so the record is
        // brought into step with it once, here — and only for today, the one
        // day whose state is still known.
        if today.state == .completed {
            progress.keepChallenge(today.challenge, on: today.day, at: today.completedAt ?? progress.now)
        }
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
        let wasAccepted = today.state == .accepted
        today.state = .accepted
        today.completedAt = nil
        persist()
        progress.releaseChallenge(on: today.day)
        if !wasAccepted { ForgeTelemetry.send(.challengeAccepted) }
    }

    /// Not today. Reversible all day — somebody who skips at eight and changes
    /// their mind at four should not have to wait for midnight.
    func skip() {
        today.state = .skipped
        today.completedAt = nil
        persist()
        progress.releaseChallenge(on: today.day)
    }

    func complete() {
        guard today.state != .completed else { return }
        today.state = .completed
        today.completedAt = progress.now
        persist()
        progress.keepChallenge(today.challenge, on: today.day, at: progress.now)
        ForgeTelemetry.send(.challengeCompleted)
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
        progress.releaseChallenge(on: today.day)
    }

    /// The dimension today's challenge feeds, said on its card — "Counts toward
    /// Discipline". The aim, read off the challenge, so a card and the Shape
    /// can never name two different ones.
    static func countsToward(_ challenge: DailyChallenge) -> String {
        "Counts toward \(challenge.focus.label)"
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
        // Whatever the day's challenge was, it is not the one being kept now:
        // a finish of the one replaced must not go on counting for its
        // dimension under a card that is about another.
        progress.releaseChallenge(on: today.day)
        ForgeTelemetry.send(.challengeAccepted)
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

import Foundation
import Observation

/// The weekly reviews, and the one rule for when one is offered.
///
/// Holds what somebody wrote and nothing else. Every figure a review shows is
/// read out of `ProgressStore` at the moment it is drawn — see `ReviewFacts` —
/// so a review opened a year later is read against the history as it actually
/// is rather than against a summary that was true once.
///
/// Same shape as `IdentityStore` and `ChapterStore`: App Group defaults, a
/// versioned key, an `isLoaded` guard, and a hand-written tolerant decoder.
@MainActor
@Observable
final class ReviewStore {

    /// Oldest week first.
    private(set) var reviews: [WeeklyReview] = []

    /// Which weekday the review is offered on. 1 = Sunday, matching
    /// `Calendar` and `ForgeDay.weekday`.
    ///
    /// Sunday by default because the week it reviews is the one that just
    /// ended, and because the evening of a day most people are not working is
    /// the only ninety seconds a week this can reliably have. Changeable in
    /// Settings — somebody whose week ends on a Thursday should be asked on a
    /// Thursday, and the whole thing is worthless on a day they resent.
    var reviewWeekday: Int = 1 {
        didSet {
            guard reviewWeekday != oldValue else { return }
            persist()
        }
    }

    /// The hour it becomes available, on the user's own day clock.
    ///
    /// Evening, because a review of a day that is still going is a review of a
    /// guess. Not user-facing: the day it lands on is worth choosing and the
    /// hour is not worth a second row in Settings.
    static let hour = 18

    private let defaults: UserDefaults
    private let key = "forge.reviews.v1"
    private let weekdayKey = "forge.reviewWeekday.v1"
    private var isLoaded = false

    init(defaults: UserDefaults = ForgeShared.defaults) {
        self.defaults = defaults
        load()
    }

    // MARK: - Storage

    private func load() {
        defer { isLoaded = true }
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([WeeklyReview].self, from: data) {
            reviews = decoded.sorted { $0.weekStart < $1.weekStart }
        }
        if defaults.object(forKey: weekdayKey) != nil {
            let stored = defaults.integer(forKey: weekdayKey)
            if (1...7).contains(stored) { reviewWeekday = stored }
        }
    }

    private func persist() {
        guard isLoaded else { return }
        if let data = try? JSONEncoder().encode(reviews) {
            defaults.set(data, forKey: key)
        }
        defaults.set(reviewWeekday, forKey: weekdayKey)
    }

    // MARK: - Which week

    /// The seven days ending on the most recent review weekday.
    ///
    /// **Defined against the review weekday rather than against
    /// `Calendar.firstWeekday`**, and that is the whole of why this is correct
    /// across locales. "Sunday evening" reviews the week that just ended
    /// everywhere; a window built from the calendar's own first weekday would
    /// review a week that had barely started for every user whose region begins
    /// the week on Sunday, which is most of the Americas.
    ///
    /// Read in `ForgeDay`, so the four-in-the-morning day boundary applies for
    /// free: somebody answering at one a.m. on Monday is still in Sunday and
    /// gets Sunday's review rather than next week's.
    func window(endingOnOrBefore day: ForgeDay) -> (start: ForgeDay, end: ForgeDay) {
        let back = (day.weekday - reviewWeekday + 7) % 7
        let end = day.adding(days: -back)
        return (end.adding(days: -6), end)
    }

    /// The week a review would be about right now.
    func currentWindow(on day: ForgeDay) -> (start: ForgeDay, end: ForgeDay) {
        window(endingOnOrBefore: day)
    }

    // MARK: - Whether to offer one

    /// Whether Forge should offer a review.
    ///
    /// Four conditions, and each one is a way this could become a nuisance:
    ///
    /// - the window has closed — on the review day itself, not before evening,
    ///   because a review of a day that is still going is a review of a guess;
    /// - this week has not already been dealt with. **Dealt with, not answered**
    ///   — dismissing writes a row too, so a review declined on Sunday does not
    ///   come back on Monday. See `dismiss(week:at:)`;
    /// - there is something to review. A week that asked for nothing produces a
    ///   screen with nothing on it, which teaches somebody to close it unread;
    /// - and it is not still the same week the install started in. Reviewing a
    ///   week somebody was present for two days of is a review of the app.
    func isDue(on day: ForgeDay, hour: Int, askedDays: Int, firstTracked: ForgeDay?) -> Bool {
        let window = currentWindow(on: day)
        if day == window.end, hour < Self.hour { return false }
        guard !isDealtWith(week: window.start) else { return false }
        guard askedDays > 0 else { return false }
        guard let firstTracked, firstTracked <= window.end else { return false }
        return true
    }

    /// Whether this week has been answered or declined.
    func isDealtWith(week start: ForgeDay) -> Bool {
        review(for: start)?.completedAt != nil
    }

    func review(for start: ForgeDay) -> WeeklyReview? {
        reviews.first { $0.weekStart == start }
    }

    /// Every week somebody actually wrote something about, newest first. What
    /// the chapter close reads back.
    var answered: [WeeklyReview] {
        reviews.filter(\.isAnswered).sorted { $0.weekStart > $1.weekStart }
    }

    /// The answered reviews whose week falls inside a chapter.
    func answered(from first: ForgeDay, to last: ForgeDay) -> [WeeklyReview] {
        answered.filter { $0.weekStart >= first.adding(days: -6) && $0.weekStart <= last }
            .sorted { $0.weekStart < $1.weekStart }
    }

    // MARK: - Answering

    /// Write the two sentences down.
    ///
    /// An empty answer is stored as an empty answer rather than refused: leaving
    /// one blank is a legitimate way to do a review, and a form that will not
    /// close until both boxes are full is a form people stop opening.
    @discardableResult
    func answer(
        week start: ForgeDay,
        whatHappened: String,
        whatNext: String,
        at instant: Date = .now
    ) -> WeeklyReview {
        var review = review(for: start) ?? WeeklyReview(weekStart: start)
        review.whatHappened = WeeklyReview.trimmed(whatHappened)
        review.whatNext = WeeklyReview.trimmed(whatNext)
        review.completedAt = instant
        review.updatedAt = instant
        upsert(review)
        return review
    }

    /// Not now. Writes the week down as dealt with so it is not offered again,
    /// and keeps no record of the fact anywhere the user can see — there is no
    /// count of skipped reviews, because a count of skipped reviews is a streak
    /// with a longer period.
    func dismiss(week start: ForgeDay, at instant: Date = .now) {
        var review = review(for: start) ?? WeeklyReview(weekStart: start)
        review.completedAt = instant
        review.updatedAt = instant
        upsert(review)
    }

    private func upsert(_ review: WeeklyReview) {
        if let index = reviews.firstIndex(where: { $0.weekStart == review.weekStart }) {
            reviews[index] = review
        } else {
            reviews.append(review)
            reviews.sort { $0.weekStart < $1.weekStart }
        }
        persist()
    }

    /// Take on what a merge decided, in one pass. A replacement rather than a
    /// union, the same reasoning `IdentityStore.adopt(_:)` is built on.
    func adopt(_ incoming: [WeeklyReview]) {
        let sorted = incoming.sorted { $0.weekStart < $1.weekStart }
        guard sorted != reviews else { return }
        reviews = sorted
        persist()
    }

    #if DEBUG
    func deleteAll() {
        reviews = []
        persist()
    }
    #endif
}

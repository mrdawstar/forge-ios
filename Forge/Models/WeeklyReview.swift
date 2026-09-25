import Foundation

/// Ninety seconds, once a week, in the user's own words.
///
/// # Why this exists
///
/// Forge's loop is all input. Complete, complete, complete, pull — and the only
/// thing the app ever says back is a three-second overlay that removes itself.
/// A practice with no output is a practice nobody can think about, and around
/// week six the days stop meaning anything because nothing has ever asked what
/// they were for.
///
/// So: one moment a week where the app says one true thing and the user says two.
/// That is the whole design, and every constraint on it comes from the same
/// place — **it has to survive being done fifty times a year.**
///
/// - **Two questions, never three.** A review that takes five minutes is done
///   twice and abandoned in week three. Two open questions and a week you can
///   see is about ninety seconds, which is a thing somebody does on a Sunday
///   without deciding to.
/// - **The app observes; the user interprets.** Forge states one fact it can
///   prove from the record and stops. It does not diagnose, suggest, or draw a
///   conclusion about the person — see `ReviewObservation`.
/// - **Skippable forever, and it costs nothing.** No streak of reviews, no count
///   of how many were missed, nothing marked against a week nobody wrote about.
///   Somebody who dismisses every review for a year has exactly the app they
///   would have had otherwise.
///
/// # What is stored
///
/// The two sentences, and when they were written. The observation is **not**
/// stored: it is derived from the record on read, the same rule everything else
/// in this app follows, so a review read back next year is read against the
/// history as it actually is rather than as it was summarised. What cannot be
/// re-derived is what somebody *said*, which is exactly what is kept.
struct WeeklyReview: Identifiable, Codable, Equatable, Sendable {

    /// The Monday — or whichever day the user's calendar starts the week on —
    /// of the week this is about. The identity of a review is the week itself,
    /// so there can never be two for one week and no id has to be minted.
    let weekStart: ForgeDay

    /// "What actually happened this week?"
    ///
    /// Deliberately not "how did it go". A week is a set of events, and asking
    /// for a rating gets a rating — which is a number about a person, which is
    /// the thing this app does not do.
    var whatHappened: String

    /// "What is next week for?"
    ///
    /// Forward, and singular. Not a list of goals: one sentence about what the
    /// next seven days are in aid of, which is the sentence the chapter close
    /// reads back and the only thing that makes a run of weeks a direction
    /// rather than a sequence.
    var whatNext: String

    /// When it was answered. Nil for one that was opened and left.
    var completedAt: Date?

    /// When this row last changed, for the merge. See `Chapter.updatedAt`.
    var updatedAt: Date = .distantPast

    var id: ForgeDay { weekStart }

    /// Whether anything was actually written. A review somebody skipped through
    /// is not a review, and nothing should read it back as one.
    var isAnswered: Bool {
        !whatHappened.isEmpty || !whatNext.isEmpty
    }

    /// The longest either answer may be.
    ///
    /// Long enough for a real thought, short enough that it cannot become a
    /// journal entry — this is a review, and the journal is an activity in the
    /// library for people who want one.
    static let answerLimit = 280

    init(
        weekStart: ForgeDay,
        whatHappened: String = "",
        whatNext: String = "",
        completedAt: Date? = nil,
        updatedAt: Date = .now
    ) {
        self.weekStart = weekStart
        self.whatHappened = WeeklyReview.trimmed(whatHappened)
        self.whatNext = WeeklyReview.trimmed(whatNext)
        self.completedAt = completedAt
        self.updatedAt = updatedAt
    }

    static func trimmed(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(answerLimit))
    }

    /// Hand-written and tolerant, for the reason every decoder in this app is:
    /// one throw fails the whole array, and the failure mode here is somebody
    /// losing the only sentences in Forge they actually wrote themselves.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weekStart = try c.decode(ForgeDay.self, forKey: .weekStart)
        whatHappened = WeeklyReview.trimmed(
            try c.decodeIfPresent(String.self, forKey: .whatHappened) ?? ""
        )
        whatNext = WeeklyReview.trimmed(
            try c.decodeIfPresent(String.self, forKey: .whatNext) ?? ""
        )
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? completedAt ?? .distantPast
    }

    private enum CodingKeys: String, CodingKey {
        case weekStart, whatHappened, whatNext, completedAt, updatedAt
    }
}

// MARK: - What the app is allowed to notice

/// Everything an observation may be drawn from.
///
/// A value rather than the store, and that is what makes the rules testable: the
/// generator is a pure function of this, so the empty week, the tied week and
/// the week where somebody kept everything are three literals in a test file
/// rather than three seeded histories. The same shape `ForgeNotificationPlan`
/// uses, for the same reason.
struct ReviewFacts: Equatable, Sendable {

    /// One weekday's record over the trailing window.
    struct Weekday: Equatable, Sendable, Identifiable {
        /// 1 = Sunday, matching `ForgeDay.weekday` and `Calendar`.
        let weekday: Int
        /// Days of this weekday that were kept.
        let kept: Int
        /// Days of this weekday that asked for anything at all.
        let asked: Int

        var id: Int { weekday }
        var rate: Double { asked > 0 ? Double(kept) / Double(asked) : 0 }
    }

    /// One activity's week.
    struct Habit: Equatable, Sendable, Identifiable {
        let id: String
        /// The name the user knows it by, resolved before it gets here.
        let name: String
        let planned: Int
        let completed: Int

        var rate: Double { planned > 0 ? Double(completed) / Double(planned) : 0 }
        var heldEveryTime: Bool { planned > 0 && completed == planned }
    }

    /// One identity's week, in days of evidence.
    struct Identity: Equatable, Sendable, Identifiable {
        let id: String
        /// The user's own sentence.
        let statement: String
        /// Days this week at least one tagged activity was finished.
        let days: Int
        /// Days this week one was asked for.
        let asked: Int
    }

    /// Days kept in the week under review.
    var kept: Int = 0
    /// Days in the week that asked for anything.
    var asked: Int = 0
    /// The trailing window this reads weekdays over, in weeks.
    var windowWeeks: Int = 0
    var weekdays: [Weekday] = []
    var habits: [Habit] = []
    var identities: [Identity] = []

    /// Nothing happened at all — no day asked for anything and none was kept.
    var isEmpty: Bool { asked == 0 && kept == 0 }
}

/// The one thing Forge says about a week.
///
/// # The register
///
/// **Flat, true, and about the record rather than about the person.** "You kept
/// four of five Mondays and one of five Fridays" is a fact somebody can do
/// something with. "You struggle on Fridays" is a diagnosis, and "Great work on
/// Mondays!" is an app with an opinion about a life it cannot see. Read
/// `DaySummary.line(for:)` and `PathStandard` for where this voice comes from:
/// the furthest Forge goes is noticing out loud.
///
/// **Nothing invented from a tie.** Where the record does not clearly say one
/// thing rather than another, the rule declines and the next one gets its turn —
/// the same bargain `BladeViewModel.habitExtremes` makes. An observation drawn
/// from two habits sitting at the same rate is a difference the app made up, and
/// the cost of making one up is that none of the others can be trusted either.
///
/// **One, never a list.** Three observations is a report, and a report is read
/// once. The rules are tried in order and the first that clears its own bar
/// wins, which is why the order below is a claim about what is most worth
/// hearing rather than an implementation detail.
///
/// # The seam
///
/// `make(from:)` is rules over a value. When a model is connected it answers the
/// same question from the same `ReviewFacts` and returns the same `String`, and
/// nothing else in the app changes — the same shape `ForgeAI` has, and the same
/// promise: what the phone computed and what a model wrote must stay
/// distinguishable, so a model-written observation arrives through a different
/// call and is labelled.
enum ReviewObservation {

    /// How many of a weekday there have to be before its rate is worth saying.
    /// Below this a fortnight of bad luck reads as a pattern.
    static let minimumWeekdaySample = 3
    /// How far apart two weekdays have to be before the difference is real.
    static let weekdayGap = 0.4
    /// How far apart two habits have to be before naming both is fair.
    static let habitGap = 0.34

    /// The sentence for this week, or nil when the record has nothing to say.
    ///
    /// Nil is a real answer and the review handles it: a first week has no
    /// pattern in it, and inventing one would teach somebody on day four that
    /// the observations are decoration.
    static func make(from facts: ReviewFacts) -> String? {
        weekdaySplit(facts)
            ?? habitSplit(facts)
            ?? neglectedIdentity(facts)
            ?? heldEverything(facts)
            ?? plainCount(facts)
    }

    // MARK: The rules, in the order they are tried

    /// "You kept four of five Mondays and one of five Fridays."
    ///
    /// First because it is the observation somebody could not have made
    /// themselves. Everybody knows roughly how their week went; almost nobody
    /// knows which day of the week has been quietly costing them for a month.
    static func weekdaySplit(_ facts: ReviewFacts) -> String? {
        let readable = facts.weekdays.filter { $0.asked >= minimumWeekdaySample }
        guard readable.count >= 2 else { return nil }
        guard let best = readable.max(by: { $0.rate < $1.rate }),
              let worst = readable.min(by: { $0.rate < $1.rate }),
              best.weekday != worst.weekday,
              best.rate - worst.rate >= weekdayGap
        else { return nil }

        // Lower-cased mid-sentence. `ForgeCount.spelled` capitalises, because
        // almost everywhere else in the app a count begins its own sentence —
        // "Thirty days." — and this is the one place it does not.
        return "You kept \(spelled(best.kept).lowercased()) of \(spelled(best.asked).lowercased()) \(plural(best.weekday)) "
            + "and \(spelled(worst.kept).lowercased()) of \(spelled(worst.asked).lowercased()) \(plural(worst.weekday))."
    }

    /// "Reading held every day it was asked for. The run did not."
    ///
    /// Two activities, named, and no adjective attached to either. The second
    /// clause is the one that has to stay flat: "the run did not" is what
    /// happened, and "you keep skipping your run" is the app telling somebody
    /// something about themselves that it is in no position to say.
    static func habitSplit(_ facts: ReviewFacts) -> String? {
        let readable = facts.habits.filter { $0.planned >= 2 }
        guard readable.count >= 2 else { return nil }
        guard let best = readable.max(by: { $0.rate < $1.rate }),
              let worst = readable.min(by: { $0.rate < $1.rate }),
              best.id != worst.id,
              best.rate - worst.rate >= habitGap
        else { return nil }

        let opening = best.heldEveryTime
            ? "\(best.name) held every day it was asked for."
            : "\(best.name) held \(spelled(best.completed).lowercased()) of \(spelled(best.planned).lowercased()) days."
        let closing = worst.completed == 0
            ? "\(worst.name) did not."
            : "\(worst.name) held \(spelled(worst.completed).lowercased())."
        return "\(opening) \(closing)"
    }

    /// "Someone who trains had no day this week. Someone who reads had four."
    ///
    /// Only ever said when one identity has real evidence and another has none:
    /// with a single identity there is nothing to compare and the sentence would
    /// be a reprimand rather than an observation. This is also the fact the
    /// daily challenge is now aimed at — see `ChallengeContext`.
    static func neglectedIdentity(_ facts: ReviewFacts) -> String? {
        guard facts.identities.count >= 2 else { return nil }
        guard let quietest = facts.identities.min(by: { $0.days < $1.days }),
              let loudest = facts.identities.max(by: { $0.days < $1.days }),
              quietest.id != loudest.id,
              quietest.days == 0, loudest.days >= 2,
              // It cannot have been neglected if it was never asked for. A
              // sentence somebody wrote and put no activity behind is not a
              // week they failed, it is a tag with nothing under it yet.
              quietest.asked > 0
        else { return nil }

        return "\(quietest.statement) had no day this week. "
            + "\(loudest.statement) had \(spelled(loudest.days).lowercased())."
    }

    /// "Every day this week asked for something, and every day got it."
    ///
    /// The one sentence here that could be read as praise, and it is written to
    /// be a description instead: it says what the record shows and stops. Kept
    /// separate from the plain count below so that a whole week does not read
    /// as "you kept seven of seven days", which is a scoreline.
    static func heldEverything(_ facts: ReviewFacts) -> String? {
        guard facts.asked >= 5, facts.kept == facts.asked else { return nil }
        return "Every day this week asked for something, and every day got it."
    }

    /// The floor. Says what the week was and nothing else.
    ///
    /// **Agreeing in number**, which it did not: a first week with one day on
    /// the record read "One of the one days that asked for something *were*
    /// kept" — three grammatical mistakes in the one sentence Forge writes about
    /// somebody's week, on the screen where it is the only thing it says. A
    /// first week is the commonest week there is.
    static func plainCount(_ facts: ReviewFacts) -> String? {
        guard !facts.isEmpty else { return nil }
        guard facts.kept > 0 else {
            return facts.asked == 1
                ? "The one day that asked for something was not finished. The record simply says so."
                : "No day was finished this week. The record simply says so."
        }
        guard facts.asked > 1 else {
            return "The one day that asked for something was kept."
        }
        let kept = spelled(facts.kept)
        let asked = spelled(facts.asked).lowercased()
        return facts.kept == 1
            ? "\(kept) of the \(asked) days that asked for something was kept."
            : "\(kept) of the \(asked) days that asked for something were kept."
    }

    // MARK: - Checking a sentence somebody else wrote

    /// Whether a model-written observation is allowed to be shown.
    ///
    /// # Why this exists at all
    ///
    /// Every other model-written thing in Forge is a *proposal*: a plan is shown
    /// as a list of changes and applied only if somebody says yes, a challenge is
    /// an offer that can be declined. A reading is different in kind — it is a
    /// claim about the user's own life, made to the one person in the world with
    /// no way to check it and every reason to believe it. "You kept four of five
    /// Mondays" is either true or it is the app inventing a month of somebody's
    /// history, and there is no version of the second that is recoverable.
    ///
    /// So the prompt is the cheap half of this feature and this function is the
    /// expensive half. **The model is never trusted; it is checked.** A sentence
    /// that fails any test below is thrown away and the rules answer instead, and
    /// the user is told nothing, because a fallback that works is not an incident.
    ///
    /// # The four tests
    ///
    /// 1. **Every number it asserts is in the record.** Digits and spelled-out
    ///    words both. A sentence containing a count the facts do not contain is
    ///    a sentence about a week that did not happen.
    /// 2. **Every name it uses exists.** Anything capitalised mid-sentence has
    ///    to be a habit the user named, a word from an identity they wrote, or a
    ///    weekday. This is what catches the failure the numbers test cannot:
    ///    a true count attached to the wrong activity.
    /// 3. **It is in the register.** No exclamation, no congratulation, no
    ///    diagnosis, no second-guessing of the person. The same denylist the
    ///    rules are tested against, applied to text the rules did not write.
    /// 4. **It is short.** Two sentences. A model given room to elaborate
    ///    elaborates, and every extra clause is another claim to check.
    ///
    /// Returns the trimmed sentence when it passes, and nil when it does not.
    static func validate(_ text: String, against facts: ReviewFacts) -> String? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= readingLimit else { return nil }
        guard sentenceCount(clean) <= 2 else { return nil }
        guard !breaksRegister(clean) else { return nil }
        guard numbersAreSupported(clean, by: facts) else { return nil }
        guard namesExist(clean, in: facts) else { return nil }
        return clean
    }

    /// Two sentences of about this length. Long enough for the weekday split,
    /// which is the longest thing the rules themselves ever say.
    static let readingLimit = 220

    /// Every number the record can honestly support.
    ///
    /// Built from the facts rather than from a range, so a sentence saying
    /// "three of five Mondays" when no weekday was asked for five times is
    /// rejected even though both numbers are small and plausible.
    static func supportedNumbers(in facts: ReviewFacts) -> Set<Int> {
        var found: Set<Int> = [facts.kept, facts.asked, facts.windowWeeks]
        for weekday in facts.weekdays { found.insert(weekday.kept); found.insert(weekday.asked) }
        for habit in facts.habits { found.insert(habit.completed); found.insert(habit.planned) }
        for identity in facts.identities { found.insert(identity.days); found.insert(identity.asked) }
        return found
    }

    private static func numbersAreSupported(_ text: String, by facts: ReviewFacts) -> Bool {
        let supported = supportedNumbers(in: facts)
        for token in numberTokens(in: text) {
            if let digits = Int(token) {
                guard supported.contains(digits) else { return false }
                continue
            }
            // Spelled-out counts are how the rules write, so they are how a
            // model asked to match the register will write too — and an
            // unsupported "seven" is exactly as false as an unsupported "7".
            if let spelled = numberWords[token] {
                guard supported.contains(spelled) else { return false }
            }
        }
        return true
    }

    /// Zero through forty-two, which is every count a week or a six-week
    /// chapter can produce, plus the two ordinals that stand in for one and two.
    ///
    /// Deliberately **not** including "a", "an", "no" or "none". They are
    /// numbers in the grammatical sense and never in the asserting sense — an
    /// English sentence cannot avoid them, and treating each one as a claim
    /// would reject almost everything the rules themselves say.
    private static let numberWords: [String: Int] = {
        var table: [String: Int] = ["once": 1, "twice": 2]
        for value in 0...42 {
            table[ForgeCount.spelled(value).lowercased()] = value
        }
        return table
    }()

    /// Tokens for the number check, keeping hyphens inside a word.
    ///
    /// `ForgeCount.spelled(21)` is "twenty-one", and splitting on the hyphen
    /// would turn one true claim into two separate ones — twenty and one — that
    /// the record almost certainly does not support, so a correct sentence would
    /// be thrown away.
    private static func numberTokens(in text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber && $0 != "-" }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-")) }
            .filter { !$0.isEmpty }
    }

    /// Whether every capitalised word is something the record actually holds.
    ///
    /// The vocabulary is the union of the habit names, the identity statements,
    /// the weekday names, and a closed list of the words a sentence in Forge's
    /// register legitimately opens with. Anything else capitalised is a proper
    /// noun the model brought with it, which is the shape an invented activity
    /// takes — a true count attached to a thing that does not exist, which the
    /// numbers check alone would wave straight through.
    ///
    /// **Sentence-initial words are checked too**, and an earlier version of
    /// this did not check them. It exempted the first word of every sentence as
    /// "just capitalisation", which meant `"Swimming held every day it was
    /// asked for."` passed cleanly for somebody who has never swum — the single
    /// most likely shape for this failure to take, because a sentence about an
    /// activity usually begins with the activity. The exemption is gone and the
    /// openers below took its place: a bounded list beats a blanket pass.
    static func namesExist(_ text: String, in facts: ReviewFacts) -> Bool {
        var vocabulary = sentenceOpeners
        for habit in facts.habits { vocabulary.formUnion(words(in: habit.name)) }
        for identity in facts.identities { vocabulary.formUnion(words(in: identity.statement)) }
        vocabulary.formUnion(Calendar.current.weekdaySymbols.map { $0.lowercased() })
        vocabulary.formUnion(Calendar.current.weekdaySymbols.map { $0.lowercased() + "s" })

        for token in text.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            let bare = token.trimmingCharacters(in: CharacterSet.letters.inverted)
            guard let first = bare.first, first.isUppercase else { continue }
            guard vocabulary.contains(bare.lowercased()) else { return false }
        }
        return true
    }

    /// Words a sentence here may begin with, and there are not many.
    ///
    /// Derived from what the rules themselves write plus the spelled numbers,
    /// because a count is the other thing a true sentence about a week starts
    /// with. Anything outside this and the record is a name the model invented.
    static let sentenceOpeners: Set<String> = {
        var words: Set<String> = [
            "forge", "you", "your", "yours", "i", "it", "its", "the", "a", "an",
            "this", "that", "these", "those", "there", "then", "every", "each",
            "no", "none", "nothing", "not", "someone", "somebody", "some",
            "both", "neither", "either", "and", "but", "days", "day", "week",
            "weeks", "on", "in", "of", "at", "by", "for", "from", "half",
            "most", "more", "less", "fewer", "only", "just", "still", "again",
        ]
        for value in 0...42 { words.insert(ForgeCount.spelled(value).lowercased()) }
        return words
    }()

    /// Words Forge does not say about somebody's week.
    ///
    /// Congratulation, diagnosis, and the second person telling somebody what
    /// they are like. The list is deliberately short and deliberately blunt: it
    /// is a floor under the register rather than a style guide, and the prompt
    /// does the actual work of asking for the voice.
    static let forbiddenWords: Set<String> = [
        "amazing", "awesome", "great", "fantastic", "incredible", "proud",
        "congratulations", "congrats", "wonderful", "brilliant", "crushed",
        "smashed", "keep", "nailed", "impressive", "excellent", "good",
        "struggle", "struggling", "failing", "failed", "lazy", "should",
        "must", "need", "try", "harder", "disappointing", "unfortunately",
        "journey", "unlock", "level", "score", "beat", "streak",
    ]

    static func breaksRegister(_ text: String) -> Bool {
        if text.contains("!") { return true }
        let spoken = Set(words(in: text))
        // "keep" is on the list as a congratulation ("keep it up") but "kept"
        // is the verb the whole app is written in, so the check is on the exact
        // word rather than on a stem.
        return !spoken.isDisjoint(with: forbiddenWords)
    }

    private static func sentenceCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0 == "." || $0 == "?" })
            .filter { $0.contains(where: \.isLetter) }
            .count
    }

    private static func words(in text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    // MARK: -

    private static func spelled(_ value: Int) -> String { ForgeCount.spelled(value) }

    /// "Mondays". Read off the calendar so it follows the device's language
    /// rather than a table of English literals that would go stale beside it.
    private static func plural(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        guard symbols.indices.contains(weekday - 1) else { return "days" }
        return symbols[weekday - 1] + "s"
    }
}

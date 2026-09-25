import SwiftUI

/// One sentence a world says.
///
/// Not an author quotation and deliberately not attributed to a real person.
/// Putting a living person's name under a sentence they never said is both a
/// legal problem and a smaller, cheaper thing than writing the world properly.
/// What is attributed is the Path — and since the catalog became archetypes
/// rather than characters there is no person left to attribute anything to,
/// which is one fewer way for this file to go wrong. See `AttributedQuote` for
/// the separate type that does carry a real name, and the rule it follows.
struct Quote: Identifiable, Equatable, Sendable {
    let id: String
    let text: String

    init(_ id: String, _ text: String) {
        self.id = id
        self.text = text
    }
}

/// Which sentence today gets, and the rule for choosing it.
///
/// The rule matters more than the sentences. Two devices signed into one account
/// must show the same words on the same day — a quote that differs between a
/// phone and an iPad is the app admitting it is decorative — so the choice is
/// arithmetic on the civil date and never a random draw, a launch counter or a
/// stored index. Nothing is persisted, because nothing needs to be: the same day
/// asks the same question and gets the same answer, on any device, forever.
enum QuoteBook {

    /// A stable position in the year, turned into a position in the list.
    ///
    /// Built from the civil date rather than from a `Date`, for the same reason
    /// `ForgeDay` exists at all: a timestamp moves across a timezone and a date
    /// does not, so somebody who lands in Tokyo keeps the sentence they woke up
    /// to instead of being handed tomorrow's on the way down.
    ///
    /// `month * 31 + day` rather than a real ordinal: it does not need to be a
    /// day count, only to advance by one most days and never to sit still, and
    /// this cannot be wrong about a leap year because it never asks.
    static func index(for day: ForgeDay, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let ordinal = day.year * 372 + day.month * 31 + day.day
        // Swift's `%` keeps the sign of the dividend, and a negative year is a
        // corrupted value rather than an impossible one.
        return ((ordinal % count) + count) % count
    }
}

// MARK: - Words somebody actually said

/// A line with a name under it.
///
/// Deliberately a different type from `Quote`, which is a Path speaking in its
/// own invented voice and is attributed to the world rather than to a person.
/// This one carries a real attribution, and that is the whole reason it is
/// separate: the two must never be able to reach the same `Text`, because the
/// day a world's line appears under somebody's name is the day Forge has put
/// words in a real person's mouth.
///
/// # The rule these were chosen under
///
/// Every line here is one the named source is reliably documented as having
/// said or written. Nothing is composed, nothing is "in the spirit of", and
/// anything whose attribution is contested — the gym-wall sayings that circulate
/// under four different names, the Aristotle line that is actually Will Durant's
/// summary of him — is either attributed correctly or left out. Modern
/// copyrighted sources appear as short excerpts only. Characters are attributed
/// to the character, never to the actor who spoke the line.
struct AttributedQuote: Identifiable, Equatable, Sendable {
    let id: String
    let text: String
    /// The person, the character, or the tradition. Shown verbatim under the
    /// line — a quotation without its source is a quotation Forge made up.
    let source: String

    init(_ id: String, _ text: String, _ source: String) {
        self.id = id
        self.text = text
        self.source = source
    }
}

/// What a line is being said *about*.
///
/// Six, and they are not decoration: the whole point of this system is that the
/// sentence after a hard day is about hardness and the sentence after four hours
/// of deep work is about attention. A single shuffled pool would be the
/// inspirational-quote-of-the-day widget every other app ships, which is exactly
/// what Forge is not.
enum QuoteTheme: String, CaseIterable, Sendable {
    /// A day with training in it. Physical hardness.
    case resilience
    /// A day of deep work. Attention.
    case focus
    /// A day of things nobody made you do.
    case discipline
    /// A day that was mostly about starting.
    case action
    /// A challenge taken and finished.
    case toughness
    /// Everything else, and the long view.
    case perseverance
}

/// What was just finished, so the line can be about it.
enum EarnedMoment: Equatable, Sendable {
    /// The day's list, finished. The leaning is the day's own — see
    /// `ChallengeContext.leaning`.
    case day(leaning: ChallengeFocus?)
    /// Today's challenge, finished.
    case challenge(ChallengeFocus)

    var theme: QuoteTheme {
        switch self {
        // A challenge is the one thing in Forge nobody has to do, so finishing
        // one is always about the same quality whatever it was aimed at.
        case .challenge: .toughness
        case .day(let leaning):
            switch leaning {
            case .physical: .resilience
            case .intellect, .ambition: .focus
            case .discipline: .discipline
            case .relationship: .action
            // Steadiness is the long view rather than a push, which is the one
            // wall written about enduring something rather than starting it.
            case .mental: .perseverance
            case nil: .perseverance
            }
        }
    }
}

/// The wall.
///
/// Chosen the same way `QuoteBook` chooses a Path's line — arithmetic on the
/// civil date, never a random draw — so two devices signed into one account show
/// the same words for the same day, and so a screenshot of the moment is
/// reproducible.
enum ForgeQuotes {

    /// Today's line for what was just earned.
    ///
    /// Never nil. This is the one place in Forge that speaks after the blade is
    /// out, and a moment that sometimes says nothing is a moment somebody learns
    /// not to look at.
    static func quote(for moment: EarnedMoment, on day: ForgeDay) -> AttributedQuote {
        let wall = quotes(for: moment.theme)
        return wall[QuoteBook.index(for: day, count: wall.count)]
    }

    static func quotes(for theme: QuoteTheme) -> [AttributedQuote] {
        switch theme {
        case .resilience: resilience
        case .focus: focus
        case .discipline: discipline
        case .action: action
        case .toughness: toughness
        case .perseverance: perseverance
        }
    }

    /// Every line, for the test that proves none of them is empty, unattributed
    /// or duplicated.
    static var all: [AttributedQuote] {
        QuoteTheme.allCases.flatMap(quotes(for:))
    }

    // MARK: Resilience — a day with training in it

    static let resilience: [AttributedQuote] = [
        AttributedQuote("q.res.goggins", "Stay hard.", "David Goggins"),
        AttributedQuote(
            "q.res.ali",
            "Suffer now and live the rest of your life as a champion.",
            "Muhammad Ali"
        ),
        AttributedQuote(
            "q.res.arnold",
            "The last three or four reps is what makes the muscle grow.",
            "Arnold Schwarzenegger"
        ),
        // This slot held a line of film dialogue attributed to a fictional
        // character. It went on 2026-09-15, with the one in `action`, for the
        // reason the character plates went in August: a trademarked character's
        // name under a line of somebody else's screenplay is the only
        // intellectual property left in the app, and it is worth nothing to the
        // product. Douglass said this in 1857 and it is public domain.
        AttributedQuote(
            "q.res.douglass",
            "If there is no struggle, there is no progress.",
            "Frederick Douglass"
        ),
    ]

    // MARK: Focus — a day of deep work

    static let focus: [AttributedQuote] = [
        AttributedQuote(
            "q.foc.emerson",
            "Concentration is the secret of strength.",
            "Ralph Waldo Emerson"
        ),
        AttributedQuote("q.foc.marcus", "Confine yourself to the present.", "Marcus Aurelius"),
        AttributedQuote(
            "q.foc.clear",
            "You do not rise to the level of your goals. You fall to the level of your systems.",
            "James Clear"
        ),
    ]

    // MARK: Discipline — a day of things nobody made you do

    static let discipline: [AttributedQuote] = [
        AttributedQuote("q.dis.jocko", "Discipline equals freedom.", "Jocko Willink"),
        AttributedQuote(
            "q.dis.marcus",
            "Waste no more time arguing about what a good man should be. Be one.",
            "Marcus Aurelius"
        ),
        AttributedQuote(
            "q.dis.epictetus",
            "First say to yourself what you would be; and then do what you have to do.",
            "Epictetus"
        ),
        // Durant, summarising Aristotle in The Story of Philosophy — and one of
        // the most misattributed sentences in circulation. It is here under the
        // name of the man who actually wrote it.
        AttributedQuote(
            "q.dis.durant",
            "We are what we repeatedly do. Excellence, then, is not an act, but a habit.",
            "Will Durant"
        ),
    ]

    // MARK: Action — a day that was mostly about starting

    static let action: [AttributedQuote] = [
        AttributedQuote(
            "q.act.marcus",
            "What stands in the way becomes the way.",
            "Marcus Aurelius"
        ),
        // Was a line of film dialogue under a trademarked character's name. See
        // the note in `resilience`. Seneca, Epistulae Morales 104.26.
        AttributedQuote(
            "q.act.seneca",
            "It is not because things are difficult that we do not dare; it is because we do not dare that things are difficult.",
            "Seneca"
        ),
        AttributedQuote(
            "q.act.roosevelt",
            "Nothing in the world is worth having or worth doing unless it means effort, pain, difficulty.",
            "Theodore Roosevelt"
        ),
    ]

    // MARK: Toughness — a challenge taken and finished

    static let toughness: [AttributedQuote] = [
        AttributedQuote(
            "q.tou.tyson",
            "Everybody has a plan until they get punched in the mouth.",
            "Mike Tyson"
        ),
        AttributedQuote(
            "q.tou.kobe",
            "Everything negative — pressure, challenges — is all an opportunity for me to rise.",
            "Kobe Bryant"
        ),
        AttributedQuote(
            "q.tou.jordan",
            "I've failed over and over and over again in my life. And that is why I succeed.",
            "Michael Jordan"
        ),
        AttributedQuote("q.tou.proverb", "Fall seven times, stand up eight.", "Japanese proverb"),
    ]

    // MARK: Perseverance — the long view

    static let perseverance: [AttributedQuote] = [
        AttributedQuote(
            "q.per.king",
            "Champions keep playing until they get it right.",
            "Billie Jean King"
        ),
        AttributedQuote(
            "q.per.kobe",
            "The moment you give up is the moment you let someone else win.",
            "Kobe Bryant"
        ),
        AttributedQuote(
            "q.per.plutarch",
            "Perseverance is more prevailing than violence.",
            "Plutarch"
        ),
    ]
}

// MARK: - Reaching today's quote from a view

private struct DailyQuoteKey: EnvironmentKey {
    static let defaultValue: Quote? = nil
}

extension EnvironmentValues {
}

// MARK: - Placeholders

extension Quote {
}

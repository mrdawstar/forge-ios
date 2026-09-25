import Foundation

/// What sits behind the AI screens until a model does.
///
/// Everything here is arithmetic on the user's own week. It does not call
/// anything, nothing leaves the phone, and — the part that decides how every
/// screen using it must be worded — **it is not a model and never claims to
/// be**. `isConnected` is `false`, and each surface that shows its output says
/// so in plain language.
///
/// # Why it does real work instead of nothing
///
/// The obvious stand-in is a stub that throws, and it would have been the wrong
/// thing to build. A premium feature whose screens cannot be driven end to end
/// is a feature nobody — user or author — can judge, and the flow that matters
/// here is not the sentence the model writes, it is everything around it:
/// compose a request, watch it work, **read a list of changes**, apply them,
/// see the week actually move. All of that is real now, and the only part
/// waiting on a model is the range of sentences it will accept.
///
/// So this refuses honestly. It answers three kinds of request it can genuinely
/// do — lay out a week around fixed hours, shift everything by an offset, move
/// one activity to another day — and for anything freer it throws
/// `.notConnected` rather than guessing. A planner that invents an answer to a
/// sentence it did not understand is worse than one that says it did not
/// understand.
struct LocalForgeAI: ForgeAI {

    let isConnected = false

    // MARK: - Challenges

    /// The catalogue, narrowed to what was asked for and then tilted toward the
    /// person asking.
    ///
    /// Narrowing is exact where it can be — a request for a hard Courage
    /// challenge returns a hard Courage challenge — and widens by one step
    /// rather than failing when the shelf is empty at that combination, because
    /// "no challenge exists at that setting" is a sentence about our catalogue
    /// that no user should ever have to read.
    func challenge(
        brief: AIBrief,
        difficulty: ChallengeDifficulty,
        focus: ChallengeFocus,
        wish: String
    ) async throws -> DailyChallenge {
        // Long enough that the composing state is visible, short enough that it
        // is never a wait. Replaced wholesale by a real request later.
        try? await Task.sleep(for: .milliseconds(650))

        let aimed = ChallengeCatalog.all.filter { $0.focus == focus }
        let exact = aimed.filter { $0.difficulty == difficulty }
        let shelf = exact.isEmpty ? aimed : exact
        guard !shelf.isEmpty else { throw ForgeAIError.failed }

        // What they typed picks from the shelf where it can. Word overlap, not
        // comprehension — but "something to stop me procrastinating" really does
        // land on "Do the thing you keep moving", and a shelf of sixty is
        // small enough for that to be true more often than not.
        let picked = Self.bestMatch(for: wish, in: shelf) ?? shelf.randomElement()!

        return DailyChallenge(
            id: "\(picked.id).personal.\(UUID().uuidString.prefix(6))",
            title: picked.title,
            detail: Self.tailored(picked.detail, to: brief),
            focus: focus,
            difficulty: difficulty,
            isPersonal: true
        )
    }

    /// The challenge whose words overlap most with what they asked for, or nil
    /// when nothing overlaps at all.
    static func bestMatch(for wish: String, in shelf: [DailyChallenge]) -> DailyChallenge? {
        let wanted = Self.meaningfulWords(in: wish)
        guard !wanted.isEmpty else { return nil }

        var best: (challenge: DailyChallenge, score: Int)?
        for candidate in shelf {
            let text = Self.meaningfulWords(in: "\(candidate.title) \(candidate.detail)")
            let score = wanted.count { want in
                text.contains { Self.sharesStem($0, want) }
            }
            if score > 0, score > (best?.score ?? 0) { best = (candidate, score) }
        }
        return best?.challenge
    }

    /// Whether two words are the same word wearing a different ending.
    ///
    /// **This used to be a pair of `hasPrefix` checks, and the doc comment
    /// above them claimed it stemmed. It did not.** `hasPrefix` only matches
    /// when one whole word is the start of the other, so "training" reached
    /// "train" but "negotiating" never reached "negotiate" — they agree for
    /// eight characters and then diverge, `i` against `e`, and neither is a
    /// prefix of the other. A test had asserted the working case for months
    /// while the comment described the broken one.
    ///
    /// So this compares the shared opening instead, which is what stemming
    /// actually is at this crudeness. Six characters is the bar, except where a
    /// word is shorter than that and is wholly contained — which keeps the old
    /// "training"/"train" behaviour that was genuinely working.
    ///
    /// It is still word overlap and not comprehension, and it is still allowed
    /// to be: this is the fallback that runs when no model is reachable, and a
    /// shelf of sixty is small enough that crude matching lands more often
    /// than not. `ClaudeForgeAI` is what runs when it matters.
    static func sharesStem(_ a: String, _ b: String) -> Bool {
        let shortest = min(a.count, b.count)
        guard shortest > 0 else { return false }
        let shared = zip(a, b).prefix { $0 == $1 }.count
        return shared >= min(stemLength, shortest)
    }

    /// Long enough that "morning" and "moment" are different words, short
    /// enough that "negotiate" and "negotiating" are the same one.
    static let stemLength = 6

    /// Words worth matching on: everything past four letters, lowercased.
    ///
    /// The threshold is doing the work of a stop-list. "want", "give", "some"
    /// and "that" are the words two unrelated sentences share, and a match on
    /// them is noise dressed as a result.
    private static func meaningfulWords(in text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter }
            .map(String.init)
            .filter { $0.count > 4 }
    }

    /// One clause about their actual week, appended to the catalogue's sentence.
    ///
    /// Not a rewrite. It names something the user already put in Forge, so the
    /// line reads as being about them without inventing a single fact — the only
    /// kind of personalisation a phone with no model can honestly do.
    private static func tailored(_ detail: String, to brief: AIBrief) -> String {
        if let anchor = brief.activities.first {
            return "\(detail) Slot it beside \(anchor.name.lowercased())."
        }
        if brief.streak >= 3 {
            return "\(detail) You are \(brief.streak) days in — this is the day to add weight."
        }
        return detail
    }

    // MARK: - Reading the record back

    /// The week, read back by the rules.
    ///
    /// The one method here that is not a lesser version of what a model does.
    /// `ReviewObservation` states a fact drawn from the record and stops, which
    /// is a genuinely correct answer to "what happened this week" — a model
    /// writes it better, and neither can write it *truer*. That is why the
    /// review shipped before the model did and why a phone with no account
    /// still gets an observation.
    ///
    /// Throwing on nil rather than returning an empty reading, because "the
    /// record has nothing to say yet" is a real state — a first week has no
    /// pattern in it — and the review screen already draws it correctly by
    /// showing no observation at all.
    func reading(brief: AIBrief) async throws -> PracticeReading {
        guard let facts = brief.week else { throw ForgeAIError.nothingToRead }
        guard let line = ReviewObservation.make(from: facts) else {
            throw ForgeAIError.nothingToRead
        }
        return PracticeReading(observation: line, isModelWritten: false)
    }

    // MARK: - Planning

    /// Work out what kind of request this is, and answer only the kinds that can
    /// be answered without a model.
    func plan(brief: AIBrief, request: String) async throws -> SchedulePlan {
        guard !brief.isEmpty else { throw ForgeAIError.nothingToPlan }
        try? await Task.sleep(for: .milliseconds(850))

        let asked = request.lowercased()
        let busy = Self.window(in: asked)

        // A stated commitment is the strongest signal there is that somebody
        // wants the whole week laid out, so it outranks the narrower readings
        // below — "I work 9 to 5, move my run to Wednesday" is a plan.
        if busy != nil || asked.isEmpty || Self.wantsAPlan(asked) {
            return try Self.layOut(brief: brief, request: asked, busy: busy)
        }
        if let offset = Self.shift(in: asked) {
            return try Self.shiftEverything(by: offset, brief: brief)
        }
        if let move = Self.moveRequest(in: asked, brief: brief) {
            return try Self.move(move.activity, to: move.weekday, brief: brief)
        }
        throw ForgeAIError.notConnected
    }

    private static let planWords = [
        "plan", "schedule", "routine", "rebuild", "lay out", "sort out",
        "organise", "organize", "my week", "my day",
    ]

    static func wantsAPlan(_ request: String) -> Bool {
        planWords.contains { request.contains($0) }
    }

    // MARK: Laying out a week

    /// Put the week's activities into the hours that are actually free.
    ///
    /// The rules, in the order they are applied:
    ///
    /// 1. **Stated commitments are inviolate.** Nothing is placed inside a
    ///    window somebody said they were working, and anything already sitting
    ///    in one is moved out. This is the single complaint that makes a
    ///    generated day useless, so it is the first rule rather than the last.
    /// 2. **Frequencies are honoured.** "Train three times" becomes three days
    ///    spread across the week rather than three days in a row — see
    ///    `spread(_:)`.
    /// 3. **Times already chosen are kept**, unless they collide. Somebody who
    ///    set an activity to 06:00 meant it, and a planner that reshuffles what
    ///    it was not asked about is one nobody presses twice.
    /// 4. **Everything else is placed in order**, morning first unless the
    ///    request says otherwise, spaced so the day is not a wall.
    static func layOut(brief: AIBrief, request: String, busy: (start: Int, end: Int)?) throws -> SchedulePlan {
        let wake = brief.wakeMinutes ?? 7 * 60
        var changes: [ScheduleChange] = []

        // The hours left over once the stated commitment is taken out, each with
        // its own cursor. 15 minutes after waking, and nothing after 22:30.
        var morning = Slot(from: wake + 15, to: busy?.start ?? Self.dayEnd)
        var evening = Slot(from: (busy?.end).map { $0 + 30 } ?? Self.dayEnd, to: Self.dayEnd)

        // Anything with an hour that does not clash keeps it, and keeps its
        // place: the cursors are advanced past it so nothing is laid on top.
        for activity in brief.activities {
            guard let start = activity.startMinute, !Self.clashes(activity, with: busy) else { continue }
            morning.reserve(start, activity.length)
            evening.reserve(start, activity.length)
        }

        for activity in brief.activities {
            // Days first — a frequency changes how often, not when.
            if let count = Self.frequency(for: activity.name, in: request) {
                let days = Self.spread(count)
                if days != activity.weekdays {
                    changes.append(
                        .days(id: activity.id, name: activity.name, weekdays: days, was: activity.weekdays)
                    )
                }
            }

            let settled = activity.startMinute
            let clashing = Self.clashes(activity, with: busy)
            // Rule 3: leave a good time alone.
            if settled != nil, !clashing { continue }

            let prefersEvening = Self.prefersEvening(activity.name, in: request)
            let placed = prefersEvening
                ? evening.take(activity.length) ?? morning.take(activity.length)
                : morning.take(activity.length) ?? evening.take(activity.length)

            guard let placed else { continue }
            changes.append(
                .time(id: activity.id, name: activity.name, minute: placed, was: settled)
            )
        }

        guard !changes.isEmpty else { throw ForgeAIError.noChange }

        var summary = "\(changes.count == 1 ? "One change" : "\(changes.count) changes") to your week."
        if let busy {
            summary += " Your \(ClockMinute.label(busy.start)) to \(ClockMinute.label(busy.end)) is left alone."
        }
        return SchedulePlan(summary: summary, changes: changes, isModelWritten: false)
    }

    /// Nothing is scheduled past this. A planner that fills somebody's midnight
    /// is not planning, it is running out of room and carrying on.
    private static let dayEnd = 22 * 60 + 30

    /// A run of free minutes, and how far into it we have got.
    private struct Slot {
        var cursor: Int
        let end: Int
        /// Minutes left between one activity and the next.
        static let gap = 15

        init(from: Int, to: Int) {
            self.cursor = from
            self.end = to
        }

        /// Claim the next `length` minutes, or nil when this slot is full.
        mutating func take(_ length: Int) -> Int? {
            let start = Self.rounded(cursor)
            guard start + length <= end else { return nil }
            cursor = start + length + Self.gap
            return start
        }

        /// Up to the next five minutes.
        ///
        /// Purely cosmetic and worth every line. Laying activities end to end
        /// with their real durations produces 7:31, 8:16, 8:33 — arithmetic,
        /// visibly. Nobody writes a plan like that; people write them on the
        /// fives, and a generated day that looks generated is one people trust
        /// less than one they wrote themselves.
        static func rounded(_ minute: Int) -> Int {
            (minute + 4) / 5 * 5
        }

        /// Step over something already sitting here.
        mutating func reserve(_ start: Int, _ length: Int) {
            guard start + length > cursor, start < end else { return }
            cursor = min(end, start + length + Self.gap)
        }
    }

    private static func clashes(_ activity: ScheduledActivity, with busy: (start: Int, end: Int)?) -> Bool {
        guard let busy, let start = activity.startMinute else { return false }
        return start < busy.end && (start + activity.length) > busy.start
    }

    // MARK: Shifting the whole week

    /// "Everything an hour later." Moves what has a time and leaves the rest.
    static func shiftEverything(by offset: Int, brief: AIBrief) throws -> SchedulePlan {
        let changes: [ScheduleChange] = brief.activities.compactMap { activity in
            guard let start = activity.startMinute else { return nil }
            let moved = min(max(0, start + offset), 23 * 60 + 59)
            guard moved != start else { return nil }
            return .time(id: activity.id, name: activity.name, minute: moved, was: start)
        }
        guard !changes.isEmpty else { throw ForgeAIError.noChange }

        let size = ClockMinute.duration(abs(offset)) ?? "a little"
        return SchedulePlan(
            summary: "Everything with a time moves \(size) \(offset > 0 ? "later" : "earlier").",
            changes: changes
        )
    }

    /// "an hour later", "30 minutes earlier", "push everything back 45 minutes".
    static func shift(in request: String) -> Int? {
        let laterWords = ["later", "back", "push"]
        let earlierWords = ["earlier", "sooner", "forward", "bring"]
        let isLater = laterWords.contains { request.contains($0) }
        let isEarlier = earlierWords.contains { request.contains($0) }
        guard isLater != isEarlier else { return nil }

        guard let size = duration(in: request) else { return nil }
        return isLater ? size : -size
    }

    /// "an hour", "two hours", "30 minutes", "45 min".
    static func duration(in request: String) -> Int? {
        let words = request.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        for (index, word) in words.enumerated() {
            guard word.hasPrefix("hour") || word.hasPrefix("min") else { continue }
            let unit = word.hasPrefix("hour") ? 60 : 1
            // The number in front of it, as digits or as a word.
            guard index > 0 else { return unit }
            let before = words[index - 1]
            if let count = Int(before) { return count * unit }
            if let count = number(before) { return count * unit }
            // "an hour", "half an hour"
            if before == "an" || before == "a" {
                return index > 1 && words[index - 2] == "half" ? unit / 2 : unit
            }
            return unit
        }
        return nil
    }

    // MARK: Moving one activity

    /// "Move my workout to Wednesday."
    static func moveRequest(in request: String, brief: AIBrief) -> (activity: ScheduledActivity, weekday: Int)? {
        guard let weekday = self.weekday(in: request) else { return nil }
        guard let activity = self.activity(named: request, in: brief) else { return nil }
        return (activity, weekday)
    }

    static func move(_ activity: ScheduledActivity, to weekday: Int, brief: AIBrief) throws -> SchedulePlan {
        let current = activity.weekdays.isEmpty ? Set(1...7) : activity.weekdays
        guard current != [weekday] else { throw ForgeAIError.noChange }
        return SchedulePlan(
            summary: "\(activity.name) moves to \(RitualRepeat.short(weekday)).",
            changes: [
                .days(id: activity.id, name: activity.name, weekdays: [weekday], was: activity.weekdays)
            ]
        )
    }

    /// The first weekday named in a sentence, as a `Calendar` weekday.
    static func weekday(in request: String) -> Int? {
        let names = [
            (1, ["sunday", "sun"]), (2, ["monday", "mon"]), (3, ["tuesday", "tue", "tues"]),
            (4, ["wednesday", "wed"]), (5, ["thursday", "thu", "thurs"]),
            (6, ["friday", "fri"]), (7, ["saturday", "sat"]),
        ]
        let words = Set(request.split { !$0.isLetter }.map(String.init))
        for (weekday, spellings) in names where spellings.contains(where: words.contains) {
            return weekday
        }
        return nil
    }

    /// The activity a sentence is about, matched on its own name.
    ///
    /// Longest name first, so "morning run" wins over "run" when the week holds
    /// both and the sentence names the longer one.
    static func activity(named request: String, in brief: AIBrief) -> ScheduledActivity? {
        brief.activities
            .sorted { $0.name.count > $1.name.count }
            .first { request.contains($0.name.lowercased()) }
    }

    // MARK: Reading a sentence

    /// The first pair of hours in a sentence, if there is one.
    ///
    /// "work from 9 to 17", "9-5", "09:00 until 17:30". Anything cleverer than
    /// this belongs to the model, not to the fallback standing in for it.
    ///
    /// Written as a scan rather than as a regex on purpose: the target builds in
    /// Swift 5 language mode, where a bare-slash literal needs a build setting
    /// this project does not have, and a runtime-compiled `Regex` would trade a
    /// readable twenty lines for untyped captures and a `try!`.
    static func window(in request: String) -> (start: Int, end: Int)? {
        var spaced = request.lowercased()
        for dash in ["-", "–", "—"] {
            spaced = spaced.replacingOccurrences(of: dash, with: " - ")
        }

        let separators: Set<String> = ["-", "to", "until", "till"]
        var opening: Int?
        var awaitingEnd = false

        for word in spaced.split(whereSeparator: { $0 == " " || $0 == "," }) {
            let token = String(word).trimmingCharacters(in: CharacterSet(charactersIn: ".;!?"))

            if awaitingEnd, let start = opening, let closing = minutes(token) {
                // "nine to five" means the afternoon. Only ever applied to a
                // morning start, so "17 to 9" stays the nonsense it is rather
                // than being helpfully turned into an evening.
                let end = (closing < start && start <= 12 * 60) ? closing + 12 * 60 : closing
                return end > start ? (start, end) : nil
            }

            if separators.contains(token) {
                awaitingEnd = opening != nil
            } else if let time = minutes(token) {
                opening = time
                awaitingEnd = false
            }
            // Anything else — "from", "work", "i" — is passed over rather than
            // treated as a break, so "9 am to 5 pm" reads as one window.
        }
        return nil
    }

    /// "9" or "09:30", in minutes past midnight. Nil for anything that is not a
    /// clock time, which is most of a sentence.
    private static func minutes(_ token: String) -> Int? {
        let parts = token.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 2, let hour = Int(parts[0]), (0...23).contains(hour) else { return nil }
        guard parts.count == 2 else { return hour * 60 }
        guard let minute = Int(parts[1]), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    /// The part of a sentence that is about one activity.
    ///
    /// Split on conjunctions rather than by counting characters either side of
    /// the name. The first version of this took 36 characters in each direction
    /// and got "train three times and read every evening" wrong in the most
    /// embarrassing way available: the window around *train* reached all the way
    /// into *every evening*, so training was scheduled seven days a week. A
    /// clause has an end, and the end is where the next one starts.
    static func clause(about name: String, in request: String) -> String? {
        request
            .replacingOccurrences(of: ";", with: ",")
            .components(separatedBy: ",")
            .flatMap { $0.components(separatedBy: " and ") }
            .first { $0.contains(name.lowercased()) }
    }

    /// How many times a week the request asks for this activity, if it says.
    ///
    /// Read from the clause about that activity, so "train three times and read
    /// every evening" gives three to one and seven to the other rather than
    /// three — or seven — to both.
    static func frequency(for name: String, in request: String) -> Int? {
        guard let clause = clause(about: name, in: request) else { return nil }

        if clause.contains("every day") || clause.contains("daily") || clause.contains("every evening")
            || clause.contains("every morning") || clause.contains("every night") {
            return 7
        }
        guard clause.contains("time") || clause.contains("session") || clause.contains("week") else {
            return nil
        }

        let words = clause.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        for word in words {
            if let digits = Int(word), (1...7).contains(digits) { return digits }
            if let spelled = number(word), (1...7).contains(spelled) { return spelled }
        }
        return nil
    }

    private static func number(_ word: String) -> Int? {
        switch word {
        case "one", "once": 1
        case "two", "twice": 2
        case "three", "thrice": 3
        case "four": 4
        case "five": 5
        case "six": 6
        case "seven": 7
        case "half": 0
        default: nil
        }
    }

    /// Which days a given number of sessions a week should land on.
    ///
    /// Spread rather than consecutive, and that is the whole point of doing this
    /// in code: three sessions on Monday, Tuesday and Wednesday is the schedule
    /// somebody abandons in week two. Rest between them is the part a person
    /// asking for "three times" means and does not say.
    static func spread(_ count: Int) -> Set<Int> {
        switch max(1, min(7, count)) {
        case 1: [4]                    // Wednesday
        case 2: [3, 6]                 // Tuesday, Friday
        case 3: [2, 4, 6]              // Monday, Wednesday, Friday
        case 4: [2, 3, 5, 6]           // Mon, Tue, Thu, Fri
        case 5: RitualRepeat.weekdays5.weekdays
        case 6: [2, 3, 4, 5, 6, 7]     // everything but Sunday
        default: Set(1...7)
        }
    }

    /// Whether the request puts this activity in the evening.
    ///
    /// Read from the same clause `frequency` uses, for the same reason: "train
    /// in the morning and read in the evening" has to give each of them their
    /// own half of the sentence.
    static func prefersEvening(_ name: String, in request: String) -> Bool {
        guard let clause = clause(about: name, in: request) else { return false }
        return clause.contains("evening") || clause.contains("night") || clause.contains("after work")
    }
}

private extension ScheduledActivity {
    /// How long to reserve for it. Half an hour for anything that has never been
    /// given a length — long enough to be a real block, short enough that a
    /// week of them still fits in a day.
    var length: Int { minutes > 0 ? minutes : 30 }
}

import Foundation

/// Seven questions, answered once, and the six starting numbers they give.
///
/// # What this is
///
/// **Stated data.** The record (`DayRecord`) is what somebody did; this is what
/// they said about themselves before they had done anything in Forge. Both are
/// facts and they are different facts, which is why this is stored beside the
/// record rather than written into it — the same reason `ForgeViewModel.focus`
/// is stored and the Shape is not.
///
/// **Only the answers are kept.** Every baseline is derived from them on read
/// (§5 #2): the table below is the only place a starting number comes from, so
/// changing it changes every install's starting numbers on the next read and no
/// install can hold a number the table does not produce.
///
/// # Why the baselines stop at seventy-five
///
/// A self-report can honestly put somebody most of the way. It cannot put them
/// at the top: the last quarter of every dimension is only reachable through
/// days actually kept, so `range` clamps every answer to 5…75. The floor is five
/// rather than nought for the reason `FocusHexagon` has a floor — a part of a
/// person nobody is pointing at is still a part of them, and a vertex at the
/// centre draws them as nothing.
///
/// # How long an answer counts
///
/// See `BlendedShape`. An answer is the whole of a dimension's score until the
/// record has something to say about it, hands over to the record across
/// twenty-eight days once it does, and stops counting sixty days after the
/// assessment for a dimension nothing was ever planned in.
struct Assessment: Equatable, Sendable {

    /// The key it is kept under, in the App Group like everything else.
    static let key = "forge.assessment.v1"

    /// Where every baseline is clamped. See the note on the type.
    static let range = 5...75

    /// The day the questions were answered: a civil day, labelled once when it
    /// is written, for the reason `ForgeDay` exists at all.
    let day: ForgeDay

    /// Each question, and the index of the option chosen. A question that was
    /// never answered — or whose stored answer this version cannot read — is
    /// simply absent, and its dimension falls back to the record alone.
    let answers: [Question: Int]

    init(day: ForgeDay, answers: [Question: Int]) {
        self.day = day
        // Only indices that exist. An out-of-range index is an answer nobody
        // could have given, and treating it as one would invent a number.
        self.answers = answers.filter { $0.key.options.indices.contains($0.value) }
    }

    // MARK: - The questions

    /// One tap each, and the order is the order they are asked in.
    ///
    /// Sleep is the odd one out: it does not set a dimension of its own, it
    /// moves Mental. Somebody who sleeps five hours is having a harder time
    /// staying steady than their screen time alone would say, and somebody who
    /// sleeps eight is having an easier one.
    enum Question: String, CaseIterable, Sendable {
        case training
        case planning
        case screenTime = "screen_time"
        case sleep
        case reading
        case friends
        case building

        /// The dimension this answer speaks for.
        var dimension: RitualCategory {
            switch self {
            case .training: .physical
            case .planning: .discipline
            case .screenTime, .sleep: .mental
            case .reading: .intellect
            case .friends: .relationship
            case .building: .ambition
            }
        }

        /// Whether the answer adjusts another question's baseline rather than
        /// setting one of its own.
        var isAdjustment: Bool { self == .sleep }

        var prompt: String {
            switch self {
            case .training: "How many days a week do you train?"
            case .planning: "How often does your day go the way you planned it?"
            case .screenTime: "How much screen time on a normal day?"
            case .sleep: "How much do you sleep?"
            case .reading: "When did you last finish a book?"
            case .friends: "When did you last spend real time with a friend, in person?"
            case .building: "How many hours a week go into what you're building: work, a craft, a side project?"
            }
        }

        /// The four answers, least first. `id` is what is stored — never the
        /// label, which is copy and may be reworded — and `value` is the
        /// baseline, or for sleep the adjustment to Mental.
        var options: [Option] {
            switch self {
            case .training: [
                Option(id: "none", label: "None", value: 10),
                Option(id: "one_two", label: "1–2", value: 30),
                Option(id: "three_four", label: "3–4", value: 55),
                Option(id: "five_plus", label: "5 or more", value: 75),
            ]
            case .planning: [
                Option(id: "rarely", label: "Rarely", value: 10),
                Option(id: "sometimes", label: "Sometimes", value: 30),
                Option(id: "mostly", label: "Mostly", value: 55),
                Option(id: "almost_always", label: "Almost always", value: 75),
            ]
            case .screenTime: [
                Option(id: "six_plus", label: "6 hours or more", value: 10),
                Option(id: "four_six", label: "4–6 hours", value: 25),
                Option(id: "two_four", label: "2–4 hours", value: 45),
                Option(id: "under_two", label: "Under 2 hours", value: 70),
            ]
            case .sleep: [
                Option(id: "under_six", label: "Under 6 hours", value: -10),
                Option(id: "six_seven", label: "6–7 hours", value: 0),
                Option(id: "seven_eight", label: "7–8 hours", value: 10),
                Option(id: "eight_plus", label: "8 hours or more", value: 5),
            ]
            case .reading: [
                Option(id: "cant_remember", label: "Can't remember", value: 10),
                Option(id: "this_year", label: "This year", value: 30),
                Option(id: "this_month", label: "This month", value: 55),
                Option(id: "reading_now", label: "Reading one now", value: 65),
            ]
            case .friends: [
                Option(id: "over_a_month", label: "Over a month ago", value: 10),
                Option(id: "this_month", label: "This month", value: 30),
                Option(id: "this_week", label: "This week", value: 55),
                Option(id: "most_days", label: "Most days", value: 70),
            ]
            case .building: [
                Option(id: "none_yet", label: "None yet", value: 10),
                Option(id: "one_three", label: "1–3 hours", value: 30),
                Option(id: "four_ten", label: "4–10 hours", value: 55),
                Option(id: "ten_plus", label: "10 hours or more", value: 75),
            ]
            }
        }

        /// The option a stored id names, or nil for one this version does not
        /// know — which lands as "unanswered" rather than as a guess.
        func index(of id: String) -> Int? {
            options.firstIndex { $0.id == id }
        }
    }

    struct Option: Equatable, Sendable {
        let id: String
        let label: String
        let value: Int
    }

    // MARK: - Baselines

    /// The value an answered question carries, or nil where it was not answered.
    func value(_ question: Question) -> Int? {
        answers[question].map { question.options[$0].value }
    }

    /// A dimension's starting number, or nil where the question that sets it
    /// was not answered.
    ///
    /// Sleep only ever adjusts: without a screen-time answer there is nothing
    /// for it to adjust, and a Mental baseline made of sleep alone would be a
    /// number about a different question.
    func baseline(for dimension: RitualCategory) -> Int? {
        guard let setter = Question.allCases.first(where: {
            $0.dimension == dimension && !$0.isAdjustment
        }), let start = value(setter) else { return nil }

        let adjustment = Question.allCases
            .filter { $0.dimension == dimension && $0.isAdjustment }
            .compactMap { value($0) }
            .reduce(0, +)
        return Self.clamped(start + adjustment)
    }

    static func clamped(_ value: Int) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }

    /// Every dimension with a baseline, in the app's own order.
    var baselines: [RitualCategory: Int] {
        RitualCategory.dimensions.reduce(into: [:]) { result, dimension in
            if let baseline = baseline(for: dimension) { result[dimension] = baseline }
        }
    }

    /// The dimensions, lowest baseline first. Ties keep the app's own order, so
    /// the answer is the same on every phone and every read. A dimension with
    /// no baseline sorts last: there is nothing to say it is low.
    var ranked: [RitualCategory] {
        let order = RitualCategory.dimensions
        return order.sorted { a, b in
            let lhs = baseline(for: a) ?? Int.max
            let rhs = baseline(for: b) ?? Int.max
            if lhs != rhs { return lhs < rhs }
            return (order.firstIndex(of: a) ?? 0) < (order.firstIndex(of: b) ?? 0)
        }
    }

    /// What the build beat preselects: the two lowest baselines. A suggestion,
    /// said as one ("Suggested from your answers"), and one tap to change.
    var suggestedFocus: [RitualCategory] {
        Array(ranked.filter { baseline(for: $0) != nil }.prefix(2))
    }

    /// Whether every question has an answer.
    var isComplete: Bool { answers.count == Question.allCases.count }

    // MARK: - The one line about time

    /// A gain, never a fear: what an hour of screen time is worth given back.
    ///
    /// Chosen by the screen-time answer and silent for anybody under two hours,
    /// because there is nothing honest to say to them about it. The arithmetic
    /// is the whole claim — two hours a day is 730 hours a year, a month of
    /// days — and it is never turned round into what the time is costing.
    var gainLine: String? {
        guard let index = answers[.screenTime] else { return nil }
        switch Question.screenTime.options[index].id {
        case "six_plus": return "Two hours a day back is a month a year."
        case "four_six": return "One hour a day back is fifteen days a year."
        case "two_four": return "Thirty minutes a day back is a week a year."
        default: return nil
        }
    }
}

// MARK: - Stored form

/// Written as `{"day": {...}, "answers": {"training": "three_four", ...}}`.
///
/// **Hand-written and tolerant** (§9). The day is the only required field —
/// without it the sixty-day rule cannot be placed in time, and an assessment
/// that cannot be placed is not one. Everything else degrades one answer at a
/// time: a key this version does not know is ignored, a value it does not
/// recognise is dropped, and a value of the wrong type is dropped, so one bad
/// answer never costs the other six.
extension Assessment: Codable {

    private enum CodingKeys: String, CodingKey {
        case day, answers
    }

    private struct AnswerKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let day = try container.decode(ForgeDay.self, forKey: .day)
        // A day no calendar holds cannot be placed in time either (§17.7).
        guard day.isPlausible else {
            throw DecodingError.dataCorruptedError(forKey: .day, in: container, debugDescription: "Not a day.")
        }

        var answers: [Question: Int] = [:]
        if let stored = try? container.nestedContainer(keyedBy: AnswerKey.self, forKey: .answers) {
            for key in stored.allKeys {
                guard let question = Question(rawValue: key.stringValue),
                      let id = try? stored.decode(String.self, forKey: key),
                      let index = question.index(of: id)
                else { continue }
                answers[question] = index
            }
        }
        self.init(day: day, answers: answers)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(day, forKey: .day)
        var stored = container.nestedContainer(keyedBy: AnswerKey.self, forKey: .answers)
        // In the order they are asked, so a diff of the defaults reads cleanly.
        for question in Question.allCases {
            guard let index = answers[question] else { continue }
            try stored.encode(question.options[index].id, forKey: AnswerKey(stringValue: question.rawValue))
        }
    }

    /// The stored assessment, or nil when there is none or it cannot be read.
    static func read(from defaults: UserDefaults) -> Assessment? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Assessment.self, from: data)
    }

    /// Write it, or remove it with nil.
    static func write(_ assessment: Assessment?, to defaults: UserDefaults) {
        guard let assessment else {
            defaults.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(assessment) else { return }
        defaults.set(data, forKey: key)
    }
}

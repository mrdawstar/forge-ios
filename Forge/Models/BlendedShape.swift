import Foundation

/// The six and OVR, as every screen shows them: the answers somebody gave,
/// handing over to what they actually do.
///
/// # Why there is a second shape at all
///
/// `ForgeShape` reads the record and nothing else, which is right and has one
/// cost: for the first weeks there is almost nothing to read, so the hexagon
/// could not be drawn until somebody had a week behind them — exactly the
/// weeks in which a new install decides whether this is worth keeping. The
/// assessment (`Assessment`) gives each dimension a starting number on day one,
/// and this is where the two meet. **Everything here is derived on read**; the
/// only stored input is the answers, and the record is still the only thing
/// that can move a number.
///
/// # The rules, per dimension
///
/// With `A` the day of the assessment and `F` the first day anything feeding
/// the dimension was planned:
///
/// - **Planned, within sixty days of `A`, fewer than twenty-eight days of
///   record since `F`:** `shown = w × reading + (1 − w) × baseline`, with
///   `w = days / 28`. The weight moves a day at a time, so the answer counts for
///   less each day and the record for more.
/// - **Never planned, and today within sixty days of `A`:** the baseline,
///   marked "from your answers".
/// - **Anything else:** exactly today's `ForgeShape` score — the presence floor
///   included, "—" when unmeasured. After twenty-eight days the record alone
///   speaks; sixty days after the assessment an untouched dimension stops being
///   carried by what somebody said about it two months ago.
/// - **No assessment at all** (every 1.0 install until they take it): exactly
///   `ForgeShape`, number for number. `BlendedShapeTests` holds the equality.
///
/// # Days, and today
///
/// `days` counts the finished days since `F`, plus today once something in the
/// dimension has been kept today — the same rule `ForgeShape.read` follows, and
/// for the same reason: a day in progress is never a miss. So the morning never
/// lowers a number and the first thing kept each day raises it.
///
/// # Why the record's half has a scaled presence floor
///
/// The reading weighed against the baseline is `ForgeShape`'s own arithmetic
/// over the days since `F`, with the presence floor scaled to the part of the
/// window that has passed (`8 × days / 28`). For anybody planning a dimension
/// at least twice a week that scaling changes nothing — the reading is simply
/// `100 × kept / asked` — and it does two things nothing else here could:
///
/// - **The hand-over is continuous.** At twenty-eight days the scaled floor is
///   the real one and the days since `F` are the real window, so the blend's
///   last value and `ForgeShape`'s first are the same number.
/// - **Planning one thing once cannot climb.** Without it, one kept day followed
///   by silence would read as a flawless record for four weeks and walk the
///   score towards a hundred on nothing — the exact exploit `presenceFloor`
///   exists to refuse, reopened by the weight.
struct BlendedShape: Equatable, Sendable {

    /// How long after the assessment an answer can still carry a dimension
    /// nothing has been planned in.
    static let answersLast = 60
    /// Days of record over which the answers hand over to it. The Shape's own
    /// window, so the hand-over ends exactly where the record is a full reading.
    static let blendDays = ForgeShape.window

    /// Where a dimension's number is coming from.
    enum Source: Equatable, Sendable {
        /// The answers alone: nothing here has been kept yet.
        case answers
        /// The answers and the record, `days` of the twenty-eight in.
        case blend(days: Int)
        /// The record alone — `ForgeShape`, exactly.
        case record
    }

    struct Dimension: Identifiable, Equatable, Sendable {
        /// What the record alone says. Always present, and exactly what
        /// `ForgeShape` would show.
        let record: ForgeShape.Dimension
        /// The starting number from the answers, where there is one.
        let baseline: Int?
        let source: Source
        /// The number every screen shows. Meaningful only where `hasScore`.
        let score: Int
        let direction: ForgeShape.Direction

        var category: RitualCategory { record.category }
        var id: String { record.id }

        /// Whether there is a number to show rather than a dash.
        var hasScore: Bool {
            switch source {
            case .answers, .blend: true
            case .record: record.isMeasured
            }
        }

        /// 0…1, for drawing. Nought for a dash.
        var fraction: Double { hasScore ? Double(score) / 100 : 0 }

        /// What the number is made of, in the fewest words that are true.
        var isFromAnswers: Bool { source == .answers }

        /// How much of the number the answers still carry, 0…1.
        var answersWeight: Double {
            switch source {
            case .answers: 1
            case .blend(let days): 1 - Double(days) / Double(BlendedShape.blendDays)
            case .record: 0
            }
        }
    }

    /// All six, always, in `RitualCategory.dimensions` order.
    let dimensions: [Dimension]
    /// The record's own reading, for everything that is about the record.
    let record: ForgeShape
    /// Whether any of this comes from answers.
    let hasAssessment: Bool

    /// OVR: the mean of the six numbers shown, a dash counting as nought —
    /// the same rule `ForgeShape.overall` has always had, for the same reason.
    var overall: Int {
        guard !dimensions.isEmpty else { return 0 }
        let total = dimensions.reduce(0) { $0 + ($1.hasScore ? $1.score : 0) }
        return Int((Double(total) / Double(dimensions.count)).rounded())
    }

    /// The word under the number. With no assessment it is the record's,
    /// exactly; otherwise it is read the same way over the six shown here —
    /// **counting only dimensions that have a direction yet.**
    ///
    /// That last part is the difference from `ForgeShape.state`, and it
    /// matters on the day an assessment is taken: two dimensions just started
    /// have a number and no direction, and counting them made the hexagon say
    /// "Steady" on somebody's first afternoon. Nothing about a first afternoon
    /// is steady; it is early, and the word says so until a week of record
    /// gives two dimensions a direction.
    var state: ForgeShape.Direction {
        guard hasAssessment else { return record.state }
        let directed = dimensions.filter {
            switch $0.source {
            case .answers: false
            case .blend: $0.direction != .unknown
            case .record: $0.record.isMeasured && $0.direction != .unknown
            }
        }
        guard directed.count >= 2 else { return .unknown }
        let rising = directed.count { $0.direction == .rising }
        let slipping = directed.count { $0.direction == .slipping }
        if rising > slipping { return .rising }
        if slipping > rising { return .slipping }
        return .steady
    }

    /// Whether the hexagon can be drawn. From day one when there are answers
    /// — that is what they are for — and otherwise the record's own rule.
    var isReadable: Bool { hasAssessment || record.isReadable }

    /// The one dimension to look at next, by `ForgeShape.needsAttention`'s rules
    /// — **among dimensions the record alone is speaking for.** Its sentence is
    /// "has had the least of you", which is a claim about days kept; a number
    /// still partly made of answers cannot support it, and naming a dimension
    /// by its record score while the hexagon above shows a blend would put two
    /// readings of one side on one screen. With no assessment this is
    /// `ForgeShape.needsAttention`, exactly.
    var needsAttention: ForgeShape.Dimension? {
        let candidates = dimensions
            .filter { $0.source == .record && $0.record.hasActivities && $0.record.isMeasured }
            .map(\.record)
        guard candidates.count > 1,
              let weakest = candidates.min(by: { $0.score < $1.score }),
              let best = candidates.max(by: { $0.score < $1.score }),
              best.score - weakest.score >= 15
        else { return nil }
        return weakest
    }

    func dimension(_ category: RitualCategory) -> Dimension? {
        dimensions.first { $0.category == category }
    }

    // MARK: - Reading it

    /// The six, read on `today` from a record, the activities somebody keeps
    /// now (for the same weights `ForgeShape` uses), and the answers if any.
    ///
    /// Pure: the live Becoming tab and the onboarding's projections call the
    /// same function, one over the real record and one over days that have not
    /// happened yet.
    ///
    /// `challenges` is each day's finished daily challenge, which counts as a
    /// kept day for its dimension here exactly as it does in `ForgeShape` — so
    /// it is written into the days once, at the top, and both halves of the
    /// blend read the same credited record. See `ForgeShape.crediting`.
    static func read(
        _ byDay: [ForgeDay: DayRecord],
        today: ForgeDay,
        activities: [Ritual],
        assessment: Assessment?,
        challenges: [ForgeDay: RitualCategory] = [:]
    ) -> BlendedShape {
        let byDay = ForgeShape.crediting(byDay, challenges: challenges)
        let shape = ForgeShape.read(byDay, today: today, activities: activities)

        guard let assessment else {
            return BlendedShape(
                dimensions: shape.dimensions.map {
                    Dimension(record: $0, baseline: nil, source: .record,
                              score: $0.score, direction: $0.direction)
                },
                record: shape,
                hasAssessment: false
            )
        }

        let everything = ForgeShape.allWeights(of: activities)
        let expiry = assessment.day.adding(days: answersLast)
        let todays = byDay[today]

        let dimensions = shape.dimensions.map { recorded -> Dimension in
            let fromRecord = Dimension(
                record: recorded, baseline: nil, source: .record,
                score: recorded.score, direction: recorded.direction
            )
            // A question left unanswered gives this dimension nothing to start
            // from, so the record speaks for it from the first day.
            guard let baseline = assessment.baseline(for: recorded.category) else {
                return fromRecord
            }
            let fromAnswers = Dimension(
                record: recorded, baseline: baseline, source: .answers,
                score: baseline, direction: .unknown
            )

            let weights = ForgeShape.weights(everything, for: recorded.category)
            guard let first = ForgeShape.firstPlanned(byDay, weights, through: today) else {
                // Never planned: the answers carry it for sixty days.
                return today <= expiry ? fromAnswers : fromRecord
            }
            // Taken up more than sixty days after the assessment: the answers
            // are about somebody two months ago, and the record starts clean.
            guard first <= expiry else { return fromRecord }

            let settled = ForgeShape.settledToday(weights, in: todays)
            let days = max(0, today.days(since: first)) + (settled > 0 ? 1 : 0)
            guard days < blendDays else { return fromRecord }
            // Planned today and nothing kept yet: nothing has happened, so the
            // answers are still the whole of it.
            guard days > 0 else { return fromAnswers }

            let yesterday = today.adding(days: -1)
            let asked = ForgeShape.creditedDays(byDay, weights, from: first, to: yesterday, planned: true) + settled
            let kept = ForgeShape.creditedDays(byDay, weights, from: first, to: yesterday, planned: false) + settled
            let scaledFloor = Double(ForgeShape.presenceFloor) * Double(days) / Double(blendDays)
            let reading = ForgeShape.reading(kept: kept, asked: asked, floor: scaledFloor)

            let weight = Double(days) / Double(blendDays)
            let shown = Int((weight * reading + (1 - weight) * Double(baseline)).rounded())

            return Dimension(
                record: recorded, baseline: baseline, source: .blend(days: days),
                score: shown,
                direction: blendDirection(shown: shown, baseline: baseline, days: days)
            )
        }

        return BlendedShape(dimensions: dimensions, record: shape, hasAssessment: true)
    }

    /// Which way a blended dimension has moved: against where the answers put
    /// it, with the Shape's own eight points of noise, and only once there is a
    /// week of record behind it. A day or two of anything is not a direction,
    /// and "steady" on somebody's second morning would be a claim about a week
    /// that has not happened.
    static func blendDirection(shown: Int, baseline: Int, days: Int) -> ForgeShape.Direction {
        guard days >= FirstWeek.length else { return .unknown }
        if shown - baseline > ForgeShape.noise { return .rising }
        if baseline - shown > ForgeShape.noise { return .slipping }
        return .steady
    }
}

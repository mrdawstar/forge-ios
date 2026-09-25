import SwiftUI

/// The one progression.
///
/// # Why there is only one now
///
/// Forge shipped three systems counting the same number. Seven blades at
/// 0/1/3/7/14/30/60 days kept, five milestones at 1/7/30/100/365 days kept, and
/// both drawn on the same screen — so "Folded Sword · 7 days" sat two hundred
/// points above "Seven days · A week of this", the same event told twice in two
/// registers, each diluting the other. Two ladders against one number is not
/// twice the progression; it is the same progression with a second opinion about
/// what it means.
///
/// Worse, the visible one ran out. The blades stopped at sixty days, which is
/// roughly where somebody stops being a person trying this and starts being a
/// person who does it — the exact point at which the app had nothing further to
/// say.
///
/// So: one ladder, read out of days kept, that never terminates.
///
/// # The metaphor, said out loud
///
/// **The blade is the person you are becoming, and the day is what you strike it
/// with.** The first run has said this since the six-beat rebuild and nothing
/// else in the app ever picked it up. Say it, and the shape of the ladder falls
/// out on its own: for the first sixty days the blade is being *made*, and what
/// advances is which blade you carry — seven objects, seven pieces of art, an
/// actual choice at the end of it. After that the blade exists, and what advances
/// is what the work has done to it. A temper. A patina. An edge that has been
/// kept rather than ground new.
///
/// That second half costs no art, which is the point: `BladeState` is a grade
/// applied to the sprite already on screen, so the ladder can run to a thousand
/// days on seven images. It is also honest in a way a new sprite would not be —
/// the person at day five hundred is not carrying a different blade, they are
/// carrying the same one, older.
///
/// # What this is not
///
/// Not a score, and nothing here is collectible. The doctrine at the top of
/// `Milestone` is unchanged and this file inherits every word of it: a rung is a
/// sentence about who somebody has become, and the only thing it needs in order
/// to be worth reading is being true. Nothing is paid out for reaching one,
/// nothing is lost by not, and **no figure on this ladder can go down** — days
/// kept is cumulative by construction, so a bad week costs a person nothing they
/// had already been told they were.
enum Ladder {

    /// Every rung, in order, far enough out that nobody reaches the end.
    ///
    /// The first seven are the blades at exactly the thresholds they have always
    /// had — an existing install's collection is untouched by this file, and
    /// somebody who has earned the seventh blade still has it. Everything past sixty
    /// days is new ground the old ladder simply did not cover.
    ///
    /// Ids are **the shipped milestone ids where the two ladders coincided**:
    /// `one`, `seven`, `thirty`, `hundred`, `year`. That is not tidiness, it is
    /// the migration: an install that had reached "Thirty days" keeps it under
    /// the same id when the two ladders became one.
    static let rungs: [LadderRung] = [
        LadderRung(id: "start", threshold: 0, name: "Rough Sword",
                   note: "Unworked steel. Nothing has been asked of it yet.", mark: .blade(1)),
        LadderRung(id: "one", threshold: 1, name: "Struck Sword",
                   note: "One day behind it, and the first mark anything leaves.", mark: .blade(2)),
        LadderRung(id: "three", threshold: 3, name: "Shaped Sword",
                   note: "Three days. It has started to hold a form.", mark: .blade(3)),
        LadderRung(id: "seven", threshold: 7, name: "Folded Sword",
                   note: "A week folded into it. What repeats is what holds.", mark: .blade(4)),
        LadderRung(id: "fourteen", threshold: 14, name: "Quenched Sword",
                   note: "A fortnight. Hard enough now to take an edge.", mark: .blade(5)),
        LadderRung(id: "thirty", threshold: 30, name: "Edged Sword",
                   note: "Thirty days. It cuts because you kept turning up.", mark: .blade(6)),
        LadderRung(id: "sixty", threshold: 60, name: "Proven Sword",
                   note: "Sixty days. Long enough that it is no longer being tested.", mark: .blade(7)),
        // Past here the blade stops changing and starts ageing.
        LadderRung(id: "hundred", threshold: 100, name: "Tempered",
                   note: "Colour in the steel. It has been held in the fire long enough to change.",
                   mark: .state(.tempered)),
        LadderRung(id: "oneeighty", threshold: 180, name: "Patina",
                   note: "Half a year on the same blade. It has stopped looking new.",
                   mark: .state(.patina)),
        LadderRung(id: "year", threshold: 365, name: "Honed",
                   note: "A year. The edge is one that has been kept, not one that arrived.",
                   mark: .state(.honed)),
        LadderRung(id: "fivehundred", threshold: 500, name: "Weathered",
                   note: "Marks that came from use. None of them are damage.",
                   mark: .state(.weathered)),
        LadderRung(id: "twoyears", threshold: 730, name: "Burnished",
                   note: "Two years. Worn bright in the places you hold it.",
                   mark: .state(.burnished)),
        LadderRung(id: "thousand", threshold: 1000, name: "Old iron",
                   note: "A thousand days. Nobody asks about it any more, including you.",
                   mark: .state(.old)),
    ]

    /// The last fixed rung. Past this the ladder generates itself — see
    /// `rung(after:)`.
    private static let lastFixed = 1000
    /// Roughly a year, in days, for the generated rungs. Not a calendar year:
    /// this ladder counts days somebody kept, and a leap day is not one of them.
    private static let yearStep = 365

    // MARK: - Reading it

    /// The rung somebody is standing on, given what they have kept.
    ///
    /// Never nil: the first rung is at zero, so an install on its first morning
    /// is already on the ladder rather than beneath it. Nothing in Forge is
    /// approached from outside.
    static func current(daysKept: Int) -> LadderRung {
        reached(daysKept: daysKept).last ?? rungs[0]
    }

    /// Everything reached, oldest first.
    static func reached(daysKept: Int) -> [LadderRung] {
        var found = rungs.filter { daysKept >= $0.threshold }
        // Past the fixed table, fill in every generated rung that has also been
        // reached, so a four-year practice has four years of ladder behind it
        // rather than a table that stops and a person who fell off the end.
        var cursor = lastFixed
        while true {
            guard let next = generated(after: cursor), daysKept >= next.threshold else { break }
            found.append(next)
            cursor = next.threshold
        }
        return found
    }

    /// The next rung up, or nil for nobody — this ladder does not end.
    ///
    /// Deliberately still an `Optional` return. The one caller that could be
    /// handed nil is a hypothetical practice past the arithmetic limit of `Int`,
    /// and a view that has to handle "nothing left to reach" is a view that
    /// handles the end of the seven blades correctly for free.
    static func rung(after daysKept: Int) -> LadderRung? {
        if let fixed = rungs.first(where: { $0.threshold > daysKept }) { return fixed }
        return generated(after: max(daysKept, lastFixed))
    }

    /// How far along the space between two rungs somebody is, 0…1.
    ///
    /// Measured from the rung behind rather than from zero, so the ring fills
    /// across each gap instead of crawling — at nine hundred days a bar measured
    /// from zero is visually indistinguishable from the same bar tomorrow, and a
    /// progress indicator that never appears to move is worse than none.
    static func progress(daysKept: Int) -> Double {
        guard let next = rung(after: daysKept) else { return 1 }
        let behind = current(daysKept: daysKept).threshold
        let span = next.threshold - behind
        guard span > 0 else { return 1 }
        return min(1, max(0, Double(daysKept - behind) / Double(span)))
    }

    /// What the blade looks like at this point in a practice.
    ///
    /// Derived on every read, never stored. A stored state is a state that can
    /// disagree with the history that produced it, which is the one bug class
    /// this codebase designs itself out of everywhere else.
    static func state(daysKept: Int) -> BladeState {
        reached(daysKept: daysKept).compactMap(\.mark.state).last ?? .raw
    }

    /// Which of the seven blades this many days has earned — the same answer
    /// `SwordStore` gives, expressed on the ladder.
    static func bladeID(daysKept: Int) -> Int {
        reached(daysKept: daysKept).compactMap(\.mark.bladeID).last ?? 1
    }

    /// The generated rung after a given threshold: one a year, forever.
    ///
    /// Only reached past `lastFixed`, so the hand-written table stays the thing
    /// that decides everything anybody will actually see for their first three
    /// years. What is generated has no state of its own — the blade has finished
    /// changing by then, and inventing a tenth patina to mark year six would be
    /// the ladder padding itself.
    private static func generated(after threshold: Int) -> LadderRung? {
        let next = max(threshold, lastFixed) / yearStep * yearStep + yearStep
        let years = next / yearStep
        guard years >= 3 else { return nil }
        return LadderRung(
            id: "years.\(years)",
            threshold: next,
            name: "\(ForgeCount.spelled(years)) years",
            note: "Still here.",
            mark: .state(.old)
        )
    }
}

// MARK: - A rung

/// One marker on the single ladder.
///
/// Carries no progress of its own. Whether it is reached is arithmetic against
/// `ProgressStore.daysKept` performed at the point of asking — see
/// `LadderRung.isReached(daysKept:)` — for the same reason a `Milestone` never
/// stored its own count.
struct LadderRung: Identifiable, Equatable, Sendable {
    let id: String
    /// Days kept to stand here.
    let threshold: Int
    /// What it is called. A blade's own name, or the state of one.
    let name: String
    /// One sentence about the object, never about the person. No rung
    /// congratulates anybody: "Sixty days behind you" is a fact, and "Amazing
    /// work!" is an app with an opinion about somebody's life.
    let note: String
    let mark: LadderMark

    func isReached(daysKept: Int) -> Bool { daysKept >= threshold }

    /// "Sixty days", "One day" — the threshold as a person would say it.
    var thresholdLabel: String {
        switch threshold {
        case 0: "From the start"
        case 1: "One day"
        default: "\(ForgeCount.spelled(threshold)) days"
        }
    }

    func renamed(to name: String, note: String) -> LadderRung {
        LadderRung(id: id, threshold: threshold, name: name, note: note, mark: mark)
    }
}

/// What a rung actually changes about the blade.
///
/// Two cases and there will never be a third: either you are handed a new blade,
/// or the one you have is further along. Anything else somebody might want to
/// hang here — a title, a badge, a colour to unlock — is a collectible, and this
/// ladder does not have those.
enum LadderMark: Equatable, Sendable {
    /// One of the seven, by `Sword.id`.
    case blade(Int)
    /// The blade you are already carrying, matured.
    case state(BladeState)

    var bladeID: Int? {
        if case .blade(let id) = self { return id }
        return nil
    }

    var state: BladeState? {
        if case .state(let state) = self { return state }
        return nil
    }
}

// MARK: - The blade, older

/// What time and use have done to the blade.
///
/// **A closed set, deliberately, and a grade rather than an asset.** Each case is
/// a handful of numbers applied to the sprite already in the collection, so the
/// ladder runs past a thousand days without a single new image — and because it
/// is the *same* image being graded, it reads as one object ageing rather than
/// as a seventh, eighth and ninth sword nobody drew.
///
/// `bespokeAsset` is the hook for the day somebody does draw them. A state that
/// names an asset uses it; every state that does not falls back to grading the
/// blade, which is what all of them do today. That is the same escape the
/// scene's own plate system uses, and it exists for the same reason:
/// the feature has to ship before the art does, and it must not have to be
/// rewritten when the art arrives.
///
/// Raw values are written to nothing. State is derived from days kept on every
/// read — see `Ladder.state(daysKept:)` — so there is no stored value to
/// migrate and no way for a blade to be in a state the history does not support.
/// The `String` raw value exists for tests and for a future sync field, and is
/// tolerant on the way in for the reason every enum in this codebase is.
enum BladeState: String, CaseIterable, Codable, Equatable, Sendable {
    /// The blade as it is handed over. Everything below sixty days.
    case raw
    case tempered
    case patina
    case honed
    case weathered
    case burnished
    case old

    /// The word for it, where anything is said at all.
    var label: String? {
        switch self {
        case .raw: nil
        case .tempered: "Tempered"
        case .patina: "Patina"
        case .honed: "Honed"
        case .weathered: "Weathered"
        case .burnished: "Burnished"
        case .old: "Old iron"
        }
    }

    /// Bespoke art, when there is any. Nil everywhere today.
    var bespokeAsset: String? { nil }

    /// How the sprite is graded to look this old.
    ///
    /// Small numbers on purpose. The blade has to stay recognisably the blade
    /// somebody chose — a state that recoloured it would be a different sword
    /// wearing its name, and the collection would then disagree with the stone.
    /// The progression across the six is deliberate rather than arbitrary: heat
    /// first, then colour draining out of it, then contrast coming back as an
    /// edge, then the whole thing settling darker and warmer as it stops being
    /// new. Read down the list and it is a blade getting older.
    var grade: BladeGrade {
        switch self {
        case .raw: BladeGrade()
        case .tempered: BladeGrade(saturation: 1.06, contrast: 1.04, brightness: 0.01,
                                   tint: Color(red: 1.0, green: 0.72, blue: 0.42), tintOpacity: 0.10)
        case .patina: BladeGrade(saturation: 0.86, contrast: 1.02, brightness: -0.02,
                                 tint: Color(red: 0.62, green: 0.80, blue: 0.74), tintOpacity: 0.12)
        case .honed: BladeGrade(saturation: 0.92, contrast: 1.12, brightness: 0.03,
                                tint: Color(red: 0.86, green: 0.93, blue: 1.0), tintOpacity: 0.10)
        case .weathered: BladeGrade(saturation: 0.80, contrast: 1.08, brightness: -0.04,
                                    tint: Color(red: 0.72, green: 0.68, blue: 0.60), tintOpacity: 0.14)
        case .burnished: BladeGrade(saturation: 0.88, contrast: 1.14, brightness: 0.04,
                                    tint: Color(red: 1.0, green: 0.88, blue: 0.66), tintOpacity: 0.14)
        case .old: BladeGrade(saturation: 0.74, contrast: 1.10, brightness: -0.03,
                              tint: Color(red: 0.80, green: 0.74, blue: 0.62), tintOpacity: 0.16)
        }
    }

    /// Unknown states land on `raw`, which is the blade as it ships. Being wrong
    /// here costs a tint and never a fact.
    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = BladeState(rawValue: raw) ?? .raw
    }
}

/// The numbers a state applies to a blade sprite.
///
/// Absolute values with Forge's own spelled out as the default, exactly like
/// `PathSubjectGrade`: a grade expressed as "a bit warmer than usual" needs the
/// usual to be found before it can be drawn, and two callers will find different
/// usuals.
struct BladeGrade: Equatable, Sendable {
    var saturation: Double = 1
    var contrast: Double = 1
    var brightness: Double = 0
    /// Multiplied over the sprite, so it can age the metal without lifting it.
    var tint: Color?
    var tintOpacity: Double = 0

    var isIdentity: Bool { self == BladeGrade() }
}

// MARK: - Drawing one

extension View {
    /// Age a blade sprite by the state it is in.
    ///
    /// One modifier so the stone scene, the collection card and the Blade tab's
    /// portrait cannot end up showing the same blade at three different ages.
    @ViewBuilder
    func bladeState(_ state: BladeState) -> some View {
        let grade = state.grade
        if grade.isIdentity {
            self
        } else {
            saturation(grade.saturation)
                .contrast(grade.contrast)
                .brightness(grade.brightness)
                .overlay {
                    if let tint = grade.tint {
                        tint.opacity(grade.tintOpacity).blendMode(.overlay)
                    }
                }
                // Clipped to the sprite rather than to its box, or the overlay
                // paints the transparent margin around the blade as well and the
                // whole thing reads as a tinted rectangle.
                .mask { self }
        }
    }
}

import SwiftUI

/// The eight accents, in the one file both the app and the widgets compile.
///
/// # Why the palette lives here
///
/// Because a widget is not allowed to look like a different app from the one it
/// belongs to. The accent is the only thing about Forge's interface that is a
/// taste — see `ForgeAppearance` — and until this existed the widgets could not
/// see it: the extension compiles `Shared/` and `ForgeDay` and nothing else, so
/// `ForgeThemeAccent` was out of reach and every widget was drawn in the system
/// tint whatever the person had chosen.
///
/// So the raw values and the colours are here, in a file both targets already
/// build, and `ForgeThemeAccent.color` reads them. One table, and a phone whose
/// app is set to Moss has widgets in Moss.
///
/// **The snapshot carries the choice**, not the widget: `ForgeSnapshot.accent`
/// is written by the app alongside everything else it publishes, which keeps the
/// one-direction rule this whole boundary is built on — the app writes, the
/// widgets read.
///
/// A raw value nobody recognises resolves to `forge`, like every other tolerant
/// read in this app. A widget drawn in the wrong blue is a cosmetic surprise; a
/// widget that fails to draw is a black rectangle on somebody's Lock Screen.
///
/// > This file was `BladeMark.swift`, and held a vector drawing of a sword in a
/// > stone that every widget put at the top of itself. It was withdrawn — see
/// > `HomeWidgets` for what replaced it — and what is left is what the name says:
/// > the colour vocabulary two targets have to agree on.
enum ForgeAccentPalette {
    static let fallback = "forge"

    static func color(_ raw: String) -> Color {
        switch raw {
        case "ember": Color(red: 1.00, green: 0.48, blue: 0.21)
        case "gold": Color(red: 0.96, green: 0.76, blue: 0.28)
        case "moss": Color(red: 0.44, green: 0.78, blue: 0.48)
        case "tide": Color(red: 0.26, green: 0.80, blue: 0.83)
        case "violet": Color(red: 0.66, green: 0.55, blue: 1.00)
        case "rose": Color(red: 1.00, green: 0.51, blue: 0.58)
        case "bone": cream
        default: Color(red: 0.20, green: 0.55, blue: 1.00)
        }
    }

    /// The warm off-white Forge sets its primary buttons and its one achromatic
    /// accent in. Defined here rather than in `ForgeTheme` because the widget
    /// target cannot see that file — and `ForgeTheme.cream` reads *this* one, so
    /// there is still exactly one definition in the process.
    static let cream = Color(red: 0.949, green: 0.933, blue: 0.902)

    /// The room, as far as a widget needs it: near-black, warm rather than blue.
    /// Forge is a dark app and says so at the root (`preferredColorScheme(.dark)`),
    /// so a widget that took the system's light ground would be the one surface
    /// of the product that is not the same product.
    static let ground = Color(red: 0.055, green: 0.052, blue: 0.062)
    static let groundLift = Color(red: 0.105, green: 0.100, blue: 0.115)
}

/// How full one square of a progress grid is.
///
/// Five steps rather than a continuous ramp, and that is the whole trick a
/// contribution graph turns. A smooth gradient over a fraction gives every
/// square its own slightly different shade, which is more information and less
/// meaning: nobody can tell 0.62 from 0.68 at thirteen points across, and trying
/// makes the grid read as noise. Buckets give the eye something to group.
///
/// # Why it is in `Shared/`
///
/// Because the large widget draws the same grid the Blade tab does, and two
/// implementations of "how full is this square" would eventually disagree by a
/// step — on the one surface where the two are side by side on the same screen.
/// The **app** does the bucketing (`ProgressStore.heatTrail`) and writes the
/// levels into the snapshot; the widget only draws them. Same direction as
/// everything else across this boundary.
///
/// `HeatLevel` in the app is an alias for this, so nothing on the Blade tab had
/// to change and the analytics tests still name it.
enum ForgeHeatLevel: Int, CaseIterable, Equatable, Sendable {
    /// A day that happened and was not kept.
    case none = 0
    case light = 1
    case some = 2
    case most = 3
    /// Everything the day asked for.
    case full = 4
    /// A day a banked rest covered. Filled, so it is plainly accounted for, and
    /// deliberately colourless — rest is not a small achievement, it is a
    /// different kind of day, and shading it with the accent would put it on the
    /// same scale as the work.
    case rest = 5

    static func of(_ value: Double, isRest: Bool) -> ForgeHeatLevel {
        // Rest only wins where nothing was earned. Somebody who rested and then
        // did the day anyway did the day, and the grid should say so.
        if isRest && value <= 0 { return .rest }
        return switch value {
        case ..<0.001: .none
        case ..<0.34: .light
        case ..<0.67: .some
        case ..<0.999: .most
        default: .full
        }
    }

    /// How much of the accent is in the square. Zero for the two steps that are
    /// not on the ramp at all — see `neutral`.
    var accentOpacity: Double {
        switch self {
        case .none, .rest: 0
        case .light: 0.28
        case .some: 0.52
        case .most: 0.76
        case .full: 1
        }
    }

    /// What a step that is not on the accent ramp is drawn in, as a fraction of
    /// the foreground colour.
    var neutralOpacity: Double {
        switch self {
        case .none: 0.07
        case .rest: 0.20
        default: 0
        }
    }

    /// The square, in whichever accent the caller is drawn in.
    ///
    /// Both targets fill from here, which is the point of the file: the grid on
    /// the Blade tab and the grid on a Home Screen are the same five shades.
    func style(accent: Color) -> AnyShapeStyle {
        accentOpacity > 0
            ? AnyShapeStyle(accent.opacity(accentOpacity))
            : AnyShapeStyle(Color.primary.opacity(neutralOpacity))
    }

    /// What the four filled steps are, for the legend. Rest is not on the ramp
    /// and has no place on a scale that runs from less to more.
    static var ramp: [ForgeHeatLevel] { [.none, .light, .some, .most, .full] }

    var spoken: String {
        switch self {
        case .none: "nothing"
        case .light, .some, .most: "part of the day"
        case .full: "the whole day"
        case .rest: "a rest day"
        }
    }

}

/// One day, as a progress grid needs it: how full it was, and whether it was
/// kept.
///
/// # Why both
///
/// Because they are not the same fact and the grid says both. A square is
/// **full** when the day's list was finished; a day is **kept** when the blade
/// came out of the stone, which is a separate deliberate act — the first pull is
/// granted with the list unfinished, and a finished list nobody pulled is not a
/// day kept. The colour is the first fact and every count under the grid is the
/// second, and treating one as the other would put a number under a picture that
/// disagrees with it.
///
/// Carried across the boundary as one `Int` per day, because a trail of a
/// hundred and eighty-two of these goes into a `UserDefaults` value that is read
/// on every widget refresh. `keptBit` is a flag on top of the level rather than
/// a pair of arrays: two arrays can arrive at different lengths, and then
/// somebody's Tuesday is coloured from one day and counted from another.
struct ForgeHeatMark: Equatable, Sendable {
    var level: ForgeHeatLevel
    var wasKept: Bool

    /// Set above every `ForgeHeatLevel` raw value, with room left over.
    private static let keptBit = 8

    /// A day earlier than anything this person has.
    ///
    /// Deliberately *not* a level. A grid that drew the eleven weeks before
    /// somebody installed Forge as `none` would be telling them they did nothing
    /// on days the app was not there for, which is the one kind of lie the whole
    /// derived-state rule exists to prevent. It is written as this, read back as
    /// `nil`, and drawn as an empty slot — so the grid reads as starting where
    /// the practice did.
    static let beforeRecord = -1

    var raw: Int { level.rawValue + (wasKept ? Self.keptBit : 0) }

    /// **Failable, and `beforeRecord` is why.** That value is a legal thing to
    /// find on the wire and is not a mark: it says this day is earlier than
    /// anything the person has, and the caller has to be able to tell that from
    /// a day they did nothing on. Returning a `.none` mark for it would put the
    /// lie back that the constant exists to prevent.
    ///
    /// Otherwise tolerant, like every other decoder in this app: anything
    /// unrecognised reads as a day that happened and was not kept, which is the
    /// reading that claims least.
    init?(raw: Int) {
        guard raw >= 0 else { return nil }
        wasKept = raw >= Self.keptBit
        level = ForgeHeatLevel(rawValue: raw % Self.keptBit) ?? .none
    }

    init(level: ForgeHeatLevel, wasKept: Bool) {
        self.level = level
        self.wasKept = wasKept
    }
}

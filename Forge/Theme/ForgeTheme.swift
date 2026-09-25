import SwiftUI

/// The measurements the whole app agrees on.
///
/// Everything in here exists because it was being decided twice. Before this
/// file grew a `Space` and a `Radius` there were eleven corner radii in the app
/// and nineteen padding values, all of them arrived at by eye, one screen at a
/// time — and the result is the thing people mean when they say an app feels
/// glued together. They cannot say which number is wrong, because none of them
/// is; what they can see is that no two panels agree about what a margin is.
///
/// So the rule is: a view may pick a token, and a view may not pick a number.
/// Where a number really is particular to one screen — the sword scene's
/// measured plate offsets, a sheet detent worked out from row heights — it stays
/// where it is measured and says why. Everything else comes from here.
enum ForgeTheme {

    // MARK: - Colours
    //
    // Surfaces are not hand-mixed translucent whites — Liquid Glass supplies
    // them. What remains is the brand palette plus semantic aliases, so text
    // tracks the system instead of fixed opacities.

    static let bg = Color.black
    /// Read from `ForgeAccentPalette`, which is in `Shared/` and therefore the
    /// one copy both the app and the widget extension compile. See that file:
    /// the widgets could not see this one, so a phone set to Moss had blue
    /// widgets.
    static let cream = ForgeAccentPalette.cream

    /// The one tint the app is drawn in, and what every native control picks up.
    ///
    /// **Blue, deliberately, and the comment that used to be here was wrong.**
    ///
    /// It argued for an ember taken off the same fire as the scene, on the
    /// grounds that a warm room should not carry a cold accent. The asset was
    /// changed back to blue afterwards and this text was not, so the file spent
    /// a while confidently describing a colour the app does not use.
    ///
    /// Blue is the right answer, and the argument the old comment missed is that
    /// the accent is not scenery. Every warm thing on screen is *the room* — the
    /// plate, the stone, the blade, the light. An accent that joins them has
    /// nothing left to distinguish it, and the one job of an accent is to say
    /// "this is the interface, and this part of it responds to you". Cool
    /// against that warmth is what makes a chosen row read as chosen rather than
    /// as another lit surface, and it is why every selection state in the app
    /// now takes this and nothing else.
    ///
    /// Read from the asset catalog so the light and dark variants live in one
    /// place. `ForgeAccent` is a separate, closed set and is only ever used to
    /// colour an identity's own mark — never a control.
    ///
    /// **It is now the one the user picked**, and it is a `var` on purpose. See
    /// `ForgeAppearance`: the blue above is still the default and still the
    /// argument, but it is a default rather than a law, and the seventy-nine
    /// call sites reading this get the change for free because every one of them
    /// reads it from inside a view body.
    static var accent: Color { ForgeAppearance.shared.accent.color }

    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color.secondary.opacity(0.6)
    static let textMuted = Color.secondary
    static let separator = Color.primary.opacity(0.10)
    static let destructive = Color.red

    // MARK: - Space
    //
    // One scale, in the order things nest. A view that needs "a bit more than
    // `row`" wants `section`; a view that needs a number between them wants a
    // different layout.

    enum Space {
        /// Between a glyph and the word it belongs to.
        static let hair: CGFloat = 4
        /// Between two lines of the same thought.
        static let tight: CGFloat = 8
        /// Inside a control, and between the parts of one row.
        static let inner: CGFloat = 12
        /// Between rows.
        static let row: CGFloat = 16
        /// The page margin. Every full-width screen in the app starts here.
        static let gutter: CGFloat = 20
        /// Between a heading and what it heads.
        static let section: CGFloat = 28
        /// Between two things that are not about each other.
        static let chapter: CGFloat = 40
    }

    // MARK: - Radius
    //
    // Corners get rounder as surfaces get bigger, which is what makes a stack of
    // them read as nested rather than as a pile. The old set had a 28pt card
    // inside a 22pt card inside a 44pt sheet, which reads as three unrelated
    // panels that happen to be touching.

    enum Radius {
        /// The little rounded square behind an activity's mark.
        static let glyph: CGFloat = 12
        /// Capsule-adjacent: chips, small buttons.
        static let chip: CGFloat = 14
        /// Buttons and inline controls.
        static let control: CGFloat = 18
        /// The standard card.
        static let card: CGFloat = 24
        /// A card that fills the screen — the Paths hero.
        static let hero: CGFloat = 30
        /// Presented sheets.
        static let sheet: CGFloat = 44
    }

    static let cardRadius = Radius.card
    static let sheetRadius = Radius.sheet

    static func cardShape(_ radius: CGFloat = Radius.card) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    // MARK: - Fonts

    static func label(_ size: CGFloat = 9.5) -> Font {
        .system(size: size, weight: .semibold)
    }

    static func mono(_ size: CGFloat = 10, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func title(_ size: CGFloat = 32) -> Font {
        .system(size: size, weight: .bold)
    }

    static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular)
    }

    /// The small all-caps line that labels a value — "DIFFICULTY", "THE DAY".
    ///
    /// A named style rather than four call sites each choosing their own size,
    /// weight and kerning, which is how the app ended up with 9pt/1.3 in one
    /// place and 10pt/1.4 twenty points away on the same card.
    static var overline: Font { .system(size: 10, weight: .semibold) }
    static let overlineKerning: CGFloat = 1.3
}

// MARK: - Motion

/// The UI's curves. The scene has its own — see `Animation.settle` and friends
/// in `SwordSceneLayers` — and these are deliberately separate: those describe
/// mass moving, and these describe an interface responding.
///
/// Three, because the app was using nine. A tally of the hand-written springs
/// found `0.30/0.80`, `0.32/0.82`, `0.34/0.84`, `0.36/0.84`, `0.38/0.84` and
/// `0.34/0.86` — six curves nobody could tell apart in isolation and everybody
/// could feel side by side, because a row that removes itself on one spring next
/// to a section that closes on another reads as two apps.
extension Animation {

    /// A thing acknowledging a tap: a chip selecting, a mark swapping, a value
    /// changing under your finger. Fast, and barely bounces.
    static let forgeSelection: Animation = .spring(response: 0.28, dampingFraction: 0.86)

    /// A row arriving, leaving, or moving. Slow enough to follow.
    static let forgeRow: Animation = .spring(response: 0.36, dampingFraction: 0.84)

    /// Something appearing or going away with no weight to it.
    static let forgeFade: Animation = .easeOut(duration: 0.20)
}

// MARK: - Surfaces

/// Native Liquid Glass card surface, replacing the old fill + stroke-overlay
/// stack.
struct ForgeCard: ViewModifier {
    var radius: CGFloat = ForgeTheme.Radius.card

    func body(content: Content) -> some View {
        content.glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
    }
}

extension View {
    func forgeCard(radius: CGFloat = ForgeTheme.Radius.card) -> some View {
        modifier(ForgeCard(radius: radius))
    }

    /// Interactive glass — responds to touch. For tappable card surfaces.
    func forgeInteractiveCard(radius: CGFloat = ForgeTheme.Radius.card) -> some View {
        glassEffect(
            .regular.interactive(),
            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
    }
}

// MARK: - The colour the app is drawn in

/// The tints Forge can be dressed in, and there are eight of them.
///
/// # Why a closed set and not a colour picker
///
/// The same argument `ForgeAccent` makes about identities, and it is stronger
/// here because this colour is on every control in the app. A free picker can
/// name a colour that fails contrast against dark glass, and the person who
/// picks it has no way to know that is what they did — they see one swatch, not
/// the eleven places it lands. A closed set means the review happens once, in
/// this file, against the surfaces these actually sit on.
///
/// Eight is also what makes the screen a *choice* rather than a tool. Two rows
/// of four, every one of them named, every one of them a decision somebody made
/// on purpose. A picker is a component; this is a wardrobe.
///
/// # How they were chosen
///
/// Each one has to clear two tests, and both were run against the app rather
/// than against a swatch: it has to be legible as a 12pt label on regular glass
/// over the dark room, and it has to still read as *the interface* rather than
/// as part of the scene. That second test is what keeps the warm ones honest —
/// `ember` is a hotter, more saturated orange than anything in the plate, so it
/// separates from the firelight instead of joining it.
enum ForgeThemeAccent: String, CaseIterable, Identifiable, Sendable {
    /// The blue Forge has always been, and the default. See `ForgeTheme.accent`.
    case forge
    case ember
    case gold
    case moss
    case tide
    case violet
    case rose
    /// The one achromatic option, and it is warm rather than grey. A neutral
    /// accent would be indistinguishable from the app's own secondary text and
    /// every selection state would vanish; `bone` is the cream the app already
    /// uses on its primary buttons, promoted to the tint.
    case bone

    var id: String { rawValue }

    /// The name shown under the swatch. A colour nobody can say out loud is a
    /// colour nobody chooses on purpose.
    var label: String {
        switch self {
        case .forge: "Forge"
        case .ember: "Ember"
        case .gold: "Gold"
        case .moss: "Moss"
        case .tide: "Tide"
        case .violet: "Violet"
        case .rose: "Rose"
        case .bone: "Bone"
        }
    }

    /// One line about what it is, not about what it looks like.
    var note: String {
        switch self {
        case .forge: "The default. Cool against a warm room."
        case .ember: "The fire, brought up onto the interface."
        case .gold: "Floodlit. The warmest of them."
        case .moss: "Quiet, and the easiest to live with."
        case .tide: "Cold water. Sharpest at small sizes."
        case .violet: "Late. Reads as evening rather than night."
        case .rose: "Warm without being loud."
        case .bone: "No colour at all — the cream the buttons already use."
        }
    }

    /// One table, in `Shared/ForgeAccentPalette`, because the widgets need it
    /// too and cannot see this file.
    var color: Color { ForgeAccentPalette.color(rawValue) }
}

/// What the app looks like, as the user set it.
///
/// # Why a singleton rather than a store handed down
///
/// Every other piece of state in Forge is built in `ContentView.init` and passed
/// to whoever needs it, and that rule is worth keeping for anything that is a
/// *fact about the practice*. This is not one. It is read by seventy-nine call
/// sites across every screen in the app, none of which has any other reason to
/// know a theme exists, and threading an object through all of them to change a
/// colour would be the most invasive possible way to do the least important
/// thing in the product.
///
/// Observation makes the shortcut safe. `@Observable` tracks a read wherever it
/// happens, including inside a `static var` on an `enum` — so `ForgeTheme.accent`
/// is a dependency of every body that mentions it, and changing this redraws
/// exactly those views and nothing else.
///
/// # Nothing derived, one key, tolerant on read
///
/// An unknown raw value lands on `forge` rather than throwing, for the reason
/// every decoder in this codebase is tolerant: the failure mode of strictness is
/// somebody opening the app to find it looks wrong and having no idea why.
@Observable
final class ForgeAppearance {

    /// The one instance. See the note above on why this is not handed down.
    ///
    /// Not `@MainActor`, and deliberately: `ForgeTheme.accent` is a plain static
    /// read from every view in the app and annotating this would make that read
    /// isolated, which would put an actor hop in front of a colour.
    static let shared = ForgeAppearance()

    private enum Key {
        static let accent = "forge.accent.v1"
    }

    var accent: ForgeThemeAccent {
        didSet {
            guard accent != oldValue else { return }
            ForgeShared.defaults.set(accent.rawValue, forKey: Key.accent)
        }
    }

    init() {
        let stored = ForgeShared.defaults.string(forKey: Key.accent)
        accent = stored.flatMap(ForgeThemeAccent.init(rawValue:)) ?? .forge
    }
}

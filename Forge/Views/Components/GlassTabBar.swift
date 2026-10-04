import SwiftUI

/// Tab identity for the app's root `TabView`.
///
/// The hand-built `GlassTabBar` that used to live here — a capsule of
/// `.ultraThinMaterial` with four stacked gradient/stroke overlays faking a
/// glass highlight — has been removed. iOS 26's native tab bar is real Liquid
/// Glass, and it brings the minimize-on-scroll behaviour, accessibility
/// labels and system tab-switching animations that the custom bar lacked.
enum AppTab: String, CaseIterable, Hashable {
    /// Order is deliberate, and the middle two are a pair.
    ///
    /// The day comes first because it is the only tab anybody has to open. Then
    /// **Blade**, which is the record — every day already kept — and then
    /// **Becoming**, which is the direction. Past and future, in that order,
    /// either side of the present.
    ///
    /// `becoming` replaced `paths`, and the change was not a rename. A tab is a
    /// claim about how often something is worth opening, and a shelf of worlds
    /// to dress the app in is worth opening roughly twice: once out of
    /// curiosity, and once to leave. What is worth returning to is who somebody
    /// said they were becoming and what the record says about it — and the
    /// shelf is a section of that rather than a peer of it. See
    /// `BecomingTabView`.
    ///
    /// # Forge · Blade · Becoming · Arcs (1.1)
    ///
    /// **Arcs took Settings' place in the bar** (DIRECTION_1_1 §5): a program
    /// somebody is ninety days into is worth a tab, and the screen where rest
    /// days and the wake time are set is visited a few times a year. Blade sits
    /// directly beside the day it is made of, Becoming after it, and Arcs last,
    /// where Settings used to be. Settings has one home: a gear in the Arcs
    /// navigation bar (`settingsHosts`), and every screen in it is where it
    /// was. Deep links, notifications and widgets still land on Forge.
    case forge, blade, becoming, arcs

    var label: String { rawValue.capitalized }

    /// The tabs whose navigation bar carries the gear that opens Settings.
    static let settingsHosts: [AppTab] = [.arcs]

    var iconKey: String {
        switch self {
        case .forge: return "sword"
        case .arcs: return "mountain"
        case .blade: return "chart"
        case .becoming: return "path"
        }
    }

    /// SF Symbol used by the native tab bar.
    ///
    /// `becoming` is the one tab that is not drawn from one — see `image`. The
    /// hexagon it names is the fallback, and nothing should reach it.
    var symbol: String {
        switch self {
        // SF Symbols has no sword; the forge itself reads better here and
        // leaves the trophy glyph to the sword-collection screens.
        case .forge: return "flame.fill"
        // A climb with a top: an Arc has a start and an end. Not a flag — the
        // daily challenge is the flag, and two flags in one app would be one
        // mark meaning two things.
        case .arcs: return "mountain.2.fill"
        case .becoming: return "hexagon"
        default: return ForgeIcons.symbol(for: iconKey)
        }
    }

    /// The catalogue image a tab is drawn from, where no system symbol says the
    /// thing.
    ///
    /// **Only Becoming has one, and it is a sign.** The tab has been four
    /// glyphs now: `arrow.triangle.turn.up.right.diamond` while it was a shelf
    /// of worlds, then `hexagon` for the polygon every screen on it is built
    /// around. The hexagon is honest about the *content* and says nothing about
    /// the *tab* — a bare outline of a shape is the one mark in the bar that is
    /// not a picture of an idea, and beside a flame and a chart it reads as a
    /// placeholder somebody forgot to replace.
    ///
    /// So it is a road sign: **a solid diamond plate with a turn-right arrow
    /// knocked out of it** (since telemetry, `FORGE_CONTEXT.md` §2p — it was a
    /// straight arrow in an outlined diamond before that). Becoming is the
    /// direction, beside Blade, which is the record of days already kept; the
    /// turn says the direction is a change of course rather than more of the
    /// same road. Solid rather than outlined so it sits with the flame beside it,
    /// which is `flame.fill`.
    ///
    /// It is a `template`-rendered vector in `Assets.xcassets` rather than
    /// `arrow.triangle.turn.up.right.diamond.fill`: the system glyph's arrow is
    /// a thin junction mark, and this one is drawn to the reference — a heavy
    /// stem, one rounded bend, a broad head. The arrow is an even-odd hole in
    /// the plate, so the tab bar's own background shows through it and the tint
    /// colours only the plate, selected or not, exactly as it did the old sign.
    var image: String? {
        switch self {
        case .becoming: return "BecomingSign"
        default: return nil
        }
    }
}

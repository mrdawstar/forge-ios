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
    case forge, blade, becoming, settings

    var label: String { rawValue.capitalized }

    var iconKey: String {
        switch self {
        case .forge: return "sword"
        case .blade: return "chart"
        case .becoming: return "path"
        case .settings: return "gear"
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
        case .becoming: return "hexagon"
        default: return ForgeIcons.symbol(for: iconKey)
        }
    }

    /// The catalogue image a tab is drawn from, where no system symbol says the
    /// thing.
    ///
    /// **Only Becoming has one, and it is a sign.** The tab has been three
    /// glyphs now: `arrow.triangle.turn.up.right.diamond` while it was a shelf
    /// of worlds, then `hexagon` for the polygon every screen on it is built
    /// around. The hexagon is honest about the *content* and says nothing about
    /// the *tab* — a bare outline of a shape is the one mark in the bar that is
    /// not a picture of an idea, and beside a flame and a chart it reads as a
    /// placeholder somebody forgot to replace.
    ///
    /// So it is a road sign again, but the right one: **a plain arrow pointing
    /// forward, inside a diamond.** Becoming is the direction — the tab about
    /// days that have not happened, sitting beside Blade, which is the record
    /// of the ones that have — and a direction sign is the least decorated way
    /// to say that. The *turn* arrow stays rejected for the reason it was
    /// rejected the first time: a junction is a choice between routes, and this
    /// tab is about one.
    ///
    /// It is a `template`-rendered vector in `Assets.xcassets` rather than a
    /// symbol because **SF Symbols has no `arrow.right.diamond`**: the family
    /// carries `plus`, `minus`, `xmark`, `checkmark` and `questionmark` in a
    /// diamond, and the only arrow in one is the junction. Drawn to the same
    /// optics as its neighbours — one stroke weight, round caps and joins, and
    /// the arrow sized so the sign reads before the arrow does.
    var image: String? {
        switch self {
        case .becoming: return "BecomingSign"
        default: return nil
        }
    }
}

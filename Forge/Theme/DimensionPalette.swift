import SwiftUI

/// The six have colours, and this is the only place they are decided.
///
/// # Which colour, and why these
///
/// Physical is Ember, Discipline is Forge blue, Mental is Tide, Intellect is
/// Gold, Relationship is Rose and Ambition is Violet (DIRECTION_1_1 §4). They
/// are **the existing accent palette**, read from `ForgeAccentPalette` rather
/// than mixed again here, so each one has already cleared the two tests every
/// accent had to (`ForgeThemeAccent`): legible as a small label on dark glass,
/// and still reading as interface rather than as part of the lit room.
///
/// # What they are for, and what they are not
///
/// A dimension's colour says **which part of a person** something is about: the
/// hexagon's vertices and edge, a stat tile, a dimension's glyph, a challenge's
/// aim. It never means "chosen" or "pressed" — that is still the accent's one
/// job (`ForgeTheme.accent`), which is why a chosen row keeps its accent
/// hairline and its glyph takes the dimension's colour.
///
/// Not in `Shared/`: the widgets draw no dimensions, and this reads
/// `RitualCategory`, which the widget target cannot see. The colours
/// themselves are still the one table in `Shared/ForgePalette.swift`.
enum DimensionPalette {

    /// The accent each dimension is drawn in, by its raw name.
    static func accentName(for dimension: RitualCategory) -> String {
        switch dimension {
        case .physical: "ember"
        case .discipline: ForgeAccentPalette.fallback
        case .mental: "tide"
        case .intellect: "gold"
        case .relationship: "rose"
        case .ambition: "violet"
        // A filter, never drawn as a dimension.
        case .all: "bone"
        }
    }

    static func color(for dimension: RitualCategory) -> Color {
        ForgeAccentPalette.color(accentName(for: dimension))
    }
}

extension RitualCategory {
    /// This dimension's colour. See `DimensionPalette`.
    var color: Color { DimensionPalette.color(for: self) }
}

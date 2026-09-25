import SwiftUI

// MARK: - Icon key → SF Symbol
//
// Forge used to ship its own SVG path table and a hand-written path parser.
// Every glyph in that table has a native SF Symbol equivalent, so the keys now
// resolve straight to `Image(systemName:)` — which gives us hierarchical and
// variable rendering, symbol effects, Dynamic Type scaling and correct optical
// alignment inside Liquid Glass controls for free.
enum ForgeIcons {
    static let symbols: [String: String] = [
        // Rituals
        "drop": "drop.fill",
        "bed": "bed.double.fill",
        // Clearing a surface used to share the bed glyph, which read as a
        // duplicate the moment the two sat next to each other in a list.
        "surface": "table.furniture.fill",
        "brush": "mouth.fill",
        "figure": "figure.strengthtraining.functional",
        "book": "book.fill",
        "run": "figure.run",
        "dumbbell": "dumbbell.fill",
        "stretch": "figure.flexibility",
        "meditate": "figure.mind.and.body",
        "journal": "pencil.and.list.clipboard",
        "music": "music.note",
        "plant": "leaf.fill",
        "dishes": "sink.fill",
        "coffee": "cup.and.saucer.fill",
        "pill": "pills.fill",
        "shower": "shower.fill",
        "broom": "dishwasher.fill",
        "bike": "bicycle",
        "hands": "hands.and.sparkles.fill",
        // Added with the thirteen activities that filled out the thin
        // dimensions. Every one of them exists because a glyph was being
        // *reused*: "Call someone", "Listen properly" and "Help someone" all
        // drew the same pair of sparkling hands, three rows apart on the first
        // screen a new user picks from, and a list where three items share a
        // mark reads as a list that has lost its data.
        "ear": "ear.fill",
        "envelope": "envelope.fill",
        "phone": "phone.fill",
        "speech": "text.bubble.fill",
        "quote": "quote.bubble.fill",
        "pencil": "pencil.line",
        "wind": "wind",
        "hand": "hand.raised.fill",
        "cloud": "cloud.fill",
        "mute": "speaker.slash.fill",
        "bag": "bag.fill",
        "hammer": "hammer.fill",
        // And four more for the same reason, on activities that predate the
        // thirteen: `book` was drawing Read, Learn, Practise a language *and*
        // Study, which is four rows of the picker with one mark between them.
        "lightbulb": "lightbulb.fill",
        "globe": "globe",
        "cap": "graduationcap.fill",
        "fork": "fork.knife",

        // Chrome & status
        //
        // The trophy and the medal have been taken out. Nothing in Forge is won,
        // and the two glyphs that said otherwise were the last of it — "sword"
        // resolved to a trophy, which put a prize on the one screen that exists
        // to sell somebody a blade.
        "sword": "figure.fencing",
        "chart": "chart.bar.fill",
        "gear": "gearshape.fill",
        "search": "magnifyingglass",
        "lock": "lock.fill",
        "check": "checkmark",
        "sparkle": "sparkles",
        "bolt": "bolt.fill",
        "flame": "flame.fill",
        "mountain": "mountain.2.fill",
        "target": "target",
        "timer": "timer",
        "scroll": "scroll.fill",
        "bell": "bell.fill",
        "sunrise": "sunrise.fill",
        "sun": "sun.max.fill",
        "moon": "moon.fill",
        "calendar": "calendar",
        "code": "chevron.left.forwardslash.chevron.right",
    ]

    static func symbol(for key: String) -> String {
        symbols[key] ?? "questionmark"
    }
}

// MARK: - Activity icon catalogue
//
// What a user-made activity can be marked with. Deliberately a curated set
// rather than all 8 000-odd SF Symbols: the job is "find the one that means my
// day run" in a couple of seconds, and a complete index makes that harder,
// not easier. Everything here is filled, single-weight and monochrome, so any
// two sit together without one shouting.

enum ActivityIcons {
    struct Icon: Identifiable, Hashable {
        let symbol: String
        let name: String
        /// Extra search terms — what someone might type that is not the name.
        var alias: String = ""

        var id: String { symbol }

        func matches(_ query: String) -> Bool {
            name.localizedCaseInsensitiveContains(query)
                || alias.localizedCaseInsensitiveContains(query)
        }
    }

    struct Group: Identifiable {
        let name: String
        let icons: [Icon]
        var id: String { name }
    }

    static let groups: [Group] = [
        Group(name: "Movement", icons: [
            Icon(symbol: "figure.run", name: "Run", alias: "jog cardio"),
            Icon(symbol: "figure.walk", name: "Walk", alias: "steps"),
            Icon(symbol: "figure.strengthtraining.functional", name: "Workout", alias: "exercise train gym"),
            Icon(symbol: "figure.strengthtraining.traditional", name: "Weights", alias: "lift gym strength"),
            Icon(symbol: "dumbbell.fill", name: "Lift", alias: "weights gym"),
            Icon(symbol: "figure.flexibility", name: "Stretch", alias: "mobility warm up"),
            Icon(symbol: "figure.yoga", name: "Yoga", alias: "stretch mat"),
            Icon(symbol: "figure.core.training", name: "Core", alias: "abs plank"),
            Icon(symbol: "figure.jumprope", name: "Skip", alias: "jump rope cardio"),
            Icon(symbol: "figure.boxing", name: "Boxing", alias: "fight bag"),
            Icon(symbol: "figure.pool.swim", name: "Swim", alias: "pool"),
            Icon(symbol: "figure.hiking", name: "Hike", alias: "trail outdoors"),
            Icon(symbol: "bicycle", name: "Cycle", alias: "bike ride"),
            Icon(symbol: "figure.stair.stepper", name: "Stairs", alias: "steps climb"),
            Icon(symbol: "figure.dance", name: "Dance", alias: "move"),
            Icon(symbol: "figure.cooldown", name: "Cool Down", alias: "recover"),
        ]),
        Group(name: "Mind", icons: [
            Icon(symbol: "book.fill", name: "Read", alias: "reading book pages"),
            Icon(symbol: "book.closed.fill", name: "Book", alias: "reading"),
            Icon(symbol: "character.book.closed.fill", name: "Language", alias: "learn vocabulary study"),
            Icon(symbol: "graduationcap.fill", name: "Study", alias: "learn school course"),
            Icon(symbol: "square.and.pencil", name: "Journal", alias: "write diary notes"),
            Icon(symbol: "pencil.and.outline", name: "Write", alias: "journal draft"),
            Icon(symbol: "list.bullet.rectangle.fill", name: "Notes", alias: "write list"),
            Icon(symbol: "checklist", name: "Plan", alias: "planning todo tasks"),
            Icon(symbol: "calendar", name: "Schedule", alias: "plan diary day"),
            Icon(symbol: "brain.head.profile", name: "Focus", alias: "mind think concentrate"),
            Icon(symbol: "lightbulb.fill", name: "Ideas", alias: "think brainstorm"),
            Icon(symbol: "chevron.left.forwardslash.chevron.right", name: "Code", alias: "coding program dev"),
            Icon(symbol: "laptopcomputer", name: "Work", alias: "desk computer"),
            Icon(symbol: "puzzlepiece.fill", name: "Puzzle", alias: "game chess brain"),
            Icon(symbol: "globe", name: "World", alias: "language news travel"),
            Icon(symbol: "paintbrush.pointed.fill", name: "Create", alias: "art draw paint"),
        ]),
        Group(name: "Stillness", icons: [
            Icon(symbol: "figure.mind.and.body", name: "Meditate", alias: "meditation sit calm"),
            Icon(symbol: "lungs.fill", name: "Breathe", alias: "breathing breath"),
            Icon(symbol: "wind", name: "Breath", alias: "breathing air calm"),
            Icon(symbol: "hands.and.sparkles.fill", name: "Pray", alias: "prayer gratitude faith"),
            Icon(symbol: "hand.raised.fill", name: "Stillness", alias: "pause stop"),
            Icon(symbol: "heart.fill", name: "Gratitude", alias: "love thanks heart"),
            Icon(symbol: "sparkles", name: "Reflect", alias: "gratitude thoughts"),
            Icon(symbol: "sunrise.fill", name: "Sunrise", alias: "morning dawn light"),
            Icon(symbol: "sun.max.fill", name: "Daylight", alias: "sun light outside"),
            Icon(symbol: "sunset.fill", name: "Sunset", alias: "evening dusk"),
            Icon(symbol: "moon.stars.fill", name: "Night", alias: "sleep evening"),
            Icon(symbol: "moon.zzz.fill", name: "Sleep", alias: "rest bed night"),
            Icon(symbol: "leaf.fill", name: "Nature", alias: "outside green plant"),
            Icon(symbol: "music.note", name: "Music", alias: "listen song play"),
            Icon(symbol: "headphones", name: "Listen", alias: "music podcast audio"),
            Icon(symbol: "pianokeys", name: "Piano", alias: "music practice instrument"),
        ]),
        Group(name: "Fuel", icons: [
            Icon(symbol: "drop.fill", name: "Water", alias: "drink hydrate glass"),
            Icon(symbol: "waterbottle.fill", name: "Bottle", alias: "water drink hydrate"),
            Icon(symbol: "cup.and.saucer.fill", name: "Coffee", alias: "espresso drink"),
            Icon(symbol: "mug.fill", name: "Tea", alias: "drink warm"),
            Icon(symbol: "fork.knife", name: "Breakfast", alias: "eat food meal"),
            Icon(symbol: "carrot.fill", name: "Vegetables", alias: "eat food healthy greens"),
            Icon(symbol: "fish.fill", name: "Protein", alias: "eat food meal"),
            Icon(symbol: "pills.fill", name: "Vitamins", alias: "supplements pills meds"),
            Icon(symbol: "basket.fill", name: "Groceries", alias: "shop food"),
        ]),
        Group(name: "Home", icons: [
            Icon(symbol: "bed.double.fill", name: "Make Bed", alias: "bedroom tidy sleep"),
            Icon(symbol: "shower.fill", name: "Cold Shower", alias: "shower wash cold"),
            Icon(symbol: "bathtub.fill", name: "Bath", alias: "wash soak"),
            Icon(symbol: "bubbles.and.sparkles.fill", name: "Clean", alias: "cleaning tidy wash"),
            Icon(symbol: "sink.fill", name: "Dishes", alias: "wash kitchen sink"),
            Icon(symbol: "washer.fill", name: "Laundry", alias: "wash clothes"),
            Icon(symbol: "trash.fill", name: "Bins", alias: "rubbish trash waste"),
            Icon(symbol: "house.fill", name: "Home", alias: "house tidy"),
            Icon(symbol: "dog.fill", name: "Dog Walk", alias: "pet walk dog"),
            Icon(symbol: "cat.fill", name: "Cat", alias: "pet feed"),
            Icon(symbol: "hammer.fill", name: "Fix", alias: "repair diy build"),
            Icon(symbol: "wrench.and.screwdriver.fill", name: "Maintain", alias: "repair diy tools"),
        ]),
        Group(name: "Discipline", icons: [
            Icon(symbol: "target", name: "Goal", alias: "aim target focus"),
            Icon(symbol: "flame.fill", name: "Streak", alias: "fire habit"),
            Icon(symbol: "bolt.fill", name: "Energy", alias: "power fast"),
            Icon(symbol: "timer", name: "Timer", alias: "time minutes"),
            Icon(symbol: "stopwatch.fill", name: "Stopwatch", alias: "time track"),
            Icon(symbol: "hourglass", name: "Patience", alias: "time wait"),
            Icon(symbol: "iphone.slash", name: "No Phone", alias: "screen detox offline feed"),
            Icon(symbol: "lock.fill", name: "Locked", alias: "block restrict"),
            Icon(symbol: "eye.fill", name: "Notice", alias: "look watch aware"),
            Icon(symbol: "flag.fill", name: "Milestone", alias: "goal finish"),
            Icon(symbol: "mountain.2.fill", name: "Climb", alias: "hard challenge summit"),
            Icon(symbol: "checkmark.seal.fill", name: "Done", alias: "complete finish tick"),
        ]),
    ]

    static let all: [Icon] = groups.flatMap(\.icons)

    /// Default for a new activity — neutral enough to be a starting point, not
    /// so neutral it looks like a placeholder that failed to load.
    static let fallback = "checkmark.seal.fill"

    static func matching(_ query: String) -> [Icon] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.matches(trimmed) }
    }

    /// The catalogue entry for a symbol, when one exists — used for the
    /// spoken name of a chosen icon.
    static func named(_ symbol: String?) -> String {
        guard let symbol else { return "" }
        return all.first { $0.symbol == symbol }?.name ?? ""
    }

    /// Which group a symbol belongs to. The verification classifier reads this
    /// as a second opinion on what an activity actually is — the icon somebody
    /// reached for says something their wording might not.
    static func groupName(for symbol: String) -> String? {
        groups.first { group in group.icons.contains { $0.symbol == symbol } }?.name
    }
}

// MARK: - Convenience view

struct ForgeIconView: View {
    let key: String
    /// Bypasses the key table when a symbol is already known by name — what
    /// user-made activities carry.
    var symbol: String? = nil
    var size: CGFloat = 20
    var color: Color = .primary

    var body: some View {
        Image(systemName: symbol ?? ForgeIcons.symbol(for: key))
            .font(.system(size: size * 0.86, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .frame(width: size, height: size)
    }
}

/// The mark for one ritual, wherever a ritual is listed.
///
/// A user-made activity carries its symbol directly; a library entry resolves
/// one through `iconKey`. Both come out of the same monochrome set at the same
/// weight, so a day of five library activities and one the user invented
/// reads as one list rather than as two kinds of thing.
struct RitualGlyph: View {
    let ritual: Ritual
    var size: CGFloat = 20
    var color: Color = .primary

    var body: some View {
        ForgeIconView(
            key: ritual.iconKey,
            symbol: ritual.symbolName,
            size: size,
            color: color
        )
    }
}

/// How this one gets confirmed, in one character.
///
/// One view for all three methods, and that is the whole point of it. There
/// used to be a `HealthMark` and nothing else, which meant every list decided
/// for itself whether to draw a glyph and which — and a row could end up
/// wearing a heart while the words beside it said "Your Word". A mark that is
/// *derived from the method* cannot disagree with the method.
///
/// Deliberately colourless and sizeless: it takes the font and the foreground
/// style of whatever it is placed in, so it reads as a character of the
/// metadata beside it rather than as a badge stuck onto the row. A tinted heart
/// pulled the eye to the quietest thing on the line — the target — and away from
/// the activity, which is the thing somebody is actually reading.
///
/// `imageScale(.small)` is the only shaping it does. A filled heart set solid at
/// text size is heavier than the digits it stands next to, and the point is that
/// nobody should notice it until they are looking for it.
///
/// Hidden from VoiceOver at every call site — the rows it appears in say what it
/// means in words, and a glyph announced beside those words is the same fact
/// twice.
struct VerificationMark: View {
    let method: VerificationMethod

    var body: some View {
        Image(systemName: method.symbol)
            .imageScale(.small)
            .accessibilityHidden(true)
    }
}

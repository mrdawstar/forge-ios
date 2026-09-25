import SwiftUI
import WidgetKit

/// Everything Forge puts outside the app.
///
/// Four widgets and one Live Activity, and the list is meant to stay that
/// length: each family answers exactly one question, and a fifth would only be
/// a second answer to a question one of these already covers.
@main
struct ForgeWidgetBundle: WidgetBundle {
    var body: some Widget {
        DayWidget()
        DayLiveActivity()
    }
}

// MARK: - Timeline

/// One reading of the day, at a moment.
struct DayEntry: TimelineEntry {
    let date: Date
    let snapshot: ForgeSnapshot
}

/// Reads what the app last wrote, and asks to be woken at the next moment the
/// answer could be different by itself.
///
/// The app reloads timelines whenever the day actually moves, so this
/// schedule is only the backstop: it exists so a phone that has not had Forge
/// opened since yesterday still shows today's empty day rather than
/// yesterday's finished one.
struct DayProvider: TimelineProvider {

    /// What the system draws while it has nothing — in the gallery, and in the
    /// redacted placeholder behind a locked screen.
    ///
    /// A plausible day rather than an empty one: a widget shown empty in the
    /// gallery is a widget nobody adds. Nothing here is written anywhere and
    /// nothing here is ever shown over real data — `getTimeline` reads the
    /// snapshot, and an absent snapshot is a genuinely empty day.
    func placeholder(in context: Context) -> DayEntry {
        DayEntry(date: .now, snapshot: .fresh(daysKept: 12, total: 3))
    }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        completion(DayEntry(date: .now, snapshot: ForgeSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let now = Date.now
        let snapshot = ForgeSnapshot.read(now: now)
        let entry = DayEntry(date: now, snapshot: snapshot)
        completion(Timeline(entries: [entry], policy: .after(nextRollover(after: now, snapshot: snapshot))))
    }

    /// The next time the forge day turns over, which is the only instant at
    /// which a snapshot stops being true without anybody touching the app.
    private func nextRollover(after now: Date, snapshot: ForgeSnapshot) -> Date {
        let calendar = Calendar.current
        let next = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: snapshot.dayStartHour, minute: 0),
            matchingPolicy: .nextTime
        )
        // An hour's grace on the fallback rather than a tight loop, if the
        // calendar ever cannot answer.
        return next ?? now.addingTimeInterval(3600)
    }
}

// MARK: - Widget

/// One widget, five families.
///
/// Declared together because they are one idea shown at five sizes rather than
/// five features — a user adding "Forge" to their Lock Screen should not have to
/// choose between five entries that all say Forge.
///
/// **They are not one design scaled five ways.** Each family answers the biggest
/// question its own space can hold: the circle answers *how many left*, the
/// rectangle *what next*, the small card *what next, and how far through*, the
/// medium adds *where today sits in the week*, and the large is the only one
/// that is not about today at all — six months of the record, which is a fact
/// that needs a whole card and is worthless in a corner of a small one.
struct DayWidget: Widget {
    var body: some WidgetConfiguration {
        // The kind still spells the old name, and it is not free to follow the
        // rename. WidgetKit stores it with every widget a user has placed: a
        // new spelling is a new widget, so every Home Screen and Lock Screen
        // already carrying this one would go blank and have to be set up again.
        // Nobody ever sees this string; they only see it break.
        StaticConfiguration(kind: "ForgeMorning", provider: DayProvider()) { entry in
            DayWidgetView(snapshot: entry.snapshot)
                // **Dark, because the ground below is.** A widget renders in
                // whatever appearance the Home Screen is in, so `.primary` on a
                // phone in light mode is black — and the first build of this
                // drew a black blade and black digits on Forge's near-black
                // card, which is to say nothing at all. Fixing the ground
                // without fixing the foreground is half a change.
                .environment(\.colorScheme, .dark)
                .containerBackground(for: .widget) { ground(entry.snapshot) }
                // Every family opens the same screen, because every family is
                // about the same screen.
                .widgetURL(ForgeLink.today)
        }
        .configurationDisplayName("Forge")
        .description("What today still asks for, and the record behind it.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .systemSmall,
            .systemMedium,
            .systemLarge,
        ])
    }
}

struct DayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: ForgeSnapshot

    var body: some View {
        switch family {
        case .accessoryCircular: CircularView(snapshot: snapshot)
        case .accessoryRectangular: RectangularView(snapshot: snapshot)
        case .systemMedium: MediumView(snapshot: snapshot)
        case .systemLarge: LargeView(snapshot: snapshot)
        default: SmallView(snapshot: snapshot)
        }
    }
}

/// The ground the Home Screen families are drawn on.
///
/// # Why it is not `.fill.tertiary`
///
/// Because Forge is a dark app that says so at the root — every screen is
/// `preferredColorScheme(.dark)`, the whole product is one lit room — and a
/// widget taking the system's own light material was the single surface of the
/// product that looked like a different product. A person with Forge on their
/// Home Screen next to Calendar had a pale grey card with a blade on it.
///
/// So it is the room: near-black, warmed rather than blued, lifted very slightly
/// at the top so the card has a direction of light like everything else in the
/// app. On top of that, one soft wash of the person's own accent from above —
/// the only colour on a widget that has nothing done yet, and low enough that it
/// reads as light falling into a room rather than as a gradient. It brightens
/// when the blade is out, which is the one state worth its own treatment
/// everywhere else in this target too.
///
/// **Accessory families get nothing.** `containerBackground` is ignored on the
/// Lock Screen, where the system draws its own material; the builder still runs,
/// so it is cheap, and it stays correct if a future family starts honouring it.
@ViewBuilder
private func ground(_ snapshot: ForgeSnapshot) -> some View {
    ZStack {
        LinearGradient(
            colors: [ForgeAccentPalette.groundLift, ForgeAccentPalette.ground],
            startPoint: .top,
            endPoint: .bottom
        )
        // One wash, from where the app's light comes from. It used to sit dead
        // centre with the drawn blade under it; with the blade gone the card is
        // read from the top left like a page, and the light belongs at the top
        // left with it.
        RadialGradient(
            colors: [snapshot.tint.opacity(snapshot.isEarned ? 0.26 : 0.13), .clear],
            center: UnitPoint(x: 0.16, y: 0.0),
            startRadius: 0,
            endRadius: 220
        )
    }
}

import SwiftUI
import TipKit

/// The first week's five tips, and the one rule about when any of them may
/// speak.
///
/// # Five, in order, one at a time
///
/// One ordered `TipGroup`, so a tip only ever appears once the one before it is
/// done with, and never two on a screen:
///
/// 1. on the first activity row — **"Tap when it's done."**
/// 2. on the scene, once everything is done — **"Drag the blade up to keep the day."**
/// 3. on the Becoming tab — **"Your six stats move with what you keep."**
/// 4. on the Arcs tab — **"Arcs have a start and an end. One at a time."**
/// 5. on the `+` — **"Add anything in one tap."**
///
/// The order is the order the app is learned in: keep something, pull, see
/// what it moved, see what a longer stretch looks like, add more. A tip whose
/// place has not come up — somebody who never opens Arcs — holds the ones
/// after it, which is what "in order" costs and is the point of it.
///
/// Each is shown **at most once** (`MaxDisplayCount(1)`), and the ones that
/// teach an act are put away the first time the act is done, whether or not
/// the tip was ever read: nobody needs to be told to tap a row they have
/// already tapped.
///
/// # Inline, except on the `+`
///
/// A TipKit popover is modal: the first touch anywhere outside it only puts it
/// away. Pointed at the first row, that touch is the tap the tip asks for, and
/// on the scene it is the drag — so the first four are inline `TipView`s, each
/// beside what it is about (above the list, above the controls with its arrow
/// up at the blade, under the tiles, at the top of the Arcs tab), and nothing
/// has to be dismissed before the screen works. The `+` keeps a popover: it is
/// a button, the tip names what it does, and it is the one place a popover's
/// arrow is the clearest thing on offer.
///
/// # When none of them may speak
///
/// `mayShow`: never in the first run, which teaches all of this already, and
/// never over a moment that is the day rather than a pause in it — a summary,
/// a pull, a celebration, an honor prompt, or one of the three things the app
/// offers above the day (coming back, the chapter, the week). The answer is
/// handed to TipKit as a transient parameter every tip's rules read, so it is
/// worked out by the app, tested here, and never stored.
enum ForgeTips {

    /// What is on screen, as far as a tip is concerned.
    struct Moment: Equatable, Sendable {
        var hasCompletedFirstRun: Bool
        /// The first run's own screens are up.
        var isFirstRunCovering: Bool = false
        /// A summary, a celebration, a pull under way, an honor prompt, or
        /// one of the three moments above the day.
        var isDayMomentOnScreen: Bool = false
    }

    /// Whether any tip may be on screen at this moment.
    static func mayShow(_ moment: Moment) -> Bool {
        moment.hasCompletedFirstRun && !moment.isFirstRunCovering && !moment.isDayMomentOnScreen
    }

    /// Whether a pull is the act the pull's tip teaches, and so puts it away.
    ///
    /// Not the first run's own pull. It comes before any tip may speak, and an
    /// ordered group passes over an invalidated tip for good — retired there,
    /// the second of the five was skipped for every new install, and the
    /// Becoming tab's came straight after the first row's.
    static func pullRetiresTip(hasCompletedFirstRun: Bool) -> Bool {
        hasCompletedFirstRun
    }

    /// `mayShow`, as TipKit reads it. Transient: it is a fact about this
    /// second, worked out again on every launch, never a stored value.
    @Parameter(.transient) static var isQuiet: Bool = false

    /// Everything on today's list is done and the blade has not come out —
    /// the only moment the pull's tip is about.
    @Parameter(.transient) static var isLoose: Bool = false

    /// The five, in order. Shared, so every screen asks the same group which
    /// tip is current.
    @MainActor static let group = TipGroup(.ordered) {
        RowTip()
        PullTip()
        BecomingTip()
        ArcsTip()
        AddTip()
    }

    /// The current tip, if it is this one — what each anchor hands to
    /// `popoverTip`, so only the tip whose turn it is can appear.
    @MainActor static func current<T: Tip>(_ type: T.Type) -> T? {
        group.currentTip as? T
    }

    /// The ids, in the group's order. What the tests read.
    static let order = [RowTip().id, PullTip().id, BecomingTip().id, ArcsTip().id, AddTip().id]

    // MARK: - Launch

    /// Once, at launch, before anything draws (`ForgeApp.init`).
    ///
    /// `.immediate`: the group already allows one tip at a time, in order, and
    /// each one waits for its own place on screen — a daily allowance on top
    /// of that would hold the pull's tip back to tomorrow on exactly the
    /// first day somebody needs it.
    static func configure(defaults: UserDefaults = .standard) {
        #if DEBUG
        if defaults.bool(forKey: resetKey) {
            defaults.removeObject(forKey: resetKey)
            try? Tips.resetDatastore()
        }
        #endif
        try? Tips.configure([.displayFrequency(.immediate)])
    }

    #if DEBUG
    private static let resetKey = "forge.debug.resetTips.v1"

    /// Settings → DEBUG → Reset Tips. Every tip is made eligible again now,
    /// and the whole datastore is cleared on the next launch as well, before
    /// TipKit is configured — the only moment it can be.
    static func resetAll(defaults: UserDefaults = .standard) async {
        defaults.set(true, forKey: resetKey)
        await RowTip().resetEligibility()
        await PullTip().resetEligibility()
        await BecomingTip().resetEligibility()
        await ArcsTip().resetEligibility()
        await AddTip().resetEligibility()
    }
    #endif
}

// MARK: - The five

/// 1. The first activity row.
struct RowTip: Tip {
    var id: String { "forge.tip.row" }
    var title: Text { Text("Tap when it's done.") }
    var rules: [Rule] { #Rule(ForgeTips.$isQuiet) { $0 == true } }
    var options: [any TipOption] { MaxDisplayCount(1) }
}

/// 2. The scene, once the blade is loose.
struct PullTip: Tip {
    var id: String { "forge.tip.pull" }
    var title: Text { Text("Drag the blade up to keep the day.") }
    var rules: [Rule] {
        #Rule(ForgeTips.$isQuiet) { $0 == true }
        #Rule(ForgeTips.$isLoose) { $0 == true }
    }
    var options: [any TipOption] { MaxDisplayCount(1) }
}

/// 3. The Becoming tab.
struct BecomingTip: Tip {
    var id: String { "forge.tip.becoming" }
    var title: Text { Text("Your six stats move with what you keep.") }
    var rules: [Rule] { #Rule(ForgeTips.$isQuiet) { $0 == true } }
    var options: [any TipOption] { MaxDisplayCount(1) }
}

/// 4. The Arcs tab.
struct ArcsTip: Tip {
    var id: String { "forge.tip.arcs" }
    var title: Text { Text("Arcs have a start and an end. One at a time.") }
    var rules: [Rule] { #Rule(ForgeTips.$isQuiet) { $0 == true } }
    var options: [any TipOption] { MaxDisplayCount(1) }
}

/// 5. The `+` on the Forge tab.
struct AddTip: Tip {
    var id: String { "forge.tip.add" }
    var title: Text { Text("Add anything in one tap.") }
    var rules: [Rule] { #Rule(ForgeTips.$isQuiet) { $0 == true } }
    var options: [any TipOption] { MaxDisplayCount(1) }
}

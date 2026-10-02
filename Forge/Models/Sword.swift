import SwiftUI

struct Sword: Identifiable, Equatable {
    let id: Int
    let name: String
    /// Perfect days needed to earn this blade.
    let requirement: Int
    let note: String
    /// Set by `SwordStore` from the real count of earned days. Never a
    /// stored fact about a blade — a collection that disagrees with the history
    /// behind it is the same bug as a streak that does.
    var isUnlocked: Bool = false

    var title: String { "\(name) Sword" }

    /// Collection art. Every sprite is 483×1771.
    var asset: String { "sword\(id)" }
    /// The lit variant the stone scene draws.
    var litAsset: String { "sword\(id)-lit" }

    var requirementLabel: String {
        requirement == 1 ? "1 day" : "\(requirement) days"
    }

    /// The nine, named for what is being done to the steel rather than for a
    /// rank the holder has reached.
    ///
    /// # Why these names and not the old ones
    ///
    /// They used to be Starter, Apprentice, Disciplined, Knight, Royal, Legend
    /// and Champion, with notes reading "Emerald inlay", "Ruby core", "Opal
    /// blade" and "Winged gold". Every one of those is a *rank* or a *material*,
    /// and between them they were the last place in the app that sounded like
    /// loot. Two specific problems:
    ///
    /// - **A rank is a claim about the person.** "Legend" at thirty days is the
    ///   app telling somebody what they are, which is the one thing Forge does
    ///   not do — and it is the same sentence whether those thirty days were
    ///   fought for or easy.
    /// - **A material is not evidence.** An opal blade is a thing you were
    ///   awarded. Nothing about it refers to a day anybody lived, so the only
    ///   available reading is that it dropped.
    ///
    /// So the arc is a forging: rough stock, struck, shaped, folded, quenched,
    /// edged, proven. It says the same thing the ladder above it says — the
    /// first sixty days are the blade being *made* — and it hands over cleanly
    /// to `BladeState`, which is what use does to a blade that already exists.
    /// **Proven** is the hinge: at sixty days the object is finished, and
    /// everything after is wear.
    ///
    /// **The names are display only.** Ids and requirements are untouched, so an
    /// existing install's collection, equipped blade and unlock history all
    /// survive this verbatim — see `Ladder.rungs`, which carries the same nine
    /// strings and must be changed with this file or the two screens disagree.
    ///
    /// # Honed and Enduring (1.1)
    ///
    /// Two more, at ninety and a hundred and eighty days kept (DIRECTION_1_1
    /// §6), because sixty was where the blades stopped and sixty is where a
    /// practice starts being worth keeping. They are **appended**: ids 8 and 9,
    /// nothing before them renumbered, no requirement moved. An install from
    /// 1.0 keeps the blade it carries and everything it has earned and seen; a
    /// long practice simply finds the new two already behind it (see
    /// `SwordStore.dismissCelebration`, which is what stops that arriving as two
    /// parties). Proven is no longer the last blade, so it is no longer the
    /// hinge: Enduring is, and past it the blade takes temper marks rather than
    /// new steel (`Ladder.temperMarks(daysKept:)`).
    ///
    /// None of the notes congratulates anybody, and none mentions a day that was
    /// missed — a blade is a record of what somebody does, not a report on how
    /// cleanly they have done it.
    static let collection: [Sword] = [
        Sword(id: 1, name: "Rough", requirement: 0,
              note: "Unworked steel. Nothing has been asked of it yet."),
        Sword(id: 2, name: "Struck", requirement: 1,
              note: "One day behind it, and the first mark anything leaves."),
        Sword(id: 3, name: "Shaped", requirement: 3,
              note: "Three days. It has started to hold a form."),
        Sword(id: 4, name: "Folded", requirement: 7,
              note: "A week folded into it. What repeats is what holds."),
        Sword(id: 5, name: "Quenched", requirement: 14,
              note: "A fortnight. Hard enough now to take an edge."),
        Sword(id: 6, name: "Edged", requirement: 30,
              note: "Thirty days. It cuts because you kept turning up."),
        Sword(id: 7, name: "Proven", requirement: 60,
              note: "Sixty days. Long enough that it is no longer being tested."),
        Sword(id: 8, name: "Honed", requirement: 90,
              note: "Ninety days. An edge that has been kept, not one that arrived."),
        Sword(id: 9, name: "Enduring", requirement: 180,
              note: "Half a year. It wears in now, rather than down."),
    ]
}

// MARK: - Store

/// The one place the app agrees on which blades you own, which one is new, and
/// which one you carry.
///
/// This used to be answered in three places that never spoke to each other:
/// `BladeViewModel.equippedID`, which the collection wrote; a stored
/// `Sword.isEquipped` flag that nothing ever updated after launch; and
/// `ForgeViewModel.equippedSwordID`, which was what the sword in the stone
/// actually read. Tapping a card moved the first, so the collection changed and
/// the stone kept whatever it had. Everything is derived from `equippedID` now,
/// so there is nothing left to keep in sync.
@Observable
final class SwordStore {

    /// The history the blades are earned out of.
    private let progress: ProgressStore
    private let defaults: UserDefaults

    /// The single source of truth for what you carry. Every screen derives from
    /// this.
    private(set) var equippedID: Int = 1 { didSet { persist() } }

    /// Blades the user has looked at in the collection. Drives the unseen mark
    /// on a card, and nothing else.
    private(set) var acknowledgedIDs: Set<Int> = [] { didSet { persist() } }

    /// Blades whose celebration has already played.
    ///
    /// Deliberately not the same set as `acknowledgedIDs`. Seeing the overlay
    /// and having gone and looked at the card are two different things, and the
    /// celebration used to be gated on the second one: declining a new blade
    /// with "Keep <current>" left it unacknowledged on purpose, so the mark on
    /// the card would still walk somebody over to the collection — but that also
    /// left it unclaimed, and the same full-screen celebration came back every
    /// single day until they went. Splitting the two facts keeps the mark
    /// and ends the replay.
    private(set) var celebratedIDs: Set<Int> = [] { didSet { persist() } }

    /// A blade has just been earned and its celebration has not been shown yet.
    var pendingUnlock: Sword?

    private var isLoaded = false

    private enum Key {
        static let equipped = "forge.equippedSword.v1"
        static let acknowledged = "forge.acknowledgedSwords.v1"
        static let celebrated = "forge.celebratedSwords.v1"
    }

    init(progress: ProgressStore, defaults: UserDefaults = ForgeShared.defaults) {
        self.progress = progress
        self.defaults = defaults
        load()
    }

    private func load() {
        defer { isLoaded = true }
        if defaults.object(forKey: Key.equipped) != nil {
            let saved = defaults.integer(forKey: Key.equipped)
            if Sword.collection.contains(where: { $0.id == saved }) { equippedID = saved }
        }
        if let seen = defaults.array(forKey: Key.acknowledged) as? [Int] {
            acknowledgedIDs = Set(seen)
        }
        if let shown = defaults.array(forKey: Key.celebrated) as? [Int] {
            celebratedIDs = Set(shown)
            return
        }
        // Nothing written yet: this install predates the split. Every blade
        // already earned has had its celebration — that is what `claimBlades`
        // does on every extraction — so seeding from what is unlocked stops the
        // upgrade itself from replaying a fortnight of them.
        celebratedIDs = Set(swords.filter(\.isUnlocked).map(\.id))
    }

    private func persist() {
        guard isLoaded else { return }
        defaults.set(equippedID, forKey: Key.equipped)
        defaults.set(Array(acknowledgedIDs), forKey: Key.acknowledged)
        defaults.set(Array(celebratedIDs), forKey: Key.celebrated)
    }

    // MARK: Reading

    /// Days kept — the only thing that earns a blade. Counted out of the
    /// history rather than stored, so it cannot drift from it.
    var daysKept: Int { progress.daysKept }

    var swords: [Sword] {
        Sword.collection.map { sword in
            var resolved = sword
            resolved.isUnlocked = daysKept >= sword.requirement
            return resolved
        }
    }

    /// Unlocked, but not yet seen in the collection. Drives the NEW badge, and
    /// clears the moment the card is tapped or the blade is equipped. The
    /// starter blade is given rather than earned, so it never arrives as news.
    var newIDs: Set<Int> {
        Set(swords.filter { $0.isUnlocked && $0.requirement > 0 }.map(\.id))
            .subtracting(acknowledgedIDs)
    }

    var equipped: Sword {
        swords.first { $0.id == equippedID } ?? swords[0]
    }

    /// What the stone scene draws.
    var equippedSceneAsset: String { equipped.litAsset }

    func isEquipped(_ id: Int) -> Bool { id == equippedID }
    func isNew(_ id: Int) -> Bool { newIDs.contains(id) }

    /// Blades that were **earned**, which is not the same as blades that exist.
    ///
    /// The Starter is given. It requires nought days, everybody has it before
    /// they have done anything, and counting it made the collection open on
    /// "one of seven" for somebody who had kept no days at all — a score they
    /// were awarded for installing an app. Worse, it made the last one read
    /// "seven of seven", which turns a practice into a set that can be
    /// completed and then has nothing left to say.
    ///
    /// So the count is over what the practice produced. The Starter stays in
    /// the grid and stays equippable — it is plain steel and somebody may want
    /// to carry it, and removing it outright would take that away — but it is
    /// no longer evidence of anything and no longer counted as such.
    var ownedCount: Int { earnable.filter(\.isUnlocked).count }
    var ownedLabel: String { "\(ownedCount) of \(earnable.count)" }

    /// Every blade with a day count behind it.
    var earnable: [Sword] { swords.filter { $0.requirement > 0 } }

    /// The next blade still to earn, if any remain.
    var nextLocked: Sword? { swords.first { !$0.isUnlocked } }

    /// 0…1 toward the next blade.
    var nextProgress: Double {
        guard let next = nextLocked, next.requirement > 0 else { return 0 }
        return min(1, Double(daysKept) / Double(next.requirement))
    }

    // MARK: Writing

    /// Carry a blade. Ignored for blades that are not owned, so a locked card
    /// can be tapped safely — it just tells the user what it costs.
    func equip(_ id: Int) {
        guard let sword = swords.first(where: { $0.id == id }), sword.isUnlocked else { return }
        acknowledge(id)
        guard id != equippedID else { return }
        withAnimation(.smooth(duration: 0.42)) {
            equippedID = id
        }
    }

    /// Take on what another device knows about the blades.
    ///
    /// The two sets have already been unioned by the merge — seeing a blade and
    /// being shown its celebration are both things that have happened and
    /// cannot un-happen — so this is a straight assignment. What it prevents is
    /// the phone that syncs second replaying a fortnight of unlock overlays for
    /// blades that were celebrated on the first one.
    func adopt(equippedID id: Int, acknowledgedIDs seen: Set<Int>, celebratedIDs shown: Set<Int>) {
        if Sword.collection.contains(where: { $0.id == id }) { equippedID = id }
        acknowledgedIDs = seen
        celebratedIDs = shown
    }

    /// The user has seen this blade; drop its NEW badge.
    func acknowledge(_ id: Int) {
        guard newIDs.contains(id) else { return }
        withAnimation(.easeOut(duration: 0.35)) {
            _ = acknowledgedIDs.insert(id)
        }
    }

    /// Queue the celebration for whatever the day just earned.
    ///
    /// Called only when a day is banked, never on launch — the record of
    /// the extraction is what unlocks the blade, and replaying that on every
    /// cold start would throw the same party every day. Earning two at once is
    /// still one moment rather than two overlays fighting each other.
    @discardableResult
    func claimBlades() -> Bool {
        let earned = swords.filter {
            $0.isUnlocked && $0.requirement > 0 && !celebratedIDs.contains($0.id)
        }
        guard let best = earned.max(by: { $0.requirement < $1.requirement }) else { return false }
        // Animated so the celebration fades up rather than appearing whole.
        withAnimation(.easeInOut(duration: 0.4)) {
            pendingUnlock = best
        }
        return true
    }

    /// The celebration is over, whichever button ended it.
    ///
    /// Claiming happens here rather than when the overlay is raised, so a blade
    /// earned by somebody who force-quits mid-animation still gets its moment
    /// the next time round. Once this has run it never comes back: a celebration
    /// is a one-off, and the only thing that raises another is another blade.
    ///
    /// **Everything the shown blade stood on is claimed with it.** `claimBlades`
    /// shows only the best of what is waiting, so "two at once is one moment" —
    /// and it was only half true: the lesser blade stayed uncelebrated and
    /// played its own party on the next day kept. Two at once used to need a
    /// sync; since 1.1 it is every long practice meeting Honed and Enduring on
    /// the first day it keeps after the update, so the lesser one would have
    /// arrived the morning after the greater. It is marked here instead, and it
    /// keeps its unseen dot in the collection (`newIDs`), which is what walks
    /// somebody over to it.
    func dismissCelebration() {
        guard let shown = pendingUnlock else { return }
        let beneath = swords.filter { $0.isUnlocked && $0.requirement <= shown.requirement }
        celebratedIDs.formUnion(beneath.map(\.id) + [shown.id])
        withAnimation(.easeInOut(duration: 0.32)) {
            pendingUnlock = nil
        }
    }
}

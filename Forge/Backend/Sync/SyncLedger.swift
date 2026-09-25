import Foundation

/// The sync engine's own bookkeeping, and none of the user's data.
///
/// Four facts and a set of change stamps. Kept apart from everything the app
/// stores because it is the one thing here that is genuinely disposable: throw
/// all of it away and the next sync is slower and completely correct, which is
/// exactly the property you want from a cache.
final class SyncLedger {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = ForgeShared.defaults) {
        self.defaults = defaults
    }

    private enum Key {
        /// Which account these cursors describe. A different one signing in
        /// makes every number below meaningless.
        static let owner = "forge.sync.owner.v1"
        /// The server's arrival time of the newest row this device has seen.
        static let pullCursor = "forge.sync.pullCursor.v1"
        /// The high-water mark of local changes the server has confirmed.
        static let pushedThrough = "forge.sync.pushedThrough.v1"
        /// The account that received this install's pre-existing local data.
        static let migrated = "forge.sync.migratedForUser.v1"
        /// Content fingerprints, so a change can be dated without every store
        /// in the app having to date itself.
        static let stamps = "forge.sync.stamps.v1"
        /// Activities thrown away, and when.
        static let tombstones = "forge.sync.tombstones.v1"
        /// Identities thrown away, and when.
        ///
        /// A second dictionary rather than a shared one, and the reason is not
        /// tidiness. `LivePracticeBridge.definitions` turns every entry in the
        /// activity dictionary into an `ActivityRow` with `is_deleted` set, so
        /// an identity id sitting in there would be uploaded as the deletion of
        /// an activity that never existed — into a different table, under a
        /// primary key that means something else. Two kinds of tombstone go to
        /// two tables, so they are two lists.
        static let identityTombstones = "forge.sync.identityTombstones.v1"
    }

    // MARK: - Cursors

    var ownerUserID: String? {
        get { defaults.string(forKey: Key.owner) }
        set { write(newValue, Key.owner) }
    }

    var pullCursor: Date? {
        get { defaults.object(forKey: Key.pullCursor) as? Date }
        set { write(newValue, Key.pullCursor) }
    }

    var pushedThrough: Date? {
        get { defaults.object(forKey: Key.pushedThrough) as? Date }
        set { write(newValue, Key.pushedThrough) }
    }

    /// Nil removes rather than stores.
    ///
    /// `set(_:forKey:)` does treat a nil as a removal, but not obviously enough
    /// to leave implicit in the one place where "the cursor is cleared" has to
    /// actually be true — a cursor that survives being set to nil would make a
    /// second account's first sync ask for a delta against the first account's
    /// history.
    private func write(_ value: Any?, _ key: String) {
        guard let value else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(value, forKey: key)
    }

    /// The account this install's existing local practice was uploaded into.
    ///
    /// The whole of "migration happens once", and the reason it is a user id
    /// rather than a boolean. Somebody who signs out and signs back in as
    /// themselves must not re-upload anything, and somebody who signs in as a
    /// *different* account on the same phone must not have the first person's
    /// days poured into their account. Both fall out of comparing this to
    /// whoever just signed in.
    var migratedUserID: String? {
        get { defaults.string(forKey: Key.migrated) }
        set { defaults.set(newValue, forKey: Key.migrated) }
    }

    // MARK: - Owner

    /// Which of the three things just happened.
    enum Adoption: Equatable {
        /// The account this ledger already describes. Ask for a delta.
        case unchanged
        /// Nothing has ever been uploaded from this install. Everything local
        /// is unsent, which is what makes the first sign-in a migration.
        case first
        /// A different account on a phone whose practice already belongs to
        /// another one.
        case switched
    }

    /// Point the ledger at an account.
    ///
    /// The third case is the one worth spelling out. Somebody signs out and a
    /// different person signs in on the same phone: the days sitting in
    /// local storage are the *first* person's, and they are already in the
    /// first person's account. Treating them as unsent would pour one person's
    /// practice into another person's cloud, permanently and invisibly.
    ///
    /// So on a switch the watermark is set to now rather than cleared: nothing
    /// that already exists on this phone counts as outstanding, and only what
    /// happens from here goes up. Nothing local is deleted — this is somebody
    /// else's device to sort out, and destroying a year of days to tidy up
    /// after a sign-in is not a trade any app gets to make on its own.
    ///
    /// The test is whether this install has *ever* handed its local pile to an
    /// account, not whether it handed it to this one. Once it has, a change of
    /// owner is a switch even if the new owner is somebody who was here before:
    /// alice, then bob, then alice again would otherwise upload the days
    /// bob's phone merged in — into alice's account, under alice's name, for
    /// good.
    ///
    /// Signing out and back in as the same person is not a change of owner at
    /// all, so it takes the `.unchanged` path above and re-uploads nothing.
    @discardableResult
    func adopt(userID: String, now: Date = .now) -> Adoption {
        guard ownerUserID != userID else { return .unchanged }

        // Deliberately not clearing the stamps. They describe local content,
        // not the account, and keeping them means signing into a second account
        // does not make every local value look like it changed a moment ago.
        pullCursor = nil
        let isSwitch = migratedUserID != nil
        pushedThrough = isSwitch ? now : nil
        ownerUserID = userID
        return isSwitch ? .switched : .first
    }

    /// The account is gone, so everything that describes a relationship with it
    /// is meaningless.
    ///
    /// Not what a sign-out does, and the difference matters. Signing out leaves
    /// all of this alone so that signing back in as yourself resumes rather than
    /// re-uploads. Deleting the account means there is nothing to resume: the
    /// next sign-in is a first sign-in, and the practice still on this phone —
    /// which deletion deliberately leaves where it is — has to count as unsent
    /// all over again, or it would never reach the new account.
    ///
    /// The stamps are kept. They date local content, which has not changed and
    /// whose history is still accurate.
    func forgetAccount() {
        ownerUserID = nil
        pullCursor = nil
        pushedThrough = nil
        migratedUserID = nil
    }

    // MARK: - Change stamps

    /// What the ledger dates. Spelled out here rather than as string literals
    /// at two call sites, because a stamp read under one key and written under
    /// another is a bug that looks exactly like a value that keeps changing.
    enum StampKey {
        static let settings = "settings"
        static let arrangement = "arrangement"
        static let blades = "blades"

        static func activity(_ id: String) -> String { "activity.\(id)" }
        /// Prefixed separately from `activity` even though identity ids already
        /// carry their own `identity.` prefix. The prefix here says which *kind
        /// of thing* the ledger is dating, and relying on the id's own shape to
        /// keep two namespaces apart is the kind of coupling that survives right
        /// up until somebody changes how an id is minted.
        static func identity(_ id: String) -> String { "identity.\(id)" }
    }

    private struct Stamp: Codable {
        var fingerprint: String
        var at: Date
    }

    /// When this content was first seen.
    ///
    /// Reading has a side effect, which is unusual and is the point: the
    /// question "when did this change" can only be answered by something that
    /// remembers what it looked like last time, and this is that something.
    /// Same fingerprint, same answer as before; a new one, and the answer is
    /// now.
    func stamp(for key: String, fingerprint: String, now: Date = .now) -> Date {
        var stamps = allStamps()
        if let existing = stamps[key], existing.fingerprint == fingerprint {
            return existing.at
        }
        // A value this ledger has never met, on an install that has never sent
        // anything anywhere, is not a change — it is the first time anybody
        // asked. Dating it *now* is a claim the phone is in no position to
        // make, and it is the wrong one twice over: the day-start on a fresh
        // install is four in the morning because that is what Forge ships, not
        // because somebody chose it this second. Signing in on a new phone
        // would then have that untouched default beat the hour its owner
        // actually picked last spring — and beat it on every device, because a
        // value that wins a merge is a value that gets uploaded.
        //
        // Dating it from the beginning of time says the true thing: this is as
        // old as the app, and anything anybody has genuinely done outranks it.
        // Once a push has been confirmed the ledger is no longer meeting the
        // practice for the first time, and a key it has not seen really is new
        // — an activity somebody just made — so it is dated now and goes up.
        let isFirstLook = stamps[key] == nil && pushedThrough == nil
        let at = isFirstLook ? .distantPast : now
        stamps[key] = Stamp(fingerprint: fingerprint, at: at)
        write(stamps)
        return at
    }

    /// Record a stamp we already know, rather than one discovered by looking.
    ///
    /// Used after a merge lands: the value on the phone has just changed, but
    /// it changed *into* something the server already had, and dating it now
    /// would make it look like a local edit that needs sending straight back.
    func setStamp(for key: String, fingerprint: String, at: Date) {
        var stamps = allStamps()
        stamps[key] = Stamp(fingerprint: fingerprint, at: at)
        write(stamps)
    }

    private func allStamps() -> [String: Stamp] {
        guard let data = defaults.data(forKey: Key.stamps),
              let decoded = try? JSONDecoder().decode([String: Stamp].self, from: data)
        else { return [:] }
        return decoded
    }

    private func write(_ stamps: [String: Stamp]) {
        guard let data = try? JSONEncoder().encode(stamps) else { return }
        defaults.set(data, forKey: Key.stamps)
    }

    /// Drop stamps for keys that no longer exist, so the ledger does not grow
    /// by one entry for every activity anybody has ever made and deleted.
    func pruneStamps(keeping keys: Set<String>) {
        let stamps = allStamps()
        let pruned = stamps.filter { keys.contains($0.key) }
        guard pruned.count != stamps.count else { return }
        write(pruned)
    }

    // MARK: - Tombstones

    /// Activities thrown away on this device, and when.
    ///
    /// Kept here rather than in `ForgeViewModel` because a deleted activity is
    /// not part of a day — it is a fact the cloud needs so that the other
    /// phone does not hand it back, and it has no meaning at all in an app that
    /// never signs in. It is written on deletion regardless, because whether
    /// somebody will sign in later is not knowable at the moment they delete.
    func tombstones() -> [String: Date] {
        (defaults.dictionary(forKey: Key.tombstones) as? [String: Date]) ?? [:]
    }

    func recordTombstone(_ id: String, at: Date = .now) {
        var all = tombstones()
        all[id] = at
        defaults.set(all, forKey: Key.tombstones)
    }

    /// An activity that exists again — remade with the same id, or restored by
    /// a merge that had a newer version of it.
    func clearTombstone(_ id: String) {
        var all = tombstones()
        guard all.removeValue(forKey: id) != nil else { return }
        defaults.set(all, forKey: Key.tombstones)
    }

    /// Identities thrown away on this device, and when.
    ///
    /// The same shape and the same argument as the activity list above — a
    /// deletion has to travel, or the other phone hands it straight back — and
    /// a separate dictionary for the reason spelled out on `Key`.
    ///
    /// Note that retiring an identity is **not** a deletion and never reaches
    /// here: a retired identity is an ordinary row with a date in it, which
    /// merges like any other value. See `Identity.retiredAt`.
    func identityTombstones() -> [String: Date] {
        (defaults.dictionary(forKey: Key.identityTombstones) as? [String: Date]) ?? [:]
    }

    func recordIdentityTombstone(_ id: String, at: Date = .now) {
        var all = identityTombstones()
        all[id] = at
        defaults.set(all, forKey: Key.identityTombstones)
    }

    func clearIdentityTombstone(_ id: String) {
        var all = identityTombstones()
        guard all.removeValue(forKey: id) != nil else { return }
        defaults.set(all, forKey: Key.identityTombstones)
    }
}

/// How long to wait before trying again.
///
/// Deterministic on purpose. Jitter is the right answer for a thousand servers
/// that all restarted at once; this is one phone whose owner is asleep, and the
/// natural jitter of when somebody next picks it up is larger than anything
/// this function could add. Being able to state the schedule in a test is worth
/// more.
enum SyncBackoff {

    /// First retry after half a minute, doubling, and never further apart than
    /// half an hour. The ceiling matters more than the curve: a phone that
    /// comes back into signal should find its way to the server within one
    /// window, not one nap.
    static let base: TimeInterval = 30
    static let ceiling: TimeInterval = 30 * 60

    static func delay(afterFailures failures: Int) -> TimeInterval {
        guard failures > 0 else { return 0 }
        // Capped before the shift so a long run of failures cannot overflow the
        // exponent on its way to a number that was going to be clamped anyway.
        let doublings = min(failures - 1, 16)
        return min(base * pow(2, Double(doublings)), ceiling)
    }
}

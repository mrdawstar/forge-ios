import Foundation

/// The one container the app, the widgets and the Live Activity all read.
///
/// Everything Forge has ever written lived in the app's own `UserDefaults`,
/// which a widget extension cannot see: they are different sandboxes and always
/// were. Moving to an App Group is what makes a widget able to answer "how much
/// of your day is left" at all.
enum ForgeShared {

    /// Must match the App Group on both targets' entitlements. A typo here is
    /// invisible at build time and shows up as a widget that is permanently
    /// empty, which is why nothing else in the app spells it out.
    static let appGroup = "group.com.dawid.forge"

    /// Falls back to the app's own defaults rather than trapping.
    ///
    /// A missing entitlement is a provisioning problem, not a reason to lose
    /// somebody's history: the app keeps working exactly as it did before, and
    /// only the widgets go quiet.
    static let defaults: UserDefaults = UserDefaults(suiteName: appGroup) ?? .standard

    /// Whether the group is actually available. The widgets show their empty
    /// state rather than a wrong one when it is not.
    static var isGroupAvailable: Bool { UserDefaults(suiteName: appGroup) != nil }

    private static let migrationKey = "forge.migratedToAppGroup.v1"

    /// Every key Forge has ever written, in one list.
    ///
    /// Spelled out rather than discovered by prefix: `dictionaryRepresentation`
    /// on the standard suite returns the whole system's defaults for this app,
    /// including keys iOS put there itself, and copying those into a shared
    /// container would be moving somebody else's furniture.
    static let ownedKeys = [
        // History and the shape of the day.
        "forge.history.v1",
        "forge.dayStartHour.v1",
        "forge.restDays.v1",
        // What the day is made of.
        "forge.hasCompletedFirstRun.v1",
        "forge.activeRituals.v1",
        "forge.customRituals.v1",
        "forge.verificationMemory.v1",
        "forge.libraryEdits.v1",
        "forge.commitment.v1",
        // 1.0's single paywall door. Nothing reads it since 1.1 retired the
        // doors (FORGE_CONTEXT §6); kept so an old install's value still has a
        // home rather than being stranded in the old suite.
        "forge.premiumInvited.v1",
        // Forge Pro (1.1). Whether this install ran 1.0 or 1.0.1 (`Founder`),
        // whether the one exit offer has been shown (`ExitOffer`), whether the
        // trial reminder was asked for (`TrialReminder`), and when Forge asked
        // for a rating (`RatingPrompt`).
        "forge.founder.v1",
        "forge.exitOffer.v1",
        "forge.trialReminder.v1",
        "forge.ratingAsked.v1",
        // Whether Forge's AI has been allowed. Stranding it would ask again —
        // or, worse, lose a revocation. See `AIConsentStore`.
        "forge.aiConsent.v1",
        // The markers somebody set for themselves. Not derivable from the
        // history — Forge cannot work out that somebody meant to read for
        // thirty days — so this is the one thing on the Blade tab that is
        // genuinely lost if it is left behind.
        "forge.customMilestones.v1",
        // Blades.
        "forge.equippedSword.v1",
        "forge.acknowledgedSwords.v1",
        "forge.celebratedSwords.v1",
        // The cloud's own bookkeeping. None of it is user data — throwing all
        // of it away costs one slow sync and nothing else — but it is carried
        // across anyway, because leaving it behind would make the launch after
        // an update re-upload a whole history to say nothing new.
        "forge.sync.owner.v1",
        "forge.sync.pullCursor.v1",
        "forge.sync.pushedThrough.v1",
        "forge.sync.migratedForUser.v1",
        "forge.sync.stamps.v1",
        "forge.sync.tombstones.v1",
        // Notifications.
        "forge.notifications.enabled.v1",
        "forge.notifications.wake.v1",
        "forge.notifications.asked.v1",
        "forge.notifications.lastOpened.v1",
        // Health.
        "forge.healthAsked.v1",
    ]

    /// Carry an existing install's data into the group. Once, ever.
    ///
    /// Called from the app and from nowhere else. A widget that ran first would
    /// otherwise migrate its own empty sandbox, set the flag, and strand every
    /// day the user had already earned — the extension has its own
    /// `standard` defaults and they have never held anything.
    @discardableResult
    static func migrateIfNeeded(
        from local: UserDefaults = .standard,
        into shared: UserDefaults = ForgeShared.defaults
    ) -> Int {
        // Nothing to move into: without the group these are the same suite.
        guard shared != local, !shared.bool(forKey: migrationKey) else { return 0 }

        var moved = 0
        for key in ownedKeys {
            guard let value = local.object(forKey: key) else { continue }
            // Never overwrite. If the group already holds a value, it is newer
            // than anything left behind in the old suite.
            guard shared.object(forKey: key) == nil else { continue }
            shared.set(value, forKey: key)
            moved += 1
        }

        // The originals are deliberately left where they are. They cost a few
        // kilobytes and they are the only copy if this ever has to be undone.
        shared.set(true, forKey: migrationKey)
        return moved
    }

    #if DEBUG
    /// Puts the group back to never-migrated, so the one-time path can be run
    /// more than once while it is being checked.
    static func resetMigration(in shared: UserDefaults = ForgeShared.defaults) {
        shared.removeObject(forKey: migrationKey)
    }
    #endif
}

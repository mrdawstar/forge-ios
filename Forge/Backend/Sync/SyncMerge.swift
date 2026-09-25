import Foundation

/// What the server had, as far as this pull could see.
///
/// Deliberately a *delta* and not a picture. An incremental pull asks for
/// everything that has arrived since last time, so a day missing from here
/// means "unchanged since you last looked", never "the server does not have
/// it". Treating it as the latter is how a sync engine deletes a year of
/// somebody's history and reports success.
struct RemotePractice: Equatable, Sendable {
    var settings: LocalPractice.Settings?
    var activities: [LocalPractice.ActivityDefinition] = []
    var arrangement: LocalPractice.Arrangement?
    var days: [DayRecord] = []
    var blades: LocalPractice.Blades?
    var identities: [LocalPractice.IdentityDefinition] = []
    var chapters: [Chapter] = []
    var reviews: [WeeklyReview] = []

    static let none = RemotePractice()

    var isEmpty: Bool {
        settings == nil && arrangement == nil && blades == nil
            && activities.isEmpty && days.isEmpty && identities.isEmpty
            && chapters.isEmpty && reviews.isEmpty
    }
}

/// What the server still needs to be told.
struct UploadSet: Equatable, Sendable {
    var settings: LocalPractice.Settings?
    var activities: [LocalPractice.ActivityDefinition] = []
    var arrangement: LocalPractice.Arrangement?
    var days: [DayRecord] = []
    var blades: LocalPractice.Blades?
    var identities: [LocalPractice.IdentityDefinition] = []
    var chapters: [Chapter] = []
    var reviews: [WeeklyReview] = []

    var isEmpty: Bool {
        settings == nil && arrangement == nil && blades == nil
            && activities.isEmpty && days.isEmpty && identities.isEmpty
            && chapters.isEmpty && reviews.isEmpty
    }
}

struct PracticeMerge: Equatable, Sendable {
    /// What the phone should now hold.
    var practice: LocalPractice
    var upload: UploadSet
}

/// The rules, and nothing else.
///
/// Every function here is `static`, takes values, returns values, and touches
/// no clock, no network and no store. That is not tidiness — it is the only way
/// a merge can be trusted. Conflict resolution is the one part of a sync engine
/// that is genuinely hard to get right and genuinely impossible to check by
/// using the app, because the interesting cases need two phones, an aeroplane
/// and a fortnight. Written like this, all of them are a unit test.
///
/// Three rules, applied everywhere:
///
///  1. **Newer wins.** Every record carries the moment the *user* changed it.
///  2. **On an exact tie, the server wins.** Not "local wins" and not "the
///     bigger one wins": every device sees the same server row, so agreeing to
///     defer to it is the only tie-break that makes two phones converge on the
///     same answer without talking to each other.
///  3. **Sets are unioned, never replaced.** Completions, blades seen, blades
///     celebrated. These only ever grow in real life, and a union cannot lose
///     work done on the phone that happened to sync second.
///  4. **A practice that is not this account's does not take part.** All three
///     rules above decide between two versions of *the same person's* work. When
///     a different account signs in on a phone, the pile sitting in local
///     storage is the previous holder's and there is nothing to resolve: they
///     get their own practice back, whole, and none of it travels either way.
///
/// Note what rules 1–3 rest on, because it is easy to assume something
/// stronger. "This device already pushed that value" does **not** mean the
/// server still holds it: an upsert replaces a whole row, so another device
/// syncing a stale version overwrites ours. That is exactly why a merge that
/// produces something the server lacks is sent back up, and why the watermark
/// only ever decides what is *offered*, never who wins.
enum SyncMerge {

    // MARK: - Everything

    /// Merge one pull into the local practice, and work out what still has to
    /// go up.
    ///
    /// `pushedThrough` is the high-water mark of what this device has confirmed
    /// the server received. Anything changed after it is dirty and gets sent.
    /// Passing nil means "nothing has ever gone up from here" — which makes the
    /// first sign-in migration not a special path at all, just this function
    /// with an empty watermark. That is deliberate: a migration written as its
    /// own code path is a second sync engine that only runs once, on the day
    /// somebody's data matters most, and is therefore the least exercised code
    /// in the app.
    static func merge(
        local: LocalPractice,
        remote: RemotePractice,
        pushedThrough: Date?,
        localIsForeign: Bool = false
    ) -> PracticeMerge {
        guard !localIsForeign else {
            return PracticeMerge(practice: handOver(to: remote, on: local), upload: UploadSet())
        }

        var practice = local
        var upload = UploadSet()

        // MARK: Settings
        if let incoming = remote.settings {
            let merged = settings(local: local.settings, remote: incoming)
            practice.settings = merged
            if merged != incoming { upload.settings = merged }
        } else if isDirty(local.settings.updatedAt, since: pushedThrough) {
            upload.settings = local.settings
        }

        // MARK: Arrangement
        if let incoming = remote.arrangement {
            let merged = arrangement(local: local.arrangement, remote: incoming)
            practice.arrangement = merged
            if merged != incoming { upload.arrangement = merged }
        } else if isDirty(local.arrangement.updatedAt, since: pushedThrough) {
            upload.arrangement = local.arrangement
        }

        // MARK: Blades
        if let incoming = remote.blades {
            let merged = blades(local: local.blades, remote: incoming)
            practice.blades = merged
            if merged != incoming { upload.blades = merged }
        } else if isDirty(local.blades.updatedAt, since: pushedThrough) {
            upload.blades = local.blades
        }

        // MARK: Activities
        let activityMerge = activities(
            local: local.activities, remote: remote.activities, pushedThrough: pushedThrough
        )
        practice.activities = activityMerge.merged
        upload.activities = activityMerge.upload

        // MARK: Days
        let dayMerge = days(
            local: local.days, remote: remote.days, pushedThrough: pushedThrough
        )
        practice.days = dayMerge.merged
        upload.days = dayMerge.upload

        // MARK: Identities
        let identityMerge = identities(
            local: local.identities, remote: remote.identities, pushedThrough: pushedThrough
        )
        practice.identities = identityMerge.merged
        upload.identities = identityMerge.upload

        // MARK: Chapters
        let chapterMerge = chapters(
            local: local.chapters, remote: remote.chapters, pushedThrough: pushedThrough
        )
        practice.chapters = chapterMerge.merged
        upload.chapters = chapterMerge.upload

        // MARK: Reviews
        let reviewMerge = reviews(
            local: local.reviews, remote: remote.reviews, pushedThrough: pushedThrough
        )
        practice.reviews = reviewMerge.merged
        upload.reviews = reviewMerge.upload

        return PracticeMerge(practice: practice, upload: upload)
    }

    /// Nothing has ever been pushed, or this changed after the last push.
    private static func isDirty(_ at: Date, since watermark: Date?) -> Bool {
        guard let watermark else { return true }
        return at > watermark
    }

    /// A different account has signed in on this phone.
    ///
    /// The whole of rule 4, and deliberately not a merge. Two people's days
    /// unioned into one day is not a conflict resolved, it is one person's
    /// practice filed under another person's name — and because the merged row
    /// then differs from the server's, it would be uploaded, permanently and
    /// invisibly. So nothing local is considered and nothing local is offered:
    /// the account gets what the account has.
    ///
    /// Replacing what is on the phone is safe by construction rather than by
    /// hope. This path is only ever reached when the ledger has already handed
    /// this install's practice to some account — that is what `migratedUserID`
    /// records — so the previous holder's days are in the previous holder's
    /// cloud, and signing back in brings them down again.
    ///
    /// Where the account has no row yet — a brand-new one whose first sync has
    /// not happened — the phone keeps what it is showing rather than blanking
    /// the screen. Nothing of it is uploaded, so it stays this device's business
    /// until its new owner changes it and makes it genuinely theirs.
    private static func handOver(
        to remote: RemotePractice,
        on local: LocalPractice
    ) -> LocalPractice {
        LocalPractice(
            settings: remote.settings ?? local.settings,
            activities: remote.activities,
            arrangement: remote.arrangement ?? local.arrangement,
            days: remote.days,
            blades: remote.blades ?? local.blades,
            // Taken wholesale like the activities and the days, and for the
            // stronger version of the same reason. An identity is the most
            // personal sentence in the app; leaving the previous holder's on
            // screen for the person who just signed in would be the app telling
            // somebody they are becoming a stranger.
            identities: remote.identities,
            // Same rule, and the same reason twice over: a chapter is a stretch
            // of somebody's life with their name on it and a review is two
            // sentences they wrote about their own week. Neither may survive an
            // account change on the screen of the person who just signed in.
            chapters: remote.chapters,
            reviews: remote.reviews
        )
    }

    // MARK: - Days

    struct DayOutcome: Equatable, Sendable {
        var merged: [DayRecord]
        var upload: [DayRecord]
    }

    static func days(
        local: [DayRecord],
        remote: [DayRecord],
        pushedThrough: Date?
    ) -> DayOutcome {
        var byDay = Dictionary(local.map { ($0.day, $0) }, uniquingKeysWith: { _, latest in latest })
        var upload: [ForgeDay: DayRecord] = [:]

        // Anything changed since the last confirmed push goes up regardless of
        // what came down — the server may simply not have it yet.
        for record in local where isDirty(record.stamp, since: pushedThrough) {
            upload[record.day] = record
        }

        for incoming in remote {
            guard let mine = byDay[incoming.day] else {
                // A day this phone has never seen. Nothing to resolve.
                byDay[incoming.day] = incoming
                upload[incoming.day] = nil
                continue
            }
            let merged = day(local: mine, remote: incoming)
            byDay[incoming.day] = merged
            // Only send it back if the merge actually produced something the
            // server does not have. Echoing every row we just received is how
            // two phones keep each other awake.
            if merged != incoming {
                upload[incoming.day] = merged
            } else {
                upload[incoming.day] = nil
            }
        }

        return DayOutcome(
            merged: byDay.values.sorted { $0.day < $1.day },
            upload: upload.values.sorted { $0.day < $1.day }
        )
    }

    /// One day, resolved.
    ///
    /// Completions are unioned and never replaced, and that is the single most
    /// consequential decision in this file. Two phones, one day, no signal:
    /// push-ups ticked off on the phone, reading ticked off on the iPad. Under
    /// last-writer-wins one of those is simply gone, and the person who did the
    /// work has no way to know which. Under a union, both are kept.
    ///
    /// The cost is honest and worth stating: undoing an activity does not
    /// travel. If it is undone here and the other device still has it, the next
    /// merge brings it back. That is a checkbox somebody re-taps, against a
    /// day's work somebody never gets back, and the trade only goes one way.
    static func day(local: DayRecord, remote: DayRecord) -> DayRecord {
        // The server wins an exact tie, so `>` rather than `>=`.
        let winner = local.stamp > remote.stamp ? local : remote
        var merged = winner

        // Union by activity, keeping the earliest time it was finished. A
        // completion is a fact about a moment, and the earlier record of it is
        // the truer one.
        var completions: [String: DayRecord.Completion] = [:]
        for completion in local.completions + remote.completions {
            // `<` and not `<=`: on an identical instant the later of the two
            // iterations wins, and remote is iterated second. That is rule 2
            // applied one level down — the two sides carry the same moment but
            // may disagree about the method, and both devices have to resolve
            // that the same way or the row never settles.
            if let existing = completions[completion.ritualID], existing.at < completion.at {
                continue
            }
            completions[completion.ritualID] = completion
        }
        // Sorted by when they happened, because the order the list shows a
        // finished activity in is the order it was finished in.
        //
        // The id breaks a tie. Two activities banked in the same sweep are
        // microseconds apart and the wire keeps milliseconds, so they arrive
        // back sharing an instant — and a dictionary's values in an unstable
        // sort would then order them differently on each device and each
        // launch. The merged row would never equal the row that produced it,
        // and the two phones would trade the same day between them for as
        // long as they both had signal.
        merged.completions = completions.values.sorted {
            ($0.at, $0.ritualID) < ($1.at, $1.ritualID)
        }

        // A day earned on both devices was earned at the earlier of the two
        // times. Where only one side has it, the winner's answer stands —
        // including a nil, which is somebody deliberately putting the blade
        // back.
        if let mine = local.extractedAt, let theirs = remote.extractedAt {
            merged.extractedAt = min(mine, theirs)
        }

        merged.plannedIDs = winner.plannedIDs
        // Not `now`. Re-merging the same two records has to produce the same
        // record, or every sync would find something new to upload and two
        // phones would trade the same day back and forth forever.
        merged.updatedAt = max(local.stamp, remote.stamp)

        return merged
    }

    // MARK: - Activities

    struct ActivityOutcome: Equatable, Sendable {
        var merged: [LocalPractice.ActivityDefinition]
        var upload: [LocalPractice.ActivityDefinition]
    }

    /// Straight last-writer-wins per id, tombstones included.
    ///
    /// A deletion is not a special case here — it is an ordinary newer write
    /// whose `isDeleted` happens to be true. That is what stops a thrown-away
    /// activity from being handed back by the other phone, and it is why the
    /// table has an `is_deleted` column rather than a `DELETE`.
    static func activities(
        local: [LocalPractice.ActivityDefinition],
        remote: [LocalPractice.ActivityDefinition],
        pushedThrough: Date?
    ) -> ActivityOutcome {
        var byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        var upload: [String: LocalPractice.ActivityDefinition] = [:]

        for definition in local where isDirty(definition.updatedAt, since: pushedThrough) {
            upload[definition.id] = definition
        }

        for incoming in remote {
            guard let mine = byID[incoming.id] else {
                byID[incoming.id] = incoming
                upload[incoming.id] = nil
                continue
            }
            let merged = mine.updatedAt > incoming.updatedAt ? mine : incoming
            byID[incoming.id] = merged
            upload[incoming.id] = merged == incoming ? nil : merged
        }

        return ActivityOutcome(
            merged: byID.values.sorted { $0.id < $1.id },
            upload: upload.values.sorted { $0.id < $1.id }
        )
    }

    // MARK: - Identities

    struct IdentityOutcome: Equatable, Sendable {
        var merged: [LocalPractice.IdentityDefinition]
        var upload: [LocalPractice.IdentityDefinition]
    }

    /// Last-writer-wins per id, tombstones included — the same shape as
    /// `activities`, deliberately, because it is the same problem.
    ///
    /// **Retirement is a value, not a deletion, and it is unioned.** Retiring is
    /// a thing that has happened and cannot un-happen, so it is treated the way
    /// an acknowledged blade is: whichever side has it, the merge keeps it. That
    /// matters because of the cap. Somebody at three active identities on their
    /// phone retires one and names a fourth; the iPad, offline, still has the
    /// old three. Under plain last-writer-wins the iPad's newer edit to some
    /// other field could resurrect the retired one, and the account would come
    /// back holding four active identities — a state the app promises is
    /// unreachable and has no way to resolve.
    ///
    /// The earlier of two retirement dates wins, for the same reason
    /// `extractedAt` takes the earlier of two: it is a fact about a moment, and
    /// the earlier record of it is the truer one.
    ///
    /// Restoring one is therefore the operation that does **not** travel, and
    /// that is the honest trade. It is one tap to redo against a cap that would
    /// otherwise be silently broken by a device that had been in a drawer.
    static func identities(
        local: [LocalPractice.IdentityDefinition],
        remote: [LocalPractice.IdentityDefinition],
        pushedThrough: Date?
    ) -> IdentityOutcome {
        var byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        var upload: [String: LocalPractice.IdentityDefinition] = [:]

        for definition in local where isDirty(definition.updatedAt, since: pushedThrough) {
            upload[definition.id] = definition
        }

        for incoming in remote {
            guard let mine = byID[incoming.id] else {
                byID[incoming.id] = incoming
                upload[incoming.id] = nil
                continue
            }
            var merged = mine.updatedAt > incoming.updatedAt ? mine : incoming
            merged.retiredAt = earliest(mine.retiredAt, incoming.retiredAt)
            // A deletion is the one thing that outranks everything, on either
            // side. It is already carried by last-writer-wins whenever the
            // deletion is the newer write; this makes it true when it is not,
            // so an identity thrown away on one phone is not handed back by an
            // older device that merely edited its symbol afterwards.
            merged.isDeleted = mine.isDeleted || incoming.isDeleted
            merged.updatedAt = max(mine.updatedAt, incoming.updatedAt)
            byID[incoming.id] = merged
            upload[incoming.id] = merged == incoming ? nil : merged
        }

        return IdentityOutcome(
            merged: byID.values.sorted { $0.createdAt < $1.createdAt },
            upload: upload.values.sorted { $0.id < $1.id }
        )
    }

    // MARK: - Chapters and reviews

    struct ChapterOutcome: Equatable, Sendable {
        var merged: [Chapter]
        var upload: [Chapter]
    }

    /// Last-writer-wins per id, with **closing unioned** — the same shape
    /// identities use, and for the same kind of reason.
    ///
    /// A chapter that has been closed cannot un-close: it is a fact about a
    /// moment, exactly like a retirement or an extraction, so whichever side has
    /// it keeps it and the earlier of two closing dates wins. Without that, a
    /// phone left in a drawer that merely renamed the chapter afterwards would
    /// reopen six weeks somebody had deliberately finished — and the app would
    /// then hold two open chapters, a state `ChapterStore` promises is
    /// unreachable.
    static func chapters(
        local: [Chapter],
        remote: [Chapter],
        pushedThrough: Date?
    ) -> ChapterOutcome {
        var byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        var upload: [String: Chapter] = [:]

        for chapter in local where isDirty(chapter.updatedAt, since: pushedThrough) {
            upload[chapter.id] = chapter
        }

        for incoming in remote {
            guard let mine = byID[incoming.id] else {
                byID[incoming.id] = incoming
                upload[incoming.id] = nil
                continue
            }
            var merged = mine.updatedAt > incoming.updatedAt ? mine : incoming
            merged.closedAt = earliest(mine.closedAt, incoming.closedAt)
            merged.updatedAt = max(mine.updatedAt, incoming.updatedAt)
            byID[incoming.id] = merged
            upload[incoming.id] = merged == incoming ? nil : merged
        }

        return ChapterOutcome(
            merged: byID.values.sorted { $0.openedAt < $1.openedAt },
            upload: upload.values.sorted { $0.id < $1.id }
        )
    }

    struct ReviewOutcome: Equatable, Sendable {
        var merged: [WeeklyReview]
        var upload: [WeeklyReview]
    }

    /// Last-writer-wins per week, and nothing is unioned.
    ///
    /// Two devices cannot both hold a *different* answer to the same week
    /// without one of them being later, and the later one is the one somebody
    /// meant — these are two sentences a person typed, and merging the text of
    /// two versions would produce a paragraph neither of them wrote.
    ///
    /// There is no tombstone. A review is never deleted: `dismiss` writes a row
    /// with no answers rather than removing one, so "I skipped that week" and
    /// "that week has not been offered yet" stay different facts on every
    /// device.
    static func reviews(
        local: [WeeklyReview],
        remote: [WeeklyReview],
        pushedThrough: Date?
    ) -> ReviewOutcome {
        var byWeek = Dictionary(local.map { ($0.weekStart, $0) }, uniquingKeysWith: { _, latest in latest })
        var upload: [ForgeDay: WeeklyReview] = [:]

        for review in local where isDirty(review.updatedAt, since: pushedThrough) {
            upload[review.weekStart] = review
        }

        for incoming in remote {
            guard let mine = byWeek[incoming.weekStart] else {
                byWeek[incoming.weekStart] = incoming
                upload[incoming.weekStart] = nil
                continue
            }
            let merged = mine.updatedAt > incoming.updatedAt ? mine : incoming
            byWeek[incoming.weekStart] = merged
            upload[incoming.weekStart] = merged == incoming ? nil : merged
        }

        return ReviewOutcome(
            merged: byWeek.values.sorted { $0.weekStart < $1.weekStart },
            upload: upload.values.sorted { $0.weekStart < $1.weekStart }
        )
    }

    /// The earlier of two moments, where either may be absent and absent means
    /// "has not happened".
    private static func earliest(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case let (.some(a), .some(b)): min(a, b)
        default: a ?? b
        }
    }

    // MARK: - Settings

    static func settings(
        local: LocalPractice.Settings,
        remote: LocalPractice.Settings
    ) -> LocalPractice.Settings {
        var merged = local.updatedAt > remote.updatedAt ? local : remote

        // Monotonic. Somebody with a year of days arriving on a new phone
        // must never be shown onboarding, whichever row happens to be newer.
        merged.firstRunCompleted = local.firstRunCompleted || remote.firstRunCompleted

        // The tally is a count of times the user disagreed with the classifier
        // on each device, so the union of that experience is the higher of the
        // two. Taking the winner's wholesale would throw away corrections made
        // on the other phone and quietly un-teach it.
        var tally = local.verificationMemory.overrideTally
        for (method, count) in remote.verificationMemory.overrideTally {
            tally[method] = max(tally[method] ?? 0, count)
        }
        merged.verificationMemory.overrideTally = tally

        merged.updatedAt = max(local.updatedAt, remote.updatedAt)
        return merged
    }

    // MARK: - Arrangement

    /// The whole list from whichever side is newer.
    ///
    /// Not a union, and not a merge of orderings. The order *is* the data —
    /// somebody arranged their day — and there is no sensible way to
    /// interleave two arrangements that does not produce a third one nobody
    /// asked for.
    static func arrangement(
        local: LocalPractice.Arrangement,
        remote: LocalPractice.Arrangement
    ) -> LocalPractice.Arrangement {
        var merged = local.updatedAt > remote.updatedAt ? local : remote
        merged.updatedAt = max(local.updatedAt, remote.updatedAt)
        return merged
    }

    // MARK: - Blades

    static func blades(
        local: LocalPractice.Blades,
        remote: LocalPractice.Blades
    ) -> LocalPractice.Blades {
        var merged = local.updatedAt > remote.updatedAt ? local : remote
        // Both are things that have happened and cannot un-happen: a blade you
        // have looked at, a celebration you have already been shown. Unioning
        // them is what stops a fortnight of unlock overlays replaying on the
        // phone that synced second.
        merged.acknowledgedIDs = local.acknowledgedIDs.union(remote.acknowledgedIDs)
        merged.celebratedIDs = local.celebratedIDs.union(remote.celebratedIDs)
        merged.updatedAt = max(local.updatedAt, remote.updatedAt)
        return merged
    }
}

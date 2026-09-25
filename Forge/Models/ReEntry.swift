import Foundation

/// Coming back.
///
/// # The failure this replaces
///
/// Miss five days, open Forge, and the app showed an empty list and a streak
/// reading zero. Everything on screen was a true statement about the last week
/// and every one of them was the wrong thing to say: the number that had gone to
/// nothing was the most prominent object, the day was blank, and the honest read
/// of the whole screen was *you were doing well and you stopped*. That is the
/// moment people delete a habit app, and it is entirely self-inflicted — the
/// same record that produced the dead streak also says two hundred and six days
/// kept, which is both truer and the thing worth saying.
///
/// Banked rest already protects people who are succeeding. This protects the
/// people who are not, which is where the retention actually is.
///
/// # The rules
///
/// - **The streak is not mentioned.** Not shown, not implied, not "your chain
///   ended" — the screen does not know what a streak is.
/// - **Nothing on it can go down.** Days kept is cumulative by construction; a
///   figure that had fallen while somebody was away would be the app charging
///   them for the absence.
/// - **No welcome, no guilt.** Not "Welcome back!", not "We missed you", and not
///   "Let's get back on track". The register is the same flat one everything
///   else uses — see `DaySummary.line(for:)`.
/// - **One thing, small.** Not the day they had before they left. The list they
///   built for a good week is the exact thing that failed, and handing it back
///   whole is asking somebody to resume at the difficulty that stopped them.
enum ReEntry {

    /// How long an absence has to be before it is worth saying anything.
    ///
    /// Three days, and the number is a judgement about what a gap *means*. One
    /// or two days is a weekend, a cold, a birthday — an ordinary shape in a
    /// practice measured in years, and greeting somebody after it would be the
    /// app being twitchy about a Tuesday. Three days is when a person has
    /// usually started telling themselves a story about having stopped, and the
    /// story is what this screen exists to interrupt.
    static let threshold = 3

    /// Whether somebody is coming back rather than simply here.
    ///
    /// - `gap`: days since the last day they kept. Nil means they never have.
    /// - `daysKept`: the cumulative count, which is the whole content of the
    ///   screen — there is nothing to say to somebody with none.
    /// - `isTodayEarned`: a day finished today ends the absence, whatever the
    ///   gap was an hour ago.
    static func isReturning(gap: Int?, daysKept: Int, isTodayEarned: Bool) -> Bool {
        guard let gap, daysKept > 0, !isTodayEarned else { return false }
        return gap >= threshold
    }

    /// What the screen says about the absence.
    ///
    /// **It names the gap and refuses to characterise it.** Saying nothing at
    /// all would be strange — the person knows they have been away — and saying
    /// anything more than the length of it is the app guessing at a life it
    /// cannot see. Somebody was ill, or had a week of work, or simply did not
    /// want to; all three get the same sentence, because the app cannot tell
    /// them apart and should not pretend to.
    static func absence(days gap: Int) -> String {
        switch gap {
        case ..<7: "It has been \(ForgeCount.spelled(gap).lowercased()) days."
        case ..<14: "It has been about a week."
        case ..<35: "It has been a few weeks."
        case ..<90: "It has been a couple of months."
        default: "It has been a while."
        }
    }

    /// The line under the count. Says what the record is, and stops.
    ///
    /// Present tense on purpose. "You have kept two hundred days" is a fact
    /// about the past; "that does not come off the record" is a fact about now,
    /// and now is the thing in question when somebody is deciding whether they
    /// are still a person who does this.
    static func reassurance(daysKept: Int) -> String {
        daysKept == 1
            ? "That day is still on the record. Nothing has been taken off it."
            : "Those days are still on the record. Nothing comes off it."
    }
}

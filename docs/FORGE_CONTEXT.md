# FORGE — Context

> Source of truth for understanding Forge. Read this before changing anything.
> Last verified against the codebase: **2026-09-15** (§2n, the account removed).

---

## ⚠️ Status: read this first

**Release 1.1 is in progress (from 2026-09-29).** Read **§2t** and **§17**
first, then [docs/DIRECTION_1_1.md](DIRECTION_1_1.md), which wins wherever it
disagrees with this file. 1.1 is built in eight sessions (S0–S7); each one adds a
dated subsection to §17. The 1.0 status below is kept as history.

**Forge was feature-complete for 1.0 and had no submission blockers left.**
Last verified against the codebase: **2026-09-15**. Read **§2n** first — it is
the removal of the account, and it is the largest change to what the app *is*
since the archetypes went. Then **§2m**, which is one Info.plist key and the
reason the first upload bounced, then the release pass in **§2l** — which is the section to read first, because it closes the icon and the
URLs, rebuilds every widget around the record instead of a drawing of a sword,
and adds a large family. §2j is the one to read next: it moves Plan off the home
screen, deletes the challenge generator, and changes what the notifications
say.

> **This file had gone out of date and parts of it still are.** Between
> 2026-08-12 and 2026-08-31 the app went through a redesign that this document
> did not follow: **Paths and archetypes were deleted outright**, the **six
> dimensions and the Forge Shape** replaced them, and 1.0 was decided to ship
> with **nothing behind a paywall**. Wherever the sections below describe a
> shelf of worlds, a `ForgePath`, a `PathStore`, a locked archetype or a Premium
> tier, they are describing software that no longer exists. §2g, §2h and §2i
> are written against the code as it stands and are the sections to trust.

The shape of the product today:

```
Forge     the day, the sword scene, Plan, the challenge
Blade     the record: blade, ladder, chapter, heatmap, milestones, analytics
Becoming  the direction: the Shape, what you chose to build, the six
Settings  rest days, appearance, the week, notifications, sound, planning, legal
```

**There is no account.** Not "optional", not "signed out by default" — there is
no sign-in control anywhere in the app and no way to make one. See §2n.

**What is derived and what is stated.** Everything Forge *counts* is read back
out of `DayRecord`s and stored nowhere (§5.2). Everything somebody *said* — the
six they chose to build (`ForgeViewModel.focus`), an identity statement, a
chapter's intention — is stored, and the gap between the two is where the whole
of `DayPlanner` lives.

**Identities are history-only.** The spine (§2a) is intact and load-bearing —
`Ritual.identityID`, the sync table, the challenge's aim, the notification voice
— but the first run no longer asks for one, and the Becoming tab shows the
section only to somebody who already has one. See §2g.

**Live blockers before submission: none.** What is left is a VoiceOver pass and
a run on real hardware, neither of which blocks an upload. See §12.

---

## 1. What Forge is

An iOS app for keeping a daily practice. Not a habit tracker in presentation:
the day is something you **earn**, and the earning is physical.

You keep a short list of activities. When you finish everything today asked for,
a sword in a stone comes **loose** — and you still have to drag it free. That
pull banks the day. Days kept unlock blades; blades and milestones are the
record of the practice.

The app's differentiators, in order:

1. **The sword scene and the pull.** Finishing makes the blade loose; the user
   completes the act. No competitor has this.
2. **The voice.** Restrained, adult, unflattering. Nothing congratulates.
   "Early days." "You stopped deciding a while ago."
3. **Derived-state honesty.** The app structurally cannot lie about what you did.

## 2. "Build what you want to build"

The heart of the product, and the sentence the app now actually says — on the
promise screen of the first run, in one line:

```
Forge is not a habit tracker.
You choose what to build. Forge shows you what you have actually built.
```

That is a **trade**, and both halves are load-bearing. The first half is
`ForgeViewModel.focus`: as many of the six as somebody means, chosen in the
first run and changeable on the Becoming tab (§2h — the cap of three is gone). The second is `ForgeShape`: the same six, scored
on the last four weeks of the record and stored nowhere. Neither can be inferred
from the other — nothing in a history says a person *meant* to become steadier
with people — and **the gap between them is the only place in Forge where advice
can honestly come from.** See §2g and `Models/DayPlanner.swift`.

The older framing, *become who you're becoming*, is not wrong and is not the
question the app asks a stranger any more; §2g records why. What survives of it
is the identity spine (§2a), which is a substrate rather than a screen.

Note `ForgeViewModel.identityLine` is a misnomer predating all of this: it
returns a generic day-count sentence from `DaySummary` and has nothing to do
with `Identity`.

## 2a. The identity spine (built)

The one mechanical idea: **an activity carries the identity it is evidence for.**
That single tag is what later phases hang off.

```
Identity              statement in the user's own words ("Someone who trains"),
  (Models/           symbol, accent (reuses PathAccent), createdAt, retiredAt
   Identity.swift)   ≤ 3 active (Identity.activeLimit)
      │
      │  IdentityPrompt — 7 shipped starting points, data not generated.
      │  Taking one mints an ordinary identity the user owns.
      ▼
IdentityStore         @MainActor @Observable, App Group defaults,
  (Engine/)           "forge.identities.v1", isLoaded guard, no derived state
      │
      ▼
Ritual.identityID     nil = untagged = exactly how the app behaved before.
  RitualEdit          Doubly optional (String??) so "cleared the tag" is
   .identityID        expressible, same as startMinute.
      │
      ▼
ProgressStore         daysOfEvidence(taggedTo:) — DAYS, not completions
  (derived,           evidenceRate(taggedTo:)   — over days it was planned
   never stored)      firstEvidence(taggedTo:)  — where the record starts
      │
      ▼
ForgeViewModel        activityIDs(taggedTo:), daysOfEvidence(for:),
  (identity-named     evidenceRate(for:), firstEvidence(for:),
   wrappers)          setIdentity(_:on:), clearIdentity(_:)
```

**Rules established here that later phases must not break:**

- **Retiring is not deleting.** An identity pursued for eight months explains
  eight months of history. `retire` keeps the row and frees a slot against the
  cap; `delete` is a separate, deliberate act that writes a tombstone. They are
  two methods, not a boolean, so the expensive one cannot be passed by accident.
- **Evidence counts days, not completions.** Three tagged activities finished on
  one Tuesday is one day of evidence. Counting otherwise turns an identity into
  a score.
- **Evidence is retroactive.** The tag lives on the activity, not on each
  completion, so somebody who has run for a year and writes the sentence today
  has a year of evidence. Stamping completions was considered and rejected for
  exactly that reason.
- **`firstEvidence` reads the record, not `createdAt`.** Naming a thing is not
  starting it.
- **Deleting an identity does not clear the tags.** An id that resolves to
  nothing reads as untagged everywhere; clearing them would be a second silent
  edit to somebody's day.
- **Nil must stay ordinary.** Every activity on every phone is untagged. Nothing
  may become required and nothing may read differently for want of a tag.

**Sync.** `identities` table (migration `0005_identities.sql`), `IdentityRow`,
`LocalPractice.IdentityDefinition`, `SyncMerge.identities(...)`, separate
tombstone dict in `SyncLedger` (a shared one would upload identity ids as
*activity* deletions into the wrong table). Merge is last-writer-wins per id,
**except**: `retiredAt` is unioned (earliest wins) and `isDeleted` is unioned.
Retirement is unioned because of the cap — a device that had been in a drawer
could otherwise resurrect a retired identity and leave the account holding four
active ones, a state the app promises is unreachable. The cost is that
*restoring* an identity does not travel; that is one tap to redo against a
silently broken invariant.

`activities.identity_id` also travels, or the spine would not survive a new
phone: the identities would arrive, every activity would land untagged, and
every reading would honestly report zero for a year of practice.

## 2b. The first run (**superseded — see §2g**)

> The six beats and the rules under them still hold. What changed on 2026-08-31
> is the second one: `who` became `build`, and the branch to a world at `shape`
> went with the archetypes long before that. Read this for the rules, §2g for
> what the screens are.

Six beats, under two minutes, still ending with a real pull on the real home
screen. `ForgeViewModel.FirstRunStage` drives it; `FirstRunView` draws it.

```
promise   "Forge is not a habit tracker." / what it does, in one trade
   ↓
who       7 IdentityPrompts + a free-text field. 1–3. Skippable.
   ↓      Button reads "Skip for now" until something is named.
shape     2–3 FREE worlds ranked against what they named, or
   ↓      "I'll build my own day" → choose
   ├────────────────┐
   │                ▼
   │            choose    8 activities DERIVED from the identity, effort
   │              ↓       ascending, each row saying what it is evidence for
   ▼              ▼
metaphor  "The blade is who you're becoming. Every day you keep is a strike."
   ↓
doOne     the smallest thing they chose, named as First evidence for: …
   ↓
pull      real home screen, real blade, first-pull grace
   ↓
closing   names the identity; offers the notification primer once
```

**Rules this beat established:**

- **Every beat is skippable forward and none is destructive.** Skipping `who`
  leaves zero identities, and `IdentityActivities.offered(for: [])` returns the
  shipped eight — the exact list the old first run had. Verified by test, not by
  assertion.
- **Everything written is real.** Real identities, real tagged activities on
  today, a real completion, a real blade. No tutorial state.
- **What is chosen is *today's*, never daily.** `chooseStarters` pinned the three
  already; `pinToTodayOnly` now does the same for a routine taken at `shape`.
  A stranger has not agreed to a five-activity day forever, and a repeat picker
  three screens away is not consent.
- **Only free worlds are offered.** A locked card in onboarding is a paywall in
  front of somebody who has been given nothing yet.
- **Choosing tags.** `chooseStarters(_:identities:)` and `tagImported(_:identities:)`
  write the `identityID`, or the sequence would produce identities and untagged
  activities and every evidence reading would be zero forever.

`IdentityActivities` (in `Models/`) is the one place the activity ladder and the
identity→activity mapping live. `effortOrder` covers every library activity and
decides which activity `firstRunActivity` asks for — **the first thing Forge ever
asks anybody to do should be the smallest thing they chose.** A test holds the
ladder complete.

`PathSuggestion.ranked(for:)` **was a deliberate seam** — it ranked worlds by
overlap between their routine and what the identity asked for, because
`ForgePath` had no affinity field. Phase 3 closed it: it now reads
`ForgePath.affinities` through `PathCatalog.ranked(for:)`, which is the same
ordering the shelf uses, so the first run's offer and the Becoming tab can never
form two opinions.

## 2c. Archetypes and the Becoming tab (**deleted — historical**)

> ⚠️ **None of this exists.** `ForgePath`, `PathCatalog`, `PathStore`,
> `PathDetailView`, `ArchetypeShelf` and every world in them were removed with
> the Shape redesign. `ForgeAccent` survives because `Identity` stores its raw
> values. Kept for the argument it records — why characters were the wrong axis
> — which is worth not relearning.

**Characters became archetypes.** `ForgePath.character` — a person's name, shown
as the kicker — is gone, and `affinities: [IdentityPrompt]` took its place. The
argument, recorded at the top of `ForgePath.swift`: characters are finite,
someone else's, unpersonalisable and aspirationally narrow, and only the first of
those four objections is a legal one. An archetype is a plausible answer to *who
do you want to become*; a character is a costume.

Eight, of which two are free:

| Archetype | Affinities | Routine |
|---|---|---|
| The Beginner (free) | steady, early | the Starter's, verbatim |
| The Operator (free) | early, finishes | the Vigil's, verbatim |
| The Craftsman | builds, present | the Workshop's, verbatim |
| The Athlete | trains, steady | the Standard's, verbatim |
| The Scholar | reads, present | written |
| The Steward | steady, present | written |
| The Builder | finishes, builds | written |
| The Monk | present, early | written |

The four ported routines kept their movements, reasons, task notes, standards,
milestone renames and completion lines. Exactly two sentences changed, both
quotes that were doing an impression rather than holding a belief.

**The binding is the point.** `affinities` is read in four places: the shelf
orders and marks by it, `PathDetailView` says which identity a world is a shape
for (in the user's own words where they wrote one), the first run's offer ranks
by it, and `ForgeViewModel.tagImported(_:identities:archetype:)` files every
activity an import adds under the identity it is evidence for — activity-level
evidence first, the archetype's affinity as the fallback.

**Artwork.** Every character plate was withdrawn. One asset survives —
`dawn-room`, an empty lit room with no figure in it — and it dresses The
Beginner. The other seven ship `PathTheme.undrawn(accent:)`, which renders a
world as its colour rather than as a gap. `PathHero` / `PathSubjectGrade` and the
whole compositing system are untouched and a plate drops straight back in. Four
accents were added (`ink`, `moss`, `tide`, `bone`) so eight worlds still look
like eight places; `PathAccent` and `PathAmbience` are still closed sets, and
three ambience cases are deliberately dormant until their worlds have plates.

**Migration.** `PathID.successors` maps `starter → beginner`, `wayne → operator`,
`ronaldo → athlete`, `stark → craftsman`, resolved on read in
`PathCatalog.path(for:)`. Nobody loses the world they were in. Unknown ids still
fall back to Forge.

**The tab bar** is now `Forge · Blade · Becoming · Settings` — the present, the
record, the direction. `BecomingTabView` holds, in order: the identities and
their evidence, the archetype being walked (or the plain statement that none is,
which is where the deleted Forge card's job went), and the shelf. The shelf is
the same `PathHeroCard` feed as before, extracted to `ArchetypeShelf` — not
rebuilt.

## 2d. One ladder, chapters and the portrait (built)

**Three systems counted the same number.** Seven blades at 0/1/3/7/14/30/60 days
kept, five shipped milestones at 1/7/30/100/365, both drawn on the Blade tab —
"Knight Sword · 7 days" two hundred points above "Seven days · A week of this".
And the visible one ran out at sixty days, which is where long-term retention
starts being worth something.

`Models/Ladder.swift` is now the one progression, read out of days kept:

```
0/1/3/7/14/30/60   the seven blades, at exactly their old thresholds
100 180 365 500 730 1000   BladeState: tempered · patina · honed ·
                           weathered · burnished · old iron
past 1000                  one generated rung a year, forever
```

The metaphor is finally said out loud, on the screen the blade lives on: **the
blade is who you're becoming, and the day is what you strike it with.** The
first seven rungs are the blade being *made*; everything after is what the work
has done to it. `BladeState` is a closed enum carrying a `BladeGrade` applied to
the existing sprite — no new art, and `bespokeAsset` is the hook for the day
there is some. Rung ids reuse the shipped milestone ids (`one`, `seven`,
`thirty`, `hundred`, `year`), so `PathMilestone` renames land on the merged
ladder without a word of the archetype catalog changing.

`Milestone.all` / `Milestone.forge` are **deleted**. What is left in
`Milestone.swift` is the user-authored half, which was never duplicated and is
the best thing on that screen.

**Chapters** (`Models/Chapter.swift`, `Engine/ChapterStore.swift`) are a named
six-week arc — id, name, identityIDs, intention, opened/closed — with every
reading derived (`ChapterReading`: days kept inside the window, days elapsed,
completion rate; plus evidence per identity). A chapter is a *window laid over
the history*, never a container for part of it, so closing one loses nothing and
one opened retroactively immediately says something true. One open at a time,
enforced by `open` closing the previous in the same call. Opened automatically
once, at the end of the first run.

**The Blade tab is a portrait**: the blade at its state with the metaphor → who
you're becoming, with evidence per identity → the current chapter → the heatmap
(carousel cut from four pages to two) → your own milestones → one row into all
analytics. Habits and trends moved behind the analytics door. The seven-card
gallery moved into a sheet behind "Your blades" — a shelf of mostly-locked cards
is the collectible reading of the blades that the metaphor exists to prevent,
but equipping still has to be reachable.

`longestStreak` is **gone from the app**, down to the field on
`ProgressStore.StreakState`. It had been pulled from the front card for being a
personal best and went on living on the analytics sheet. `streakRuns()` — a
history of chains rather than a trophy for the best one — is what remains.

**The day's reflection now persists.** `ForgeQuotes` was only ever shown on the
three-second summary overlay, so the one sentence written to be read after the
work was the one nobody read. `ForgeViewModel.reflection(challengeFocus:)` is
the single expression both the overlay and the resting panel use, and it holds
on the Home screen — in the slot that used to say "Early days." — until the day
turns over. A walked archetype's own line still outranks it.

## 2e. The return loop (built)

The daily loop was all input — complete, complete, complete, pull — and the only
output was a three-second overlay that removed itself. Five things now close it.

**The weekly review** (`Models/WeeklyReview.swift`, `Engine/ReviewStore.swift`,
`Views/Review/WeeklyReviewView.swift`). Sunday evening by default, on the user's
own day clock, changeable in Settings. Ninety seconds: the week shown as seven
marks, **one true observation**, and two questions in their own words — *what
actually happened this week?* and *what is next week for?*

- The window is **seven days ending on the review weekday**, never
  `Calendar.firstWeekday`. A window built from the calendar's first weekday
  reviews a week that has barely started for everybody in the Americas.
- `ReviewObservation` is rules over a `ReviewFacts` value — a pure function, so
  the empty and tied cases are literals in a test. Four rules in priority order:
  weekday split, habit split, neglected identity, plain count. **Nothing is
  invented from a tie**, and an empty week gets silence.
- Dismissing writes a row too, so a declined week does not come back tomorrow.
  Nothing counts skipped reviews — a count of those is a streak with a longer
  period.

**The chapter close** (`Views/Review/ChapterCloseView.swift`). At six weeks:
the weeks side by side, evidence per identity inside the chapter, **the user's
own sentences from every weekly review read back**, and one question — *is this
still who you're becoming?* — which retires (never deletes) or carries on, then
opens the next chapter with a new intention.

**Re-entry** (`Models/ReEntry.swift`, `Views/Review/ReturnView.swift`). A gap of
three or more days opens on a short screen that **never mentions the streak**,
states the cumulative fact ("Two hundred and six days kept"), names the absence
without characterising it, and offers **one small thing** — the least-effort
activity on today's list, not the day that stopped being kept.

**The artifact** (`Views/Review/PracticeArtifact.swift`). One square image at a
blade and at a chapter close: the blade at its current state, the count spelled
out, the identity, the date. `ImageRenderer` + `ShareLink`, rendered when the
screen appears, **never posted and never asked for**. No logo, no watermark, no
streak.

**Notifications, rewritten.** Same architecture, same cap, same grace, same
final decline. What changed is what they say: the morning names the identity the
day's first thing is for, an activity's line is "Evidence for someone who
trains" rather than "Time to begin", and the follow-up is "Still on today's
list" rather than "Keep the promise you made to yourself". One new kind —
`.review`, weekly, silent.

**The challenge is rebound.** `ChallengeContext.neglected` carries the identity
with the least evidence *this week*, and it outranks the day's own names. The
old reading aimed the challenge at whatever the day already held — a day of
running got a fitness challenge on top of the run. Selection is still
deterministic per date.

**Sync.** `chapters` and `reviews` tables (migration `0006`), `ChapterRow` /
`ReviewRow`, `SyncMerge.chapters` / `.reviews`. Chapters are last-writer-wins
with **closing unioned** (earliest wins, like retirement); reviews are plain
last-writer-wins per week with no tombstone, because dismissing writes a row
rather than removing one.

### 2f. The real model, and the paywall that matches it (phase 6, 2026-08-12)

**The seam held.** `ForgeAI` was written before there was anything behind it,
and connecting a real model was one property in `ContentView` — `claude` — and
no other line anywhere. That is the whole return on having built the protocol
first.

**`RemoteForgeAI` (`Engine/`) never talks to a model.** It posts to
`functions/v1/forge-ai`, a Supabase edge function that holds the model key as a
server secret — `OPENAI_API_KEY` since §2q (it was an Anthropic key here, and
the type was called `ClaudeForgeAI`). An API key in an iOS binary is an extracted API key; the app
therefore has none and cannot be made to leak one. Every method falls back to
`LocalForgeAI` — offline, signed out, unpaid, unconfigured, or an answer that
failed validation — and `isModelWritten` comes back false, which every screen
showing either a plan or a reading says out loud.

**The third method, `reading(brief:)`, is the one with teeth.** A plan is a
proposal somebody accepts or declines; a *reading* is a claim about the user's
own life, made to the one person with no way to check it. So
`ReviewObservation.validate(_:against:)` checks four things before a model
sentence is ever shown: every number appears in `ReviewFacts`, every capitalised
name exists in the record, the register holds (no exclamation, congratulation or
diagnosis), and it is at most two sentences. A sentence that fails is discarded
silently and the rules answer instead. `ModelTrustTests` holds all of it,
including that **the rules' own output passes the bar they impose on a model**.

One real hole was found and closed while writing those tests: the name check
originally exempted sentence-initial words as "just capitalisation", so
`"Swimming held every day it was asked for."` passed for somebody who has never
swum — the single likeliest shape for the failure, because a sentence about an
activity usually starts with it. `sentenceOpeners` replaced the exemption.

**`AIBrief` widened by three fields** — `identities`, `chapterIntention` and
`week` — and it remains the one struct through which anything can reach a model.
`AIDisclosureView` (Settings → AI) renders that value verbatim rather than
describing it, so "what does it know about me" is answered by the same object
the AI is handed.

**Spend is bounded in Postgres, not by the paywall.** `premium_status` is
writable by its owner — 0001's own comment says so — so gating the edge function
on it is a product check and not a security one. Migration `0007` adds
`ai_usage`, a table with RLS on and **zero policies** (service-role only), and
`claim_ai_call(uuid, integer)` claims a slot before the model is called. Forty a
day. The real fix is App Store Server API verification and is not built.

**The generated archetype** is `PathDraft` — four fields, reviewed on a sheet,
adopted on a yes. Everything that makes a world a practice (routine, movements,
milestones, artwork, the *rule* of the standard) is borrowed from a shipped
skeleton, so a generated path adds no art, invents no rule, and cannot make the
app unreadable. `PathAccent` and `PathStandardRule` stay closed.

**The paywall now describes only what ships.** The four withdrawn claims are
gone and `PaywallHonestyTests` fails if any returns. The line moved: **three**
archetypes are free — Beginner, Operator and **Athlete, the hardest day on the
shelf**, so the free tier is not the easy tier — alongside the whole loop, the
complete history, identities, chapters and the rules-written weekly review.
Sold: every archetype, a generated one, model-written readings, arranging a
week, aimed challenges, and continuity as a bullet rather than the pitch.
`"nothing that has already happened is ever sold back"` survives verbatim.

**A second door, and only a second.** `PremiumInvitation.shouldOfferAtChapterClose`
fires once ever, at the close of a chapter — the one moment somebody has
deliberately stopped, read six weeks back, and is deciding what the next six are
for. Its own flag, because declining on day five is not declining this.


### 2g. The launch-polish pass (2026-08-31) — **the current state**

Seven things were asked for and all seven are built. Where this section
disagrees with anything above it, this section is right.

**1. Plan, and the end of "Forge AI".**
`Views/Overlays/PlanSheet.swift` (was `ForgeAISheet`) and
`Models/DayPlanner.swift`. The control bar's left action reads **PLAN** behind
the same `sparkle`; the word "AI" is gone from every screen in the app.

The screen was a text field in front of a model that is not connected, and it
answered `.notConnected` to most of what anybody would type. It now **speaks
first**: `DayPlanner.moves(_:)` returns up to five *moves*, each a real
`SchedulePlan` and each stating its own arithmetic.

| Move | Fires when | Says |
|---|---|---|
| `untangle` | two activities overlap on a shared weekday, or one starts before the wake time | "X starts while Y is still running on Tuesday" |
| `order` | two or more activities have no hour | reuses `LocalForgeAI.layOut` — one implementation of where a morning goes |
| `strengthen` | a **chosen** dimension is weakest, or one has nothing filed under it | "You chose relationship. It reads 18 against physical at 71" |
| `ease` | asked ≥ 6 times in four weeks and kept < half, on ≥ 4 days | "Kept on 4 of the 11 days it was asked for" — proposes **three** days |
| `balance` | heaviest weekday exceeds lightest non-rest one by 45 minutes | moves exactly one non-daily activity |

The rules that matter: **nothing is invented** (a tidy week returns an empty
array and the screen says so), **rest days are never a destination**, `ease`
never goes below three days, and `strengthen` offers the *smallest* thing in the
dimension rather than the most impressive. The typing field is still there,
under the moves, because an outside commitment and a decision already made are
the two things no amount of reading the record can produce.

`ScheduleChange` gained **`.adopt`** — take up a library activity that is not in
the day. `.create` would have minted a *custom copy* of "Call someone" with a
fresh id, losing its filing, its verification and every count that runs over
time.

**2. Themes.** `ForgeThemeAccent` (eight, closed set) and `ForgeAppearance`
in `Theme/ForgeTheme.swift`; `Views/Settings/AppearanceView.swift`.
`ForgeTheme.accent` became a computed `static var` over an `@Observable`
singleton — Observation tracks the read wherever it happens, so all seventy-nine
call sites update with no plumbing. The screen previews the change on real
components (`ProgressSegments`, the row's completion mark, the primary button)
rather than on a swatch.

**3. The home panel.**
- **Scrolling.** `SwipeToDelete` used `highPriorityGesture`, which claims the
  touch at 12pt and cancels the enclosing `ScrollView`'s pan — so a swipe that
  started on a row (which is most of them, on a 295pt panel) was swallowed. It
  is `simultaneousGesture` now, and the direction test does the arbitrating.
  The row's tap had to move from `Button` to `TapGesture` in the same change: a
  `Button` fires on touch-up anywhere in its own bounds however far the finger
  travelled, so a sideways swipe was opening Delete *and* completing the
  activity under it.
- **Overflow.** `FreeStateView` is a `ScrollView` and `sheetFreeReviewH` is
  derived from the number of activities, capped at the panel's ceiling. At nine
  activities the review used to render past the bottom of the glass with no
  gesture that would reach it. The dot row caps at twelve and becomes a count.

**4. The first run.** Six beats, and the second one changed:
`FirstRunStage.who` → **`.build`**. "Who are you becoming?" is a conclusion
people reach after months of a practice, and asking a stranger for it in their
first thirty seconds mostly bought a Skip. It asks **what do you want to
build** — as many of the six as they mean (§2h) — over a live `FocusHexagon` that fills as
choices are made. The answer is stored as `ForgeViewModel.focus`, the offer is
`IdentityActivities.offered(forDimensions:)`, each starter row says which part
it builds, and the closing line names them.

**5. The blade.** `BladePlate` gives the metaphor beat a strike — the sprite
lifts, a specular sweep runs down the edge once, it settles. 900ms, once, off
under Reduce Motion. And the black screen recorded in §12 was reproduced and
fixed: see below.

**6. Settings.** Rest days say what they are for, what they change and what they
do not; the picker is read back in words. **Sound and Haptics did nothing** —
`ForgeAudio.isEnabled` and `ForgeHaptics.isEnabled` existed and nothing wrote to
them — and now persist and apply. Appearance is new. The AI section is
**Planning** and describes what actually happens.

**7. The home background.** The bottom vignette's darkest end was landing 122pt
below the screen. `bottomVignette` is a `VStack` in a `ZStack` whose intrinsic
height is set by its largest child — and two of those are `fullBleed`, at
`h × 1.14`. So the band was proposed 996pt on an 874pt phone and only ~62% of
the smoothstep was on screen: the room lifted toward the panel instead of
falling away under it. One explicit `.frame(width:height:alignment: .bottom)`
pins it. Measured after: the band runs 554→874 and finishes.

#### The model was switched off (2026-08-31, after the pass above)

`RemoteForgeAI.isModelEnabled = false`. **1.0 sends nothing anywhere for any AI
feature** — see §7 for the mechanism, the three call sites it closed, and the
one-line route back. Plan is unaffected: its moves were never on that path.

Two things go with it and must move together: `APP_STORE.md` §1 now answers
"not collected" for the AI brief, and `NoNetworkTests` fails the suite if the
constant changes without the labels. The `.notConnected` message stopped
promising a connection and started teaching the grammar that works.

#### Two bugs found while testing, both real

**The black home screen (§12) is diagnosed and fixed.** It reproduced on the
first walk through the rebuilt first run. Completing the `doOne` activity writes
a `DayRecord`, and everything downstream fires synchronously off it — the
snapshot, the notification plan, and the Live Activity, which makes the system
re-specify the scene's frame. Removing the full-screen cover in the *same*
runloop turn asks SwiftUI to hand the window back to a hierarchy that has been
idle behind an opaque overlay for ninety seconds while the scene is being
re-laid-out. `FirstRunView.handOverToTheBlade()` gives the write its own turn and
the handover an animation. Two clean walks since; **worth watching on a device.**

**Today's count was counting the wrong thing.** `totalDone` was `doneIDs.count`
— everything completed today, whether or not today still asks for it. Complete
two activities, take one off today (it happens on Thursday as well), and the
header reads "2 OF 3" over one tick. Worse: `allDone` is
`totalDone >= totalActive`, so **taking something off today was a way to earn
the day** with an unfinished activity still on the panel. It counts today's list
now. `DayCountTests` holds both halves.

#### The activity library: 39 → 52

Once every activity is filed against one of six parts of a person, a thin
dimension stops being a curation detail: the Shape names a weak side out loud
and then has almost nothing to offer for it. Mental, Relationship and Ambition
held five each. Thirteen were added — `teach`, `sketch`, `lookup`, `listen`,
`letter`, `arrange`, `numbers`, `askfor`, `craft`, `breathe`, `silence`,
`worry`, `prep` — and `IdentityActivities.effortOrder` was **re-interleaved**
rather than appended to, because a batch is a fact about when something was
written and that list is a claim about how hard it is to start. Sixteen glyphs
were added: `book` had been drawing four different activities and
`hands.and.sparkles` three. A test holds both (`noDimensionIsThin`,
`glyphsAreNotOverloaded`, `theLadderIsComplete`).

### 2h. The onboarding, the sword moment and the six as one vocabulary (2026-09-02)

Five things were asked for and all five are built. Where this section disagrees
with anything above it, this section is right.

**1. The first run chooses as many of the six as it means.**
`FirstRunView.build` had a hard cap of three, on the argument that "a person
building everything is building nothing". That is a true sentence about a *day*
and a false one about a direction — nobody wants to be weaker in three of six —
and the cap made the honest answer unavailable. It is gone, here and in
`FocusEditor` on the Becoming tab. Nothing downstream needed it:
`DayPlanner.strengthen` reads the weakest **chosen** dimension, which is well
defined over six, and the day is still three activities, which is where the real
constraint always was.

What that broke and how it is answered: eight starters across six dimensions is
one each plus rounding, so `IdentityActivities.offerCount(for:)` widens to two
per dimension (ceiling twelve) past three chosen. One, two or three chosen still
gets exactly eight, and an empty focus still gets the shipped eight verbatim.

**2. The starters are curated per dimension, not "the cheapest in it".**
`IdentityActivities.starters` is a new hand-ordered table, one list per
dimension, ordered by *how much it is the thing*. The old rule — that
dimension's library activities, effort ascending — offered somebody who said
Physical a glass of water, some vitamins and a properly made coffee, because
those are the three physical activities that ask least. The effort ladder still
decides the order they are *shown* in and still decides which one the first run
asks for, so the smallest chosen thing is still the first ask; the curation
decides only *which* are offered. A test holds that every dimension's list
covers its own library exactly once.

The starter row also stopped replacing the activity's subtitle with "Builds
physical". The library is written so **the label is the act and the subtitle is
the standard** ("Walk outside" / "Eight minutes, sky above you"), and spending
that line on a category turned a screen of concrete things into a screen of
filing. The dimension is a small glyph on the right — the word was tried first
and truncated the sentence it was put there to sit beside.

**3. The sword moment is a pull, and it says the thing.**
`FirstRunStage.metaphor` read *the blade is what you are building* over a still
photograph with a Continue button under it. It now reads **"You are shaping
yourself."**, and the way out of the beat is `PullToBegin` — a real drag on the
blade, with eased resistance, friction ticks, a hot edge that brightens as it
comes and a break at the top. There is no button.

It is **not** `SwordEngine`: that simulation has catches and slip-back and is
meant to be losable, which is correct on the home screen and wrong on the one
screen somebody can be lost on. This one is a single continuous drag with weight
on it. VoiceOver gets it as an accessibility action on one labelled element,
which is the same act performed by somebody who cannot drag — the only beat with
no other way past it is the one that must not have one.

It also closes a real gap: the first *earning* pull happens ninety seconds later
on the real home screen, and until now nobody had ever been shown the gesture.

**4. The first day shows one thing, and holds still.**
`doOne` read `vm.firstRunActivity` on every draw — and that property answers with
the smallest thing on today's list **that is not done**. So keeping the first one
changed the answer, and the beat spent the handover showing a *second, different*
activity that appeared and vanished at the exact moment somebody completed their
first thing in the app. It is frozen in `FirstRunView.firstTask` now.

The beat also no longer leaves the instant it is kept: the mark ticks, the line
becomes "Kept. That is the whole mechanic — every activity on your day works
exactly like that", and the handover is 1250ms rather than 420. The write still
gets its own runloop turn, which is the part that was load-bearing (§2g, the
black home screen).

**5. Cinematic, and less blue.** `FirstRunAmbience` puts the room behind the
sequence — a warm source where the app's light is, a cold counterweight low on
the other side, drifting on a nine-second cycle, off under Reduce Motion. Beats
land in reading order (`View.rises(after:)`). `FocusHexagon` draws its
instrument in cream and keeps the accent for the intention inside it. And
selection stopped being a filled blue card: with the cap gone, six chosen rows
were six blue cards stacked on each other, so a chosen row is a light tint under
an accent hairline with an accent mark.

#### The challenge is aimed at the six, and browsable

**`ChallengeFocus` is now the six dimensions**, one to one with `RitualCategory`
(`.category` is the mapping). It used to be `discipline · focus · fitness ·
courage · mind · productivity`, on the argument that a challenge is *aimed*
rather than *sorted*. That was right when `RitualCategory` was a filing system
for a picker; it is wrong now that the six are the spine of the product, and a
second six-word vocabulary beside them cost the reader something for nothing.
The old raw values decode through `ChallengeFocus.legacy` — today's challenge
state is stored, and a throw would drop somebody's accepted challenge
mid-morning. Relationship stopped being a hole: the old objection (a challenge
must not set a task a third party has not agreed to) survives in **how those ten
are written** — every one is something the user starts alone.

**The catalogue is sixty, ten per aim**, up from forty-eight, and rewritten
against the same bar: countable or a bright line, doable today, specific enough
to say out loud. `LocalForgeAI.bestMatch` and the deterministic per-date
selection are untouched.

**The sheet is a pager.** `DailyChallengeSheet` shows six cards — one per part
of a person, in `RitualCategory.dimensions` order, today's own sitting in its
dimension's slot — and opens on today's. `ChallengeCatalog.browse(for:including:)`
draws each from that dimension's shelf using the same FNV arithmetic salted with
the dimension's name, so the six are identical on two phones and across
launches. Nothing is decided by swiping: the card under the finger is what the
buttons act on, and "Take this one" is an explicit press that replaces today's
challenge exactly as `generate` does.

**The fixed slots are load-bearing.** The first version put today's card first
and the other five after it; taking a card then reordered the array under a
scroll offset that does not move with it, and everything afterwards — the lit
dot, the card on screen, the buttons — was one position out from what the state
believed. Reproduced on device. Slots keyed to the dimension make it unreachable.

#### The Becoming tab starts cleaner

`navigationSubtitle` is gone — the screen opens on the word and the hexagon.

**"What you're building" as a section is gone too, and that is a deletion rather
than a move.** It was a card of its own under the polygon, one row per chosen
dimension, each carrying that dimension's name, score and direction — every one
of which is in **The Six** a few points below, for all six, in the same order and
the same words. Two readings of one fact invite somebody to check whether they
agree. What was *not* redundant is the choosing, so a chosen dimension is now
marked `BUILDING` inside The Six, and what is left of the section is one row
stating the answer in words and opening `FocusEditor`. That row is present
whether or not there is a shape to draw yet; the six rows themselves still wait
for `isReadable`, because a column of six "Nothing here" is not a reading.

### 2i. The compositing, the long day and the analytics (2026-09-03)

Four things were asked for and all four are built. Where this section disagrees
with anything above it, this section is right.

#### 1. The scene had three compositing artifacts, and they were measurable

**Every soft mark in the scene was clipping its own gradient.** They were
`Ellipse().fill(RadialGradient(…))` with an off-centre `UnitPoint`, which reads
as obviously correct and is not: a `RadialGradient` is a **circle in point
space**, so a wide, short ellipse crops it top and bottom — and it crops it while
the gradient is still at 40–70% of peak. What that draws is *the ellipse's own
outline*, at 40–70% strength, as a hard arc. Nine of the ten socket marks were
doing it, and so were `floorBounce` (a 180pt gradient cut 104pt from its focus,
in bounced light, across the middle-left of the room) and `groundShadow` (47% of
a black fall-off stopping dead along an arc under 15pt of blur).

`SoftPool` (`SwordSceneLayers.swift`) makes that shape of mistake unavailable:
the fall-off is generated in a **square**, where a circular gradient reaching
zero at `side / 2` is exactly zero at every edge, and the oval footprint comes
from squashing the square afterwards. There is no shape to crop against and no
value at any boundary. The off-centre bias became the view's **position** rather
than a gradient focus, because the two were one fact expressed as two knobs and
the real centre of a mark was `position + (focus − 0.5) × size` — a number
nobody was reading.

**The socket's darkness had drifted off the blade.** Measured off a screenshot:
the centre of mass of the shading ran from **+11pt at the mouth to +20pt** forty
points below it, against a blade on the axis, so the hole read as a smudge
beside the sword. Three marks were each carrying a right-bias and they
compounded. The rule that sorts it: **occlusion is centred, only the cast is
offset.** What light cannot reach is the contact itself, and that does not move
because the key does. Still lit from the upper left; falling down-right by four
to seven points instead of twenty.

**`GripRing` was the visible artifact and it is deleted.** A 44×66 rounded
rectangle, stroked half a point of white and pulsed over the grip: its left edge
measured **+18/255 brighter than the plate beside it** — a hard vertical line
with a semicircular cap, hanging in the room to the left of the blade, ending in
mid-air. Everything doctrine §8 forbids in one box. The affordance was worth
keeping and the shape was not, so it is `SwordSceneView.gripHint`: a brightened
copy of the sprite masked to the grip band, the same trick `sheenPass` uses,
which cannot bleed outside the steel by construction.

**And the stone is opaque.** It was `.opacity(0.9)`, which is a tenth of the
blade *and the blade's 0.42 drop shadow* — both hard-edged — coming through the
rock, so the stone carried a faint ghost of the sword down its face with two
straight seams on it. Whatever bedding-in that was for, `atmosphere` does over
the top of the subjects anyway.

#### 2. A long day

**`allDone` and "the list is finished" were the same property, and it hid the
day.** The first run's grace makes the blade loose with one of three done, so
`allDone` is true for a day that plainly is not — and `ForgeTabView.content` was
reading it to decide whether somebody sees a *closing* screen. `isListFinished`
is the honest reading and the free state uses it now; the pull prompt keeps
`allDone`, because being *loose* is exactly what the grace is for.

**`ProgressSegments` degrades into a bar.** One segment per activity is the
right reading for a five-activity day and it was silently unbounded: the row is
about 207pt wide, so at seventeen activities each segment is under nine points,
and past forty the arithmetic gives every segment less than a point. It measures
the width it actually has and switches to a single proportion bar below the
legibility floor.

**The week planner's list carries the day list's fade mask.** Without it a long
day ended on a row sliced in half against the glass.

Verified on device at eleven and sixteen activities: the panel expands to its
ceiling and no further, the list scrolls to its end in both Today and Week, and
nothing is clipped or unreachable.

#### 3. Analytics: two wrong denominators, and a timeline that started too early

**The overview was dividing numbers from two different sets.** The activity
tally ran over *every* record, today's included, so the completion rate counted
an unfinished morning as a shortfall and sagged at four in the morning — the
exact failure `countsTowardRate` exists to prevent, happening in the figure
printed beside the one it protects. And `daysKept` counts every earned day while
`daysPossible` excluded rest weekdays, so somebody who keeps their rest days
could read **over a hundred per cent**; on the very first day it read `1 of 0`
and printed 0%. `ProgressStore.ratedDays()` is now the one list both are
fractions of, and today is in it only once it has been **earned**.

**The year starts where the record does.** `year(_:)` drops the months that end
before `firstTrackedDay` — eight rows of grey dash for somebody who installed in
September is not their record — and `yearHeatmap(_:)` drops the leading blank
columns for the same reason. **The months and weeks ahead stay**, because not
yet reached and not recorded are different facts; `Period.isFuture` is what lets
the list say which. The section reads "68% of 2026 · from Jun".

**"Most often" is marked in HABITS.** The list is ranked by rate, which answers
*what holds* and cannot answer *what do I actually do* — four out of four beats
sixty out of ninety. `BladeViewModel.mostKeptHabit` marks the row with the most
days behind it, or nothing when there is a tie.

**"Activities done, since the first day" is gone from the overview**, for the
reason it was deleted from the front card: it only goes up, so it says what
"days kept" says in a bigger font — and it had turned up here one screen further
in, exactly as the longest streak had. In its place is the thing the three rates
beside it are all fractions *of*: **Record begins · 10 Jun · 85 days on file**.

**The trends window is clipped to the record too.** "Last six months" drew two
hairline bars in front of a three-month history, which is the same empty-period
problem in a rolling window rather than a calendar year.

**Two duplicated headings went.** `TrendsCard` was printing "TRENDS" inside a
section called TRENDS, and the chapter card said "One **days** kept".

### 2j. The second polish pass (2026-09-03) — **the current state**

Nine things were asked for and all nine are built. Where this section disagrees
with anything above it, this section is right.

#### 1. The home screen has one action, and Plan is not on it

`ForgeControlBar` was `[TODAY|WEEK] … [PLAN · challenge]` — two bare glyphs of
equal weight, which is what a toolbar looks like rather than what a decision
looks like. It is `[TODAY|WEEK] … [flag CHALLENGE]` now: one named capsule, whose
**colour is its state** (accent mark and full-strength word when unanswered,
both quiet once answered, mark bolder when done) so the waiting dot is gone.

**Plan moved to the week**, under the `…` menu in `WeekPlannerView.dayHeader`,
which is also now always present rather than appearing only on a day that
already held something. The argument: every move `DayPlanner` proposes is a
change to the *week* — an hour moved, a frequency eased, an activity taken off a
Tuesday — so the home screen was the one screen on which its output could not be
read. `PlanSheet.onApplied` is a no-op from there; it used to switch the panel to
Week, which is where the user already is.

`DayPlanner.strengthen`'s headline quoted the activity bare and produced **"Add
Set tomorrow's one thing to your week"**. It quotes it now (`\u{201C}…\u{201D}`),
which is the only form that is grammatical for all fifty-two labels — lowercasing
broke on labels that are sentences and leaving it bare breaks on every label that
opens with a verb.

#### 2. The crossed swords are gone

`ChallengeSwords` drew a 660pt two-sword vector scaled to seventeen: a hairline
outline beside SF Symbols at medium weight, which on glass read as a smudge. And
it was medieval dressing — Forge has one object in it, and a second unrelated
weapon standing in for "today's challenge" is a costume.

`ChallengeMark` is `flag` / `flag.fill`. **`target` was tried first and is
wrong**: `RitualCategory.ambition` already *is* `target`, so the sheet would have
carried the same glyph twice on one card meaning two different things. The asset
is deleted.

The Becoming tab's icon went the same way: `arrow.triangle.turn.up.right.diamond`
— a road sign, chosen when the tab was a shelf of worlds — is now `hexagon`,
which is what every screen on that tab is drawn around.

#### 3. The challenge browses without an end, and the generator is deleted

`ChallengeCatalog.browse(for:including:page:)` takes a page: page zero is the six
that carry today's own (unchanged, same salt, same slots), and every page after
it is another round of the same six aims. `DailyChallengeSheet` appends a round
as the finger nears the last card, over a `LazyHStack`, so the pan never stops
and only the cards near the viewport are ever built.

Two things had to change with it. The pager keys its cards by **page and slot**
rather than by challenge id — sixty challenges over an unbounded scroll means the
same one can come round again, and two views sharing an id in a `ForEach` collapse
into one and take the scroll position with them. And the pager has a **fixed
height** (`@ScaledMetric`, capped at 400): an `HStack` is as tall as its tallest
child, so a lazily-built longer card used to push the rail and the buttons down
mid-swipe.

The six dots became a **six-mark rail of the dimensions**, lit for the aim on
screen. A page indicator over a deck with no length would either grow forever or
lie, and the useful fact was never the ordinal.

**`ChallengeGeneratorView` is deleted**, and with it `ChallengeStore.generate`,
`isGenerating`, `generationFailed`, `isModelConnected` and the store's `ForgeAI`
dependency. It was a weight picker, a six-way aim grid and a free-text field in
front of a model 1.0 does not connect — a screen that said so out loud, half of
whose controls were dead code with `true ?` still standing where a premium check
used to be. The pager answers the question the form was actually for. The
**seam is not gone**: `ForgeAI.challenge` and `LocalForgeAI.bestMatch` are
untouched, so 1.1 has a screen to write rather than an architecture to rebuild.
§7's table of live call sites is therefore two rows, not three.

#### 4. Becoming shows all six from the first day, and stops moving

**The Six was behind `shape.isReadable`** — two measured dimensions and five kept
days. That gate is right for the *hexagon* and wrong for the list: somebody who
chose two dimensions in the first run opened the tab and found the two they had
already picked, with no indication that there were six, what the other four were,
or that anything could be added to them. The one screen about direction showed
only the direction already taken. The list is unconditional now; the polygon
still waits.

**Three separate causes of the screen jumping while choosing were fixed:**

- `focusRow` carried one accent glyph per chosen dimension and the full list in
  words, both unbounded. A fourth choice squeezed the sentence, a fifth wrapped
  it to a third line, and the hexagon above and all six rows below moved. It is
  one hexagon and a bounded two-line sentence now — which is why all six is said
  as **"all six"** rather than enumerated.
- `toggle` wrapped the mutation in `withAnimation`, and an explicit transaction
  animates *every* view reading the focus — including the `ScrollView` the rows
  sit in. Each piece animates its own property instead (`DimensionChoiceRow` on
  `isChosen`, `FocusHexagon` on its fractions, `focusRow` on its headline).
- `FirstRunView.build` changes its subtitle on the first choice, and the two
  sentences do not wrap to the same number of lines on a narrow phone. It
  reserves two lines.

#### 5. The weekly review reads back, and the weeks are findable

The seven marks were a card and the observation was a heading floating under it;
they are **one card divided by a hairline**, because they are one fact.

**The review now opens on what you said last week was for.** One line, quoted,
never scored — Forge does not say whether the week matched the sentence, because
nothing here knows. It is the only thing on that screen that makes doing it fifty
times different from doing it once.

**`WeeklyReviewHistory`** is a sheet off one row on the **Becoming** tab: every
week somebody has answered, newest first, read-only. Everything written was
stored and nothing was readable until a chapter closed six weeks later — so the
honest reading of "Kept on your phone" was that the sentences went somewhere the
person who wrote them could not follow. It is on Becoming rather than Blade
because a review is not a record of what happened; it is the two sentences
somebody wrote about where this is going.

#### 6. Adding a task offers what you already keep

**The week's `+` opened a blank composer.** Somebody who has selected Thursday
and pressed `+` is far more likely to want something they already do than to want
to invent one, and the picker did not offer it: `ActivityLibraryView` showed the
library minus everything in the day, so **an activity kept on Mondays was
invisible on every other day** and the only route onto Thursday was the repeat
picker three screens away.

`ActivityLibraryView` now takes a `weekday` and leads with **"Already in your
week"** — everything in `activeRitualIDs` that does not happen on that day, each
row saying which days it currently runs on, adding the day rather than minting a
copy. `AddToDaySheet` presents it from the week; the day editor still pushes it.
Everything through it honours the day: `addRitual(_:onWeekday:)`, the composer's
`.onlyToday(target)`, and the title.

#### 7. Two ways the record could disagree with the day

**`publishPlanned` was only wired to `activeRitualIDs`.** Taking an activity off
today with a swipe does not touch that array — it narrows a repeat rule, which
lands in `libraryEdits`. So the row left the panel and `DayRecord.plannedIDs`
went on claiming it: the widget and the Live Activity kept counting it, every
rate divided by a denominator one too big, and — the visible one — **tomorrow,
when today became a past day, the week planner drew it out of the record and
showed an activity that had not been on that day.** `customRituals` and
`libraryEdits` write the day down too now, and `publishPlanned` guards on
`isLoaded` the way `persist()` always has.

**`todayRitualIDs` kept ids that resolve to nothing** (`?? true` — "if we cannot
tell, assume today"). Every list resolves its ids and drops the failures, so a
phantom drew no row; but `totalActive` counts the array, so it was counted. That
is a day reading "0 OF 4" over three rows, which can never be finished and
therefore never earned. Both are held by tests in `ActivityScheduleTests`.

#### 8. The widgets are the same app (**partly superseded — see §2l.2**)

> The accent, the room, the one-directional snapshot and the
> `.environment(\.colorScheme, .dark)` are all still true and still load-bearing.
> What is gone is `BladeMark`, the drawn sword in a stone that every paragraph
> below takes for granted, and the shape of what each family says. §2l.2 and
> §2l.3 are the current description.


`ForgeAccentPalette` (in `Shared/ForgePalette.swift`, which both targets compile)
holds the eight accents; `ForgeThemeAccent.color` and `ForgeTheme.cream` read it,
and `ForgeSnapshot.accent` carries the choice across the one-directional boundary
so **a phone set to Moss has Moss widgets**. The snapshot's decoder is
hand-written and tolerant for the usual reason: the synthesised one throws on a
missing key, and `read` would fall back to an empty day on the first launch after
the update.

The Home Screen families are drawn on **the room** — near-black, warmed, lifted
at the top, with one soft wash of the accent — rather than on `.fill.tertiary`,
which was the one surface of the product that looked like a different product.
That change is only half done without `.environment(\.colorScheme, .dark)`: the
first build drew a black blade and black digits on a near-black card, because a
widget renders in whatever appearance the Home Screen is in.

What each one says changed too. The small widget carried **only** days kept —
the same answer every one of the fifteen times a day somebody looks at it — and
now carries the day as well, over a shared `DayRail`. The Lock Screen rectangle
spent a third of itself printing the app's own name beside the app's own mark;
it names **the next unfinished activity** instead, which is the difference
between a status and a prompt.

#### 9. Notifications quote the user rather than the app

The identity spine is history-only, so the identity-voiced copy written in §2e is
what almost nobody sees. The fallbacks were "Your day starts now.", "Time to
begin." and "Your day" — the same sentences on day one and day four hundred.
Every one of them now says something only true of this person:

| | Was | Is |
|---|---|---|
| morning | "Your day starts now." | `standing` — "Ninety-one days kept.", spelled |
| activity | "Time to begin." | "20 min. Then it is behind you." — the duration **they** set |
| missed | "Still on today's list." | + "2 of 5 done." |
| evening | title "Your day" | title is the count; body names the next open activity |

**The count and never the chain.** A streak is a number whose only property is
that it can be lost, and a notification built on one works by making somebody
afraid — the register every other decision in this app refuses. Days kept only
goes up. It is baked into a repeating request so it can lag for a phone that has
not opened Forge, which is the safe direction: a day is not kept without the app,
so it can undercount and can never overstate.

### 2k. The release QA pass (2026-09-03) — **the current state**

A full walk of the product on device, from a wiped install through onboarding,
the pull, the challenge, the week, the review and a cold relaunch. Six real bugs,
two of them serious. Where this section disagrees with anything above it, this
section is right.

#### 1. The first run could trap somebody in it forever

**The worst bug in the set.** `hasCompletedFirstRun` is written by the *closing
beat*, and the beat before it is the real home screen where the first pull
happens. Anything that ends the process in that window — a force quit, a call,
the OS reclaiming memory, the phone put down overnight — brought the app back to
the promise screen for somebody who had already kept a day, with their
activities, their blade and their history sitting behind it.

And it was not merely embarrassing. **The sequence cannot finish a second time:**
its last beat waits for the day to be earned, today's day is already earned, so
`finishEarnedSequence` never runs, `.pull` never becomes `.closing`, and there is
no way out of onboarding until tomorrow. Reproduced by relaunching after a pull.

`ForgeViewModel.load()` now settles it from the record: **an earned day means the
first run is behind you**, whatever the flag says. Read rather than patched with
a second flag, because nobody reaches an earned day without having walked the
sequence. `FirstRunTests` holds both halves — an earned day skips it, an unearned
one still gets it.

#### 2. The pull could not be done the way the app told you to do it

The prompt says **"Press the grip and drag up"**, and the grip sits at
y ≈ 150…235pt when the blade is loose. Breaking free needs `raw` ≈ 0.79, which at
`SwordEngine.travel = 250` is **198pt of finger travel** — finishing at y ≈ 0,
past the status bar, with the finger off the glass. Measured: a deliberate 151pt
haul from the grip reached 0.52 and slipped back every time. The one gesture the
product is built around could only be completed by ignoring the instruction and
starting halfway down the blade.

`travel` is **150**. The break lands at 118pt and a full pull at 150 — from the
grip that finishes around y ≈ 70. **Nothing about the feel changed**: the
resistance curve, both catches, the critically-damped spring, the friction ticks,
the synthesised grind and the break are untouched, and the weight was always in
the mapping rather than in the distance. A casual 60pt flick still reaches 0.30
and slips back. Verified on device: pressing the grip and dragging now frees the
blade, earns the day and runs the celebration.

#### 3. The sword was not coming out of the middle of the stone

Measured off the composed screen at 402pt wide: **crown apex at x 154, blade at
196**. The sword entered the rock's right shoulder, a ninth of the screen off the
peak, with the socket — correctly drawn on the axis — sitting there with it.

The cause was a false premise in `rockLeft`'s own doc comment. It claimed the
silhouette sits dead centre in `rock-lit.png`, so centring the frame puts the
crown on the axis. Measured off the asset's alpha: the **bulk** is centred
(mid-x ≈ 330 of 660) but the **apex is at x ≈ 279** — 7.7% of the width left of
it. The rock's high point is not over its middle. Centring put the apex 27pt
left; an unexplained −20 nudge on top of it made it 47.

`rockLeft` gains 35 — the offset that splits the error evenly between the apex
and the bulk — and `crackDrift` moves with it, exactly as much, so the fissures
stay on the face they were drawn for. Measured after: **apex 184, blade 196,
silhouette midpoint 198 against a screen centre of 201.** The stone is centred,
the blade enters the middle of the crown's plateau, and the socket, the cracks
and the contact shading are all on the entry point.

#### 4. The permission primer promised notifications Forge does not send

`NotificationPrimerView` carried its own three sentences as string literals —
"Your day starts now.", "Time to begin.", "Keep the promise you made to
yourself." — and §2j.9 rewrote all three without it. So the one screen whose
entire job is *showing somebody what they are agreeing to* was showing work the
app would never do.

The rows call `ForgeNotificationPlan`'s own functions now. `standing(daysKept:)`
and `waiting(_:done:planned:)` take primitives instead of a whole state so the
primer can reach them, `opening(first:firstTimed:at:)` stopped being private, and
`ContentView.notificationState` is one value handed to both the scheduler and the
primer. `NotificationPlanTests` holds the rows against the plan and refuses the
three retired sentences by name.

#### 5. Taking a challenge from deeper in the shelf did nothing visible

`Card.isToday` was `page == 0 && id matches` — true of the slot today's challenge
is drawn into, false of the identical card further down the deck. So taking a
card from page two changed the store and left the screen still saying ANOTHER FOR
TODAY, still offering "Take this one" for a challenge the day already held. It is
`drawn.id == challenge.id`: a fact about the day rather than about where in the
shelf a card sits.

#### 6. The one sentence Forge writes about your week did not parse

A first week — one day on the record, and the commonest week there is — read
**"One of the one days that asked for something were kept."** Three mistakes in
one sentence, on the screen where it is the only thing the app says. The count
line above it read "one of one days kept." `ReviewObservation.plainCount` and
`WeeklyReviewView.kept` agree in number now, and `ReviewTests` holds every case
including that nothing anywhere says "one days".

#### Also

- **`TARGETED_DEVICE_FAMILY` was "1,2".** The app declared iPad support it has
  never been laid out for: `SwordSceneView` scales against a 402pt canvas, so an
  11" iPad would draw the scene at 2× with a 794pt task panel. It is `1`.
- **The focus row said "5 of the six"** where Forge spells counts under a hundred
  (§8). It says "five of the six".
- Verified and unchanged: the challenge pager browses past eleven cards with no
  endpoint and no height jumps; the Becoming six select and deselect with every
  row at an identical y; adding from the week's `+` lands on the day chosen and
  "Already in your week" lists what runs elsewhere; the weekly review saves and
  reads back on Becoming; a cold relaunch restores the day, the count, the
  equipped blade and the list.

### 2l. The release pass (2026-09-03) — **the current state**

The pass that clears the submission blockers and rebuilds the widgets. Where
this section disagrees with anything above it, this section is right.

#### 1. The two hard blockers are closed, and neither is a `#warning` any more

**The icon exists.** `AppIcon.appiconset` holds a 1024×1024, sRGB, opaque
`AppIcon.png` resized from the supplied art, named in `Contents.json` as the one
universal iOS slot. Confirmed against a **Release** build: `CFBundleIconName =>
AppIcon` in the built `Info.plist`, `AppIcon60x60@2x.png` in the bundle, and the
tile drawn on the Simulator's Home Screen where the blank placeholder used to
be. `ITMS-90713` cannot fire on this build.

**The URLs are real**: `forgebetter.app/privacy`, `/terms` and a third,
`ForgeLinks.support`, which is new. Settings → About leads with **Support** —
the other two are documents somebody reads once at most, and this is the row a
person opens when the app has done something wrong. The `#warning` is deleted,
and what replaced it is `BackendRegressionTests.productionLinksAreConfigured`,
which fails the run if any of the three stops being the live one. A warning that
fires on every build is read on none of them; a failing test is read once and
fixed.

`Forge.storekit` carries the same two strings in `eula` and `policyURL`.

#### 2. The widgets are not a picture of a sword any more

`BladeMark` — the vector blade-in-stone that opened every family — is
**deleted**, and `Shared/BladeMark.swift` is now `Shared/ForgePalette.swift`,
holding what the name says: the colour vocabulary both targets compile.

The argument for deleting it: the mark carried **one bit** (in the stone, or out
of it) at the size of a hero image, and it was the same picture on the fifteenth
look of the day as on the first. On a Home Screen between Weather and Calendar
it read as a screenshot of Forge rather than as part of iOS, and at the sizes it
was actually drawn — 16pt in the Dynamic Island, 22pt on the Lock Screen
rectangle — it was a grey smudge. Everywhere it stood is now the fact it was
standing in front of.

Five families, and **not one design at five sizes**:

| Family | The question it answers |
|---|---|
| `accessoryCircular` | how many left — a gauge, one digit, no artwork |
| `accessoryRectangular` | **what next** — the state, the activity, a rule; full width now the mark has gone |
| `systemSmall` | the date, the next thing, and how far through |
| `systemMedium` | that, plus **where today sits in the week** — seven marks and "4 of 7 kept" |
| `systemLarge` | **six months of the record** — the only family that is not about today |

The Live Activity lost the mark too, in all four of its slots. Every one is a
`DayRing` now: two strokes carrying the day's fraction, which is the only mark
legible at sixteen points and the one the system renders properly inside the
Dynamic Island.

#### 3. The large widget, and the trail that feeds it

Twenty-six columns of seven, drawn from `ForgeSnapshot.history` in the same five
shades as the heatmap on the Blade tab, with the months labelled across the top
and three counts underneath (this week, this month, today). The square side is
**measured** from a `GeometryReader`, because 26 columns is 9.7pt a side on a
6.1" phone and 10.9 on a 6.9" one and a constant would overflow one or stripe
the other.

Three rules make the picture honest, and each of them was a bug in the first
build of it:

- **The bucketing happens in the app.** `ProgressStore.heatTrail(days:)` returns
  one `ForgeHeatMark` per day and the widget only draws them. A grid drawn over
  there from raw fractions would be a second implementation of
  `ForgeHeatLevel.of` — and the first time the two disagreed by a step it would
  be on a Home Screen next to the Blade tab that disagrees with it. `HeatLevel`
  in the app is now an alias for the shared `ForgeHeatLevel`, so there is one
  table of five shades in the process.
- **A mark carries the level *and* whether the day was kept**, in one `Int`.
  Those are not the same fact: a square is full when the list was finished, and a
  day is kept when the blade came out, which is a separate act. The colour is the
  first and every count under the grid is the second. `ForgeHeatMark.beforeRecord`
  is a third value and is deliberately not a level — see below.
- **The trail stops at yesterday.** Today is the one day that can change after
  the trail is written, so the grid takes today's square from `fraction` and
  `isEarned` like every other family, and everything before it from the trail.
  `ForgeSnapshot.mark(on:)` is the one place that decides, which is also what
  makes a phone that has not opened Forge for a week draw correctly rather than
  drawing a hole.

**Three kinds of square, and the difference is load-bearing.** A day is filled.
A day *earlier than this person's record* is an **outline with no fill** — it
must not take the ramp's lowest step, because that step means "a day you had and
did not keep" and these are days Forge was not installed for. A day still ahead
draws nothing at all. The first build drew nothing for the last two, and on a
fresh install the large family was a black card with one blue square in it and
the medium's week strip was six weekday letters under a gap: both read as a
widget that had failed to load rather than as a record that has not started.

#### 4. Becoming counts after the six rather than before them

`focusRow` — "You're building all six." — sat directly under the hexagon, which
put a tally of the choice above the six rows that *are* the choice, and pushed
the list itself below the fold on a small phone. It is under the list now:
**the shape, then the six it is made of, then how many of them you said you were
building.** A progress line belongs after the thing it is progress through.

Its height still does not depend on the count — two lines for the sentence and
two for the note, reserved — which was the fix for the screen moving mid-choice
and matters more down there, not less.

Selecting, deselecting, all six, and one: walked on device at every count, with
every row landing at an identical y and no horizontal movement.

#### 5. The Becoming tab is a sign again

`hexagon` is out. It is honest about the *content* and says nothing about the
*tab*: a bare outline of a shape is the one mark in the bar that is not a picture
of an idea, and beside a flame and a chart it reads as a placeholder somebody
forgot to replace.

It is **a plain arrow pointing forward, inside a diamond** — a direction sign,
for the tab about days that have not happened, beside Blade, which is the record
of the ones that have. The *turn* arrow stays rejected for the reason it was
rejected the first time: a junction is a choice between routes, and this tab is
about one.

It is a `template`-rendered vector in `Assets.xcassets` (`BecomingSign`) rather
than a symbol, because **SF Symbols has no `arrow.right.diamond`** — the family
carries `plus`, `minus`, `xmark`, `checkmark` and `questionmark` in a diamond,
and the only arrow in one is the junction. **The SVG's intrinsic size is 27×27
and that is not cosmetic**: the first build declared it at its 100-unit viewBox
size, so UIKit drew it at a hundred points, it swallowed a third of the screen
and its hit area ate taps meant for the button above the tab bar.

#### 6. Seven points off the stone, and the pool under it

`rockLeft` was `−20 + 35 = +15`, which is what the §2k arithmetic lands on. It
ships at **+4**, in two steps: +8 in this pass, then +4 on a second look (§2m).
The derivation splits the error evenly between the crown's apex and the rock's
bulk, and the eye does not weigh those equally: it finds the **apex**, because
that is where the blade enters and where it is already looking, so an offset fair
to both reads very slightly as a stone sitting right of its own sword.
`crackDrift` moves with it exactly (−23 + 24 = **1**), or the fissures come off
the face they were drawn for.

Measured on the composed screen afterwards: apex ≈ 192, blade 200, silhouette
midpoint ≈ 198, screen centre 201 — the crown's high point and the rock's mass
now straddle the blade, which is what the derivation was aiming at.

`groundShadow` moved **up 14pt**, to `mouth + 34`. The pool is drawn where the
stone's mass meets the floor and the stone had drifted up the frame relative to
it over the compositing passes, so the dark was pooling a little below the rock
rather than under it — which reads as hovering. The shadow moved rather than the
stone, because the stone is on the sword's axis by measurement and the pool is
the only thing there with no landmark of its own to be wrong about.

**The socket's own shading came up 2pt in §2m** — `contactOcclusion` to
`mouth + 0` and `bladeCast` to `mouth + 5`. That is the dark patch a person
actually sees *around the entry point*, as opposed to the pool under the whole
rock, and the two are worth not confusing when a note says "the shadow".

#### 7. What the pass could not verify

- **VoiceOver.** It cannot be driven synthetically. The labels, values and hints
  are in the source and `AccessibilityTests` holds them, but nobody has heard
  them.
- **The weekly review screen.** Its arithmetic is held by `ReviewTests` and
  nothing in this pass touched `ReviewStore`, `WeeklyReviewView` or
  `ReviewObservation` — but the screen itself would not open in the Simulator.
  Re-entry outranks it by design (§2e), a fabricated Sunday has no activities
  pinned to it so the day cannot be earned to clear that, and `debugDayOffset`
  does not survive a relaunch. Needs one look on a real review evening.
- **Hardware.** Everything below is a Simulator.

#### Also

- The **Lock Screen widgets have now been seen rendered**, which closes the last
  item on §12's device list. Both accessory families were placed on a real Lock
  Screen and read correctly at their real size.
- **`PrivacyInfo.xcprivacy` and `APP_STORE.md` disagreed.** The manifest declares
  `OtherDiagnosticData` — correctly, because `UserService.registerDevice` sends
  the device model, iOS version and app version — and the nutrition labels said
  Diagnostics was not collected. App Store Connect checks exactly that pair. The
  document was wrong and is fixed; the code is unchanged.
- The supplied App Store plates arrived at **853×1844**, which App Store Connect
  does not accept. Copies at exactly 1290×2796 are in `screenshots/appstore-6.9/`.
  See `APP_STORE.md` §5 for the one judgement call left open about them.
- Verified again and unchanged: the challenge pager browses past two full rounds
  with identical card heights and no jumps, and taking one from deep in the deck
  updates the day; a cold relaunch restores the day, the count, the blade and the
  list; completing an activity moves every widget within a second.

### 2m. The rejected upload (2026-09-04) — **the current state**

The first App Store upload was rejected before review, by the validator rather
than by a person:

```
ITMS-90683: Missing purpose string in Info.plist — NSHealthUpdateUsageDescription
```

#### What was actually causing it

**Forge really does use HealthKit, and the entitlement is intentional.**
`Engine/HealthBridge.swift` imports it, the archived binary links
`HealthKit.framework`, and `Forge.entitlements` carries
`com.apple.developer.healthkit = true`. It is what `VerificationMethod.health`
runs on — the steps, distance and workouts that tick a measurable activity off
by themselves. Nothing third-party is involved: Forge has no package
dependencies at all, and every framework in the binary is Apple's.

**And it is read-only, permanently.** `requestAuthorization(toShare: [], read:)`,
with an empty share set and a doc comment saying it must stay empty. There is no
`HKHealthStore.save`, no `HKQuantitySample` construction and no delete anywhere
in the app.

So the rejection was not "Forge is touching health data it does not need". It was
this: **Apple's upload validation does not look at how the app uses HealthKit,
only that the entitlement is present** — and that entitlement grants read and
write together, so the validator asks for a purpose string for each.
`NSHealthShareUsageDescription` alone has never been enough for a target that
declares the capability. Every read-only HealthKit app hits this once.

**The capability could not be removed instead.** HealthKit *read* access
requires the entitlement; without it `requestAuthorization` fails and the
auto-completion feature stops working. Removing it would have deleted a shipped
feature to satisfy a missing string.

#### What changed

One key in `Forge/Info.plist`:

```
NSHealthUpdateUsageDescription =
  "Forge does not write anything to Health. It only reads the steps, distance
   and workouts your phone already records, so activities it can measure tick
   themselves off."
```

Written as the truth rather than as filler. **iOS will never show it** — the
sheet it belongs to is the one raised by asking for write access, and Forge asks
for none — but if it ever did appear it would be the only thing a person had to
go on, and the day somebody adds a write here, the sentence already in front of
them should be an omission rather than a lie. No code changed, no entitlement
changed, and no behaviour changed.

#### The rest of that class, audited so this does not cost a second round trip

Every framework the archived binary links, checked against the purpose strings
each one demands:

| Framework | Needs a string? |
|---|---|
| HealthKit | **yes, both** — now present |
| AVFAudio | no — `ForgeAudio` sets `.ambient` playback and never records |
| UserNotifications | no Info.plist key; it is a runtime prompt |
| ActivityKit, StoreKit, AuthenticationServices, CoreHaptics, WidgetKit | none |

And nothing in the source touches `CLLocationManager`, `AVCaptureDevice`,
`PHPhotoLibrary`, `CNContactStore`, `CMMotionManager`, `SFSpeechRecognizer`,
`CBCentralManager`, `EKEventStore` or `ATTrackingManager` — zero hits, each.
HealthKit was the only one of its kind, and it is answered.

#### Verified after

A clean **Release** build and a real signed **archive**, whose
`builtin-validationUtility -validate-for-store` pass is the same one that
produced the rejection. In the archived `Forge.app`: both HealthKit strings
present, `CFBundleIconName => AppIcon`, `UIDeviceFamily = [1]`, the HealthKit
entitlement on the app and **not** on the widget extension. 549 tests still
passing.

> ⚠️ **The archive on this machine is signed with an Apple *Development*
> identity**, because that is the only certificate in the keychain — so it
> carries `get-task-allow = true` and must not be uploaded as-is. Distribute it
> through Xcode's Organizer (or with a distribution profile), which re-signs it;
> the Info.plist this fix is about is unaffected by that step.

#### Also, two micro-adjustments to the scene

`rockLeft` +8 → **+4** and `crackDrift` 5 → **1**: the stone a few points
further left, the fissures with it. And the socket's dark marks up 2pt each —
`contactOcclusion` to `mouth + 0`, `bladeCast` to `mouth + 5`. Sizes,
feathering, opacities, scale and vertical position of everything else are
untouched; see §2l.6 for the measurements after.

### 2n. The account removed (2026-09-15) — **the current state**

The build that cleared `ITMS-90683` reached a human reviewer, and came back
**Guideline 2.1 — Information Needed**. 2.1 is a question rather than a verdict,
and the question an app like this one gets asked is always some form of *we
found a sign-in; give us an account we can use, or tell us what is behind it.*

#### Why the answer was to delete it rather than to answer it

The honest answer would have been "nothing is behind it" — and that is precisely
the problem with keeping it. In 1.0 the account bought exactly one thing, backup
and sync, and it sat in Settings as two system buttons a reviewer could press on
a screen where nothing else in the app required them. Everything downstream of
those two buttons was App Review surface with no user benefit attached:

- a demo-credentials question on every submission, for a feature no reviewer
  needs in order to review the app;
- a Delete Account flow, required of every app that lets somebody make an
  account, which existed only to undo something nobody had to do;
- five nutrition-label rows — email, user id, user content, purchases,
  diagnostics — all of them "yes, but only if you sign in";
- a Sign in with Apple entitlement;
- a Google button opening `ASWebAuthenticationSession` against a project whose
  OAuth provider configuration is not checked by anything in this repository,
  so the failure mode in front of a reviewer was a web sheet that goes nowhere;
- and a footer in Settings promising that signing in "makes backup and sync
  possible", which was the app making a claim about itself on a screen the
  reviewer was already standing on.

Against that: **no feature in Forge has ever needed an account.** The day, the
pull, the record, the Shape, Plan, the review, the widgets and the Live Activity
all read the App Group and nothing else. That was the promise `SupabaseConfig`'s
doc comment made from the beginning — *"with no project configured, every
service is inert and Forge is exactly the local-only app it was before"* — and
this is the release that takes it up on it.

#### What actually changed, and it is five things

1. **`Views/Settings/AccountSection.swift` is deleted.** It was the only
   user-facing auth surface in the app: Sign in with Apple, Continue with
   Google, Sign Out, Delete Account, the backup status line and the footer.
   Nothing else referenced it.
2. **The Supabase project is out of `Forge/Info.plist`.** This is the load-
   bearing one. `SupabaseConfig.fromBundle()` now answers nil, so no
   `HTTPClient` exists, so `AuthService.restore()` refuses before it reads the
   keychain, so `SyncService.isEnabled` is false, so **no request of any kind
   can be formed** — including for a returning user who signed in to an earlier
   build, who is signed out by the absence of the project alone.
3. **`ContentView` no longer builds a `ForgeBackend` at all.** The `@State`, the
   `LivePracticeBridge`, and the nine `syncNow` / `syncSoon` /
   `refreshCredentialState` / `premiumChanged` call sites are gone, and
   `RemoteForgeAI`'s token closure is `{ nil }`. The day's path never held a
   reference to any of it, which is why this was a deletion rather than a
   refactor.
4. **`com.apple.developer.applesignin` is off the entitlements**, and the proof
   is in the binary: `otool -L` on the Release build no longer lists
   `AuthenticationServices`. The auth code is dead-stripped.
5. **`PrivacyInfo.xcprivacy` declares an empty `NSPrivacyCollectedDataTypes`.**
   All four rows existed only for a signed-in account. A manifest that keeps
   claiming collection the binary cannot perform is the one mismatch App Store
   Connect checks automatically.

#### What was deliberately *not* done

**`Backend/` still compiles and is still in the target.** Sixteen files of auth
and sync, a merge engine with tombstones and last-write-wins, and the tests that
hold it down. Deleting it would also mean deleting `Net/`, which `AIEndpoint`
builds on, which `RemoteForgeAI` owns, which carries `AIBrief`,
`AIWirePlan.resolved(against:)` and `ReviewObservation.validate(_:against:)` —
types that `PlanSheet`, `AIDisclosureView` and the weekly review all read. That
is a day's refactor of working code, on a submission build, for a benefit a
reviewer cannot observe: **dead code is not App Review surface.**

What makes it safe rather than merely convenient is that severance is
mechanical and tested, not a matter of nobody happening to call it.
`BackendRegressionTests.theAppShipsWithNoAccount` fails the run if either
Info.plist key comes back, and `anUnconfiguredAuthServiceIsInert` fails it if an
unconfigured `AuthService` ever reaches a session. Putting the account back is
therefore a deliberate act that deletes a test, not an accident.

#### One thing fixed on the way past

`AIDisclosureView`'s **"Where it goes"** section named Forge's server and
Anthropic's API unconditionally — two screens below an opening sentence saying
*"No model is connected in this build, so nothing below is ever sent."* Both
cannot be true. It now follows `isConnected` like the title and the opening
already did, and reads *"Nowhere. Everything above stays on this phone."* A
screen whose entire purpose is to be checkable against the binary cannot end on
a description of traffic the binary is incapable of.

#### What this costs

Backup and sync, which nobody had. A new phone is a fresh start, and the only
route off a device is the image the user exports themselves. That is the trade,
and it is recorded here so 1.1 can reverse it deliberately: the engine is
intact, the merge is tested, and turning it back on is `Info.plist` plus
`AccountSection` plus the five documents in `APP_STORE.md` §1 that describe what
an account collects.

#### Verified after

A clean **Release** build; 551 tests in 40 suites passing; `otool -L` showing
Apple frameworks only and no `AuthenticationServices`; the built `Info.plist`
carrying no `ForgeSupabase*` key, `CFBundleIconName => AppIcon`,
`CFBundleVersion => 2` and both HealthKit strings. And a **fresh install walked
end to end in the Simulator**: first run, three activities chosen, one
completed, the sword pulled, the day earned, the blade celebration, the
notification primer declined, a second activity completed and the state moving
from 1 of 3 to 2 of 3, all four tabs opened, Settings read to the bottom with no
Account section on it, the Privacy Policy row opening the live page, and a cold
relaunch that kept the day and did not replay the onboarding.

### 2o. 1.0.1 hygiene (2026-09-25)

A small release of fixes found looking at 1.0 on a phone. Nothing in §5 moved;
the chapter threshold is the one behaviour change, and it only hides a link.

1. **Scripture on the wall.** `ForgeQuotes` gained 23 short Bible verses
   (Philippians 4:13, Joshua 1:9, Proverbs 24:16, Isaiah 40:31, Romans 5:3–4,
   1 Corinthians 9:24 and 9:27, 2 Timothy 1:7, Galatians 6:9, Proverbs 27:17,
   James 1:2–4 and a dozen more), spread over the six themes and attributed to
   book, chapter and verse. KJV wording, or a close modern rendering of it —
   see the note on `AttributedQuote`. Every existing line stays (21 → 44). The
   Batman and Rocky lines named in the brief were already removed on
   2026-09-15 (§2n era, see `ForgeQuotes.resilience`) and were not re-added.
2. **"What do you want to build?"** Skip is a text button top-right; the
   capsule is only Continue (disabled until something is chosen). The six
   `RitualCategory.meaning` lines are one short line each (≤ 32 chars) so the
   sixth row is not clipped. `FocusHexagon.reach` is 0.55 chosen / 0.22 not,
   so choosing draws an intention rather than a finished shape.
3. **"Choose three".** Fixed title "Pick three for today."; the button reads
   "Choose 3 · N selected" until three are picked (`FirstRunCopy`).
4. **Home, first day.** The scene's badge reads **DAY ONE** at zero days kept
   (`HomeCopy.daysBadge`). The loose prompt carries one line of what is still
   on today — "2 left · Deep work, Wake up" — which is only ever non-empty
   under the first run's grace (`ForgeViewModel.leftToday`, `HomeCopy.leftLine`).
5. **Blade tab.** "Close this chapter" appears only once the chapter has run
   14 days (`ChapterReading.canClose`, counting the opening day as day one).
   "Your blades · N of 6" verified: six earnable blades, one per blade rung of
   `Ladder` above the zero-day Starter; a test pins the two together.
6. **One primary button.** `ForgeButton` (cream `.glassProminent` capsule) was
   already the primary component, so it is reused rather than duplicated as a
   `ForgePrimaryButton`. The challenge sheet's blue "Accept" / "Take this one"
   / "Mark it done" now use it, and the sheet opens at `.medium` (`.large` on
   drag).

Tests: quote counts and the named verses (`ForgeQuoteTests`), the 14-day
threshold and the blade counter against `Ladder` (`ChapterTests`), and the
copy above (`FirstDayCopyTests`). Written on Linux without a build — run the
suite in Xcode before tagging.

### 2p. Telemetry (2026-09-25)

Forge could not answer the first question about its own launch: where people
leave. Which beat of the first run, whether the pull is found, whether a
re-entry brings anybody back. So it counts those — anonymously, and only those.

#### What was built

- **`Engine/ForgeTelemetry.swift`**, the only file that imports TelemetryDeck
  (app id `5E5C19F4-…-68E6FDFE47C5`). An `Event` enum, one `send(_:)`, and
  `start()` from `ForgeApp.init`. No call site names a signal as a string or
  touches the SDK. The Swift package was already referenced by the project;
  this links its `TelemetryDeck` product into the Forge target.
- **The events, and only these:** `app_first_open`, `onboarding_beat_view{beat}`,
  `onboarding_focus_chosen{count}`, `onboarding_completed`,
  `first_pull_completed`, `activity_completed{method}`, `day_earned`,
  `pull_abandoned`, `challenge_accepted`, `challenge_completed`,
  `activity_added{source}`, `notification_opened{kind}`,
  `weekly_review_completed`, `reentry_shown`, `reentry_recovered`,
  `chapter_closed` — and, defined with no call site until the paywall lands,
  `paywall_view{door}`, `paywall_dismissed{door}`, `trial_started{plan}`,
  `purchase_completed{plan}`, `restore_tapped`.
- **Every parameter is a closed value.** `beat`, `method`, `source`, `kind`,
  `door`, `plan` are raw values of enums; `count` is a number. No case can carry
  an activity name, an identity, a chapter, a review, a quote, a chosen time or
  a HealthKit reading. `TelemetryTests.payloadsAreClosed` holds the key set.
- **`days_since_install` on every signal**, and nothing new stored to know it:
  `ProgressStore.firstRecordedDay` is the oldest day in the history, and Forge
  writes today's record on first open (the planned list goes down before
  anything is done), so that day is the install day. Handed to telemetry as a
  closure from `ContentView`, which holds the store.
- **Settings → Privacy → "Share anonymous usage"**, on by default, one
  sentence under it. Stored under `forge.shareUsage.v1` in the App Group.
  Off means `send` returns before anything is built; nothing is queued.
- **Silent under test**, by `ForgeTelemetry.isRunningTests`, checked on every
  send. The SDK's automatic session signal is off, so the list above is the
  whole of what Forge sends by name; turning the switch off mid-session also
  sets the SDK's own `analyticsDisabled`.

#### Where each event fires

| Event | Call site |
|---|---|
| `app_first_open` | `ContentView` launch pass: first run not finished, on the day of the first record. A relaunch mid-onboarding that day counts again; read unique users. |
| `onboarding_beat_view` | `ForgeViewModel.firstRunStage` `didSet`; the opening `promise` beat from the launch pass. |
| `onboarding_focus_chosen` | `FirstRunView.advance`, leaving *build* for *choose*. Zero for Skip. |
| `onboarding_completed` | `ForgeViewModel.finishFirstRun`. |
| `first_pull_completed`, `day_earned`, `reentry_recovered` | `ForgeViewModel.isOut` setter, when the day goes from not earned to earned. Recovered = the `ReEntry` gap was open the moment before. Undo-and-pull again re-sends `day_earned`. |
| `activity_completed` | `tick` (`basic`) and `keepPromise` (`honor`), only when newly done. |
| `pull_abandoned` | `SwordEngine.dragEnded`, slipped back after moving past 5%. |
| `challenge_accepted` / `_completed` | `ChallengeStore.accept`, `take`, `complete`. |
| `activity_added` | `AddActivitySheet` (`library`, `custom`), Becoming's offer (`becoming`), `ForgeViewModel.apply` (`plan`). |
| `notification_opened` | `ContentView`, on `notifications.opened`. |
| `weekly_review_completed` | `ReviewStore.answer`, first answer for a week only. |
| `reentry_shown` | `ContentView.offerWhatIsDue`. |
| `chapter_closed` | `ChapterStore.close`. |

#### The network, now

One host, `nom.telemetrydeck.com`, in `ForgeNetwork.allowedHosts`.
`URLSessionTransport` refuses every other host with `.notConfigured` before a
socket exists — so even a Supabase project pasted back into `Info.plist` could
not connect. `NoNetworkTests` checks the list is exactly that host, that
look-alikes and plain http are refused, and — with a `URLProtocol` tripwire
standing where the network would be — that a request elsewhere never reaches
the session while the allowed host does. `BackendRegressionTests` does the same
through `HTTPClient` with a project configured. Adding a host means changing
both tests, the manifest and the labels together.

#### Privacy

`PrivacyInfo.xcprivacy` declares **Product Interaction** and **Other Diagnostic
Data** (what the SDK attaches to every signal: device model, OS and app version, screen size, language, locale, region and time zone, appearance and accessibility settings, and its own anonymous session counts (sessions, days used, first-session date)), Analytics, **not linked**, **not
tracking**. `APP_STORE.md` §1, the review note in §6 and the §8 checklist say
the same. The hosted policy at forgebetter.app/privacy needs the paragraph in
the PR description before the next submission.

#### Also

The Becoming tab's sign is now a solid diamond plate with a turn-right arrow
knocked out of it (`BecomingSign.svg`, same asset name, same template
rendering) — see `AppTab.image`.

#### Not verified

Written on Linux with no build. The TelemetryDeck calls (`Config`,
`sendNewSessionBeganSignal`, `analyticsDisabled`, `initialize`, `signal`) were
checked against the SwiftSDK 2.14.2 source but not compiled; the first signals
should be checked in the TelemetryDeck dashboard in Test Mode, which the SDK
turns on by itself for Debug builds.

### 2q. AI without an account (2026-09-25)

Forge's model jobs need a server — the key cannot ship in the app — and the
server needs to know *who* is calling, to cap spend. §2n took the account out
and it is not coming back for this. So the caller is an identity nobody sees,
and entitlement is proven by Apple's own signature rather than by anything
Forge stores.

**Status: the backend is built and tested; the app side is wired but switched
off.** `RemoteForgeAI.isModelEnabled` is still `false` and there is still no
project in `Info.plist`, so the shipped app makes no request and nothing in
§7's network table changes. Turning it on is `supabase/README.md` §1, then a
separate app PR (README §1.9).

#### The identity: anonymous, invisible, required

- **`AnonymousIdentity`** (`Backend/Auth/`) calls GoTrue's anonymous sign-up
  (`POST /auth/v1/signup` with an empty body — what the SDKs call
  `signInAnonymously`). It gets a real Supabase user: a random uuid with no
  email, password, provider or name. Needs *Allow anonymous sign-ins* on in the
  dashboard.
- **Nothing visible.** No sign-in screen, no Settings row, no state any view
  observes, no word anywhere in the UI. `AuthService` — the dormant visible
  account — never sees it. The session is in the Keychain under its own
  account, this device only; a new phone mints a new one.
- **Minted lazily, and only for Premium.** `RemoteForgeAI.connect()` asks for
  the proof of purchase *before* the token, so somebody without Premium never
  has an identity created for them.
- **The JWT is required.** `verify_jwt` stays on (never deploy with
  `--no-verify-jwt`), and the function resolves the user with
  `auth.getUser()`. An anonymous user alone gets nothing: 402.
- Failure is always the fallback: offline, sign-ups off, refresh refused — the
  token is nil and `LocalForgeAI` answers, labelled as the phone's.

#### The entitlement: StoreKit 2 JWS, verified offline

- The app sends `jwsRepresentation` of its best current Premium transaction
  (`ForgeStore.entitlementProof`: lifetime first, else the longest unexpired
  unrevoked subscription; only transactions StoreKit verified on-device) in
  **`X-Forge-Transaction`**.
- `supabase/functions/forge-ai/storekit.ts` verifies it with no network and no
  App Store Connect key: the `x5c` chain (leaf → Apple WWDR intermediate →
  root), the root pinned to **Apple Root CA G3** by SHA-256
  (`63343abf…3e9179`), every signature in the chain, CA constraints, Apple's
  intermediate and receipt-signing OIDs, validity at the transaction's
  `signedDate`; then ES256 over the JWS; then the claims — bundle id
  `com.dawid.forge` (from the Xcode project), product id one of
  `com.dawid.forge.premium.annual` (auto-renewable, `expiresDate` must be in the
  future) or `…premium.lifetime` (non-consumable), no `revocationDate`, and the
  environment.
- ~~There is no monthly product.~~ **Superseded by §6 (Forge Pro, 2026-09-27):**
  `…premium.monthly` is sold and is in `PREMIUM_PRODUCTS` as a renewable.
- **Production vs Sandbox.** Only `Production` is accepted unless the server
  secret `FORGE_ALLOW_SANDBOX` is exactly `true`. `Xcode` (local StoreKit
  testing) is always refused — it is not Apple-signed. TestFlight and App
  Review purchases are Sandbox; see README §1.6 for the trade-off.
- Every failure — missing, malformed, forged, untrusted chain, wrong bundle,
  wrong product, expired, revoked, disallowed environment — is **402**.
- Trust is injectable for tests only: the tests generate a CA chain per run,
  and one test checks the production policy refuses it. No Apple-signed
  fixture was fabricated.

#### Quotas: per user and per purchase

- 0007's `claim_ai_call` (per Supabase user per UTC day) is kept.
- **0008** adds `ai_usage_by_transaction`, keyed by the verified
  **`originalTransactionId`** — read only from the Apple-signed payload, never
  from the body or a header — so one purchase cannot power unlimited anonymous
  identities.
- `claim_ai_entitled_call` applies both atomically (row-locked upserts, fails
  closed): **10 calls a day per purchase**, 10 per user. A weekly reading and a
  handful of plans is far under it. No purchase: 0 calls.
- 0008 also revokes 0007's functions from `PUBLIC`: they had been executable by
  client roles, so a caller could spend somebody else's per-user allowance
  (never raise it).

#### The model: OpenAI, two jobs, fixed per task

- **OpenAI Responses API** (`POST /v1/responses`), strict JSON-schema output,
  `store: false`, a timeout, no tools, no conversation. Not a chat feature.
- **Reading → `gpt-6-sol`** (quality is the product: a claim about somebody's
  own week). **Plan → `gpt-6-luna`** (structured interpretation, re-checked on
  the phone). Separate constants in `prompts.ts`; the client cannot choose.
- The provider sits behind `ModelProvider` (`openai.ts`); nothing about
  OpenAI's response format reaches the handler. Outcomes map to the statuses
  the app already falls back on: refusal 422, empty/malformed/upstream 502.
- The **challenge** job is retired server-side (400) and client-side (always
  the catalogue), matching §2j.3.
- The Reading rules now forbid medical advice, diagnosis, reading any activity
  as a symptom, and recommending treatment, medication or a professional.
  `ReviewObservation.validate` is unchanged.

#### The key

**`OPENAI_API_KEY` exists only as a Supabase server secret.** Not in Swift,
`Info.plist`, config, tests, logs, Git or PRs; the function logs only a task
and a reason. **No AI key is bundled in the app** — the app has never held one.

#### Also

- `ClaudeForgeAI` is now **`RemoteForgeAI`**, and every Anthropic reference in
  production code, the function and the setup docs is gone. (0007's comments
  still say Anthropic; it is an applied migration and is left as written.)
- `AIDisclosureView`'s connected wording names OpenAI and the anonymous
  identifier. It is only shown once the model is on.

### 2r. AI prepared, activation pending (2026-09-28)

**Status: the whole iOS side of Forge's AI is built, tested against scripts,
and switched off.** `RemoteForgeAI.isModelEnabled` is still `false`, there is
still no Supabase project in `Info.plist`, **no real `OPENAI_API_KEY` is
configured anywhere**, and no test or build makes a real OpenAI or Supabase
call. A later, small activation PR turns it on (checklist at the end).

#### What is implemented

- **AI UX and consent.** `AIConsentStore` (App Group key `forge.aiConsent.v1`:
  `undecided` / `allowed` / `declined`). `AIDisclosureView` is also the consent:
  it explains **what** is sent (the `AIBrief`, rendered, plus Plan's typed
  request), that it goes to **Forge's backend** (Supabase), that **OpenAI**
  processes it behind that backend, that the user's **own words** may be
  processed for the feature, and that it is **not used for advertising or
  tracking** — then **Allow** / **Not now**. It is raised by `View.aiConsent`
  only when a button that would reach the model is pressed (Plan's "Work it
  out", the review's "Read my week"), and only in a build where the model is
  reachable — **never at launch**, never on opening Settings or a review.
  **Not now** stores `declined`; the request then runs and `RemoteForgeAI`
  answers from `LocalForgeAI`, sending nothing. Revocable in **Settings →
  Planning** (row + "Turn off Forge's AI", and inside the disclosure).
- **The order of checks** (`RemoteForgeAI.connect`), each stopping the next:
  the switch → consent → the StoreKit proof → the anonymous identity. So the
  identity is created **only for a Pro user, after consent, when a request is
  actually attempted**.
- **Anonymous Supabase identity stays invisible.** `AnonymousIdentity` (§2q) is
  unchanged: no UI, Keychain-only, minted lazily inside `connect()`. No
  `AccountSection`, no Apple/Google sign-in, no sync UI —
  `BackendRegressionTests.noVisibleAuthentication` now scans the app's views and
  entitlements and fails if any user-visible authentication path returns.
- **StoreKit JWS proof prepared.** Every remote request carries
  `X-Forge-Transaction` = `jwsRepresentation` of the best current Forge Pro
  entitlement (`ForgeStore.entitlementProof`, unchanged). Backend verification
  (§2q) is untouched.
- **Weekly Reading Pro UX prepared.** The rules' observation is **free, first,
  and shown to everybody** (this reverses PR #4's gating of it). Under it
  (`WeeklyReviewReading.parts`): non-Pro → the locked row, door 2 (once);
  Pro with a reachable model → "Read my week" → consent if undecided → the
  model → a validated reading shown under the observation, labelled
  model-written; **Pro in this build → nothing added**, nothing fabricated. The
  reading is no longer requested from `.task` — opening a review cannot create
  an identity.
- **`reading_fell_back`** telemetry (no parameters) fires when a model reading
  fails `ReviewObservation.validate` and the phone's sentence stands. No
  generated or user-written text reaches telemetry.
- **OpenAI stays behind the Forge backend.** The app contains no model key and
  never contacts OpenAI; the only key is the future server secret
  `OPENAI_API_KEY`. Anthropic / Claude is not referenced (the disclosure test
  checks the copy).
- **Local fallback remains active** for every path: switch off, no consent, no
  purchase, offline, sign-ups off, 402/5xx, failed validation.
- **Network allowlist prepared.** `ForgeNetwork.allowedHosts` adds the
  configured project's host only when the switch is on and a project exists;
  today it is still exactly TelemetryDeck's.
- **Test seam.** `RemoteForgeAI(testingEndpoint:…)` is `#if DEBUG` only, so a
  release binary cannot be constructed with a forced endpoint.

Tests: `AIPrepTests` (consent, still-off, the future path against
`ScriptedTransport` + a real `AnonymousIdentity` on a scripted auth endpoint,
Weekly Reading layout), `NoNetworkTests`, `BackendRegressionTests`.

#### ⚠️ Release blocker until activation

`ProFeature.weeklyReading` sells a model-written reading, and with the switch
off Pro adds no Weekly Reading beyond the free observation. **Do not ship a
build that sells Forge Pro before the activation PR**, or change that line
(and the App Store description, `APP_STORE.md` §4) first.

#### Activation — the later PR, after the manual steps

Manual (`supabase/README.md` §1): link the project; enable anonymous sign-ins;
`supabase db push` through `0008`; OpenAI API billing + monthly limit; create
the key and `supabase secrets set OPENAI_API_KEY` (never in the repo); decide
`FORGE_ALLOW_SANDBOX`; `supabase functions deploy forge-ai` (never
`--no-verify-jwt`); run the free smoke test (§1.8).

Code (README §1.9): `ForgeSupabaseURL` + `ForgeSupabaseAnonKey` (publishable key
only) in `Info.plist`; `isModelEnabled = true`; update the tripwires that exist
to fail at exactly that moment (`NoNetworkTests`, `AIStillOffTests`,
`BackendRegressionTests.theAppShipsWithNoAccount` / `onlyTelemetryIsAllowed`);
switch `APP_STORE.md` §1 to the prepared labels, publish the prepared privacy
paragraph (§2), use the prepared review note (§6); update `PrivacyInfo.xcprivacy`.

### 2s. The first week on Becoming, and the Proof Card (2026-09-28)

Local only: everything here is read off the existing record. No model, no
Supabase, no network.

#### The first-week contract (`Models/FirstWeek.swift`)

Before the shape can be drawn, the Becoming hero is one sentence and a bar
instead of "Your shape is forming":

> *Your shape draws itself on Sunday. Until then: three days kept of seven.*

- **When it appears:** from the first recorded day (`ProgressStore
  .firstRecordedDay`, or today for an empty record) until the shape is shown.
- **When the real `ForgeShape` replaces it:** on the draw day — seven days after
  the first recorded day — *if* `ForgeShape.isReadable` (unchanged: two measured
  dimensions, five kept days of credit). A week that ends without enough to read
  keeps the card, with the promise swapped for what is still true: *"Your shape
  draws itself as the days add up. The last seven: two days kept."*
- **Words:** the draw day is named ("on Sunday", "tomorrow", "next Sunday" on
  day one); counts are "no days", "one day", "three days" — spelled via
  `ForgeCount`, never "one days".
- **Progress:** in the opening week, days lived of seven (the draw day comes
  whatever is kept); after it, the last seven's kept days of seven. **Computed
  from `DayRecord.isEarned` on every read — no counter, no flag, no key** (§5
  rule #2; `FirstWeekTests.nothingIsStored`).

#### Empty dimensions get a starter

A dimension nothing is filed under shows, inside its row in The Six, one
restrained line — *Smallest start: <activity>* — and an **Add** button
(`BecomingStarter`). The activity is `ForgeShape.suggestions(…, limit: 1)`: the
lowest-effort **library** activity filed under that dimension that is not
already kept. Never invented, never added without the tap. It goes through
`ForgeViewModel.addRitual` via `BecomingOffer.add`, which sends
**`activity_added { source: becoming }`** and nothing else (no name, no text).
The "Add to your day" list for a weak dimension uses the same path. Because the
row carries it, the next-step card no longer repeats "Nothing is building …".
"Nothing here" and "No days yet" are gone; a dimension with activities but no
day yet reads "Starting".

#### The Proof Card (`Views/Review/PracticeArtifact.swift`)

`PracticeArtifact`, evolved rather than replaced: the sword in the stone
(`hero`), the days kept **in words** ("One day kept", "Forty-two days kept"), a
quiet occasion line, the date, and `forgebetter.app` — nothing else (no
congratulation, no streak, no handle, no user text). Two formats,
**1080 × 1920** and **1080 × 1080**, rendered as PNG only when the share sheet
asks (`ProofCardFile`, `Transferable`), shared through `ShareLink`.

**Exactly two entry points**, each a quiet third action titled *Save the proof*
(`ProofCardButton`, a menu of the two formats):

1. **Blade unlock** — in `SwordUnlockOverlay`, arriving with *Carry it* / *Keep*
   once the celebration has staged; never over the pull.
2. **Chapter close** — in `ChapterCloseView`'s commit bar once *Close this
   chapter* has been pressed. Nothing else about closing changed; the old
   "Save or share" button at the top of that screen is this one, moved.

**Forge never asks for sharing anywhere else**: no prompt at launch, no random
or later prompt, no notification, nothing in an unfinished day, and the share
sheet never opens on its own. `ProofCardTests.proofCardDoors` reads the source
and fails if `ProofCardButton` is placed anywhere else or anything other than
`PracticeArtifact.swift` can open a share sheet.

### 2t. The 1.1 direction (2026-09-29)

The owner fixed the direction of 1.1 in
[docs/DIRECTION_1_1.md](DIRECTION_1_1.md). **Where it disagrees with this file,
it wins.** What it supersedes:

- **§5 #1 is amended, not dropped:** nothing that has already happened is sold
  back, and the record stays readable forever; the ongoing practice is what is sold.
- **§5 #8 is retired:** the three doors go; new installs meet a hard paywall with
  a free week after onboarding (DIRECTION §1). Founders (1.0 / 1.0.1 installs)
  keep everything but AI free.
- **§6 is replaced in session S2** (plans, prices, trial, founders, lapsed state).
- **§8 "numbers as words" is narrowed to prose:** scores, the six stats, OVR,
  prices, dates, times and Arc day counters are digits (DIRECTION §3).
- **The §2g/§2h first run is replaced in session S1** by the transformation
  onboarding (DIRECTION §2).

Progress on each session is recorded in §17.

## 3. The core loop (as built)

```
Plan the day        activities, each with optional start time + weekday repeat
      ↓
Complete them       tap → basic / honor prompt / HealthKit auto-settle
      ↓
Blade comes LOOSE   all of today's activities done  (allDone)
      ↓
PULL the sword      a real drag gesture — the user completes the act
      ↓
Day is EARNED       DayRecord.extractedAt is set; this is the only thing
      ↓             that makes a day count
Summary             one headline + one line + a quote, ~3s, self-dismissing
      ↓
Free state          panel shrinks; evening opens "Tomorrow" after 18:00
```

Supporting loops: a **daily challenge** (deterministic per date, everyone gets
one), an **evening commitment** (settle tomorrow), a **weekly planner** (edit
the recurring routine).

## 4. The systems and how they connect

```
Ritual (activity) ──── id, label, icon, verification, minutes,
   │                   startMinute?, repeats (weekday set), category
   │                   library (28 shipped) + custom + libraryEdits overlay
   ▼
ForgeViewModel ─────── activeRitualIDs = THE DAY (what you keep)
   │                   todayRitualIDs  = TODAY   (after repeat rules)
   │                   ↑ this distinction is the most load-bearing in the app
   ▼
ProgressStore ──────── byDay: [ForgeDay: DayRecord]  ← THE ONLY TRUTH
   │                   every number derived on read; nothing banked
   ├──► daysKept, currentStreak, bankedRest, restDays
   ├──► heatmap(), week(), trends(), completionRate()
   ▼
SwordStore ─────────── 7 blades unlocked by daysKept (0/1/3/7/14/30/60)
MilestoneStore ─────── 5 shipped (1/7/30/100/365 days) + ≤12 custom
ChallengeStore ─────── today's challenge, chosen from the day's own shape
ForgeAppearance ────── the accent the app is drawn in. One of eight, stored,
                       and the only thing about the interface that is a taste
```

**Paths are gone.** `ForgePath`, `PathCatalog` and `PathStore` were deleted with
the Shape redesign; §2c keeps the argument. What replaced them:

```
RitualCategory ──────── the six dimensions. Every activity is filed under one.
   │                    `Ritual.categories` (shipped) + `categoryOverride`
   ▼
ForgeShape ──────────── six scores 0–100 over a rolling 28 days, derived on
  (Analytics.swift)     read. Days, not completions. `presenceFloor` stops one
   │                    easy activity holding a perfect hundred forever.
   ▼
ForgeViewModel.focus ── what somebody SAID they want to build. Stored, any
                        number of the six, empty is ordinary. The only thing here that is
                        not derived, and the reason `DayPlanner` can say
                        anything useful — see §2g.
```

**Commitments** (`Models/DayCommitment.swift`) are deliberately thin: the day you
arrange in the evening *is* `activeRitualIDs`. All that's stored is the fact you
looked at it and said yes. A second stored list would be a second answer to
"what is my day."

**Chapters do not exist.** Planned only — see §13.

## 5. Product principles that must not be broken

These are enforced by design and documented in-code. Read the relevant file's
doc comments before touching any of them.

| # | Principle | Where |
|---|---|---|
| 1 | **Nothing that has already happened is ever sold back.** The history, heatmap, trends, streak, blades, milestones, rest days and widgets are free forever. Charging to view your own record is charging rent on your own life. | `Premium.swift` |
| 2 | **Nothing is stored that can be derived.** No banked streaks, no cached counts. The "badge says 12, calendar shows 9" bug class is unreachable. | `ProgressStore.swift` |
| 3 | **Nothing manufactures a problem to have something to say.** A weakest dimension is only named when it is genuinely behind (`needsAttention`, 15 points), a `DayPlanner` move only fires when its condition is actually met, and a tidy week gets an empty screen that says so. | `ForgeShape`, `DayPlanner` |
| 4 | **Nothing congratulates.** The furthest the app goes is noticing out loud that a decision stopped being made. No exclamation marks, no praise, no promises about outcomes. | `DaySummary`, `PathVoice` |
| 5 | **One progression against one number.** Blades and milestones counted days kept at nearly the same thresholds on the same screen; they are one `Ladder` now. Nothing may add a second. | `Ladder` |
| 6 | **The app never plays a character.** No person to be, no costume to wear. Enforced now by there being nothing left that could — see §2c for why the worlds went. | — |
| 7 | **A suggestion appends and never removes.** Adding what Becoming or Plan offers can never cost somebody the list they spent months tuning — which is why there is no confirmation dialog in front of one. A dialog in front of an offer is the app admitting the offer is risky. | `ScheduleChange.adopt`, `ForgeViewModel.addRitual` |
| 8 | **Forge asks about money at three doors, each at most once, in order — and never over a day.** *Changed on purpose with Forge Pro (2026-09-27); this replaces "asks once, ever … after 5 days kept, on the Blade tab".* The doors: after the first blade celebration closes; a locked Weekly Reading row at the first review that has a reading; an invitation at the first chapter close. Never at launch, never during the day flow or the pull, never in the first run, never to a Pro install, and a later door retires any earlier one it overtook. Tapping a locked control is somebody asking and is not rationed. See §6. | `PremiumInvitation` |
| 9 | **Nothing writes to the schedule without being read first.** `DayPlanner` and any model both propose `ScheduleChange` values; `ForgeViewModel.apply` is reached only from a button that says how many changes it is about to make. | `SchedulePlan.swift`, `PlanSheet` |
| 10 | **Never claim a model wrote something it didn't.** `isConnected` and `isModelWritten` are surfaced, never hidden. | `ForgeAI`, `LocalForgeAI` |
| 11 | **Rest days are not misses.** They neither break nor extend a chain. | `ProgressStore.restWeekdays` |
| 12 | **The day is a practice, not a calendar.** Activities are standing arrangements (weekday set + time), not dated instances. | §11 |

## 6. Free vs Forge Pro

**Forge Pro is sold from 1.1 (2026-09-27).** The decisions below are final
business decisions and are recorded here as **deliberate changes** to what 1.0
said: §5 rule #8 ("asks once, ever") and the "no monthly plan" argument that
used to head `Premium.swift`. Neither is an accident to be reverted.

**The line.** Forge is free. **Pro reads your record back to you.** Everything
that *is* the record stays free forever (§5 rule #1, unchanged): the day, the
pull, history, heatmap, trends, streak, blades, milestones, rest days,
chapters, the weekly review's marks, count, last week's line and both
questions, every answer ever written, Becoming, Plan's own moves, the widgets.

| Pro adds | Gate | Where |
|---|---|---|
| **Weekly Reading** — a model-written reading *under* the free rules' observation, requested with "Read my week" (§2r; nothing is added while the model is off) | `PremiumGate.showsWeeklyReading`, `WeeklyReviewReading.parts` | `WeeklyReviewView.weeklyReading` |
| **Plan in your own words** — the free-text field | `PremiumGate.canPlanInWords` | `PlanSheet.askInWords` |
| **Eight accents** — accent 1 (Forge blue) is free, 2–8 are Pro | `PremiumGate.isLocked` | `AppearanceView` |

A lapsed install falls back to Forge blue once StoreKit has *answered* — never
on the `.free` placeholder `ForgeStore` starts with (`hasReadEntitlement`). Since
§2r the paywall's Weekly Reading line (`ProFeature.detail`) describes the
model-written reading, which exists only once remote AI is activated — see the
release blocker in §2r (§5 rule #10).

**Products** (`PremiumProduct`, `Forge.storekit`, App Store Connect and
`forge-ai`'s `PREMIUM_PRODUCTS` must all agree — `PremiumTests.storekitFile`
reads the `.storekit`):

| | Monthly | Annual | Lifetime |
|---|---|---|---|
| Product ID | `com.dawid.forge.premium.monthly` | `com.dawid.forge.premium.annual` | `com.dawid.forge.premium.lifetime` |
| Type | Auto-renewable, group *Forge Pro* | Auto-renewable, same group, same level | Non-consumable |
| Price (US) | $9.99 / month | $49.99 / year | $99.99 once |
| Intro offer | — | **7-day free trial** (1 week, free) | — |

**Monthly is back on purpose.** 1.0 refused it ("charging rent … re-decided
twelve times a year"). Pro is a reading, and somebody deciding whether a reading
is worth anything should be able to try it for a month. Annual stays the default
and the only plan with a trial; lifetime stays for anybody who never wants to
be asked again. Lifetime outranks a subscription (`PremiumEntitlement.resolve`).

**The paywall** (`PaywallView`): black, the sword in the stone (`hero`), the
headline *"Forge is free. Pro reads your record back to you."*, the three
benefits, annual selected (*"7 days free, then $49.99/year"* when StoreKit says
the account is eligible), monthly and lifetime under it, `ForgePrimaryButton`,
**Restore purchases**, **Not now** pinned and always visible, the renewal terms
for the selected plan, Terms of Use (Apple's standard EULA) and the Privacy
Policy. **Every price is `Product.displayPrice`**; `PremiumCopy` only builds the
words around it.

**The three doors** (`PremiumInvitation`, App Group key
`forge.paywallDoors.v1`, each at most once, in order):

1. **First blade** — after the first blade celebration *closes*. Inside the
   first run (where "Struck" is always earned) it waits until the first run
   finishes. For an install upgraded from 1.0, it is the next blade.
2. **Weekly Reading** — the first weekly review that *has* a reading shows a
   locked, redacted row in its place (a placeholder, never this week's sentence
   blurred). Tapping opens the paywall; seeing it spends the door. A first week
   with no reading does not spend it.
3. **Chapter close** — `PremiumInvitationView`, one card at the foot of
   `ChapterCloseView`, below everything the person came to read.

Never: at launch, during the day flow or the pull (`doorMoment.isDayInProgress`),
in the first run, over a summary or celebration, or to a Pro install; and until
StoreKit has answered, the install is treated as Pro. The locked controls
(accents, Plan's field) and **Settings → Forge Pro** open the paywall whenever
tapped — that is somebody asking, not a door.

**Settings → Forge Pro** (top of Settings): status (Free / Forge Pro · plan),
See Forge Pro, Restore Purchases, and — for a subscription — Manage
Subscription via `AppStore.showManageSubscriptions(in:)`.

**Telemetry** (§2p, no new keys): `paywall_view` / `paywall_dismissed` with
`door` (`first_blade`, `weekly_reading`, `chapter_close`, `accent`, `plan`,
`settings`), `trial_started` and `purchase_completed` with `plan` (a trial is
never counted as a sale), `restore_tapped`.

**Still rejected**, each of which a growth team would suggest first:

- *Capping the history* — charging rent on someone's own life.
- *Capping activities per day or edit frequency* — makes the free app worse
  exactly where it's supposed to be good, and punishes beginners hardest.
- *Gating a whole tab* — a fully locked tab is an advertisement wearing a tab bar
  icon, and it teaches people to stop tapping it.
- *A paywall at launch, in onboarding, on a timer, or over the day* — see the
  doors above.

## 7. Planning, and where a model would plug in

**1.0 makes no model request of any kind.** `RemoteForgeAI.isModelEnabled` is
`false`, which forces `endpoint` to nil in every construction of the type. There
is then no object in the process able to form the request: `AIEndpoint` is the
only thing that builds one, and every method opens with `guard let endpoint` and
falls to `LocalForgeAI`. Because a `guard` stops at the first failing condition,
the `await token()` beside it is never evaluated either — so this also stops the
session refresh that asking for a token can trigger.

Three call sites were live; all three are local, and one no longer exists:

| Call | Was reached from | Answers now |
|---|---|---|
| `plan` | Plan's free-text field | `LocalForgeAI` — work hours, frequencies, a whole-week shift, moving one activity |
| `challenge` | The challenge generator — **deleted, see §2j.3** | always the catalogue; the backend no longer serves it (§2q) |
| `reading` | the weekly review's **"Read my week"** (Pro), behind consent — §2r | `ReviewObservation`, the rules |

That third one used to be the only outbound request in the app not behind a
button (it ran on `.task`), and it carried the widest payload — `ReviewFacts` on
top of the brief. Since §2r it is behind a button and consent, and
`ContentView` still passes `betterReading: nil` while the model is off.

**Plan's own suggestions never went through any of this.** `DayPlanner` (§2g)
computes them from the record before `ForgeAI` is consulted at all, so the
feature is unchanged by the model being off.

```swift
protocol ForgeAI: Sendable {
    var isConnected: Bool { get }
    func challenge(brief:difficulty:focus:wish:) async throws -> DailyChallenge
    func plan(brief:request:) async throws -> SchedulePlan
    func reading(brief:) async throws -> PracticeReading
}
```

### Turning it back on

**Superseded in detail by §2r's activation list.** The short version still
holds: change one `false` to `true`. Not one line of UI, not one screen, not one
string: `isConnected` starts returning true and the disclosure screen, the
Settings footer, the review's closure and Plan's field all swap on their own,
because every one of them already branches on it. The wire types
(`AIWireBrief`, `AIWirePlan.resolved(against:)`) and the validator
(`ReviewObservation.validate(_:against:)`) were not deleted.

Before flipping it: everything in `supabase/README.md` §1 — anonymous sign-ins
on, migrations through `0008`, `OPENAI_API_KEY` set, `forge-ai` deployed — then
the project in `Info.plist`, and **restore `APP_STORE.md` §1**: the privacy
nutrition labels currently answer "not collected" on the strength of the
constant, and `NoNetworkTests` is the tripwire that makes the two impossible to
change separately. What a request carries once it is on — an invisible
anonymous JWT and the StoreKit transaction — is §2q.

### The architecture that has to survive a model arriving

- **A plan is a reviewable diff, not prose.** `SchedulePlan` is a list of
  `ScheduleChange` cases, each carrying **what it replaces** — so the review
  screen says "07:00, was 09:30". A model that answers in prose leaves the user
  the same work they had, plus reading.
- **`AIBrief` is the transmission surface and the only thing that would ever
  leave the phone.** `DayPlanner.Facts` is deliberately *wider* — the Shape,
  four weeks of per-activity counts, the rest days — precisely because it never
  leaves. Two structs, and which one a value is in says whether it can be
  transmitted. Do not widen `AIBrief` to feed a local rule.
- **`LocalForgeAI` is an honest stand-in**, not a stub that throws. It does real
  constraint arithmetic (busy windows, frequency spreading, 5-minute rounding),
  and it refuses honestly rather than guessing at sentences it cannot parse —
  and `ForgeAIError.notConnected`'s message now teaches the grammar that does
  work instead of promising a connection that is not coming.
- **A reading is checked before it is shown.**
  `ReviewObservation.validate(_:against:)` holds a model sentence to four rules
  before anybody reads it. See §2f.

**The honest division of labour when a model arrives:** `DayPlanner` keeps
deciding *what is worth changing*, because it can see the record; the model
widens *what somebody can ask for in their own words*, which is the one thing
arithmetic cannot do. Both produce a `SchedulePlan`, both go through the same
review screen and the same `isModelWritten` flag.

### Everything else that touches the network

Re-audited **2026-09-25**, when anonymous usage was added (§2p):

| Path | Starts when | Gated on |
|---|---|---|
| StoreKit | launch, and on any transaction | Apple's own, no user data |
| TelemetryDeck, `nom.telemetrydeck.com` | an event in `ForgeTelemetry.Event` | **Share anonymous usage** (on by default); never under test |

**That is the whole table now.** `ForgeNetwork.allowedHosts` is exactly the
TelemetryDeck host, `URLSessionTransport` refuses anything else before a socket
exists, and `NoNetworkTests` / `BackendRegressionTests.onlyTelemetryIsAllowed`
fail the run if either changes. Sign-in, token refresh, sync, device
registration and the entitlement row every one required a Supabase project and
a session, and there is neither — `SupabaseConfig.fromBundle()` answers nil, so
no client is constructed and no request can be formed. There is no remote push
(the Live Activity is `pushType: nil`), no remotely loaded image or asset, no
attribution or crash SDK, and no third-party host or framework other than
TelemetryDeck's — see §2p.

## 8. UX and design principles

- **Dark, cinematic, one room.** Lit from the upper left; every sprite has that
  baked in. **The scene is not a preference** — the accent (§2g) never touches
  the room, the stone or the blade.
- **Liquid Glass** (`.glassEffect`, `.glassProminent`, `GlassEffectContainer`)
  throughout. Native tab bar with `.tabBarMinimizeBehavior(.onScrollDown)`.
- **Numbers as words.** "Thirty days" is a fact about a person; "30" is a score.
  Figures take back over past 100 (`ForgeCount.spelled`).
- **The panel never eats the scene.** The sword has a floor (`sceneFloor: 210`);
  the panel's ceiling gives way first. A panel that grows until the blade is a
  strip has turned Forge into a list app with a wallpaper.
- **Unfinished work floats to the top** of each part; finished drops to the
  bottom in completion order.
- **Permissions are asked in context, once, and a no is final.** Health is asked
  the first time a measurable activity is taken on — never at launch, never in
  onboarding. Notifications are asked once, after the first blade, behind a
  primer that shows real examples before iOS is asked anything.
- **Reduce Motion and Dynamic Type are honoured everywhere.** Ambience is off
  under Reduce Motion whatever a Path says.
- Haptics are semantic (`tap`, `detent`, `ritualVerified`, `swordReseated`), not
  decorative.

## 9. Technical architecture

- **SwiftUI + `@Observable`.** No Combine, no external dependencies.
- **Stores are built once in `ContentView.init` and handed down.** `ProgressStore`
  first — everything else reads it. Order matters: `ForgeBackend` is built last
  because it reads the other four and nothing reads it.
- **Persistence is `UserDefaults` in an App Group** (`group.com.dawid.forge`), so
  widgets and the Live Activity read the same day. Every key is versioned
  (`forge.history.v1`). History is JSON-encoded `[DayRecord]`.
- **Every decoder is hand-written and tolerant.** One `throw` fails a whole
  array, and the failure mode is someone opening Forge to find their milestones
  gone. Enums with associated values encode as bare strings; unknown raw values
  land on a safe default rather than throwing. This lesson has been relearned
  three times — see `MilestoneSubject`, `MilestoneUnit`, `VerificationMethod`.
- **Backend is severable, and as of 2026-09-15 it is severed.** Supabase (auth
  + data API, hand-rolled over `URLSession`) is still in the target and still
  compiles, but nothing in the running app constructs any of it and
  `Info.plist` carries no project for it to reach. Nothing on the day's path
  ever held a reference to it, which is what made the removal a deletion rather
  than a refactor. See §2n.
- **Sync** is last-write-wins on `updatedAt`, with unions for monotonic facts
  (acknowledged/celebrated blades) and tombstones via `SyncLedger` for real
  deletions. **Dormant in 1.0** — the engine and its tests are intact and
  nothing calls them.
- **The day starts at 04:00**, not midnight (`dayStartHour`). Everything reads
  the civil day through `ForgeDay`, so a session finished at 01:30 files under
  the right weekday.
- **`SWIFT_VERSION = 5.0`**, no strict concurrency on the app target, no
  `SWIFT_ENABLE_BARE_SLASH_REGEX` — **bare-slash regex literals do not compile.**
  Use a hand-written scan or a runtime `Regex(_:)`.

## 10. Navigation / information architecture

```
TabView (native, Liquid Glass)
├── Forge     the day + sword scene. TODAY / WEEK modes, control bar
│             (Today/Week · challenge), draggable panel. Plan and Copy Day
│             open from the week's own ⋯ menu — see §2j.1
├── Blade     the record: blade + ladder, chapter, heatmap, your milestones,
│             one row into all analytics
├── Becoming  the direction: the Shape (hexagon), one row saying what you chose
│             to build, the six inspectable (the chosen ones marked), one next
│             step, and — only for somebody who has them — the identities
└── Settings  rest days, appearance, the week, notifications, sound and feel,
              planning, About (Support · Privacy Policy · Terms), DEBUG.
              **There is no Account section** — see §2n
```

The panel on the Forge tab has **five states**, decided in one place
(`ForgeTabView.content`): the week, an empty day, the list, the pull prompt, and
the free state. The one that matters and used to be missing: a day that is
**banked but not finished** — the first day anybody has — shows the *list*, with
one line saying today is already theirs and what is left is still worth doing.

App-level overlays (presented above the tab bar, in `ContentView`): first run,
day summary, blade unlock celebration, and the three moments — return, weekly
review, chapter close.

Deep links (`ForgeLink`), notifications and widgets **all land on the Forge tab**
and dismiss any open sheet — they're all about the same day, so arriving
anywhere else would need a tap to undo.

## 11. Deliberately removed or rejected — and why

| Removed / rejected | Why |
|---|---|
| **History paywall** (free saw 5 weeks, Premium 12) | Charging rent on someone's own life. The one place Forge was doing the thing it says it doesn't. |
| **Longest streak** | A personal best whose only job is to be beaten, and which spends most of its life describing someone the user no longer is. Taken off the front card first, then found still living on the analytics sheet, and finally deleted down to the field on `StreakState` — a value that exists is a value the next screen puts back. |
| **Two progressions against one number** | Seven blades and five shipped milestones counted days kept at nearly the same thresholds on the same screen. Merged into `Ladder`; see §2d. |
| **Total activities ever completed** (front card) | Only ever goes up, so it said the same thing as "days kept" in a bigger font. Replaced with completion rate. |
| **Horizontal full-screen Path carousel** | Once the creed, philosophy, three movements and a standard were on the card, the photograph — the reason anybody stopped scrolling — was background behind ~90 words. |
| **A "Forge" card on the shelf** | An exit shown permanently to the majority who have nothing to come back from. The exit moved to the world's own screen; the *statement* that you are in no world moved to the Becoming tab, where it is a fact about the present rather than an offer. `PathCard.forge` is deleted. |
| **Characters as the axis for worlds** | Finite, someone else's, unpersonalisable, aspirationally narrow — and a stack of IP exposure on top. A thirty-four-year-old parent of two is not becoming Batman. Replaced by archetypes; see §2c. |
| **Clock times as a Path's primary structure** | A missable time means someone who slept in has failed the world before breakfast. Routines are *movements*; times are suggestions with no machinery behind them. |
| **Dated tasks / a real calendar** | Forge is a practice, not a productivity app. The moment an activity has a date it needs a notification, a snooze, and a rule for what a missed one means. |
| **Monthly subscription** | Everything is on-device and costs ~nothing to run. Billing every 30 days asks someone to re-decide 12×/year about a practice measured in years. |
| **A challenge that can't be undone** | "I pressed Done before I did it" is not worth a permanent state. Nothing about the record changes either way. |
| **Terminal `completed` challenge state** | Same reason. Every transition is reversible. |
| **A second stored list for "tomorrow"** | Two answers to "what is my day", with no way to tell which the user meant. |
| **Path-owned milestones** | Two numbers about yourself that can disagree — the same bug as a streak that disagrees with its history, in a better coat. |
| **Free `Color` / free palettes for Paths** | A world that can name any colour is a world that can make the app unreadable. `PathAccent` and `PathAmbience` are closed sets so the review happens in one file. |

## 12. ⚠️ Live blockers before TestFlight / App Store

**None. All three are closed** — see §2l for the first two and the list below
for the third.

### What is left, and none of it blocks a submission

- **VoiceOver has never been exercised.** It cannot be driven synthetically.
  Every control carries a label, a value and, where the gesture is not obvious,
  a hint; `AccessibilityTests` holds them and the sword pull has an
  accessibility action so it is completable without a drag. Nobody has heard any
  of it. Half an hour with the screen curtain on before the build is submitted
  is the honest cost.
- **The weekly review screen has not been opened on a device this pass.** See
  §2l.7 for why the Simulator would not present it and why that is a fixture
  problem rather than a defect.
- **Nothing has run on hardware.** Everything verified in §2i–§2l is a
  Simulator. The first-run handover in particular (§2g, the black home screen)
  was intermittent before it was reproducible and is worth watching on a phone.
- One judgement call is open about the App Store plates — the app UI inside the
  device mockups is a build behind. `APP_STORE.md` §5 states it; it is a
  guideline 2.3.3 risk rather than a certainty, and the decision is the author's.
- **The hosted privacy policy is a version behind.** It still describes signing
  in, an account, a server and an entitlement row, none of which exist after
  §2n. It over-discloses rather than under-discloses, so it is not a rejection
  by itself — but it contradicts a nutrition label saying nothing is collected.
  `APP_STORE.md` §2 says what to delete from it. **Do it before submitting.**

### Cleared

- **~~There is no app icon~~ — 2026-09-03.** 1024×1024, sRGB, opaque, in the
  catalogue and confirmed in a Release build's `Info.plist`. See §2l.1.
- **~~Privacy policy and Terms URLs are not set~~ — 2026-09-03.** All three live,
  the `#warning` deleted, and a test standing where it stood. See §2l.1.
- **~~The Lock Screen widget families have never been seen rendered~~ —
  2026-09-03.** Both placed on a real Lock Screen in the Simulator and read at
  their real size. See §2l.
- **~~Dynamic Type and Reduce Motion have never been exercised~~ —
  2026-09-03.** AX5 walked across the Forge, Becoming and Settings tabs (the
  challenge capsule collapses to its glyph, nothing clips, everything scrolls);
  Reduce Motion walked on the home screen.
### Cleared

- **~~Intellectual property~~ — 2026-08-11.** Every character plate and every
  real person's name is gone with the archetypes. Two tests were the tripwire
  and went with the catalogue they guarded.
- **~~The paywall sells software that doesn't exist~~ — 2026-08-12, and again
  by deletion.** There is no paywall in 1.0 (§6).
- **~~The test target does not compile~~ — cleared.** 549 tests, 40 suites, all
  passing (§14).
- **~~The edge function is not deployed~~ — settled by switching the model off.**
  `RemoteForgeAI.isModelEnabled` is `false`, so 1.0 makes no model request at
  all and there is nothing to deploy for. See §7 for the switch and for the
  audit of everything else on the network. The Supabase project stays configured
  in `Info.plist` because **sync still uses it** — that is a separate, signed-in,
  user-initiated feature.
- **~~The black home screen after the first run~~ — diagnosed and fixed
  2026-08-31.** It was a full-screen cover being removed in the same runloop
  turn as the `DayRecord` write that starts the Live Activity. See §2g. **Still
  worth watching on a device** — it was intermittent before it was reproducible.

## 13. What is not built, and what it would cost

The six-phase repositioning designed on 2026-08-11 is finished, and phase 3
(archetypes) was subsequently undone by deleting Paths entirely. What is left
open:

- **A dated-override layer.** "Skip just this Tuesday", "move tomorrow's
  workout" and any one-off appointment still cannot be said — activities are
  standing arrangements (§5.12). The honest fix is a dated layer *on top of* the
  recurring model, consulted by `ForgeViewModel.todayRitualIDs`, which is the
  most load-bearing property in the app. Not reinterpreting what `setWeekday`
  and `moveActivity` mean.
- **Per-weekday times.** `startMinute` is one value per activity, so "Mon 18:00,
  Wed 19:00" is not expressible either. Same fix, same place.
- **Naming an identity outside the first run.** It was first-run-only, and the
  first run no longer asks (§2g) — so for a new install the identity spine is
  reachable only through history and sync. Everything that *reads* an identity
  still works. If 1.1 wants them back as a feature rather than as a substrate,
  the editor belongs on the Becoming tab beside `FocusEditor`, which is exactly
  the shape it would take.
- **Premium.** Two product ids and three entitlement states are wired to
  nothing (§6). 1.1's line is *depth of becoming* — the model-written reading
  and continuity — and none of it is written.
- **Backup, sync and an account.** Removed from 1.0 outright (§2n), not merely
  switched off. The engine, the merge and their tests are intact; bringing it
  back is `Info.plist`, a rebuilt `AccountSection`, and the five documents in
  `APP_STORE.md` §1 that describe what an account collects. It must come back
  with a Delete Account flow, which is why it was cheaper to remove than to
  keep.

## 14. Build and test

**Verified 2026-09-03 on Xcode 26.6.**

```bash
cd /Users/dawidbubnow/Desktop/Forge/Forge
```

Build the app — **succeeds**:

```bash
xcodebuild -project Forge.xcodeproj -scheme Forge -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Run the tests — **549 tests in 40 suites, all passing**:

```bash
xcodebuild -project Forge.xcodeproj -scheme Forge \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

⚠️ **Grep for the swift-testing line, not the XCTest one.** The suites are
`@Suite`/`@Test`, so the XCTest summary reads "Executed 0 tests" and is
meaningless here. The line that matters is `Test run with N tests in M suites`.

Any new test file must follow two rules that the Xcode 26 toolchain enforces
and earlier ones did not:

1. **`@MainActor` on any `@Suite` touching a `@MainActor` type** (`IdentityStore`,
   `ForgeStore`, and anything that reaches `ForgeHaptics`). The app target is
   unaffected (`SWIFT_VERSION = 5.0`, no strict concurrency), so this only ever
   bites in tests.
2. **`Comment(rawValue:)` for a runtime-`String` expectation message.** A plain
   `String` no longer converts to `Comment`.

A third trap, which is not the toolchain's fault: **`ForgeViewModel` reads and
writes the real App Group suite, shared by every test in the process**, and
`hasCompletedFirstRun` lives there. Any suite touching the first run must call
`vm.resetFirstRun()` in its helper or it inherits whether an earlier test
finished onboarding. `FirstRunTests.makeViewModel` and `DayCountTests` show the
pattern.

**Known-benign:** `AnalyticsTests` → "A period before the history began is empty
rather than zero" can fail **only when run on a Monday**, for a calendar reason
rather than a code one. The *test* is wrong, not `ProgressStore` — do not "fix"
it by touching the store.

**Simulator note:** destinations are iOS 26.5 devices (iPhone 17 / 17 Pro /
17 Pro Max / 17e). `xcrun simctl list` also shows older iPhone 16 devices that
`xcodebuild` will reject — read destinations from
`xcodebuild -showdestinations`, not from `simctl`.

### Driving the running app

- A synthetic `tap` never flips a SwiftUI `Toggle` — use a short `touch_path`
  across the switch.
- **The sword pull *can* be performed** — this note used to say it could not.
  A multi-point `touch_path` with `dt_ms` on every point drives `SwordEngine`
  properly: twenty points, 60ms apart, from y≈400 up to y≈135 breaks the blade
  free every time. That is the only way past the first run without a fixture.
- A multi-point `touch_path` is **not** a reliable scroll; it arrives as a tap.
  Use the simulator control's own `swipe` with a `duration` — that does produce
  a real pan, and it is what verified the day-list scrolling fix.
- **Seeding a fixture that works** (used on 2026-08-31 to verify the freed panel
  with twelve activities): `uninstall`, `install`, then before the first launch
  write `forge.hasCompletedFirstRun.v1` (bool), `forge.activeRituals.v1` (array
  of ids) and `forge.history.v1` (`-data <hex>`; JSON `[DayRecord]`, `Date`s as
  seconds since the 2001 epoch, `extractedAt` set to reach the free state) with
  `xcrun simctl spawn <udid> defaults write group.com.dawid.forge …`. Writing
  defaults *after* the app has run is unreliable — it flushes its own cache over
  them.
- **`simctl install` wipes the app's own data container on this toolchain**,
  whatever the note above used to say, so every reinstall is a fresh first run.
  Do all the code changes first and set the fixture up once, after the last
  install.
- **`defaults write group.com.dawid.forge` does not work at all** under
  `simctl spawn` here: an unsigned build (`CODE_SIGNING_ALLOWED=NO`) carries no
  App Group entitlement, so `ForgeShared.defaults` falls back to `.standard` and
  the group domain never exists. The UI is the only way in.
- **Never run `xcodebuild ... CODE_SIGNING_ALLOWED=NO` into the *default*
  derived data.** It leaves an unsigned `Forge.app` there, and every later
  `xcodebuild test` then fails with "Simulator device failed to launch" /
  "Launchd job spawn failed" — which looks like a wedged simulator and is not.
  Build test-adjacent things normally, use `-derivedDataPath` for the unsigned
  ones, and `rm -rf <DerivedData>/Build/Products` to recover.
- Settings → DEBUG has "Seed 12 Weeks of History", "Clear History" and "Run
  First Launch Again"; reach for those before hand-writing defaults.

## 15. Toolchain

```
Xcode 26.6 (Build 17F113)
Active developer dir: /Applications/Xcode-26.6.app/Contents/Developer
SDK: iOS 26.5 / iOS Simulator 26.5
Deployment target: iOS 26.0
Swift language mode: 5.0 (no strict concurrency on the app target)
Bundle: com.dawid.forge     App Group: group.com.dawid.forge
Marketing version: 1.0
```

> **Note:** the memory file `toolchain-cannot-build-forge.md` describes an
> Xcode 16.4 workaround (shims, SwiftPM test package, deployment-target
> rewriting). **That is obsolete** — Xcode 26.6 is installed and the project
> builds directly. That memo remains useful only for its simulator-driving and
> defaults-seeding notes.

**Project file:** `objectVersion = 56`, no synchronized groups — **a new file
needs four `project.pbxproj` entries** (PBXBuildFile, PBXFileReference, group
children, target Sources phase). Copy a neighbouring file's four lines and swap
in two fresh 24-hex-char UUIDs; validate with `plutil -lint`. A file that isn't
in the target fails to resolve at compile time, so the build is the proof.
One trap when scripting it: check for `/* Name.swift */` rather than for the
bare filename, or `PlanTests.swift` reads as already present because
`NotificationPlanTests.swift` contains it.

The `ForgeWidgets` target compiles only `ForgeWidgets/*.swift` plus
`Shared/{ForgeShared, ForgeSnapshot, ForgePalette, ForgeActivityAttributes,
ForgeLink}` and `Models/ForgeDay.swift` — it does **not** see `Ritual.swift`,
`IconShape.swift` or `ForgeTheme.swift`. `ForgePalette.swift` was
`BladeMark.swift` until the widget artwork was withdrawn (§2l.2); it holds
`ForgeAccentPalette` and `ForgeHeatLevel`.

## 16. Working on this codebase

- **Read the doc comments before changing anything.** They are the design
  document: they explain what was rejected and why, not what the line does.
  Several record bugs that were fixed at real cost.
- **Match the comment density and register.** This codebase explains decisions.
- **Never introduce stored derived state.** If you're adding a cached count,
  you're introducing the bug class §5.2 exists to prevent.
- **Never break a migration.** An existing user must open the app and see exactly
  what they saw yesterday.
- **Versioned keys only**, and hand-written tolerant decoders only.
- **If you change what "finished" means**, keep the `totalActive > 0` guard —
  an empty day used to arrive already earned, and the blade came loose at
  midnight having done nothing. And keep `totalDone` a count of **today's
  list**: it was a count of everything completed today, which made taking a
  finished activity off the day a way to earn it (§2g).
- **A `Button` is the wrong control for a row that also swipes.** It fires on
  touch-up anywhere inside its own bounds however far the finger travelled. Use
  a `TapGesture`, which has the movement tolerance. See `RitualRowView`.
- **`highPriorityGesture` inside a `ScrollView` cancels the scroll.** If a
  gesture has to coexist with scrolling, it is `simultaneousGesture` and the
  arbitration is yours to write.

## 17. Release 1.1

Built in eight sessions, S0 to S7, against
[docs/DIRECTION_1_1.md](DIRECTION_1_1.md). Each session adds a dated
subsection here describing what changed in behaviour, what was verified, and
what was not.

### 17.0 Direction (2026-09-29)

Session S0. No product code changed.

- Merged `feat/first-week` (§2s) and `docs/launch-kit` (`docs/launch/*`) into
  main. `FirstWeekTests` "Days are said in words" was corrected on the way: it
  rejected "twenty-one days kept" as if it were "one days".
- Added `docs/DIRECTION_1_1.md` and §2t, which lists what it supersedes.
- Rewrote the repository's `CLAUDE.md` as the single copy of the working rules
  (the copy in the parent folder, outside git, now only points here). It
  corrects the old claim of synchronized groups: the project is
  `objectVersion = 56` and a new file needs four `project.pbxproj` entries (§15).
- **Stale on purpose, to fix when it is rebuilt:** §3 and §4 still mention
  HealthKit (the "HealthKit auto-settle" step of the core loop). HealthKit was
  removed before 1.0 and returns in session S5 (DIRECTION §8), read-only.
- **For the owner before progression is built — DIRECTION §6 does not fit the
  ladder as it is.** `Ladder` already has thirteen rungs up to 1000 days, among
  them `oneeighty` "Patina" (180) and `year` "Honed" (365). "Honed (90 days
  kept) and Enduring (180)" would rename or collide with existing rungs, which
  the same section forbids ("existing rung ids and requirements never change").
  Decide the names and thresholds before the session that builds §6.
- **Known test failures on main before and after this session (environmental):**
  the `ForgeStoreKitTests` suite gets no products from `SKTestSession` on this
  Mac (`store.status == .unavailable`), and the `AIPrepTests` that need a Pro
  entitlement fail with it. `Forge.storekit` itself is valid. To investigate
  before session S2 touches the paywall.

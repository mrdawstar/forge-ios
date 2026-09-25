# Forge — App Store submission

> Everything App Store Connect asks for, written down so it is decided once
> rather than improvised in the form. Last updated **2026-09-25** — anonymous
> usage (TelemetryDeck) added; §1 changed. Before that, **2026-09-15**: the
> submission after the Guideline 2.1 reply, where the account was removed
> outright (§1 and §6).
>
> Items marked **BLOCKER** cannot be filled in from this repository and must be
> done before a build is submitted for review. Everything else is ready to paste.

---

## 1. Privacy nutrition labels

The honest version, field by field. The rule applied throughout: a label is
about what the *app* does, not about what a reasonable app might do — so
anything Forge has no code path for is answered "not collected" and the answer
is checkable against a named file.

### Data used to track you
**None.** There is no advertising identifier, no attribution framework, and
nothing is combined with data from another company. The one third-party SDK is
TelemetryDeck (anonymous usage, below), which is not a tracking domain and
receives no identifier it could join to anything. `grep` for
`AppTrackingTransparency`, `ASIdentifierManager`, `FirebaseAnalytics`,
`AppsFlyer`, `Amplitude`, `Mixpanel` returns nothing.

### Data linked to you

**None.** — *changed 2026-09-15, and this is the biggest change on the page.*

**Forge 1.0 has no account.** There is no sign-in control anywhere in the app,
`Forge/Info.plist` carries no Supabase project, nothing in the running app
constructs an auth or a sync service, and `AuthenticationServices` is not even
linked into the Release binary. Every row that used to be here — email address,
user id, other user content, purchases, diagnostics — existed only for a
signed-in account, and there is no longer any way to become one.

The rows are recorded below rather than deleted, because each one names a thing
that comes straight back the day sync does:

| Was collected | Only when | Would come back with |
|---|---|---|
| Email address | signed in | `AuthService` / Supabase GoTrue |
| User ID | signed in | Supabase `auth.users` uuid |
| Other user content — activity names, identity statements, chapters, reviews | signed in **and** entitled | `SyncService` |
| Purchases | signed in | `premium_status` row |
| Other Diagnostics — device model, iOS version, app version | signed in | `UserService.registerDevice` |

`PrivacyInfo.xcprivacy` declares **nothing linked to the user** — its only two
rows are the anonymous-usage ones below — and
`BackendRegressionTests.theAppShipsWithNoAccount` fails the test run if the
project ever comes back into `Info.plist`. The nutrition labels in App Store
Connect must say **Data Not Linked to You: Product Interaction, Other
Diagnostic Data** and nothing else, and match it — a manifest disagreeing with
the labels is the one mismatch App Store Connect checks automatically.

> ⚠️ **The day sync is switched back on, this whole section comes back with it**,
> along with the manifest, the labels, the App Review notes and a privacy policy
> that describes an account again. That is five places, which is why the test
> exists.

### Data not linked to you

**Two rows** — *added with anonymous usage (`FORGE_CONTEXT.md` §2p).*

| Data type | Purpose | Linked | Tracking | What it is |
|---|---|---|---|---|
| **Usage Data → Product Interaction** | Analytics | No | No | The events in `ForgeTelemetry.Event`: first-run beat viewed, how many of the six were chosen, an activity completed (and whether by tick or by honor), a day earned, a pull let go, a challenge accepted/completed, an activity added (and from which screen), a notification opened (and which kind), a weekly review done, the re-entry screen shown / a day earned after it, a chapter closed. Each carries `days_since_install`, derived from the oldest day in the record. |
| **Diagnostics → Other Diagnostic Data** | Analytics | No | No | What the TelemetryDeck SDK attaches to every signal: device model, OS and app version, screen size, language, locale, region and time zone, appearance and accessibility settings, and its own anonymous session counts (sessions, days used, first-session date). Checked against the SDK source (2.14.2, `Signal.swift`). |

In App Store Connect: *Usage Data → Product Interaction* and *Diagnostics →
Other Diagnostic Data*, each **Analytics** only, **not linked to the user**,
**not used for tracking**. `PrivacyInfo.xcprivacy` declares the same two rows.

What makes "not linked" true: there is no account, no sign-in and no user id;
TelemetryDeck receives only an anonymised identifier — hashed on the
phone, and hashed again with a salt on TelemetryDeck's side — that cannot be
reversed to a person or a device. What makes it *anonymous usage* rather
than user content: no event carries an activity name, an identity statement, a
chapter name, a review's words, a time somebody chose, or anything from
HealthKit — `ForgeTelemetry.Event` has no case that could hold one, and
`TelemetryTests.payloadsAreClosed` fails if a parameter key outside the closed
set ever appears.

**Settings → Privacy → "Share anonymous usage"** turns all of it off. On by
default. When off, and always under test, `ForgeTelemetry.send` returns before
anything is built and the SDK's own `analyticsDisabled` is set; its automatic
session signal is disabled in any case.

The paywall events (`paywall_view`, `paywall_dismissed`, `trial_started`,
`purchase_completed`, `restore_tapped`) are defined but have no call site in
this build; when they do, they add nothing new to the labels — a purchase
event's `plan` is "annual" or "lifetime", never a price, receipt or Apple ID,
and Purchases stays **not collected**.

The other candidate was the AI brief, and **1.0 does not send it.**
`ClaudeForgeAI.isModelEnabled` is `false`, which forces the endpoint to nil, so
there is no object in the process capable of forming that request — not for a
plan, not for a challenge, and not for the weekly reading. There is now a second
lock on the same door: the endpoint is built from `SupabaseConfig`, and there is
no project to build one from. `PlanTests` fails the build's test run if the
constant changes.

Plan is arithmetic on the device (`DayPlanner`), the challenge generator picks
from thirty-six shipped challenges, and the weekly review's observation is
written by rules over the user's own record. None of the three touches the
network.

### Data not collected

**Everything else.** Health & Fitness, Location, Contacts, Photos, Browsing
History, Search History, Crash Data, Performance Data, Sensitive Info, Financial
Info, Physical Address, Phone Number, Name, Email Address, User ID, Device ID,
Purchases, User Content, Customer Support, Advertising Data, and every Usage
Data and Diagnostics row other than the two above.

**Health data specifically.** Forge reads steps, distance and workouts from
HealthKit to tick off activities it can measure. It is **read-only**
(`requestAuthorization(toShare: [], read:)` in `HealthBridge`), the readings are
never written to disk, never synced, and never included in an `AIBrief` — there
is no field on that struct that could hold one. HealthKit data therefore is not
"collected" in the App Store sense and must not be declared as such.

> ⚠️ **Read-only does not exempt the app from the *write* purpose string.** The
> first upload was rejected with `ITMS-90683: Missing purpose string in
> Info.plist — NSHealthUpdateUsageDescription`. Upload validation checks the
> **entitlement**, not the usage, and `com.apple.developer.healthkit` grants
> read and write together — so both `NSHealthShareUsageDescription` and
> `NSHealthUpdateUsageDescription` must be in `Forge/Info.plist`. Both are, as
> of 2026-09-04. The update string says the app does not write, which is true
> and which iOS will never show. Do not delete it to tidy up. See
> `FORGE_CONTEXT.md` §2m.

### What the app does over the network, in full

Re-audited 2026-09-25, when anonymous usage was added (§2p). Every path, and
what starts it:

| Path | Starts when | Sends |
|---|---|---|
| StoreKit product load | Launch, and on any transaction | Apple's own; no user data |
| TelemetryDeck (`nom.telemetrydeck.com`) | One of the events in `ForgeTelemetry.Event`, only while **Share anonymous usage** is on | Event name, its closed parameters, `days_since_install`, the SDK's device, locale and session fields, and an anonymised, double-hashed install id |

**That is the whole table.** There is nothing else. Sign-in, token refresh,
sync, device registration and the entitlement row all required a Supabase
project and a session, and there is neither: `SupabaseConfig.fromBundle()`
answers nil, so no `HTTPClient` can be constructed, so no request can be formed.
The StoreKit call is Apple's own, carries no Forge data, sells nothing, and
fails silently to `.unavailable` with no UI attached.

**One host, held by tests.** `ForgeNetwork.allowedHosts` is exactly
`nom.telemetrydeck.com`; `URLSessionTransport` refuses any other host before a
socket is opened, and `NoNetworkTests` / `BackendRegressionTests` fail the run if
the list grows or if a request to any other host gets through. TelemetryDeck's
SDK arrives as a Swift package and is the one third-party code in the app; as a
static library it will not appear in `otool -L` — re-check that on the next
Release build and correct this line if it does.

**Not present anywhere in the app:** attribution, advertising or
crash-reporting SDKs; remote push (the Live Activity is
`Activity.request(pushType: nil)`); remotely loaded images or assets; any
third-party host other than TelemetryDeck's. `grep` for
`AppTrackingTransparency`, `ASIdentifierManager`, `FirebaseAnalytics`,
`AppsFlyer`, `Amplitude`, `Mixpanel`, `AsyncImage` returns nothing.

---

## 1a. App icon — **cleared 2026-09-03**

`Forge/Assets.xcassets/AppIcon.appiconset` holds `AppIcon.png`: **1024×1024,
sRGB, opaque, no alpha, square** — resized from the supplied `screenshots/appicon.PNG`
(1254×1254) and named in `Contents.json` as the one universal iOS slot.

Verified against a Release build (`-configuration Release`, iOS Simulator SDK):

```
CFBundleIconName => AppIcon
CFBundleIcons    => { CFBundlePrimaryIcon => { CFBundleIconFiles => [AppIcon60x60] } }
AppIcon60x60@2x.png present in the bundle
```

and seen rendered on the Simulator's Home Screen, where the app used to draw
the blank placeholder tile. `ITMS-90713` cannot fire on this build.

If it ever has to be replaced, the requirements Apple enforces on that one file
are: exactly **1024×1024**, **opaque** (an alpha channel is rejected), sRGB,
square with **no rounded corners** — iOS applies the mask.

---

## 2. URLs — **cleared 2026-09-03**

All three are live and set in `Shared/ForgeLink.swift`:

| | |
|---|---|
| Privacy Policy | `https://forgebetter.app/privacy` |
| Terms of Use | `https://forgebetter.app/terms` |
| Support | `https://forgebetter.app/support` |

The `#warning` that fired on every build is **deleted**, and the thing that
replaced it is a test: `BackendRegressionTests.productionLinksAreConfigured`
fails the run if any of the three is unset or points somewhere else. A warning
fires on every build and is therefore read on none of them.

Settings → About now carries three rows in this order: **Support**, Privacy
Policy, Terms of Use. Support leads because the other two are documents somebody
reads once at most, and this is the row a person opens when the app has done
something wrong. Each row is still absent rather than broken if its URL were
ever unset. `Forge/Forge.storekit` carries the same two strings in `eula` and
`policyURL`.

⚠️ **The hosted policy is a version behind and must be updated before this
build is submitted.** It still describes signing in with Apple or Google, an
account that stores an email and a user id, device information, and an
entitlement row — and 1.0 has none of those. An over-disclosing policy is not a
rejection by itself, but it contradicts a nutrition label saying nothing is
collected, and that contradiction is checkable in thirty seconds.

What it must say after the edit, at minimum: that everything is stored locally
on the device; that **there is no account and no way to make one**; that the app
makes **no network requests** other than Apple's own StoreKit; that deleting the
app deletes the data; and that HealthKit data is read-only and never
transmitted. The sections about signing in, about what the server stores, and
about the account-deletion route should be **deleted**, not softened — there is
no server-side data and no account to delete.

It must **not** describe AI processing, because 1.0 does none. Add that section
on the day the model is switched on, and not before — a policy that describes
transmission the app cannot perform is as wrong as one that omits transmission
it can.

---

## 3. Age rating

**4+.** No objectionable content of any kind. Answer "None" to every
questionnaire item.

Two questions need care:

- **"Does your app contain user-generated content?"** — Yes, technically: users
  write activity names, chapter names and review answers. They **never leave the
  device**: there is no account, no server, no feed, no sharing surface other
  than an image the user explicitly exports, no comments and no profiles.
  Answer yes and say so in the review notes; this does not raise the rating.
- **"Unrestricted web access?"** — No.

---

## 4. Description

**Subtitle (30 char max):**

> A day you earn, not one you tick

**Promotional text (170):**

> The blade comes loose when the day is done — and you still have to pull it
> free. Forge keeps the practice, not the score.

**Description:**

```
Forge is for keeping a daily practice.

You keep a short list of the things a day asks of you. When you have done all of
them, a sword in a stone comes loose — and you still have to drag it out. That
pull banks the day.

WHAT IT IS NOT

There is no score. Nothing congratulates you, nothing guilts you, and no number
in Forge goes down when you have a bad week. Days you have already kept are
never taken away or hidden.

SIX PARTS OF A PERSON

Physical, Intellect, Discipline, Mental, Relationship, Ambition. Every activity
belongs to one of them, so Forge can show you the shape of the last four weeks
rather than only the size of it — which parts of you are getting stronger, and
which are getting nothing.

Choose one to three to build. Forge points what it suggests at them, and then
tells you honestly how it is going.

PLAN

One tap, and Forge reads your own week back to you: two things booked at the
same time, four activities with no hour on them, the part of you that is getting
the least, the thing you ask for every day and keep twice a week. Every
suggestion states the arithmetic behind it, and nothing changes until you say
so. It all happens on your phone.

ONE SUNDAY EVENING A WEEK

Ninety seconds. Your week, one true observation drawn from your own record, and
two questions in your own words. Skippable forever, and skipping costs nothing.

EVERYTHING, FREE

The whole daily loop. Any number of activities. Your complete history, the
shape, the heatmap, the trends, the blades, the milestones, rest days, widgets,
a challenge every day, chapters, the weekly review and Plan.

There is no subscription and nothing is locked.
```

**Keywords (100 char max):**

```
habit,routine,discipline,daily,practice,streak,ritual,morning,identity,journal
```

## 5. Screenshots — **supplied, with one caveat to decide**

Five finished marketing images were supplied in `screenshots/` (`1s`…`5s`):
designed plates, each a headline over a device mockup of a Forge screen, on the
product's own black-and-blue. They are the ones to use.

**They arrived at 853×1844**, which App Store Connect does not accept — the 6.9"
slot takes 1290×2796 or 1320×2868. Resized copies at exactly **1290×2796**, sRGB
and opaque, are in **`screenshots/appstore-6.9/`** and are what to upload. The
scale is 1.51×, so type in them is very slightly softer than a native capture;
nothing in them is cropped and the aspect is corrected by seven pixels of the
plate's own black rather than by stretching.

⚠️ **The app UI inside the mockups is from an earlier build.** Plate 1 shows the
control bar as `[TODAY|WEEK] [+ PLAN ✕]` — the crossed-swords glyph and the
waiting dot, both deleted in §2j.2, and Plan itself moved to the week in §2j.1.
Plate 3 shows the Becoming tab with "You're building…" *above* The Six, which is
the pre-2026-09-03 order, enumerating four dimensions with four glyphs. Both
also carry the old road-sign tab icon.

That is a **guideline 2.3.3 risk** ("screenshots should accurately reflect the
app"), not a certainty — reviewers routinely pass marketing plates whose device
art is a version behind, and nothing in these shows a feature that does not
exist. It is a judgement call and the decision is the author's: ship as-is and
accept a small rejection risk, or re-render the two device mockups against the
current build. Recorded here so it is a decision rather than an oversight.

6.5" is optional when a 6.9" set is supplied; App Store Connect scales down.

---

## 6. App Review notes

Rewritten 2026-09-15 against the current build. The previous version described
an optional account, which no longer exists.

```
No account is required, and none can be created. Forge has no sign-in, no
registration and no password anywhere in the app. Launch it and the full app is
immediately available — there are no demo credentials to supply because there is
nothing to sign in to.

Forge works entirely offline. Besides Apple's own StoreKit product lookup at
launch, the only network traffic is anonymous usage statistics sent to
TelemetryDeck (which screens and actions are used — never anything the user
writes), which can be turned off in Settings → Privacy → Share anonymous usage.
No screen depends on the network. Everything a user creates is stored locally
on the device.

To review it in about a minute:
1. Launch. A short first run asks which parts of yourself you want to build and
   which activities to start with, then shows how the sword is pulled.
2. On the Forge tab, tap an activity to complete it.
3. When the day's list is done the blade comes loose — press the grip and drag
   upward to earn the day.
4. The Blade tab shows the record: blade, chapter, heatmap and milestones.
5. The Becoming tab shows the six areas every activity is filed under.
6. The Settings tab has appearance and accent colour, and the Privacy Policy,
   Terms and Support links.

HealthKit is read-only and optional. It is used solely to auto-complete
activities the phone can already measure (steps, distance, workouts), and is
requested in context the first time such an activity is taken on — never at
launch. No health data is stored, synced or transmitted, and the app never
writes to Health. Declining it leaves every feature working; activities are
then completed by tapping.

This build contains no AI processing of any kind. The app holds no model key and
makes no model request. The Plan feature (opened from the week, under the More
button) works out every suggestion on the device from the user's own activities
and history.

User-generated content — activity names, chapter names, weekly review answers —
never leaves the device. There is no social surface, no feed and no sharing
between users.

Nothing is sold. There is no paywall, no subscription and no locked content.
```

## 7. Subscription metadata — **not needed for 1.0**

**Nothing is sold.** There is no paywall, no invitation and no locked control
anywhere in the app, so no in-app purchase needs to be submitted with this
build and the review questionnaire's purchase questions are all "no".

The two products still exist in `Forge/Forge.storekit` and in App Store Connect,
and `ForgeStore` still reads the entitlement — they are dormant, not deleted,
because 1.1 adds Premium back around the model. When that happens they need:

| | Annual | Lifetime |
|---|---|---|
| Product ID | `com.dawid.forge.premium.annual` | `com.dawid.forge.premium.lifetime` |
| Type | Auto-renewing subscription | Non-consumable |
| Price | 29.99/yr | 74.99 |
| Intro offer | 1 week free | — |
| Family Sharing | On | On |

**Required on the subscription's own page, on the day it is sold:** a link to
the terms, a link to the privacy policy, and the subscription length and price
stated in the description. All three are review-checked for auto-renewing
subscriptions.

## 8. Pre-submission checklist

- [x] **App icon installed** (2026-09-03) — 1024×1024, sRGB, opaque;
      `CFBundleIconName` confirmed in the built Release `Info.plist` and the tile
      seen on the Simulator's Home Screen (§1a)
- [x] Privacy policy URL live, and `ForgeLinks.privacy` set (§2)
- [x] Privacy policy says nothing about AI processing (1.0 does none — §1)
- [x] Terms URL live, and `ForgeLinks.terms` set; **Support** set too, and the
      row leads the About section
- [x] `#warning` in `Shared/ForgeLink.swift` deleted — replaced by a test that
      fails if any of the three URLs stops being the live one
- [x] Screenshots supplied and resized to 1290×2796 in `screenshots/appstore-6.9/`
      (§5) — **one judgement call left open there about the UI version inside
      the mockups**
- [x] Dynamic Type at AX5 and Reduce Motion walked in the Simulator (2026-09-03)
- [ ] **VoiceOver** — still not exercised. It cannot be driven synthetically;
      the labels, values and hints are in the source and covered by
      `AccessibilityTests`, but nobody has heard them
- [x] **Device pass on the first run specifically** — walked twice more on
      2026-09-03 from a wiped install, including the pull and a cold relaunch.
      Still never on hardware
- [x] **Lock Screen widgets seen rendered** (2026-09-03) — both accessory
      families placed on a real Lock Screen in the Simulator and photographed:
      the circle shows the remaining count in its gauge, the rectangle shows
      "3 left / Breathe" over the rule. Neither carries the withdrawn sword mark
- [x] **Weekly review** — logic covered by `ReviewTests`; **the screen itself
      could not be reached in the Simulator this pass**, because re-entry
      outranks it and a fabricated Sunday has no activities pinned to it. Needs
      one look on a real review evening
- [x] **Sword pull walked end to end** (2026-09-03) — press the grip, drag, break
      free, earn the day, blade celebration, free state. `SwordEngine.travel` was
      250 and made it unreachable from the grip; it is 150
- [x] **First run walked end to end from a wiped install** (2026-09-03), including
      a cold relaunch afterwards — which is how the onboarding-replay trap was
      found and fixed
- [x] Privacy nutrition labels decided (§1) — **nothing collected**, rewritten
      2026-09-15 when the account was removed
- [x] Age rating decided (§3)
- [x] Description, subtitle, keywords written (§4)
- [x] Review notes written (§6) — rewritten 2026-09-15 against the accountless
      build
- [x] Nothing is sold, so no IAP submission is required (§7)
- [x] Network audit re-done and written down (§1, 2026-09-15) — **one** call in
      the whole binary, Apple's own StoreKit lookup. No AI request, no
      analytics, no third-party host, no Supabase project to reach
- [x] Release configuration builds clean, and no debug UI reaches it — `strings`
      on the Release binary finds none of the DEBUG settings rows
- [x] iPhone only (`TARGETED_DEVICE_FAMILY = 1`). It declared iPad support the
      app has never been laid out for
- [x] **The account is gone** (2026-09-15) — no sign-in, no registration, no
      logout, no Delete Account, because there is nothing to delete. The Sign in
      with Apple entitlement is removed and `AuthenticationServices` is no
      longer linked into the Release binary (`otool -L`). This closes the demo-
      credentials question a Guideline 2.1 reply asks, by removing the thing it
      asks about
- [ ] **Hosted privacy policy updated** to match the accountless build — see §2.
      It still describes sign-in, a server and an entitlement row. **Do this
      before submitting**
- [ ] **App Privacy in App Store Connect set to "Data Not Linked to You":
      Usage Data → Product Interaction and Diagnostics → Other Diagnostic
      Data**, Analytics only, not used for tracking — matching
      `PrivacyInfo.xcprivacy` (§1, changed 2026-09-25 for anonymous usage)
- [ ] **Hosted privacy policy gains the anonymous-usage paragraph** (the
      TelemetryDeck PR carries it ready to paste)
- [ ] **App Review Information: leave the demo account fields empty** and tick
      "Sign-in not required" 
- [x] **Both HealthKit purpose strings in `Forge/Info.plist`** (2026-09-04) —
      `NSHealthShareUsageDescription` *and* `NSHealthUpdateUsageDescription`.
      Read-only usage does not exempt the second one; the entitlement is what
      the validator checks. This is what `ITMS-90683` was
- [x] **Archive builds and passes `-validate-for-store`** (2026-09-04) — but the
      only certificate on the build machine is an Apple *Development* one, so
      the archive carries `get-task-allow` and must be distributed through
      Xcode's Organizer, which re-signs it for the store
- [x] `PrivacyInfo.xcprivacy` present and matching §1 — **and §1 was corrected
      to match it**: Diagnostics is collected for a signed-in account and used
      to say "not collected"
- [x] Large widget added, and the sword-in-stone widget artwork withdrawn from
      every family and from the Live Activity (2026-09-03)

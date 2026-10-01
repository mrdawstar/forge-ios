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

The paywall events (`paywall_view`, `exit_offer_view`, `exit_offer_accepted`,
`trial_started`, `purchase_completed`, `restore_tapped`, `founder_detected`)
are **wired from 1.1** (Forge Pro, the hard paywall — `FORGE_CONTEXT.md` §6).
They carry only a closed `door` or `plan` value — `door` is "onboarding",
"locked", "settings" or "ai"; `plan` is "annual", "annual_offer", "monthly" or
"lifetime" — never a price, receipt, transaction id or Apple ID, and are
anonymous like every other event. `paywall_dismissed` was retired with the
three doors.

> ⚠️ **Decide before submitting 1.1:** 1.0's position was that these add
> nothing to the labels and **Purchases stays not collected**. With the events
> now actually sent, the conservative reading of Apple's definition ("an
> individual's purchases or purchase tendencies") is to declare **Purchases →
> Purchase History, Analytics, not linked, not tracking**, and add the matching
> row to `PrivacyInfo.xcprivacy`. Whichever is chosen, the labels and the
> manifest must say the same thing.

### Forge's AI — prepared, **not active in this build** (`FORGE_CONTEXT.md` §2r)

Forge Pro's AI features (the Weekly Reading and Plan in your own words) are
**built on the iOS side and switched off**. What that means for the labels:

**This build — submit with the labels above, unchanged.** Remote AI is disabled:
`RemoteForgeAI.isModelEnabled` is `false`, which forces the endpoint to nil, and
there is no Supabase project in `Info.plist` to build one from — two locks, each
held by a test (`NoNetworkTests`, `AIPrepTests`, `BackendRegressionTests`). No
AI brief, no request text and no purchase proof leaves the phone; Plan is
arithmetic on the device (`DayPlanner`, `LocalForgeAI`), the challenge comes
from the shipped catalogue, and the weekly review's observation is written by
rules over the user's own record. The consent screen exists in the binary but
cannot be reached, because it is only raised when a request would actually be
made.

**The day AI is activated — replace the labels with these.** Everything below
is collected only for Forge Pro users, only after they press **Allow** on the
in-app disclosure (explicit consent, revocable in Settings → Planning), only
when they press a button that asks for it, and is processed by **Forge's backend
(Supabase edge function `forge-ai`) and OpenAI** behind it. None of it is used
for advertising or tracking, sold, or combined with other companies' data.

| Data type | Purpose | Linked | Tracking | What it is |
|---|---|---|---|---|
| **User Content → Other User Content** | App Functionality | No | No | The `AIBrief`: activity names, times, lengths and days; what the user said they are becoming (identity statements) and the chapter's intention; counts of days kept; for a Weekly Reading, one week's counts per weekday, activity and identity; for Plan, the request the user typed. Never weekly-review answers, dates, health data, names, email, location or contacts. |
| **Purchases → Purchase History** | App Functionality | No¹ | No | The Apple-signed StoreKit 2 transaction (`X-Forge-Transaction`), verified offline by the backend to confirm Forge Pro. Used for entitlement and the per-purchase spend cap (`ai_usage_by_transaction`, keyed on `originalTransactionId`). |
| **Identifiers → User ID** | App Functionality | No¹ | No | The anonymous Supabase user id minted lazily for the first AI request — no email, password, name or provider. Used only to authenticate and rate-limit calls. |

¹ *Decide before activating.* Neither is joined to a name, email or account,
which supports "not linked"; the conservative reading of Apple's definition
treats any persistent identifier as linked. Pick one, and make
`PrivacyInfo.xcprivacy` say the same (add `NSPrivacyCollectedDataTypeOtherUserContent`,
`…PurchaseHistory` and `…UserID` with purpose `AppFunctionality`,
`NSPrivacyCollectedDataTypeTracking = false`).

What stays true after activation: the app holds **no OpenAI key** (the only one
is the server secret `OPENAI_API_KEY`), the app never contacts OpenAI directly,
responses are requested with `store: false`, OpenAI does not train on API data
by default, and every model-written sentence is labelled as such on screen.
Anthropic / Claude is not used anywhere.

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

It must **not** describe AI processing while remote AI is switched off (§1,
"Forge's AI — prepared, not active"). Publish the paragraph below **on the day
the model is switched on**, and not before — a policy that describes
transmission the app cannot perform is as wrong as one that omits transmission
it can.

**Ready to publish at activation — "Forge's AI features":**

> Forge Pro includes optional AI features: the Weekly Reading and Plan in your
> own words. They are off until you choose to use one and press **Allow** on the
> in-app explanation, and you can turn them off at any time in Settings →
> Planning. When you use one, Forge sends what that feature needs to Forge's own
> server (hosted on Supabase): the names, times and days of your activities,
> counts of the days you kept, the statements you wrote about who you are
> becoming and your chapter's intention, and — for Plan — the request you
> typed; for the Weekly Reading, one week's counts. The request is made under
> an anonymous identifier with no name or email, together with Apple's signed
> proof of your Forge Pro purchase, which our server verifies. Our server asks
> OpenAI to write the answer; the app never contacts OpenAI directly and
> contains no OpenAI key. We ask OpenAI not to store the response, and OpenAI
> does not use API data to train its models by default. Forge keeps a count of
> requests per purchase and per anonymous identifier to limit use, and does not
> keep the content you sent. None of this is used for advertising or tracking,
> sold, or combined with data from other companies. Your weekly review answers,
> dates, health data, location and contacts are never sent. If you do not allow
> AI, or turn it off, every feature keeps working on your phone.

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

FORGE PRO — SEVEN DAYS FREE, THEN DECIDE

Keeping new days takes Forge Pro: the daily loop, any number of activities,
the six stats scored on what you actually do, a blade for every stretch of days
you keep, a challenge every day, and Plan. Start with a free week.

YOUR RECORD STAYS YOURS

If you ever stop, nothing is deleted or hidden. Your history, the shape, the
heatmap, the trends, the blades, the weekly reviews and the widgets stay
readable for good.

Annual with a 7-day free trial, or monthly. Forge reminds you two days before
the trial ends. Subscriptions renew automatically unless cancelled at least 24
hours before the end of the period; manage or cancel them in your Apple Account
settings. A one-time Lifetime purchase is in Settings.

Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy Policy: https://forgebetter.app/privacy
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

Rewritten 2026-09-15 against the current build, and again on 2026-10-01 for
1.1's hard paywall (`FORGE_CONTEXT.md` §6, §17.2). Paste the block below.

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

To review it in about three minutes:
1. Launch. A short first run asks seven one-tap questions, shows the starting
   stats and a plan, and asks you to pull the blade once to rehearse it.
2. The Forge Pro paywall follows (see "Forge Pro" below). Tap "Start my free
   week" and confirm with the Sandbox account: the 7-day trial costs nothing.
3. Do the one activity it names and tap "I kept my promise", then drag the blade
   upward on the Forge tab to earn the first day.
4. The Blade tab shows the record: blade, chapter, heatmap and milestones.
5. The Becoming tab shows the six areas every activity is filed under.
6. The Settings tab has Forge Pro (status, Restore Purchases, Manage
   Subscription, Lifetime), appearance, and the Privacy Policy, Terms and
   Support links.

HealthKit is read-only and optional. It is used solely to auto-complete
activities the phone can already measure (steps, distance, workouts), and is
requested in context the first time such an activity is taken on — never at
launch. No health data is stored, synced or transmitted, and the app never
writes to Health. Declining it leaves every feature working; activities are
then completed by tapping.

This build contains no AI processing. Forge Pro's AI features are prepared but
switched off in this version: the app holds no model key and makes no model
request. The Plan feature (opened from the week, under the More button) works
out every suggestion on the device from the user's own activities and history.

User-generated content — activity names, chapter names, weekly review answers —
never leaves the device. There is no social surface, no feed and no sharing
between users.

Forge Pro (in-app purchase) — a hard paywall with a free week. A new install
meets the paywall at the end of the first run, before the first day is kept.
Keeping new days needs Forge Pro: Annual ($49.99/year with a 7-day free trial,
preselected) or Monthly ($12.99/month, no trial). The paywall shows the trial as
a timeline (today everything unlocked, a reminder on day 5, the charge on day 7
unless cancelled), says "Nothing is charged today", offers a reminder before
the trial ends, and has Restore Purchases, the Terms of Use (Apple's standard
EULA) and the Privacy Policy. Every price is read from StoreKit.

There is no close button on that one screen. "Not now" at the bottom shows, the
first time, one lower annual price offered once ($29.99/year, still with the
7-day free trial; "No thanks" returns to the paywall); after that it shows one
line and the paywall stays. A Sandbox purchase or Restore Purchases continues
into the app. Lifetime ($129.99) is sold only in Settings → Forge Pro.

Nothing already recorded is ever locked: if a subscription ends, the history,
blades, Becoming, reviews and widgets stay readable, and only keeping new days,
the daily challenge and the AI features ask for Forge Pro again.

The free trial in Sandbox: the trial is free, and Sandbox runs on Apple's
accelerated clock — the 1-week trial lasts about 3 minutes and a year about an
hour. To see what a lapsed subscriber sees, cancel in Settings → Forge Pro →
Manage Subscription and wait for the period to end: the Forge tab then shows
"New days need Forge Pro. Your record stays yours." with Continue, and the rest
of the app stays readable.

Founders: installs that ran Forge 1.0 or 1.0.1 keep everything except the AI
features free, recognised on the device from their existing record or from the
App Store's original-purchase record in production. This never applies in
Sandbox, TestFlight or App Review, so a review device always sees the paywall
exactly as a new customer does.
```

### Prepared review-note paragraph for the AI activation build

Replace the "This build contains no AI processing" paragraph above with this
**only in the build where remote AI is switched on**:

```
Forge Pro includes two optional AI features: the Weekly Reading (Weekly review
→ "Read my week") and Plan in your own words (the week → More → Plan → type a
request → "Work it out"). Before the first request, the app shows a disclosure
of exactly what is sent, where, and to whom, with "Allow" and "Not now". "Not
now" keeps everything on the device. Consent can be withdrawn in Settings →
Planning. Requests go to Forge's own backend (a Supabase edge function), which
verifies the StoreKit transaction and asks OpenAI to write the answer; the app
contains no OpenAI key and never contacts OpenAI directly. Requests are made
under an anonymous identifier — there is still no account or sign-in. Every
model-written sentence is checked against the user's own numbers and labelled
"Written by a model". To test: use a Sandbox account, buy Forge Pro (the annual
trial is free), then use either feature.
```

## 7. Subscription metadata — **Forge Pro (1.1)**

Forge Pro is a hard paywall with a free week (DIRECTION_1_1 §1). The decisions
are recorded in `FORGE_CONTEXT.md` §6; this section is what App Store Connect
needs. `PremiumTests.productsAgree` reads this file, `Forge.storekit` and the
backend's `PREMIUM_PRODUCTS`, and fails if any of them names a product the
others do not.

### Products

| | Annual | Annual offer | Monthly | Lifetime |
|---|---|---|---|---|
| Product ID | `com.dawid.forge.premium.annual` | `com.dawid.forge.premium.annual.offer` | `com.dawid.forge.premium.monthly` | `com.dawid.forge.premium.lifetime` |
| Type | Auto-renewable subscription | Auto-renewable subscription | Auto-renewable subscription | Non-consumable |
| Reference name | Pro Annual | Pro Annual Offer | Pro Monthly | Pro Lifetime |
| Subscription group | **Forge Pro** | same group | same group | — |
| Level in group | 1 | 1 | 1 (all three the same level: switching is a crossgrade) | — |
| Duration | 1 year | 1 year | 1 month | — |
| Price (USA) | **$49.99** | **$29.99** | **$12.99** | **$129.99** |
| Introductory offer | **Free trial, 1 week**, new subscribers | **Free trial, 1 week**, new subscribers | none | — |
| Family Sharing | On | On | On | On |
| Display name (en-US, ≤ 30) | Forge Pro — Annual | Forge Pro — Annual Offer | Forge Pro — Monthly | Forge Pro — Lifetime |
| Description (en-US, ≤ 45) | Keep new days and the challenge, yearly. | Keep new days and the challenge, yearly. | Keep new days and the challenge, monthly. | Keep new days and the challenge, for good. |
| Where it is sold | the paywall, preselected | the exit offer, once, after "Not now" on the onboarding paywall | the paywall | Settings → Forge Pro only |

**Subscription group display name (en-US):** Forge Pro.

**One thing Apple decides, not Forge.** Every subscription in a group appears in
the system's own subscription screen (Settings → Apple Account → Subscriptions),
so an annual subscriber can see the $29.99 offer there and switch to it. That
is the price of keeping the offer in the same group, which the brief chose; a
separate group would avoid it and allow somebody to hold two subscriptions at
once.

**Character limits (App Store Connect):** display name 2–30 characters,
description at most 45. The table fits both (the longest description is 42);
`Forge.storekit` carries the same strings.

**Review screenshot for each product** — ready in
`docs/verification/1.1-s2/review/`, PNG, at sizes App Store Connect accepts for
iPhone (1206 × 2622 from the iPhone 17 Pro, 1170 × 2532 from the 17e):

| Product | File | What it shows |
|---|---|---|
| Annual | `review/annual.png` | the paywall at the end of the first run, Annual selected, "Start my free week" |
| Annual offer | `review/annual-offer.png` | the exit offer, "Start my free week at $29.99" |
| Monthly | `review/monthly.png` | the paywall with Monthly selected, "Continue" |
| Lifetime | `review/lifetime.png` | Settings → Forge Pro, the Lifetime row at $129.99 |

**Review notes for each product** (the *Review Information → Review Notes*
field; paste the matching one):

- Annual: `The default plan on the paywall shown at the end of the first run (after the seven questions and the rehearsed pull). Preselected. 7-day free trial for new subscribers, then $49.99 a year. Also reachable later from the Forge tab's "Continue" and Settings → Forge Pro → See Forge Pro.`
- Annual offer: `Shown once per install: tap "Not now" on the paywall at the end of the first run. One lower annual price, still with the 7-day free trial if the subscriber has not already used a free trial in the Forge Pro group. "No thanks" returns to the paywall.`
- Monthly: `On the same paywall, below Annual. $12.99 a month, no free trial.`
- Lifetime: `Sold only in Settings → Forge Pro → Lifetime. One-time purchase, never renews. It unlocks the same things as a subscription.`

### Required on the product page and in the app

App Review checks all of these for auto-renewable subscriptions (Guideline
3.1.2, Schedule 2 §3.8(b)):

- **In the app, beside the purchase button** — the plan's name, length and
  price, the trial and what happens when it ends, the auto-renewal terms, and
  functional links to the Terms of Use and Privacy Policy. `PaywallView` carries
  all of them; prices come from `Product.displayPrice`, per-week and per-month
  figures from `Product.price` in the product's own format, never typed.
- **Terms of Use.** Forge uses **Apple's standard EULA**
  (`https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`, linked
  from the paywall as "Terms of Use"). Add this line to the end of the **App
  Description** (§4):

  > Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

  If a custom EULA is ever preferred, set it in App Store Connect → App
  Information → License Agreement and change `ForgeLinks.appleEULA`.
- **Privacy Policy URL** in App Store Connect — already set (§2). The policy
  should gain one sentence: purchases are processed by Apple; Forge receives
  only whether the device is entitled, and anonymous `trial_started` /
  `purchase_completed` signals naming the plan (see §1).
- **Restore Purchases** — on the paywall and in Settings → Forge Pro.
- **Manage Subscription** — Settings → Forge Pro, Apple's own sheet.

### App Store Connect checklist — exactly what to create

Product IDs cannot be changed after they are created and can never be reused,
even after deletion: type them exactly. Prices are set as **United States
base price**, and App Store Connect derives every other storefront.

**A. Before anything else**

- [ ] **Business → Agreements**: the Paid Applications agreement is active,
      with banking and tax complete. Without it no product can be sold or
      tested in Sandbox.

**B. The subscription group** — *Apps → Forge → Monetization →
Subscriptions*

- [ ] Group reference name **Forge Pro** (create it if 1.0's cycle did not).
- [ ] Group localisation: **English (U.S.)**, subscription group display name
      **Forge Pro**, app name display option **Use App Name**.

**C. Annual** — `com.dawid.forge.premium.annual` (edit if it exists, create
it otherwise)

- [ ] Reference name **Pro Annual**; product ID as above; duration **1 Year**
- [ ] Level: **1** (all three subscriptions share level 1, so switching
      between them is a crossgrade)
- [ ] Availability: all countries or regions
- [ ] Subscription Prices → Add → base country **United States**, **$49.99**
      → accept Apple's derived prices
- [ ] Subscription Prices → Introductory Offer: all countries or regions,
      start today, **no end date**, type **Free**, duration **1 Week**.
      Eligibility is Apple's: one introductory offer per customer per group,
      which the app reads (`isEligibleForIntroOffer`); nothing to set
- [ ] Localisation English (U.S.): display name **Forge Pro — Annual**,
      description **Keep new days and the challenge, yearly.**
- [ ] Review Information: screenshot `review/annual.png`; review notes
      "Annual" above
- [ ] Family Sharing: **on** (see the warning in E)

**D. Annual offer** — `com.dawid.forge.premium.annual.offer` (**new**)

- [ ] Same group; reference name **Pro Annual Offer**; duration **1 Year**;
      level **1**; all countries or regions
- [ ] Price: United States **$29.99**
- [ ] Introductory offer: **Free**, **1 Week**, all countries or regions,
      start today, no end date
- [ ] Localisation English (U.S.): display name **Forge Pro — Annual Offer**,
      description **Keep new days and the challenge, yearly.**
- [ ] Review Information: screenshot `review/annual-offer.png`; review notes
      "Annual offer" above
- [ ] Family Sharing: **on**

**E. Monthly** — `com.dawid.forge.premium.monthly` (create it if it does not
exist)

- [ ] Same group; reference name **Pro Monthly**; duration **1 Month**;
      level **1**; all countries or regions
- [ ] Price: United States **$12.99**
- [ ] **No** introductory offer
- [ ] Localisation English (U.S.): display name **Forge Pro — Monthly**,
      description **Keep new days and the challenge, monthly.**
- [ ] Review Information: screenshot `review/monthly.png`; review notes
      "Monthly" above
- [ ] Family Sharing: **on**. ⚠️ Once Family Sharing is turned on for a
      product it cannot be turned off again. `Forge.storekit` says on for all
      four; if that is not the decision, change the file before the switch,
      not after

**F. Lifetime** — *Monetization → In-App Purchases*,
`com.dawid.forge.premium.lifetime`, **Non-Consumable** (edit if it exists)

- [ ] Reference name **Pro Lifetime**; all countries or regions
- [ ] Price: United States **$129.99**
- [ ] Localisation English (U.S.): display name **Forge Pro — Lifetime**,
      description **Keep new days and the challenge, for good.**
- [ ] Review Information: screenshot `review/lifetime.png`; review notes
      "Lifetime" above
- [ ] Family Sharing: **on**

Every product should now read **Ready to Submit**; "Missing Metadata" means a
field above is empty.

**G. The 1.1 version**

- [ ] Upload a build with **build number above 2** (`CURRENT_PROJECT_VERSION`
      is 3). `AppTransaction.originalAppVersion` is the build number, and the
      founder rule reads anything ≤ 2 as a 1.0 / 1.0.1 install
      (`Founder.lastFounderBuild`)
- [ ] On the version page, **In-App Purchases and Subscriptions** → add all
      four. A first subscription must be submitted together with an app
      version; products left off are not reviewed and do not go live
- [ ] App Description ends with the Terms of Use (EULA) line above
- [ ] App Review Information → Notes: §6's block, unchanged; demo account
      empty, "Sign-in required" off
- [ ] Hosted privacy policy has the purchase sentence above
- [ ] **App Privacy**: decide the Purchases question in §1 (not collected,
      or Purchases → Purchase History, Analytics, not linked, not tracking)
      and make the labels and `PrivacyInfo.xcprivacy` say the same thing
- [ ] `forge-ai` redeployed with the annual offer in `PREMIUM_PRODUCTS` before
      the model is switched on (the repo has it)

**H. Sandbox, before submitting**

- [ ] *Users and Access → Sandbox → Test Accounts*: create a tester with an
      email that is not a real Apple Account, storefront **United States**
- [ ] On an iPhone with a development or TestFlight build: Settings →
      Developer → Sandbox Apple Account (on older iOS, Settings → App Store →
      Sandbox Account), sign in with the tester. Never sign the tester into
      the real App Store
- [ ] Sandbox time runs fast: a 1-week trial lasts about 3 minutes, a month
      about 5, a year about an hour, and a subscription renews a limited
      number of times before it lapses by itself. The tester's renewal rate
      can be changed on the device or in App Store Connect
- [ ] To see the free week again, *Sandbox → Test Accounts → the tester →
      Clear Purchase History* (intro eligibility is per group, so after one
      trial the paywall correctly drops every trial word until then)
- [ ] Walk it: fresh install → first run → paywall with real prices → Not now
      → exit offer → No thanks → Not now again stays → Start my free week →
      the reminder permission → the first day. Then let it lapse (cancel in
      Settings → Forge Pro → Manage Subscription, or wait out the renewals):
      the Forge tab shows "New days need Forge Pro. Your record stays yours.",
      the Blade tab stays readable, Continue opens the no-trial paywall.
      Restore. Buy Monthly. Buy Lifetime from Settings
- [ ] The founder rule never applies in Sandbox or TestFlight, by design: a
      tester always meets the paywall. Founders can only be checked once 1.1
      is live (install 1.0.1 from the App Store, update)
- [ ] `Forge.storekit` is only Xcode's local test file. Sandbox, TestFlight
      and the App Store read App Store Connect; if a price or name is ever
      changed there, change the file too

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
- [ ] **Forge Pro (1.1):** the four IAPs are set up and attached to the version
      (§7 checklist), the App Description ends with the EULA line, and the
      Purchases label decision in §1 is made
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

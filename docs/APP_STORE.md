# Forge — App Store submission

> Everything App Store Connect asks for, written down so it is decided once
> rather than improvised in the form. Last updated **2026-10-04**, the 1.1
> release candidate (`FORGE_CONTEXT.md` §17.7): Purchase History gained
> Analytics (§1); the live privacy policy was read and §2 says what 1.1
> changes in it; the age rating was answered again under Apple's 2025
> questionnaire, **13+** (§3); 1.1's name, keywords, description, screenshots
> and review notes are in [`docs/launch/appstore-1.1.md`](launch/appstore-1.1.md),
> which is what gets pasted (§4–§6); the build is **1.1 (4)** (§7, §8). Before
> that, **2026-10-03** — Forge's AI switched on with Ask Forge (§17.6);
> **2026-09-25** — anonymous usage (TelemetryDeck) added; **2026-09-15** — the
> submission after the Guideline 2.1 reply, where the account was removed
> outright.
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

**Three rows since 1.1, all from Forge's AI** (`FORGE_CONTEXT.md` §17.6), and
Purchase History serves Analytics as well since 2026-10-04 (§17.7, below). What
the AI collects is collected only for Forge Pro users, only after they press
**Allow** on the in-app disclosure (revocable in Settings → Planning), and only
when they press something that asks: Plan's "Work it out", the review's "Read
my week", or a message in Ask Forge.

| Data type | Purpose | Linked | Tracking | What it is |
|---|---|---|---|---|
| **User Content → Other User Content** | App Functionality | Yes | No | The `AIBrief`: activity names, times, lengths and days; identity statements and the chapter's intention; counts of days kept. For a Weekly Reading, one week's counts per weekday, activity and identity. For Plan, the request typed. For **Ask Forge**, the message and the conversation before it (at most the last eight messages), the six scores and OVR as shown on Becoming, the running Arc's id, day and phase, and today's list with which are done (`CoachBrief`). Never weekly-review answers, dates, any past day's record, health readings, names, email, location or contacts. Forge's server stores none of it; OpenAI is asked not to (`store: false`). |
| **Purchases → Purchase History** | App Functionality, Analytics | Yes | No | App Functionality: the Apple-signed StoreKit 2 transaction (`X-Forge-Transaction`), verified offline by the backend to confirm Forge Pro; its `originalTransactionId` keys the per-purchase daily quotas (`ai_usage_by_transaction`, `ai_coach_usage_by_transaction`). Analytics: the paywall's anonymous events — `trial_started` and `purchase_completed` with the plan, `paywall_view` with the door — which Apple's "purchase tendencies" counts. |
| **Identifiers → User ID** | App Functionality | Yes | No | The anonymous Supabase user id minted on the first AI request — no email, password, name or provider. Used only to authenticate and rate-limit (`ai_usage`, `ai_coach_usage`). |

**Why "linked".** Every request travels under the anonymous user id, which
identifies an account even though the account has no name, email or password;
Apple's definition counts that. This is the conservative reading the §2r note
asked to be decided before activation. "Not linked" is arguable for the user
content (OpenAI receives it with no identifier, and Forge's server keeps none of
it); if that reading is chosen instead, change this table **and**
`PrivacyInfo.xcprivacy` together — `AskForgeGateTests.manifest` holds the
manifest to "linked".

**There is still no visible account.** No sign-in control, no email, no
password; nothing in the running app constructs the dormant `ForgeBackend`,
`AuthService` or `SyncService` (`BackendRegressionTests.theAppShipsWithNoAccount`
reads the source to hold it). The rows the old 1.0 account collected stay
recorded below, because each comes straight back the day sync does:

| Was collected | Only when | Would come back with |
|---|---|---|
| Email address | signed in | `AuthService` / Supabase GoTrue |
| User ID (of a visible account) | signed in | Supabase `auth.users` uuid |
| Other user content — activity names, identity statements, chapters, reviews (sync) | signed in **and** entitled | `SyncService` |
| Purchases (the `premium_status` row) | signed in | `premium_status` row |
| Other Diagnostics — device model, iOS version, app version | signed in | `UserService.registerDevice` |

In App Store Connect: **Data Linked to You: User Content (Other User Content),
Purchases (Purchase History), Identifiers (User ID)** — each App Functionality,
Purchase History Analytics as well, none used for tracking.
`PrivacyInfo.xcprivacy` declares the same three with the same purposes, and
`AskForgeGateTests.manifest` holds it.

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

**Decided 2026-10-04 (`FORGE_CONTEXT.md` §17.7):** with the paywall events
sent, the conservative reading of Apple's definition ("an individual's
purchases or purchase tendencies") counts them as **Purchases → Purchase
History** for **Analytics**, so Analytics is now a purpose of that row, in
App Store Connect and in `PrivacyInfo.xcprivacy`. A label is one row per type,
so it cannot be both linked and not linked; the AI's "linked" governs, and the
anonymous telemetry half is over-stated rather than under-stated.

### Forge's AI — active since 1.1 (`FORGE_CONTEXT.md` §17.6)

*Was "prepared, not active" (§2r); switched on in session S6.* The three rows
above are what it collects. What stays true: the app holds **no OpenAI key**
(the only one is the server secret `OPENAI_API_KEY`), the app never contacts
OpenAI directly, responses are requested with `store: false`, OpenAI does not
train on API data by default, every model-written reply, reading and plan is
labelled as such on screen, a proposal to change the week is only applied from
Plan's review, and Anthropic / Claude is not used anywhere. A message to Ask
Forge that suggests a crisis is answered on the phone with the 988 lifeline and
is **not sent**.

### Data not collected

**Everything else.** Health & Fitness, Location, Contacts, Photos, Browsing
History, Search History, Crash Data, Performance Data, Sensitive Info, Financial
Info, Physical Address, Phone Number, Name, Email Address, Device ID, Customer
Support, Advertising Data, every User Content row other than Other User Content
(no Emails or Text Messages, Photos or Videos, Audio, Gameplay Content), and
every Usage Data and Diagnostics row other than the two above.

**Customer Support specifically.** Ask Forge's *Report* opens a pre-filled
email in the person's own mail app; the app sends nothing. Mail they choose to
send is ordinary support email, not data collected by the app.

**The backup file specifically** (Settings → Your Data, 1.1, §17.7). Export
Backup writes the record to a file the person saves or sends with the share
sheet; Import Backup reads a file they pick. Neither touches the network and
Forge never receives either: not collected.

**Health data specifically.** Since 1.1 (session S5, `FORGE_CONTEXT.md`
§17.5) Forge reads **steps, workout minutes, sleep and mindful minutes** from
HealthKit to tick off the activities they measure. It is **read-only**
(`requestAuthorization(toShare: [], read:)` in `Engine/HealthBridge.swift`), and
it is **read on the device and not collected**: a reading is used the moment it
arrives to decide whether an activity is done and then dropped. Readings are
never written to disk, never synced, never sent to telemetry
(`ForgeTelemetry.Event` has no case that could hold one) and never included in
an `AIBrief` — there is no field on that struct that could hold one. Ask Forge's
`CoachBrief` carries whether each of today's activities is done — a completion,
which a Health-checked activity can be — and never a reading. What Forge
keeps is the completion it caused (an activity id, banked as `health` in the
day's record) and `HealthLedger` (the primer's answer, which activities were
offered, which were ticked today): decisions, never values. Health & Fitness is
therefore **not** declared on the label, and `PrivacyInfo.xcprivacy` says the
same in a comment beside its collected-data list.

> ⚠️ **Read-only does not exempt the app from the *write* purpose string.** The
> first upload was rejected with `ITMS-90683: Missing purpose string in
> Info.plist — NSHealthUpdateUsageDescription`. Upload validation checks the
> **entitlement**, not the usage, and `com.apple.developer.healthkit` grants
> read and write together — so both `NSHealthShareUsageDescription` and
> `NSHealthUpdateUsageDescription` must be in `Forge/Info.plist`. Both are, as
> of 2026-09-04, rewritten in 1.1 S5 for the four types now read. The update string says the app does not write, which is true
> and which iOS will never show. Do not delete it to tidy up. See
> `FORGE_CONTEXT.md` §2m.

### What the app does over the network, in full

Re-audited 2026-10-03, when Forge's AI was switched on (§17.6), and checked
again 2026-10-04 for the backup (§17.7), which added no path; before that
2026-09-25, when anonymous usage was added (§2p). Every path, and what starts
it:

| Path | Starts when | Sends |
|---|---|---|
| StoreKit product load | Launch, and on any transaction | Apple's own; no user data |
| TelemetryDeck (`nom.telemetrydeck.com`) | One of the events in `ForgeTelemetry.Event`, only while **Share anonymous usage** is on | Event name, its closed parameters, `days_since_install`, the SDK's device, locale and session fields, and an anonymised, double-hashed install id |
| Forge's AI (`eslaeueyeuaejdnqfasv.supabase.co`): `POST /auth/v1/signup` once, a token refresh when it expires, `POST /functions/v1/forge-ai` | A Forge Pro user who allowed AI presses "Work it out", "Read my week" or sends a message in Ask Forge — in that order of checks: the switch, consent, the StoreKit proof, then the anonymous identity (`RemoteForgeAI.connect`) | The request content in §1's first row, the anonymous JWT and the StoreKit JWS. Never at launch, on opening a screen, or in the background |

**That is the whole table.** The visible account's sign-in, sync, device
registration and entitlement row are still unreachable: nothing in the running
app constructs `ForgeBackend`, so the project in `Info.plist` is only ever used
by `AnonymousIdentity` and `AIEndpoint`. The StoreKit call is Apple's own,
carries no Forge data, and fails silently to `.unavailable` with no UI attached.

**Two hosts, held by tests.** `ForgeNetwork.allowedHosts` is exactly
`nom.telemetrydeck.com` and Forge's project host (which joins only because the
switch is on and the project is configured, `ForgeNetwork.aiHost`);
`URLSessionTransport` refuses any other host before a socket is opened, and
`NoNetworkTests` / `BackendRegressionTests` fail the run if the list changes or
if a request to any other host gets through. TelemetryDeck's
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

**The hosted policy, read on 2026-10-04.** forgebetter.app/privacy says
"LAST UPDATED 27 SEPTEMBER 2026" and describes 1.0.1 correctly: no account,
TelemetryDeck with its switch, Apple Health read-only, no AI, no purchase
events. The 1.0-era warning that stood here (sign-in, a server, an entitlement
row) no longer applies. What 1.1 changes in it is
[`docs/launch/privacy-policy.md`](launch/privacy-policy.md): section by section
against the live page's own headings, which sections to replace, the new "AI
features (Forge Pro)" section, and the exact text. **Apply it the day 1.1 goes
live**, not before: the live 1.0.1 makes no AI request and sells nothing, and a
policy describing either is as wrong as one omitting them. Its Apple Health
paragraph also corrects the live page's types (steps, walking and running
distance, workouts — 1.0's) to 1.1's four.

The short form, for anywhere a paragraph is wanted:

**"Forge's AI features" (1.1):**

> Forge Pro includes optional AI features: Ask Forge, the Weekly Reading and
> Plan in your own words. They are off until you choose to use one and press
> **Allow** on the in-app explanation, and you can turn them off at any time in
> Settings → Planning. When you use one, Forge sends what that feature needs to
> Forge's own server (hosted on Supabase): the names, times and days of your
> activities, counts of the days you kept, the statements you wrote about who
> you are becoming and your chapter's intention; for Plan, the request you
> typed; for the Weekly Reading, one week's counts; and for Ask Forge, your
> message with the conversation before it (at most eight messages), your six
> stats and overall score, where you are in a running Arc, and today's list
> with which are done. The Ask Forge conversation is kept on your phone, and
> can be cleared there. The request is made under
> an anonymous identifier with no name or email, together with Apple's signed
> proof of your Forge Pro purchase, which our server verifies. Our server asks
> OpenAI to write the answer; the app never contacts OpenAI directly and
> contains no OpenAI key. We ask OpenAI not to store the response, and OpenAI
> does not use API data to train its models by default. Forge keeps a count of
> requests per purchase and per anonymous identifier to limit use, and does not
> keep the content you sent. None of this is used for advertising or tracking,
> sold, or combined with data from other companies. Your weekly review answers,
> dates, any past day's record, health readings, location and contacts are
> never sent, and a message to Ask Forge that suggests a crisis is answered on
> your phone with the 988 Suicide & Crisis Lifeline and is not sent. If you do not allow
> AI, or turn it off, every feature keeps working on your phone.

---

## 3. Age rating — **13+** under Apple's 2025 questionnaire

Answered again on 2026-10-04 (`FORGE_CONTEXT.md` §17.7). The 1.0 answer that
stood here ("4+, answer None to everything") predates Apple's current
questionnaire, which has five ratings (4+, 9+, 13+, 16+, 18+) and new
questions; under it, 4+ would be wrong twice. Every answer, with Apple's
definition and the reason, is in
[`docs/launch/appstore-1.1.md`](launch/appstore-1.1.md) §9. The three that are
not "No"/"None":

- **Guns or Other Weapons: Frequent** — Apple's definition names swords, and
  the sword is the main screen. This alone gives 13+.
- **Health or Wellness Topics: Yes** — Arcs recommend training, steps, sleep
  and early mornings; Apple Health ticks off four kinds of activity (9+).
- **Medical or Treatment Information: Infrequent** — the conservative answer
  for Ask Forge's 988 crisis reply; Forge diagnoses and treats nothing and Ask
  Forge declines to (13+; "None" is arguable and changes nothing).

**User-Generated Content: No** and **Messaging and Chat: No** under Apple's
current definitions ("broad distribution of content created by users";
"users can directly communicate with one another"): nothing a person writes
reaches another person, and Ask Forge is a person and a model. The 1.0 answer
to the old UGC question was "yes, technically"; the question changed. 13+ costs
nothing with an audience of 18 to 30 and matches the privacy policy's "not
intended for children under 13".

---

## 4. Description, name, subtitle, keywords, promotional text

**For 1.1, everything that is pasted is in
[`docs/launch/appstore-1.1.md`](launch/appstore-1.1.md)** — three name and
subtitle pairs with the recommendation (§1), keywords (§2), promotional text
for the season and after it (§3), the description whose first lines give the
price (§4) and What's New (§5), each counted by a script. The 1.0 description,
subtitle ("A day you earn, not one you tick") and keywords that stood here
describe a free app with no Arcs, stats or AI; they are in git history and must
not be pasted for 1.1. The description still ends with the Terms of Use (EULA)
and Privacy Policy lines §7 requires.

## 5. Screenshots — **a new set is needed for 1.1**

The five plates in `screenshots/appstore-6.9/` (1290 × 2796, outside the
repository, beside it) show 1.0's interface: Settings as the fourth tab where
1.1 has Arcs, no Arc, no Forge Pro, the home screen's control bar from before
§2j, and on plate 1 a film quote with its character's name, a line the app
removed on 2026-09-15 (§2o). Against a 1.1 description that names Arcs, Forge Pro
and Ask Forge, they would be a real Guideline 2.3.3 risk rather than the small
one recorded for 1.0. **The plan for
1.1 — six frames at 1320 × 2868 with headlines, and how to capture each — is
[`docs/launch/appstore-1.1.md`](launch/appstore-1.1.md) §8.** Frame 5 (Ask
Forge) has to come from a real Sandbox purchase on an iPhone, because the
Simulator's purchases cannot reach the model.

## 6. App Review notes

**For 1.1, paste the block in
[`docs/launch/appstore-1.1.md`](launch/appstore-1.1.md) §6** (3,897 bytes).
App Store Connect's Notes field takes at most **4,000 bytes**; the block that
stood here (rewritten 2026-10-01 and 2026-10-03) was **6,251** and could not
have been pasted whole. The new one keeps everything a reviewer needs: how the
hard paywall is reached and why it cannot be closed,
the Sandbox trial, the founder rule and why a reviewer never meets it, the AI
consent (Guideline 5.1.2(i)), the safety reply and Report, and where Apple
Health is asked. It is plain ASCII, so no character costs more than one byte.

### The AI paragraph, applied

App Review buys in Sandbox, so `FORGE_ALLOW_SANDBOX` must stay `true` on the
server through TestFlight and the review window if the reviewer is to see the
model rather than the one "can't reach the server" line (`supabase/README.md`
§1.6). It also applies to every later review: each update is reviewed with a
Sandbox purchase, so turning it off after 1.1 is approved means turning it on
again for each review.

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

- [ ] Upload **1.1 (4)**: `MARKETING_VERSION` 1.1, `CURRENT_PROJECT_VERSION`
      4 in all six build configurations, the widget extension's the same
      (`PremiumTests.uploadable`). The build number must stay above 2:
      `AppTransaction.originalAppVersion` is the build number, and the
      founder rule reads anything ≤ 2 as a 1.0 / 1.0.1 install
      (`Founder.lastFounderBuild`). If App Store Connect already has a 4 for
      1.1 (a TestFlight upload), raise it in all six places before archiving
- [ ] Export compliance: answered in the build (`ITSAppUsesNonExemptEncryption`
      = NO in `Forge/Info.plist`: HTTPS through the system only), so the
      build is not held at "Missing Compliance"
- [ ] On the version page, **In-App Purchases and Subscriptions** → add all
      four. A first subscription must be submitted together with an app
      version; products left off are not reviewed and do not go live
- [ ] App Description ends with the Terms of Use (EULA) line above
- [ ] App Review Information → Notes: the block in
      `docs/launch/appstore-1.1.md` §6 (3,897 bytes); demo account empty,
      "Sign-in required" off
- [ ] Hosted privacy policy: `docs/launch/privacy-policy.md` applied the day
      1.1 goes live (§2); its "Forge Pro and the App Store" section carries the
      purchase sentence above
- [ ] **App Privacy** in App Store Connect set to §1's five rows
      (`docs/launch/appstore-1.1.md` §7). The Purchases question is decided:
      Purchase History, App Functionality and Analytics, linked, not
      tracking; `PrivacyInfo.xcprivacy` already says so
- [ ] Age rating questionnaire answered as §3 (13+)
- [x] `forge-ai` redeployed with the annual offer in `PREMIUM_PRODUCTS` before
      the model is switched on (owner, before S6)
- [x] `forge-ai` redeployed with the `coach` task (v2) and migration `0009`
      pushed (S6, 2026-10-03, `FORGE_CONTEXT.md` §17.6)

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
- [ ] Privacy policy: apply `docs/launch/privacy-policy.md` (the 1.1 changes,
      section by section, to the live page) the day 1.1 goes live (§2); until
      then the live 27 September text stays, because 1.0.1 makes no AI request
      and sells nothing
- [x] Terms URL live, and `ForgeLinks.terms` set; **Support** set too, and the
      row leads the About section
- [x] `#warning` in `Shared/ForgeLink.swift` deleted — replaced by a test that
      fails if any of the three URLs stops being the live one
- [ ] **1.1 screenshots**: six frames at 1320 × 2868
      (`docs/launch/appstore-1.1.md` §8). The 1.0 plates in
      `screenshots/appstore-6.9/` show 1.0's interface and are not for 1.1 (§5)
- [x] Dynamic Type at AX5 and Reduce Motion walked in the Simulator (2026-09-03)
- [ ] **VoiceOver** — still not exercised by ear. Since 1.1's release pass
      (`FORGE_CONTEXT.md` §17.7) `AccessibilityTests` renders every 1.1
      control in a window and reads back what VoiceOver is handed (label,
      traits, hint, selected), which found and fixed two gaps; nobody has
      listened to it
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
- [x] Privacy nutrition labels decided (§1) — rewritten 2026-10-03 for the AI:
      Other User Content, Purchase History and User ID, linked, App
      Functionality; plus §2p's two anonymous-usage rows; Purchase History
      gained Analytics on 2026-10-04
- [x] Age rating decided (§3) — answered again 2026-10-04 under Apple's 2025
      questionnaire: 13+
- [x] Name, subtitle, keywords, promotional text, description and What's New
      written for 1.1 (`docs/launch/appstore-1.1.md` §1–§5)
- [x] Review notes written for 1.1 (`docs/launch/appstore-1.1.md` §6) —
      2026-10-04, inside the 4,000-byte limit
- [ ] **Forge Pro (1.1):** the four IAPs are set up and attached to the version
      (§7 checklist), the App Description ends with the EULA line, and the
      Purchases label decision in §1 is made
- [x] Network audit re-done and written down (§1, 2026-10-03) — StoreKit,
      TelemetryDeck, and Forge's own project for the AI, each held by tests
      (`NoNetworkTests`, `BackendRegressionTests`)
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
- [x] **Hosted privacy policy matches the accountless build** — read
      2026-10-04: the live page (27 September 2026) has no account, sign-in or
      server, and carries the anonymous-usage section (§2)
- [ ] **App Privacy in App Store Connect** — for 1.1, all five rows of §1:
      linked Other User Content, Purchase History (App Functionality,
      Analytics) and User ID; not linked Product Interaction and Other
      Diagnostic Data (Analytics); nothing used for tracking — matching
      `PrivacyInfo.xcprivacy`
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
- [x] **1.1 (4) archived** (2026-10-04, Release): the app carries
      `healthkit`, an empty `healthkit.access`, `healthkit.background-delivery`
      and the App Group; the widget extension only the App Group; both 1.1 (4).
      The Xcode-managed App Store profile on the build machine for
      `com.dawid.forge` (created 2026-09-03) already carries HealthKit and
      background delivery, so the App ID has the capability; the portal page
      itself was not opened (`FORGE_CONTEXT.md` §17.7)
- [x] `PrivacyInfo.xcprivacy` present and matching §1 — **and §1 was corrected
      to match it**: Diagnostics is collected for a signed-in account and used
      to say "not collected"
- [x] Large widget added, and the sword-in-stone widget artwork withdrawn from
      every family and from the Live Activity (2026-09-03)

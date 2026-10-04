# Forge 1.1 — App Store listing

Written on 2026-10-04 (session S7, the release candidate) against the build
that ships: **1.1 (4)**, branch `release/1.1`. Every claim below is something
that build does; every count was checked by a script, not by eye. The
submission checklist and the reasoning behind the privacy answers live in
[`docs/APP_STORE.md`](../APP_STORE.md); this file is what gets pasted.

## Where each part goes

| App Store Connect field | Where | Section |
|---|---|---|
| Name, Subtitle | Apps → Forge → App Information → Localizable Information (editable while 1.1 is being prepared) | §1 |
| Keywords | the 1.1 version page → App Store → Keywords | §2 |
| Promotional Text | the 1.1 version page (can change any time, without a build) | §3 |
| Description | the 1.1 version page | §4 |
| What's New in This Version | the 1.1 version page | §5 |
| App Review Information → Notes | the 1.1 version page, bottom | §6 |
| App Privacy | Apps → Forge → App Privacy | §7 |
| Screenshots, iPhone 6.9" | the 1.1 version page → Previews and Screenshots | §8 |
| Age Rating | Apps → Forge → App Information → Age Rating → Edit | §9 |

Name, subtitle, keywords, description and screenshots can only change with a
new version; promotional text can change at any time.

---

## 1. Name and subtitle (30 characters each)

Apple reads the name, the subtitle and the keyword field together and matches a
search against words from any of them, so "habit" in the name and "tracker" in
the keywords answer "habit tracker". A word used twice counts once, which is why
§2 repeats nothing from the name or subtitle. The name carries the most weight,
then the subtitle, then the keywords.

| Pair | Name | Subtitle | Aims at |
|---|---|---|---|
| **A — recommended** | `Forge: Habit & Discipline` (25) | `Winter Arc · Level Up Daily` (27) | discipline, habit (+ *tracker* → habit tracker), winter arc, level up; self improvement from the keywords |
| B | `Forge: Habit Tracker` (20) | `Self Improvement & Discipline` (29) | habit tracker, self improvement, discipline; winter arc and level up from the keywords only |
| C | `Forge: Winter Arc Discipline` (28) | `Habit Tracker · Level Up Daily` (30) | winter arc, discipline, habit tracker, level up; self improvement from the keywords |

**Recommendation: A.** The two evergreen words, *habit* and *discipline*, sit in
the name, which keeps its weight all year. *Winter Arc* and *Level Up* sit in
the subtitle, where they catch this season's searches from the people Forge is
built for (DIRECTION_1_1, "Who Forge is for") and describe something in the
build: Winter Arc is one of Forge's four Arcs. After January 31 the subtitle
should change with the next version, for example to `Monk Mode · Level Up
Daily` (26), with *winter,arc* taking the place of *monk,mode* in the keywords;
the name never has to.

- **B** wins the biggest query, *habit tracker*, which is also the most crowded
  one on the store, and puts *winter arc* in the keyword field only, its
  weakest position, exactly when the term is at its height. It also names Forge
  as the thing 1.0's first screen said it was not.
- **C** is the strongest for *winter arc* from October to January, but a name
  only changes with a new version, so from February a seasonal word would sit in
  the name of an all-year app. At least two apps on the US store are *named*
  Winter Arc ([Winter Arc – Grow in the Cold](https://apps.apple.com/us/app/winter-arc-grow-in-the-cold/id6736709926),
  [Winter Arc – 75 Day Challenge](https://apps.apple.com/us/app/-/id6748643261)); a
  name built around another app's name invites a Guideline 2.3.7 objection. As a
  subtitle phrase it describes Forge's own program.

The separator `·` is not indexed; a comma or a dash works the same.

## 2. Keywords (100 characters)

For pair **A**:

```
tracker,self,improvement,routine,morning,goals,monk,mode,challenge,focus,stats,glow,planner,workout
```

**99 / 100.** No spaces after commas, no word from the name or the subtitle (*forge,
habit, discipline, winter, arc, level, up, daily*), no plurals of words already
present. What the words assemble with the name and subtitle: *habit tracker,
discipline tracker, self improvement, morning routine, monk mode* (an Arc),
*glow up, daily planner, winter arc challenge, workout tracker, level up stats*.
Left out on purpose: *streak* (Forge does not sell loss-aversion), anything
medical, and other apps' or programs' names (*75 Hard* is somebody else's program).

For pair B: `winter,arc,level,up,routine,morning,goals,monk,mode,challenge,focus,stats,glow,planner,workout,daily` (100).
For pair C: `self,improvement,routine,morning,goals,monk,mode,challenge,focus,stats,glow,planner,workout` (91).

## 3. Promotional text (170 characters)

From launch to January 31:

```
Winter Arc: 90 days through the dark months, in four phases. Your six stats move only with what you actually do. Pull the sword on every day you keep.
```

**150 / 170.** From February 1, without a new build:

```
Lock In 7: seven days on the plan you already have, with a challenge each day. Your six stats move only with what you actually do. Free for 7 days.
```

**147 / 170.**

## 4. Description (4,000 characters)

```
Free for 7 days, then $49.99 a year. Or $12.99 a month with no trial. Cancel anytime.

Forge turns the things you said you would do into a day you earn. Finish today's list and the sword in the stone comes loose. Then you pull it free. That pull banks the day.

SIX STATS, REAL NUMBERS
Physical, Intellect, Discipline, Mental, Relationship and Ambition, each scored out of 100, with an overall score. Seven questions set where you start. After that, the numbers move only with what you actually do.

SEE WHERE YOUR PLAN GOES
Before you begin, Forge shows your stats now, in 7 days, in 30 days and at full potential, worked out on the plan you choose if you keep five days in seven. A projection, never a promise.

ARCS
Programs with a start and an end. Winter Arc: 90 days through the dark months, in four phases. Monk Mode 30, Discipline 66, and Lock In 7 to start. An Arc shows what it adds to your week before it adds anything, asks before each phase raises the bar, sets a trial every week, and leaves a mark on your record when you finish.

A BLADE FOR EVERY STRETCH
Nine blades, from Rough to Enduring at 180 days kept, then a temper mark for every ninety days after that. Days you have kept are never taken away.

A CHALLENGE EVERY DAY
One small challenge a day. Finish it and it counts toward its stat.

CHECKED BY APPLE HEALTH
Steps, workouts, sleep and mindful minutes can tick themselves off. Read-only and on your iPhone: Forge never writes to Health, and nothing it reads leaves the phone. Optional; you can always tick anything yourself.

ASK FORGE AND PLAN
A coach that reads your record. Ask why a stat is slipping, which Arc fits your week, or how to make next week harder. It can propose changes to your week, and nothing changes until you review them and apply them. Written by AI, labelled as such, and used only after you allow it. Not medical advice. Plan works your week around the hours you cannot move, and changes nothing until you apply it.

ONE EVENING A WEEK
Your week in numbers, one observation drawn from your own record, and two questions. With Forge Pro, a written Weekly Reading, checked against your record before you see it.

YOURS, ON YOUR IPHONE
No account, no sign-in, no ads. Your record stays on your iPhone, and you can export it as a backup file and import it on a new one. Home Screen and Lock Screen widgets, a Live Activity for the day, and a card of a blade, an Arc or your stats to save, in portrait or square.

FORGE PRO
Annual: free for 7 days, then $49.99 a year. Monthly: $12.99 a month, no trial. Lifetime: $129.99 once, in Settings. Forge can remind you two days before the trial ends. Payment is charged to your Apple Account when you confirm, or when the free week ends. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period, and renewal is charged within the 24 hours before it ends. Manage or cancel in your Apple Account settings. Prices are US prices; the App Store shows yours before you confirm.

If you stop, your record stays readable: history, blades, stats, reviews and widgets. Keeping new days, Arcs, the daily challenge and Ask Forge need Forge Pro.

Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy Policy: https://forgebetter.app/privacy
```

**3,300 / 4,000.** Paste as is; the App Store keeps the line breaks.

- **The first lines** say what it costs, as asked: the free week and the annual
  price, the monthly price with no trial, cancel anytime. The free week is
  written in digits like a price, as the paywall's badge writes it ("7 days
  free").
- **Prices are US prices.** The App Store shows each storefront its own price,
  but a storefront with no localization of its own reads this English (U.S.)
  text, which is why the Forge Pro paragraph says so. If Forge is sold only in
  the United States, that sentence can go.
- **Nothing invented.** No user counts, ratings, outcomes or percentages; no
  claim about anybody changing; the one projection is called a projection and
  states its assumption, as the screen does. Every feature named is in 1.1 (4):
  the six stats and the assessment (§17.1), Forge Pro (§17.2), the four Arcs
  (§17.3), nine blades and temper marks (§17.4), Apple Health (§17.5), Ask
  Forge, the Weekly Reading and Plan in your own words (§17.6), the backup
  (§17.7).
- The subscription paragraph is the paywall's own fine print in other words,
  and the two links Apple requires end the text (Guideline 3.1.2).

## 5. What's New in This Version

```
Forge 1.1 is the biggest change since launch.

Six stats. Seven questions set where you start in Physical, Intellect, Discipline, Mental, Relationship and Ambition. From then on the numbers move only with what you do.

Arcs. Programs with a start and an end: Lock In 7, Monk Mode 30, Discipline 66 and Winter Arc, 90 days in four phases. Each shows what it adds before it adds it, and leaves a mark on your record when you finish.

Checked by Apple Health. Steps, workouts, sleep and mindful minutes can tick themselves off. Read-only, on your iPhone.

Ask Forge. A coach that reads your record and can propose changes to your week, which you review before anything moves. Only after you allow it.

Two new blades. Honed and Enduring, and after Enduring a temper mark for every ninety days kept.

Also: a daily challenge that counts toward its stat, a backup you can export and import in Settings, and widgets that say when new days need Forge Pro.

Forge Pro. New installs start with 7 days free, then $49.99 a year, or $12.99 a month. If you used Forge before 1.1, everything except the AI stays free for you, and your record carries over exactly as it is.
```

**1,158 / 4,000.** Founders are told the one thing that changes for them; nobody
is told to worry about losing anything, because nothing is lost.

## 6. App Review Information

- **Sign-in required:** off. Demo account fields: empty.
- **Contact:** the owner's name, phone and email (App Store Connect keeps them
  from 1.0.1; check they are current).
- **Notes** (App Store Connect's limit is **4,000 bytes**; this is
  **3,897 bytes**, plain ASCII so no character costs more than one byte — the
  previous block in APP_STORE.md §6 was 6,251 and would not have fitted):

```
No account or sign-in exists, so there are no demo credentials.

HOW TO REVIEW (Sandbox account)
1. Launch. The first run: seven one-tap questions, what to build, starting stats with Now / 7 days / 30 days / Full (a labelled projection), the research, a plan with an Arc, one rehearsal pull of the blade.
2. The Forge Pro paywall follows. Tap "Start my free week" and confirm in Sandbox: the 7-day trial costs nothing.
3. Do the one activity it names, tap "I kept my promise", then drag the blade up on the Forge tab to earn the first day.
4. Tabs: Forge (the day), Arcs, Becoming (six stats, Ask Forge), Blade (the record). Settings is the gear on Becoming and Blade.

FORGE PRO: HARD PAYWALL, FREE WEEK
A new install meets the paywall at the end of the first run. Keeping new days needs Forge Pro: Annual $49.99/year with a 7-day free trial (preselected), or Monthly $12.99/month, no trial. The screen shows the trial as a timeline (today unlocked, reminder day 5, charge day 7 unless cancelled), "Nothing is charged today", an optional local reminder two days before the trial ends, Restore Purchases, Terms of Use (Apple's standard EULA) and Privacy Policy. Prices come from StoreKit.
No close button. "Not now" shows, once per install, one lower annual price ($29.99/year, free week if eligible; "No thanks" returns). After that, "Not now" says "Forge needs Forge Pro to keep new days." and the paywall stays. A purchase or Restore continues. Lifetime ($129.99) is sold only in Settings > Forge Pro.
When a subscription ends nothing recorded is locked: history, blades, stats, reviews and widgets stay readable; only new days, Arcs, the daily challenge and AI need Forge Pro. Sandbox: the free week lasts about 3 minutes.

FOUNDERS
Installs that ran 1.0 or 1.0.1 keep everything except the AI free, recognised on the device from their existing record, or in production from the original App Store purchase (build 2 or earlier). Never in Sandbox, TestFlight or App Review: a review device meets the paywall as a new customer.

AI (FORGE PRO)
To test: start the trial, then Becoming > speech bubble (top right) > a suggested question > Allow. The Weekly Reading is in the weekly review, first offered after a full week of use. Plan in your own words: Forge tab > Week > ... > Plan the week > type > Work it out.
Before the first request the app shows exactly what is sent, where and to whom, with Allow and Not now (5.1.2(i)); nothing is sent without Allow, and it can be withdrawn in Settings > Planning. Requests go to Forge's backend (Supabase), which verifies the StoreKit transaction and asks OpenAI for the answer. The app holds no OpenAI key and uses an anonymous identifier, not an account.
Ask Forge: no persona or avatar, "Not medical advice" under its title. It declines diagnosis or treatment, drugs, PEDs, supplement doses, extreme diets, sexual content and harassment. A message suggesting self-harm is answered on the device with the 988 Suicide & Crisis Lifeline (Call 988, Text 988) and is not sent. Long-press a reply > Report opens a pre-filled email the user sends. Replies are labelled "Written by Forge's AI"; a proposed change opens a review screen and applies only when confirmed.

APPLE HEALTH (READ-ONLY, OPTIONAL)
Steps, workout minutes, sleep and mindful minutes tick off activities the phone can measure. Forge never writes, and nothing it reads leaves the device. Permission is asked after a screen listing the four types, when such an activity first enters the day after the first run. To see it: Forge tab > + on today's list > Hit your steps > close the sheet. Declining leaves every activity completable by tapping.

USER CONTENT
What users write stays on the device; nothing is shared between users. Settings > Your Data exports a backup file and imports one after a confirmation. Anonymous usage stats (TelemetryDeck) can be turned off in Settings > Privacy.
```

**Attach nothing else.** Each in-app purchase has its own review screenshot and
note (APP_STORE.md §7). The server must keep `FORGE_ALLOW_SANDBOX=true` through
TestFlight and App Review: the reviewer buys in Sandbox, and without it Ask
Forge would answer "can't reach the server" (`supabase/README.md` §1.6).

## 7. App Privacy (the nutrition labels)

Answered from the code, field by field, in APP_STORE.md §1; this is what to
click. **Data used to track you: none.** Tracking: **No** for every type.

| Category → type | Purposes | Linked to the user | What it is in the code |
|---|---|---|---|
| User Content → **Other User Content** | App Functionality | **Yes** | The AI request: activity names, times and days, counts of days kept, identity statements and the chapter's intention; a week's counts for the Weekly Reading; the typed request for Plan; for Ask Forge the message, up to eight earlier turns, the six scores and OVR, the running Arc's id, day and phase, today's list with what is done (`AIBrief`, `CoachBrief`). Only after Allow, only on a button that asks. |
| Purchases → **Purchase History** | App Functionality, **Analytics** | **Yes** | App Functionality: Apple's signed transaction (`X-Forge-Transaction`), checked by the server to confirm Forge Pro. Analytics: the anonymous events `trial_started` and `purchase_completed` (with the plan) and `paywall_view` (with the door). |
| Identifiers → **User ID** | App Functionality | **Yes** | The anonymous Supabase user id minted on the first AI request; no email, name or password. |
| Usage Data → **Product Interaction** | Analytics | **No** | `ForgeTelemetry.Event`, with closed parameters, to TelemetryDeck; off in Settings → Privacy. |
| Diagnostics → **Other Diagnostic Data** | Analytics | **No** | What the TelemetryDeck SDK attaches: device model, OS and app version, locale, region, time zone, display and accessibility settings, its anonymous session counts. |

**Everything else: Not collected** — including Health & Fitness (read on the
device, used, dropped; never stored or sent), Contacts, Location, Email
Address, Name, Crash Data, Customer Support (Report opens the person's own mail
app) and the backup file (the person saves it where they choose; Forge never
receives it).

**Why Purchase History is linked although the telemetry half is anonymous:** a
label is one row per data type with one linked answer, and the AI half travels
with the anonymous user id, which Apple counts as linked (the S6 decision,
kept). Over-stating the telemetry half is the safe side.
`Forge/PrivacyInfo.xcprivacy` declares exactly these five rows, and
`AskForgeGateTests.manifest` holds it.

## 8. Screenshots — six frames for the 6.9" display

**Size: 1320 × 2868 portrait** (the iPhone 17 Pro Max's own size; App Store
Connect also takes 1290 × 2796). One set at 6.9" covers every smaller iPhone.
Each frame is a designed plate: a headline, one support line under it, and the
app's own screen below, on Forge's black. No exclamation marks, no prices typed
onto an image, no ratings or counts that are not on the screen.

| # | Screen | Headline | Support line |
|---|---|---|---|
| 1 | The first run's projection: the stage control on **Full**, the hexagon at 100 with the Enduring blade; or Now and Full potential side by side | **Your stats now, and at full potential.** | Seven questions set where you start. The projection runs on your plan. |
| 2 | Becoming: the hexagon with OVR and the six tiles, all with numbers (a record of about two months) | **Six stats. Real numbers.** | They move only with what you actually do. |
| 3 | Arcs: the running Winter Arc card, "Day 15 of 90", the phase, this week's trial | **Winter Arc. 90 days.** | Four phases, a trial every week, and a mark on your record when you finish. |
| 4 | The Forge tab with the blade loose and a finger on the grip, mid-pull | **Earn the day. Pull the sword.** | Finish the list and the blade comes loose. Then you pull it free. |
| 5 | Ask Forge: a question and a real reply, "Not medical advice" visible under the title | **Ask Forge.** | A coach that reads your record. Nothing changes until you apply it. |
| 6 | The Forge tab's list with a row ticked off, "Checked by Apple Health" under its name | **Checked by Apple Health.** | Steps, workouts and sleep tick themselves off. Read-only, on your iPhone. |

**How to capture each one** (iPhone 17 Pro Max Simulator, iOS 26.5, a Debug
build, so Settings → Debug can seed the record; nothing from Settings appears in
any frame):

- Before every capture:
  `xcrun simctl status_bar <udid> override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3`,
  then `xcrun simctl io <udid> screenshot frame-N.png` — the file is 1320 × 2868.
- **1**: a fresh install, through the questions to the projection; tap **Full**.
  For the side-by-side, capture **Now** too.
- **2**: Settings → Debug → Forge Pro **Pro**, **Seed 12 Weeks of History**,
  then Becoming. Wait for the hexagon to settle before capturing.
- **3**: Settings → Debug → Arc **Winter Arc**, Started days ago **14**,
  **Start Arc 14 Days Ago**, then the Arcs tab.
- **4**: a day with one activity left: complete it, then hold the grip and drag
  part-way (the simulator's `touch_path`, FORGE_CONTEXT §14) and capture while
  the finger is down; the finger is drawn on the plate, not in the capture.
- **5**: **on a physical iPhone with a real Sandbox purchase**, so the reply is
  the model's own: the Simulator's purchases are Xcode's, which the server
  refuses by design, and the scripted replies of a Debug build may not be shown
  as Forge's AI (§5 #10). A 17 Pro capture (1206 × 2622) goes into the same
  plate as the others, scaled; the plate is what is 1320 × 2868. Ask one of the
  three suggested questions.
- **6**: Settings → Debug → Forge Pro **Pro**; add **Hit your steps** from the
  `+` on today's list, Continue on the Health screen and Allow; add a step
  sample above 8,000 in the Simulator's Health app (Browse → Activity → Steps →
  Add Data); return to Forge.

Order: as asked, transformation first. The first three are the ones search
results show, so they carry the numbers, the stats and Winter Arc. Screenshot 4
is the one only Forge has. Captures of every one of these screens from this
session's QA are in `docs/verification/1.1-s7/` (iPhone 17 Pro and 17e sizes,
for reference, not for upload).

## 9. Age rating (App Store Connect's questionnaire since 2025)

Apple's current questionnaire has five ratings (4+, 9+, 13+, 16+, 18+) and
asks about in-app controls, capabilities, mature themes, medical or wellness
content, sexuality, violence and chance. It has no question about AI as such;
the AI chat is answered under the questions it actually touches (Messaging and
Chat, Medical or Treatment Information, Health or Wellness). Definitions are
quoted from Apple's
[age ratings values and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions).

| Question | Answer | Why |
|---|---|---|
| Parental Controls | No | None in the app. |
| Age Assurance | No | Forge does not check age. |
| Unrestricted Web Access | No | No web view; Support, Privacy and Terms open in Safari. |
| User-Generated Content | No | Apple: "the broad distribution of content created by users". Nothing a person writes reaches anybody else; a Proof Card goes only where they send it. |
| Social Media | No | |
| Messaging and Chat | No | Apple: "users can directly communicate with one another". Ask Forge is a person and a model, not people with each other. |
| Advertising | No | |
| Profanity or Crude Humor | None | |
| Horror/Fear Themes | None | |
| Alcohol, Tobacco, or Drug Use or References | None | Ask Forge declines drugs and PEDs. |
| Medical or Treatment Information | **Infrequent** | Forge diagnoses and treats nothing and Ask Forge declines to, but a message suggesting a crisis is answered with the 988 Suicide & Crisis Lifeline, which is emergency guidance, and Ask Forge talks about sleep and training. The conservative answer; *None* is arguable and changes nothing below. |
| Health or Wellness Topics | **Yes** | Apple: "self-care or lifestyle recommendations … exercise recommendations". Arcs ask for training, steps, sleep and early mornings; Apple Health ticks off steps, workouts, sleep and mindful minutes. |
| Mature or Suggestive Themes | None | |
| Sexual Content or Nudity | None | Ask Forge declines sexual content. |
| Graphic Sexual Content and Nudity | None | |
| Cartoon or Fantasy Violence | None | The pull draws a sword from a stone; nothing is harmed. |
| Realistic Violence | None | |
| Prolonged Graphic or Sadistic Realistic Violence | None | |
| Guns or Other Weapons | **Frequent** | Apple: "depictions of guns, weapons, or objects that may cause bodily harm. May include: guns, swords, or knives." The sword is on the Forge tab every day, on the Blade tab, the paywall and every share card. |
| Gambling | No | |
| Simulated Gambling | None | |
| Contests | None | Apple: users who "compete with one another". Arcs and trials are a person against their own plan. |
| Loot Boxes | No | |

**Result: 13+**, from *Frequent* weapons (and *Infrequent* medical, if kept).
*Infrequent* weapons would give 9+, and is not honest for an app whose main
screen is a sword. 13+ costs nothing with an audience of 18 to 30, matches the
privacy policy's "not directed at children under 13", and keeps the AI chat off
the youngest ratings. Do not set "Made for Kids". No age-range override is
needed.

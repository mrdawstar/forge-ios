<!--
EDITOR'S NOTES — do not publish this comment.

Published at: https://forgebetter.app/privacy

Two things must be filled in before publishing:
  1. [EFFECTIVE DATE]    — the date you publish this version.
  2. [CONTACT EMAIL]     — a monitored address for privacy questions.
  (Optional) [DEVELOPER NAME] — the legal name shown on the App Store listing.

Section 7 has two versions:
  - 7A "Current version" — publish NOW, while RemoteForgeAI.isModelEnabled is false.
  - 7B "When AI features are active" — publish ON THE DAY the activation build
    goes live, replacing 7A, and update the effective date. Also switch the
    App Store privacy labels (docs/APP_STORE.md §1) at the same time.
Section 8's table has one row marked "(when AI is active)" — keep it hidden or
labelled until then; it is already worded correctly for both states.

Nothing else needs to change at activation.
-->

# Forge Privacy Policy

**Effective date:** [EFFECTIVE DATE]

This policy explains what the Forge iOS app ("Forge", "we", "us") does with
information about you. Forge is made by [DEVELOPER NAME]. If anything here is
unclear, contact us at [CONTACT EMAIL].

## The short version

- Your Forge record — your activities, the days you kept, and what you write —
  is stored on your iPhone. We do not have a copy.
- There is no account and no sign-in.
- If you leave it on, Forge sends **anonymous** usage counts to TelemetryDeck,
  so we can see which features are used. It never includes your activities or
  anything you write. You can turn it off in Settings.
- Purchases are handled by Apple. We never see your payment details.
- Forge has no advertising, does not track you across apps or websites, and
  does not sell your information.
- Forge's AI features are optional, require your explicit permission, and are
  described in section 7.

## 1. Your Forge record

Everything you put into Forge — the activities you keep and their schedules,
the days you completed and earned, rest days, chapters and their names and
intentions, weekly review answers, the statements you wrote about who you are
becoming, milestones you set, and your settings — is stored **on your device**,
in storage shared only between the Forge app and its own widgets.

We do not operate a server that stores your record, and there is no way to
upload it to one. Your record is included in your device's own backups (for
example iCloud Backup, if you use it) under your Apple Account's settings, as
with any app's data. Deleting Forge deletes the record on that device.

Your record leaves the device only in the specific cases this policy describes:
an image you choose to save or share (section 5), and — only if you allow it,
when available — the content an AI feature needs (section 7).

## 2. Accounts

Forge has **no user account and no login**. There is no sign-up, no email or
password, and no profile.

The only exception is technical and invisible: to authorise requests to Forge's
AI features (section 7), Forge may create an **anonymous session** with our
backend. It has no name, email or password attached to it, you never see it,
and it is created only when you use an AI feature after allowing it. It is not
created when you open the app, open Settings, or use any other feature.

## 3. Apple Health

If you allow it, Forge **reads** steps, distance and workouts from Apple Health
to mark activities your phone can measure as done. Forge never writes to Apple
Health, does not store the readings, and does not send health data anywhere —
not to analytics, not to our backend, and not to any AI provider. Health access
is optional; every feature works without it.

## 4. Notifications, widgets and the Live Activity

Reminders are scheduled on your device. Widgets and the Live Activity read the
same on-device record. None of these involve a server; the Live Activity is not
updated by push.

## 5. Images you save or share

When a blade is earned or a chapter closes, you can choose to create an image
(the "Proof Card") showing the sword, the number of days you kept, the date and
our web address. It is created on your device and goes only where you send it
using Apple's share sheet. Forge does not upload it and does not prompt you to
share at any other time.

## 6. Anonymous usage analytics (TelemetryDeck)

Forge uses **TelemetryDeck**, a privacy-focused analytics service, to count how
the app is used — for example that a day was earned, that a weekly review was
completed, that an activity was added and from which screen, or that the Forge
Pro screen was opened and from where.

**What is sent:** the name of the event, a small set of fixed values chosen by
the app (for example which screen, which plan, or how many days since install),
and technical information the TelemetryDeck software adds to every event, such
as device model, operating-system and app version, language, region, time zone
and display and accessibility settings. Events are associated with an
**anonymised identifier** that is hashed on your device and again by
TelemetryDeck, and cannot be used by us to identify you.

**What is never sent:** activity names, anything you type (review answers,
chapter names, identity statements, requests to Plan), health data, your
location, your contacts, or your Apple Account details.

**What it is used for:** understanding which parts of Forge are used and where
people get stuck — product analytics only. It is not used for advertising and
is not used to track you across apps or websites.

**Your choice:** anonymous usage sharing is on by default and can be turned off
at any time in **Settings → Privacy → Share anonymous usage**. When it is off,
Forge sends no analytics events.

## 7. AI features

Forge Pro includes optional AI features: the **Weekly Reading** and **Plan in
your own words**.

### 7A. Current version

<!-- Publish this subsection now. Replace it with 7B on the day AI is activated. -->

In the current version of Forge, these features do **not** use any remote AI
service. Plan in your own words and all of Forge's suggestions are worked out on
your device from your own record, and nothing is sent to our backend or to any
AI provider for them.

Forge already contains the permission screen and the protections described in
7B, so that when remote AI is switched on in a future version you will be asked
first, before anything is sent. We will update this policy before that happens.

### 7B. When AI features are active

<!-- Publish this subsection, in place of 7A, on the day the activation build goes live. -->

**How it works.** When you use an AI feature, the request goes from the Forge
app to **Forge's own backend** (hosted on Supabase), which asks **OpenAI** to
write the answer and returns it to the app. The Forge app never contacts OpenAI
directly and does **not** contain an OpenAI API key; the key exists only on our
backend.

**Your permission comes first.** Before the first AI request, Forge shows you
exactly what would be sent, where it goes and who processes it, with two
choices: **Allow** and **Not now**. If you choose *Not now*, nothing is sent and
Forge keeps working on your device as before. You can withdraw permission at
any time in **Settings → Planning**; from then on, no further requests are made.
AI features are available only with Forge Pro, and a request is only made when
you press a button that asks for one.

**What is sent — only what the feature needs:**

- your activities' names, times, lengths and days;
- counts of the days you kept;
- what you wrote about who you are becoming, and your current chapter's
  intention;
- for a **Weekly Reading**: that week's counts, per day, per activity and per
  identity statement;
- for **Plan in your own words**: the request you typed.

Weekly review answers, dates of individual days, health data, your name, email,
location and contacts are **not** sent.

**How the request is authorised.** Each request carries the anonymous session
described in section 2 and Apple's signed proof of your Forge Pro purchase (the
StoreKit transaction), which our backend verifies. It does not include your
name, email or payment details.

**What we keep.** Our backend does not store the content you send or the answer
it returns. It keeps a count of AI requests per day for each anonymous session
and each purchase, to limit use, and minimal technical logs (for example which
feature was requested and whether it succeeded). Our hosting provider may keep
standard request logs, such as IP addresses and timestamps, under its own terms.

**OpenAI.** OpenAI processes the request to produce the answer. We ask OpenAI
not to store the response for later retrieval. Under OpenAI's API data policies
at the time of writing, data sent through its API is not used to train its
models by default; OpenAI may retain API data for a limited period for abuse
and misuse monitoring. See openai.com/policies for OpenAI's current terms.

**What it is used for.** Only to provide the feature you asked for (App
Functionality). AI data is **not** used for advertising, is **not** used to
track you, is **not** sold, and is **not** combined with data from other
companies. Every sentence an AI model writes is checked against your own record
before it is shown, and is labelled on screen as written by a model.

## 8. Service providers

We use the following providers to run Forge. Each processes information only as
described in this policy and under its own terms.

| Provider | What for | What it receives |
|---|---|---|
| **Apple** | App Store, purchases and subscriptions, Apple Health, notifications | As described by Apple's own privacy policy |
| **TelemetryDeck** | Anonymous usage analytics (section 6) | Anonymous events, only if usage sharing is on |
| **Supabase** (when AI is active) | Hosting Forge's backend for AI features (section 7) | The anonymous session, proof of purchase, and the content of an AI request you allowed |
| **OpenAI** (when AI is active) | Writing the answer to an AI request (section 7) | The content of an AI request you allowed, sent by our backend |

We do not use any advertising, attribution or data-broker services.

## 9. Purchases (Forge Pro)

Forge Pro is sold through the App Store as a monthly or annual subscription
(the annual plan includes a free trial for eligible accounts) or a one-time
lifetime purchase. **Apple processes all payments.** We never receive your card
number, billing address or Apple Account password.

To know whether you have Forge Pro, the app reads your entitlement from Apple's
StoreKit on your device. When AI features are active, Forge sends Apple's signed
transaction record for your purchase to our backend so it can verify Forge Pro
access (section 7). You can manage or cancel subscriptions in your Apple Account
settings, and restore purchases in **Settings → Forge Pro**.

## 10. No advertising, no tracking, no selling

Forge shows no ads. Forge does not track you across other companies' apps or
websites, does not use the advertising identifier, and does not sell or share
your personal information for advertising.

## 11. How long information is kept

- **Your Forge record:** on your device until you delete it or delete the app.
- **Anonymous analytics:** kept by TelemetryDeck under its retention settings;
  it cannot be linked back to you by us.
- **When AI is active:** the anonymous session is kept on your device and in our
  backend's authentication system; usage counts are kept per day to enforce
  limits. The content of AI requests is not stored by our backend.

## 12. Your choices and rights

- Turn off anonymous usage sharing in **Settings → Privacy**.
- Decline or withdraw permission for AI features in **Settings → Planning**.
- Turn off Apple Health access in the iOS Settings app.
- Delete your Forge record by deleting the app.

Depending on where you live, you may have rights to access, correct or delete
personal information, or to object to its processing. Because Forge keeps your
record on your device and uses no account, most of it is already under your
direct control. For anything else, contact us at [CONTACT EMAIL] and we will
respond as required by applicable law.

## 13. Children

Forge is not directed at children under 13, and we do not knowingly collect
personal information from children.

## 14. Security

We design Forge to keep information on your device wherever possible and to
send as little as a feature needs. Connections to our service providers are
encrypted. No method of storage or transmission is completely secure, and we
cannot guarantee absolute security.

## 15. International processing

Our service providers may process information in countries other than yours,
including the United States, under their own safeguards.

## 16. Changes to this policy

If we change this policy — for example when AI features become active — we will
update the effective date above and publish the new version at
forgebetter.app/privacy before the change takes effect in the app.

## 17. Contact

Questions about this policy or your information:

- Email: [CONTACT EMAIL]
- Support: https://forgebetter.app/support

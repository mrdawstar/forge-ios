<!--
EDITOR'S NOTES — do not publish this comment.

Published at: https://forgebetter.app/privacy

This file is the 1.1 version of the policy, written on 2026-10-04 (session S7,
FORGE_CONTEXT §17.7) against the live page, which reads "LAST UPDATED 27
SEPTEMBER 2026" and describes 1.0.1. The live page is the owner's own text and
has its own structure (eleven sections, the developer's name, the website,
Vercel, UODO), so this file does not replace it wholesale: it says, section by
section, what changes, and gives the exact text to paste.

WHEN: on the day 1.1 goes live, and not before. The live 1.0.1 makes no AI
request and sells nothing; a policy describing either would be as wrong as one
omitting them. Switch the App Store privacy labels at the same time
(docs/APP_STORE.md §1, docs/launch/appstore-1.1.md §7).

WHAT TO DO, in the order the live page has its sections:

  Date line .......................... "LAST UPDATED <the day 1.1 goes live>"
  The short version .................. REPLACE with section 1 below
  Who is responsible ................. unchanged
  Your practice stays on your device . REPLACE with section 2 below
  Anonymous Usage Analytics .......... REPLACE its first three paragraphs with
                                       section 3 below; "Information attached
                                       to analytics" and "Your choice" unchanged
  Apple Health ....................... REPLACE with section 4 below
  The App Store and purchases ........ REPLACE, heading included, with
                                       section 5 below ("Forge Pro and the App
                                       Store")
  Planning and personal content ...... REPLACE with section 6 below
  (new) .............................. INSERT section 7 below, "AI features
                                       (Forge Pro)", straight after section 6
  Deleting data and retention ........ REPLACE with section 8 below
  This website and support ........... unchanged
  Your rights ........................ unchanged
  Children and changes ............... unchanged

Three facts a sentence below depends on, and how to keep them true:
  - The anonymous AI counts are kept "to enforce the daily limits" and
    nothing more is promised: public.prune_ai_usage() deletes counts older
    than 14 days, but nothing schedules it yet (supabase/migrations/0007). If a
    daily cron job is added, the sentence can say "Counts older than 14 days
    are deleted."
  - The Supabase region of the AI project is not named, because this session
    could not see it. Supabase → Project Settings → General → Region; if it is
    the EU project the website section already names, say so in section 7.
  - OpenAI's API terms are described as they stood on 2026-10-04 (no training
    on API data by default; retention for abuse monitoring). Re-read
    openai.com/policies before publishing.
-->

# Forge Privacy Policy — the 1.1 changes

## 1. The short version

Forge has no accounts or cloud sync. Your activities, notes and personal
record stay on your device. The app uses TelemetryDeck for anonymous usage
analytics to help improve Forge; analytics are on by default and can be turned
off at any time. Forge Pro is sold through the App Store, and Apple handles
every payment. Forge's optional AI features send what they need to our server
and to OpenAI only after you allow them, and only when you ask. Apple Health
readings never leave your iPhone. There are no ads or cross-app tracking.

## 2. Your practice stays on your device

No account is required, and no account can be created. Your activities,
schedules, completion history, your answers to the seven starting questions,
Arcs, blades, milestones, chapters, review answers, your Ask Forge conversation
and your settings are stored locally on your iPhone. Forge's widgets and Live
Activity share that local storage to show your day, and reminders, including
the reminder before a free trial ends, are scheduled on the device.

Forge does not sync this content between devices or keep a copy of it on a
server. The only content that leaves your iPhone is what an AI feature sends
after you allow it (see "AI features"), and a backup file you choose to export.

**Backup files.** Settings → Your Data → Export Backup creates one file with
your record, your week, your Arcs, your words (including review answers and the
Ask Forge conversation) and your settings. It is made on your iPhone and goes
only where you save or send it; Forge does not receive a copy. Anyone who has
the file can read it, so keep it somewhere private. Import Backup replaces what
is on your iPhone with a backup file, after asking you. Permissions, Forge Pro
and your privacy choices are never in the file and are never changed by one.

If you use iCloud or computer backups, your device backup may include Forge's
local data under your Apple backup settings. Forge cannot access those
backups.

## 3. Anonymous Usage Analytics — the first three paragraphs

Forge uses TelemetryDeck to collect anonymous usage analytics so we can
understand how the app is used and improve its features.

This includes events such as the first app opening, each onboarding step,
answering the starting questions, adding or completing an activity, earning a
day, completing or abandoning a sword pull, accepting or completing a
challenge, opening a notification, completing a weekly review, returning to
the app's practice after a break, closing a chapter, seeing the Forge Pro
screen, starting a free trial or a purchase, tapping Restore Purchases, being
recognised as an earlier user, and a Weekly Reading being replaced by the
phone's own sentence.

Events contain a limited set of predefined values or counts, such as which
onboarding step or feature was used, the way an activity was marked complete,
the number of focus areas selected, which screen opened Forge Pro, which plan
was chosen (annual, annual offer, monthly or lifetime), and days since
installation as estimated from the local activity record.

We do not send activity names, notes, identity statements, chapter names,
review answers, your answers to the starting questions, other user-generated
text, chosen schedule times, Apple Health readings, prices, receipts,
transaction IDs, or anything you ask Forge's AI or it answers to TelemetryDeck.

## 4. Apple Health

Apple Health is optional. With your permission, Forge reads steps, workouts
(their minutes), sleep (time asleep) and mindful minutes to complete
activities your phone can measure. Access is read-only: Forge does not write
to Health. Forge asks the first time an activity Health can check enters your
day, and never when the app opens.

Health readings are processed on your iPhone the moment they arrive and are
not stored by Forge: Forge records that an activity was completed, not the
reading behind it. Readings are never sent to TelemetryDeck, to our server or
to an AI service; if you use Ask Forge, it is told which of today's activities
are done, never a reading. With your permission, iOS can wake Forge in the
background when new Health data arrives, so an activity can complete itself.
You can withdraw Health access in iOS Settings or in the Health app.

## 5. Forge Pro and the App Store

Forge Pro is sold through the App Store: an annual subscription with a free
trial for eligible accounts, a monthly subscription, and a one-time Lifetime
purchase. Apple processes every payment; Forge does not receive your card
details, billing address or Apple Account password. The app learns whether you
have Forge Pro from Apple's StoreKit on your iPhone. Apple's StoreKit may
communicate with Apple to load product information or check purchases; Apple
handles that exchange under Apple's privacy policy.

**Free trial reminder.** If you start a free trial and leave "Remind me before
the trial ends" on, Forge schedules a notification on your iPhone for two days
before the trial ends, at the start of your day. It is created on the device,
needs your permission for notifications, and sends nothing anywhere.

**Earlier users.** To recognise an install that used Forge 1.0 or 1.0.1,
Forge checks on your iPhone whether a record from an earlier version is there,
or reads Apple's record of the version you first downloaded. This happens on
the device.

**Analytics.** If anonymous usage sharing is on, Forge sends anonymous events
when the Forge Pro screen is shown (and which screen opened it), when the
one-time offer is shown or accepted, when a free trial or a purchase starts
(with the plan), when Restore Purchases is tapped, and when an earlier user is
recognised. They never include a price, receipt, transaction ID or Apple
Account details.

**AI requests.** When you use an AI feature, Forge sends Apple's signed record
of your Forge Pro purchase to our server, which checks it to confirm access
(see "AI features").

## 6. Planning and personal content

Planning suggestions, challenges and weekly review observations are worked
out on your device. Your practice is not published in a feed or shared with
other users. Forge's AI features, below, are the only exception, and only
after you allow them.

## 7. AI features (Forge Pro)

Forge Pro includes three optional AI features: **Ask Forge**, a coach that
reads your record and answers questions about it; the **Weekly Reading**; and
**Plan in your own words**. They need Forge Pro, including for earlier users.

**How it works.** When you use one, the request goes from the Forge app to
Forge's own server, hosted by Supabase, which asks OpenAI to write the answer
and returns it to the app. The app never contacts OpenAI directly and contains
no OpenAI key.

**Your permission comes first.** Before the first AI request, Forge shows you
exactly what would be sent, where it goes and who processes it, with two
choices: **Allow** and **Not now**. With *Not now*, nothing is sent and every
feature keeps working on your device. You can withdraw permission at any time
in **Settings → Planning**; no request is made after that. A request is only
ever made when you press a button that asks for one.

**What is sent, and only what the feature needs:**

- your activities' names, times, lengths and days;
- counts of the days you kept;
- what you wrote about who you are becoming, and your current chapter's
  intention;
- for a **Weekly Reading**: that week's counts, per day, per activity and per
  identity statement;
- for **Plan in your own words**: the request you typed;
- for **Ask Forge**: what you write, with the conversation before it (at most
  the last eight messages, yours and its replies); your six stats and overall
  score as Forge shows them; which Arc you are running, its day and its phase;
  and today's activities, with which are done.

Weekly review answers, dates, the record of any past day, Health readings,
your name, email, location and contacts are **not** sent.

**Your Ask Forge conversation stays on your iPhone.** Forge keeps the last 40
messages so you can read them back; **Clear** in Ask Forge deletes them. Our
server does not keep them.

**What Ask Forge will not do.** It does not give medical, psychiatric or
nutritional diagnosis or treatment, advice about drugs, performance-enhancing
substances or supplement doses, extreme diets or fasting protocols, sexual
content, or help with harassing anyone. A message that suggests you may be in
crisis is answered on your iPhone with the 988 Suicide & Crisis Lifeline, and
that message is not sent. Ask Forge is not medical advice.

**Reporting a reply.** A long press on an Ask Forge reply offers *Report*,
which opens an email to our support address with that reply in it. Nothing is
sent unless you send the email yourself.

**How a request is authorised.** Each request carries an anonymous identifier,
created the first time you use an AI feature after allowing it, and Apple's
signed record of your Forge Pro purchase, which our server verifies. The
identifier has no name, email or password; you never see it. It is not created
when you open the app or use any other feature.

**What we keep.** Our server does not store what you send or the answer it
returns. It keeps a count of AI requests per day for each anonymous identifier
and each purchase, to enforce the daily limits, and minimal technical logs,
such as which feature was asked for and whether it succeeded. Our hosting
provider may keep standard request logs, such as IP addresses and times, under
its own terms.

**OpenAI.** OpenAI, in the United States, processes each request to write the
answer. We ask OpenAI not to store the response. Under OpenAI's API terms,
data sent through its API is not used to train its models by default, and
OpenAI may keep it for a limited period to monitor abuse. See
openai.com/policies.

**What it is used for.** Only to provide the feature you asked for. AI data is
not used for advertising, is not used to track you, is not sold, and is not
combined with data from other companies. Every reply, reading and plan written
by AI is labelled as written by AI; a Weekly Reading is checked against your
own record before it is shown, and a proposed change to your week is applied
only after you review it and confirm it.

## 8. Deleting data and retention

Deleting Forge removes its locally stored app data, including the Ask Forge
conversation. There is no Forge account or cloud copy of your record to
delete. Device backups are managed through your Apple settings, and a backup
file you exported is yours to keep or delete.

If you used an AI feature, its anonymous identifier exists in our server's
sign-in system and in your iPhone's keychain, which iOS may keep after the app
is deleted. It carries no name, email or Apple Account, so it cannot be linked
to you. The daily request counts hold no content and are kept only to enforce
the limits.

Anonymous analytics already received are separate from your local record and
are not removed by uninstalling the app. Forge does not hold an account or
identity mapping that would let us reliably find an individual's anonymous
events. Contact us with questions about analytics retention or a data request.

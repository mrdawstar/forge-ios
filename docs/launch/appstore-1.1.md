# Forge 1.1 — App Store listing

Everything in this file is written against what the app actually does on the
`feat/first-week` branch. It is not the submission checklist — that is
`docs/APP_STORE.md` (privacy labels §1, review notes §6, subscription setup §7).

> ⚠️ **One decision before submitting 1.1: is remote AI on?**
>
> The Pro **Weekly Reading** is a model-written reading. It only exists once
> remote AI is activated (`RemoteForgeAI.isModelEnabled`, currently `false` —
> `FORGE_CONTEXT.md` §2r). Until then Pro adds no Weekly Reading beyond the
> free observation everybody gets.
>
> - **Recommended:** activate AI first, then submit 1.1 with **Variant B**
>   below.
> - **If 1.1 must ship before activation:** use **Variant A**, *and* change the
>   in-app paywall line (`ProFeature.weeklyReading` in `Forge/Models/Premium.swift`)
>   in a separate code PR first. Selling a feature the build cannot deliver is
>   an App Review rejection and a broken promise to paying users.
>
> Plan in your own words and the eight accents work today, on the device, with
> AI off.

---

## Name and subtitle

| Field | Value | Length |
|---|---|---|
| App Name | `Forge: Daily Discipline` | 23 / 30 |
| Subtitle | `Earn the day. Keep the proof.` | 29 / 30 |

## Keywords

```
habit,routine,ritual,practice,morning,self improvement,goals,focus,planner,reflection,consistency
```

**97 / 100 characters.** No spaces after commas. Deliberately left out because
the name and subtitle already index them: *forge, daily, discipline, earn, day,
keep, proof*. Also left out on purpose: *streak* (Forge does not use
loss-aversion language), *tracker*, and anything medical or wellness-outcome
flavoured.

## Promotional text (≤ 170)

```
When the day's list is done, the blade comes loose. You still have to pull it free. Forge keeps the record of the days you earned, and reads it back to you.
```

(156 characters. Promotional text can be changed without a new build — swap it
at AI activation if you want to lead with the Weekly Reading.)

---

## Description

Use **Variant A** or **Variant B** for the `FORGE PRO` block, per the decision
above. Everything else is shared.

```
Forge is for keeping a daily practice.

You keep a short list of the things a day asks of you. When you have done all of them, a sword in a stone comes loose — and you still have to press the grip and drag it out. That pull banks the day.

WHAT IT IS NOT

There is no score to chase and nothing congratulates you. Forge does not guilt you for a missed day, and days you have already kept are never taken away or hidden. Rest days are yours to set, and they are not counted as misses.

THE RECORD

Every day you earn stays on the record: a heatmap of the months behind you, trends, and seven blades earned along the way, from Rough to Proven. Chapters close every six weeks with your weeks side by side and your own words read back.

SIX PARTS OF A PERSON

Physical, Intellect, Discipline, Mental, Relationship, Ambition. Every activity belongs to one of them, so Forge can draw the shape of the last four weeks — which parts of you are getting stronger, and which are getting nothing. In your first week it tells you when the shape will draw itself, and how many days you have kept so far. Where a part has nothing in it yet, Forge offers the smallest activity that would start it. Nothing is added unless you add it.

PLAN

One tap, and Forge reads your own week back to you: two things booked at the same time, activities with no hour on them, the part of you getting the least. Every suggestion states the arithmetic behind it, and nothing changes until you say so.

ONE EVENING A WEEK

Ninety seconds. Your week, one observation drawn from your own record, and two questions in your own words. Skippable, and skipping costs nothing.

THE PROOF

When a blade is earned or a chapter closes, you can save a quiet image of it — the sword in the stone, the days you kept, and the date — in portrait or square. Forge never asks you to share anywhere else.

ON YOUR PHONE

Your record stays on your phone. There is no account to create and no sign-in. No ads. Home Screen and Lock Screen widgets, and a Live Activity for the day. Forge can read steps, distance and workouts from Apple Health to tick off what your phone can already measure; it never writes to Health, and it is optional.

FREE — AND YOUR RECORD ALWAYS WILL BE

The whole daily loop. Any number of activities. Your complete history, the shape, the heatmap, the trends, the blades, rest days, widgets, a challenge every day, chapters, the weekly review and Plan's suggestions. Forge Pro never locks anything you have already done.

[FORGE PRO — paste Variant A or Variant B here]

Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy Policy: https://forgebetter.app/privacy
```

### Variant A — AI not yet active

```
FORGE PRO

Forge is free. Pro adds:
- Plan in your own words: tell Plan the hours you cannot move and what you want fitted around them, and it lays out the week on your phone.
- Eight accents to dress the app in. Forge blue stays free.

Monthly, annual with a 7-day free trial, or once for life. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel them in your Apple Account settings.
```

### Variant B — after AI activation

```
FORGE PRO

Forge is free. Pro reads your record back to you:
- Weekly Reading: a written reading of what held and what slipped, checked against your own record before you see it. Written by an AI model through Forge's own server, only after you allow it.
- Plan in your own words: tell Plan the hours you cannot move and what you want fitted around them.
- Eight accents to dress the app in. Forge blue stays free.

Monthly, annual with a 7-day free trial, or once for life. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel them in your Apple Account settings.
```

Notes on claims kept out on purpose: no cloud sync, no account, no friends or
groups, no health or therapy outcomes, no promise that anybody will change.
Prices are not written into the description — the App Store shows them, per
storefront.

---

## What's New in 1.1

```
Forge Pro
Forge is free. Pro is optional: Plan in your own words and eight accents, as Monthly, Annual with a 7-day free trial, or Lifetime. Your record stays free. Restore Purchases and Manage Subscription are at the top of Settings.

Your first week on Becoming
Until your shape can be drawn, Becoming tells you when it will draw itself and how many days you have kept so far. Parts of you with nothing in them yet offer the smallest activity that would start them.

Save the proof
When a blade is earned or a chapter closes, you can save an image of it, in portrait or square.
```

At AI activation, add one line under Forge Pro: *"Weekly Reading: a written
reading of your week, checked against your own record. Only after you allow
it."*

---

## Screenshots — five headline concepts

Ordered by what a stranger needs to understand first. Headline on the image,
one short support line under it. No exclamation marks.

| # | Screen | Headline | Support line |
|---|---|---|---|
| 1 | Forge tab, blade loose, finger on the grip mid-pull | **Earn the day.** | Finish the list. Then pull the blade free. |
| 2 | Blade tab: heatmap and blade | **The record stays.** | Every day you earned, never taken away. |
| 3 | Becoming: the shape (or, for a first-week account, the first-week card) | **Six parts of you.** | Drawn from what you actually keep. |
| 4 | See below | — | — |
| 5 | Settings or a calm Forge tab, with a plain-text overlay | **No ads. No account.** | Your record stays on your phone. |

**Screenshot 4 depends on the AI decision:**

- **Variant A (AI off):** the weekly review with the free observation —
  headline **"Your week, read back."**, support *"One observation from your own
  record, and two questions."* Do not show a Weekly Reading that the build
  cannot produce.
- **Variant B (AI on):** the weekly review with a real, validated Weekly Reading
  under the observation — headline **"Your week, in writing."**, support
  *"Forge Pro. Checked against your own record."* Capture it from a real
  Sandbox purchase with consent given; do not mock the text.

**Alternative for slot 4 or 5:** the Proof Card (1080 × 1920) — headline
**"Keep the proof."**, support *"A blade earned, saved as an image."* It echoes
the subtitle and needs no AI.

Screenshots of Forge Pro must show prices only as the App Store renders them
(`Product.displayPrice`), never typed onto the image.

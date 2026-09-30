# Forge 1.1 — Direction

Decided by the owner on 2026-09-29. Where this file disagrees with docs/FORGE_CONTEXT.md (§5, §6, §8, §2g, §2h or anything older), this file wins. FORGE_CONTEXT §2t records the change; every session that builds part of it adds a dated subsection to FORGE_CONTEXT §17.

## Who Forge is for

Men 18–30 in the US who want to become disciplined, stronger and more capable, and who respond to games, ranks and visible numbers. Copy, examples, art and Arcs are written for that person. The UI never says "for men"; it is simply built for them.

## The promise

Keep concrete daily actions. Your six stats move with what you actually do. Every day you keep, you pull the sword. Honest numbers, real science, nothing invented.

## 1. Money: a hard paywall with a free week

- New installs finish onboarding and meet the paywall. There is no free tier for new installs.
- Plans (US prices; the App Store sets the rest):
  - Annual — `com.dawid.forge.premium.annual` — $49.99 a year — 7-day free trial — the default, preselected.
  - Monthly — `com.dawid.forge.premium.monthly` — $12.99 a month — no trial.
  - Annual offer — `com.dawid.forge.premium.annual.offer` — $29.99 a year, renewing at $29.99 — 7-day free trial — shown once, when somebody declines the paywall.
  - Lifetime — `com.dawid.forge.premium.lifetime` — $129.99 — never on the onboarding paywall; sold only in Settings → Forge Pro.
- Trial honesty: the paywall shows the timeline (today everything unlocked, day 5 a reminder, day 7 the charge unless cancelled), and Forge schedules a local reminder two days before the trial ends when notifications are allowed.
- Founders: every install that ran 1.0 or 1.0.1 keeps the whole app free forever, except the AI features, which need a subscription. Detected on the device, never asked for, never in Sandbox.
- Lapsed or never subscribed: the record stays readable forever (Blade, Becoming, history, blades, reviews, Proof Card, widgets). Keeping new days, Arcs, the daily challenge and AI need Forge Pro. Nothing is ever deleted or hidden.
- §5 #1 is amended, not dropped: nothing that has already happened is sold back. The ongoing practice is what is sold.
- The three doors (§5 #8) are retired.
- A paywall row only names a feature that exists in the build.
- Never: countdown timers, fake scarcity, invented member counts, invented statistics, fake discounts, or a rating prompt before somebody has used the app.

## 2. Onboarding shows the transformation (replaces the §2g/§2h first run)

Seven one-tap questions → starting stats → Now / In 7 days / In 30 days / Full potential, each with the blade that stage earns → three cited findings → your plan, with an Arc → pull to begin → paywall → do one now → the first pull. About two minutes.

- Starting stats come from the answers (stated data) and blend into the record-derived Shape (derived on read). §5 #2 holds.
- Projections run the same arithmetic on the proposed plan, with the assumption printed on screen. They are projections, never promises (§5 #4 holds).

## 3. Numbers

Scores, the six stats, OVR, prices, dates, times and Arc day counters are digits. Prose still spells counts up to one hundred ("three days kept"). §8's "numbers as words" is narrowed to prose.

## 4. The six have colours

Physical = Ember, Discipline = Forge blue, Mental = Tide, Intellect = Gold, Relationship = Rose, Ambition = Violet — the existing accent palette. Used on the hexagon, stat tiles, dimension glyphs and challenge cards. The app accent still means "your action".

## 5. Arcs

Programs with a start and an end: Lock In 7 (the starter), Monk Mode 30, Discipline 66, Winter Arc 90 (seasonal, promoted Oct 1 – Jan 31). An Arc appends activities after showing what it adds (§5 #7 and #9 hold), ramps them by phase through reviewable changes, sets a weekly trial, and leaves a permanent mark on the record when finished. One active Arc at a time.

## 6. Progression has no cap

The ladder gains Honed (90 days kept) and Enduring (180). After Enduring, every further 90 days kept adds a temper mark. Still one progression against one number (§5 #5 holds). Existing rung ids and requirements never change.

## 7. The daily challenge counts

A completed challenge counts as a kept day for its dimension in the Shape.

## 8. Proof over promises: Apple Health

Measurable activities — steps, workout minutes, sleep, mindful minutes — tick themselves off from Apple Health: read-only, on the device, nothing leaves the phone. Asked in context the first time such an activity enters the day, never at launch or during onboarding.

## 9. AI (Forge Pro)

Ask Forge — a coach that reads your record and can propose reviewable plan changes; Weekly Reading; Plan in your own words. OpenAI behind the Forge backend, an invisible anonymous identity, StoreKit JWS, as built in §2q/§2r. No persona, no name, no avatar (§5 #6 holds).

## 10. Rating prompt

Once, when the first blade celebration closes. At most once more, when Folded (day 7) is earned, if the first did not show. Never in onboarding, never over a day in progress.

## 11. Community

Not in 1.1: moderation load, App Store rules for user-generated content, and an empty room costs more than no room. Revisit as private Squads after 1,000 paying users.

## What does not change

The sword scene and the pull. Derived-state honesty (§5 #2). Rest days are not misses (§5 #11). Suggestions append (§5 #7). Nothing writes to the schedule unread (§5 #9). Never claim a model wrote something it didn't (§5 #10). The app never plays a character (§5 #6): the blade transforms, not a person. Voice: plain, adult, direct; no exclamation marks, no congratulations, never loss-aversion. No visible account.

## Science Forge may cite (and nothing else)

1. Lally, van Jaarsveld, Potts & Wardle (2010), *European Journal of Social Psychology* 40(6), 998–1009. New daily behaviours took a median of 66 days to become automatic (range 18–254); missing one opportunity did not materially affect the process.
2. Gollwitzer & Sheeran (2006), *Advances in Experimental Social Psychology* 38, 69–119. Across 94 studies, if-then plans (deciding when and where you will act) had a medium-to-large effect on reaching goals (d = 0.65).
3. Harkin et al. (2016), *Psychological Bulletin* 142(2), 198–229. Across 138 studies, monitoring progress improved goal attainment, more so when progress was physically recorded or made public.
4. Dai, Milkman & Riis (2014), *Management Science* 60(10), 2563–2582. Temporal landmarks (a new week, month or season) increase aspirational behaviour: the fresh start effect.

Paraphrase, cite in small type, never overstate, no logos, no percentages that are not in these papers.

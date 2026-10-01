# Forge

iOS app (SwiftUI, iOS 26, iPhone only; app target in Swift 5 language mode). A daily practice:
activities -> the day is "earned" by pulling a sword out of a stone. US market, English UI.

**Before any product change read docs/DIRECTION_1_1.md. Where it disagrees with
docs/FORGE_CONTEXT.md, DIRECTION_1_1.md wins.**

## Read first, and only what you need
- docs/DIRECTION_1_1.md: the 1.1 direction (money, onboarding, numbers, Arcs, Health, AI).
- docs/FORGE_CONTEXT.md is large. Do NOT read it whole. Use `grep -n '^#' docs/FORGE_CONTEXT.md`
  and read only the sections your task names. Always relevant: §2t (the 1.1 direction),
  §17 (Release 1.1), §2n (no account), §5 (principles), §7 (AI seam).
- docs/APP_STORE.md: privacy labels (§1), description, review notes.
- docs/launch/: App Store 1.1 listing, privacy policy, videos, creator outreach.

## Layout
```
Forge/            app (Engine/, Models/, ViewModels/, Views/, Backend/, Shared/, Theme/)
ForgeWidgets/     widgets + Live Activity
ForgeTests/       Swift Testing (@Suite/@Test)
supabase/         functions/forge-ai (edge function), migrations/0001-0008
docs/             FORGE_CONTEXT.md, DIRECTION_1_1.md, APP_STORE.md, launch/
```

## Environment rules
- Cloud sessions run on Linux: do NOT try to build, install Xcode/Swift toolchains, or run iOS
  tests. Write carefully, keep changes compilable by inspection, and list what must be verified
  on the Mac.
- Mac only, build and test:
  ```
  xcodebuild -project Forge.xcodeproj -scheme Forge \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
  ```
  Report the swift-testing line `Test run with N tests in M suites`, not the XCTest
  "Executed 0 tests" line. Read destinations from `xcodebuild -showdestinations`, not `simctl`.
- Never build with `CODE_SIGNING_ALLOWED=NO` into the default derived data; it breaks later
  `xcodebuild test` runs (FORGE_CONTEXT §14). Use `-derivedDataPath` for unsigned builds.
- Verify UI changes in the iOS Simulator on iPhone 17 Pro and iPhone 17e and attach screenshots
  to the PR.

## The Xcode project (FORGE_CONTEXT §15)
- `objectVersion = 56`, **no synchronized groups**. A file on disk is not in the build until
  project.pbxproj says so.
- A new Swift file needs four project.pbxproj entries: PBXBuildFile, PBXFileReference, the
  group's children, and the target's Sources build phase. A new test file needs the same four
  for the ForgeTests target. New images go into Forge/Assets.xcassets.
- Copy a neighbouring file's entries and use fresh 24-hex-character IDs (check they are unused).
  When scripting, match `/* Name.swift */`, not the bare filename.
- Validate with `plutil -lint Forge.xcodeproj/project.pbxproj`, then let the build prove it.
- ForgeWidgets compiles only ForgeWidgets/*.swift plus a few Shared/ files and
  Models/ForgeDay.swift; it does not see Ritual.swift or ForgeTheme.swift.

## Writing tests (FORGE_CONTEXT §14)
- `@MainActor` on any `@Suite` that touches a `@MainActor` type (IdentityStore, ForgeStore,
  anything reaching ForgeHaptics).
- `Comment(rawValue:)` for a runtime-String expectation message; a plain String no longer
  converts to Comment.
- ForgeViewModel uses the real App Group suite shared by every test: any suite touching the
  first run calls `vm.resetFirstRun()` in its helper.
- AnalyticsTests "A period before the history began..." can fail only on a Monday. The test
  is wrong, not ProgressStore; do not "fix" the store.
- StoreKit tests (SKTestSession) need `get-task-allow` on the Simulator: Debug Simulator builds
  use Forge/ForgeSimulator.entitlements. A new entitlement goes into it and Forge.entitlements
  both; PremiumTests fails until they match.
- One swift-testing test: `-only-testing:'ForgeTests/<Suite type>/<func>()'` (with the
  parentheses, or it matches nothing and passes with 0 tests).

## Money (summary of DIRECTION_1_1.md §1)
- Hard paywall after onboarding for new installs; no free tier for them.
- Annual $49.99 with a 7-day trial (default), Monthly $12.99 (no trial), Annual offer $29.99
  with a trial (shown once, on decline), Lifetime $129.99 (Settings → Forge Pro only).
- The paywall shows the trial timeline; a local reminder two days before the trial ends.
- Founders (ran 1.0 or 1.0.1): everything free forever except AI. Detected on device.
- Lapsed: the record stays readable forever; new days, Arcs, the daily challenge and AI need
  Pro. Nothing is deleted or hidden. §5 #1 is amended; the three doors (§5 #8) are retired.
- A paywall row only names a feature in the build. Never timers, fake scarcity, invented
  counts or statistics, fake discounts, or a rating prompt before somebody has used the app.

## Voice (user-facing copy)
No exclamation marks. No congratulations. Never loss-aversion ("don't lose your streak").
The app never plays a character. Numbers as words up to one hundred **in prose only**
("three days kept"); scores, the six stats, OVR, prices, dates, times and Arc day counters are
digits. Only the four papers listed in DIRECTION_1_1.md may be cited.

## Documentation
- Document each session's changes as a dated subsection of FORGE_CONTEXT §17 Release 1.1.
- New Swift files: say in the PR which files were added to project.pbxproj.

## Git / PR workflow
The repository root is this folder. Run `git rev-parse --show-toplevel` first: the home folder
is also a git repository, and nothing may be committed there.

1. Always start from the latest remote `main`: fetch origin, switch to main, update it from
   origin/main, verify the working tree is clean.
2. One task = one branch = one PR.
3. Before the final push, fetch `origin/main` again and merge it into the feature branch.
4. If merge conflicts exist, resolve them yourself and semantically: preserve everything already
   merged into main and everything intended by the branch; never take one whole side blindly;
   never remove unrelated tests, documentation, telemetry, security fixes, or features.
5. Re-run all tests/checks available in the environment after resolving conflicts.
6. Push to the existing feature branch and create or update ONE PR. Never open a replacement PR
   because the branch became outdated.
7. Before declaring the task complete, verify the PR is mergeable against the current `main`.
   If it is not because main moved, update from main, resolve, re-run checks, push again.
8. If permissions allow and all available checks pass with no unresolved conflicts, merge the PR
   with a merge commit. Do not merge with failing tests, unresolved conflicts, or known untested
   critical changes.
9. After merging: fetch origin, update local main, verify the changes are in `origin/main`, and
   delete the remote feature branch if safe.
10. Never force-push `main`. Never rewrite `main` history. Never discard merged work to resolve a
    conflict.
11. For iOS/Swift changes, cloud Linux cannot replace Xcode validation: clearly report when the
    Xcode build or tests remain unverified.

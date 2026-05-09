# PhoneCare Copilot Instructions

This repository has a non-standard iOS build workflow because local Xcode is not always available and private GitHub Actions minutes may be exhausted.

## IPA Build Rules

- Prefer the existing workflow in `.github/workflows/build.yml` for IPA generation.
- The current supported artifact is an **unsigned IPA** intended for Sideloadly.
- A valid IPA must contain:
  - `Payload/PhoneCare.app/Info.plist`
  - `Payload/PhoneCare.app/PhoneCare`
- If you change IPA packaging, preserve the `ditto`-based packaging flow used in `.github/workflows/build.yml`.

## When Private GitHub Actions Minutes Are Exhausted

- Do **not** block waiting for private-repo CI.
- Use a temporary **public** repository to consume free unlimited public Actions minutes.
- Standard fallback flow:
  1. Create a temporary public repo with `gh repo create`.
  2. Push `main` to that repo.
  3. Wait for `.github/workflows/build.yml` to complete.
  4. Download the `PhoneCare-unsigned` artifact.
  5. Place the resulting IPA at `~/Downloads/phonecare-ipa/PhoneCare.ipa`.
- Example pattern:

```bash
TEMP_REPO="phone-care-verify-$(date +%Y%m%d-%H%M%S)"
gh repo create "felisbinofarms/$TEMP_REPO" --public
git remote add temp-build "https://github.com/felisbinofarms/$TEMP_REPO.git"
git push -u temp-build main
gh run list --repo "felisbinofarms/$TEMP_REPO"
gh run download <RUN_ID> --repo "felisbinofarms/$TEMP_REPO" --name PhoneCare-unsigned --dir ~/Downloads/phonecare-ipa
```

## Important Project Caveat

- New Swift files are **not always automatically included** in the checked-in Xcode project.
- If you add a new file and CI cannot find the symbol, either:
  - update `PhoneCare.xcodeproj/project.pbxproj`, or
  - temporarily embed the new type in an already-included file until the project file is regenerated.
- Do not assume `project.yml` alone is enough at build time.

## CI Expectations

- `xcodebuild` commands in shell pipelines must use `set -eo pipefail` so failures are not masked.
- Build for device with:
  - `-sdk iphoneos`
  - `-destination 'generic/platform=iOS'`
  - `CODE_SIGNING_ALLOWED=NO`
- Packaging is for Sideloadly testing, not App Store distribution.

## Distribution Expectations

- For local device install, assume Sideloadly is the default path.
- If the user asks where the IPA is, the expected location is:

```text
~/Downloads/phonecare-ipa/PhoneCare.ipa
```

- If Sideloadly reports missing `Info.plist`, the IPA is malformed and must be rebuilt.

## Subscription / Paywall Testing

- Debug builds may include a test-user premium bypass in Settings.
- Preserve production StoreKit behavior unless the change is explicitly debug-only.

## Review / Merge Guidance

- Before approving PRs that add new Swift files, verify they are included in the Xcode project or CI will fail.
- Before merging build-related changes, ensure the generated IPA still contains a full app bundle and is not an empty shell.

## Product Decision Summary (Locked)

These product decisions are locked and have already shipped or are about to ship. When you suggest code changes, do not propose changes that contradict these decisions without flagging them as a deliberate revision. The canonical sources are the linked decision docs in `docs/`.

### Free vs Premium policy (decided 2026-05-06)
Source of truth: `docs/free-vs-premium-decision-2026-05-06.md`

- **Q1 / Q3 - Batch is the premium lever.** Free shows all scan data and supports single-item delete across photos, contacts, and storage. Premium unlocks batch operations.
- **Q2 - No starter batch on free.** Single-delete only on free. Cleanest pitch.
- **Q4 - Similar-photo detection (#70) ships free.** We do not gate the truth fix that the marketing copy already promised.
- **Q5 per-surface gates:**
  - Contact merge: find duplicates free, merge action premium
  - Battery trend: 24-hour history free, longer history premium
  - Privacy Audit: info free, fixes and guided actions premium
  - Guided Cleanup flows: premium
  - Storage breakdown: free
- **Q6 - Capability-level gating.** Premium gating is applied at the capability level via `PremiumGateModifier`, not feature by feature.
- **Q7 - Paywall framing.** Headline: "PhoneCare Premium does the heavy lifting." Body lists batch cleanups, guided flows, battery history, and smart reminders.
- **Q8 - Trial structure.** 7-day free trial on monthly and annual only. No trial on weekly (already a near-trial price; layering a 7-day trial risks Apple's "trial gaming" review flag).

### Launch readiness decisions (decided 2026-05-07 / 2026-05-08)
Source of truth: `docs/launch-decisions-2026-05-07.md`

- **Q1 - #74 closed.** Free-vs-premium queue is clean.
- **Q2 - Legal hosting.** Privacy Policy and Terms of Service live in a separate free public companion repo (e.g. `pyroforbes/phonecare-legal`) with GitHub Pages enabled. The in-app `SettingsViewModel.swift` URLs and the App Store Connect Privacy URL field both point at those Pages URLs.
- **Q3 - Sandbox StoreKit E2E.** Runs alongside the TestFlight build, manually on a physical iPhone. Joseph or Victor creates the sandbox account; runbook lives with the test plan.
- **Q4 - Metadata authorship.** Hybrid. AI drafts tactical fields (keywords, reviewer notes); Joseph and Victor write brand-voice fields (description, subtitle, promotional text). Screenshots can start as simulator captures, re-captured on real device pre-submission if visual polish needs it.
- **Q5 - Error-path tests pre-launch (#118).** Shipped. At least 2 error-path tests per service across SubscriptionManager, ContactAnalyzer, CleanupUndoManager, BatteryViewModel, OnboardingViewModel.
- **Q6 - Similar-photo detection (#70).** Shipped. Vision framework `VNFeaturePrintObservation` for similarity grouping, threshold 0.5. Keep-best signals are sharpness (Laplacian variance), resolution, and file size, weighted 0.5 / 0.25 / 0.25. One unified list with the existing `GroupReason` chip per group.
- **Q7 - Space-first photos workflow (#71).** Shipped. Existing 2 photo categories plus screen recordings. 250 MB large-video threshold. Default sort (biggest-first videos, oldest-first screenshots) plus per-surface user-toggleable sort.
- **Q8 - Family Mode deferred indefinitely.** CloudKit-shared architecture conflicts with the on-device-only commitment in `CLAUDE.md`. Issue #18 left open as a future-consideration ticket.

### Where to read more

- `docs/free-vs-premium-decision-2026-05-06.md` for full reasoning behind each Q-decision in the free vs premium policy.
- `docs/launch-decisions-2026-05-07.md` for full reasoning behind each launch-readiness decision.
- `docs/issue-triage-2026-05-04.md` for the upstream triage workup that surfaced the Q-questions.
- `docs/qa-smoke-test.md` for the real-device smoke-test checklist.
- `CLAUDE.md` for project rules and the same product-decision summary, kept in sync with this file.
# Launch-readiness decisions, 2026-05-07

**Filed:** 2026-05-07
**For:** Joseph + Victor
**Blocks:** the remaining 8 open GitHub issues, App Store submission readiness
**Time to read:** ~10 minutes

---

## Decisions made so far

- **Q1: a — Closed #74 with a wrap-up comment** linking to the resolved policy doc and the 8 merged PRs. Decided 2026-05-07 by Joseph. The free-vs-premium queue is now fully clean.
- **Q2: Free public companion repo for legal docs.** Decided 2026-05-08 by Joseph after research into GitHub Pages on private repos as of May 2026 (confirmed: requires GitHub Pro, $4/month, which we're choosing to skip). Joseph creates a new public repo (e.g. `pyroforbes/phonecare-legal`) containing only the privacy policy and terms-of-service markdown. GitHub Pages enabled on that repo. The in-app `SettingsViewModel.swift:20-22` URLs and the App Store Connect Privacy Policy URL field both point at the public Pages URLs. Manual sync between `docs/legal/` in the main repo and the companion repo is acceptable (low edit frequency).

  **Path forward:**
  1. Joseph creates `pyroforbes/phonecare-legal` (public), copies `docs/legal/privacy-policy.md` and `docs/legal/terms-of-service.md` to the repo root.
  2. Joseph enables GitHub Pages (Settings → Pages → Source: main branch) and confirms the URLs render publicly.
  3. Joseph shares the resolved Pages URLs with me.
  4. I open a small PR updating `SettingsViewModel.swift:20-22` to point at the new URLs, plus a brief note in `docs/legal/README.md` (or similar) flagging the companion repo as the publicly-hosted source and reminding future editors to update both copies on every change.
  5. At App Store submission, the same Privacy Policy URL goes into App Store Connect.
- **Q3: b — Sandbox StoreKit E2E test runs alongside the TestFlight build.** Decided 2026-05-08 by Joseph. Avoids running it twice (sandbox state can drift between Xcode StoreKit tests and real device) and keeps the safety net intact before reviewer exposure. Joseph or Victor will manually create the sandbox account in App Store Connect and run the test matrix on a physical iPhone. I'll write the step-by-step runbook (covering all 10 verification tasks: product loading, full purchase flow per plan, trial transitions, restore, premium gating, sandbox account creation, credential documentation for reviewer notes).
- **Q4: c — Hybrid metadata authorship.** Decided 2026-05-08 by Joseph. I draft tactical fields (keywords, reviewer notes) using the market doc as input; Joseph and Victor write the brand-voice fields (description, subtitle, promotional text). Sub-question on screenshots defaulted to simulator-first per recommendation (Apple accepts them, faster to produce, can be re-captured on a real device pre-submission if visual polish needs it).
- **Q5: a — All 10 error-path tests pre-launch.** Decided 2026-05-08 by Joseph. Aligns with the brand promise of "honest, trustworthy, no surprises" — silent error-path failures contradict that. Roughly one day of work. Will be filed as a sequenced PR covering 2 tests per service across SubscriptionManager, ContactAnalyzer, CleanupUndoManager, BatteryViewModel, and OnboardingViewModel.
- **Q6: Similar-photo detection strategy locked.** Decided 2026-05-08 by Joseph (confirmed all three sub-recommendations).
  - **6a: a** — Vision framework's `VNFeaturePrintObservation` for similarity grouping. On-device, public API, matches what Apple's Photos app uses.
  - **6b: sharpness + resolution + file size** as keep-best signals for v1. Face/eye detection deferred to v1.1.
  - **6c: b** — One unified list with the existing `GroupReason` chip per group. No three-section fragmentation.
- **Q7: Space-first workflow scope locked.** Decided 2026-05-08 by Joseph.
  - **7a: c** — Existing 2 categories (large videos, screenshots) + screen recordings at launch. Bursts and Live Photos deferred to post-launch.
  - **7b: b** — 250 MB threshold for large videos. Tunable later.
  - **7c: amended** — Defaults stay (biggest-first for videos, oldest-first for screenshots), AND ship a simple user-toggleable sort. Two-option picker per category: videos = [Biggest first / Oldest first], screenshots = [Oldest first / Newest first]. Defaults must be clearly indicated in the UI (selected state on the picker is the standard pattern).

  **Implementation note:** the sort toggle is per-surface (lives at the top of each category's list), persisted in `@State` per session (not across launches for v1). Keep visuals minimal — a small segmented control or capsule pair, matching the existing `categoryPicker` pattern in `PhotosView.swift`.
- **Q8: c — Family Mode deferred indefinitely.** Decided 2026-05-08 by Joseph. Reasoning: Family Mode's CloudKit-shared architecture requires device pairing (effectively a form of auth) and cross-device data sharing, which conflicts with the brand commitment to "100% local storage, no backend, no auth" (CLAUDE.md). The growth-loop value isn't worth the architectural compromise. I'll add a comment on #18 explaining the deferral and leave the issue open as a future-consideration ticket; Joseph can close or revisit if priorities shift.

---

## What we're deciding

Eight specific yes-or-pick-one questions to clear the rest of the open issue queue. The free-vs-premium policy is shipped (8 PRs merged; tests at 383 in 23 suites). What's left is launch-readiness: legal-URL hosting, App Store metadata, sandbox testing, test-coverage gaps, two feature scope locks (#70 similar-photo, #71 space-first), an administrative close, and a post-launch growth feature timing call.

Same format as the free-vs-premium doc that worked well last time.

---

## Why now

The eight tier-policy issues are done. Code reflects the locked policy. The next phase is shipping the app. Every open question below either blocks an App Store submission, defines launch-day feature scope, or sets the post-launch roadmap. Locking them now lets us run the rest as a clean execution sprint.

---

## The 8 questions

### Q1. Close #74 as resolved?

#74 was the parent meta-issue for the free-vs-premium boundary rework. We resolved it via the decision doc (`docs/free-vs-premium-decision-2026-05-06.md`) and the eight implementation issues (#151 through #158, all merged).

**Options:**
- **a)** Yes, close it with a wrap-up comment linking to the policy doc and the 8 merged PRs.
- **b)** No, keep it open as a tracking ticket.

**My take: a.** Clean queue. No work pending. The trail is preserved by the comment.

---

### Q2. Where do we host the privacy policy and terms-of-service URLs? (#145, P0 launch blocker)

Current state: `SettingsViewModel.swift:20-22` points the in-app links at `github.com/pyroforbes/phone-care-ios/blob/main/docs/legal/...`. The repo is private; both URLs return HTTP 404 to anonymous clients (verified). App Store Review will fail this under Guideline 5.1.1, which requires the privacy policy URL to be publicly accessible.

**Options:**
- **a)** GitHub Pages on a public companion repo (e.g. `pyroforbes/phonecare-legal`). Free, simple, separate.
- **b)** GitHub Pages on the existing private repo, with Pages itself set to public visibility. Pages can be public even when the source repo is private.
- **c)** Marketing site, if one is being built or already exists.
- **d)** Notion, Read.cv, S3, Netlify, or similar simple static hosting.

**Engineering consequence:** Same two lines in `SettingsViewModel.swift` change to point at the new URLs. The Privacy Policy URL field in App Store Connect gets the same URL at submission time.

**My take: b.** Single source of truth (the markdown is already in `docs/legal/`), zero extra infrastructure, no second repo to maintain. Apple just needs the URL to resolve publicly. They don't care that the source repo is private.

---

### Q3. When does the sandbox StoreKit end-to-end test run? (#46)

Apple requires a sandbox test account with an active subscription for reviewer testing. The issue lists 10 verification tasks (full purchase flow, state transitions, restore, premium gating, sandbox account creation, documentation).

**Options:**
- **a)** Now, before any other launch prep. Block #47 submission on this passing.
- **b)** Right before the TestFlight build, in tandem with build artifacts.
- **c)** Defer to the first reviewer round. Submit, let the reviewer catch issues, fix in resub.

**Engineering consequence:** Options a and b require Joseph or Victor to manually create a sandbox account in App Store Connect, run the test matrix on a physical device, and document the credentials. Option c gambles on the reviewer being lenient and adds 2 to 7 days of latency per rejection.

**My take: b.** Sandbox E2E in tandem with the TestFlight build. Doing it earlier risks doing it twice (sandbox state can drift between Xcode StoreKit tests and real device). Doing it later loses the safety net.

---

### Q4. App Store metadata authorship (#47)

#47 has roughly 30 sub-tasks. The decision-heavy items are the ones that need authoring: description, subtitle, promotional text, keywords, reviewer notes.

**Options:**
- **a)** Joseph and Victor write all the marketing copy directly. You know the brand voice best.
- **b)** I draft a first pass for each metadata field; you and Victor edit and approve.
- **c)** Hybrid: I draft tactical fields (keywords, reviewer notes); you write the voice-heavy fields (description, subtitle, promotional text).

**Engineering consequence:** Options b and c save significant time. Option a keeps brand voice tightest. None block any code work.

**My take: c.** Keywords and reviewer notes are tactical and factual; I can draft those efficiently with the market doc as input. The description and subtitle ARE the brand pitch; those need your hand.

**Sub-question if b or c:** screenshots, simulator first or real device first? Recommend simulator first (Apple accepts them, faster to produce, can be re-captured on a real device pre-submission if visual polish needs it).

---

### Q5. Add the missing error-path tests pre-launch? (#118)

P2 issue listing 5 services with zero error-path test coverage:
- `SubscriptionManager`: purchase failure, network timeout, invalid transaction
- `ContactAnalyzer`: store denied mid-merge, data corruption on save
- `CleanupUndoManager`: undo handler exceptions
- `BatteryViewModel`: DataManager unavailable
- `OnboardingViewModel`: scan cancellation and timeout

AC says at least 2 error-path tests per service, so 10 total tests minimum.

**Options:**
- **a)** Write all 10 tests pre-launch. Small PR, increases confidence.
- **b)** Write the 4 most-likely-to-fail-in-production tests (e.g. SubscriptionManager network timeout, ContactAnalyzer mid-merge denial). Accept the gap on the rest.
- **c)** Defer entirely. Accept the gap. Fix bugs reactively post-launch.

**Engineering consequence:** Option a is roughly one day of my work. Option b is roughly half a day. Option c is zero now but higher risk of post-launch bugs that erode the calm-expert brand reputation.

**My take: a, all 10.** Small total effort; tightens the safety net before exposure to real users. The brand promise is "honest, trustworthy, no surprises." Error paths failing silently in production directly contradicts that. Worth the day.

---

### Q6. Similar-photo detection strategy (#70)

Tier already locked (free per Q4 in the prior decision doc). Open product spec decisions split into three sub-questions.

**6a. Detection method:**

- **a)** Vision framework's `VNFeaturePrintObservation`. Apple's built-in perceptual feature print, generates a "fingerprint" per image, compute distance between fingerprints to group similar photos. Public API, on-device. This is what Apple's own Photos app uses.
- **b)** Custom perceptual hash (pHash). Implement a simple hash function on downsampled images. Lighter weight, less accurate.
- **c)** Keep the current heuristic (file size + creation time + dimensions) and just relabel the UX honestly.

My take: **a**. Vision is the right tool, on-device, public API, and Apple's own implementation. Industry standard. We get to be the "honest helper" without overpromising.

**6b. "Keep best" signals to surface:**

Possible signals: sharpness (Laplacian variance, already partially in #137), resolution, file size (proxy for quality), face detection (closed-eye and smile detection via Vision).

My take: **sharpness + resolution + file size for v1.** Face and eye detection are delightful but add processing cost; defer to v1.1 if users ask.

**6c. Confidence tier UX:**

- **a)** Three sections: "exact duplicate," "very similar," "possibly similar."
- **b)** One unified list with a confidence chip per group (using the existing `GroupReason` enum from the codebase).

My take: **b**. Three sections fragments the experience. The chip already exists.

---

### Q7. Space-first workflow scope at launch (#71)

Tier already locked (free preview + premium batch per Q3 in the prior decision doc). Open product spec decisions split into three sub-questions.

**7a. Which categories ship at launch?**

Currently surfaced: large videos, screenshots (by age). Issue lists future: screen recordings, bursts, Live Photos.

- **a)** All 5 at launch.
- **b)** Just the existing 2 (large videos + screenshots). Add the others post-launch.
- **c)** Existing 2 + screen recordings.

My take: **c**. Screen recordings are a single `PHAssetMediaSubtype` filter (cheap to add) and they're often the largest single files on a phone. Bursts and Live Photos are more design work and lower impact. Defer to post-launch.

**7b. Large-video threshold:**

- **a)** 100 MB
- **b)** 250 MB
- **c)** 500 MB

My take: **b, 250 MB.** Catches typical "one big video" without flagging every 4K minute clip. Tunable later.

**7c. Sort order within each category:**

- **a)** Biggest size first (highest reclaim).
- **b)** Oldest first (safest delete).
- **c)** User-toggleable.

My take: **biggest first for videos, oldest first for screenshots** (already implemented for screenshots). User-toggleable adds complexity for v1. Defer.

---

### Q8. Family Mode timing (#18)

Post-launch growth feature per the issue title and market doc §5.2. Issue body sketches a CloudKit-based architecture with no backend.

**Options:**
- **a)** v1.1, start building immediately after launch, ship in 3 to 4 weeks.
- **b)** v2, 3 to 6 months post-launch, after we have user data and reviews.
- **c)** Defer indefinitely. Only build if users ask.

**Engineering consequence:** Family Mode is meaningful work (CloudKit shared zone setup, cross-device messaging, settings UX, parent and child flows). Several days minimum, possibly 1 to 2 weeks for a polished v1.

**My take: b, v2.** Pre-launch focus should be the calm-expert MVP shipping cleanly. Family Mode is a viral and growth-loop feature; it's most valuable AFTER you have the base product proving itself in the App Store. Building it pre-launch delays the launch and dilutes attention. Building it 3 months in lets you target users who already love the app and want to share it.

---

## What happens after you answer

Same workflow as the free-vs-premium doc:

1. You answer the 8 questions inline, or reply in chat as `Q1: a, Q2: b, ...`.
2. **Q1 (close #74):** I close it with a wrap-up comment.
3. **Q2 (legal hosting):** once you enable Pages on the chosen path, I update `SettingsViewModel.swift` (one PR).
4. **Q3 (sandbox timing):** I write a runbook for whoever runs the test.
5. **Q4 (metadata authorship):** I draft tactical fields (keywords, reviewer notes); you draft brand-voice fields.
6. **Q5 (error-path tests):** if (a), I file a single tracking issue + sequenced PRs.
7. **Q6 (#70 spec):** I file the implementation issue with the locked spec.
8. **Q7 (#71 spec):** I file the implementation issue with the locked spec.
9. **Q8 (Family Mode timing):** I add a comment on #18 with the chosen timing.

---

## Final answers, all 8 locked (2026-05-08)

> **Q1: a** — Closed #74.
> **Q2: free public companion repo** — `pyroforbes/phonecare-legal` (or similar). GitHub Pro avoided. Joseph creates the repo and shares the public Pages URLs; I update `SettingsViewModel.swift` and add a sync note for future edits.
> **Q3: b** — Sandbox E2E tests run alongside the TestFlight build.
> **Q4: c** — Hybrid metadata authorship. I draft tactical fields (keywords, reviewer notes); Joseph and Victor write brand-voice fields (description, subtitle, promotional text). Screenshots simulator-first.
> **Q5: a** — All 10 error-path tests pre-launch.
> **Q6** — Vision `VNFeaturePrintObservation` (a), sharpness + resolution + file size for keep-best, unified list with `GroupReason` chip (b).
> **Q7** — Existing 2 categories + screen recordings at launch (c), 250 MB large-video threshold (b), defaults stay (biggest-first videos, oldest-first screenshots) **plus a simple per-surface user-toggleable sort**.
> **Q8: c** — Family Mode deferred indefinitely. Brand commitment to local-only / no-auth outweighs the growth-loop value.

## What I do next (auto-mode follow-ups)

Immediate (already done or doing now):
- Q1: #74 closed with the resolved-policy comment
- Q8: comment posted on #18 explaining the indefinite deferral (future-consideration ticket left open for revisit)

Awaiting Joseph:
- Q2: Joseph creates the public companion repo and shares the URLs; I open a PR updating `SettingsViewModel.swift` and add a sync note.
- Q3: when TestFlight is queued, I write the sandbox-test runbook for whoever runs it.
- Q4: when the metadata window opens, I draft keywords + reviewer notes; you draft brand-voice copy.

Ready to start now (one PR per issue, awaiting your go on which to tackle first):
- Q5: error-path tests across 5 services (one PR, ~10 new tests).
- Q6: implementation issue + PR for #70 with the locked similar-photo spec.
- Q7: implementation issue + PR for #71 with the locked space-first scope.

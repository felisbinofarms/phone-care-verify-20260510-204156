# GitHub Issue Triage — PhoneCare iOS
**Date:** 2026-05-04
**Open issues at time of triage:** 44

## Context

A collaborator's Copilot generated ~42 issues (#85–#125) on the `pyroforbes/phone-care-ios` repo, on top of older strategy/launch issues from you (#18, #46, #47, #67, #70, #71, #74). Total open: **44**.

Recent commits (`471a6eb`, `6ffa237`, `89d2935`, `2c9945e`, `babdbe2`) claim sweeping fixes for #89, #90–#116, #119, #124 — but **the issues are still open**. I spot-checked the code at the line ranges each issue cites. **Many fixes are real and just need the issue closed; several are not actually fixed; a few are partial.** Triage below reflects current code, not commit messages.

The goal of this document is to give (a) a clean MVP-vs-post-MVP cut, (b) an order of attack, and (c) which issues are "shut up and ship code" vs. which need product/design/external work.

---

## Section 1 — Already Fixed in Code (close on GitHub, no work)

These have working fixes in the current `main`. Verify on the issue page, then close with a short comment pointing at the commit.

| # | Title | Where fixed |
|---|---|---|
| 67 | Photos tab real deletion | `PhotosViewModel.confirmBatchDelete` now calls `PHPhotoLibrary.shared().performChanges` (line 274) |
| 93 | GuidedFlowCoordinator @MainActor | Type marked `@MainActor` (line 12) |
| 96 | Contacts merge ProgressView | `ContactsView` shows ProgressView when `isMerging` (lines 135–143) |
| 98 | Dashboard refresh | `onChange(of: appState.selectedTab)` added (lines 45–52) |
| 99 | DashboardViewModel tests | `DashboardViewModelTests.swift` exists with `@Test` cases |
| 100 | BatteryMonitor tests | `BatteryMonitorTests.swift` exists |
| 101 | StorageAnalyzer async tests | Async coverage added |
| 102 | PhotoAnalyzer async tests | Async coverage added |
| 103 | ContactAnalyzer merge/restore tests | Coverage added |
| 104 | SubscriptionManager purchase tests | Coverage added |
| 105 | PrivacyAuditor performAudit tests | Coverage added |
| 107 | Storage "Other" .orange | Now `Color.pcTextSecondary` (line 90) |
| 111 | PhotoAnalyzer hash timeout | 5s timeout added (line 539) |
| 112 | Restore Purchases visibility | Visible in both premium and free branches (`SubscriptionStatusView` lines 56 & 79) |
| 114 | PrivacyView a11y label | `accessibilityLabel("Privacy score: X out of 100")` added (line 51) |
| 116 | Share-prompt cooldown UserDefaults | Persisted to UserDefaults (lines 35, 42) |
| 124 | UndoToastView countdown cancel | `timerTask?.cancel()` in `.onDisappear` (line 77) |

**Action:** close all 17 of these with a one-line note like "Fixed in 6ffa237" and move on. ~30 min of GitHub busywork.

---

## Section 2 — Not Actually Fixed (real code work remaining)

| # | Pri | Title | Status | Type |
|---|---|---|---|---|
| **89** | **P0** | PaywallViewModel `priceFormatStyle` undefined — compile error | **NOT FIXED** — property still missing | Code |
| 90 | P1 | PaywallViewModel `products[1]` unsafe subscript | NOT FIXED — still indexing | Code |
| 92 | P1 | StorageAnalyzer 0 B / 0 B silent failure | NOT FIXED — no error state | Code |
| 95 | P1 | PhotosView UndoToast ↔ SharePrompt transition race | NOT FIXED | Code |
| 97 | P1 | ContactsViewModel doesn't validate merge succeeded | NOT FIXED | Code |
| 91 | P1 | Contacts property name mismatch | PARTIAL — runtime works via mapping but names misaligned | Code (refactor) |
| 94 | P1 | SubscriptionManager non-atomic premium write | PARTIAL — UserDefaults write present, no transactional ordering | Code |
| 106 | P2 | PhotoAnalyzer blurry detection is pixel-dimension based | NOT FIXED — still uses 8×8 average hash, no Laplacian/Vision | Code (algorithmic) |
| 108 | P2 | DashboardViewModel hardcoded `51` threshold | NOT FIXED — no shared constant | Code (refactor) |
| 109/125 | P2/P3 | PrivacyAuditor concurrency / no loading state | PARTIAL — `isLoading` set but no re-entry guard | Code |
| 110 | P2 | ContactAnalyzer phone normalization breadth | NOT FIXED — uses "last 7 digits" suffix only | Code |
| 113 | P2 | Paywall a11y labels missing on some buttons | PARTIAL — Restore/Terms/Privacy labeled; Try Again, Not Now bare | Code |
| 115 | P2 | BatteryView "Not available" with no explanation | NOT FIXED — bare string still | Code |
| 119 | P3 | BatteryMonitor observers may leak if `stopMonitoring` not called | **WONTFIX recommended** — `@MainActor deinit` was intentionally removed in `2c9945e` due to Swift 6 isolation rules. Document and close. | Decision |
| 117 | P2 | PermissionManager `checkAllStatuses` untested | NOT DONE | Tests |
| 118 | P2 | Async error paths untested across services | NOT DONE | Tests |
| 120 | P3 | HealthScoreRingView color animation desync | NOT FIXED | Code |
| 121 | P3 | "Open Photos" undo toast label misleading | NOT FIXED | Copy |
| 122 | P3 | Settings notification toggles no confirmation/undo | NOT FIXED | UX |
| 123 | P3 | Onboarding back button never shown | NOT FIXED | UX |

---

## Section 3 — Strategy / Product-Design Issues (not pure code)

These need decisions before code can be written. They're not Copilot-generated.

| # | Title | Type | Notes |
|---|---|---|---|
| 70 | Honest similar-photo review w/ keep-best explanations | Product + Code | Needs algorithm choice (Vision featurePrintObservation? Embedding?) and "why grouped" copy strategy |
| 71 | Space-first cleanup workflows (heavy videos, screenshots) | Product + Code | UX flow design needed before code |
| 74 | Free vs Premium boundary rework | Strategy | Conversion-impact decision; competitive response to Clever Cleaner. **Decide before #46/#47 lock-in App Store metadata.** |
| 46 | E2E StoreKit 2 sandbox testing | QA + Code | Requires sandbox account + manual flow exercise |
| 47 | App Store submission checklist | Ops/Marketing | Screenshots, description, ASO keywords, sandbox creds — non-code |
| 18 | Family Mode (post-launch) | Post-launch | Architectural design needed; explicitly tagged post-launch |

---

## Section 4 — MVP Tiers & Recommended Order

### Tier 0 — Ship-Stoppers (do this week)
Anything that breaks build, crashes the user, or fails Apple review.

1. **#89** — PaywallViewModel compile error. (Can't build right now if this is real — verify locally first.)
2. **#90** — Unsafe `products[1]` subscript in paywall (crash on edge-case StoreKit response).
3. **#92** — Storage silent 0/0 failure (looks broken to reviewer).
4. **#97** — Contact merge silent failure (data loss risk → trust violation).
5. **#95** — UndoToast/SharePrompt race (visible UI glitch reviewer can hit).
6. **#113** (finish) — A11y labels on remaining paywall buttons (accessibility is active review criteria per CLAUDE.md).

### Tier 1 — MVP Quality (before submission)
Bugs that reach the user but won't reject the build.

7. **#91** — Align Contacts property names (refactor, low risk).
8. **#94** — Subscription state atomicity (cache-coherency on crash).
9. **#106** — Real blurry detection (Laplacian variance or Vision). High false-positive trust hit.
10. **#108** — Extract `goodThreshold` to `HealthScoreCalculator` (one-line refactor, prevents drift).
11. **#109** + **#125** — PrivacyAuditor concurrency guard + loading state (one fix covers both).
12. **#110** — Broaden phone normalization (or document the limit and ship).
13. **#115** — BatteryView explanation + Settings deep-link (currently a dead-end card).
14. **#117** + **#118** — Test coverage gaps (PermissionManager, error paths).

### Tier 2 — Pre-Launch Strategy Gates (block #47)
Don't lock App Store metadata until these are decided.

15. **#74** — Free/Premium boundary decision. Affects paywall copy, screenshots, App Store description.
16. **#70** — Similar-photo strategy. Affects Photos screenshots and copy claims.
17. **#71** — Space-first workflow. Affects onboarding value-before-paywall promise.

### Tier 3 — Submission
18. **#46** — Sandbox StoreKit E2E.
19. **#47** — App Store submission checklist (screenshots, ASO, privacy labels, reviewer notes).

### Tier 4 — Polish (defer to first patch release)
- **#119** — Close as WONTFIX with rationale.
- **#120, #121, #122, #123** — P3 polish; ship without, fix in 1.0.1.

### Tier 5 — Post-Launch
- **#18** — Family Mode.

---

## Section 5 — "Strictly Code, Just Fix It" List

Issues that need zero product input — a competent agent can take each end-to-end. Suggest batching as a single sweep PR per group.

**Group A — Compile/Crash sweep (1 PR, ~1 day):**
#89, #90, #92, #97, #95

**Group B — Refactor/Correctness sweep (1 PR, ~1 day):**
#91, #94, #108, #109+#125

**Group C — Algorithmic accuracy (separate PR each, careful review):**
#106 (blurry detection — needs perf testing), #110 (phone normalization — needs locale test cases), #111 already done

**Group D — A11y + UX polish sweep (1 PR, ~half day):**
#113, #115, #120, #121, #122, #123

**Group E — Test coverage sweep (1 PR):**
#117, #118

**Issues that are NOT pure code (need product/strategy input):**
#46, #47, #70, #71, #74, #18, #119 (decision)

---

## Section 6 — Recommended Next Actions (in order)

1. **Sanity check #89.** Try `xcodebuild` or Xcode build now. If it actually fails to compile, that's the literal blocker — fix before anything else.
2. **Close the 17 already-fixed issues** (Section 1) in one sitting. Cleans the board so the remaining 27 are real signal.
3. **Tier 0 sweep** as Group A in one PR.
4. **Run Tier 1 in parallel:** Group B + Group D + Group E PRs can be developed concurrently without merge conflicts (different files).
5. **Make the Tier 2 strategy calls (#74, #70, #71)** before starting #47 metadata work.
6. **Submission gates last:** #46 then #47.

## Verification

This is a triage doc, not a code change. Verification = the resulting commits/PR comments closing the issues, plus:
- `xcodebuild -scheme PhoneCare build` succeeds (catches #89).
- `xcodebuild test` passes after Group E (validates new test coverage).
- `gh issue list --state open` count drops from 44 → ~10 strategy/launch items after the sweep.

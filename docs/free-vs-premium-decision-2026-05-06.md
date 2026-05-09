# Free vs Premium — pre-launch decision

**Filed:** 2026-05-06
**For:** Joseph + business partner
**Blocks:** GitHub issues #74 (this decision), #70, #71, paywall copy, onboarding sequencing
**Time to read:** ~10 minutes

---

## Decisions made so far

All eight archetype-D-consistent decisions made 2026-05-06 by Joseph + Victor (bulk-resolved per Joseph's request once Q1/Q3 established the pattern). Discord trail captured these in two passes — Q1/Q3 individually, then Q4/Q5/Q6 bundled.

- **Q1: b — Free + single-delete only across all photo duplicate groups; premium unlocks batch.** Aligns with market doc's stated freemium principle (*"scan data visible, actions gated"*); free users with hundreds or thousands of duplicates still see them and can clean up one at a time. Batch is the natural conversion lever for bulk users.
- **Q2 (cap question): single-delete only on free.** Implied by Q1=b. The line is "free deletes one at a time, premium handles many at once." No starter-batch generosity. Cleanest pitch.
- **Q3: b — Same shape as Q1 applied to space-first workflows (large videos, old screenshots, screen recordings).** Free preview + single-item delete; premium unlocks batch. One mental model across all photo cleanup.
- **Q4: a — Similar-photo detection upgrade (#70) ships free.** The current marketing copy already promises "we compare photos pixel by pixel"; #70 fixes the truth gap. Gating that fix would be a bait-and-switch on a stated promise.
- **Q5: Per-surface gate decisions:**
  - **Contact merge: PF** — find duplicates free, merge action premium. Same pattern as Q1/Q3.
  - **Battery trend chart: PF** — 24h free, longer history premium. Info free, depth premium.
  - **Privacy Audit detail: F** — info free; fixes/guided action premium.
  - **Guided Cleanup flows: P** — the step-by-step expert experience IS the premium product.
  - **Storage breakdown: F** — already free, anchors trust.
- **Q6: a — Batch operations are the central premium lever across the app, applied at the capability level.** This is what Q1=b and Q3=b already mean in policy form. Implementation note: `PremiumGateModifier` is applied at the capability level (one place, one truth), not feature-by-feature. Undo retention specifics (how long contact backups persist, whether we keep a reviewable cleanup-session history, free vs premium boundaries on those) are deferred to a separate product issue to be filed before launch.
- **Q7: (d) Time + (b) Breadth combined.** Paywall pitch leads with the heavy-lifting framing and the supporting body lists the full premium scope (batch, guided flows, battery history, smart reminders), reflecting the all-encompassing iPhone care positioning rather than narrowing to cleanup alone. Final copy:

  > **Headline:** "PhoneCare Premium does the heavy lifting."
  >
  > **Body:** "Batch cleanups across photos, contacts, and storage. Step-by-step guided flows for the bigger jobs. Battery health history. Smart reminders that keep your phone in good shape."

  Each body line maps to a real premium gate locked in Q5. Backed by `CLAUDE.md` line 73 (premium scope: cleanup actions, batch operations, undo support, full duplicate lists, guided flows, trend charts) and existing benefit list in `PaywallOnboardingView.swift:60-64`.
- **Q8: b — 7-day Apple-standard free trial on annual + monthly, no trial on weekly.** The weekly tier at $0.99 is already a near-trial; layering a 7-day free trial on top would give users 14 free days for $0.99 and risks Apple's submission flag for trial gaming. Annual and monthly keep the standard 7-day trial as the conversion onboarding mechanism.

  **Captured product requirements alongside Q8** (raised by Joseph during the decision):
  - **Duolingo-style transparency on trial-to-paid conversion.** Apple's default reminder ("Subscription will renew in X days") is the floor. Layer our own in-app notification a day or two before the trial ends as extra courtesy. Combined with explicit upfront disclosure on the paywall (the standard "free for 7 days, then $X" copy that Apple's UI also enforces), this is the most transparent version of a trial possible. Brand-aligned with the calm-expert promise of "no surprises, we tell you everything."
  - **In-app re-prompt mechanism for users who decline the trial.** Users who skip the trial during onboarding stay on the freemium tier and see contextual upgrade prompts at moments of natural friction (e.g. "delete the other 46 in this group? Premium does batch in one tap"). Not aggressive paywall re-shows; situational, value-anchored prompts. Already partially supported by `PaywallViewModel.shouldShow` (1-week re-show interval at line 20). Confirm and refine the placement strategy in the onboarding-and-conversion implementation issue.

---

## Status

**All 8 decisions locked as of 2026-05-06.** Ready to translate into implementation issues per the standard one-PR-per-issue workflow. Decision doc remains the canonical source for these choices.

## Confirmed product requirements raised during decisions

- **Side-by-side comparison view for verifying duplicates before deletion** (raised by Joseph during Q1). The user must be able to confirm two (or more) photos are actually duplicates before deleting either. This is a *safety / trust* feature — anchored in the market doc trust pillars (*transparency: show your work*, *reversibility*) — not a tier lever. Free and premium both get it. Open question: how this UX adapts for batch delete (premium) where the user can't pairwise-verify every group manually — likely a grid view with the suggested-keeper highlighted plus a "review individually" escape hatch. To be filed as a separate product issue once the tier decisions are locked.

---

## What we're deciding

The free / premium boundary at launch. Eight specific yes-or-pick-one questions below. Your answers drive every premium gate in the codebase, the paywall pitch, the onboarding paywall placement, and the Settings premium-status copy.

This decision is **not** about competitors. It's about whether the boundaries we ship match the brand commitments already in `docs/market-analysis.md` — the "Calm Expert Principle," the trust pillars (predictability, transparency, reversibility, no pushiness), and the explicit freemium principle on line 30: *"scan data visible, actions gated."*

The current code does **not** match those commitments yet. The "first 3 groups free, rest hidden" rule in `PhotosViewModel.freeGroupLimit = 3` was a placeholder, not a designed policy — and it directly contradicts "scan data visible." Locking the right policy now is the cheapest moment to do it; every gate is reversible with a one-line constant change today and a UX revision + paywall rewrite after launch.

---

## Why this decision, why now

**Brand integrity.** The market doc lists *"Paywall before value → feels like a trap"* as a top trust-destroyer for the 40+ audience. Premium gates are the surface where we're most likely to accidentally feel scammy. The 40+ user has been burned before; they sniff it out instantly.

**Stated principle vs. shipped code.** The market doc commits to *"freemium with real free value: scan data visible, actions gated."* The current `freeGroupLimit = 3` hides scan data (groups 4+) entirely, which is the opposite. Either the principle is wrong, or the code is. We need to align them before launch.

**Brand differentiator alignment.** Your own market doc identifies the moat as: unified dashboard, breadth (photos + contacts + battery + privacy), undo as a superpower, plain-English UX, and the calm-expert tone. Whatever we gate has to *reinforce* that moat, not undercut it. Gating the scan-data view undercuts it. Gating the batch/undo/history *capabilities* reinforces it (premium = "the expert friend handles the heavy lifting").

**Cost of locking it now vs. later.** Today: every gate change is a one-line edit. After launch: paywall copy is in screenshots, retention reports key off it, and any gate move triggers a UX revision pass.

---

## Four strategy archetypes

Pick a frame, then we tune within it. The axes are **brand fit** (does this match the calm-expert promise?) and **monetization sustainability** (does it actually convert?).

| Archetype | One-line summary | Brand fit | Conversion |
|---|---|---|---|
| **A. Generous free / narrow premium** | All scans + basic actions free; premium = non-photo verticals (contacts, battery, privacy, guided flows). | High (free is the whole core tool) | Risky — narrow paid surface |
| **B. Tight free / broad premium** (current) | Free is preview-only; premium unlocks past the cap. | **Low** — paywall hits before scan-data is visible | Good cap-based conversion, but matches the scam-app investment-then-paywall pattern from market doc §2.1 |
| **C. Time-gated** | Full features for first 7 days, reverts to limited after. | Low — feels like a trap | High initial value, low long-term trust |
| **D. Quality-gated** ⭐ | All scans free, single-item actions free, **batch + undo-history + advanced detection (e.g. similar-shot reasoning) + guided flows = premium**. | **High** — paywall sells capability, not artificial friction | Defensible — premium is genuinely more useful |

**My honest recommendation: Archetype D.** It's the only frame where the premium pitch matches the calm-expert brand. *"PhoneCare Premium handles the heavy lifting — batch cleanups across photos, contacts, and storage, plus 30 days of undo history."* That sells capability, not friction. And it maps cleanly onto how the existing `PremiumGateModifier` is wired — instead of gating *which groups you can see*, we gate *what you can do at scale*.

You don't have to pick D. The questions below let you express A, B, or D in detail. (C is omitted; tell me if you want it back.)

---

## The eight questions

Each: pick one. Each has an **Engineering consequence** that names the file or behavior the answer changes — so the tradeoff is concrete.

### Q1. Is basic photo duplicate detection (exact + obvious duplicates) free or gated at launch?

**Options:**
- **a) Free, unlimited** — every duplicate group visible, every single-item delete unlocked
- **b) Free with batch cap** — see all groups, delete one at a time freely; premium unlocks bulk delete
- **c) Gated by group count** — keep the current "first 3 groups, rest hidden" rule

**Why it matters:** This is the most-used surface in the app. The market doc principle is *"scan data visible, actions gated."* Option (c) hides scan data, which conflicts with that. Options (a) and (b) match it. Option (b) keeps a real conversion lever (batch is the time-saver).

**Engineering consequence:**
- **a)** Delete `freeGroupLimit` from `PhoneCare/Features/Photos/PhotosViewModel.swift:63`. Rip the "Show paywall after 3 groups" branch in `PhotosView.swift:336`. Rewrite paywall pitch (it currently says "unlock the rest").
- **b)** Replace `freeGroupLimit` with `freeBatchDeleteLimit` (e.g. 1 = single-item only). Add per-action gate to the multi-select delete flow. Adjust paywall pitch to "remove the per-action cap."
- **c)** Keep current code; just paywall copy changes. Lowest engineering cost — but the brand-integrity cost is the highest of the three.

**My recommendation:** **b)**. Honors the stated freemium principle (scan visible, actions gated) and keeps a clear, fair conversion lever. The user can clean up modestly without paying; bulk users hit the lever exactly where it makes sense.

---

### Q2. If you picked Q1=b or Q1=c, what's the cap?

(Skip if Q1=a.)

**For Q1=b (batch limit):** "single delete only" / 5 / 10 / "no batch on first scan, batch on subsequent"
**For Q1=c (group limit):** keep 3 / raise to 10 / raise to 20

**Engineering consequence:** One-line constant in `PhotosViewModel.swift:63`. Paywall pitch tweaks.

**My recommendation:** if Q1=b, **single-delete only on free** — the cleanest line ("free deletes one at a time, premium handles many at once"). Easy to explain, easy to defend.

---

### Q3. The new space-first workflows in #71 (large videos, old screenshots, screen recordings) — what tier?

**Options:**
- **a) All free** — every category visible, single-item delete free
- **b) Free preview, premium batch** — visible + single-delete free, bulk action premium
- **c) Premium only** — gated entirely behind the paywall

**Why it matters:** Per market doc §4.4, *"I freed up 12GB today!"* is one of the top viral triggers — the share-with-a-friend moment. If we gate the whole feature behind premium (c), free users never have that moment, and the word-of-mouth loop weakens. (a) and (b) preserve it.

**Engineering consequence:** Decides the gate placement in the new Photos sub-views #71 will introduce. Affects whether the launch demo can show storage wins before the paywall fires.

**My recommendation:** **b)**. Same lever as Q1: single-item delete free (trust + viral moment), batch premium (real time-saver). Consistent across the photo experience.

---

### Q4. The upgraded similar-photo detection in #70 (real perceptual hashing, "keep best" reasoning) — what tier?

**Options:**
- **a) Free** — the marketing copy already promises "we compare photos pixel by pixel"; #70 fixes the truth gap
- **b) Premium** — it's net-new advanced functionality
- **c) Free for grouping, premium for "why this is the keeper" reasoning**

**Why it matters:** The market doc trust pillar is *"transparency: show your work — real numbers, not estimates."* The current copy commits us to a level of detection we don't actually do. #70 makes the promise true. Charging for that fix is a bait-and-switch — exactly the pattern §2.1 calls out scam apps for.

**Engineering consequence:** Decides the gate placement in the new analyzer logic #70 introduces. Affects which `groupReason` cases (`exactDuplicate`, `similarShots`, `burstSequence`) are visible to free users.

**My recommendation:** **a)**. Fixing a stated promise isn't a premium feature; it's table stakes. Premium earns its keep on Q1, Q3, Q5, Q6.

---

### Q5. Non-photo features — which are free, which are premium?

For each surface, pick: **F** (free), **P** (premium), or **PF** (visible free, action premium):

| Surface | Current state | Your call |
|---|---|---|
| **Contact merge** (find + merge duplicates) | Premium gate on the merge action | F / P / PF |
| **Battery trend chart** (history older than 24h) | Premium | F / P / PF |
| **Privacy Audit detail** (per-permission deep insights, recommendations) | Free summary, premium for guided action | F / P / PF |
| **Guided Cleanup flows** (step-by-step wizards) | Premium | F / P / PF |
| **Storage breakdown** (category drill-down) | Free | F / P / PF |

**Engineering consequence:** Each cell maps to the `PremiumGateModifier` placement in the corresponding view file (`ContactsView.swift`, `Battery/BatteryTrendChart.swift`, `Dashboard/PrivacyAuditCard.swift`, `GuidedCleanup/Flows/*.swift`, `StorageView.swift`).

**My recommendation:**
- Contact merge: **PF** — finding duplicates is the trust-building insight; merging the heavy work is what premium earns. Symmetric with photo Q1.
- Battery trend: **PF** — current state. 24h free, longer history premium. Anchored in market doc §4.2 pain point #6 ("the battery doesn't last like it used to" → information helps, history is the deeper insight).
- Privacy detail: **F** — the market doc moat is *"unified privacy audit"* (§5.1). Gating the unified view weakens the moat. Premium sells the *fix* (guided action), not the *info*.
- Guided Cleanup: **P** — this is the calm-expert experience itself. *"My son set this up for my phone and I love it"* (§4.4) — the guided flow is what justifies the recommendation. Worth paying for.
- Storage breakdown: **F** — already free, anchors the trust. Don't touch it.

---

### Q6. Is "batch action + undo history" the central premium lever?

**Options:**
- **a) Yes** — batch action (delete more than 1 thing at once) and undo history older than 24h are premium across photos, contacts, and storage
- **b) No** — gate by feature category instead

**Why it matters:** Market doc §5.2 calls undo *"the superpower."* Premium that *expands* the undo window (24h → 30d) and adds *speed* (batch) sells what the brand already says is special, instead of inventing new artificial walls. It's the cleanest pitch and the easiest to maintain — `PremiumGateModifier` is applied at one capability level, not many feature levels.

**Engineering consequence:** Determines whether `PremiumGateModifier` is applied at the *capability* level (one place, one truth) or the *feature* level (many places, drift over time). One-place is dramatically simpler.

**My recommendation:** **a)**. It's the cleanest implementation, the cleanest pitch, and the most defensible against a user accusing the app of hiding basics.

---

### Q7. What does the paywall sheet lead with?

The paywall headline + first paragraph. Pick one frame (or a combination):

- **a) Photos** — "Clean up thousands of photos in seconds." (Photos-led.)
- **b) Breadth** — "PhoneCare takes care of the whole phone — photos, contacts, battery, privacy." (Aligned with market doc §5.1 differentiator: "single pane of glass that Apple hasn't built.")
- **c) Safety** — "Every cleanup is reviewable, recoverable, and never tries to scare you into a purchase." (Aligned with the calm-expert brand and the anti-scareware promise.)
- **d) Time** — "Stop dragging through cleanup. PhoneCare's batch tools finish in one tap." (Premium = your time back.)

**Why it matters:** This is the line a user reads at the moment of decision. The market doc §4.3 is explicit: trust is destroyed by alarm language and built by plain language + transparency. (a) is fine but narrow. (b) sells the moat. (c) sells the brand. (d) sells the premium value directly.

**Engineering consequence:** Edits to `PaywallViewModel.swift` (headline + body strings) and `PaywallBottomSheet.swift` (visual hierarchy).

**My recommendation:** **(d) Time** as the headline + **(b) Breadth** as the supporting paragraph. Together they sell archetype D directly: *"PhoneCare Premium does the heavy lifting — batch cleanups across photos, contacts, and storage, plus 30 days of undo history. Skip the dragging through long lists."* Plain English, no fear, no exclamation, matches §4.3 trust pillars.

---

### Q8. Trial — keep 7-day free trial across all three plans?

**Options:**
- **a) Keep 7-day on all three** (current state)
- **b) 7-day on annual + monthly, no trial on weekly** (weekly at $0.99 is already a near-trial)
- **c) Shorter trial (3-day) on all three**
- **d) Trial only on annual** (annual is the conversion target)

**Why it matters:** Market doc §1.2 cites *"78% of trial-converters convert in the first week"* — week one is everything. The trial window has to be long enough for the user to actually run a scan, see results, and feel value before deciding. 3 days is too short for the 40+ audience who don't open utility apps daily.

**Engineering consequence:** StoreKit 2 product configuration in App Store Connect (no code change, but `ProductCardView.swift` reads the trial offer per product). Configuration is final at submission.

**My recommendation:** **(b)**. Weekly with a trial is essentially "try free for 14 days," which Apple's review sometimes flags as gaming. A weekly tier with no trial is still cheap enough to be a try-it option.

---

## What happens after you answer

Mark up this doc inline (write your answer next to each Q) or reply in chat as `Q1: a, Q2: skip, Q3: b, ...`. Either works.

Once I have the answers:

1. I file a follow-up implementation issue for each tier change that touches code (typically one per question that crosses a file boundary). Each gets its own branch and PR per the standard one-PR-per-issue workflow.
2. I update #74 with the resolved policy and close it.
3. I add a comment on #70 and #71 with the tier placement so their implementation plans scope correctly.
4. I draft the paywall copy as part of the Q7 implementation PR — you and your partner review the actual strings before merge.
5. I update onboarding paywall sequencing if the archetype shifts paywall placement in the 11-screen flow.

---

## What's *not* in this doc

- **Pricing changes.** $19.99/yr is treated as fixed. If you also want to revisit pricing, that's a separate decision doc; do it as a second pass after tier policy locks.
- **Legal-URL hosting (#145).** Deferred per current direction.
- **Post-launch features (#18 Family Mode).** Out of scope for the launch decision.
- **App Store submission checklist (#47) / E2E StoreKit testing (#46).** Process work, separate from tier policy.

---

## TL;DR if you only have 2 minutes

My honest recommendation, all eight answers in one block:

> **Archetype D — quality-gated, anchored in the market doc's stated freemium principle.**
> Q1: b (free + single-delete, batch premium)
> Q2: single-delete only on free
> Q3: b (free preview + single-delete, premium batch)
> Q4: a (free — fixing what the copy already promised)
> Q5: Contacts PF, Battery PF, Privacy F, Guided P, Storage F
> Q6: a (yes — batch + undo history is the lever)
> Q7: (d) Time headline + (b) Breadth supporting
> Q8: b (no trial on weekly)

Whether you take this or not, the *structural* recommendation stands: **answer the eight questions before any work on #70 or #71 starts.** Otherwise we're guessing at the wrong scope, and the bigger risk — accidentally shipping a paywall that violates the calm-expert brand — sits in the gap between intent and code.

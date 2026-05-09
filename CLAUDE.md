# PhoneCare iOS

## Project Overview
PhoneCare is an iOS utility app that provides honest phone maintenance — storage cleanup, duplicate photo/contact management, battery health monitoring, and privacy audits. It targets iPhone users aged 40+ who are frustrated by predatory scam cleaner apps. The app charges $19.99/year vs competitors' $400+/year.

**Tagline:** "Your phone, taken care of."

## Technical Stack
- **Platform:** iOS only (iPhone), Swift, SwiftUI
- **Minimum iOS:** iOS 17+
- **Architecture:** MVVM with SwiftUI
- **Data:** 100% on-device storage. NO backend, NO external auth, NO external database, NO cloud sync
- **Subscriptions:** StoreKit 2 (mandatory — no RevenueCat or third-party wrappers)
- **Icons:** SF Symbols only (no custom icon assets for in-app icons)
- **Font:** SF Pro only (system font — no custom fonts)
- **Analytics:** Zero third-party SDKs. Apple Analytics only (opt-in)

## Key Apple Frameworks
- PhotoKit — duplicate/similar photo detection
- Contacts framework — duplicate contact detection and merge
- UIDevice / ProcessInfo — battery health and thermal state
- StoreKit 2 — subscriptions and paywall
- WidgetKit — home screen widgets (post-launch)
- UserNotifications — local notifications only (post-launch)

## Architecture Rules
- All data persistence uses a local store (SwiftData or Core Data — team's choice)
- All scans/heavy work must run on background threads — never block the UI
- Support Dynamic Type across ALL text (non-negotiable for 40+ audience)
- Support VoiceOver on every interactive element
- Support Dark Mode with the documented color palette
- Respect Reduce Motion system setting

## Design System (from Style Design Document)

### Colors — NEVER use red/orange for storage warnings or health scores
| Token | Light | Dark | Usage |
|-------|-------|------|-------|
| color.primary | #0A3D62 | #5DADE2 | Brand blue, nav bars |
| color.accent | #1A8A6E | #58D68D | CTAs, success, health |
| color.background | #F8F9FA | #1C1C1E | Screen backgrounds |
| color.surface | #FFFFFF | #2C2C2E | Cards |
| color.textPrimary | #2C3E50 | #F2F2F7 | Body text |
| color.textSecondary | #95A5A6 | #8E8E93 | Metadata |
| color.warning | #F39C12 | #F5B041 | Genuine warnings only |
| color.error | #E74C3C | #EC7063 | True errors only |

### Spacing (8pt grid)
- xs: 4pt, sm: 8pt, md: 16pt, lg: 24pt, xl: 32pt, xxl: 48pt

### Corner Radii
- sm: 8pt (badges), md: 12pt (buttons), lg: 16pt (cards)

### Touch Targets
- Minimum 44pt (Apple HIG). PhoneCare standard: 50pt for primary CTAs
- List rows: 56pt minimum, 64pt for actionable rows

### Buttons
- Primary CTA: #1A8A6E bg, white text, 50pt height
- Secondary: #E8F8F5 bg, #1A8A6E text, 50pt height
- Destructive: white bg, #E74C3C text, 50pt height (always with confirmation dialog)

## Navigation
Flat tab bar with 5 tabs (no hamburger menus, no drawers):
1. Home (heart.text.square.fill) — Dashboard
2. Storage (internaldrive.fill) — Storage breakdown
3. Photos (photo.on.rectangle.fill) — Photo cleanup
4. Privacy (lock.shield.fill) — Permission audit
5. Settings (gearshape.fill) — Account & settings

## Feature Tiers (Free vs Premium)
- **Free:** View all scan data, health scores, storage breakdown, first 3 duplicate groups
- **Premium:** Cleanup actions, batch operations, undo support, full duplicate lists, guided flows, trend charts

## Anti-Scareware Rules (CRITICAL — these are brand-defining)
- NEVER use red/orange for storage warnings or health scores
- NEVER show fake virus/threat alerts
- NEVER show paywall before delivering real scan value
- NEVER hide the dismiss/close button on paywall
- NEVER use fear-based language ("at RISK", "DANGER")
- Health score colors: green spectrum (51-100), amber (0-50), NEVER red
- Always show "Not now" clearly on paywalls
- All destructive actions require explicit confirmation + undo window

## Content & Language Rules
- Write at 6th-grade reading level maximum
- Use plain English: "space" not "storage allocation", "photos that look the same" not "duplicate assets"
- Tone: calm, clear, encouraging — like a knowledgeable friend
- Every destructive action gets plain-English confirmation with item count and size

## Subscription Products (StoreKit 2)
- Weekly: $0.99/week (no trial; weekly is already a near-trial price point per Q8 of docs/free-vs-premium-decision-2026-05-06.md)
- Monthly: $2.99/month (7-day free trial)
- Annual: $19.99/year (7-day free trial), DEFAULT, pre-selected

## MVP Features (Launch)
1. F1: Phone Health Dashboard — composite health score, card-based layout
2. F2: Storage Analyzer — category breakdown with charts
3. F3: Duplicate & Similar Photo Finder — scan, review, batch delete, undo
4. F4: Duplicate Contact Merger — scan, side-by-side compare, merge, undo
5. F5: Battery Health Monitor — current status, daily snapshots, trend chart
6. F6: Privacy Audit — permission summaries, deep links to Settings
7. F7: Guided Cleanup Flows — step-by-step wizards
8. F8: Onboarding & Personalization — 11-screen flow, value before paywall
9. F9: Paywall & Subscription (StoreKit 2)
10. F10: Settings & Subscription Management

## App Store Review Compliance (from docs/apple-review-docs/)
- NO placeholder content, "coming soon", broken links, or dead-end screens
- All permission `NSUsageDescription` strings must be clear and specific
- Privacy nutrition labels must be 100% accurate (we collect zero user data)
- StoreKit 2: clear pricing, renewal terms, cancellation info displayed before purchase
- "Restore Purchases" button must be easy to find (in Settings + onboarding)
- Trial-to-paid transitions must be transparent (7-day trial, clear what happens after)
- NO private/undocumented APIs (battery health max capacity NOT available via public API — deep link to Settings instead)
- NO AI data sharing (we're 100% on-device — no consent modal needed)
- Dynamic Type, VoiceOver, Dark Mode are active review criteria
- Screenshots must match real app UI exactly
- Build with latest SDK before submission
- Provide sandbox test account with active subscription for reviewer

## Development Workflow
- Use plan mode for complex features before implementing
- Break features into small, testable increments
- Write unit tests for all business logic (health score calculation, duplicate detection, etc.)
- Test with VoiceOver and Dynamic Type before considering any feature complete
- Use subagents for parallel independent tasks

## Reference Documents
All detailed specifications are in `docs/inital-project-docs/`:
- `PhoneCare - Project Management Document.docx` — full feature specs, acceptance criteria, timeline
- `PhoneCare - Style Design Document.docx` — complete design system, colors, typography, components
- `Competitive Market Research - iOS Phone Maintenance Apps.docx` — market analysis
- `initial idea.docx` — original concept and market gap analysis

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
- **Q8 - Family Mode deferred indefinitely.** CloudKit-shared architecture conflicts with the on-device-only commitment above. Issue #18 left open as a future-consideration ticket.

### Where to read more

- `docs/free-vs-premium-decision-2026-05-06.md` for full reasoning behind each Q-decision in the free vs premium policy.
- `docs/launch-decisions-2026-05-07.md` for full reasoning behind each launch-readiness decision.
- `docs/issue-triage-2026-05-04.md` for the upstream triage workup that surfaced the Q-questions.
- `docs/qa-smoke-test.md` for the real-device smoke-test checklist.
- `.github/copilot-instructions.md` for build / IPA / CI rules and the same product-decision summary, kept in sync with this file.

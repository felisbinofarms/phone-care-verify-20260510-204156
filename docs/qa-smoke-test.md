# PhoneCare QA Smoke Test

A 30 to 45 minute walk-through of the golden paths plus the most likely regression sources. Use this on a real device before any TestFlight cut or App Store submission.

Tick each box as you go. If something fails, stop, capture a screenshot or screen recording, file an issue, and keep going.

## 1. Setup

- [ ] Real iPhone running iOS 17 or later
- [ ] StoreKit Configuration loaded in the Run scheme (or a sandbox Apple ID is signed in)
- [ ] Test photo library has at least:
  - 5 visually-similar shots (e.g. burst from one moment, or near-duplicates from a recent event)
  - 2 exact duplicates (same shot saved twice)
  - 5 screenshots spanning at least three of: This Week, Last Month, Older than 30 Days, Older than 90 Days
  - 2 screen recordings
  - 3 large videos over 250 MB each
- [ ] Test contact list has at least 2 duplicate contacts (same phone number under different names, or same email)
- [ ] Notifications permission has not been answered yet on this install

## 2. Onboarding (11 screens)

- [ ] Fresh install (delete the app first if needed) opens onto the welcome screen
- [ ] All 11 screens advance without a stuck state, broken layout, or missing button
- [ ] Goal selection (multiple choice) saves the selected goals
- [ ] Phone-feeling step records the choice
- [ ] Tech-savvy level records the choice
- [ ] Permission prompts appear at the right step (Photos, Contacts, Notifications)
- [ ] Scan progress UI advances through stages: storage, photos, contacts, battery, privacy
- [ ] Personal plan reflects the scan results in plain English
- [ ] Final screen completes and lands on the dashboard

## 3. Dashboard

- [ ] Health score color is green or amber, never red or orange
- [ ] Card order respects the goals selected in onboarding
- [ ] Each card shows useful summary content, not placeholder text
- [ ] Tapping a card deep-links into its detail view
- [ ] No "AT RISK" or "DANGER" wording anywhere

## 4. Photos

- [ ] Five categories visible in the picker: Duplicates, Screenshots, Blurry, Large Videos, Screen Recordings
- [ ] Sort picker visible at the top of Large Videos, Screen Recordings, and Screenshots
- [ ] Default sort selected: biggest-first for Large Videos and Screen Recordings, oldest-first for Screenshots
- [ ] Toggling sort reorders the list as expected
- [ ] Screen recordings appear in the Screen Recordings category, not in Large Videos
- [ ] Each duplicate group shows the GroupReason chip (icon plus plain-English text)
- [ ] Each duplicate group shows a keep-best reason in italic caption text under the group
- [ ] Tapping Keep Best, Select Rest pre-selects the duplicates and leaves the suggested keeper unselected
- [ ] Batch delete: select 2 or more photos, confirm, the system delete dialog appears, photos move to Recently Deleted
- [ ] Undo toast shows after a confirmed delete

## 5. Contacts

- [ ] Scan finds the seeded duplicate group
- [ ] Side-by-side compare shows both contacts with all fields
- [ ] Merge combines fields without losing data
- [ ] Merged contact appears in the system Contacts app
- [ ] Undo within the 30-day window restores the original contacts

## 6. Battery

- [ ] Current state visible (level, charging, low power mode if on)
- [ ] At least one snapshot recorded for today
- [ ] Trend chart visible on premium; gated for free
- [ ] Tip cards render correctly
- [ ] Thermal state color is accent or warning, never error

## 7. Privacy Audit

- [ ] Each permission row shows current status
- [ ] Tapping a row deep-links into the system Settings app at the right page
- [ ] Returning to PhoneCare reflects any change made in Settings

## 8. Paywall (each of four triggers)

- [ ] User-initiated (Settings → Upgrade): always shows
- [ ] Batch delete with multiple selections (free user): friction prompt appears, paywall opens once per session
- [ ] Gated CTA (free user taps a premium feature): paywall opens once per session
- [ ] Scan milestone (proactive): paywall appears, then is suppressed for 7 days
- [ ] Every paywall has a visible Dismiss or Close control

## 9. Subscription Flow

- [ ] Three plans visible with prices and trial labels
- [ ] Annual is pre-selected by default
- [ ] Trial labels correct: "7-day free trial" on Monthly and Annual, no trial label on Weekly
- [ ] Purchase a plan via StoreKit sandbox completes the flow
- [ ] After purchase, `isPremium` flips to true and premium gates open
- [ ] Restore Purchases reachable from both Settings and onboarding
- [ ] Trial reminder notification scheduled (visible in iOS Notification settings, or via the `[TrialReminder] Scheduled` log line)
- [ ] Cancel sandbox subscription, confirm the app downgrades on the next entitlement check

## 10. Settings

- [ ] Privacy Policy link opens
- [ ] Terms of Service link opens
- [ ] Contact Support link opens
- [ ] Rate App link opens the App Store review prompt
- [ ] Dark mode toggle (System / Light / Dark) takes effect immediately
- [ ] Subscription management deep-links to the iOS subscriptions screen

## 11. Permission-Denied Paths

- [ ] Deny Photos: Photos tab shows a graceful empty state with a path to Settings, no crash
- [ ] Deny Contacts: Contacts feature explains the issue and offers a Settings deep-link
- [ ] Deny Notifications: trial reminder scheduling silently no-ops, no error shown to the user

## 12. Accessibility Spot-Checks

- [ ] Largest Dynamic Type setting (Settings → Accessibility → Display & Text Size → Larger Text → max): main screens are still readable, no truncation that hides actions
- [ ] VoiceOver: every interactive element has a label, the Photos sort picker announces "Sort order"
- [ ] Reduce Motion: any animations respect the system setting

## 13. Anti-Scareware Spot-Checks

- [ ] No red or orange used for storage warnings or health scores anywhere
- [ ] No fake virus or threat alerts
- [ ] No fear-based language ("AT RISK", "DANGER", "URGENT")
- [ ] All paywalls show "Not now" or "Close" clearly
- [ ] All destructive actions require explicit confirmation with item count and size
- [ ] All destructive actions have an undo path

## When Done

If all boxes are ticked, the app is QA-ready. File issues for any failures, ideally with a screenshot or screen recording attached. Add new sections to this doc whenever a regression slips through, so the next QA pass catches it.

# FoodLog 2.3.0

Repository release · 1 October 2026 · app version 2.3, build 5

- Native Liquid Glass bottom navigation with journal content scrolling beneath
  it, reachable final rows, and native-material fallbacks on older iOS versions.
- Automatic device authentication when locked, explicit retry after cancellation,
  and immediate, 1-minute, or 5-minute relocking. Background privacy covers also
  conceal presented drafts and keyboard predictions.
- Fasts tab beside Journal with automatic overnight estimates from consecutive
  days' last and first logged meals. Drink entries and days without logged meals
  are excluded. No manual Start/End controls or new fasting-session writes.
- Patterns displays average, latest, and range overnight estimates for 7 days,
  30 days, and All. Estimates update with meal edits, deletions, and time zones.
- Previously saved fasting records remain available. The Core Data model,
  existing entries, and food CSV formats are unchanged.
- Cancel offers Keep draft or Discard; the editor no longer contains a separate
  Discard draft button. Autosaved drafts remain protected by the app lock.

## Verification

The release configuration compiles for iPhone without signing. Earlier focused
checks passed for the 38 existing logic tests, overnight estimates after
edit/delete/relaunch, glass underlap/final-row reachability, automatic unlock,
grace-period drafts, and app-switcher privacy.

The final Fasts-tab and Patterns-summary additions have not been simulator-tested.
The accessibility audit's last finding was scrolled text blurred through the
native navigation edge; its exclusion was adjusted but not rerun. A full simulator
regression suite was intentionally not run, as requested. Real-device biometric
behavior and the older-iOS visual fallback remain manual checks.

This is a local repository tag, not a TestFlight or App Store submission.

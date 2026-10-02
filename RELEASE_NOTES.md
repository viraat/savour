# FoodLog 0.9.1

Repository release · 2 October 2026 · app version 0.9.1, build 6

Changes from `feature/fasts-copy-polish` are merged into main. Historical release
tags have been renumbered below 1.0 without changing their release commits.
No Git remote is configured; this is a local repository release, not a TestFlight
or App Store submission.

- Monthly Fasts calendar with accent-colour fills, increasing opacity for longer
  fasts, and readable numbers in light and dark mode. Select a date for details.
- Optional, adjustable fasting goal, defaulting to 14 hours. Qualifying dates
  have a silver border. The goal appears beside the shorter/longer legend as
  `>14h goal` or `>14h 30m goal`, without zero-minute suffixes.
- Compact history with dates, durations, and meal-time ranges. The latest 30
  fasts appear initially; View more appends another 30. The average of the
  displayed fasts has bold text and a distinct shaded, outlined row.
- Hourglass icon replaces the moon. Removed the This month link, duplicate
  Fasts page in Settings, and fasting card from Journal.
- Search and Filter align beside the Journal heading. The expanded search field
  uses native Liquid Glass on supported iOS versions and a material fallback.
- Journal, Fasts, Patterns, and Settings share consistent title typography and
  placement. Calendar and history explanations are not repeated on every row.
- Replaced custom bottom navigation with the system TabView, including native
  tab selection, Liquid Glass rendering, and per-tab navigation stacks. Add entry
  is now a native glass button in the page header, not part of the tab bar.
- Header, food-suggestion, photo, and date/time buttons use native glass styles on
  supported iOS versions, with native bordered styles on older versions. The
  editor's entry-actions menu opens directly instead of inside another overflow.
- Existing food entries, saved fasting records, Core Data models, draft storage,
  and CSV formats remain unchanged.

## Verification

Swift syntax checks and focused local logic checks passed for calendar layout,
daylight-saving transitions, opacity, contrast, optional/custom goals, compact
duration formatting, and 30-at-a-time pagination. UI tests were updated but not
run, including new native-tab and single-level entry-menu regression checks.
No simulator tests were run, as requested.

The release configuration builds successfully for iPhone without signing. The
earlier sandbox restriction has been removed. Visual layout, tab animations,
and native-glass appearance still need a manual check on the device.

## Historical tag renumbering

Tags `v0.1.0` through `v0.5.0` are unchanged. The replacement annotated tags
below point to the exact same historical commits; their old names have been
removed. Historical commits and app versions embedded in older builds have not
been rewritten. The old names can be recreated at the preserved commits if needed.

Versioning policy: milestone releases increment the minor component (`0.5.0`
to `0.6.0`). Smaller feature, fix, and polish releases increment the patch
component (`0.5.0` to `0.5.1`). Keep the major component at zero until the app
is ready for a 1.0 release. Build numbers continue increasing independently.

| Old tag | Replacement | Release scope | Preserved commit |
| --- | --- | --- | --- |
| v1.0.0 | v0.5.1 | Now shortcut in time editor | 1e48e2f1ca5cd1dcd1ee89bd263d258cc0f2f590 |
| v2.0.0 | v0.6.0 | UI and Patterns redesign | 1bcb3f69cdd67c347ce95abec068c8827f0840e0 |
| v2.1.0 | v0.7.0 | CSV import, migration, reliability, autocomplete | 84a8ca4183fcfcc7304f76ea09a1c810be41ff59 |
| v2.2.0 | v0.8.0 | Fasting, date picker, persistent drafts | b9ad9fbe6c8d8b8bf622cedea6055fe2e1719cc8 |
| v2.3.0 | v0.9.0 | Fasts tab, automatic estimates, biometric unlock | 756b94afbae266c81e3d19762b0fc9707c7fddb4 |

The current UI-polish release is `v0.9.1` on main, with app version `0.9.1`
and build number `6`.

# FoodLog releases

## FoodLog 0.5.2

Repository release · 2 October 2026 · app version 0.5.2, build 7

Merged `feature/bottom-add-action` into main. Add entry now uses native prominent
trailing tab placement on iOS 27, on the same row as Journal, Fasts, Patterns, and
Settings. A public UIKit selection delegate opens the existing pop-up entry sheet
and rejects selection of Add, leaving the current destination unchanged.

Earlier systems retain native tab navigation with a separate bottom-right Add
button above it: native `.glass` and `safeAreaBar` on iOS 26, bordered controls and
`safeAreaInset` on older supported versions. No custom tab background, blur,
selection animation, or frame override is introduced. Data models, entries,
drafts, fasting data, and CSV formats are unchanged.

The unsigned device Release build and device test-target compilation passed.
Regression tests were added but not executed; no simulator tests were run.
Visual placement and animations still need an on-device check.

See [CHANGELOG.md](CHANGELOG.md) for the cumulative release history. No Git remote
is configured, so this is a local repository release, not a published remote
release, TestFlight build, or App Store submission.

## FoodLog 0.5.1

Repository release · 2 October 2026 · app version 0.5.1, build 6

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
- Current fast row above the average shows the latest non-drink meal's start
  timestamp and elapsed time, refreshed every minute. It recalculates after meal
  additions, edits, deletions, and relaunch without storing a fasting session.
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

### Verification

Swift syntax checks and focused local logic checks passed for calendar layout,
daylight-saving transitions, opacity, contrast, optional/custom goals, compact
duration formatting, current-fast inference, and 30-at-a-time pagination. UI tests
were updated but not run, including native-tab, single-level entry-menu, and
current-fast relaunch/next-meal regression checks.
No simulator tests were run, as requested.

The release configuration builds successfully for iPhone without signing. The
earlier sandbox restriction has been removed. Visual layout, tab animations,
and native-glass appearance still need a manual check on the device.

## Historical tag renumbering

The initial `v0.1.0` tag is unchanged. Early MVP enhancements are `v0.1.1`
through `v0.1.5`; subsequent milestones are `v0.2.0` through `v0.5.0`.
Historical commits and app versions embedded in older builds have not been
rewritten. Some tag names now identify different releases, as documented below;
the previous naming can be restored at the recorded commits if needed.

Versioning policy: milestone releases increment the minor component (`0.5.0`
to `0.6.0`). Smaller feature, fix, and polish releases increment the patch
component (`0.5.0` to `0.5.1`). Keep the major component at zero until the app
is ready for a 1.0 release. Build numbers continue increasing independently.

| Old tag | Replacement | Release scope | Preserved commit |
| --- | --- | --- | --- |
| v0.2.0 | v0.1.1 | Individual companions | 99b60ca0cb4d6e16cc045a0818db2e625f0d27ac |
| v0.3.0 | v0.1.2 | Reusable locations and entry redesign | 209b073c04ca1a3c2fd517b48456677786e34add |
| v0.4.0 | v0.1.3 | Meal suggestions and app lock | fac4433818340a4611fb936aa50378adc7d4e988 |
| v0.5.0 | v0.1.4 | Configurable meal times | de0a52537c8dfefa5f909b4df8aa5eda3cce6d7c |
| v0.5.1 (originally v1.0.0) | v0.1.5 | Now shortcut in time editor | 1e48e2f1ca5cd1dcd1ee89bd263d258cc0f2f590 |
| v0.6.0 (originally v2.0.0) | v0.2.0 | UI and Patterns redesign | 1bcb3f69cdd67c347ce95abec068c8827f0840e0 |
| v0.7.0 (originally v2.1.0) | v0.3.0 | CSV import, migration, reliability, autocomplete | 84a8ca4183fcfcc7304f76ea09a1c810be41ff59 |
| v0.8.0 (originally v2.2.0) | v0.4.0 | Fasting, date picker, persistent drafts | b9ad9fbe6c8d8b8bf622cedea6055fe2e1719cc8 |
| v0.9.0 (originally v2.3.0) | v0.5.0 | Fasts tab, automatic estimates, biometric unlock | 756b94afbae266c81e3d19762b0fc9707c7fddb4 |

The UI-polish release was tagged `v0.5.1`, with app version `0.5.1`
and build number `6`. It includes the Current fast summary added while the
release renumbering was in progress. The former `v0.9.1` tag has been retired;
its commit `4f947ead42eb5cfe68800579f777098c0ef4981b` remains in main's history.

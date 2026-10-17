# Savour releases

Savour was previously named FoodLog. Historical releases below retain their
original name; see [CHANGELOG.md](CHANGELOG.md) for the cumulative release history.

## Savour 0.7.1

Repository release · 17 October 2026 · app version 0.7.1, build 18

A patch release that makes Settings → Your data → iCloud sync easier to understand.

- **Clearer status.** Status now shows Off, Syncing, Synced, Waiting to sync,
  Sync stopped, or an iCloud account problem, instead of "iCloud sync enabled".
- **Last sync.** The time of the last successful sync is kept between launches
  and cleared when sync is turned off.
- **Account and conflicts.** A new row shows whether this device is signed in to
  iCloud, and a new section explains what happens when two devices change,
  delete, or restore the same entries.
- **Simpler wording.** The page, alerts, and error messages use short, plain
  sentences. "iCloud storage is full" is now recognised when CloudKit reports it
  inside a partial failure.
- **Removed "Check iCloud status".** Account status already refreshes
  automatically.

Verification: see the build/releases/0.7.1 verification record.

## Savour 0.7.0

Repository release · 17 October 2026 · app version 0.7.0, build 17

Log food through Siri or a custom shortcut, with the same journal storage and
optional iCloud sync as entries made in the app.

- **Log Food action.** Say “Log food in Savour” and answer what you ate, or pass
  text from Dictate Text in a custom shortcut. Food is required; time defaults
  to now and the meal category follows the existing time-based suggestion.
- **Optional details.** Custom shortcuts can provide a date, category, place,
  individual companions, and note. The action returns the saved food text.
- **Setup in Settings.** Meals → Siri & Shortcuts includes a Siri tip, a link
  to Shortcuts, and instructions for building a custom shortcut.
- **Authentication and drafts.** The device must be unlocked. App lock requires
  authentication before saving; shortcut entries preserve unfinished drafts.
- **Siri phrase indexing.** The app declares its development language so Xcode
  generates the English Siri phrase index.

Verification: the Savour simulator build, all 177 iOS unit tests (including eight
new shortcut tests), and the targeted Siri & Shortcuts setup UI test passed.
The signed iPhone Release archive and App Store export passed; the exported IPA
has version 0.7.0 (17), production CloudKit/APNs entitlements, and compiled Siri
phrase metadata.
Siri speech recognition and real authentication prompts still require an iPhone
check. Live iCloud sync and restoring a real backup from the old app on a device
remain unverified.

## Savour 0.6.3

Repository release · 13 October 2026 · app version 0.6.3, build 16

A patch release that turns Patterns' When chart into a per-meal time spread,
removes the What card, regroups Settings → Your data, and improves food
suggestions.

- **Time spreads in Patterns.** For 30 days and All, When shows one row per meal
  type: a line from earliest to latest, a bar for the usual middle half and a
  tick at the median. 7 days keeps one dot per meal. All now uses all history.
- **What card removed.** Patterns no longer has the What card; "Different foods"
  stays in Overview.
- **Clearer Your data.** Settings → Your data groups CSV (Import, Export; no
  photos) and Full backup (Export, Restore). Erase all entries sits on its own.
- **Better food suggestions.** Items eaten together with those already added
  come first, after anything matching what you type.
- **Export compliance.** Info.plist declares ITSAppUsesNonExemptEncryption = NO,
  so App Store Connect skips the export-compliance question.
- **Test fix.** The CSV share-sheet UI test waits for iOS 27's file caption.

Verification: Mac SwiftPM suites passed. On an iPhone 18 Pro simulator
(iOS 27.0), the affected unit and UI tests passed, including the accessibility
audits on Settings, Journal and Patterns. The full UI suite was not re-run for
this release.

**Known issue:** on a hardware keyboard (including a Mac keyboard in the
Simulator), Return does not add a food chip; the on-screen Return key and a
comma do.

**Still not verified:** live iCloud sync and restoring a real backup from the
old app on a device.

This is a local tagged repository release, not a TestFlight build or App Store
submission. It has not been pushed.

## Savour 0.6.2

Repository release · 12 October 2026 · app version 0.6.2, build 15

A patch release that reworks the Journal's weekly card and the Patterns tab,
and makes the fasting average cover a recent period.

- **Eating rhythm on the Journal.** "This week" shows one column per day with a
  dot per meal at its time, coloured by meal type. Tap a day to jump to it.
- **Patterns by when, what, where and who.** A meal-time chart with each meal's
  usual time and the overnight gaps; usual, new and different foods; the map
  and people, with how often meals were out or shared. The streak and the
  Entries/Days tiles are gone; one "N meals over N days" line opens the overview.
- **Recent fasting average.** The Fasts average covers the last 7 days by
  default. Settings → Fasting → Average over offers 7, 14 or 30 days, or All.
- **Accessibility.** The rhythm chart is a single VoiceOver element that reads
  each day's meals; chart text uses the app's readable grey; new rows have
  44 pt targets.

Verification: Mac SwiftPM suites passed. On an iPhone 18 Pro simulator
(iOS 27.0), the new and affected unit and UI tests passed, including the
accessibility audits on the Journal and Patterns. The full UI suite was not
re-run for this release.

**Known issue:** on a hardware keyboard (including a Mac keyboard in the
Simulator), Return does not add a food chip; the on-screen Return key and a
comma do.

**Still not verified:** live iCloud sync and restoring a real backup from the
old app on a device.

This is a local tagged repository release, not a TestFlight build or App Store
submission. It has not been pushed.

## Savour 0.6.1

Repository release · 12 October 2026 · app version 0.6.1, build 14

A patch release with fixes and iOS 27 test updates on top of 0.6.0.

- **Faster "Erase all entries".** Fasting links are detached in one pass over a
  single fetch instead of refetching every fast for each meal. Recorded fasts,
  targets and unrelated links are kept, and the erase still saves or rolls back
  as a whole.
- **CSV export fix.** Exporting from an in-memory store no longer raises an
  uncatchable Core Data exception. App stores are on disk and still export from
  a consistent snapshot.
- **iOS 27 accessibility.** The Fasts calendar keeps its legends' and days' own
  identifiers, history rows are single VoiceOver buttons again, and "Erase all
  entries" uses a darker red in light mode (about 5.7:1 contrast).
- **iOS 27 UI tests updated** for the new search Close button, share sheet,
  overlapping tab frames and relaunch behaviour. `imports/` is git-ignored so
  personal journal CSVs aren't committed.

Verification: all Mac SwiftPM suites passed and both schemes build. On an
iPhone 18 Pro simulator (iOS 27.0), the full unit suite and every previously
failing UI test passed on this code.

**Still not verified:** live iCloud sync and restoring a real backup from the
old app on a device (see 0.6.0).

This is a local tagged repository release, not a TestFlight build or App Store
submission. It has not been pushed.

## Savour 0.6.0

Repository release · 11 October 2026 · app version 0.6.0, build 13

A milestone release: Savour moves to its own Xcode project and app identity,
gains full backups and optional iCloud sync, and changes how food is entered.

- **Food items as chips.** Return, a comma or a suggestion adds an item; tap a
  chip to remove it or long-press to edit. An empty field suggests the meal's
  usual items. Items are still stored as comma-separated text, so existing
  entries, CSV, backups, sync and Patterns are unchanged.
- **Full backup and restore.** Settings → Your data exports a ZIP with every
  entry, person and original photo, and restores it without overwriting
  existing or conflicting records. Use it to move your journal to the new app.
- **Optional iCloud sync** (off by default) for the new Savour app, using your
  private iCloud database. Drafts and preferences stay on the device.
- **New project and identity.** `Savour.xcodeproj` replaces `FoodLog.xcodeproj`.
  The Savour target uses `tech.buildboring.Savour` (team `829WP93FV4`) and
  installs alongside the old `com.viraat.foodlog` app, which the FoodLog target
  still builds. Moving data across is done with backup and restore.
- **iOS 17 or later is now required.** Deprecated `onChange` and `Map` APIs and
  the iOS 16 fallbacks were removed; both schemes build without warnings.
- **Fixes and polish.** On iOS 27 the screen no longer ends in a blank strip
  above the home indicator. Fasts shows the latest 7 estimates with View more.
  "Open Savour in Settings" opens Savour's own settings page. The meal-labels
  setting and the Privacy footer were removed, and the credit and version moved
  to the bottom of Settings.

Verification: all Mac SwiftPM suites passed, and the unsigned iPhone Release
build of the Savour scheme succeeded. On an iPhone 18 Pro simulator (iOS 27.0),
the full unit and UI suites ran on the food-chip changes with 193 passing; the
remaining failures were all pre-existing (including the known `/dev/null` CSV
export test and several UI tests that need updating for iOS 27).

**Not yet verified:** live iCloud sync. Xcode had no signed-in account, so the
CloudKit container, schema and syncing between two devices are untested; see
`ICLOUD_SYNC.md` before enabling it or shipping to TestFlight. A real backup
from the old app restored into the new app on a device has also not been tested.

This is a local tagged repository release, not a TestFlight build or App Store
submission. It has not been pushed.

## Savour 0.5.7

Repository release · 6 October 2026 · app version 0.5.7, build 12

Performance and correctness fixes on top of 0.5.6:

- Draft autosaves wait 0.5 seconds after typing stops instead of rewriting the
  photo-bearing draft file on every keystroke; lifecycle and close paths still
  save immediately.
- CSV import reuses date formatters and JSON encoders, serializes existing
  entries once and prefetches companions instead of faulting them per entry.
- The legacy-entry repair runs once per store, recorded in store metadata,
  instead of fetching every entry on every launch.
- Changing an existing or explicitly timed entry's meal type keeps its
  timestamp; meal default times apply only to untouched new entries.
- Journal and editor photos are downsampled to their display size and cached.
  Cached previews show on the first frame, photo-less rows skip photo reads and
  the cache entirely, and reopened editors reuse the saved photo's preview.

All Mac SwiftPM suites passed. On an iPhone 17 Pro simulator (iOS 26.3.1), the
full unit and UI suites ran on 0.5.6 main and on this release's photo changes:
both failed the same 17 tests, so these changes introduced no new failures.
Those 17 pre-existing failures need separate investigation; both suites shared
one simulator concurrently, which may account for some UI flakiness. One is a
known test-only crash: `testAsyncCSVExportUsesSavedEntriesWithoutSavingUnfinishedEdits`
uses a `/dev/null` store that cannot support the export's query generation;
the same test passes against an on-disk store.

Full backup/restore remains separate on `codex/full-backup-restore`, now updated
with main but not merged. The Settings/Fasts polish on
`codex/settings-fasts-polish` is not included. This is a local tagged repository
release, not a TestFlight build or App Store submission. It has not been pushed.

## Savour 0.5.6

Repository release · 6 October 2026 · app version 0.5.6, build 11

Merged `codex/performance-caching` into main. Autocomplete reuses a local index;
journal grouping, fasting estimates, patterns and people/place suggestions reuse
bounded, view-owned snapshots. They refresh when underlying entries or relevant
filters/calendar state change. Layouts, draft recovery and stored data are unchanged.

This release also includes the previously merged Your data/About Settings detail
pages and CSV export reliability fix: a progress indicator, ready-file sharing,
explicit errors and timestamped filenames.

All 35 Mac reminder/performance tests passed. Debug app/test-target compilation
and the unsigned iPhone Release build passed. No simulator run or on-device
profiling was performed; CSV/UI regressions are compile-checked, not executed.

Full backup/restore remains separate on `codex/full-backup-restore` and is not
included. This is a local tagged repository release, not a TestFlight build or
App Store submission. It has not been pushed or published remotely.

## Savour 0.5.5

Repository release · 4 October 2026 · app version 0.5.5, build 10

Merged `codex/fasts-footer-polish` into main. The estimates explanation at the
bottom of Fasts uses a smaller native caption font and adaptive gray text. The
history section's bottom separator is hidden. Dynamic Type, light/dark mode,
meal calculations and stored data are unchanged.

Full backup/restore remains unmerged on `codex/full-backup-restore`.
The unsigned iPhone Release build and Debug test-target compilation passed.
No simulator run or visual verification was performed.

This is a local tagged repository release, not a TestFlight build or App Store
submission. It has not been pushed or published remotely.

## Savour 0.5.4

Repository release · 3 October 2026 · app version 0.5.4, build 9

Merged `codex/meal-logging-prompt` into main. The live summary now says
“Time since last logged meal,” with “Last meal” labeling its timestamp and matching
VoiceOver wording. Its longer heading uses a wrapping row layout.

After more than 24 elapsed hours it shows “Time since last meal: too long” and a
“Log a meal” button opening the same draft-aware entry sheet as Add. Exactly 24
hours keeps the elapsed summary. Logging another meal resets it; drinks do not.
No food entry is created before Save.

Full backup/restore is not included: it remains on `codex/full-backup-restore`,
rebased onto this main release. Entries, Core Data models, drafts and CSV formats
are unchanged.

The unsigned iPhone Release build and Debug test-target compilation passed.
All 21 Mac reminder regression tests passed. New threshold/UI regressions were
compiled but not executed, and no simulator run was performed.

This is a local tagged repository release, not a TestFlight build or App Store
submission. It has not been pushed or published remotely.

## Savour 0.5.3

Repository release · 3 October 2026 · app version 0.5.3, build 8

Includes the stacked `codex/native-navigation-refinements`,
`codex/grouped-settings`, and `codex/daily-notifications` branches, plus the
previously merged Savour rename.

- Cleaner native grouped Settings, inline Dime attribution, and a centered
  bottom footer: “Built with ❤️ by Viraat” above the app version and build.
- Up to three optional daily meal reminders with independent native time
  pickers, add/remove actions, duplicate prevention, and safe single-reminder
  migration. Notifications stay off until enabled; permission is requested in
  context. The iOS notification-settings button is always available.
- Stable local notification identifiers, serialized scheduling, cancellation,
  and rollback or safe disable on partial scheduling failures. Notification
  content contains no journal or draft details.
- Space-saving native same-row root titles, native Journal search/filter,
  clearer fasting averages/goal semantics, and native statistical count charts.
- Hosted-page accessibility fixes and stronger Settings/Cancel contrast.
- Existing entries, Core Data models, drafts, saved fasting records, bundle
  identifier, and food-entry CSV formats are preserved.

### Verification

All 21 reminder logic tests passed on the Mac. The final unsigned iPhone Release
build and Debug test-target compilation passed. The earlier explicitly requested
one-time Settings simulator checks are documented in [TESTING.md](TESTING.md).
No additional simulator run was performed for this release. Latest title/footer
layout, contrast re-audit, and actual notification permission/delivery behavior
remain device/simulator checks; compiled UI regressions were not executed.

This is a tagged repository release, not a TestFlight build or App Store submission.

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

# Savour reliability tests

Savour has two XCTest targets (the project and target names remain `FoodLog`):

- `FoodLogTests` checks parsing, meal suggestions, statistics, default times,
  inline food matching and replacement, CSV validation, import round-trips,
  empty exports and duplicate handling, concise place
  formatting, migration from every stored model version, and biometric lock
  lifecycle transitions, cancellation, relock boundaries, and clock changes.
  Overnight estimates cover first/last meal selection, Drink exclusions, missing
  days, time-zone changes, daylight-saving transitions, and recalculation after
  edits/deletion without modifying saved fasting sessions.
- `FoodLogUITests` checks add, edit, delete, relaunch persistence, explicit meal
  defaults, inline autocomplete, time controls, denied Contacts and Location behavior, biometric
  automatic unlock/retry, relock settings and grace-period draft preservation,
  app-switcher content shielding, glass underlap and final-row reachability,
  map-pin selection, CSV preview/import, appearance changes,
  long food names, keyboard reachability, and accessibility semantics.

UI tests launch the app with `--ui-testing` and use a separate
`FoodLogUITests.sqlite` store in the test app container. Resetting this store
does not affect the normal app store. Map and CSV fixtures, denied Contacts and
Location paths, and biometric denial use explicit debug launch arguments, so
the UI suite does not depend on a simulator's permission history.

## Run the automated suite

### Release 0.5.5 — 2026-10-04

App version `0.5.5`, build `10`, adds smaller adaptive-gray Fasts footer text and
removes its section's bottom separator. The unsigned iPhone Release build and
Debug test-target compilation passed. No simulator run or visual verification
was performed. Full backup/restore is excluded from this release.

### Release 0.5.4 — 2026-10-03

App version `0.5.4`, build `9`, includes the meal-summary wording and over-24-hour
logging action only. Backup/restore remains on its separate feature branch.
The unsigned iPhone Release build, Debug app/test-target compilation and 21 Mac
reminder tests passed. New regressions cover the exact 24-hour boundary, the next
logged meal resetting it, drinks not resetting it, and opening the existing
entry sheet from Fasts. These regressions are compile-checked, not executed;
no simulator run was performed.

### Release 0.5.3 — 2026-10-03

Final app metadata is version `0.5.3`, build `8`. All 21 Mac reminder tests,
the unsigned iPhone Release build, and Debug test-target compilation passed.
No new simulator run was performed for this release. The latest same-row titles,
About footer and notification-settings-link UI regressions are compile-checked,
not executed. Real notification delivery and the Settings contrast re-audit
remain pending opt-in simulator/device verification.

### Backup and restore without a simulator

The root Swift package builds the actual export/restore code, compiles all five
Core Data model versions and tests private, disposable Mac SQLite stores. It does
not read or restore the user's app journal. ZIPFoundation 0.9.20 is pinned in
both SwiftPM and the Xcode project. No new simulator run has been performed.
On 2026-10-03, all 26 backup/restore tests and 21 reminder tests passed, as did
the unsigned iPhone Release build and Debug app/test-target compilation.

```sh
swift test --scratch-path /private/tmp/savour-reminder-logic-build
```

Backup tests cover full-field/relationship/photo round-trips, exact dates and
coordinates, nil/empty binary values, orphan records, duplicate/missing UUIDs,
stable object references, photo deduplication, unsaved UI edits, all previous
model versions, repeated restores, conflicting graphs, journal changes after
preview, store reopening, cancellation, rollback, malformed schemas/values,
unknown versions/entities, dangling relationships, unsafe/duplicate paths,
symlinks, missing photos, checksum failures and temporary-file cleanup.

Settings backup controls are compile-checked UI regressions, not executed. Real
Files/iCloud providers, share-sheet completion/cancellation, large journals,
biometric locking while sheets are open and actual phone restoration remain
pending an explicitly requested device/simulator check.

### Reminder logic without a simulator

The root Swift package builds the reminder service, autocomplete/cache, draft and
backup logic. The reminder target builds only `FoodReminder.swift` and its tests;
it has no external dependencies and does not build/launch the iOS UI. All permission and
notification clients/preferences in these tests are in-memory fakes; they
neither display a real permission prompt nor schedule a real notification.

```sh
swift test --scratch-path /private/tmp/savour-reminder-logic-build
```

All 21 tests passed on the Mac on 2026-10-03. They cover default-off behavior,
permission grant/denial/revocation/provisional status, custom and midnight times,
preserving legacy morning/evening/custom schedules on upgrade, persistence across
model recreation, invalid preferences, independent replacement, the three-time
cap, duplicate prevention, removal/reindexing and stale-request cleanup,
disable/cancel without removing unrelated notifications, partial scheduling
failures/rollback failures, and Disable queued during a slow permission request.
Calendar components omit
fixed dates/time zones and notification content excludes all journal details.

The native iOS Notifications screen and added UI regressions are build-checked,
not simulator-tested. Real permission prompts, notification delivery after
force-quitting, Focus/Scheduled Summary behavior, notification taps through App
Lock, and delivery after time-zone/DST changes still need an opt-in simulator or
device check. No extra simulator run was performed for this feature.

### Performance caching without a simulator — 2026-10-04

```sh
swift test --scratch-path /private/tmp/savour-performance-logic-tests
```

All 14 performance tests and 21 reminder tests passed. The performance target
compiles the actual `FoodLogLogic.swift` and `FoodHistoryCache.swift`, using private
in-memory Core Data stores, not the user's journal. It verifies ranking and
segment replacement against a frozen copy of the original suggestion engine,
normalization/deduplication, meal selection, limits, recency, cache reuse, input
key changes, meal/companion edits and deletion, background-import merges,
undo/redo, rollback/reset, context switching, and day/timezone/range changes.

The diagnostic Mac microbenchmark uses 3,000 synthetic meals sharing five foods
and eight queries. The measured query batch took about 1.03 seconds rebuilding
the original candidates versus 0.35 milliseconds with an already-built index;
initial index construction is excluded from the latter. There is no flaky timing
assertion or claimed app-wide speedup. Real-device Instruments profiling remains
pending; no simulator was launched. The Debug app/test targets and unsigned
iPhone Release configuration compile successfully.

This first pass changes autocomplete and derived-data caching only. Draft I/O
and photo decoding are deliberately unchanged to preserve recovery behavior.

Native navigation/search/statistics regressions cover system page titles,
same-row inline-large root headings aligned with Journal search/filter controls,
Clear versus Cancel, retaining Journal queries across the Add sheet, accessible
count bars without task-progress semantics, inclusive goal labels, and an
all-completed-fasts average unaffected by View more or calendar navigation.
These new UI regressions are compile-checked during routine work, not run unless
simulator testing is explicitly requested.

Settings-layout coverage retains all existing controls and the five accent
choices, checks selection persistence, and exercises access to meal defaults,
fasting goals, privacy, CSV actions, and attribution in the grouped form.
The About inline attribution, centered credit/version/build footer, and access
to iOS notification settings before enabling are also covered by compile-checked
UI regressions. These latest layout changes have not been simulator-tested.

### One-time settings verification — 2026-10-03

At the user's request, targeted tests ran on a fresh **Savour Settings QA**
iPhone 17 Pro simulator with iOS 27.0 (24A434). Existing simulator stores and
their unfinished drafts were left untouched. This is not standing authorization
to run simulator tests during routine work.

- All 55 logic tests passed on the updated implementation, including migration,
  CSV, drafts, fasting, suggestions, and biometric lifecycle logic.
- Nine focused UI regressions passed: existing settings/accent persistence,
  fasting goal controls, relock persistence, map/appearance, native page titles,
  light/dark layout, tab selection/modal Add, automatic authentication/retry,
  and concealment of an unfinished draft behind a denied lock.
- Settings light/dark layout checks passed at normal and the largest
  accessibility text size. Screenshots of upper/lower sections were inspected;
  native rows wrap and the final action remains reachable above the tabs.
- A separate hierarchy regression confirmed that native navigation titles and
  settings controls are exposed through the UIKit/SwiftUI hosting boundary.
  Replacing the whole hosting environment had hidden this content from
  accessibility; explicit app-environment forwarding fixed it. Native pickers
  expose selected accent through their accessibility **value**, not their label;
  offscreen Form rows are virtualized, so tests reveal them before inspecting.

**Accessibility audit remains open:** the strict grouped-settings audit reports
an iOS 27 contrast “nearly passed” finding with no identified element. Its
attachment and screenshot were inspected, but no specific offending control
could be established; the check is not exempted or described as passing.
The primary-screen audit separately reports contrast on the existing editor's
Cancel control. Functional passes and screenshot review are not a full
accessibility sign-off. The full UI suite was not run.

Follow-up polish uses higher-contrast semantic label colors for app-owned
Settings headings/secondary text and a neutral tint on the native editor Cancel
action. No audit exceptions were added. These changes need an opt-in simulator
re-audit before either finding can be marked resolved.

Result bundles and light/dark/large-text attachments for this local run are in
`/private/tmp/savour-settings-sim.2xAMDZ`. Normal text size was restored afterward.

During routine development, prefer a build and targeted logic checks. Run the
full simulator suite only when explicitly requested; the commands below are
available for that opt-in verification.

Choose an available simulator in Xcode and press **Product → Test**, or run:

```sh
xcodebuild -project FoodLog.xcodeproj \
  -scheme FoodLog \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO test
```

The test run completed on:

- iPhone 17 Pro, iOS 26.3.1: complete unit and UI suites
- iPhone 16e, iOS 26.3.1: CRUD, relaunch, defaults, map, appearance, and lock
- iPhone 16e, iOS 18.6: complete unit and UI suites, including appearance fallback

The navigation/editor smoke test also passed on the iPhone SE (3rd generation),
iPhone 13 mini, iPhone 11 Pro, iPhone 16 Plus, iPhone Air, and iPhone 17 Pro Max.
These cover the available 4.7-, 5.4-, 5.8-, 6.5-, 6.7-, and 6.9-inch screen
classes in addition to the 6.1- and 6.3-inch full-suite devices. The SE and
17 Pro smoke tests also passed at the largest accessibility text size.

On iOS 26, the UI suite audits the journal, editor, and settings in light and
dark mode for contrast, hit regions, element descriptions, and clipped text.
It also audits a populated journal and the Patterns/map screens. MapKit's canvas
can trigger a contrast result with no identified element, so those map screens
retain the other three audit checks. On iOS 18, XCTest similarly reports
screen-wide contrast/clipping failures with no element, so its automated audit
checks hit regions and descriptions; light/dark screenshots were inspected.
The audit also excludes the system search placeholder, MapKit's own legal link,
and content scrolling behind the bottom bar. Dynamic Type is checked with the
simulator's actual largest content-size setting, because the XCTest audit
reports custom SwiftUI tab labels as partially unsupported even when their
size changes correctly.

## Draft autosave debounce — 2026-10-06

`swift test --scratch-path /private/tmp/savour-draft-debounce-tests` runs nine
new draft tests plus 21 reminder and 14 performance tests (44 total). They cover
coalescing 100 rapid changes, resetting the idle timer, immediate background/Keep
draft saves, full-field/photo restoration through a fresh store, preserving other
edit drafts, cancelling writes before Discard/Save/Delete cleanup, and reporting
write failures with a successful retry. Lifecycle tests mirror the editor's
cancel-then-synchronous-save sequence; they do not exercise actual iOS lifecycle
callbacks or a Core Data journal save. Test delays are shortened; production uses
500 milliseconds. The archive format and synchronous store are unchanged.

Debug app/test-target compilation and unsigned iPhone Release build passed.
No simulator was launched. Actual backgrounding, biometric interruption,
interactive dismissal and abrupt process termination remain device checks.
With debounce, an abrupt crash/kill without a lifecycle callback can lose typing
from the last half-second; inactive/background/close paths save immediately.

## CSV formatter reuse and single-pass indexing — 2026-10-06

`swift test --scratch-path /private/tmp/savour-csv-performance-tests` runs nine
CSV tests, 14 performance tests and 21 reminder tests (44 total, all passed).
The CSV tests execute the actual Foundation helpers used by preview/commit:
3,000 lazy existing rows are serialized exactly once; UUID/content/legacy and
within-file duplicate rules, precise timestamp and structured-people identities,
validation errors, strict legacy date parsing, DST and independently captured
time zones remain covered. A 3,000-row quoted/newline CSV decodes unchanged.

An informational Mac test of 1,000 row validations measured about 0.56 seconds
with a newly constructed formatter bundle per row versus 0.11 seconds reusing
one operation-local bundle. There is no timing assertion; this compares the
new helper's per-row and reused modes, not whole-app or on-device performance.

Debug app/test-target compilation and unsigned iPhone Release build passed.
The Core Data batch-export/stale-preview commit regression and prior import
tests are compile-checked, not executed. No simulator was launched. Import
preview and commit deliberately retain their existing threading/transaction
behavior; large-file UI responsiveness still needs on-device verification.

### Companion prefetch follow-up

CSV performance follow-up (2026-10-06): the real file-import UI and its DEBUG
fixture now use a context-based preview overload. Both that overload and commit
fetch through `existingEntriesRequest()`, whose relationship prefetch includes
`companions`; background export uses the same request. Each batch owns one
JSONEncoder, and the row's people display text comes from the same names array
as people_json. A new app-model test checks prefetch configuration, row parity
after context reset, comma/quote/newline companion names, preview duplicates,
successful commit and stale-preview duplicate rechecks. It is compile-checked,
not executed. All 44 Mac tests and both build checks passed; no simulator run.
Import still runs on the existing context thread; no meal-type rules changed.

## Store-local legacy migration completion — 2026-10-06

`swift test --scratch-path /private/tmp/savour-migration-marker-tests` executes
ten new marker tests plus 14 performance and 21 reminder tests (45 total, all
passed). Temporary SQLite stores verify that the marker survives close/reopen
after both actual repair changes and no-op/empty migrations. Tests also cover
data/photo/UUID preservation, skip without fetching/saving pending objects,
migration/data-save failures, injected metadata-save failure with cache reset
and retry, version advances, unrelated metadata, multiple stores, replacement
at the same URL and rejecting a foreign coordinator's store. Marker tests use a
minimal programmatic model and a repair closure, not the app's historical models.

The existing FoodLog V1–V4 upgrade tests now verify the real startup marker and
reopen/skip behavior while retaining their entry/relationship/photo/CSV checks.
Those app-model regressions are compile-checked, not executed. Debug app/test
compilation and unsigned iPhone Release build passed; no simulator was launched.

The marker is written after data repair succeeds, using an explicit empty
`NSSaveChangesRequest` to flush metadata without dummy journal objects. Apple's
[store metadata guidance](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreData/PersistentStoreFeatures.html)
explains that an instance metadata update needs a store save to reach disk.
Automatic schema migration and manual unconditional repair remain separate;
increment the repair version when adding future data-integrity transformations.

## Meal type changes preserve intentional timestamps — 2026-10-06

`swift test --scratch-path /private/tmp/savour-entry-time-tests` executes eight
new timestamp-policy regressions plus 14 performance and 21 reminder tests
(43 total, all passed). The editor uses the actual `FoodEntryTimeSelection`
policy tested here: relabelling an existing 21:40 entry preserves even its
seconds; confirming a manual date disables later defaults; restored new/edit
drafts preserve their saved times. Untouched new entries still use standard
and custom meal defaults on the same day, and Snack/Drink/Other do not change
time. Explicitly confirming an unchanged time also preserves that choice.

UI regressions cover existing-entry relabelling/save/reopen, changing meal type
after using the Date & time sheet, and restored-draft meal changes. They are
compile-checked, not executed. Debug app/test compilation and unsigned iPhone
Release build passed; no simulator was launched. No draft fields, Core Data
schema, migration or stored timestamps were altered by this fix.

## Combined performance branch verification — 2026-10-06

After merging draft autosave debounce, CSV import performance, the store-local
migration marker and intentional timestamp preservation into main:

- `swift test --scratch-path /private/tmp/savour-merged-performance-tests`:
  all 71 Mac tests passed (21 reminders, 41 performance/CSV/migration/timestamp,
  and nine draft autosave tests).
- Debug `build-for-testing` passed for the app and both iOS test targets.
- Unsigned generic iPhone Release build passed.

No simulator was launched. App-model and UI regressions were compiled, not
executed. Existing test-target linker warnings about XCTest's newer minimum
iOS version remain. Backup/restore stays on its separate feature branch.

## Display-sized photo previews — 2026-10-06

`swift test --scratch-path /private/tmp/savour-photo-thumbnail-tests` passed all
87 Mac tests, including 16 new photo tests. These execute the actual ImageIO
decoder, actor-owned cache and Core Data photo-reading/version logic. Debug
app/test compilation and unsigned iPhone Release build also passed. No simulator
was launched and no phone profiling was performed; SwiftUI view behavior was
compile-checked rather than exercised interactively.

The decoder follows Apple's [Image and Graphics Best Practices](https://devstreaming-cdn.apple.com/videos/wwdc/2018/219mybpx95zm9x/219/219_image_and_graphics_best_practices.pdf)
ImageIO downsampling approach. Tests use real generated JPEGs: a 1,600×1,200 photo
becomes a 168×126 aspect-fill thumbnail for the 42 pt journal row at 3× scale,
with a decoded footprint below 100 KB. That is a preview-size check, not an
app-wide memory/performance measurement. Editor previews use their actual width
and screen scale. Extreme outputs are capped at 2,048 pixels.

Cache hits do not invoke the original-data loader. Committed photos are read
using a private context that is reset after each read; the journal object remains
faulted in the regression. Inserted/unsaved photo replacements and removals use
the owning context without saving. Photo-only changes, merged updates,
rollback/refresh/delete/reset invalidate versions; ordinary local note changes
do not. Memory-warning cache purges cannot be undone by an older pending load.
Original JPEGs and schema are unchanged, so the first uncached preview still
reads its original bytes. Camera/Photos acquisition processing is unchanged.

## Manual device checks

Some system integrations need a real device or direct Simulator interaction:

1. Enable App Lock and confirm Face ID or Touch ID starts without tapping Unlock,
   both after a cold launch and after the relock delay. Check all three relock
   settings, including just before and after the 1-minute and 5-minute limits.
   The journal must never appear before successful authentication.
2. Cancel or fail authentication and confirm the lock screen remains visible
   without repeated prompts; Unlock retries. Leave a draft open with the keyboard
   visible and check the app-switcher snapshot conceals both the sheet and its
   keyboard predictions. Return within a grace period and confirm the draft is
   intact. Automated biometric results are injected; real sensor behavior still
   requires this device check.
3. Grant Contacts and confirm matching names and available thumbnails appear;
   revoke access and confirm free-text companions still work.
4. Grant Location, select a MapKit result, and confirm Savour saves only place
   name and city. Revoke access and confirm free-text place entry and MapKit text
   search remain available.
5. Take a photo and choose one from Photos, relaunch, then edit and remove it.
6. Export CSV and inspect it in Numbers or another CSV reader. Import it into a
   fresh app store, review the preview, and verify the entries. Import it again
   and confirm the entries are marked as duplicates.
7. With VoiceOver enabled, navigate the journal, open an entry, edit its fields,
   and verify the tab buttons, entry row, filters, map pin, and settings controls
   have understandable labels and actions. Repeat at the largest text size and
   with Increase Contrast enabled on a physical device.
8. Log yesterday's last meal and today's first meal. Check the Fasts tab reports
   the elapsed time without needing Start or End. Add Drink entries before or
   after them and verify the estimate is unchanged. Edit or delete a boundary
   meal and verify the estimate updates. Change time zone and return to Savour
   to check grouping follows local calendar days. Previously saved fasting
   records should still be present; missing meal days must not create estimates.
   In Patterns, check average, latest, and range estimates for 7 days, 30 days,
   and All; the prior day's last meal must be included at a range boundary.
9. In Settings → Notifications, confirm no permission prompt appears until
   Enable notifications is switched on. Test Allow and Don't Allow, then change
   permission in iOS Settings and return. Configure one, two, and three times;
   check that a fourth cannot be added and duplicate times cannot be set. Verify
   midnight times, independent time edits, swipe-to-remove, three reminders at
   most after repeated changes/relaunch, and none after disabling. Saved times
   should remain when disabled. Upgrade a previous single-reminder configuration
   (morning, evening, custom; both enabled and disabled) and confirm that only its
   original time is retained. With near-future times, background/force-quit Savour
   and check delivery. Change time zone and check it follows local clock time.
   With App Lock enabled, notification content must contain no journal/draft
   data, and tapping it must require normal authentication.

Automated tests cover export to a fresh Core Data store, repeat imports,
legacy CSV, mixed valid and invalid rows, and text with commas, quotes, and line
breaks. The preview sheet and its import action have UI coverage; the system
file picker still needs a manual device check.

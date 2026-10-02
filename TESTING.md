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

Native navigation/search/statistics regressions cover system page titles,
Clear versus Cancel, retaining Journal queries across the Add sheet, accessible
count bars without task-progress semantics, inclusive goal labels, and an
all-completed-fasts average unaffected by View more or calendar navigation.
These new UI regressions are compile-checked during routine work, not run unless
simulator testing is explicitly requested.

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

Automated tests cover export to a fresh Core Data store, repeat imports,
legacy CSV, mixed valid and invalid rows, and text with commas, quotes, and line
breaks. The preview sheet and its import action have UI coverage; the system
file picker still needs a manual device check.

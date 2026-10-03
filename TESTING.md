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

### Reminder logic without a simulator

The root Swift package builds only `FoodReminder.swift` and its tests. It has no
external dependencies and does not build/launch the iOS UI. All permission and
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

Native navigation/search/statistics regressions cover system page titles,
Clear versus Cancel, retaining Journal queries across the Add sheet, accessible
count bars without task-progress semantics, inclusive goal labels, and an
all-completed-fasts average unaffected by View more or calendar navigation.
These new UI regressions are compile-checked during routine work, not run unless
simulator testing is explicitly requested.

Settings-layout coverage retains all existing controls and the five accent
choices, checks selection persistence, and exercises access to meal defaults,
fasting goals, privacy, CSV actions, and attribution in the grouped form.

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

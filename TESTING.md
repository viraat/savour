# FoodLog reliability tests

FoodLog has two XCTest targets:

- `FoodLogTests` checks parsing, meal suggestions, statistics, default times,
  CSV validation, import round-trips and duplicate handling, concise place
  formatting, and migration from every stored model version.
- `FoodLogUITests` checks add, edit, delete, relaunch persistence, explicit meal
  defaults, time controls, denied Contacts and Location behavior, biometric
  content shielding, map-pin selection, CSV preview/import, and appearance changes.

UI tests launch the app with `--ui-testing` and use a separate
`FoodLogUITests.sqlite` store in the test app container. Resetting this store
does not affect the normal app store. Map and CSV fixtures, denied Contacts and
Location paths, and biometric denial use explicit debug launch arguments, so
the UI suite does not depend on a simulator's permission history.

## Run the automated suite

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

## Manual device checks

Some system integrations need a real device or direct Simulator interaction:

1. Enable App Lock, background and reopen FoodLog, and confirm the journal never
   appears before successful Face ID or Touch ID.
2. Cancel or fail authentication and confirm the lock screen remains visible.
3. Grant Contacts and confirm matching names and available thumbnails appear;
   revoke access and confirm free-text companions still work.
4. Grant Location, select a MapKit result, and confirm FoodLog saves only place
   name and city. Revoke access and confirm free-text place entry and MapKit text
   search remain available.
5. Take a photo and choose one from Photos, relaunch, then edit and remove it.
6. Export CSV and inspect it in Numbers or another CSV reader. Import it into a
   fresh app store, review the preview, and verify the entries. Import it again
   and confirm the entries are marked as duplicates.

Automated tests cover export to a fresh Core Data store, repeat imports,
legacy CSV, mixed valid and invalid rows, and text with commas, quotes, and line
breaks. The preview sheet and its import action have UI coverage; the system
file picker still needs a manual device check.

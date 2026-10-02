# Changelog

Savour uses pre-1.0 semantic versioning: milestones increment the minor
component (`0.5.0` → `0.6.0`), and smaller features, fixes, and polish increment
the patch component (`0.5.1` → `0.5.2`). Build numbers increase independently.
Tags below use the renumbered release history; historical commits and the app
versions embedded in older builds were not rewritten. The original-to-current
tag mapping is recorded in [release notes](RELEASE_NOTES.md#historical-tag-renumbering).

## Unreleased

- Renamed the app from FoodLog to Savour on the Home Screen, Journal heading,
  About section, lock screen, authentication prompt, permission descriptions,
  user-facing errors, and new CSV export filenames.
- Kept the bundle identifier, Core Data models/store, draft storage, preferences,
  and CSV schema unchanged. The Xcode project and scheme remain `FoodLog`.

## 0.5.2 — 2026-10-02

App version 0.5.2 · build 7 · repository tag `v0.5.2`

### Changed

- Moved Add entry from the page header to the bottom of the app.
- On iOS 27, Add sits on the same row as the four navigation tabs using the
  system tab controller's prominent trailing placement. Custom selection
  handling opens the existing entry sheet without selecting a blank Add page
  or changing the current Journal, Fasts, Patterns, or Settings destination.
- Tab layout, Liquid Glass rendering, and selection animations remain native;
  no custom blur, tab-bar sizing, or selection indicator is used.
- On iOS 26, Add is a round native glass button above the system tabs, integrated
  with scroll edge effects through `safeAreaBar`. Earlier iOS versions use
  native bordered controls and `safeAreaInset`.
- Forwarded the SwiftUI environment through native tab hosting controllers so
  Core Data, appearance, accent, scene phase, locale, and Dynamic Type continue
  to update. Existing journal data, drafts, fasting data, and CSV formats are
  unchanged.

### Verification

- Added delegate tests for Add interception and ordinary tab selection, plus UI
  regressions for placement, sheet dismissal, Journal search preservation, and
  reaching the final entry above the controls.
- Unsigned device Release build and device test-target compilation passed.
  Tests were not executed and no simulator tests were run, as requested.
- Same-row visual layout and native animations still need an on-device check.

## 0.5.1 — 2026-10-02

App version 0.5.1 · build 6 · repository tag `v0.5.1`

- Added monthly accent-colour fasting calendar fills and optional fasting goals
  with silver borders for qualifying dates.
- Added compact, paginated fasting history, a distinct average row, and a
  minute-updating Current fast summary derived from the latest non-drink meal.
- Aligned page headings and Journal search/filter controls; removed redundant
  fasting navigation and repeated explanatory labels.
- Adopted native tab navigation and glass button styles; fixed the nested
  entry-actions overflow menu.
- Renumbered repository releases below 1.0 while preserving historical commits.

## 0.5.0

- Added a dedicated Fasts tab and fasting summaries in Patterns, calculated
  automatically from consecutive days' last and first non-drink meals.
- Added automatic biometric authentication, configurable relock delays, and
  background privacy shielding; adopted Liquid Glass styling.

## 0.4.0

- Added optional fasting sessions, the quick-adjustment wheel date/time picker,
  and persistent drafts for new and edited food entries.

## 0.3.0

- Added CSV import preview, validation and duplicate detection, round-trip
  handling, data migration/integrity work, reliability tests, and inline
  autocomplete for individual comma-separated foods.

## 0.2.0

- Redesigned the journal and entry experience; added the Patterns interface.

## 0.1.5

- Added the Now shortcut to the time editor.

## 0.1.4

- Added configurable default meal times.

## 0.1.3

- Added meal suggestions and biometric app locking.

## 0.1.2

- Added reusable locations and redesigned the entry editor.

## 0.1.1

- Added individual companions.

## 0.1.0

- Initial FoodLog MVP.

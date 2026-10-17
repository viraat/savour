# Changelog

Savour uses pre-1.0 semantic versioning: milestones increment the minor
component (`0.5.0` → `0.6.0`), and smaller features, fixes, and polish increment
the patch component (`0.5.1` → `0.5.2`). Build numbers increase independently.
Tags below use the renumbered release history; historical commits and the app
versions embedded in older builds were not rewritten. The original-to-current
tag mapping is recorded in [release notes](RELEASE_NOTES.md#historical-tag-renumbering).

## Unreleased

- Removed the "Check iCloud status" button; the account status already refreshes automatically.
- Clearer iCloud sync status: Off, Syncing, Synced, Sync stopped, Waiting to sync and account states.
- The last sync time is now saved between launches, shown as "Last sync", and cleared when sync is turned off.
- Added an iCloud account row and a section that explains how conflicts between devices are resolved.
- Rewrote the iCloud sync copy and error messages in simpler language. Errors wrapped in a partial failure now show the right message.

## 0.7.0 — 2026-10-17

App version 0.7.0 · build 17 · repository tag `v0.7.0`

- Added **Log Food** to Siri and Shortcuts. Say “Log food in Savour” and provide
  the food, or build a shortcut with an optional date, meal type, place,
  companions, and note. Entries default to now and the existing meal suggestion.
- Added Settings → Meals → Siri & Shortcuts with a Siri tip, Shortcuts link,
  and setup instructions. Logging requires an unlocked device, respects App
  lock authentication, and preserves unfinished editor drafts.

## 0.6.3 — 2026-10-13

App version 0.6.3 · build 16 · repository tag `v0.6.3`

- Food suggestions now favour items you've eaten together with the ones
  already added: after "Dosa", "Sambar" and "Chutney" come before breakfast's
  usual toast. Matching what you type still comes first, and with nothing added
  the ranking is unchanged (meal type, then frequency, then recency).
- Patterns' When chart keeps one dot per meal for 7 days, but 30 days and All
  now show one row per meal type: a line from earliest to latest, a bar for
  the usual middle half and a tick at the median. All uses all history rather
  than the last 30 days. Drinks are left out of the spread.
- Removed Patterns' What card (usual items, new foods and the All foods list)
  and the leftover streak note in Overview. "Different foods" stays in Overview.
- Settings → Your data groups CSV (Import, Export) and Full backup (Export,
  Restore) under their own headings, each saying what it includes: CSV has no
  photos. Erase all entries sits on its own at the bottom.
- Info.plist declares `ITSAppUsesNonExemptEncryption = NO`, so App Store
  Connect skips the export-compliance question for each build. Savour only uses
  Apple's OS encryption (HTTPS, CloudKit, data protection) and SHA-256 hashes to
  check backup integrity, which are exempt.

## 0.6.2 — 2026-10-12

App version 0.6.2 · build 15 · repository tag `v0.6.2`

- The Fasts average now covers the last 7 days by default instead of every
  completed fast. Settings → Fasting → Average over offers 7, 14 or 30 days, or
  All. The average still ignores the month shown in the calendar, and says so
  when no fasts ended in the chosen period.
- The Journal's "This week" card shows the week's eating rhythm instead of a
  logging count: one column per day, a dot per meal at its time, coloured by
  meal type. Tapping a day scrolls the journal to it.
- Patterns is organised around Savour's four questions. **When**: a meal-time
  chart for the range, each meal's usual time and the overnight gaps. **What**:
  usual items per meal, new foods and the number of different foods. **Where**
  and **Who**: the map and people, with how often meals were out or shared. A
  single "N meals over N days" line opens the daily overview.
- Removed the streak, which conflicted with Savour's no-streaks principle, and
  the Entries/Days tiles. Pattern calculations live in `FoodPatternInsights`
  with 11 Mac tests; chart legends and axes use the app's readable grey.
- The rhythm chart is one VoiceOver element with a spoken summary of each day's
  meals and times, and the new Overview and All foods rows have 44 pt targets.

## 0.6.1 — 2026-10-12

App version 0.6.1 · build 14 · repository tag `v0.6.1`

- iOS 27 accessibility fixes: the Fasts calendar is an accessibility container,
  so its legends and day buttons keep their own identifiers; history rows are
  single buttons again for VoiceOver; and "Erase all entries" uses a darker red
  in light mode (about 5.7:1 instead of system red's 3.6:1).
- Updated UI tests for iOS 27: search's Cancel is now "Close", the share sheet's
  identifier is the system's, native tab frames overlap at their edges, and the
  edit-draft relaunch test backgrounds the app before a forced kill. Contrast
  audits excuse only iOS 27's false positives on Liquid Glass toolbar text
  buttons and findings with no element. All previously failing UI tests pass.
- Erase all entries now collects meal UUIDs once and detaches matching fasting
  links in one pass over a single session fetch, instead of refetching all fasts
  per entry. Recorded fasting times, targets and unrelated links remain intact;
  detachment and deletion still save or roll back together. Added three app-model
  regressions, including 3,000 meals and rollback. These tests compile; all 71
  existing Mac tests and Debug/Release builds passed. No simulator run.
- CSV export skips the query-generation snapshot for in-memory (`/dev/null`)
  stores, which raised an uncatchable Core Data exception. App stores are on
  disk and still export from a snapshot. The export test now uses an on-disk
  store, and a new test covers in-memory export. The full unit suite and the
  bulk-erasure tests now pass on the iOS 27 simulator.
- `imports/` is git-ignored so personal journal CSVs kept there aren't committed.

## 0.6.0 — 2026-10-11

App version 0.6.0 · build 13 · repository tag `v0.6.0`

- Food entry now uses item chips, like companions. Return, a comma or a
  suggestion adds an item; tapping a chip removes it and long-press offers Edit.
  Pasted lists split into chips, half-typed text is kept on save, and an empty
  field suggests the meal's usual items. Items are still stored as the existing
  comma-separated text, so entries, CSV, backups, sync and Patterns are unchanged.
- Added four Mac tests for item joining, comma/line-break splitting, duplicate
  handling and suggestion input, and a UI test for adding, removing, saving and
  reopening chips. UI tests read the full description from `food-items`.

- Added opt-in private iCloud sync to the new-account Savour target, with account/
  transfer status in Settings → Your data. Meals, photos, places, people and
  preserved legacy fast sessions mirror through NSPersistentCloudKitContainer;
  drafts and preferences stay local. Enable/disable takes effect after restart.
- Added FoodLogV6 lightweight migration, background remote-history merging,
  conservative identical-UUID graph coalescing and safe handling of an entry
  deleted remotely while being edited. Existing store paths, backups and CSV
  formats remain unchanged. Apple provisioning/real-device verification remain
  pending; see [iCloud setup](ICLOUD_SYNC.md).
- Savour now requires iOS 17. Every target pins IPHONEOS_DEPLOYMENT_TARGET 17.0
  instead of Xcode's recommended value. `onChange` uses the two-parameter form,
  the Patterns map uses the iOS 17 `Map`/`Annotation` API, and the iOS 16
  title, search and Add-button fallbacks were removed. Both schemes build with
  no warnings.
- Removed the unused Xcode template from Savour.xcodeproj: the `Savour/`
  "Hello, world!" stubs and the placeholder SavourTests/SavourUITests targets.
  Unit and UI tests run from the FoodLog scheme.
- The fasting pagination test now follows `FastingHistory.pageSize` instead of
  assuming pages of 30.
- Fixed a blank strip at the bottom of the screen on iOS 27. The native tab
  controller was inset to the safe area, so scrolling content stopped above the
  home indicator. It now fills the screen; UIKit still insets each page. This
  affected every release since 0.5.2's iOS 27 tab bar.
- Added Settings → Your data → Export full backup and Restore full backup.
  `SavourBackup-v1` ZIP archives contain a typed JSON object graph, stable UUIDs,
  precise dates, meal types, all place/coordinate/people/note fields, companion
  relationships and original photo bytes. Fasting records are excluded;
  automatic fast estimates are recalculated from restored meals. Existing older
  manually saved fasting records are left untouched.
  CSV import/export remains unchanged. Drafts and preferences are not included.
- Restore validates schema, archive paths, CRCs, attachment sizes/checksums and
  relationship inverses before showing a read-only preview. Confirmation adds
  missing records atomically; identical records are skipped and conflicting
  meals/people graphs are left unchanged. Rechecks the journal at confirmation,
  supports every previous model version, and rolls back on validation/save errors.
- Backups use private, file-protected temporary files and native share/file
  pickers. Export never saves unfinished edits. ZIPs are not encrypted.
  ZIPFoundation 0.9.20 (MIT) is pinned for bounded, validated archive reading.
- Verification: 26 Mac backup/restore tests and 21 reminder regression tests
  passed; unsigned iPhone Release build and Debug test-target compilation passed.
  No simulator run, real Files-provider interaction or phone restore was performed.
- After a successful restore, the legacy-entry repair runs on the restored
  journal, because the store's migration marker skips that repair at launch.
- The SwiftPM manifest keeps exactly one target per source and test file; only
  the backup target compiles the Core Data model, as a resource.
- Removed the "Show meal labels in journal" setting; journal rows always show
  the meal type after the time, which was already the default.
- "Open notification settings" became "Open Savour in Settings" and opens
  Savour's own page in iOS Settings. It appears only after notification
  permission has been requested, because before that iOS has no Savour
  notification page and fell back to the system-wide list.
- The Fasts history shows the latest 7 estimates; View more adds 7 at a time.
- Moved the "Built with ❤️ by Viraat" credit and version/build to the bottom of
  Settings. About Savour keeps the Dime credits and license attribution.
- Removed the Privacy footer about background hiding and launch authentication.
- Added bottom padding below the Settings credit/version footer so its last line
  stays clear of the floating tab bar and Add button.
- Notification UI tests tap the switch itself; on iOS 26+ a Form toggle spans
  its row and tapping the row's center lands on the label without toggling.

## 0.5.7 — 2026-10-06

App version 0.5.7 · build 12 · repository tag `v0.5.7`

- Polished photo previews. Journal rows and the editor show an already cached
  preview on their first frame, and a changed photo keeps its previous preview
  visible until the replacement decodes, instead of flashing the meal icon.
  The journal finds photo-bearing entries with one ID-only query per refresh, so
  photo-less rows never read the store or occupy preview-cache slots. Editor
  previews of an entry's saved photo reuse its photo version and are cached
  across reopenings; newly picked or recovered photos decode without entering
  the shared cache. The editor now also observes photo-version changes.
- Added two Mac regressions for synchronous cache lookups and the photo-ID query,
  including unsaved photo additions/removals and leaving photo bytes unloaded.

- Replaced full-size journal/editor photo decoding during rendering with
  display-sized ImageIO previews decoded on a utility task. Journal cache misses
  read committed photos on a private Core Data queue without loading them into
  the journal's long-lived managed objects. Cache hits read no original data;
  editor previews survive typing. The memory-only cache has 24 MB/200-item limits,
  coalesces requests and handles photo changes, removal, rollback, refresh/reset,
  merged updates and memory warnings. Original photos, drafts and the data model
  are unchanged; the first uncached preview still needs to read the original.
- Added 16 Mac photo regressions for aspect-fill sizing, EXIF orientation,
  invalid/small/extreme images, cache reads/coalescing/purges, Core Data version
  invalidation and private-queue reads with unsaved-photo preservation. All 87
  Mac tests, Debug app/test compilation and unsigned iPhone Release build passed.
  No simulator run or on-device profiling was performed.
- Merged the draft autosave, CSV import performance, store-local migration marker
  and timestamp-preservation branches into main. Combined verification passed:
  all 71 Mac regression tests, Debug app/test compilation and unsigned iPhone
  Release build. No simulator run; app-model/UI tests were compiled only.
- Debounced entry/edit draft autosaves until 0.5 seconds after the latest change,
  instead of reading and rewriting the photo-bearing archive on every keystroke.
  Inactive/background transitions, editor disappearance and Keep draft still
  save synchronously. Save, Delete and Discard cancel pending writes to prevent
  a cleared draft from being recreated. Changes received while inactive save
  immediately. Draft format, file protection, photos and biometric shielding
  are unchanged; each actual write still uses the existing synchronous store.
  Abrupt termination without a lifecycle callback can lose the final 0.5 seconds
  of typing, while normal background/close paths flush the latest snapshot.
- Added nine draft debounce/cancellation tests using real temporary draft files
  and 300 KB photo payloads. All 44 Mac tests passed; Debug app/test compilation
  and unsigned iPhone Release build passed. No simulator run was performed.
- Prefetched `companions` with the shared existing-entry fetch used by CSV UI
  preview and commit (and background export), avoiding one relationship fetch
  per meal. Reused one JSONEncoder per existing-row batch, and derived display
  people from the already-read names instead of sorting/parsing companions twice.
  Added a compile-checked context-preview/prefetch/duplicate regression. All 44
  Mac tests and Debug app/test compilation and unsigned iPhone Release build
  passed; no simulator run. Import threading and meal-type validation are unchanged.
- Reused operation-local CSV date/time formatters across import preview,
  validation and duplicate indexing. Each existing entry is serialized once per
  preview/commit instead of twice. Bulk export and CSV document decoding also
  reuse formatters. Legacy/extended duplicate rules, precise timestamps, people,
  validation errors and commit-time duplicate rechecks are unchanged. Import
  still runs on its existing context/UI thread; this removes redundant work,
  not every possible pause during very large imports.
- Added nine Mac CSV regressions covering single-pass indexing, duplicate rules,
  validation, time zones/DST and 3,000 quoted rows. All 44 Mac tests passed;
  Debug app/test compilation and unsigned iPhone Release build passed. The new
  Core Data stale-preview/bulk-row regression is compile-checked, not executed.
  No simulator run was performed.
- Gated the launch-time legacy entry repair with a versioned, per-store Core
  Data metadata marker. Completed stores skip the repair before fetching any
  entries/companions. Migration data saves before the marker, and an explicit
  metadata-only store save persists it even for empty/already-repaired stores.
  Failed repairs or marker writes can retry. Automatic schema migration and
  explicit repair calls remain unchanged; future repairs can bump the version.
- Added ten Mac marker regressions using in-memory and real temporary SQLite
  stores, including reopen, empty/populated stores, failure/retry, independent
  stores and replacement at the same URL. All 45 Mac tests passed; Debug app/test
  compilation and unsigned iPhone Release build passed. Historical V1–V4 upgrade
  tests now check the marker and reopen path; these app-model tests were compiled,
  not executed. No simulator run was performed.
- Changing meal type no longer changes an existing entry's timestamp or a date
  confirmed in the Date & time sheet. Defaults apply only to untouched fresh new
  entries. Restored new/edit drafts and recovered edits retain their saved dates
  conservatively, without changing the draft format. Automatic default changes
  still follow later meal choices until the user explicitly confirms a date.
- Added eight Mac timestamp-policy regressions covering 21:40 snack-to-dinner
  relabelling, precise timestamps, manual choices, restored drafts, custom
  defaults and meals without defaults. All 43 Mac tests passed; Debug app/test
  compilation and unsigned iPhone Release build passed. Added/updated UI
  regressions are compile-checked, not executed. No simulator run was performed.

## 0.5.6 — 2026-10-06

App version 0.5.6 · build 11 · repository tag `v0.5.6`

- Built a reusable autocomplete index so typing no longer reparses the entire
  meal history. Prefix/substring/fuzzy matching, selected-meal ranking, frequency,
  recency, current-segment replacement and duplicate exclusions are unchanged.
- Cached journal filtering/grouping, people/place suggestions, fasting estimates
  and pattern summaries between UI updates. Snapshots refresh after meal or
  companion changes, imported/background merges, undo/rollback/reset, filter or
  calendar changes, significant time changes and returning to the foreground.
  Caches are view-owned, bounded and memory-only; layouts, draft autosaving,
  photos, stored data and lock behavior are unchanged.
- Added 14 Mac-only performance/correctness tests, including comparisons with the
  frozen original autocomplete engine. All 35 Mac tests passed. Debug app/test
  compilation and unsigned iPhone Release build passed; no simulator run or
  on-device profiling was performed. The synthetic 3,000-meal/8-query Mac
  benchmark reduced query work from about 1 second to under 1 millisecond after
  index construction; this is not an app-wide or phone-performance measurement.
- Fixed initial CSV/share-sheet presentation by presenting a ready file as the
  sheet item instead of capturing a separately updated URL. CSV export runs on
  a private Core Data queue with a Preparing CSV progress indicator and explicit
  errors. Only saved entries are exported; no draft or edit is saved by export.
- CSV filenames include a UTC timestamp and unique export identifier. Files are
  protected, never overwrite another export, and are removed after sharing or
  cancellation.
- CSV regressions cover filename stability/uniqueness, write errors, saved-only
  exports, cancellation and first-tap sharing after relaunch. App and test
  targets compile; these new tests were not executed and no simulator was run.
- Moved Your data and About Savour into their own native Settings detail pages.
  Data actions and project/library credits use matching Dynamic Type body text;
  About retains linked Dime attribution and the centered creator/version footer.
  No preferences or data formats changed.
- Debug app and test targets compile successfully. Updated navigation, CSV
  preview and accessibility UI tests; no simulator run was performed.
## 0.5.5 — 2026-10-04

App version 0.5.5 · build 10 · repository tag `v0.5.5`

- Made the Fasts estimates footer smaller with a native caption font and adaptive
  secondary-label gray, and hid its section's bottom separator. Dynamic Type
  and light/dark-mode adaptation are retained.
- Full backup/restore remains unmerged on its separate feature branch.
- Unsigned iPhone Release build and Debug test-target compilation passed;
  no simulator run or visual verification was performed.

## 0.5.4 — 2026-10-03

App version 0.5.4 · build 9 · repository tag `v0.5.4`

- After more than 24 elapsed hours since the latest logged meal, the summary
  shows “Time since last meal: too long” with a “Log a meal” button opening the
  existing draft-aware entry sheet. Exactly 24 hours retains the elapsed summary;
  drinks do not reset it. Added compile-checked boundary and UI regressions.
- Renamed the current-fast summary to “Time since last logged meal,” including
  VoiceOver wording; its timestamp is labeled “Last meal.” The longer heading
  uses the expanded row layout so it is not constrained to the date column.
- Existing entry-sheet behavior, draft restoration, meal detection and stored
  entries remain unchanged. Full backup/restore is excluded from this release
  and remains on `codex/full-backup-restore`.
- Verification: unsigned iPhone Release build, Debug app/test-target compilation
  and 21 Mac reminder regressions passed. New prompt boundary/UI regressions are
  compile-checked, not executed. No simulator run was performed.

## 0.5.3 — 2026-10-03

App version 0.5.3 · build 8 · repository tag `v0.5.3`

- Restored space-saving, same-row page headings across Journal, Fasts, Patterns,
  and Settings using native inline-large toolbar titles (compact inline on
  iOS 16). Journal search/filter remain native trailing toolbar controls; no
  separate expanded title band or custom navigation-bar imitation is used.
- Simplified About to an inline Dime attribution link and a centered bottom
  footer: “Built with ❤️ by Viraat” above the app version and build number.
  Removed reminder instruction footers and made the native iOS notification
  settings button available regardless of permission or enabled state.
- Added opt-in daily local notifications under Settings → Notifications, with
  up to three independently adjustable times using native time pickers, an Add
  reminder action, and swipe-to-remove extra times. Existing single reminders
  migrate unchanged without adding extra notifications. Off by default; permission
  is requested only when enabling. Stable repeating notifications are replaced
  on time edits and cancelled on removal/disable. A button links to iOS
  Settings; reminder text never includes journal or draft content.
- Preserved reminder choices across launches, reconciled permission/time changes,
  and serialized scheduling operations. Duplicate times are prevented; partial
  scheduling edits roll back, or safely disable reminders if rollback fails.
  Added 21 reminder logic tests runnable on the Mac without a simulator, plus
  compile-checked UI regressions. All 21 logic tests,
  unsigned device Release build, and Debug test-target compilation passed;
  no simulator run or real notification delivery test was performed.
- Strengthened contrast for Settings section headings, footnotes, and entry
  counts; the editor's native Cancel action uses neutral label tint. Prior
  simulator audit findings still require an explicitly requested re-audit.
- Reorganized existing settings into native grouped form sections with standard
  separators, aligned controls, compact appearance/accent selection rows, and
  version/attribution footers. The initial regrouping did not add or remove
  settings, preference keys, defaults, or actions. Unsigned device build and test-target compilation passed;
  one-time requested simulator verification is recorded in `TESTING.md`.
- Fixed iOS 27 hosted-page accessibility by forwarding app environment values
  explicitly instead of replacing each hosting controller's entire environment.
  Native page titles and controls are now exposed to VoiceOver/UI automation;
  Core Data, accent, appearance, scene phase, locale, and Dynamic Type still update.
- Renamed the app from FoodLog to Savour on the Home Screen, Journal heading,
  About section, lock screen, authentication prompt, permission descriptions,
  user-facing errors, and new CSV export filenames.
- Kept the bundle identifier, Core Data models/store, draft storage, preferences,
  and CSV schema unchanged. The Xcode project and scheme remain `FoodLog`.
- Replaced custom page headings with native navigation titles and moved
  Journal search/filter actions into the system toolbar. Journal now uses native
  search with separate Clear and Cancel actions and an iOS 16 search-drawer fallback.
- Made the fasting average cover all completed estimates independently of the
  selected month or visible history. Clarified estimated Current/Avg semantics
  once per page and changed the inclusive goal legend to `14h+ goal`.
- Replaced historical count progress controls with native Swift Charts bars,
  retaining readable labels/counts and accessible descriptions.
- Retained the same-row Add action and modal editor; documented its deliberate
  exception to standard tab-navigation semantics.
- Added regression coverage for native titles/search, historical count semantics,
  inclusive goal labels, and pagination-independent fasting averages. Unsigned
  device Release build and Debug app/test-target compilation passed. Routine
  verification was compile-only; explicitly requested simulator checks are
  recorded in `TESTING.md`.

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

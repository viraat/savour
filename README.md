# Savour

Savour (previously FoodLog) is a deliberately simple, private food journal for iPhone. It borrows
Dime's excellent low-friction interaction model, but records food instead of
money.

Current repository release: **0.7.1** (build 18). See the
[changelog](CHANGELOG.md) and [release notes](RELEASE_NOTES.md).

The installed app, Xcode project and new-account target/scheme are named Savour.
The new target uses `tech.buildboring.Savour`; the original `FoodLog` target and
`com.viraat.foodlog` identity remain available. Core Data model/store names,
draft filenames and preference keys stay unchanged. The new bundle ID is a
separate installation: transfer data with full backup/restore. Previously
exported FoodLog CSV files remain importable.

The app answers four questions:

- What did I eat?
- When did I eat it?
- Where was I?
- Who was I with?

There are no calorie targets, macro rings, budgets, streaks, red warnings, or
good/bad food labels. Nutrition features can remain optional additions later;
the core experience is a neutral record.

## Included in the MVP

- Fast full-screen food entry and editing
- Siri and Shortcuts food logging, with optional date, category, place, companions, and note
- Automatic meal-type suggestion based on time of day
- Configurable breakfast, lunch, and dinner times with five-minute adjustments
- Breakfast, lunch, dinner, snack, drink, and other categories
- Optional place, companions, and free-form note
- Optional nearby MapKit suggestions and reusable place quick fills
- Individual companions with optional Contacts autocomplete and photos in Patterns
- Companion quick fills and automatically inferred recurring groups
- Optional photo from the camera or system photo picker
- Inline food autocomplete for the current comma-separated item, ranked by match, meal type, frequency, and recency
- Journal grouped by day
- Fasts tab with automatic overnight-gap estimates from consecutive days' last and first meals (Drink entries excluded)
- Overnight average, latest, and range estimates in Patterns, respecting the selected date range
- Autosaved unfinished entries and edits; Cancel offers Keep draft or Discard
- Search across food, place, people, and notes
- Native navigation titles and contextual system search with separate Clear and Cancel actions
- Meal-category filtering
- Neutral visual summaries for 7 days, 30 days, and all time
- Current consecutive-day streak derived from journal entries
- Eating-place map with optional coordinate backfill for older entries
- Common places and companions
- CSV export and import with a preview of entries, duplicate detection, and row errors
- Full ZIP backups and non-destructive restore with UUIDs, relationships, photos,
  places/coordinates, people and notes; see [backup format](BACKUP_FORMAT.md)
- Light, dark, and system appearance with five saved accent colors
- Native grouped Settings sections with compact selection rows and standard toggles
- Optional meal-logging reminders: up to three custom local times each day
- Native navigation, sheets, bottom toolbars, and iOS 26 Liquid Glass styling
- Optional automatic biometric app lock, immediate/1-minute/5-minute relocking, and background privacy shielding
- Local-first Core Data storage with no account required for journaling
- Optional private iCloud sync for saved entries, photos, places, people and
  preserved legacy fast sessions; drafts and preferences remain local

## Build

1. Open `Savour.xcodeproj` in Xcode 27 or later.
2. Select the `Savour` scheme and an iPhone simulator or your connected iPhone.
3. Press Run.

Both app targets require iOS 17 or later. The new Savour target uses the
existing app code, Core Data model, assets and permissions. Its bundle ID is
`tech.buildboring.Savour`, with automatic signing configured for team `829WP93FV4`.

App source remains in `FoodLog/` to preserve internal model/storage names.

The original `FoodLog` target keeps the old `com.viraat.foodlog` identity and
hosts the unit and UI reliability tests; run them with the `FoodLog` scheme. See
[`TESTING.md`](TESTING.md) for the simulator matrix and permission setup.

For installation on a physical iPhone, select the Savour target and check
Signing & Capabilities for your Apple developer account. Xcode must have a valid
signing certificate and provisioning profile before installing on the device.
The new bundle ID installs separately from `com.viraat.foodlog`; use full backup
and restore to carry entries and photos across without deleting the old app.

Both app targets use pinned ZIPFoundation 0.9.20 (MIT) to validate backup
archives; its license notice is included in the app bundle. It does not use
Dime's iCloud container, widgets, budgets, or intent extensions. This lightweight
port does not include Dime's original source; attribution and licensing details
are retained in `NOTICE` and `LICENSE`.

## iCloud sync

Optional sync is available in the new Savour target under **Settings → Your data
→ iCloud sync**. It is off by default and changes take effect after restarting
the app. Entries, photos, places and people use private iCloud storage; drafts
and preferences remain on-device. Offline logging and backup/restore remain
available. Apple account provisioning and production schema deployment must be
completed before live sync/TestFlight; see [iCloud setup and testing](ICLOUD_SYNC.md).

## Siri and Shortcuts

After installing this build, open Savour once. Say **“Siri, log food in Savour”**
and answer **“What did you eat?”**. Siri saves an entry and confirms when it is
logged. The entry uses the current time and the same meal-type suggestion as
the food editor.

For a custom shortcut, open **Shortcuts → + → Add Action**, find **Savour → Log
Food**, and set Food to **Ask Each Time**, a fixed description, or the output of
**Dictate Text**. Expand the action for optional Date, Meal type, Place,
Companions, and Note. An empty Date uses the time the shortcut runs; Automatic
meal type uses that date. Companions accepts a list of individual names. The
action returns the saved food description for use in subsequent steps.

**Settings → Meals → Siri & Shortcuts** includes a Siri tip and a link to
Shortcuts. Food is required; blank input is requested again. The device must
be unlocked, and App lock requires device authentication before saving. Failed
authentication, cancellation before saving, and save errors do not report
success. Shortcut entries use the normal journal store and optional iCloud
sync, independently of unfinished drafts. Free-text places do not receive
coordinates automatically.

This uses Apple's [App Intents](https://developer.apple.com/documentation/appintents/appintent)
and [App Shortcuts](https://developer.apple.com/documentation/appintents/appshortcutsprovider)
APIs. Siri phrase recognition and authentication prompts should also be checked
on an iPhone; simulator tests cover entry creation and failure paths.

## TestFlight uploads

Upload an existing signed archive with the API-authenticated release command:

```sh
python3 scripts/upload-testflight.py build/releases/0.7.0/Savour.xcarchive
```

The command reads `~/.config/savour-release/app-store-connect.json` with these
fields: `key_id`, `issuer_id`, `private_key_path`, `team_id`, and `bundle_id`.
Keep that local configuration and the `.p8` private key outside the repository.
The uploader checks the archive's app and signing team, keeps its version/build
number, and passes the API key to Xcode for the App Store Connect upload. It
does not rely on an interactive Apple Account session. Local signing/keychain
access and valid signing certificates are still required.

Use `--dry-run` to validate the configuration and archive without uploading;
`--config` and `--export-path` can override the defaults. Choose the archive for
the intended release, and avoid uploading a build number already accepted by
App Store Connect.

## Daily reminders

Open **Settings → Notifications**. Set a time, then use **Add reminder** for up to
three independent daily reminders—for example, breakfast, lunch, and dinner.
Each row uses the native time picker. Swipe left to remove extra times. The
initial time is 8 AM; additional times initially use 1 PM and 8 PM when available,
and all can be changed. Existing single-reminder choices migrate unchanged,
without adding any extra reminders. Duplicate times are not permitted.

Reminders are off by default; permission is requested only when enabling them.
Each time has a stable repeating local notification. Changing a time replaces
its request, removing a time cancels it, and turning the enable switch off removes
all three reminder requests without changing your saved times. **Open notification
settings** is always available and opens Savour's notification controls in iOS
Settings, including when notifications are disabled.

The notification says “A moment to note your meals.” and never includes food,
notes, people, or draft details. Opening it still respects App Lock. iOS handles
delivery while Savour is closed/backgrounded; Focus, notification settings, and
Scheduled Summary can affect when it appears. No account, server, push service,
or new Core Data model is needed.

Implementation follows Apple's [local notification scheduling](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)
and [in-context permission guidance](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications).

## Data and navigation

CSV import accepts older FoodLog exports and the current format. New exports
include entry IDs, exact timestamps, and structured companion names so repeat
imports can be skipped and names containing commas can be restored. Older
exports store people as one text field, so names containing commas may be split
on import. An empty journal exports a valid header-only CSV. CSV files do not
contain photos.

On iOS 27, Savour uses a native `UITabBarController` with a prominent trailing
Add item on the same row as the four navigation tabs. A public selection delegate
intercepts Add, opens the existing entry sheet, and returns false so the selected
page never changes. This is intentionally custom action handling for an API
designed for tab destinations, not a native action slot or Apple's standard
tab-bar interaction pattern. We deliberately retain the same-row modal action
as a product choice; Apple's HIG recommends putting actions in toolbars instead.
SwiftUI page state and
the full environment (including Core Data, appearance, accent, and scene phase)
are forwarded through the hosting controllers.

On iOS 26, the fallback uses a native `TabView` and a round `.glass` Add button
above the tabs in a `safeAreaBar`; earlier systems use `safeAreaInset` and native
bordered button styling. Bottom controls have no custom backgrounds, frame
overrides, shadows, or selection animations. See Apple's
[prominent tab API](https://developer.apple.com/documentation/uikit/uitabbarcontroller/prominenttabidentifier)
and [Liquid Glass adoption guidance](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).

With App lock enabled, Savour requests device authentication automatically on
launch and when returning after the relock delay. Cancelled or unsuccessful
authentication stays on the lock screen until retry; it does not repeatedly
prompt. Settings → Privacy offers immediate, 1-minute, and 5-minute relocking.
A new process always requires authentication. Background snapshots conceal
the journal, presented drafts, and keyboard predictions even during a grace
period. Grace periods use elapsed system uptime, not the wall clock.

Overnight estimates are calculated from the last non-Drink entry on one calendar
day and the first non-Drink entry on the next. They update with meal edits,
deletions, imports, and the current time zone. Days without logged meals are
skipped. These are estimates from your journal, not confirmations that nothing
else was consumed. There is no Start/End fast control or automatic creation of
`FastSession` records. Previously saved fasting records remain available in the
Fasts tab; the existing Core Data model and CSV formats are unchanged.
The Current row estimates elapsed time since the latest logged non-Drink meal.
The Avg row includes all completed estimates, independent of the calendar month
or history pagination. History initially shows 7 rows; View more adds up to 7
without changing the average. Calendar goal borders include the exact target
duration (`14h+ goal` by default). This explanation appears once, not on every row.

Journal, Fasts, Patterns, and Settings use native same-row navigation titles
(`toolbarTitleDisplayMode(.inlineLarge)`). Titles no longer occupy a separate
expanded band below the toolbar controls. Journal uses SwiftUI `searchable`; its
toolbar search button activates the native field. Statistical count bars use Swift Charts `BarMark`,
not task-progress indicators, with visible counts and accessible row descriptions.

Food entries stay in the app's local Core Data store. The location button enables
MapKit suggestions and uses foreground location only to prioritize nearby results;
it does not fill the field. MapKit choices are saved as place name and city, with
coordinates stored separately for the eating-place map. Free-text places continue
to work and previously used places appear as quick fills. Older free-text places
can be located from Patterns through an explicit MapKit backfill action.
On upgrade, Savour keeps the original place text and any valid saved coordinates.
It leaves unknown city and coordinate fields empty until the user selects a
MapKit place or explicitly backfills older places from Patterns; it does not
guess a location from free text. Legacy entries also receive
stable IDs and structured companion records without changing their original
people text.

The Contacts button requests access only when you tap it and stays enabled for
the rest of that entry. It reads formatted names for autocomplete. Savour does
not read phone numbers or email addresses. Previously selected people appear as
quick fills. Recurring combinations appear as group suggestions and expand into
individual people, so each person is counted separately in Patterns.
When Contacts access is available, the People card matches saved companion names
to contact thumbnails and falls back to initials when no photo is available.

## Data model

Each `FoodEntry` stores:

| Field | Required | Purpose |
|---|---|---|
| Food | Yes | Plain-language description of what was eaten |
| Date/time | Yes | When it happened |
| Meal type | Yes | A simple category |
| Place | No | Typed location or venue |
| Place city | No | City returned by MapKit |
| Place coordinates | No | Latitude and longitude used by the eating-place map |
| People | No | Individually stored companion records |
| Note | No | Anything else worth remembering |
| Photo | No | An image stored with the entry |

## Origin and license

Savour is a modified work based on
[Dime](https://github.com/rafsoh/dimeApp), created by Rafael Soh and Dime's
contributors. Dime is licensed under GNU GPLv3, so this derivative remains
GPLv3. See `LICENSE` and `NOTICE`. If you distribute the app, you must comply
with the GPLv3 source and notice requirements.

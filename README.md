# Savour

Savour (previously FoodLog) is a deliberately simple, private food journal for iPhone. It borrows
Dime's excellent low-friction interaction model, but records food instead of
money.

Current repository release: **0.5.2** (build 7). See the
[changelog](CHANGELOG.md) and [release notes](RELEASE_NOTES.md).

The installed app is named Savour. The Xcode project, target, and scheme remain
`FoodLog`; the bundle identifier (`com.viraat.foodlog`), Core Data model/store name,
draft filenames, and saved preferences are unchanged to preserve upgrade and
data compatibility. Previously exported FoodLog CSV files remain importable;
new exports are named `Savour.csv` and use the same format.

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
- Light, dark, and system appearance with five saved accent colors
- Native grouped Settings sections with compact selection rows and standard toggles
- Optional meal-logging reminders: up to three custom local times each day
- Native navigation, sheets, bottom toolbars, and iOS 26 Liquid Glass styling
- Optional automatic biometric app lock, immediate/1-minute/5-minute relocking, and background privacy shielding
- Fully local Core Data storage with no account required

## Build

1. Open `FoodLog.xcodeproj` in Xcode 15 or later.
2. Select the `FoodLog` scheme and an iPhone simulator.
3. Press Run.

Use Xcode 27 or later to build the iOS 27 same-row Add action. Older SDKs retain
the native bottom-button fallback.

The shared scheme also includes unit and UI reliability tests. See
[`TESTING.md`](TESTING.md) for the simulator matrix and permission setup.

For installation on a physical iPhone, select the FoodLog target, open
Signing & Capabilities, choose your Apple developer team, and change the bundle
identifier if Xcode asks for a unique one. The deployment target is iOS 16.

The FoodLog target has no third-party package dependencies and does not use
Dime's iCloud container, widgets, budgets, or intent extensions. This lightweight
port does not include Dime's original source; attribution and licensing details
are retained in `NOTICE` and `LICENSE`.

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
or history pagination. History initially shows 30 rows; View more adds up to 30
without changing the average. Calendar goal borders include the exact target
duration (`14h+ goal` by default). This explanation appears once, not on every row.

Journal, Fasts, Patterns, and Settings use native same-row navigation titles:
`toolbarTitleDisplayMode(.inlineLarge)` on iOS 17 and later, and compact inline
titles on iOS 16. Titles no longer occupy a separate expanded band below the
toolbar controls. Journal uses SwiftUI `searchable`; on iOS 17 and
later its toolbar search button activates the native field, while iOS 16 shows
the standard search drawer. Statistical count bars use Swift Charts `BarMark`,
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

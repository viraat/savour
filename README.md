# FoodLog

FoodLog is a deliberately simple, private food journal for iPhone. It borrows
Dime's excellent low-friction interaction model, but records food instead of
money.

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
- Meal-category filtering
- Neutral visual summaries for 7 days, 30 days, and all time
- Current consecutive-day streak derived from journal entries
- Eating-place map with optional coordinate backfill for older entries
- Common places and companions
- CSV export and import with a preview of entries, duplicate detection, and row errors
- Light, dark, and system appearance with five saved accent colors
- Native navigation, sheets, bottom toolbars, and iOS 26 Liquid Glass styling
- Optional automatic biometric app lock, immediate/1-minute/5-minute relocking, and background privacy shielding
- Fully local Core Data storage with no account required

## Build

1. Open `FoodLog.xcodeproj` in Xcode 15 or later.
2. Select the `FoodLog` scheme and an iPhone simulator.
3. Press Run.

The shared scheme also includes unit and UI reliability tests. See
[`TESTING.md`](TESTING.md) for the simulator matrix and permission setup.

For installation on a physical iPhone, select the FoodLog target, open
Signing & Capabilities, choose your Apple developer team, and change the bundle
identifier if Xcode asks for a unique one. The deployment target is iOS 16.

The FoodLog target has no third-party package dependencies and does not use
Dime's iCloud container, widgets, budgets, or intent extensions. This lightweight
port does not include Dime's original source; attribution and licensing details
are retained in `NOTICE` and `LICENSE`.

CSV import accepts older FoodLog exports and the current format. New exports
include entry IDs, exact timestamps, and structured companion names so repeat
imports can be skipped and names containing commas can be restored. Older
exports store people as one text field, so names containing commas may be split
on import. An empty journal exports a valid header-only CSV. CSV files do not
contain photos.

On iOS 26, FoodLog uses the system Liquid Glass effects, glass button styles,
a grouped bottom navigation bar, and a distinct trailing add action. Journal
content scrolls behind the glass while the final entry can scroll clear of the
controls. Earlier
supported iOS versions use native materials and bordered controls through
availability-gated fallbacks.

With App lock enabled, FoodLog requests device authentication automatically on
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

Food entries stay in the app's local Core Data store. The location button enables
MapKit suggestions and uses foreground location only to prioritize nearby results;
it does not fill the field. MapKit choices are saved as place name and city, with
coordinates stored separately for the eating-place map. Free-text places continue
to work and previously used places appear as quick fills. Older free-text places
can be located from Patterns through an explicit MapKit backfill action.
On upgrade, FoodLog keeps the original place text and any valid saved coordinates.
It leaves unknown city and coordinate fields empty until the user selects a
MapKit place or explicitly backfills older places from Patterns; it does not
guess a location from free text. Legacy entries also receive
stable IDs and structured companion records without changing their original
people text.

The Contacts button requests access only when you tap it and stays enabled for
the rest of that entry. It reads formatted names for autocomplete. FoodLog does
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

FoodLog is a modified work based on
[Dime](https://github.com/rafsoh/dimeApp), created by Rafael Soh and Dime's
contributors. Dime is licensed under GNU GPLv3, so this derivative remains
GPLv3. See `LICENSE` and `NOTICE`. If you distribute the app, you must comply
with the GPLv3 source and notice requirements.

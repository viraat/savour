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
- Breakfast, lunch, dinner, snack, drink, and other categories
- Optional place, companions, and free-form note
- Optional current-location fill and place autocomplete
- Individual companions with optional Contacts autocomplete
- Frequent companion and named group quick fills
- Optional photo from the camera or system photo picker
- Suggestions from previously logged food
- Journal grouped by day
- Search across food, place, people, and notes
- Meal-category filtering
- Neutral 7-day, 30-day, and all-time pattern summaries
- Common places and companions
- CSV export
- Light, dark, and system appearance
- Fully local Core Data storage with no account required

## Build

1. Open `FoodLog.xcodeproj` in Xcode 15 or later.
2. Select the `FoodLog` scheme and an iPhone simulator.
3. Press Run.

For installation on a physical iPhone, select the FoodLog target, open
Signing & Capabilities, choose your Apple developer team, and change the bundle
identifier if Xcode asks for a unique one. The deployment target is iOS 16.

The FoodLog target has no third-party package dependencies and does not use
Dime's iCloud container, widgets, budgets, or intent extensions. This lightweight
port does not include Dime's original source; attribution and licensing details
are retained in `NOTICE` and `LICENSE`.

Food entries stay in the app's local Core Data store. If you type in the place
field, Apple MapKit may provide autocomplete results. The current-location button
requests foreground location access only when you tap it.

The Contacts button requests access only when you tap it and stays enabled for
the rest of that entry. It reads formatted names for autocomplete. FoodLog does
not read phone numbers or email addresses. Frequently selected people appear as
quick fills. You can save two or more selected people as a named group; using a
group adds its members individually so each person is counted separately in
Patterns.

## Data model

Each `FoodEntry` stores:

| Field | Required | Purpose |
|---|---|---|
| Food | Yes | Plain-language description of what was eaten |
| Date/time | Yes | When it happened |
| Meal type | Yes | A simple category |
| Place | No | Typed location or venue |
| People | No | Individually stored companion records |
| Note | No | Anything else worth remembering |
| Photo | No | An image stored with the entry |

## Origin and license

FoodLog is a modified work based on
[Dime](https://github.com/rafsoh/dimeApp), created by Rafael Soh and Dime's
contributors. Dime is licensed under GNU GPLv3, so this derivative remains
GPLv3. See `LICENSE` and `NOTICE`. If you distribute the app, you must comply
with the GPLv3 source and notice requirements.

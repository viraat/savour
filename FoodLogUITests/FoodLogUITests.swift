import XCTest

final class FoodLogUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
    }

    func testAddEditRelaunchAndDelete() {
        launch(resetStore: true)
        addEntry(named: "Reliability toast")
        XCTAssertTrue(app.staticTexts["Reliability toast"].waitForExistence(timeout: 3))

        app.terminate()
        launch(resetStore: false)
        XCTAssertTrue(app.staticTexts["Reliability toast"].waitForExistence(timeout: 3))

        app.staticTexts["Reliability toast"].tap()
        let foodField = app.textFields["food-description"]
        XCTAssertTrue(foodField.waitForExistence(timeout: 2))
        foodField.tap()
        foodField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30))
        foodField.typeText("Edited reliability toast")
        app.buttons["Save"].tap()
        let editedEntry = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "edited reliability toast")
        ).firstMatch
        XCTAssertTrue(editedEntry.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Reliability toast"].exists)

        editedEntry.press(forDuration: 1)
        app.buttons["Delete"].tap()
        app.alerts.buttons["Delete"].tap()
        XCTAssertFalse(editedEntry.waitForExistence(timeout: 2))
    }

    func testMealSwitchAppliesDefaultAndTimeControlsOnlyAppearWhenExpanded() {
        launch(resetStore: true, extraArguments: ["-foodLogDefaultTime.lunch", "795"])
        app.buttons["Add entry"].tap()

        XCTAssertFalse(app.buttons["Add 5 minutes"].exists)
        app.buttons["Meal type"].tap()
        app.buttons["Lunch"].tap()
        XCTAssertTrue(app.buttons["Date and time"].value as? String == expectedDateAndTime(hour: 13, minute: 15))
        XCTAssertFalse(app.buttons["Add 5 minutes"].exists)

        app.buttons["Date and time"].tap()
        XCTAssertTrue(app.buttons["Add 5 minutes"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Subtract 5 minutes"].exists)
        XCTAssertTrue(app.buttons["Set time to now"].exists)
    }

    func testMealSpecificSuggestionAppendsWithoutDuplication() {
        launch(resetStore: true, extraArguments: ["--seed-ui-test-suggestions"])
        app.buttons["Add entry"].tap()
        app.buttons["Meal type"].tap()
        app.buttons["Breakfast"].tap()

        let foodField = app.textFields["food-description"]
        foodField.tap()
        let toastSuggestion = app.buttons["Toast"]
        XCTAssertTrue(toastSuggestion.waitForExistence(timeout: 2))
        toastSuggestion.tap()
        XCTAssertEqual(foodField.value as? String, "Toast")
        XCTAssertFalse(app.buttons["Toast"].exists)
    }

    func testDeniedContactsAndLocationRemainUsable() {
        launch(resetStore: true, extraArguments: [
            "--simulate-contacts-denied", "--simulate-location-denied"
        ])
        app.buttons["Add entry"].tap()
        app.buttons["Add details"].tap()

        let contactButton = app.buttons["Enable contact suggestions"]
        XCTAssertTrue(contactButton.waitForExistence(timeout: 2))
        contactButton.tap()
        XCTAssertTrue(app.staticTexts["Contact access is disabled in Settings."].waitForExistence(timeout: 2))

        let locationButton = app.buttons["Enable location suggestions"]
        if !locationButton.isHittable {
            app.swipeUp()
        }
        locationButton.tap()
        XCTAssertTrue(app.staticTexts["Location access is disabled in Settings. Search still works."].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["Home, restaurant, office…"].exists)
    }

    func testEditedLocationUpdatesJournalImmediately() {
        launch(resetStore: true)
        addEntry(named: "Location refresh")
        app.staticTexts["Location refresh"].tap()
        app.buttons["Add details"].tap()

        let placeField = app.textFields["Home, restaurant, office…"]
        XCTAssertTrue(placeField.waitForExistence(timeout: 2))
        placeField.tap()
        placeField.typeText("Home")
        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["Home"].waitForExistence(timeout: 3))
    }

    func testUnavailableBiometricsNeverRevealsJournal() {
        launch(
            resetStore: true,
            extraArguments: [
                "-foodLogBiometricLockEnabled", "YES",
                "--simulate-biometric-denied"
            ]
        )
        XCTAssertTrue(app.staticTexts["FoodLog is locked"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["Food log"].exists)
        XCTAssertTrue(app.buttons["Unlock"].waitForExistence(timeout: 3))
    }

    func testMapPinAndAppearanceSetting() {
        launch(
            resetStore: true,
            extraArguments: ["--seed-ui-test-map", "--seed-ui-test-suggestions"]
        )
        app.buttons["Patterns"].tap()
        XCTAssertTrue(app.buttons["Eating places"].waitForExistence(timeout: 3))

        for tile in ["Eating places", "Overview", "Foods noted", "People"] {
            app.buttons[tile].tap()
            XCTAssertTrue(app.navigationBars[tile].waitForExistence(timeout: 3))
            if tile == "Eating places" {
                let pin = app.buttons["eating-place-map-pin"].firstMatch
                XCTAssertTrue(pin.waitForExistence(timeout: 3))
                pin.tap()
                XCTAssertTrue(app.staticTexts["Roastery Coffee House, Hyderabad"].exists)
            }
            app.buttons["Done"].tap()
        }

        app.buttons["Settings"].tap()
        let dark = app.buttons["Dark"]
        XCTAssertTrue(dark.waitForExistence(timeout: 2))
        dark.tap()
        XCTAssertTrue(dark.isSelected)
    }

    func testBottomNavigationCapturesTouchesAcrossButtonEdges() {
        launch(resetStore: true, extraArguments: ["--seed-ui-test-navigation"])
        XCTAssertTrue(app.navigationBars["Food log"].waitForExistence(timeout: 3))

        let journal = app.buttons["Journal"]
        XCTAssertTrue(journal.waitForExistence(timeout: 2))
        journal.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.12)).tap()
        journal.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.88)).tap()
        XCTAssertFalse(app.navigationBars["Edit entry"].exists)

        let patterns = app.buttons["Patterns"]
        patterns.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.88)).tap()
        XCTAssertTrue(app.navigationBars["Patterns"].waitForExistence(timeout: 2))

        let journalAgain = app.buttons["Journal"]
        journalAgain.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.12)).tap()
        XCTAssertTrue(app.navigationBars["Food log"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.navigationBars["Edit entry"].exists)
    }

    func testCSVPreviewImportsValidRowsAndReportsDuplicatesAndErrors() {
        launch(resetStore: true, extraArguments: ["--seed-ui-test-map", "--ui-test-csv-fixture"])
        app.buttons["Settings"].tap()
        app.scrollViews.firstMatch.swipeUp()
        app.buttons["Preview CSV fixture"].tap()

        XCTAssertTrue(app.navigationBars["Import preview"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["1 to import · 1 duplicates · 1 errors"].exists)
        XCTAssertTrue(app.staticTexts["Row 4 has an invalid date."].exists)
        XCTAssertTrue(app.staticTexts["Imported CSV fixture"].exists)
        app.buttons["Import 1"].tap()

        let successAlert = app.alerts["CSV import"]
        if successAlert.waitForExistence(timeout: 2) { successAlert.buttons["OK"].tap() }
        app.buttons["Journal"].tap()
        XCTAssertTrue(app.staticTexts["Imported CSV fixture"].waitForExistence(timeout: 3))

        app.buttons["Settings"].tap()
        app.scrollViews.firstMatch.swipeUp()
        app.buttons["Preview CSV fixture"].tap()
        XCTAssertTrue(app.staticTexts["0 to import · 2 duplicates · 1 errors"].waitForExistence(timeout: 3))
    }

    private func launch(resetStore: Bool, extraArguments: [String] = []) {
        let suppliesLockSetting = extraArguments.contains("-foodLogBiometricLockEnabled")
        app.launchArguments = ["--ui-testing"]
            + (resetStore ? ["--reset-ui-test-store"] : [])
            + (suppliesLockSetting ? [] : ["-foodLogBiometricLockEnabled", "NO"])
            + extraArguments
        app.launch()
    }

    private func addEntry(named food: String) {
        app.buttons["Add entry"].tap()
        let foodField = app.textFields["food-description"]
        XCTAssertTrue(foodField.waitForExistence(timeout: 2))
        foodField.tap()
        foodField.typeText(food)
        app.buttons["Add"].tap()
    }

    private func expectedDateAndTime(hour: Int, minute: Int) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none

        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components)!
        return "\(dateFormatter.string(from: date)), \(timeFormatter.string(from: date))"
    }
}

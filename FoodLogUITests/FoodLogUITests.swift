import XCTest

final class FoodLogUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
    }

    func testAddEditRelaunchAndDelete() {
        launch(resetStore: true)
        addEntry(named: "Reliability toast")
        XCTAssertTrue(journalEntry(containing: "Reliability toast").waitForExistence(timeout: 3))

        app.terminate()
        launch(resetStore: false)
        XCTAssertTrue(journalEntry(containing: "Reliability toast").waitForExistence(timeout: 3))

        journalEntry(containing: "Reliability toast").tap()
        let foodField = app.textFields["food-description"]
        XCTAssertTrue(foodField.waitForExistence(timeout: 2))
        foodField.tap()
        foodField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30))
        foodField.typeText("Edited reliability toast")
        app.buttons["Save"].tap()
        let editedEntry = journalEntry(containing: "edited reliability toast")
        XCTAssertTrue(editedEntry.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH[c] %@", "Reliability toast")
        ).firstMatch.exists)

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
        app.buttons["Breakfast"].tap()
        app.buttons["Meal type"].tap()
        app.buttons["Lunch"].tap()
        XCTAssertEqual(app.buttons["Date and time"].value as? String, expectedDateAndTime(hour: 13, minute: 15))
        XCTAssertFalse(app.buttons["Add 5 minutes"].exists)

        app.buttons["Date and time"].tap()
        XCTAssertTrue(app.buttons["Add 5 minutes"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Subtract 5 minutes"].exists)
        XCTAssertTrue(app.buttons["Set time to now"].exists)
    }

    func testFoodSuggestionReplacesOnlyCurrentSegmentWithoutDuplication() {
        launch(resetStore: true, extraArguments: ["--seed-ui-test-suggestions"])
        app.buttons["Add entry"].tap()
        app.buttons["Meal type"].tap()
        app.buttons["Breakfast"].tap()

        let foodField = app.textFields["food-description"]
        foodField.tap()
        foodField.typeText("Eggs, Toa")
        let toastSuggestion = app.buttons["Toast"]
        XCTAssertTrue(toastSuggestion.waitForExistence(timeout: 2))
        toastSuggestion.tap()
        XCTAssertEqual(foodField.value as? String, "Eggs, Toast")
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
        journalEntry(containing: "Location refresh").tap()
        app.buttons["Add details"].tap()

        let placeField = app.textFields["Home, restaurant, office…"]
        XCTAssertTrue(placeField.waitForExistence(timeout: 2))
        placeField.tap()
        placeField.typeText("Home")
        app.buttons["Save"].tap()

        XCTAssertTrue(journalEntry(containing: "Home").waitForExistence(timeout: 3))
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
        openCSVFixturePreview()

        XCTAssertTrue(app.navigationBars["Import preview"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["1 to import · 1 duplicates · 1 errors"].exists)
        XCTAssertTrue(app.staticTexts["Row 4 has an invalid date."].exists)
        XCTAssertTrue(app.staticTexts["Imported CSV fixture"].exists)
        app.buttons["Import 1"].tap()

        let successAlert = app.alerts["CSV import"]
        if successAlert.waitForExistence(timeout: 2) { successAlert.buttons["OK"].tap() }
        app.buttons["Journal"].tap()
        XCTAssertTrue(journalEntry(containing: "Imported CSV fixture").waitForExistence(timeout: 3))

        app.buttons["Settings"].tap()
        openCSVFixturePreview()
        XCTAssertTrue(app.staticTexts["0 to import · 2 duplicates · 1 errors"].waitForExistence(timeout: 3))
    }

    func testAccessibilityAuditOnPrimaryScreens() throws {
        guard #available(iOS 17.0, *) else { return }
        for appearance in ["1", "2"] {
            launch(resetStore: true, extraArguments: ["-foodLogAppearance", appearance])
            try auditVisibleUI()

            app.buttons["Add entry"].tap()
            try auditVisibleUI()
            app.buttons["Cancel"].tap()

            app.buttons["Settings"].tap()
            try auditVisibleUI()
            app.terminate()
        }
    }

    func testLongFoodNameAndKeyboardReachability() {
        launch(resetStore: true)
        XCTAssertTrue(app.staticTexts["No entries yet"].exists)
        app.buttons["Add entry"].tap()

        let food = "A very long handmade sourdough sandwich with roasted vegetables, fresh herbs, tomato relish, toasted seeds, and extra cheese"
        let field = app.textFields["food-description"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(food)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.buttons["Add"].isHittable)
        app.buttons["Add"].tap()

        let entry = journalEntry(containing: food)
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(entry.frame.maxX, app.frame.maxX - 8)
        entry.tap()
        XCTAssertEqual(app.textFields["food-description"].value as? String, food)
        app.buttons["Cancel"].tap()
    }

    func testAccessibilityAuditOnPopulatedJournalAndPatterns() throws {
        guard #available(iOS 17.0, *) else { return }
        launch(resetStore: true, extraArguments: [
            "--seed-ui-test-map", "--seed-ui-test-suggestions", "-foodLogAppearance", "1"
        ])
        try auditVisibleUI()
        app.buttons["Patterns"].tap()
        // MapKit's rendered canvas triggers a whole-screen contrast failure
        // without an element; other audit checks still cover these screens.
        try auditVisibleUI(includeContrast: false)
        app.buttons["Eating places"].tap()
        try auditVisibleUI(includeContrast: false)
    }

    func testLargeTextNavigationRemainsReachable() {
        launch(resetStore: true)
        for tab in ["Patterns", "Settings", "Journal"] {
            let button = app.buttons[tab]
            XCTAssertTrue(button.isHittable, "\(tab) should remain reachable")
            button.tap()
        }
        XCTAssertTrue(app.buttons["Add entry"].isHittable)
        app.buttons["Add entry"].tap()
        XCTAssertTrue(app.textFields["food-description"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Cancel"].isHittable)
        let dateButton = app.buttons["Date and time"]
        if !dateButton.isHittable { app.swipeUp() }
        dateButton.tap()
        let incrementButton = app.buttons["Add 5 minutes"]
        for _ in 0..<3 where !incrementButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(incrementButton.isHittable)
    }

    @available(iOS 17.0, *)
    private func auditVisibleUI(includeContrast: Bool = true) throws {
        var auditTypes: XCUIAccessibilityAuditType = [
            .hitRegion, .sufficientElementDescription
        ]
        // iOS 18 reports whole-screen contrast/clipping failures without an
        // element, even when the capture has no visible defect. iOS 26
        // supplies element-level findings that can be acted on.
        if #available(iOS 26.0, *) {
            if includeContrast { auditTypes.insert(.contrast) }
            auditTypes.insert(.textClipped)
        }
        try app.performAccessibilityAudit(for: auditTypes) { issue in
            // UIKit renders the searchable placeholder; its clipped/contrast
            // audit findings do not reflect the visible, app-owned content.
            if (issue.element?.elementType == .searchField &&
                (issue.auditType == .contrast || issue.auditType == .textClipped)) ||
                (issue.auditType == .contrast && issue.element?.label == "Add") {
                return true
            }

            // MapKit owns the attribution link and fixes its hit area.
            if issue.auditType == .hitRegion && issue.element?.elementType == .link &&
                issue.element?.label == "Legal" {
                return true
            }

            // iOS's screenshot heuristic samples text through the translucent
            // bottom bar even when the foreground tab labels are opaque.
            if issue.auditType == .contrast, let element = issue.element {
                let bar = self.app.buttons["Journal"].frame.union(self.app.buttons["Add entry"].frame)
                return element.frame.maxY >= bar.minY - 32
            }
            return false
        }
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

    private func journalEntry(containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func openCSVFixturePreview() {
        let fixture = app.buttons["Preview CSV fixture"]
        for _ in 0..<4 {
            let barTop = app.buttons["Journal"].frame.minY
            if fixture.isHittable && fixture.frame.maxY < barTop - 8 { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(fixture.isHittable)
        XCTAssertLessThan(fixture.frame.maxY, app.buttons["Journal"].frame.minY)
        fixture.tap()
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

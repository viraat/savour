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

    func testMealSwitchAppliesDefaultAndTimeControlsAppearInSheet() {
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
        XCTAssertTrue(app.buttons["Add 1 minute"].exists)
        XCTAssertTrue(app.buttons["Subtract 1 minute"].exists)
        XCTAssertTrue(app.buttons["Set time to now"].exists)
        XCTAssertTrue(app.datePickers["date-time-wheel"].exists)
        let pickerImage = XCTAttachment(screenshot: app.screenshot())
        pickerImage.name = "Meal date and time sheet"
        pickerImage.lifetime = .keepAlways
        add(pickerImage)
        app.buttons["date-time-done"].tap()
        XCTAssertFalse(app.buttons["Add 5 minutes"].exists)
    }

    func testDateTimeSheetInDarkMode() {
        launch(resetStore: true, extraArguments: ["-foodLogAppearance", "2"])
        app.buttons["Add entry"].tap()
        app.buttons["Date and time"].tap()
        XCTAssertTrue(app.datePickers["date-time-wheel"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["date-time-done"].exists)
        let pickerImage = XCTAttachment(screenshot: app.screenshot())
        pickerImage.name = "Dark date and time sheet"
        pickerImage.lifetime = .keepAlways
        add(pickerImage)
    }

    func testNewDraftSurvivesBackgroundAndForcedTerminationWithoutCreatingEntry() {
        launch(resetStore: true)
        app.buttons["Add entry"].tap()
        let foodField = app.textFields["food-description"]
        foodField.tap()
        foodField.typeText("Interrupted dinner")
        app.buttons["Date and time"].tap()
        app.buttons["Add 5 minutes"].tap()
        app.buttons["date-time-done"].tap()
        let chosenTime = app.buttons["Date and time"].value as? String

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(app.textFields["food-description"].value as? String, "Interrupted dinner")

        app.terminate()
        launch(resetStore: false)
        XCTAssertTrue(app.navigationBars["New entry"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields["food-description"].value as? String, "Interrupted dinner")
        XCTAssertEqual(app.buttons["Date and time"].value as? String, chosenTime)
        app.buttons["Cancel"].tap()
        app.buttons["Keep draft"].tap()
        waitForEditorDismissal()
        XCTAssertFalse(journalEntry(containing: "Interrupted dinner").exists)
        app.buttons["Add entry"].tap()
        XCTAssertEqual(app.textFields["food-description"].value as? String, "Interrupted dinner")
        app.buttons["Add"].tap()
        XCTAssertTrue(journalEntry(containing: "Interrupted dinner").waitForExistence(timeout: 3))
        app.terminate()
        launch(resetStore: false)
        XCTAssertFalse(app.navigationBars["New entry"].exists)
    }

    func testEditDraftDoesNotChangeOriginalUntilSave() {
        launch(resetStore: true)
        addEntry(named: "Original draft meal")
        journalEntry(containing: "Original draft meal").tap()
        let foodField = app.textFields["food-description"]
        foodField.tap()
        foodField.typeText("Revised ")
        let editedFood = foodField.value as? String ?? ""
        XCTAssertTrue(editedFood.contains("Revised"))
        XCTAssertNotEqual(editedFood, "Original draft meal")

        app.terminate()
        launch(resetStore: false)
        XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields["food-description"].value as? String, editedFood)
        app.buttons["Cancel"].tap()
        app.buttons["Keep draft"].tap()
        waitForEditorDismissal()
        XCTAssertTrue(journalEntry(containing: "Original draft meal").exists)
        XCTAssertFalse(journalEntry(containing: editedFood).exists)
        journalEntry(containing: "Original draft meal").tap()
        XCTAssertEqual(app.textFields["food-description"].value as? String, editedFood)
        app.buttons["Save"].tap()
        XCTAssertTrue(journalEntry(containing: editedFood).waitForExistence(timeout: 3))
    }

    func testDraftRequiresExplicitDiscardConfirmation() {
        launch(resetStore: true)
        app.buttons["Add entry"].tap()
        let foodField = app.textFields["food-description"]
        foodField.tap()
        foodField.typeText("Keep this draft")
        XCTAssertFalse(app.buttons["discard-entry-draft"].exists)
        app.buttons["Cancel"].tap()
        app.buttons["Keep draft"].tap()
        waitForEditorDismissal()
        app.buttons["Add entry"].tap()
        XCTAssertTrue(foodField.waitForExistence(timeout: 3))
        XCTAssertEqual(foodField.value as? String, "Keep this draft")
        app.buttons["Cancel"].tap()
        app.buttons["Discard draft"].tap()
        let editorDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.navigationBars["New entry"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [editorDismissed], timeout: 3), .completed)
        app.buttons["Add entry"].tap()
        XCTAssertNotEqual(app.textFields["food-description"].value as? String, "Keep this draft")
    }

    func testDraftIsHiddenBehindDeniedBiometricLock() {
        launch(resetStore: true, extraArguments: [
            "--seed-ui-test-draft", "-foodLogBiometricLockEnabled", "YES", "--simulate-biometric-denied"
        ])
        XCTAssertTrue(app.staticTexts["Savour is locked"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Private unfinished meal"].exists)
        XCTAssertFalse(app.textFields["food-description"].exists)
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
        XCTAssertTrue(app.staticTexts["Savour is locked"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["Savour"].exists)
        XCTAssertTrue(app.buttons["Unlock"].waitForExistence(timeout: 3))
    }

    func testAutomaticAuthenticationOnLaunchAndImmediateReturnWithoutRetryLoop() {
        launch(resetStore: true, extraArguments: [
            "-foodLogBiometricLockEnabled", "YES", "--simulate-biometric-success-once"
        ])
        XCTAssertTrue(app.navigationBars["Savour"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Unlock"].exists)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["Savour is locked"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["Savour"].exists)
        XCTAssertEqual(app.staticTexts["authentication-message"].value as? String, "2")
        app.buttons["Unlock"].tap()
        XCTAssertEqual(app.staticTexts["authentication-message"].value as? String, "3")
        XCTAssertTrue(app.buttons["Unlock"].isHittable)
    }

    func testCancelledAutomaticAuthenticationWaitsForRetry() {
        launch(resetStore: true, extraArguments: [
            "-foodLogBiometricLockEnabled", "YES", "--simulate-biometric-denied"
        ])
        let status = app.staticTexts["authentication-message"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        XCTAssertEqual(status.value as? String, "1")
        XCTAssertFalse(app.buttons["Journal"].exists)
        app.buttons["Unlock"].tap()
        XCTAssertEqual(status.value as? String, "2")
        XCTAssertTrue(app.buttons["Unlock"].isHittable)
        XCTAssertEqual(status.value as? String, "2")
    }

    func testRelockGracePeriodPreservesOpenDraftWhenBrieflySwitchingApps() {
        for delay in ["60", "300"] {
            launch(resetStore: true, extraArguments: [
                "-foodLogBiometricLockEnabled", "YES", "-foodLogRelockDelaySeconds", delay,
                "--simulate-biometric-success-once"
            ])
            XCTAssertTrue(app.buttons["Add entry"].waitForExistence(timeout: 3))
            app.buttons["Add entry"].tap()
            let field = app.textFields["food-description"]
            field.tap()
            field.typeText("Grace period draft")
            XCUIDevice.shared.press(.home)
            app.activate()
            XCTAssertTrue(app.navigationBars["New entry"].waitForExistence(timeout: 3))
            XCTAssertEqual(field.value as? String, "Grace period draft")
            XCTAssertFalse(app.staticTexts["Savour is locked"].exists)
            app.terminate()
        }
    }

    func testRelockSettingPersistsAcrossRelaunch() {
        launch(resetStore: true)
        app.buttons["Settings"].tap()
        let picker = app.buttons["relock-delay"]
        revealAboveNavigation(picker)
        picker.tap()
        app.buttons["After 5 minutes"].tap()
        XCTAssertTrue(picker.label.contains("After 5 minutes"))
        app.terminate()
        launch(resetStore: false)
        app.buttons["Settings"].tap()
        revealAboveNavigation(picker)
        XCTAssertTrue(picker.label.contains("After 5 minutes"))
    }

    func testPrivacyCoverConcealsPresentedDraftInAppSwitcherDuringGracePeriod() {
        launch(resetStore: true, extraArguments: [
            "-foodLogBiometricLockEnabled", "YES", "-foodLogRelockDelaySeconds", "60",
            "--simulate-biometric-success-once"
        ])
        app.buttons["Add entry"].tap()
        let field = app.textFields["food-description"]
        field.tap()
        field.typeText("Private draft behind lock")
        // Open the app switcher using the home-indicator gesture, including a
        // hold at the end. The capture verifies the snapshot of the open sheet.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.995))
            .press(forDuration: 0.1,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)),
                   withVelocity: .slow, thenHoldForDuration: 0.5)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 3))
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "Privacy cover over draft in app switcher"
        capture.lifetime = .keepAlways
        add(capture)
        app.activate()
        XCTAssertEqual(field.value as? String, "Private draft behind lock")
        XCTAssertFalse(app.staticTexts["Savour is locked"].exists)
    }

    func testNativeTabBarSelectionAndBottomAddAction() {
        launch(resetStore: true)
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 3))
        for title in ["Fasts", "Patterns", "Settings", "Journal"] {
            let tab = tabBar.buttons[title]
            XCTAssertTrue(tab.isHittable)
            tab.tap()
            XCTAssertTrue(tab.isSelected)
            let addButton = app.buttons["bottom-add-entry"]
            XCTAssertTrue(addButton.isHittable)
            XCTAssertGreaterThan(addButton.frame.midY, app.frame.midY)
            XCTAssertGreaterThan(addButton.frame.midX, app.frame.midX)
#if compiler(>=6.4)
            if #available(iOS 27.0, *) {
                XCTAssertLessThan(abs(addButton.frame.midY - tab.frame.midY), 14)
                XCTAssertGreaterThan(addButton.frame.minX, tabBar.buttons["Settings"].frame.maxX)
            } else {
                XCTAssertLessThanOrEqual(addButton.frame.maxY, tabBar.frame.minY)
            }
#else
            XCTAssertLessThanOrEqual(addButton.frame.maxY, tabBar.frame.minY)
#endif
            XCTAssertGreaterThanOrEqual(addButton.frame.width, 44)
            XCTAssertGreaterThanOrEqual(addButton.frame.height, 44)
            // Opening and dismissing Add from every destination must preserve
            // that destination, with no selected Add tab or placeholder page.
            addButton.tap()
            XCTAssertTrue(app.navigationBars["New entry"].waitForExistence(timeout: 3))
            app.buttons["Cancel"].tap()
            if app.alerts["Close this entry?"].waitForExistence(timeout: 1) {
                app.buttons["Keep draft"].tap()
            }
            waitForEditorDismissal()
            XCTAssertTrue(tab.isSelected)
            XCTAssertFalse(app.buttons["bottom-add-entry"].isSelected)
        }
        app.buttons["Add entry"].tap()
        XCTAssertTrue(app.navigationBars["New entry"].waitForExistence(timeout: 3))
    }

    func testJournalSearchSurvivesOpeningAndDismissingAddSheet() {
        launch(resetStore: true, extraArguments: ["--seed-ui-test-navigation"])
        app.buttons["journal-search-button"].tap()
        let search = app.searchFields["Search entries"]
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        search.tap()
        search.typeText("Navigation fixture 20\n")
        app.buttons["bottom-add-entry"].tap()
        XCTAssertTrue(app.navigationBars["New entry"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
        if app.alerts["Close this entry?"].waitForExistence(timeout: 1) {
            app.buttons["Keep draft"].tap()
        }
        waitForEditorDismissal()
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Journal"].isSelected)
        XCTAssertEqual(search.value as? String, "Navigation fixture 20")
        XCTAssertTrue(journalEntry(containing: "Navigation fixture 20").exists)
        XCTAssertFalse(journalEntry(containing: "Navigation fixture 19").exists)
    }

    func testEditEntryActionsShowDeleteWithoutAnotherOverflowMenu() {
        launch(resetStore: true, extraArguments: ["--seed-ui-test-overnight"])
        let entry = journalEntry(containing: "Overnight breakfast")
        revealAboveNavigation(entry)
        entry.tap()
        XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout: 3))
        app.buttons["Entry actions"].tap()
        XCTAssertTrue(app.buttons["Delete entry"].waitForExistence(timeout: 2))
        app.buttons["Delete entry"].tap()
        XCTAssertTrue(app.alerts["Delete this entry?"].waitForExistence(timeout: 2))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(app.textFields["food-description"].exists)
    }

    func testJournalLastEntryRemainsReachableAboveGlassNavigation() {
        for appearance in ["1", "2"] {
            launch(resetStore: true, extraArguments: [
                "--seed-ui-test-navigation", "-foodLogAppearance", appearance
            ])
            let last = journalEntry(containing: "Navigation fixture 20")
            let journal = app.buttons["Journal"]
            let addButton = app.buttons["bottom-add-entry"]
            app.scrollViews.firstMatch.swipeUp()
            XCTAssertGreaterThan(app.scrollViews.firstMatch.frame.maxY, journal.frame.minY)
            let underlap = XCTAttachment(screenshot: app.screenshot())
            underlap.name = "Content beneath glass \(appearance == "1" ? "light" : "dark")"
            underlap.lifetime = .keepAlways
            add(underlap)
            for _ in 0..<15 {
                if last.isHittable && last.frame.maxY < addButton.frame.minY - 8 { break }
                app.scrollViews.firstMatch.swipeUp()
            }
            XCTAssertTrue(last.isHittable)
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "Glass navigation \(appearance == "1" ? "light" : "dark")"
            capture.lifetime = .keepAlways
            add(capture)
            XCTAssertLessThan(last.frame.maxY, addButton.frame.minY - 8)
            last.tap()
            XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout: 3))
            XCTAssertEqual(app.textFields["food-description"].value as? String, "Navigation fixture 20")
            app.terminate()
        }
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
        let appearance = app.buttons["settings-appearance"]
        appearance.tap()
        let dark = app.buttons["Dark"]
        XCTAssertTrue(dark.waitForExistence(timeout: 2))
        dark.tap()
        XCTAssertTrue(appearance.label.contains("Dark"))
    }

    func testBottomNavigationCapturesTouchesAcrossButtonEdges() {
        launch(resetStore: true, extraArguments: ["--seed-ui-test-navigation"])
        XCTAssertTrue(app.navigationBars["Savour"].waitForExistence(timeout: 3))

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
        XCTAssertTrue(app.navigationBars["Savour"].waitForExistence(timeout: 2))
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
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
            // Audit Savour's editor controls after dismissing the system
            // keyboard, whose prediction buttons have their own audit issues.
            let dateAndTime = app.buttons["Date and time"]
            dateAndTime.tap()
            app.buttons["date-time-done"].tap()
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            try auditVisibleUI()
            app.buttons["Cancel"].tap()
            if app.alerts["Close this entry?"].waitForExistence(timeout: 1) {
                app.buttons["Keep draft"].tap()
            }
            waitForEditorDismissal()

            app.buttons["Settings"].tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
            // Bring the privacy controls above the glass before checking their
            // text contrast; deliberately refracted offscreen content is not
            // readable text and can produce an unattributed contrast finding.
            revealAboveNavigation(app.descendants(matching: .any)["dime-source-link"])
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
        for tab in ["Fasts", "Patterns", "Settings", "Journal"] {
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

    func testNativeJournalSearchClearKeepsSearchOpenAndCancelDismissesIt() {
        launch(resetStore: true, extraArguments: ["--seed-ui-test-overnight"])
        app.buttons["journal-search-button"].tap()
        let field = app.searchFields["Search entries"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.typeText("not a logged meal")
        XCTAssertTrue(app.staticTexts["Nothing found"].waitForExistence(timeout: 2))
        field.buttons["Clear text"].tap()
        XCTAssertTrue(field.isHittable)
        XCTAssertFalse(app.staticTexts["Nothing found"].exists)
        field.typeText("not a logged meal")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.staticTexts["Nothing found"].exists)
        XCTAssertFalse(app.buttons["Cancel"].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.buttons["journal-search-button"].exists)
    }

    func testFastingSettingsContainGoalControlsInsteadOfDuplicatePage() {
        launch(resetStore: true)
        app.buttons["Settings"].tap()
        revealAboveNavigation(app.switches["fasting-goal-enabled"])
        XCTAssertTrue(app.switches["fasting-goal-enabled"].exists)
        XCTAssertTrue(app.steppers["fasting-goal-hours"].exists)
        XCTAssertFalse(app.buttons.matching(identifier: "Fasts").allElementsBoundByIndex.count > 1)
    }

    func testGroupedSettingsPreserveExistingOptionsAndAccentSelection() {
        launch(resetStore: true, extraArguments: ["--seed-ui-test-map"])
        app.tabBars.firstMatch.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["settings-appearance"].exists)
        let accent = app.buttons["settings-accent-color"]
        accent.tap()
        XCTAssertTrue(app.navigationBars["Accent color"].waitForExistence(timeout: 3))
        for color in ["Teal", "Ocean", "Blue", "Violet", "Rose"] {
            XCTAssertTrue(app.buttons[color].exists)
        }
        app.buttons["Blue"].tap()
        if app.navigationBars["Accent color"].exists {
            app.navigationBars["Accent color"].buttons.firstMatch.tap()
        }
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertEqual(accent.value as? String, "Blue")
        XCTAssertTrue(app.switches["settings-meal-labels"].exists)
        app.buttons["settings-meal-times"].tap()
        XCTAssertTrue(app.navigationBars["Default meal times"].waitForExistence(timeout: 3))
        app.navigationBars["Default meal times"].buttons.firstMatch.tap()
        for identifier in ["fasting-goal-enabled", "fasting-goal-hours",
                           "relock-delay", "settings-export-csv", "settings-import-csv",
                           "settings-erase-entries", "dime-source-link"] {
            revealAboveNavigation(app.descendants(matching: .any)[identifier])
            if identifier == "relock-delay" {
                // App lock remains visible even when biometrics are unavailable
                // and its native toggle is intentionally disabled.
                XCTAssertTrue(app.switches["settings-app-lock"].exists)
            }
        }
        app.terminate()
        launch(resetStore: false)
        app.tabBars.firstMatch.buttons["Settings"].tap()
        XCTAssertEqual(accent.value as? String, "Blue")
    }

    func testNotificationTimeAndEnableSettingPersistAcrossRelaunch() {
        launch(resetStore: true)
        app.tabBars.firstMatch.buttons["Settings"].tap()
        revealAboveNavigation(app.buttons["settings-notifications"])
        app.buttons["settings-notifications"].tap()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 3))
        let enabled = app.switches["notifications-enabled"]
        XCTAssertEqual(enabled.value as? String, "0")
        let firstTime = app.descendants(matching: .any)["notifications-time-1"].firstMatch
        XCTAssertTrue(firstTime.waitForExistence(timeout: 3))
        let initialValue = firstTime.value as? String
        app.buttons["notifications-add-reminder"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["notifications-time-2"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["notifications-add-reminder"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["notifications-time-3"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["notifications-add-reminder"].exists)
        enabled.tap()
        let on = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: enabled)
        XCTAssertEqual(XCTWaiter.wait(for: [on], timeout: 3), .completed)
        XCTAssertTrue(app.buttons["notifications-open-settings"].exists)
        app.terminate()
        launch(resetStore: false)
        app.tabBars.firstMatch.buttons["Settings"].tap()
        revealAboveNavigation(app.buttons["settings-notifications"])
        app.buttons["settings-notifications"].tap()
        XCTAssertEqual(enabled.value as? String, "1")
        XCTAssertTrue(app.descendants(matching: .any)["notifications-time-3"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(firstTime.value as? String, initialValue)
        XCTAssertFalse(app.buttons["notifications-add-reminder"].exists)
        enabled.tap()
        let off = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0"), object: enabled)
        XCTAssertEqual(XCTWaiter.wait(for: [off], timeout: 3), .completed)
    }

    func testExtraNotificationTimesCanBeRemovedAndAddedAgain() {
        launch(resetStore: true)
        app.tabBars.firstMatch.buttons["Settings"].tap()
        revealAboveNavigation(app.buttons["settings-notifications"])
        app.buttons["settings-notifications"].tap()
        app.buttons["notifications-add-reminder"].tap()
        let secondTime = app.descendants(matching: .any)["notifications-time-2"].firstMatch
        XCTAssertTrue(secondTime.waitForExistence(timeout: 3))
        secondTime.swipeLeft()
        app.buttons["Delete"].tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: secondTime)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 3), .completed)
        XCTAssertTrue(app.descendants(matching: .any)["notifications-time-1"].firstMatch.exists)
        app.buttons["notifications-add-reminder"].tap()
        XCTAssertTrue(secondTime.waitForExistence(timeout: 3))
    }

    func testDeniedNotificationPermissionLeavesReminderOffWithSettingsLink() {
        launch(resetStore: true, extraArguments: ["--simulate-notifications-denied"])
        app.tabBars.firstMatch.buttons["Settings"].tap()
        revealAboveNavigation(app.buttons["settings-notifications"])
        app.buttons["settings-notifications"].tap()
        let enabled = app.switches["notifications-enabled"]
        XCTAssertTrue(enabled.waitForExistence(timeout: 3))
        enabled.tap()
        XCTAssertTrue(app.buttons["notifications-open-settings"].waitForExistence(timeout: 3))
        XCTAssertEqual(enabled.value as? String, "0")
    }

    func testNotificationSettingsLinkIsAvailableBeforeEnabling() {
        launch(resetStore: true)
        app.tabBars.firstMatch.buttons["Settings"].tap()
        revealAboveNavigation(app.buttons["settings-notifications"])
        app.buttons["settings-notifications"].tap()
        XCTAssertEqual(app.switches["notifications-enabled"].value as? String, "0")
        XCTAssertTrue(app.buttons["notifications-open-settings"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "then enable notifications")).firstMatch.exists)
    }

    func testSettingsAboutHasInlineAttributionAndCenteredVersionBuildFooter() {
        launch(resetStore: true)
        app.tabBars.firstMatch.buttons["Settings"].tap()
        let version = app.staticTexts["settings-version"]
        revealAboveNavigation(version)
        let credit = app.staticTexts["settings-credit"]
        let attribution = app.descendants(matching: .any)["dime-source-link"].firstMatch
        XCTAssertTrue(attribution.exists)
        XCTAssertTrue(attribution.label.contains("Adapted from Dime"))
        XCTAssertFalse(app.buttons["View Dime on GitHub"].exists)
        XCTAssertEqual(credit.label, "Built with ❤️ by Viraat")
        XCTAssertTrue(version.label.hasPrefix("Savour "))
        XCTAssertTrue(version.label.contains("(Build "))
        XCTAssertLessThan(credit.frame.maxY, version.frame.minY)
        XCTAssertEqual(credit.frame.midX, version.frame.midX, accuracy: 2)
        XCTAssertEqual(version.frame.midX, app.frame.midX, accuracy: 4)
    }

    func testSettingsGroupedLayoutInLightAndDarkMode() {
        for appearance in ["1", "2"] {
            launch(resetStore: true, extraArguments: ["--seed-ui-test-map", "-foodLogAppearance", appearance])
            app.tabBars.firstMatch.buttons["Settings"].tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["settings-appearance"].isHittable)
            let top = XCTAttachment(screenshot: app.screenshot())
            top.name = "Settings \(appearance == "1" ? "light" : "dark") upper sections"
            top.lifetime = .keepAlways
            add(top)
            let export = app.buttons["settings-export-csv"]
            revealAboveNavigation(export)
            XCTAssertTrue(export.label.contains("1 entry"))
            revealAboveNavigation(app.descendants(matching: .any)["dime-source-link"])
            let bottom = XCTAttachment(screenshot: app.screenshot())
            bottom.name = "Settings \(appearance == "1" ? "light" : "dark") lower sections"
            bottom.lifetime = .keepAlways
            add(bottom)
            app.terminate()
        }
    }

    func testAccessibilityAuditOnGroupedSettings() throws {
        guard #available(iOS 17.0, *) else { return }
        for appearance in ["1", "2"] {
            launch(resetStore: true, extraArguments: ["--seed-ui-test-map", "-foodLogAppearance", appearance])
            app.tabBars.firstMatch.buttons["Settings"].tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
            try auditVisibleUI()
            revealAboveNavigation(app.descendants(matching: .any)["dime-source-link"])
            try auditVisibleUI()
            app.terminate()
        }
    }

    func testSettingsAccessibilityHierarchyForDiagnostics() {
        launch(resetStore: true)
        app.tabBars.firstMatch.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["settings-appearance"].isHittable)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Grouped settings accessibility hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Grouped settings diagnostic screenshot"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testNativeNavigationTitlesOnEveryPage() {
        launch(resetStore: true)
        for (tab, title) in [("Journal", "Savour"), ("Fasts", "Fasts"),
                             ("Patterns", "Patterns"), ("Settings", "Settings")] {
            app.tabBars.firstMatch.buttons[tab].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3))
        }
    }

    func testCompactNativeTitlesShareTheJournalControlsRow() {
        guard #available(iOS 17.0, *) else { return }
        launch(resetStore: true)
        let journalBar = app.navigationBars["Savour"]
        XCTAssertTrue(journalBar.waitForExistence(timeout: 3))
        let title = journalBar.staticTexts["Savour"].firstMatch
        let search = app.buttons["journal-search-button"]
        let filter = app.buttons["Filter by meal type"]
        XCTAssertTrue(title.exists)
        XCTAssertTrue(search.isHittable)
        XCTAssertTrue(filter.isHittable)
        XCTAssertEqual(title.frame.midY, search.frame.midY, accuracy: 12)
        XCTAssertEqual(title.frame.midY, filter.frame.midY, accuracy: 12)
        let titleMidY = title.frame.midY
        for (tab, page) in [("Fasts", "Fasts"), ("Patterns", "Patterns"), ("Settings", "Settings")] {
            app.tabBars.firstMatch.buttons[tab].tap()
            let bar = app.navigationBars[page]
            XCTAssertTrue(bar.waitForExistence(timeout: 3))
            let pageTitle = bar.staticTexts[page].firstMatch
            XCTAssertTrue(pageTitle.exists)
            XCTAssertEqual(pageTitle.frame.midY, titleMidY, accuracy: 12)
        }
    }

    func testFastingAverageDoesNotChangeWhenHistoryExpandsOrCalendarMonthChanges() {
        launch(resetStore: true, extraArguments: ["--seed-ui-test-fasting-history"])
        app.tabBars.firstMatch.buttons["Fasts"].tap()
        let average = app.descendants(matching: .any)["fasting-history-average"]
        XCTAssertTrue(average.waitForExistence(timeout: 3))
        XCTAssertTrue(average.label.contains("all 65 completed fasts"))
        let originalLabel = average.label
        XCTAssertTrue(app.descendants(matching: .any)["fasting-goal-legend"].label.contains("at least 14h"))
        app.buttons["Previous month"].tap()
        XCTAssertEqual(average.label, originalLabel)
        let more = app.buttons["fasting-history-more"]
        for _ in 0..<20 {
            if more.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(more.isHittable)
        more.tap()
        for _ in 0..<25 {
            if average.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(average.isHittable)
        XCTAssertEqual(average.label, originalLabel)
    }

    func testPatternCountsAreNotExposedAsTaskProgress() {
        launch(resetStore: true, extraArguments: ["--seed-ui-test-suggestions"])
        app.tabBars.firstMatch.buttons["Patterns"].tap()
        app.buttons["Overview"].tap()
        XCTAssertTrue(app.navigationBars["Overview"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["DAYS WITH ENTRIES"].exists)
        XCTAssertEqual(app.progressIndicators.count, 0)
        app.buttons["Done"].tap()
        app.buttons["Foods noted"].tap()
        XCTAssertTrue(app.navigationBars["Foods noted"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.progressIndicators.count, 0)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ AND value CONTAINS %@", "Toast", "2"
        )).firstMatch.exists)
    }

    func testCurrentFastRestoresOnRelaunchAndRestartsWithNextMeal() {
        launch(resetStore: true, extraArguments: ["--seed-ui-test-overnight"])
        app.buttons["Fasts"].tap()
        let current = app.descendants(matching: .any)["fasting-current"]
        XCTAssertTrue(current.waitForExistence(timeout: 3))
        XCTAssertTrue(current.label.contains("Current fast estimate, last logged meal"))
        app.terminate()
        launch(resetStore: false)
        app.buttons["Fasts"].tap()
        XCTAssertTrue(current.waitForExistence(timeout: 3))
        app.buttons["Add entry"].tap()
        let food = app.textFields["food-description"]
        XCTAssertTrue(food.waitForExistence(timeout: 3))
        food.tap()
        food.typeText("Next logged meal")
        app.buttons["Meal type"].tap()
        app.buttons["Breakfast"].tap()
        app.buttons["Date and time"].tap()
        app.buttons["Set time to now"].tap()
        app.buttons["date-time-done"].tap()
        app.buttons["Add"].tap()
        waitForEditorDismissal()
        XCTAssertTrue(current.waitForExistence(timeout: 3))
        XCTAssertTrue(current.label.contains("elapsed 0h 0m"))
    }

    func testAutomaticOvernightEstimateRelaunchEditDeleteAndLegacyPreservation() {
        launch(resetStore: true, extraArguments: ["--seed-ui-test-overnight"])
        XCTAssertFalse(app.staticTexts["overnight-duration"].exists)
        verifyFastingDuration("10h 0m")
        XCTAssertFalse(app.buttons["end-fast"].exists)
        app.terminate()
        launch(resetStore: false)
        verifyFastingDuration("10h 0m")
        app.buttons["Add entry"].tap()
        XCTAssertFalse(app.switches["start-fast-after-meal"].exists)
        app.buttons["Cancel"].tap()
        let breakfast = journalEntry(containing: "Overnight breakfast")
        revealAboveNavigation(breakfast)
        breakfast.tap()
        app.buttons["Date and time"].tap()
        app.buttons["Add 5 minutes"].tap()
        app.buttons["date-time-done"].tap()
        app.buttons["Save"].tap()
        app.scrollViews.firstMatch.swipeDown()
        verifyFastingDuration("10h 5m")
        revealAboveNavigation(breakfast)
        breakfast.press(forDuration: 1)
        app.buttons["Delete"].tap()
        app.alerts.buttons["Delete"].tap()
        app.scrollViews.firstMatch.swipeDown()
        verifyFastingDuration("14h 0m")
        app.buttons["Fasts"].tap()
        XCTAssertTrue(app.navigationBars["Fasts"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Add"].exists)
        XCTAssertTrue(app.staticTexts["Previously saved fasting records"].exists)
        XCTAssertTrue(app.staticTexts["12h 0m"].exists)
        app.buttons["Patterns"].tap()
        XCTAssertTrue(app.staticTexts["FASTS"].exists)
        XCTAssertTrue(app.staticTexts["Average gap"].exists)
        XCTAssertTrue(app.staticTexts["Latest gap"].exists)
    }

    private func verifyFastingDuration(_ duration: String) {
        app.buttons["Fasts"].tap()
        XCTAssertTrue(app.navigationBars["Fasts"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any)["fasting-month-calendar"].exists)
        let row = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "fasting-history-", duration
        )).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        if !row.isHittable { app.swipeUp() }
        row.tap()
        XCTAssertTrue(app.staticTexts["overnight-duration"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["overnight-duration"].label, duration)
        app.buttons["Done"].tap()
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.staticTexts["overnight-duration"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 3), .completed)
        app.buttons["Journal"].tap()
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
            let details = XCTAttachment(string: "\(issue.auditType): \(issue.element?.debugDescription ?? "No identified element")")
            details.name = "Accessibility finding details"
            details.lifetime = .keepAlways
            self.add(details)
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
                let tabBar = self.app.tabBars.firstMatch
                if tabBar.exists && element.frame.maxY >= tabBar.frame.minY - 32 { return true }
                // Native navigation scroll-edge blur also refracts scrolled
                // text. Do not exempt the navigation title or toolbar controls.
                let navigationBar = self.app.navigationBars.firstMatch
                let belongsToScrollContent = element.elementType == .staticText &&
                    self.app.scrollViews.firstMatch.staticTexts[element.label].exists
                return belongsToScrollContent && element.frame.minY < navigationBar.frame.maxY
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
            let barTop = app.buttons["bottom-add-entry"].frame.minY
            if fixture.isHittable && fixture.frame.maxY < barTop - 8 { break }
            app.swipeUp()
        }
        XCTAssertTrue(fixture.isHittable)
        XCTAssertLessThan(fixture.frame.maxY, app.buttons["bottom-add-entry"].frame.minY)
        fixture.tap()
    }

    private func revealAboveNavigation(_ element: XCUIElement) {
        for _ in 0..<12 {
            if element.isHittable && element.frame.maxY < app.buttons["bottom-add-entry"].frame.minY - 8 { break }
            // Works for both ScrollView content and native Form/List sections.
            app.swipeUp()
        }
        if !element.isHittable {
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "Unreachable control"
            capture.lifetime = .keepAlways
            add(capture)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Unreachable control hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(element.isHittable)
        XCTAssertLessThan(element.frame.maxY, app.buttons["bottom-add-entry"].frame.minY - 8)
    }

    private func waitForEditorDismissal() {
        let dismissal = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.textFields["food-description"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissal], timeout: 3), .completed)
        let addReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: app.buttons["Add entry"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [addReady], timeout: 3), .completed)
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

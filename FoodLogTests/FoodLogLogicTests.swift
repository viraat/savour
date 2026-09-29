import CoreData
import XCTest
@testable import FoodLog

final class FoodLogLogicTests: XCTestCase {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        utcCalendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    func testFoodItemParserTrimsAndDropsEmptyItems() {
        XCTAssertEqual(
            FoodItemParser.items(in: " Toast,  eggs ,, coffee \n"),
            ["Toast", "eggs", "coffee"]
        )
    }

    func testCompanionParserSplitsLegacyNamesAndRemovesDuplicates() {
        XCTAssertEqual(
            CompanionNames.parse("Ana and Bob & Cara; ana\nDev"),
            ["Ana", "Bob", "Cara", "Dev"]
        )
    }

    func testSuggestedMealTypeBoundaries() {
        XCTAssertEqual(MealTypeSuggestion.suggested(for: date(2026, 9, 11, 5), calendar: utcCalendar), "Breakfast")
        XCTAssertEqual(MealTypeSuggestion.suggested(for: date(2026, 9, 11, 10, 59), calendar: utcCalendar), "Breakfast")
        XCTAssertEqual(MealTypeSuggestion.suggested(for: date(2026, 9, 11, 11), calendar: utcCalendar), "Lunch")
        XCTAssertEqual(MealTypeSuggestion.suggested(for: date(2026, 9, 11, 15), calendar: utcCalendar), "Snack")
        XCTAssertEqual(MealTypeSuggestion.suggested(for: date(2026, 9, 11, 18), calendar: utcCalendar), "Dinner")
        XCTAssertEqual(MealTypeSuggestion.suggested(for: date(2026, 9, 11, 23), calendar: utcCalendar), "Snack")
    }

    func testSuggestionsUseIndividualFoodsAcrossMealsAndDeduplicatePerEntry() {
        let sources = [
            FoodSuggestionSource(mealType: "Breakfast", food: "Toast, Eggs, toast"),
            FoodSuggestionSource(mealType: "Breakfast", food: "eggs, Coffee"),
            FoodSuggestionSource(mealType: "Breakfast", food: "Toast"),
            FoodSuggestionSource(mealType: "Dinner", food: "Pasta, Toast")
        ]

        XCTAssertEqual(
            FoodSuggestionEngine.suggestions(
                from: sources,
                mealType: "Breakfast",
                currentFood: "eggs, ",
                limit: 8
            ),
            ["Toast", "Coffee", "Pasta"]
        )
    }

    func testFoodSuggestionsMatchOnlyCurrentSegmentAndExcludeExistingFoods() {
        let sources = [
            FoodSuggestionSource(mealType: "Lunch", food: "Rice, Tofu  scramble"),
            FoodSuggestionSource(mealType: "Dinner", food: "Grilled tofu, Dal"),
            FoodSuggestionSource(mealType: "Lunch", food: "Tofu, rice, tofu")
        ]

        XCTAssertEqual(
            FoodSuggestionEngine.suggestions(
                from: sources,
                mealType: "Lunch",
                currentFood: " rice , DAL, tof"
            ),
            ["Tofu", "Tofu scramble", "Grilled tofu"]
        )
        XCTAssertEqual(
            FoodSuggestionEngine.suggestions(
                from: sources,
                mealType: "Lunch",
                currentFood: "Rice, tofu, gri"
            ),
            ["Grilled tofu"]
        )
    }

    func testFoodSuggestionRankingUsesMatchMealFrequencyAndRecency() {
        let sources = [
            FoodSuggestionSource(mealType: "Dinner", food: "Tofu scramble", date: date(2026, 9, 1)),
            FoodSuggestionSource(mealType: "Dinner", food: "Tofu scramble", date: date(2026, 9, 2)),
            FoodSuggestionSource(mealType: "Lunch", food: "Tofu salad", date: date(2026, 9, 1)),
            FoodSuggestionSource(mealType: "Lunch", food: "Tofu soup", date: date(2026, 9, 3)),
            FoodSuggestionSource(mealType: "Lunch", food: "Tofu scramble", date: date(2026, 9, 2)),
            FoodSuggestionSource(mealType: "Lunch", food: "Grilled tofu", date: date(2026, 9, 4))
        ]

        XCTAssertEqual(
            FoodSuggestionEngine.suggestions(
                from: sources,
                mealType: "Lunch",
                currentFood: "tof"
            ),
            ["Tofu scramble", "Tofu soup", "Tofu salad", "Grilled tofu"]
        )
        XCTAssertEqual(
            FoodSuggestionEngine.suggestions(
                from: sources,
                mealType: "Breakfast",
                currentFood: "tof",
                limit: 2
            ),
            ["Tofu scramble", "Tofu soup"]
        )
    }

    func testFoodSuggestionsNormalizeWhitespaceAndAllowSmallTypos() {
        let sources = [
            FoodSuggestionSource(mealType: "Lunch", food: "Tofu  scramble, tofu scramble"),
            FoodSuggestionSource(mealType: "Lunch", food: "Tofu")
        ]

        XCTAssertEqual(
            FoodSuggestionEngine.suggestions(from: sources, mealType: "Lunch", currentFood: "tofu   scrambl"),
            ["Tofu scramble"]
        )
        XCTAssertEqual(
            FoodSuggestionEngine.suggestions(from: sources, mealType: "Lunch", currentFood: "tofu", limit: 8),
            ["Tofu scramble"]
        )
        XCTAssertEqual(
            FoodSuggestionEngine.suggestions(from: sources, mealType: "Lunch", currentFood: "tofu scrambel"),
            ["Tofu scramble"]
        )
        XCTAssertEqual(
            FoodSuggestionEngine.suggestions(from: sources, mealType: "Lunch", currentFood: "tifu", limit: 1),
            ["Tofu"]
        )
    }

    func testReplacingFoodSuggestionKeepsEarlierSegmentsUnchanged() {
        XCTAssertEqual(
            FoodSuggestionEngine.replacingCurrentSegment(in: "rice, dal, tof", with: "Tofu"),
            "rice, dal, Tofu"
        )
        XCTAssertEqual(
            FoodSuggestionEngine.replacingCurrentSegment(in: " rice ,  dal,tof", with: "Tofu"),
            " rice ,  dal, Tofu"
        )
        XCTAssertEqual(
            FoodSuggestionEngine.replacingCurrentSegment(in: "tof", with: "Tofu"),
            "Tofu"
        )
    }

    func testFrequencyStatisticsAreCaseInsensitiveAndStable() {
        XCTAssertEqual(
            FoodLogStatistics.frequencies([" Cafe ", "cafe", "Home", "", "home"]),
            [FrequencyCount(name: "Cafe", count: 2), FrequencyCount(name: "Home", count: 2)]
        )
    }

    func testCurrentStreakCountsUniqueConsecutiveDays() {
        let today = date(2026, 9, 11, 12)
        XCTAssertEqual(
            FoodLogStatistics.currentStreak(
                entryDates: [date(2026, 9, 11), date(2026, 9, 11, 18), date(2026, 9, 10), date(2026, 9, 9)],
                relativeTo: today,
                calendar: utcCalendar
            ),
            3
        )
    }

    func testCurrentStreakMayContinueFromYesterdayButStopsAtGap() {
        let today = date(2026, 9, 11, 12)
        XCTAssertEqual(
            FoodLogStatistics.currentStreak(
                entryDates: [date(2026, 9, 10), date(2026, 9, 9), date(2026, 9, 7)],
                relativeTo: today,
                calendar: utcCalendar
            ),
            2
        )
        XCTAssertEqual(
            FoodLogStatistics.currentStreak(
                entryDates: [date(2026, 9, 9)],
                relativeTo: today,
                calendar: utcCalendar
            ),
            0
        )
    }

    func testDefaultMealTimesPreserveTheSelectedDay() {
        let suiteName = "FoodLogTests.defaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let customLunch = date(2026, 1, 1, 14, 25)
        MealDefaultTimes.set(customLunch, for: "Lunch", defaults: defaults, calendar: utcCalendar)
        let original = date(2026, 9, 11, 7, 40)
        let updated = MealDefaultTimes.applyingDefault(
            for: "Lunch",
            to: original,
            defaults: defaults,
            calendar: utcCalendar
        )

        let components = utcCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: updated)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 9)
        XCTAssertEqual(components.day, 11)
        XCTAssertEqual(components.hour, 14)
        XCTAssertEqual(components.minute, 25)
    }

    func testSnackDrinkAndOtherHaveNoDefaultTime() {
        for meal in ["Snack", "Drink", "Other"] {
            XCTAssertNil(MealDefaultTimes.minutes(for: meal))
        }
    }

    func testCSVCodecRoundTripsCommasQuotesAndNewlines() throws {
        let dataRows = [[
            "Soup, bread and \"tea\"",
            "2026-09-11",
            "12:05",
            "Lunch",
            "Corner Cafe, Hyderabad",
            "Hyderabad",
            "17.385",
            "78.4867",
            "Ana, Bob",
            "A note\nwith another line"
        ]]

        let encoded = FoodLogCSVDocument.encode(dataRows: dataRows)
        XCTAssertEqual(try FoodLogCSVDocument.decode(encoded), dataRows)
    }

    func testCSVExporterRoundTripsAStoredEntry() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let entry = FoodEntry(context: context)
        entry.id = UUID()
        entry.food = "Dosa, chutney"
        entry.date = Calendar.current.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 11,
            hour: 8,
            minute: 15
        ))!
        entry.mealType = "Breakfast"
        entry.place = "Roastery Coffee House, Hyderabad"
        entry.placeCity = "Hyderabad"
        entry.hasPlaceCoordinates = true
        entry.placeLatitude = 17.4239
        entry.placeLongitude = 78.4485
        entry.note = "Quiet table"
        entry.replaceCompanions(with: ["Ana", "Bob"], in: context)
        try context.save()

        let url = try XCTUnwrap(CSVExporter.makeFile(from: [entry]))
        defer { try? FileManager.default.removeItem(at: url) }
        let rows = try FoodLogCSVDocument.decode(String(contentsOf: url, encoding: .utf8))

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0][0], "Dosa, chutney")
        XCTAssertEqual(rows[0][1], "2026-09-11")
        XCTAssertEqual(rows[0][2], "08:15")
        XCTAssertEqual(rows[0][8], "Ana, Bob")
        XCTAssertEqual(rows[0][9], "Quiet table")
        XCTAssertEqual(rows[0][10], entry.id?.uuidString)
        XCTAssertEqual(try JSONDecoder().decode([String].self, from: Data(rows[0][11].utf8)), ["Ana", "Bob"])
    }

    func testCSVExporterCreatesValidHeaderForEmptyJournal() throws {
        let url = try XCTUnwrap(CSVExporter.makeFile(from: []))
        defer { try? FileManager.default.removeItem(at: url) }
        let rows = try FoodLogCSVDocument.decode(String(contentsOf: url, encoding: .utf8))
        XCTAssertTrue(rows.isEmpty)
    }

    func testExportImportRestoresTextFieldsAndSkipsRepeatImport() throws {
        let source = PersistenceController(inMemory: true).container.viewContext
        let original = FoodEntry(context: source)
        original.id = UUID()
        original.createdAt = Date()
        original.food = "Soup, bread and \"tea\"\nwith cake"
        original.date = Calendar.current.date(from: DateComponents(
            year: 2026, month: 9, day: 11, hour: 12, minute: 5, second: 17
        ))!
        original.mealType = "Lunch"
        original.place = "Corner \"Cafe\", Hyderabad"
        original.placeCity = "Hyderabad"
        original.hasPlaceCoordinates = true
        original.placeLatitude = 17.385
        original.placeLongitude = 78.4867
        original.note = "First line, \"quoted\"\nSecond line"
        original.replaceCompanions(with: ["Smith, Jane", "Ana \"Ace\"\nLee"], in: source)
        try source.save()

        let url = try XCTUnwrap(CSVExporter.makeFile(from: [original]))
        defer { try? FileManager.default.removeItem(at: url) }
        let csv = try String(contentsOf: url, encoding: .utf8)
        let destination = PersistenceController(inMemory: true).container.viewContext
        let preview = try FoodLogCSVImporter.preview(csv, fileName: "FoodLog.csv", existingEntries: [])
        XCTAssertEqual(preview.importableCount, 1)
        XCTAssertTrue(preview.issues.isEmpty)
        XCTAssertEqual(try FoodLogCSVImporter.commit(preview, to: destination), 1)

        let restored = try XCTUnwrap(destination.fetch(FoodEntry.fetchRequest()).first)
        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.food, original.food)
        XCTAssertEqual(restored.date, original.date)
        XCTAssertEqual(restored.mealType, original.mealType)
        XCTAssertEqual(restored.place, original.place)
        XCTAssertEqual(restored.placeCity, original.placeCity)
        XCTAssertEqual(restored.placeLatitude, original.placeLatitude)
        XCTAssertEqual(restored.placeLongitude, original.placeLongitude)
        XCTAssertEqual(restored.companionNames, original.companionNames)
        XCTAssertEqual(restored.note, original.note)
        XCTAssertEqual(CSVExporter.row(for: restored), CSVExporter.row(for: original))

        let repeatPreview = try FoodLogCSVImporter.preview(
            csv, fileName: "FoodLog.csv", existingEntries: [restored]
        )
        XCTAssertEqual(repeatPreview.duplicateCount, 1)
        XCTAssertEqual(try FoodLogCSVImporter.commit(repeatPreview, to: destination), 0)
        XCTAssertEqual(try destination.count(for: FoodEntry.fetchRequest()), 1)
    }

    func testLegacyCSVImportsAndPreviewSkipsInvalidAndDuplicateRows() throws {
        let valid = ["Toast, jam", "2026-09-11", "08:00", "Breakfast", "Home", "", "", "", "Ana, Bob", "A note\nwith a quote \"here\""]
        var invalidDate = valid
        invalidDate[1] = "September 11"
        var invalidCoordinates = valid
        invalidCoordinates[6] = "91"
        invalidCoordinates[7] = "78"
        let csv = FoodLogCSVDocument.encode(dataRows: [valid, invalidDate, valid, invalidCoordinates])
        let context = PersistenceController(inMemory: true).container.viewContext

        let preview = try FoodLogCSVImporter.preview(csv, fileName: "old.csv", existingEntries: [])
        XCTAssertTrue(preview.isLegacyFormat)
        XCTAssertEqual(preview.importableCount, 1)
        XCTAssertEqual(preview.duplicateCount, 1)
        XCTAssertEqual(preview.issues.map(\.rowNumber), [3, 5])
        XCTAssertEqual(try FoodLogCSVImporter.commit(preview, to: context), 1)

        let restored = try XCTUnwrap(context.fetch(FoodEntry.fetchRequest()).first)
        XCTAssertEqual(restored.food, valid[0])
        XCTAssertEqual(restored.companionNames, ["Ana", "Bob"])
        XCTAssertEqual(restored.note, valid[9])
        XCTAssertEqual(Array(CSVExporter.row(for: restored).prefix(10)), valid)
    }

    func testMalformedCSVIsRejected() {
        assertCSVError("\"food", equals: .unterminatedQuotedField)
        assertCSVError("fo\"od", equals: .unexpectedQuote)
        assertCSVError("\"food\"oops", equals: .charactersAfterClosingQuote)
        assertDocumentError("", equals: .missingHeader)
        assertDocumentError("food,date\n", equals: .invalidHeader)

        let valid = ["Toast", "2026-09-11", "08:00", "Breakfast", "", "", "", "", "", ""]
        assertDocumentError(
            CSVCodec.encode(rows: [FoodLogCSVDocument.header, Array(valid.dropLast())]),
            equals: .wrongColumnCount(row: 2, expected: 10, actual: 9)
        )
        assertDocumentError(
            FoodLogCSVDocument.encode(dataRows: [["", "2026-09-11", "08:00", "Breakfast", "", "", "", "", "", ""]]),
            equals: .emptyFood(row: 2)
        )
        assertDocumentError(
            FoodLogCSVDocument.encode(dataRows: [["Toast", "September 11", "08:00", "Breakfast", "", "", "", "", "", ""]]),
            equals: .invalidDate(row: 2)
        )
        assertDocumentError(
            FoodLogCSVDocument.encode(dataRows: [["Toast", "2026-09-11", "25:00", "Breakfast", "", "", "", "", "", ""]]),
            equals: .invalidTime(row: 2)
        )
        assertDocumentError(
            FoodLogCSVDocument.encode(dataRows: [["Toast", "2026-09-11", "08:00", "Breakfast", "", "", "91", "78", "", ""]]),
            equals: .invalidCoordinate(row: 2)
        )
        assertDocumentError(
            FoodLogCSVDocument.encode(dataRows: [["Toast", "2026-09-11", "08:00", "Breakfast", "", "", "17", "", "", ""]]),
            equals: .invalidCoordinate(row: 2)
        )
        assertDocumentError(
            FoodLogCSVDocument.encodeExtended(dataRows: [valid + ["bad-id", "[]", "1789113600"]]),
            equals: .invalidID(row: 2)
        )
        assertDocumentError(
            FoodLogCSVDocument.encodeExtended(dataRows: [valid + [UUID().uuidString, "not-json", "1789113600"]]),
            equals: .invalidPeople(row: 2)
        )
        assertDocumentError(
            FoodLogCSVDocument.encodeExtended(dataRows: [valid + [UUID().uuidString, "[]", "not-a-time"]]),
            equals: .invalidTimestamp(row: 2)
        )
    }

    func testPlaceFormattingKeepsOnlyPlaceNameAndCity() {
        XCTAssertEqual(
            PlaceFormatting.conciseName(
                place: "Roastery Coffee House, Road 12, Banjara Hills, Telangana",
                city: "Hyderabad"
            ),
            "Roastery Coffee House, Hyderabad"
        )
        XCTAssertEqual(PlaceFormatting.conciseName(place: "Hyderabad", city: "Hyderabad"), "Hyderabad")
        XCTAssertEqual(
            PlaceFormatting.fullAddress(
                placeName: "Roastery Coffee House",
                addressParts: ["Road No. 14", "Banjara Hills", "Hyderabad", "Telangana", "500034"]
            ),
            "Roastery Coffee House, Road No. 14, Banjara Hills, Hyderabad, Telangana, 500034"
        )
    }

    func testBackfillOnlyAcceptsSpecificExactPlaceNames() {
        XCTAssertTrue(PlaceFormatting.isConfidentBackfillMatch(
            query: "Roastery Coffee House, Hyderabad",
            resultName: "Roastery Coffee House"
        ))
        XCTAssertFalse(PlaceFormatting.isConfidentBackfillMatch(
            query: "Home",
            resultName: "Myhome Mandala"
        ))
        XCTAssertFalse(PlaceFormatting.isConfidentBackfillMatch(
            query: "Home",
            resultName: "Home"
        ))
        XCTAssertFalse(PlaceFormatting.isConfidentBackfillMatch(
            query: "Starbucks",
            resultName: "Starbucks Reserve"
        ))
    }

    func testSelectedLocationSavesConciseNameWhileFreeTextIsPreserved() {
        XCTAssertEqual(
            PlaceFormatting.savedPlaceName(
                typedValue: "Roastery Coffee House, Road No. 14, Banjara Hills, Hyderabad, Telangana, 500034",
                selectedDisplayName: "Roastery Coffee House, Hyderabad",
                hasCoordinates: true
            ),
            "Roastery Coffee House, Hyderabad"
        )
        XCTAssertEqual(
            PlaceFormatting.savedPlaceName(
                typedValue: "  Home  ",
                selectedDisplayName: nil,
                hasCoordinates: false
            ),
            "Home"
        )
    }

    func testLegacyEntryMigrationPreservesRawDataAndIsIdempotent() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let entry = FoodEntry(context: context)
        entry.food = "Dinner"
        entry.date = date(2026, 9, 11)
        entry.mealType = "Dinner"
        entry.people = "Ana and Bob, ana"
        entry.place = "Old Cafe, Hyderabad"
        entry.hasPlaceCoordinates = true
        entry.placeLatitude = 120
        entry.placeLongitude = 78
        try context.save()

        let report = try PersistenceController.migrateLegacyEntries(in: context)
        XCTAssertEqual(report.assignedIDs, 1)
        XCTAssertEqual(report.assignedCreationDates, 1)
        XCTAssertEqual(report.structuredPeople, 1)
        XCTAssertEqual(report.invalidCoordinatesDisabled, 1)
        XCTAssertEqual(entry.companionNames, ["Ana", "Bob"])
        XCTAssertEqual(entry.companionRecords.map(\.sortIndex), [0, 1])
        XCTAssertEqual(entry.wrappedPeople, "Ana and Bob, ana")
        XCTAssertEqual(entry.wrappedPlace, "Old Cafe, Hyderabad")
        XCTAssertNil(entry.placeCoordinates)
        XCTAssertEqual(try PersistenceController.migrateLegacyEntries(in: context), .init())
        XCTAssertEqual(entry.companionRecords.count, 2)
    }

    func testEveryHistoricalStoreVersionMigratesWithoutLosingEntries() throws {
        let modelDirectory = try XCTUnwrap(
            Bundle(for: FoodEntry.self).url(forResource: "FoodLog", withExtension: "momd")
        )
        for version in ["FoodLog", "FoodLogV2", "FoodLogV3", "FoodLogV4"] {
            let modelURL = modelDirectory.appendingPathComponent("\(version).mom")
            let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL))
            let storeURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("FoodLogMigration-\(UUID().uuidString).sqlite")
            defer {
                for suffix in ["", "-shm", "-wal"] {
                    try? FileManager.default.removeItem(atPath: storeURL.path + suffix)
                }
            }

            let originalID = UUID()
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
            let legacyStore = try coordinator.addPersistentStore(
                ofType: NSSQLiteStoreType,
                configurationName: nil,
                at: storeURL
            )
            let legacyContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            legacyContext.persistentStoreCoordinator = coordinator
            try legacyContext.performAndWait {
                for index in 0 ..< 2 {
                    let entry = NSEntityDescription.insertNewObject(forEntityName: "FoodEntry", into: legacyContext)
                    entry.setValue(originalID, forKey: "id")
                    entry.setValue("Legacy meal \(index)", forKey: "food")
                    entry.setValue(date(2026, 9, 8 + index, 19), forKey: "date")
                    entry.setValue("Dinner", forKey: "mealType")
                    entry.setValue(index == 0 ? "Ana and Bob" : "Cara", forKey: "people")
                    entry.setValue("Old Cafe \(index)", forKey: "place")
                    entry.setValue("Note \(index)", forKey: "note")
                    if version != "FoodLog" {
                        entry.setValue(Data([1, 2, UInt8(index)]), forKey: "photoData")
                    }
                    if version == "FoodLogV4" && index == 0 {
                        entry.setValue("Hyderabad", forKey: "placeCity")
                        entry.setValue(17.385, forKey: "placeLatitude")
                        entry.setValue(78.4867, forKey: "placeLongitude")
                        entry.setValue(true, forKey: "hasPlaceCoordinates")
                    }
                }
                try legacyContext.save()
            }
            try coordinator.remove(legacyStore)

            let migratedController = PersistenceController(storeURL: storeURL)
            let context = migratedController.container.viewContext
            let entries = try context.fetch(FoodEntry.fetchRequest())
            XCTAssertEqual(entries.count, 2, version)
            XCTAssertEqual(Set(entries.compactMap(\.id)).count, 2, version)
            XCTAssertTrue(entries.compactMap(\.id).contains(originalID), version)

            let first = try XCTUnwrap(entries.first { $0.food == "Legacy meal 0" })
            let second = try XCTUnwrap(entries.first { $0.food == "Legacy meal 1" })
            XCTAssertEqual(first.companionNames, ["Ana", "Bob"], version)
            XCTAssertEqual(second.companionNames, ["Cara"], version)
            XCTAssertEqual(first.wrappedPeople, "Ana and Bob", version)
            XCTAssertEqual(first.wrappedPlace, "Old Cafe 0", version)
            XCTAssertEqual(second.wrappedNote, "Note 1", version)
            XCTAssertEqual(first.createdAt, first.date, version)
            if version == "FoodLog" {
                XCTAssertNil(first.photoData)
            } else {
                XCTAssertEqual(first.photoData, Data([1, 2, 0]), version)
            }
            if version == "FoodLogV4" {
                XCTAssertEqual(first.wrappedPlaceCity, "Hyderabad")
                XCTAssertEqual(first.placeCoordinates?.latitude, 17.385)
                XCTAssertEqual(first.placeCoordinates?.longitude, 78.4867)
            } else {
                XCTAssertEqual(first.wrappedPlaceCity, "", version)
                XCTAssertNil(first.placeCoordinates)
            }
            let oldCSV = FoodLogCSVDocument.encode(dataRows: [Array(CSVExporter.row(for: first).prefix(10))])
            let importPreview = try FoodLogCSVImporter.preview(
                oldCSV, fileName: "old.csv", existingEntries: entries
            )
            XCTAssertEqual(importPreview.duplicateCount, 1, version)
            XCTAssertEqual(try FoodLogCSVImporter.commit(importPreview, to: context), 0, version)
            XCTAssertEqual(try context.count(for: FoodEntry.fetchRequest()), 2, version)
            XCTAssertEqual(try context.count(for: FastSession.fetchRequest()), 0, version)
            XCTAssertEqual(try PersistenceController.migrateLegacyEntries(in: context), .init(), version)
        }
    }

    func testFastLifecycleOverlapEditingAndDeletion() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let start = date(2026, 9, 14, 20)
        let first = try FastingStore.create(start: start, target: 14 * 3_600, in: context)
        try context.save()
        XCTAssertEqual(try FastingStore.active(in: context)?.objectID, first.objectID)
        XCTAssertEqual(first.targetSeconds, 14 * 3_600)
        XCTAssertThrowsError(try FastingStore.create(start: start.addingTimeInterval(3_600), in: context)) {
            XCTAssertEqual($0 as? FastingError, .overlapsExisting)
        }

        let end = date(2026, 9, 15, 10)
        try FastingStore.end(first, at: end)
        try context.save()
        XCTAssertNil(try FastingStore.active(in: context))
        XCTAssertEqual(first.duration, 14 * 3_600)

        let second = try FastingStore.create(start: end, end: end.addingTimeInterval(12 * 3_600), in: context)
        try context.save()
        XCTAssertNil(second.targetSeconds)
        XCTAssertThrowsError(try FastingStore.update(second, start: start, end: end, target: nil,
                                                      startEntryID: nil, endEntryID: nil, in: context)) {
            XCTAssertEqual($0 as? FastingError, .overlapsExisting)
        }
        try FastingStore.update(second, start: end.addingTimeInterval(3_600),
                                end: end.addingTimeInterval(10 * 3_600), target: 12 * 3_600,
                                startEntryID: nil, endEntryID: nil, in: context)
        try context.save()
        XCTAssertEqual(second.duration, 9 * 3_600)
        context.delete(second)
        try context.save()
        XCTAssertEqual(try FastingStore.sessions(in: context).count, 1)
    }

    func testFastLinksFollowMealEditsAndSurviveMealDeletion() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let meal = FoodEntry(context: context)
        meal.id = UUID()
        meal.food = "Dinner"
        meal.date = date(2026, 9, 16, 20)
        let fast = try FastingStore.create(start: meal.wrappedDate, target: nil,
                                           startEntryID: meal.id, in: context)
        try context.save()

        meal.date = date(2026, 9, 16, 21)
        try FastingStore.entryDateChanged(meal, in: context)
        try context.save()
        XCTAssertEqual(fast.startDate, meal.date)
        XCTAssertEqual(fast.startEntryID, meal.id)

        try FastingStore.detachEntry(meal, in: context)
        context.delete(meal)
        try context.save()
        XCTAssertNil(fast.startEntryID)
        XCTAssertEqual(fast.startDate, date(2026, 9, 16, 21))
    }

    func testFastPersistenceAndTimezoneIndependentElapsedTime() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoodLogFast-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(atPath: storeURL.path + suffix)
            }
        }
        let start = date(2026, 9, 18, 20)
        let end = start.addingTimeInterval(16 * 3_600)
        do {
            let context = PersistenceController(storeURL: storeURL).container.viewContext
            _ = try FastingStore.create(start: start, end: end, target: nil, in: context)
            try context.save()
        }
        let context = PersistenceController(storeURL: storeURL).container.viewContext
        let restored = try XCTUnwrap(FastingStore.sessions(in: context).first)
        XCTAssertEqual(restored.duration, 16 * 3_600)
        XCTAssertNil(restored.targetSeconds)
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        XCTAssertNotEqual(tokyo.component(.hour, from: start), newYork.component(.hour, from: start))
        XCTAssertEqual(restored.endDate?.timeIntervalSince(try XCTUnwrap(restored.startDate)), 16 * 3_600)
    }

    func testRetroactiveFastLinksBothEntriesAndCSVRemainsFoodOnly() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let startMeal = FoodEntry(context: context)
        startMeal.id = UUID()
        startMeal.food = "Dinner"
        startMeal.date = date(2026, 9, 19, 20)
        let endMeal = FoodEntry(context: context)
        endMeal.id = UUID()
        endMeal.food = "Breakfast"
        endMeal.date = date(2026, 9, 20, 10)
        let fast = try FastingStore.create(start: startMeal.wrappedDate, end: endMeal.wrappedDate,
                                           target: FastTargetPreference.seconds(for: 14),
                                           startEntryID: startMeal.id, endEntryID: endMeal.id, in: context)
        try context.save()
        XCTAssertEqual(fast.startEntryID, startMeal.id)
        XCTAssertEqual(fast.endEntryID, endMeal.id)
        XCTAssertEqual(fast.targetSeconds, 14 * 3_600)
        XCTAssertNil(FastTargetPreference.seconds(for: 0))
        let csv = FoodLogCSVDocument.encodeExtended(dataRows: [CSVExporter.row(for: startMeal), CSVExporter.row(for: endMeal)])
        XCTAssertFalse(csv.localizedCaseInsensitiveContains("FastSession"))
        XCTAssertFalse(csv.localizedCaseInsensitiveContains("targetDuration"))
        XCTAssertEqual(try FastingStore.sessions(in: context).count, 1)

        try FastingStore.detachEntry(endMeal, in: context)
        context.delete(endMeal)
        try context.save()
        XCTAssertNil(fast.endEntryID)
        XCTAssertEqual(fast.endDate, date(2026, 9, 20, 10))
    }

    private func assertCSVError(
        _ text: String,
        equals expected: CSVCodecError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try CSVCodec.decode(text), file: file, line: line) { error in
            XCTAssertEqual(error as? CSVCodecError, expected, file: file, line: line)
        }
    }

    private func assertDocumentError(
        _ text: String,
        equals expected: CSVCodecError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try FoodLogCSVDocument.decode(text), file: file, line: line) { error in
            XCTAssertEqual(error as? CSVCodecError, expected, file: file, line: line)
        }
    }
}

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

    func testSuggestionsAreMealSpecificRankedAndDeduplicatedPerEntry() {
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
                currentFood: "eggs",
                limit: 8
            ),
            ["Toast", "Coffee"]
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

    func testLegacyCompanionMigrationCreatesIndividualsAndIsIdempotent() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let entry = FoodEntry(context: context)
        entry.id = UUID()
        entry.food = "Dinner"
        entry.date = date(2026, 9, 11)
        entry.mealType = "Dinner"
        entry.people = "Ana and Bob, ana"
        try context.save()

        XCTAssertEqual(PersistenceController.migrateLegacyCompanions(in: context), 1)
        XCTAssertEqual(entry.companionNames, ["Ana", "Bob"])
        XCTAssertEqual(entry.companionRecords.map(\.sortIndex), [0, 1])
        XCTAssertEqual(PersistenceController.migrateLegacyCompanions(in: context), 0)
        XCTAssertEqual(entry.companionRecords.count, 2)
    }

    func testLegacyPersistentStoreMigratesToCurrentSchema() throws {
        let modelDirectory = try XCTUnwrap(
            Bundle(for: FoodEntry.self).url(forResource: "FoodLog", withExtension: "momd")
        )
        let legacyModelURL = modelDirectory.appendingPathComponent("FoodLog.mom")
        let legacyModel = try XCTUnwrap(NSManagedObjectModel(contentsOf: legacyModelURL))
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoodLogMigration-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(atPath: storeURL.path + suffix)
            }
        }

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: legacyModel)
        let legacyStore = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: storeURL
        )
        let legacyContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        legacyContext.persistentStoreCoordinator = coordinator
        try legacyContext.performAndWait {
            let entry = NSEntityDescription.insertNewObject(forEntityName: "FoodEntry", into: legacyContext)
            entry.setValue(UUID(), forKey: "id")
            entry.setValue("Legacy meal", forKey: "food")
            entry.setValue(date(2026, 9, 8, 19), forKey: "date")
            entry.setValue("Dinner", forKey: "mealType")
            entry.setValue("Ana and Bob", forKey: "people")
            entry.setValue("Old Cafe", forKey: "place")
            try legacyContext.save()
        }
        try coordinator.remove(legacyStore)

        let migratedController = PersistenceController(storeURL: storeURL)
        let context = migratedController.container.viewContext
        let entries = try context.fetch(FoodEntry.fetchRequest())
        let migrated = try XCTUnwrap(entries.first)
        PersistenceController.migrateLegacyCompanions(in: context)

        XCTAssertEqual(migrated.wrappedFood, "Legacy meal")
        XCTAssertEqual(migrated.wrappedPlace, "Old Cafe")
        XCTAssertEqual(migrated.wrappedPlaceCity, "")
        XCTAssertFalse(migrated.hasPlaceCoordinates)
        XCTAssertEqual(migrated.companionNames, ["Ana", "Bob"])
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

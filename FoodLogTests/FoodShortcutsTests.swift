import AppIntents
import CoreData
import XCTest
@testable import FoodLog

@MainActor
final class FoodShortcutsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func time(_ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: hour))!
    }

    func testDefaultsUseExecutionTimeAndExistingMealSuggestion() throws {
        for hour in [2, 8, 12, 16, 20] {
            let now = time(hour)
            let input = try FoodShortcutEntry(food: "  Toast, eggs \n", now: now, calendar: calendar)
            XCTAssertEqual(input.food, "Toast, eggs")
            XCTAssertEqual(input.date, now)
            XCTAssertEqual(input.mealType, MealTypeSuggestion.suggested(for: now, calendar: calendar))
            XCTAssertEqual(input.place, "")
            XCTAssertEqual(input.companions, [])
            XCTAssertEqual(input.note, "")
        }
    }

    func testExplicitDateDrivesAutomaticCategoryAndCanBeOverridden() throws {
        let breakfast = try FoodShortcutEntry(food: "Toast", date: time(8), now: time(20), calendar: calendar)
        XCTAssertEqual(breakfast.date, time(8))
        XCTAssertEqual(breakfast.mealType, "Breakfast")
        for type in ShortcutMealType.allCases where type != .automatic {
            let input = try FoodShortcutEntry(food: "Tea", date: time(8), mealType: type, calendar: calendar)
            XCTAssertTrue(FoodEntryEditor.mealTypes.contains(input.mealType))
            XCTAssertEqual(input.mealType, type.rawValue.capitalized)
        }
    }

    func testRejectsBlankFood() {
        for food in ["", "   ", "\n\t"] {
            XCTAssertThrowsError(try FoodShortcutEntry(food: food)) { error in
                guard case FoodShortcutError.emptyFood = error else { return XCTFail("Unexpected error: \(error)") }
            }
        }
    }

    func testSavePersistsDetailsAndStructuredCompanionsWithoutSavingEditorChanges() async throws {
        let persistence = PersistenceController(inMemory: true)
        let container = persistence.container
        let unsaved = FoodEntry(context: container.viewContext)
        unsaved.food = "Unfinished editor change"
        let input = try FoodShortcutEntry(food: "  Tea  ", date: time(8), mealType: .drink,
            place: " Home \n", companions: [" Ana ", "ana", "", "Bob, Jr."], note: " Morning \n")
        var authorized = false
        let id = try await FoodShortcutLogger.save(input, in: container, now: time(20)) { authorized = true }
        XCTAssertTrue(authorized)
        XCTAssertTrue(unsaved.isInserted)
        XCTAssertTrue(container.viewContext.hasChanges)

        let reader = container.newBackgroundContext()
        let mealDate = time(8)
        let creationDate = time(20)
        try await reader.perform {
            let entries = try reader.fetch(FoodEntry.fetchRequest())
            XCTAssertEqual(entries.count, 1)
            let entry = try XCTUnwrap(entries.first)
            XCTAssertEqual(entry.id, id)
            XCTAssertEqual(entry.food, "Tea")
            XCTAssertEqual(entry.date, mealDate)
            XCTAssertEqual(entry.createdAt, creationDate)
            XCTAssertEqual(entry.mealType, "Drink")
            XCTAssertEqual(entry.place, "Home")
            XCTAssertEqual(entry.note, "Morning")
            XCTAssertEqual(entry.companionNames, ["Ana", "Bob, Jr."])
            XCTAssertEqual(entry.companionRecords.count, 2)
            XCTAssertFalse(entry.hasPlaceCoordinates)
            XCTAssertNil(entry.photoData)
        }
    }

    func testFailedAuthenticationDoesNotInsertAnEntry() async throws {
        let container = PersistenceController(inMemory: true).container
        let input = try FoodShortcutEntry(food: "Toast")
        do {
            try await FoodShortcutLogger.save(input, in: container) { throw FoodShortcutError.authenticationFailed }
            XCTFail("Saving must fail when authentication fails")
        } catch FoodShortcutError.authenticationFailed {
            XCTAssertEqual(try container.viewContext.count(for: FoodEntry.fetchRequest()), 0)
        }
    }

    func testCancellationDoesNotInsertAnEntry() async throws {
        let container = PersistenceController(inMemory: true).container
        let input = try FoodShortcutEntry(food: "Toast")
        let task = Task {
            try await FoodShortcutLogger.save(input, in: container) {
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled shortcuts must not save")
        } catch is CancellationError {
            XCTAssertEqual(try container.viewContext.count(for: FoodEntry.fetchRequest()), 0)
        }
    }

    func testEachInvocationCreatesItsOwnEntry() async throws {
        let container = PersistenceController(inMemory: true).container
        let input = try FoodShortcutEntry(food: "Water", mealType: .drink)
        let first = try await FoodShortcutLogger.save(input, in: container) {}
        let second = try await FoodShortcutLogger.save(input, in: container) {}
        XCTAssertNotEqual(first, second)
        let reader = container.newBackgroundContext()
        let count = try await reader.perform { try reader.count(for: FoodEntry.fetchRequest()) }
        XCTAssertEqual(count, 2)
    }

    func testShortcutRequiresLocalDeviceAuthentication() {
        XCTAssertEqual(LogFoodIntent.authenticationPolicy, .requiresLocalDeviceAuthentication)
        XCTAssertFalse(LogFoodIntent.openAppWhenRun)
        XCTAssertEqual(SavourShortcuts.appShortcuts.count, 1)
    }
}

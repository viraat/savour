import Foundation
import XCTest
#if canImport(FoodLogPerformance)
@testable import FoodLogPerformance
#else
@testable import FoodLog
#endif

final class FoodEntryTimeSelectionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    override func setUp() {
        super.setUp()
        suite = "SavourTimeSelectionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        suite = nil
        super.tearDown()
    }

    func testRelabelledExistingSnackRetains2140AndPreciseTimestamp() {
        let selection = FoodEntryTimeSelection(isNewEntry: false, hasRestoredDraft: false)
        let original = date(hour: 21, minute: 40, second: 37)
        for meal in ["Dinner", "Lunch", "Breakfast", "Snack", "Drink", "Other"] {
            XCTAssertEqual(changing(selection, to: meal, date: original), original)
        }
    }

    func testUntouchedNewEntryUsesDefaultsAcrossMealChanges() {
        let selection = FoodEntryTimeSelection(isNewEntry: true, hasRestoredDraft: false)
        let original = date(hour: 21, minute: 40, second: 37)
        let breakfast = changing(selection, to: "Breakfast", date: original)
        XCTAssertEqual(breakfast, date(hour: 8, minute: 0))
        let lunch = changing(selection, to: "Lunch", date: breakfast)
        XCTAssertEqual(lunch, date(hour: 13, minute: 0))
        XCTAssertEqual(changing(selection, to: "Dinner", date: lunch), date(hour: 19, minute: 0))
    }

    func testExplicitDateAndTimeSelectionPreventsSubsequentDefaults() {
        var selection = FoodEntryTimeSelection(isNewEntry: true, hasRestoredDraft: false)
        _ = changing(selection, to: "Dinner", date: date(hour: 10, minute: 0))
        let picked = calendar.date(from: DateComponents(year: 2025, month: 12, day: 31,
                                                        hour: 23, minute: 17))!
        selection.didSelectDate()
        for meal in ["Breakfast", "Dinner", "Snack", "Lunch"] {
            XCTAssertEqual(changing(selection, to: meal, date: picked), picked)
        }
    }

    func testRestoredNewDraftKeepsItsTimestampWithoutNewDraftFields() {
        let selection = FoodEntryTimeSelection(isNewEntry: true, hasRestoredDraft: true)
        let recovered = date(hour: 21, minute: 40, second: 17)
        XCTAssertEqual(changing(selection, to: "Dinner", date: recovered), recovered)
    }

    func testRestoredEditAndOrphanedEditDraftKeepTheirTimestamps() {
        for restored in [false, true] {
            let selection = FoodEntryTimeSelection(isNewEntry: false, hasRestoredDraft: restored)
            let recovered = date(hour: 21, minute: 40)
            XCTAssertEqual(changing(selection, to: "Dinner", date: recovered), recovered)
        }
    }

    func testConfirmingTheSameDefaultTimeStillCountsAsExplicitChoice() {
        var selection = FoodEntryTimeSelection(isNewEntry: true, hasRestoredDraft: false)
        let dinner = changing(selection, to: "Dinner", date: date(hour: 12, minute: 0))
        selection.didSelectDate()
        XCTAssertEqual(changing(selection, to: "Lunch", date: dinner), dinner)
        selection.didSelectDate()
        XCTAssertEqual(changing(selection, to: "Breakfast", date: dinner), dinner)
    }

    func testNonDefaultMealTypesDoNotChangeTimeOrDisableFutureDefaults() {
        let selection = FoodEntryTimeSelection(isNewEntry: true, hasRestoredDraft: false)
        let original = date(hour: 21, minute: 40, second: 37)
        for meal in ["Snack", "Drink", "Other"] {
            XCTAssertEqual(changing(selection, to: meal, date: original), original)
        }
        XCTAssertEqual(changing(selection, to: "Dinner", date: original), date(hour: 19, minute: 0))
    }

    func testCustomDefaultOnlyAppliesToUntouchedNewEntryAndKeepsDay() {
        let custom = date(hour: 14, minute: 25)
        MealDefaultTimes.set(custom, for: "Lunch", defaults: defaults, calendar: calendar)
        let original = date(hour: 21, minute: 40)
        let fresh = FoodEntryTimeSelection(isNewEntry: true, hasRestoredDraft: false)
        XCTAssertEqual(changing(fresh, to: "Lunch", date: original), custom)
        var picked = fresh
        picked.didSelectDate()
        XCTAssertEqual(changing(picked, to: "Lunch", date: original), original)
        let edit = FoodEntryTimeSelection(isNewEntry: false, hasRestoredDraft: false)
        XCTAssertEqual(changing(edit, to: "Lunch", date: original), original)
    }

    private func changing(_ selection: FoodEntryTimeSelection, to meal: String, date: Date) -> Date {
        selection.dateAfterMealChange(to: meal, date: date, defaults: defaults, calendar: calendar)
    }

    private func date(hour: Int, minute: Int, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 6,
                                           hour: hour, minute: minute, second: second))!
    }
}

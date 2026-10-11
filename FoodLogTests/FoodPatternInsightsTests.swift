import XCTest
#if canImport(FoodLogPerformance)
@testable import FoodLogPerformance
#else
@testable import FoodLog
#endif

final class FoodPatternInsightsTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
    }

    private func meal(_ day: Int, _ hour: Int = 12, _ minute: Int = 0, type: String = "Lunch",
                      food: String = "Rice", place: String = "", with people: [String] = []) -> PatternMeal {
        PatternMeal(date: date(day, hour, minute), mealType: type, food: food, place: place, companions: people)
    }

    func testMinuteOfDay() {
        XCTAssertEqual(FoodPatterns.minuteOfDay(date(5, 0, 0), calendar: calendar), 0)
        XCTAssertEqual(FoodPatterns.minuteOfDay(date(5, 8, 30), calendar: calendar), 510)
        XCTAssertEqual(FoodPatterns.minuteOfDay(date(5, 23, 59), calendar: calendar), 1439)
    }

    func testDaysAreConsecutiveOldestFirst() {
        let days = FoodPatterns.days(endingOn: date(10, 15), count: 3, calendar: calendar)
        XCTAssertEqual(days, [date(8, 0), date(9, 0), date(10, 0)])
        XCTAssertEqual(FoodPatterns.days(endingOn: date(10), count: 0, calendar: calendar), [])
        XCTAssertEqual(FoodPatterns.days(endingOn: date(10), count: -2, calendar: calendar), [])
    }

    func testRhythmFiltersAndSorts() {
        let days = FoodPatterns.days(endingOn: date(10), count: 2, calendar: calendar)
        let meals = [
            meal(10, 20, 0, type: "Dinner"), meal(9, 13, 0), meal(9, 8, 0, type: "Breakfast"),
            meal(7, 9, 0, type: "Breakfast"), meal(10, 7, 15, type: "Drink")
        ]
        let points = FoodPatterns.rhythm(meals, days: days, calendar: calendar)
        XCTAssertEqual(points, [
            .init(day: date(9, 0), minute: 480, mealType: "Breakfast"),
            .init(day: date(9, 0), minute: 780, mealType: "Lunch"),
            .init(day: date(10, 0), minute: 435, mealType: "Drink"),
            .init(day: date(10, 0), minute: 1200, mealType: "Dinner")
        ])
    }

    func testTypicalWindow() {
        let two = [meal(1, 8), meal(2, 9)]
        XCTAssertNil(FoodPatterns.typicalWindow(two, mealType: "Lunch", calendar: calendar))
        // Minutes 8h..15h hourly, 8 meals: rank ceil(2)=2 -> 9h, rank ceil(6)=6 -> 13h.
        var meals = (8 ... 15).map { meal($0, $0) }
        meals.append(meal(20, 3, type: "Breakfast"))
        XCTAssertEqual(FoodPatterns.typicalWindow(meals, mealType: "Lunch", calendar: calendar),
                       .init(start: 9 * 60, end: 13 * 60))
        // Three meals: rank 1 and rank 3.
        let three = [meal(1, 10), meal(2, 12), meal(3, 11)]
        XCTAssertEqual(FoodPatterns.typicalWindow(three, mealType: "Lunch", calendar: calendar),
                       .init(start: 600, end: 720))
        XCTAssertNil(FoodPatterns.typicalWindow(meals, mealType: "Dinner", calendar: calendar))
    }

    func testUsualItemsCountOncePerMealAndGroupCaseInsensitively() {
        let meals = [
            meal(1, food: "Rice, rice, Dal"), meal(2, food: "RICE"), meal(3, food: "Café"),
            meal(4, food: "cafe, Curd"), meal(5, type: "Dinner", food: "Pizza, Pizza")
        ]
        XCTAssertEqual(FoodPatterns.usualItems(meals, mealType: "Lunch", limit: 2), ["cafe", "RICE"])
    }

    func testUsualItemsRecentSpellingTiesAndLimit() {
        let meals = [
            meal(1, food: "Toast, Eggs"), meal(2, food: "toast, Tea"), meal(3, food: "Coffee")
        ]
        // toast x2 first; then ties at 1: Coffee (day 3), Tea (day 2), Eggs (day 1).
        XCTAssertEqual(FoodPatterns.usualItems(meals, mealType: "Lunch", limit: 10),
                       ["toast", "Coffee", "Tea", "Eggs"])
        XCTAssertEqual(FoodPatterns.usualItems(meals, mealType: "Lunch"), ["toast", "Coffee", "Tea"])
        XCTAssertEqual(FoodPatterns.usualItems(meals, mealType: "Lunch", limit: 1), ["toast"])
        XCTAssertEqual(FoodPatterns.usualItems(meals, mealType: "Lunch", limit: 0), [])
        // Same day tie falls back to alphabetical.
        let same = [meal(1, 12, food: "Banana, Apple")]
        XCTAssertEqual(FoodPatterns.usualItems(same, mealType: "Lunch"), ["Apple", "Banana"])
    }

    func testNewItemsOrderAndDedupe() {
        let earlier = [meal(1, food: "Rice, Dal")]
        let period = [
            meal(6, 20, food: "Pasta, rice"), meal(5, 12, food: "DAL, Idli, Pasta"), meal(7, food: "idli, Soup")
        ]
        XCTAssertEqual(FoodPatterns.newItems(in: period, before: earlier), ["Idli", "Pasta", "Soup"])
        XCTAssertEqual(FoodPatterns.newItems(in: [], before: earlier), [])
    }

    func testDistinctItemCount() {
        let meals = [meal(1, food: "Rice, Dal"), meal(2, food: "rice ,  DAL , Curd"), meal(3, food: "")]
        XCTAssertEqual(FoodPatterns.distinctItemCount(meals), 3)
        XCTAssertEqual(FoodPatterns.distinctItemCount([]), 0)
    }

    func testEatenOut() {
        let meals = [
            meal(1, place: ""), meal(2, place: "Home"), meal(3, place: "my home"),
            meal(4, place: "Home, Hyderabad"), meal(5, place: "Roastery, Hyderabad"), meal(6, place: "Café Niloufer")
        ]
        XCTAssertEqual(FoodPatterns.eatenOut(meals), .init(count: 2, total: 5))
        XCTAssertEqual(FoodPatterns.eatenOut([]), .init(count: 0, total: 0))
    }

    func testWithOthersIgnoresBlankCompanions() {
        let meals = [meal(1), meal(2, with: ["", "  "]), meal(3, with: ["Asha"]), meal(4, with: ["", "Ravi"])]
        XCTAssertEqual(FoodPatterns.withOthers(meals), .init(count: 2, total: 4))
    }

    func testNewPlaces() {
        let earlier = [meal(1, place: "Roastery, Hyderabad"), meal(1, place: "Home")]
        let period = [
            meal(8, place: "Cafe Niloufer, Hyderabad"), meal(6, place: "ROASTERY"), meal(7, place: "Home"),
            meal(5, place: "Taj  Mahal"), meal(9, place: "taj mahal, Agra"), meal(10, place: "")
        ]
        XCTAssertEqual(FoodPatterns.newPlaces(in: period, before: earlier), ["Taj Mahal", "Cafe Niloufer"])
    }
}

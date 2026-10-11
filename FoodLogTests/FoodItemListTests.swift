import XCTest
#if canImport(FoodLogPerformance)
@testable import FoodLogPerformance
#else
@testable import FoodLog
#endif

final class FoodItemListTests: XCTestCase {
    func testItemsAreStoredAsTheExistingCommaSeparatedText() {
        XCTAssertEqual(FoodItemList.joined(["Dosa", " Coconut chutney ", ""]), "Dosa, Coconut chutney")
        XCTAssertEqual(FoodItemList.joined([]), "")
        // Round-trips through the parser used by Patterns, CSV and suggestions.
        let stored = FoodItemList.joined(["Toast", "Eggs"])
        XCTAssertEqual(FoodItemParser.items(in: stored), ["Toast", "Eggs"])
    }

    func testAddingSkipsBlanksAndCaseInsensitiveDuplicates() {
        XCTAssertEqual(FoodItemList.adding(["toast", "  ", "Coffee"], to: ["Toast"]), ["Toast", "Coffee"])
        XCTAssertEqual(FoodItemList.adding(["Eggs", "eggs"], to: []), ["Eggs"])
        // A pasted list becomes separate items rather than one item with commas.
        XCTAssertEqual(FoodItemList.adding(["rice, dal"], to: []), ["rice", "dal"])
    }

    func testTypedTextSplitsAtCommasAndLineBreaksKeepingTheItemInProgress() {
        XCTAssertTrue(FoodItemList.splitTyped("toas") == ([], "toas"))
        XCTAssertTrue(FoodItemList.splitTyped("toast,") == (["toast"], ""))
        XCTAssertTrue(FoodItemList.splitTyped("toast, eggs, cof") == (["toast", "eggs"], "cof"))
        XCTAssertTrue(FoodItemList.splitTyped("toast\neggs") == (["toast"], "eggs"))
        XCTAssertTrue(FoodItemList.splitTyped(", ,tea") == ([], "tea"))
    }

    func testSuggestionInputQueriesOnlyTheItemBeingTypedAndExcludesAddedItems() {
        let index = FoodSuggestionEngine.Index(sources: [
            FoodSuggestionSource(mealType: "Breakfast", food: "Toast, Eggs, Coffee"),
            FoodSuggestionSource(mealType: "Breakfast", food: "Toast, Tea")
        ])
        let typing = FoodItemList.suggestionInput(items: ["Eggs"], query: "to")
        XCTAssertEqual(index.suggestions(mealType: "Breakfast", currentFood: typing), ["Toast"])
        // An empty field suggests the meal's usual items, minus what's added.
        let empty = FoodItemList.suggestionInput(items: ["Toast"], query: "")
        XCTAssertEqual(index.suggestions(mealType: "Breakfast", currentFood: empty).first, "Coffee")
        XCTAssertFalse(index.suggestions(mealType: "Breakfast", currentFood: empty).contains("Toast"))
    }
}

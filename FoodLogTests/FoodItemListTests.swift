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

    func testSuggestionsRankFoodsEatenWithTheAddedItemsFirst() {
        let index = FoodSuggestionEngine.Index(sources: [
            FoodSuggestionSource(mealType: "Breakfast", food: "Toast, Coffee"),
            FoodSuggestionSource(mealType: "Breakfast", food: "Toast, Coffee"),
            FoodSuggestionSource(mealType: "Breakfast", food: "Toast, Jam"),
            FoodSuggestionSource(mealType: "Breakfast", food: "Dosa, Sambar"),
            FoodSuggestionSource(mealType: "Dinner", food: "Dosa, Sambar, Chutney"),
            FoodSuggestionSource(mealType: "Dinner", food: "Dosa, Chutney")
        ])
        // Nothing added: unchanged, the meal's most frequent items lead.
        XCTAssertEqual(index.suggestions(mealType: "Breakfast", currentFood: "").prefix(2), ["Toast", "Coffee"])
        // With Dosa added, its companions beat breakfast's usual Toast and Coffee;
        // tied at two meals each, Sambar's breakfast history puts it first.
        let afterDosa = FoodItemList.suggestionInput(items: ["Dosa"], query: "")
        XCTAssertEqual(index.suggestions(mealType: "Breakfast", currentFood: afterDosa).prefix(2), ["Sambar", "Chutney"])
        // Together counts add up across added items.
        let afterDosaAndSambar = FoodItemList.suggestionInput(items: ["Dosa", "Sambar"], query: "")
        XCTAssertEqual(index.suggestions(mealType: "Breakfast", currentFood: afterDosaAndSambar).first, "Chutney")
        // Typing still decides first: only matches are ranked.
        let typingC = FoodItemList.suggestionInput(items: ["Toast"], query: "c")
        XCTAssertEqual(index.suggestions(mealType: "Breakfast", currentFood: typingC).first, "Coffee")
    }
}

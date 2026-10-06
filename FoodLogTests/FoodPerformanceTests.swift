import CoreData
import Foundation
import XCTest
@testable import FoodLogPerformance

final class FoodPerformanceTests: XCTestCase {
    func testIndexedSuggestionsPreserveMatchingRankingAndSegmentReplacement() {
        let index = FoodSuggestionEngine.Index(sources: [
            .init(mealType: "Lunch", food: "Tofu, Tofu scramble", date: Date(timeIntervalSince1970: 10)),
            .init(mealType: "Dinner", food: "Grilled tofu, rice", date: Date(timeIntervalSince1970: 30)),
            .init(mealType: "Lunch", food: "Tofu, dal", date: Date(timeIntervalSince1970: 20))
        ])
        XCTAssertEqual(index.uniqueFoodCount, 5)
        XCTAssertEqual(index.suggestions(mealType: "Lunch", currentFood: "rice, dal, tof"),
                       ["Tofu", "Tofu scramble", "Grilled tofu"])
        XCTAssertEqual(index.suggestions(mealType: "Dinner", currentFood: "tofu, ri"), ["rice", "Grilled tofu"])
        XCTAssertEqual(index.suggestions(mealType: "Lunch", currentFood: "tofy").first, "Tofu")
        XCTAssertEqual(FoodSuggestionEngine.replacingCurrentSegment(in: "rice, dal, tof", with: "Tofu"),
                       "rice, dal, Tofu")
    }

    func testIndexNormalizesWhitespaceCaseAndDeduplicatesWithinOneEntry() {
        let index = FoodSuggestionEngine.Index(sources: [
            .init(mealType: " lunch ", food: " Tofu   scramble, TOFU scramble, tofu scramble "),
            .init(mealType: "Lunch", food: "Tofu salad"),
            .init(mealType: "Lunch", food: "Tofu salad")
        ])
        XCTAssertEqual(index.uniqueFoodCount, 2)
        XCTAssertEqual(index.suggestions(mealType: "LUNCH", currentFood: "TOF"),
                       ["Tofu salad", "Tofu scramble"])
        XCTAssertEqual(index.suggestions(mealType: "Lunch", currentFood: "tofu salad, tofu  scramble"), [])
    }

    func testOneIndexSupportsDifferentMealTypesWithoutRebuilding() {
        let sources: [FoodSuggestionSource] = [
            .init(mealType: "Breakfast", food: "Avocado toast", date: Date(timeIntervalSince1970: 20)),
            .init(mealType: "Lunch", food: "Avocado salad", date: Date(timeIntervalSince1970: 10)),
            .init(mealType: "Dinner", food: "Avocado soup", date: Date(timeIntervalSince1970: 30))
        ]
        let index = FoodSuggestionEngine.Index(sources: sources)
        XCTAssertEqual(index.suggestions(mealType: "Breakfast", currentFood: "avo").first, "Avocado toast")
        XCTAssertEqual(index.suggestions(mealType: "Lunch", currentFood: "avo").first, "Avocado salad")
        XCTAssertEqual(index.suggestions(mealType: "Dinner", currentFood: "avo").first, "Avocado soup")
        for meal in ["Breakfast", "Lunch", "Dinner", "Other"] {
            for query in ["", "avo", "avocdo", "Avocado toast, avo", "soup"] {
                XCTAssertEqual(index.suggestions(mealType: meal, currentFood: query),
                               LegacyFoodSuggestionEngine.suggestions(from: sources, mealType: meal, currentFood: query))
            }
        }
    }

    func testRecencyLimitAndDiacriticMatching() {
        let index = FoodSuggestionEngine.Index(sources: [
            .init(mealType: "Lunch", food: "Café toast", date: Date(timeIntervalSince1970: 10)),
            .init(mealType: "Lunch", food: "Cafe salad", date: Date(timeIntervalSince1970: 20))
        ])
        XCTAssertEqual(index.suggestions(mealType: "Lunch", currentFood: "cafe", limit: 1), ["Cafe salad"])
        XCTAssertEqual(index.suggestions(mealType: "Lunch", currentFood: "cafe", limit: 0), [])
        XCTAssertEqual(index.suggestions(mealType: "Lunch", currentFood: "cafe", limit: -1), [])
    }

    func testIndexedResultsMatchLegacyEngineAcrossHistoryAndLimits() {
        let foods = [" ToFu, TOFU, tofu scramble ", "Grilled tofu, Café toast",
                     "rice, Dal, tofu salad", "Dal, rice, roasted aubergine",
                     "Cafe salad, avocado toast, Avocado   salad"]
        let meals = ["Breakfast", "Lunch", "Dinner", "Snack"]
        let sources = (0..<100).map { i in
            FoodSuggestionSource(mealType: meals[i % meals.count], food: foods[i % foods.count],
                                 date: Date(timeIntervalSince1970: Double(i)))
        }
        let index = FoodSuggestionEngine.Index(sources: sources)
        for meal in meals {
            for query in ["", "t", "tof", "tofy", "cafe", "avocdo", "rice, dal, tof", "Tofu, tofu scramble"] {
                for limit in [0, 1, 8] {
                    XCTAssertEqual(index.suggestions(mealType: meal, currentFood: query, limit: limit),
                                   LegacyFoodSuggestionEngine.suggestions(from: sources, mealType: meal,
                                                                          currentFood: query, limit: limit))
                }
            }
        }
    }

    @MainActor
    func testCacheBuildsOnlyOncePerKeyAndExplicitInvalidation() async {
        let cache = FoodHistoryCache<String, Int>()
        var builds = 0
        func read(_ key: String) -> Int { cache.value(for: key) { builds += 1; return builds } }
        XCTAssertEqual(read("first"), 1)
        for _ in 0..<100 { XCTAssertEqual(read("first"), 1) }
        XCTAssertEqual(read("second"), 2)
        cache.invalidate()
        XCTAssertEqual(read("second"), 3)
        XCTAssertEqual(read("first"), 4) // Only one snapshot is retained, not an unbounded dictionary.
    }

    @MainActor
    func testEntryInsertEditAndDeleteRefreshCachedValues() async throws {
        let context = try makeContext()
        let cache = FoodHistoryCache<String, [String]>()
        cache.observe(context)
        func read() throws -> [String] {
            var names: [String] = []
            // Snapshot construction is nonthrowing in production after the
            // FetchRequest; this test fetches the same main-context objects.
            let request = NSFetchRequest<NSManagedObject>(entityName: "FoodEntry")
            names = try context.fetch(request).compactMap { $0.value(forKey: "name") as? String }.sorted()
            return cache.value(for: "journal") { names }
        }
        XCTAssertEqual(try read(), [])
        let meal = NSEntityDescription.insertNewObject(forEntityName: "FoodEntry", into: context)
        meal.setValue("Soup", forKey: "name")
        context.processPendingChanges()
        XCTAssertEqual(try read(), ["Soup"])
        meal.setValue("Edited soup", forKey: "name")
        context.processPendingChanges()
        XCTAssertEqual(try read(), ["Edited soup"])
        context.delete(meal)
        context.processPendingChanges()
        XCTAssertEqual(try read(), [])
    }

    @MainActor
    func testCompanionChangesInvalidateEvenWithoutChangingMealObject() async throws {
        let context = try makeContext()
        let person = NSEntityDescription.insertNewObject(forEntityName: "FoodEntryCompanion", into: context)
        person.setValue("Ana", forKey: "name")
        context.processPendingChanges()
        let cache = FoodHistoryCache<String, String>()
        cache.observe(context)
        func read() -> String { cache.value(for: "people") { person.value(forKey: "name") as? String ?? "" } }
        XCTAssertEqual(read(), "Ana")
        person.setValue("Bob", forKey: "name")
        context.processPendingChanges()
        XCTAssertEqual(read(), "Bob")
        context.delete(person)
        context.processPendingChanges()
        XCTAssertEqual(cache.value(for: "people") { "deleted" }, "deleted")
    }

    @MainActor
    func testRollbackAndResetInvalidateSnapshots() async throws {
        let context = try makeContext()
        let meal = NSEntityDescription.insertNewObject(forEntityName: "FoodEntry", into: context)
        meal.setValue("Saved", forKey: "name")
        try context.save()
        let cache = FoodHistoryCache<String, String>()
        cache.observe(context)
        func read() -> String { cache.value(for: "journal") { meal.value(forKey: "name") as? String ?? "" } }
        XCTAssertEqual(read(), "Saved")
        meal.setValue("Unsaved", forKey: "name")
        context.processPendingChanges()
        XCTAssertEqual(read(), "Unsaved")
        context.rollback()
        context.processPendingChanges()
        XCTAssertEqual(read(), "Saved")
        context.reset()
        XCTAssertEqual(cache.value(for: "journal") { "reset" }, "reset")
    }

    @MainActor
    func testUndoAndRedoInvalidateSnapshots() async throws {
        let context = try makeContext()
        context.undoManager = UndoManager()
        let meal = NSEntityDescription.insertNewObject(forEntityName: "FoodEntry", into: context)
        meal.setValue("Original", forKey: "name")
        try context.save()
        context.undoManager?.removeAllActions()
        let cache = FoodHistoryCache<String, String>()
        cache.observe(context)
        func read() -> String { cache.value(for: "journal") { meal.value(forKey: "name") as? String ?? "" } }
        XCTAssertEqual(read(), "Original")
        context.undoManager?.beginUndoGrouping()
        meal.setValue("Edited", forKey: "name")
        context.processPendingChanges()
        context.undoManager?.endUndoGrouping()
        XCTAssertEqual(read(), "Edited")
        context.undo()
        context.processPendingChanges()
        XCTAssertEqual(read(), "Original")
        context.redo()
        context.processPendingChanges()
        XCTAssertEqual(read(), "Edited")
    }

    @MainActor
    func testContextSwitchAndUnrelatedRecordsDoNotLeakOrRebuild() async throws {
        let first = try makeContext()
        let second = try makeContext()
        let cache = FoodHistoryCache<String, Int>()
        cache.observe(first)
        var builds = 0
        func read() -> Int { cache.value(for: "history") { builds += 1; return builds } }
        XCTAssertEqual(read(), 1)
        let legacyFast = NSEntityDescription.insertNewObject(forEntityName: "FastSession", into: first)
        legacyFast.setValue("Unrelated", forKey: "name")
        first.processPendingChanges()
        XCTAssertEqual(read(), 1)
        cache.observe(second)
        XCTAssertEqual(read(), 2)
        _ = NSEntityDescription.insertNewObject(forEntityName: "FoodEntry", into: first)
        first.processPendingChanges()
        XCTAssertEqual(read(), 2)
        _ = NSEntityDescription.insertNewObject(forEntityName: "FoodEntry", into: second)
        second.processPendingChanges()
        XCTAssertEqual(read(), 3)
    }

    @MainActor
    func testBackgroundImportMergeInvalidatesMainContextSnapshot() async throws {
        let context = try makeContext()
        let cache = FoodHistoryCache<String, Int>()
        cache.observe(context)
        func read() -> Int {
            cache.value(for: "journal") {
                (try? context.count(for: NSFetchRequest<NSManagedObject>(entityName: "FoodEntry"))) ?? -1
            }
        }
        XCTAssertEqual(read(), 0)
        let background = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        background.persistentStoreCoordinator = context.persistentStoreCoordinator
        let id = try await background.perform {
            let entry = NSEntityDescription.insertNewObject(forEntityName: "FoodEntry", into: background)
            entry.setValue("Restored meal", forKey: "name")
            try background.save()
            return entry.objectID
        }
        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: [NSInsertedObjectsKey: [id]], into: [context])
        context.processPendingChanges()
        XCTAssertEqual(read(), 1)
    }

    @MainActor
    func testCalendarTimezoneDayAndRangeKeysRefreshCalculations() async {
        struct Key: Equatable { var calendar: Calendar; var day: Date; var range: Int }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let cache = FoodHistoryCache<Key, Int>()
        var key = Key(calendar: calendar, day: Date(timeIntervalSince1970: 1_700_000_000), range: 7)
        var builds = 0
        func read() -> Int { cache.value(for: key) { builds += 1; return builds } }
        XCTAssertEqual(read(), 1)
        XCTAssertEqual(read(), 1)
        key.range = 30
        XCTAssertEqual(read(), 2)
        key.calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        XCTAssertEqual(read(), 3)
        key.day.addTimeInterval(86_400)
        XCTAssertEqual(read(), 4)
    }

    func testAutocompleteMicrobenchmark() {
        let sources = (0..<3_000).map { i in
            FoodSuggestionSource(mealType: i.isMultiple(of: 2) ? "Lunch" : "Dinner",
                                 food: "Rice, Tofu scramble, Grilled tofu, Dal, Aubergine curry",
                                 date: Date(timeIntervalSince1970: Double(i)))
        }
        let index = FoodSuggestionEngine.Index(sources: sources)
        let queries = ["t", "to", "tof", "tofu", "tofu s", "tofy", "rice, tof", "dal, tof"]
        let start = Date()
        let baseline = queries.map { LegacyFoodSuggestionEngine.suggestions(from: sources, mealType: "Lunch", currentFood: $0) }
        let rebuildTime = Date().timeIntervalSince(start)
        let cachedStart = Date()
        let cached = queries.map { index.suggestions(mealType: "Lunch", currentFood: $0) }
        let cachedTime = Date().timeIntervalSince(cachedStart)
        XCTAssertEqual(cached, baseline)
        print("Autocomplete microbenchmark (3,000 meals, 8 queries): rebuilding \(rebuildTime)s; indexed \(cachedTime)s")
        // No timing assertion: correctness must not depend on host load.
    }

    @MainActor
    private func makeContext() throws -> NSManagedObjectContext {
        let model = NSManagedObjectModel()
        model.entities = ["FoodEntry", "FoodEntryCompanion", "FastSession"].map { name in
            let entity = NSEntityDescription()
            entity.name = name
            entity.managedObjectClassName = "NSManagedObject"
            let attribute = NSAttributeDescription()
            attribute.name = "name"
            attribute.attributeType = .stringAttributeType
            attribute.isOptional = true
            entity.properties = [attribute]
            return entity
        }
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }
}

// Frozen pre-index implementation for regression equivalence and the microbenchmark.
private enum LegacyFoodSuggestionEngine {
    private struct Candidate {
        let name: String
        var count: Int
        var mealCount: Int
        var lastUsed: Date
    }

    static func suggestions(
        from sources: [FoodSuggestionSource],
        mealType: String,
        currentFood: String,
        limit: Int = 8
    ) -> [String] {
        let query = key(for: currentSegment(in: currentFood))
        let selected = Set(FoodItemParser.items(in: currentFood).map(key(for:)))
        let selectedMeal = key(for: mealType)
        var candidates: [String: Candidate] = [:]

        for source in sources {
            var countedForEntry = Set<String>()
            for item in FoodItemParser.items(in: source.food) {
                let name = normalizedWhitespace(item)
                let itemKey = key(for: name)
                guard countedForEntry.insert(itemKey).inserted else { continue }
                var candidate = candidates[itemKey] ?? Candidate(
                    name: name,
                    count: 0,
                    mealCount: 0,
                    lastUsed: .distantPast
                )
                candidate.count += 1
                if key(for: source.mealType) == selectedMeal {
                    candidate.mealCount += 1
                }
                candidate.lastUsed = max(candidate.lastUsed, source.date)
                candidates[itemKey] = candidate
            }
        }

        return candidates.compactMap { itemKey, candidate -> (Candidate, Int)? in
            guard !selected.contains(itemKey), let match = matchRank(itemKey, query: query) else {
                return nil
            }
            return (candidate, match)
        }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                if ($0.0.mealCount > 0) != ($1.0.mealCount > 0) {
                    return $0.0.mealCount > 0
                }
                if $0.0.mealCount != $1.0.mealCount {
                    return $0.0.mealCount > $1.0.mealCount
                }
                if $0.0.count != $1.0.count { return $0.0.count > $1.0.count }
                if $0.0.lastUsed != $1.0.lastUsed { return $0.0.lastUsed > $1.0.lastUsed }
                return $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending
            }
            .prefix(max(limit, 0))
            .map { $0.0.name }
    }

    static func replacingCurrentSegment(in description: String, with suggestion: String) -> String {
        guard let comma = description.lastIndex(of: ",") else { return suggestion }
        return "\(description[...comma]) \(suggestion)"
    }

    private static func currentSegment(in description: String) -> String {
        guard let comma = description.lastIndex(of: ",") else { return description }
        return String(description[description.index(after: comma)...])
    }

    private static func normalizedWhitespace(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func key(for value: String) -> String {
        normalizedWhitespace(value)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func matchRank(_ candidate: String, query: String) -> Int? {
        guard !query.isEmpty else { return 0 }
        if candidate.hasPrefix(query) { return 4 }
        let words = candidate.split(separator: " ").map(String.init)
        if words.contains(where: { $0.hasPrefix(query) }) { return 3 }
        if candidate.contains(query) { return 2 }

        guard query.count >= 3 else { return nil }
        let distance = query.count >= 5 ? 2 : 1
        if isWithinEditDistance(query, of: candidate, limit: distance)
            || words.contains(where: { isWithinEditDistance(query, of: $0, limit: distance) }) {
            return 1
        }
        return nil
    }

    private static func isWithinEditDistance(_ query: String, of word: String, limit: Int) -> Bool {
        let left = Array(query)
        let right = Array(word)
        guard abs(left.count - right.count) <= limit else { return false }
        var previous = Array(0 ... right.count)

        for (leftIndex, character) in left.enumerated() {
            var current = [leftIndex + 1]
            var rowMinimum = current[0]
            for (rightIndex, other) in right.enumerated() {
                let cost = character == other ? 0 : 1
                let result = min(
                    previous[rightIndex + 1] + 1,
                    current[rightIndex] + 1,
                    previous[rightIndex] + cost
                )
                current.append(result)
                rowMinimum = min(rowMinimum, result)
            }
            if rowMinimum > limit { return false }
            previous = current
        }
        return previous[right.count] <= limit
    }
}

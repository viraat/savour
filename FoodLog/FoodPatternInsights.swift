import Foundation

/// A logged meal, decoupled from Core Data so pattern logic is testable.
struct PatternMeal: Equatable {
    let date: Date
    let mealType: String
    let food: String          // stored comma-separated text, e.g. "Toast, Eggs"
    let place: String         // may be "" ; may be "Roastery, Hyderabad"
    let companions: [String]
}

enum FoodPatterns {
    /// Minutes after local midnight (0..<1440) in `calendar`.
    static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// `count` consecutive start-of-day dates ending with `reference`'s day, oldest first.
    static func days(endingOn reference: Date, count: Int, calendar: Calendar) -> [Date] {
        guard count > 0 else { return [] }
        let last = calendar.startOfDay(for: reference)
        return (0 ..< count).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: last) }
    }

    struct RhythmPoint: Equatable {
        let day: Date        // calendar.startOfDay of the meal
        let minute: Int      // minuteOfDay
        let mealType: String
    }

    /// One point per meal whose start-of-day is in `days`; sorted by day, then minute.
    static func rhythm(_ meals: [PatternMeal], days: [Date], calendar: Calendar) -> [RhythmPoint] {
        let allowed = Set(days)
        return meals.compactMap { meal -> RhythmPoint? in
            let day = calendar.startOfDay(for: meal.date)
            guard allowed.contains(day) else { return nil }
            return RhythmPoint(day: day, minute: minuteOfDay(meal.date, calendar: calendar), mealType: meal.mealType)
        }
        .sorted { ($0.day, $0.minute) < ($1.day, $1.minute) }
    }

    struct TimeWindow: Equatable { let start: Int; let end: Int } // minutes of day

    /// The middle half of this meal type's times: 25th to 75th percentile (nearest rank).
    static func typicalWindow(_ meals: [PatternMeal], mealType: String, calendar: Calendar) -> TimeWindow? {
        let minutes = sortedMinutes(meals, mealType: mealType, calendar: calendar)
        guard minutes.count >= 3 else { return nil }
        return TimeWindow(start: percentile(0.25, of: minutes), end: percentile(0.75, of: minutes))
    }

    /// How spread out one meal type's times are, in minutes of day.
    struct TimeSpread: Equatable {
        let mealType: String
        let count: Int
        let earliest: Int
        let lowerQuartile: Int
        let median: Int
        let upperQuartile: Int
        let latest: Int
    }

    /// One spread per meal type with at least one meal, in `mealTypes` order.
    /// Quartiles and median use the nearest rank, like `typicalWindow`.
    static func timeSpreads(_ meals: [PatternMeal], mealTypes: [String], calendar: Calendar) -> [TimeSpread] {
        mealTypes.compactMap { mealType in
            let minutes = sortedMinutes(meals, mealType: mealType, calendar: calendar)
            guard let earliest = minutes.first, let latest = minutes.last else { return nil }
            return TimeSpread(mealType: mealType, count: minutes.count, earliest: earliest,
                              lowerQuartile: percentile(0.25, of: minutes), median: percentile(0.5, of: minutes),
                              upperQuartile: percentile(0.75, of: minutes), latest: latest)
        }
    }

    private static func sortedMinutes(_ meals: [PatternMeal], mealType: String, calendar: Calendar) -> [Int] {
        meals.filter { $0.mealType == mealType }.map { minuteOfDay($0.date, calendar: calendar) }.sorted()
    }

    private static func percentile(_ p: Double, of sorted: [Int]) -> Int {
        let rank = Int((p * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }

    /// Number of distinct normalized items across the meals.
    static func distinctItemCount(_ meals: [PatternMeal]) -> Int {
        Set(meals.flatMap { uniqueItems(in: $0).map(\.key) }).count
    }

    struct Share: Equatable { let count: Int; let total: Int }

    /// Meals with a place, and how many of those are not at a home label.
    static func eatenOut(_ meals: [PatternMeal]) -> Share {
        let placed = meals.compactMap { placeName($0.place) }
        return Share(count: placed.filter { !isHome($0) }.count, total: placed.count)
    }

    /// All meals, and how many had at least one non-blank companion.
    static func withOthers(_ meals: [PatternMeal]) -> Share {
        let count = meals.filter { meal in
            meal.companions.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }.count
        return Share(count: count, total: meals.count)
    }

    /// Non-home place names in `period` never seen in `earlier`, in order of first appearance.
    static func newPlaces(in period: [PatternMeal], before earlier: [PatternMeal]) -> [String] {
        var seen = Set(earlier.compactMap { placeName($0.place) }.map(key(for:)))
        var result: [String] = []
        for meal in period.sorted(by: { $0.date < $1.date }) {
            guard let name = placeName(meal.place), !isHome(name),
                  seen.insert(key(for: name)).inserted else { continue }
            result.append(name)
        }
        return result
    }

    private static let homeLabels: Set<String> = ["home", "myhome", "myplace", "myhouse", "athome"]

    /// First comma segment of a place, whitespace-collapsed; nil when empty.
    private static func placeName(_ place: String) -> String? {
        let first = place.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let name = collapsed(first)
        return name.isEmpty ? nil : name
    }

    private static func isHome(_ name: String) -> Bool {
        let letters = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased().filter { $0.isLetter || $0.isNumber }
        return homeLabels.contains(letters)
    }

    /// Distinct items of one meal as (key, display name), in written order.
    private static func uniqueItems(in meal: PatternMeal) -> [(key: String, name: String)] {
        var seen = Set<String>()
        return FoodItemParser.items(in: meal.food).compactMap { item in
            let name = collapsed(item)
            let itemKey = key(for: name)
            return seen.insert(itemKey).inserted ? (itemKey, name) : nil
        }
    }

    private static func collapsed(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func key(for value: String) -> String {
        collapsed(value)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

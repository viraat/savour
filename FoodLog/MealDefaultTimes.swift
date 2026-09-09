import Foundation

enum MealDefaultTimes {
    static let mealTypes = ["Breakfast", "Lunch", "Dinner"]

    private static let initialMinutes: [String: Int] = [
        "Breakfast": 8 * 60,
        "Lunch": 13 * 60,
        "Dinner": 19 * 60
    ]

    static func minutes(for mealType: String, defaults: UserDefaults = .standard) -> Int? {
        guard let initialValue = initialMinutes[mealType] else { return nil }
        let key = storageKey(for: mealType)
        guard defaults.object(forKey: key) != nil else {
            return initialValue
        }
        return defaults.integer(forKey: key)
    }

    static func set(_ date: Date, for mealType: String, defaults: UserDefaults = .standard) {
        guard initialMinutes[mealType] != nil else {
            defaults.removeObject(forKey: storageKey(for: mealType))
            return
        }
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        defaults.set(minutes, forKey: storageKey(for: mealType))
    }

    static func date(for mealType: String, defaults: UserDefaults = .standard) -> Date {
        guard let minutes = minutes(for: mealType, defaults: defaults) else { return Date() }
        return Calendar.current.date(
            bySettingHour: minutes / 60,
            minute: minutes % 60,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    static func applyingDefault(for mealType: String, to date: Date) -> Date {
        guard let minutes = minutes(for: mealType) else { return date }
        var components = Calendar.current.dateComponents([.era, .year, .month, .day], from: date)
        components.hour = minutes / 60
        components.minute = minutes % 60
        components.second = 0
        return Calendar.current.date(from: components) ?? date
    }

    private static func storageKey(for mealType: String) -> String {
        "foodLogDefaultTime.\(mealType.lowercased())"
    }
}

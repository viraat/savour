// swift-tools-version: 5.9
import PackageDescription

// Runs actual reminder and performance logic on the Mac, without launching
// the app, a simulator or real permission prompts.
let appOnlyFiles = [
    "AppLockView.swift", "BrowsePatternsSettings.swift", "ContactsSearchModel.swift",
    "ContentView.swift", "DateTimePickerSheet.swift", "Fasting.swift",
    "FoodEntryDraftStore.swift", "FoodEntryEditor.swift", "FoodLogApp.swift",
    "FoodLogCSVImport.swift", "Info.plist", "JournalView.swift",
    "LocationSearchModel.swift", "MealDefaultTimes.swift", "PersistenceController.swift",
    "Assets.xcassets", "FoodLog.xcdatamodeld"
]
let package = Package(
    name: "SavourLocalLogic",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "FoodLogReminder", path: "FoodLog",
                exclude: appOnlyFiles + ["FoodLogLogic.swift", "FoodHistoryCache.swift"],
                sources: ["FoodReminder.swift"]),
        .testTarget(name: "FoodLogReminderTests", dependencies: ["FoodLogReminder"],
                    path: "FoodLogTests", exclude: ["FoodLogLogicTests.swift", "FoodPerformanceTests.swift", "FoodCSVPerformanceTests.swift"],
                    sources: ["FoodReminderTests.swift"]),
        .target(name: "FoodLogPerformance", path: "FoodLog", exclude: appOnlyFiles + ["FoodReminder.swift"],
                sources: ["FoodLogLogic.swift", "FoodHistoryCache.swift"]),
        .testTarget(name: "FoodLogPerformanceTests", dependencies: ["FoodLogPerformance"], path: "FoodLogTests",
                    exclude: ["FoodLogLogicTests.swift", "FoodReminderTests.swift"],
                    sources: ["FoodPerformanceTests.swift", "FoodCSVPerformanceTests.swift"])
    ]
)

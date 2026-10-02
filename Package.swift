// swift-tools-version: 5.9
import PackageDescription

// Runs the actual reminder service against fake notification/preferences clients
// on the Mac, without launching the app, simulator or real permission prompts.
let package = Package(
    name: "SavourReminderLogic",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "FoodLogReminder", path: "FoodLog", exclude: [
            "AppLockView.swift", "BrowsePatternsSettings.swift", "ContactsSearchModel.swift",
            "ContentView.swift", "DateTimePickerSheet.swift", "Fasting.swift",
            "FoodEntryDraftStore.swift", "FoodEntryEditor.swift", "FoodLogApp.swift",
            "FoodLogCSVImport.swift", "FoodLogLogic.swift", "Info.plist", "JournalView.swift",
            "LocationSearchModel.swift", "MealDefaultTimes.swift", "PersistenceController.swift",
            "Assets.xcassets", "FoodLog.xcdatamodeld"
        ], sources: ["FoodReminder.swift"]),
        .testTarget(name: "FoodLogReminderTests", dependencies: ["FoodLogReminder"],
                    path: "FoodLogTests", exclude: ["FoodLogLogicTests.swift"],
                    sources: ["FoodReminderTests.swift"])
    ]
)

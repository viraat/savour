// swift-tools-version: 5.9
import PackageDescription

// Runs actual reminder/backup code on the Mac without launching the iOS app,
// simulator, or real notification prompts. Backup tests use private test stores.
let appOnlyFiles = [
    "AppLockView.swift", "BrowsePatternsSettings.swift", "ContactsSearchModel.swift",
    "ContentView.swift", "DateTimePickerSheet.swift", "Fasting.swift",
    "FoodEntryDraftStore.swift", "FoodEntryEditor.swift", "FoodLogApp.swift",
    "FoodLogCSVImport.swift", "FoodLogLogic.swift", "Info.plist", "JournalView.swift",
    "LocationSearchModel.swift", "MealDefaultTimes.swift", "PersistenceController.swift",
    "Assets.xcassets", "ThirdPartyNotices.txt"
]
let package = Package(
    name: "SavourLocalLogic",
    platforms: [.macOS(.v13)],
    dependencies: [.package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")],
    targets: [
        .target(name: "FoodLogReminder", path: "FoodLog",
                exclude: appOnlyFiles + ["FoodBackup.swift", "FoodBackupRestore.swift", "FoodLog.xcdatamodeld"], sources: ["FoodReminder.swift"]),
        .testTarget(name: "FoodLogReminderTests", dependencies: ["FoodLogReminder"],
                    path: "FoodLogTests", exclude: ["FoodLogLogicTests.swift", "FoodBackupTests.swift"],
                    sources: ["FoodReminderTests.swift"]),
        .target(name: "FoodLogBackup", dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")],
                path: "FoodLog", exclude: appOnlyFiles + ["FoodReminder.swift"],
                sources: ["FoodBackup.swift", "FoodBackupRestore.swift"], resources: [.process("FoodLog.xcdatamodeld")]),
        .testTarget(name: "FoodLogBackupTests", dependencies: ["FoodLogBackup"], path: "FoodLogTests",
                    exclude: ["FoodLogLogicTests.swift", "FoodReminderTests.swift"], sources: ["FoodBackupTests.swift"])
    ]
)

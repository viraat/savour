// swift-tools-version: 5.9
import PackageDescription

// Runs actual reminder, performance, draft and backup logic on the Mac, without
// launching the app, a simulator or real permission prompts. Backup tests use
// private test stores.
let appOnlyFiles = [
    "AppLockView.swift", "BrowsePatternsSettings.swift", "ContactsSearchModel.swift",
    "ContentView.swift", "DateTimePickerSheet.swift", "Fasting.swift",
    "FoodEntryEditor.swift", "FoodLogApp.swift",
    "FoodLogCSVImport.swift", "Info.plist", "JournalView.swift",
    "LocationSearchModel.swift", "PersistenceController.swift",
    "Assets.xcassets", "ThirdPartyNotices.txt"
]
// Only the backup target compiles the Core Data model, as a resource.
let backupFiles = ["FoodBackup.swift", "FoodBackupRestore.swift", "FoodLog.xcdatamodeld"]
let localLogicFiles = ["FoodReminder.swift", "FoodLogLogic.swift", "FoodHistoryCache.swift",
                       "FoodEntryDraftStore.swift", "FoodStoreMigration.swift", "MealDefaultTimes.swift",
                       "FoodPhotoThumbnails.swift"]
let testFiles = ["FoodLogLogicTests.swift", "FoodReminderTests.swift", "FoodPerformanceTests.swift",
                 "FoodDraftAutosaveTests.swift", "FoodCSVPerformanceTests.swift", "FoodStoreMigrationTests.swift",
                 "FoodEntryTimeSelectionTests.swift", "FoodPhotoThumbnailTests.swift", "FoodBackupTests.swift"]

func excluding(_ sources: [String], from files: [String]) -> [String] {
    files.filter { !sources.contains($0) }
}

let reminderSources = ["FoodReminder.swift"]
let performanceSources = ["FoodLogLogic.swift", "FoodHistoryCache.swift", "FoodStoreMigration.swift",
                          "MealDefaultTimes.swift", "FoodPhotoThumbnails.swift"]
let draftSources = ["FoodEntryDraftStore.swift"]
let reminderTests = ["FoodReminderTests.swift"]
let performanceTests = ["FoodPerformanceTests.swift", "FoodCSVPerformanceTests.swift", "FoodStoreMigrationTests.swift",
                        "FoodEntryTimeSelectionTests.swift", "FoodPhotoThumbnailTests.swift"]
let draftTests = ["FoodDraftAutosaveTests.swift"]
let backupTests = ["FoodBackupTests.swift"]

let package = Package(
    name: "SavourLocalLogic",
    platforms: [.macOS(.v13)],
    dependencies: [.package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")],
    targets: [
        .target(name: "FoodLogReminder", path: "FoodLog",
                exclude: appOnlyFiles + backupFiles + excluding(reminderSources, from: localLogicFiles),
                sources: reminderSources),
        .testTarget(name: "FoodLogReminderTests", dependencies: ["FoodLogReminder"], path: "FoodLogTests",
                    exclude: excluding(reminderTests, from: testFiles), sources: reminderTests),
        .target(name: "FoodLogPerformance", path: "FoodLog",
                exclude: appOnlyFiles + backupFiles + excluding(performanceSources, from: localLogicFiles),
                sources: performanceSources),
        .testTarget(name: "FoodLogPerformanceTests", dependencies: ["FoodLogPerformance"], path: "FoodLogTests",
                    exclude: excluding(performanceTests, from: testFiles), sources: performanceTests),
        .target(name: "FoodLogDrafts", path: "FoodLog",
                exclude: appOnlyFiles + backupFiles + excluding(draftSources, from: localLogicFiles),
                sources: draftSources),
        .testTarget(name: "FoodLogDraftTests", dependencies: ["FoodLogDrafts"], path: "FoodLogTests",
                    exclude: excluding(draftTests, from: testFiles), sources: draftTests),
        .target(name: "FoodLogBackup", dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")],
                path: "FoodLog", exclude: appOnlyFiles + localLogicFiles,
                sources: ["FoodBackup.swift", "FoodBackupRestore.swift"], resources: [.process("FoodLog.xcdatamodeld")]),
        .testTarget(name: "FoodLogBackupTests", dependencies: ["FoodLogBackup"], path: "FoodLogTests",
                    exclude: excluding(backupTests, from: testFiles), sources: backupTests)
    ]
)

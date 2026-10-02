import SwiftUI
import UIKit

@main
struct FoodLogApp: App {
    private let persistence: PersistenceController
    @StateObject private var reminder = FoodDailyReminder.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing") {
            let storeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("FoodLogUITests.sqlite")
            if arguments.contains("--reset-ui-test-store") {
                for suffix in ["", "-shm", "-wal"] {
                    try? FileManager.default.removeItem(atPath: storeURL.path + suffix)
                }
                try? FileManager.default.removeItem(at: FoodEntryDraftStore.defaultURL)
                UserDefaults.standard.removeObject(forKey: AppRelockDelay.settingKey)
            }
            let testPersistence = PersistenceController(storeURL: storeURL)
            if arguments.contains("--seed-ui-test-draft") {
                let draft = FoodEntryDraft(
                    food: "Private unfinished meal",
                    date: Date(),
                    mealType: "Lunch",
                    place: "Home",
                    placeCity: "",
                    placeLatitude: 0,
                    placeLongitude: 0,
                    hasPlaceCoordinates: false,
                    selectedPlaceLabel: nil,
                    selectedPlaceSavedName: nil,
                    companions: ["Ana"],
                    companionQuery: "",
                    note: "Private draft note",
                    photoData: nil,
                    startFastAfterMeal: false,
                    detailsExpanded: true
                )
                try? FoodEntryDraftStore.shared.save(draft, for: .new, active: true)
            }
            if arguments.contains("--seed-ui-test-map") {
                let context = testPersistence.container.viewContext
                context.performAndWait {
                    let request = FoodEntry.fetchRequest()
                    request.predicate = NSPredicate(format: "food == %@", "Map fixture")
                    guard (try? context.count(for: request)) == 0 else { return }
                    let entry = FoodEntry(context: context)
                    entry.id = UUID()
                    entry.createdAt = Date()
                    entry.date = Date()
                    entry.food = "Map fixture"
                    entry.mealType = "Lunch"
                    entry.place = "Roastery Coffee House, Hyderabad"
                    entry.placeCity = "Hyderabad"
                    entry.placeLatitude = 17.4239
                    entry.placeLongitude = 78.4485
                    entry.hasPlaceCoordinates = true
                    entry.replaceCompanions(with: ["Ana", "Bob"], in: context)
                    try? context.save()
                }
            }
            if arguments.contains("--seed-ui-test-suggestions") {
                let context = testPersistence.container.viewContext
                context.performAndWait {
                    for (food, date) in [
                        ("Toast, Eggs", Date(timeIntervalSinceNow: -86_400)),
                        ("Toast, Coffee", Date(timeIntervalSinceNow: -172_800))
                    ] {
                        let entry = FoodEntry(context: context)
                        entry.id = UUID()
                        entry.createdAt = date
                        entry.date = date
                        entry.food = food
                        entry.mealType = "Breakfast"
                    }
                    try? context.save()
                }
            }
            if arguments.contains("--seed-ui-test-navigation") {
                let context = testPersistence.container.viewContext
                context.performAndWait {
                    for index in 0 ..< 20 {
                        let entry = FoodEntry(context: context)
                        entry.id = UUID()
                        entry.createdAt = Date(timeIntervalSinceNow: TimeInterval(-index))
                        entry.date = Date(timeIntervalSinceNow: TimeInterval(-index * 60))
                        entry.food = "Navigation fixture \(index + 1)"
                        entry.mealType = "Snack"
                    }
                    try? context.save()
                }
            }
            if arguments.contains("--seed-ui-test-fasting-history") {
                let context = testPersistence.container.viewContext
                context.performAndWait {
                    let calendar = Calendar.current
                    let today = calendar.startOfDay(for: Date())
                    for index in 0..<66 {
                        let day = calendar.date(byAdding: .day, value: -index, to: today)!
                        for (hour, type) in [(index < 30 ? 8 : 11, "Breakfast"), (20, "Dinner")] {
                            let timestamp = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
                            let entry = FoodEntry(context: context)
                            entry.id = UUID()
                            entry.createdAt = timestamp
                            entry.date = timestamp
                            entry.food = "History fixture \(index) \(type)"
                            entry.mealType = type
                        }
                    }
                    try? context.save()
                }
            }
            if arguments.contains("--seed-ui-test-overnight") {
                let context = testPersistence.container.viewContext
                context.performAndWait {
                    let calendar = Calendar.current
                    let today = calendar.startOfDay(for: Date())
                    for (food, offset, hour, type) in [
                        ("Overnight dinner", -1, 22, "Dinner"),
                        ("Late drink", -1, 23, "Drink"),
                        ("Early drink", 0, 7, "Drink"),
                        ("Overnight breakfast", 0, 8, "Breakfast"),
                        ("Later lunch", 0, 12, "Lunch")
                    ] {
                        let day = calendar.date(byAdding: .day, value: offset, to: today)!
                        let timestamp = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
                        let entry = FoodEntry(context: context)
                        entry.id = UUID()
                        entry.createdAt = timestamp
                        entry.date = timestamp
                        entry.food = food
                        entry.mealType = type
                    }
                    let start = calendar.date(byAdding: .day, value: -3, to: today)!
                    _ = try? FastingStore.create(start: start, end: start.addingTimeInterval(12 * 3_600), in: context)
                    try? context.save()
                }
            }
            persistence = testPersistence
            return
        }
#endif
        persistence = PersistenceController.shared
    }

    var body: some Scene {
        WindowGroup {
            AppLockView {
                ContentView()
            }
            .environment(\.managedObjectContext, persistence.container.viewContext)
            .task { await reminder.refresh() }
            .onChange(of: scenePhase) { phase in
                if phase == .active { Task { await reminder.refresh() } }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                if scenePhase == .active { Task { await reminder.refresh() } }
            }
        }
    }
}

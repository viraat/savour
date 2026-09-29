import SwiftUI

@main
struct FoodLogApp: App {
    private let persistence: PersistenceController

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
        }
    }
}

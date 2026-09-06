import CoreData

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "FoodLog")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.persistentStoreDescriptions.first?.setOption(
            true as NSNumber,
            forKey: NSPersistentHistoryTrackingKey
        )
        container.persistentStoreDescriptions.first?.setOption(
            true as NSNumber,
            forKey: NSMigratePersistentStoresAutomaticallyOption
        )
        container.persistentStoreDescriptions.first?.setOption(
            true as NSNumber,
            forKey: NSInferMappingModelAutomaticallyOption
        )

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Unable to load FoodLog store: \(error.localizedDescription)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}

extension FoodEntry {
    var wrappedID: UUID { id ?? UUID() }
    var wrappedFood: String { food ?? "Untitled entry" }
    var wrappedDate: Date { date ?? Date() }
    var wrappedMealType: String { mealType ?? "Other" }
    var wrappedPlace: String { place ?? "" }
    var wrappedPeople: String { people ?? "" }
    var wrappedNote: String { note ?? "" }
}

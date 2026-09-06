import CoreData

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "FoodLog")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
            container.persistentStoreDescriptions.first?.cloudKitContainerOptions = nil
        } else if CloudConfiguration.isCloudKitAvailableInCurrentBuild {
            container.persistentStoreDescriptions.first?.cloudKitContainerOptions =
                NSPersistentCloudKitContainerOptions(
                    containerIdentifier: CloudConfiguration.containerIdentifier
                )
        } else {
            container.persistentStoreDescriptions.first?.cloudKitContainerOptions = nil
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
        container.persistentStoreDescriptions.first?.setOption(
            true as NSNumber,
            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
        )

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Unable to load FoodLog store: \(error.localizedDescription)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        try? container.viewContext.setQueryGenerationFrom(.current)
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

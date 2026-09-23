import CoreData

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false, storeURL: URL? = nil) {
        container = NSPersistentContainer(name: "FoodLog")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else if let storeURL {
            container.persistentStoreDescriptions.first?.url = storeURL
        }
        container.persistentStoreDescriptions.first?.shouldAddStoreAsynchronously = false

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

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        container.loadPersistentStores { [weak container] _, error in
            if let error {
                fatalError("Unable to load FoodLog store: \(error.localizedDescription)")
            }

            guard let context = container?.viewContext else { return }
            context.performAndWait {
                do {
                    try Self.migrateLegacyEntries(in: context)
                } catch {
                    NSLog("FoodLog could not finish migrating legacy entries: %@", error.localizedDescription)
                }
            }
        }

    }

    struct MigrationReport: Equatable {
        var assignedIDs = 0
        var assignedCreationDates = 0
        var structuredPeople = 0
        var invalidCoordinatesDisabled = 0
    }

    @discardableResult
    static func migrateLegacyEntries(in context: NSManagedObjectContext) throws -> MigrationReport {
        let request: NSFetchRequest<FoodEntry> = FoodEntry.fetchRequest()
        let entries = try context.fetch(request)
        var seenIDs = Set<UUID>()
        var report = MigrationReport()

        for entry in entries {
            if let id = entry.id, seenIDs.insert(id).inserted {
                // Keep the original identity when it is unique.
            } else {
                let id = UUID()
                entry.id = id
                seenIDs.insert(id)
                report.assignedIDs += 1
            }

            if entry.createdAt == nil {
                entry.createdAt = entry.date ?? Date()
                report.assignedCreationDates += 1
            }

            if entry.companionRecords.isEmpty {
                let names = CompanionNames.parse(entry.wrappedPeople)
                if !names.isEmpty {
                    for (index, name) in names.enumerated() {
                        let companion = FoodEntryCompanion(context: context)
                        companion.id = UUID()
                        companion.name = name
                        companion.sortIndex = Int16(clamping: index)
                        companion.entry = entry
                    }
                    report.structuredPeople += 1
                }
            }

            if entry.hasPlaceCoordinates && !Self.validCoordinates(
                latitude: entry.placeLatitude,
                longitude: entry.placeLongitude
            ) {
                entry.hasPlaceCoordinates = false
                report.invalidCoordinatesDisabled += 1
            }
        }

        if context.hasChanges {
            do {
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
        return report
    }

    static func validCoordinates(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite
            && (-90 ... 90).contains(latitude)
            && (-180 ... 180).contains(longitude)
    }
}

enum CompanionNames {
    static func parse(_ legacyValue: String) -> [String] {
        let separated = legacyValue
            .replacingOccurrences(of: " and ", with: ",", options: .caseInsensitive)
            .replacingOccurrences(of: " & ", with: ",")
        return normalized(separated.components(separatedBy: CharacterSet(charactersIn: ",;\n")))
    }

    static func normalized(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { return nil }
            return trimmed
        }
    }
}

extension FoodEntry {
    var wrappedID: UUID { id ?? UUID() }
    var wrappedFood: String { food ?? "Untitled entry" }
    var wrappedDate: Date { date ?? Date() }
    var wrappedMealType: String { mealType ?? "Other" }
    var wrappedPlace: String { place ?? "" }
    var wrappedPlaceCity: String { placeCity ?? "" }
    var wrappedPeople: String { people ?? "" }
    var wrappedNote: String { note ?? "" }

    var placeCoordinates: (latitude: Double, longitude: Double)? {
        guard hasPlaceCoordinates,
              PersistenceController.validCoordinates(latitude: placeLatitude, longitude: placeLongitude)
        else { return nil }
        return (placeLatitude, placeLongitude)
    }

    var companionRecords: [FoodEntryCompanion] {
        let records = companions as? Set<FoodEntryCompanion> ?? []
        return records.sorted {
            if $0.sortIndex != $1.sortIndex { return $0.sortIndex < $1.sortIndex }
            return $0.wrappedName.localizedCaseInsensitiveCompare($1.wrappedName) == .orderedAscending
        }
    }

    var companionNames: [String] {
        let storedNames = companionRecords.map(\.wrappedName).filter { !$0.isEmpty }
        return storedNames.isEmpty ? CompanionNames.parse(wrappedPeople) : storedNames
    }

    var companionDisplayText: String {
        companionNames.joined(separator: ", ")
    }

    func replaceCompanions(with names: [String], in context: NSManagedObjectContext) {
        companionRecords.forEach(context.delete)

        let normalizedNames = CompanionNames.normalized(names)
        for (index, name) in normalizedNames.enumerated() {
            let companion = FoodEntryCompanion(context: context)
            companion.id = UUID()
            companion.name = name
            companion.sortIndex = Int16(clamping: index)
            companion.entry = self
        }
        people = normalizedNames.joined(separator: ", ")
    }
}

extension FoodEntryCompanion {
    var wrappedName: String { name ?? "" }
}

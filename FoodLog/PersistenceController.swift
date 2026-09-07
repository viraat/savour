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

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        container.loadPersistentStores { [weak container] _, error in
            if let error {
                fatalError("Unable to load FoodLog store: \(error.localizedDescription)")
            }

            guard let context = container?.viewContext else { return }
            context.perform {
                Self.migrateLegacyCompanions(in: context)
            }
        }

    }

    private static func migrateLegacyCompanions(in context: NSManagedObjectContext) {
        let request = FoodEntry.fetchRequest()
        guard let entries = try? context.fetch(request) else { return }

        var changed = false
        for entry in entries where entry.companionRecords.isEmpty {
            let names = CompanionNames.parse(entry.wrappedPeople)
            guard !names.isEmpty else { continue }
            entry.replaceCompanions(with: names, in: context)
            changed = true
        }

        if changed {
            try? context.save()
        }
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
    var wrappedPeople: String { people ?? "" }
    var wrappedNote: String { note ?? "" }

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

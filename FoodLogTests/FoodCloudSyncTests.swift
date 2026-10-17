import CloudKit
import CoreData
import XCTest
#if SWIFT_PACKAGE
@testable import FoodLogBackup
#else
@testable import FoodLog
#endif

/// Private local SQLite fixtures only. No simulator, Apple account or network.
@MainActor
final class FoodCloudSyncTests: XCTestCase {
    private func model(_ version: String? = nil) throws -> NSManagedObjectModel {
#if SWIFT_PACKAGE
        let bundle = SavourBackupExporter.modelBundle
#else
        let bundle = Bundle.main
#endif
        let directory = try XCTUnwrap(bundle.url(forResource: "FoodLog", withExtension: "momd"))
        let source = try XCTUnwrap(NSManagedObjectModel(contentsOf: version.map { directory.appendingPathComponent("\($0).mom") } ?? directory))
        let result = try XCTUnwrap(source.copy() as? NSManagedObjectModel)
        result.entities.forEach { $0.managedObjectClassName = "NSManagedObject" }
        return result
    }

    private func fixture(_ operation: (NSManagedObjectContext) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SavourCloudTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: try model())
        let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil,
            at: directory.appendingPathComponent("journal.sqlite"), options: [NSPersistentHistoryTrackingKey: true])
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        defer { context.reset(); try? coordinator.remove(store) }
        try operation(context)
    }

    @discardableResult
    private func meal(_ context: NSManagedObjectContext, id: UUID, note: String = "Note",
                      personID: UUID? = nil, photo: Data? = nil) -> NSManagedObject {
        let object = NSEntityDescription.insertNewObject(forEntityName: "FoodEntry", into: context)
        ["id": id, "date": Date(timeIntervalSince1970: 1_700_000_000),
         "createdAt": Date(timeIntervalSince1970: 1_700_000_000), "food": "Rice, tofu",
         "mealType": "Dinner", "place": "Cafe", "placeCity": "London", "note": note,
         "people": personID == nil ? "" : "Ana", "hasPlaceCoordinates": true,
         "placeLatitude": 51.5, "placeLongitude": -0.1].forEach { object.setValue($0.value, forKey: $0.key) }
        object.setValue(photo, forKey: "photoData")
        if let personID {
            let person = NSEntityDescription.insertNewObject(forEntityName: "FoodEntryCompanion", into: context)
            person.setValue(personID, forKey: "id")
            person.setValue("Ana", forKey: "name")
            person.setValue(0, forKey: "sortIndex")
            person.setValue(object, forKey: "entry")
        }
        return object
    }

    func testSyncIsOptInAndNeverUsedByOldTargetOrIsolatedTestStores() {
        XCTAssertFalse(FoodCloudSyncConfiguration.shouldSync(requested: false, bundleID: "tech.buildboring.Savour", isolatedStore: false))
        XCTAssertFalse(FoodCloudSyncConfiguration.shouldSync(requested: true, bundleID: "com.viraat.foodlog", isolatedStore: false))
        XCTAssertFalse(FoodCloudSyncConfiguration.shouldSync(requested: true, bundleID: "tech.buildboring.Savour", isolatedStore: true))
        XCTAssertTrue(FoodCloudSyncConfiguration.shouldSync(requested: true, bundleID: "tech.buildboring.Savour", isolatedStore: false))
    }

    func testCloudConfigurationIsPrivateAndKeepsMigrationHistoryAndRemoteChanges() {
        let url = URL(fileURLWithPath: "/private/tmp/cloud-configuration-test.sqlite")
        let description = NSPersistentStoreDescription(url: url)
        FoodCloudSyncConfiguration.configure(description, syncEnabled: true)
        XCTAssertEqual(description.url, url)
        XCTAssertEqual(description.cloudKitContainerOptions?.containerIdentifier, "iCloud.tech.buildboring.Savour")
        XCTAssertEqual(description.cloudKitContainerOptions?.databaseScope, .private)
        XCTAssertTrue(description.shouldMigrateStoreAutomatically)
        XCTAssertTrue(description.shouldInferMappingModelAutomatically)
        XCTAssertEqual(description.options[NSPersistentHistoryTrackingKey] as? NSNumber, true)
        XCTAssertEqual(description.options[NSPersistentStoreRemoteChangeNotificationPostOptionKey] as? NSNumber, true)
        FoodCloudSyncConfiguration.configure(description, syncEnabled: false)
        XCTAssertNil(description.cloudKitContainerOptions)
        XCTAssertEqual(description.url, url)
        XCTAssertEqual(description.options[NSPersistentHistoryTrackingKey] as? NSNumber, true)
    }

    func testCurrentModelMeetsCloudKitModelRequirements() throws {
        let model = try model()
        for entity in model.entities {
            XCTAssertTrue(entity.uniquenessConstraints.isEmpty, entity.name ?? "")
            for attribute in entity.attributesByName.values {
                XCTAssertTrue(attribute.isOptional || attribute.defaultValue != nil, attribute.name)
                XCTAssertNotEqual(attribute.attributeType, .undefinedAttributeType)
                XCTAssertNotEqual(attribute.attributeType, .objectIDAttributeType)
            }
            for relation in entity.relationshipsByName.values {
                XCTAssertTrue(relation.isOptional, relation.name)
                XCTAssertNotNil(relation.inverseRelationship, relation.name)
                XCTAssertNotEqual(relation.deleteRule, .denyDeleteRule)
                XCTAssertFalse(relation.isOrdered, relation.name)
            }
        }
        XCTAssertTrue(try XCTUnwrap(model.entitiesByName["FoodEntry"]?.attributesByName["photoData"]).allowsExternalBinaryDataStorage)
    }

    func testEveryPreviousStoreMigratesWithoutChangingUUIDsTimesPhotosOrRelationships() throws {
        for version in ["FoodLog", "FoodLogV2", "FoodLogV3", "FoodLogV4", "FoodLogV5"] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SavourCloudMigration-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("journal.sqlite")
            let old = NSPersistentStoreCoordinator(managedObjectModel: try model(version))
            let store = try old.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url)
            let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            context.persistentStoreCoordinator = old
            let id = UUID(), personID = UUID(), fastID = UUID()
            let time = Date(timeIntervalSinceReferenceDate: -123.12345)
            let bytes = Data(repeating: 42, count: 256_000)
            let entry = NSEntityDescription.insertNewObject(forEntityName: "FoodEntry", into: context)
            ["id": id, "food": "Meal, \"quotes\"\nnext line", "date": time,
             "mealType": "Lunch", "people": "Ana", "note": "Notes", "place": "Home"].forEach { entry.setValue($0.value, forKey: $0.key) }
            if entry.entity.attributesByName["photoData"] != nil { entry.setValue(bytes, forKey: "photoData") }
            if entry.entity.attributesByName["placeLatitude"] != nil {
                entry.setValue(true, forKey: "hasPlaceCoordinates")
                entry.setValue(17.4, forKey: "placeLatitude")
                entry.setValue(78.4, forKey: "placeLongitude")
                entry.setValue("Hyderabad", forKey: "placeCity")
            }
            if old.managedObjectModel.entitiesByName["FoodEntryCompanion"] != nil {
                let person = NSEntityDescription.insertNewObject(forEntityName: "FoodEntryCompanion", into: context)
                person.setValue(personID, forKey: "id"); person.setValue("Ana", forKey: "name")
                person.setValue(entry, forKey: "entry")
            }
            if old.managedObjectModel.entitiesByName["FastSession"] != nil {
                let fast = NSEntityDescription.insertNewObject(forEntityName: "FastSession", into: context)
                fast.setValue(fastID, forKey: "id"); fast.setValue(time, forKey: "startDate")
                fast.setValue(time, forKey: "createdAt"); fast.setValue(id, forKey: "startEntryID")
            }
            try context.save()
            let attributes = entry.dictionaryWithValues(forKeys: Array(entry.entity.attributesByName.keys)) as NSDictionary
            context.reset(); try old.remove(store)
            let upgraded = NSPersistentStoreCoordinator(managedObjectModel: try model())
            let newStore = try upgraded.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url,
                options: [NSMigratePersistentStoresAutomaticallyOption: true, NSInferMappingModelAutomaticallyOption: true,
                          NSPersistentHistoryTrackingKey: true])
            let migrated = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            migrated.persistentStoreCoordinator = upgraded
            let result = try XCTUnwrap(migrated.fetch(NSFetchRequest<NSManagedObject>(entityName: "FoodEntry")).first)
            XCTAssertEqual(result.dictionaryWithValues(forKeys: attributes.allKeys as! [String]) as NSDictionary, attributes, version)
            if version == "FoodLogV4" || version == "FoodLogV5" {
                let people = result.value(forKey: "companions") as? Set<NSManagedObject>
                XCTAssertEqual(people?.first?.value(forKey: "id") as? UUID, personID)
                XCTAssertEqual(people?.first?.value(forKey: "entry") as? NSManagedObject, result)
            }
            if version == "FoodLogV5" {
                let fast = try XCTUnwrap(migrated.fetch(NSFetchRequest<NSManagedObject>(entityName: "FastSession")).first)
                XCTAssertEqual(fast.value(forKey: "id") as? UUID, fastID)
                XCTAssertEqual(fast.value(forKey: "startDate") as? Date, time)
                XCTAssertEqual(fast.value(forKey: "startEntryID") as? UUID, id)
            }
            migrated.reset(); try upgraded.remove(newStore)
            // The same migrated store reopens normally; sync doesn't change its path.
            let reopened = try upgraded.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url)
            XCTAssertEqual(try migrated.count(for: NSFetchRequest<NSManagedObject>(entityName: "FoodEntry")), 1)
            migrated.reset(); try upgraded.remove(reopened)
        }
    }

    func testIdenticalUUIDGraphsCoalesceWithPhotosAndChooseStableCloudRecord() throws {
        try fixture { context in
            let id = UUID(), personID = UUID(), photo = Data(repeating: 19, count: 160_000)
            let a = meal(context, id: id, personID: personID, photo: photo)
            let b = meal(context, id: id, personID: personID, photo: photo)
            try context.save()
            let names = [a.objectID: "record-z", b.objectID: "record-a"]
            XCTAssertEqual(try FoodCloudDuplicateRepair.coalesceIdenticalEntries(in: context) { names[$0] }, 1)
            let rows = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "FoodEntry"))
            XCTAssertEqual(rows.map(\.objectID), [b.objectID])
            XCTAssertEqual(rows.first?.value(forKey: "photoData") as? Data, photo)
            XCTAssertEqual(try context.count(for: NSFetchRequest<NSManagedObject>(entityName: "FoodEntryCompanion")), 1)
            XCTAssertEqual(try FoodCloudDuplicateRepair.coalesceIdenticalEntries(in: context) { names[$0] }, 0)
        }
    }

    func testConflictingUUIDRecordsAreNeverDeleted() throws {
        try fixture { context in
            let id = UUID()
            _ = meal(context, id: id, note: "Local edit")
            _ = meal(context, id: id, note: "Remote edit")
            try context.save()
            XCTAssertEqual(try FoodCloudDuplicateRepair.coalesceIdenticalEntries(in: context) { $0.uriRepresentation().absoluteString }, 0)
            XCTAssertEqual(try context.count(for: NSFetchRequest<NSManagedObject>(entityName: "FoodEntry")), 2)
        }
    }

    func testIndependentImportsKeepEarliestCreationTimeForSameUnchangedUUID() throws {
        try fixture { context in
            let id = UUID()
            let a = meal(context, id: id)
            let b = meal(context, id: id)
            let earliest = Date(timeIntervalSince1970: 1_600_000_000)
            a.setValue(earliest, forKey: "createdAt")
            try context.save()
            let names = [a.objectID: "record-z", b.objectID: "record-a"]
            XCTAssertEqual(try FoodCloudDuplicateRepair.coalesceIdenticalEntries(in: context) { names[$0] }, 1)
            XCTAssertEqual(b.value(forKey: "createdAt") as? Date, earliest)
            XCTAssertEqual(b.value(forKey: "id") as? UUID, id)
        }
    }

    func testSameMealsWithDifferentUUIDsAreNotDuplicates() throws {
        try fixture { context in
            _ = meal(context, id: UUID()); _ = meal(context, id: UUID())
            try context.save()
            XCTAssertEqual(try FoodCloudDuplicateRepair.coalesceIdenticalEntries(in: context) { $0.uriRepresentation().absoluteString }, 0)
        }
    }

    func testPartiallyImportedPeopleAndMissingCloudIdentitiesDeferRepair() throws {
        try fixture { context in
            let id = UUID(), personID = UUID()
            let a = meal(context, id: id, personID: personID)
            let b = meal(context, id: id)
            b.setValue("Ana", forKey: "people")
            try context.save()
            XCTAssertEqual(try FoodCloudDuplicateRepair.coalesceIdenticalEntries(in: context) { $0.uriRepresentation().absoluteString }, 0)
            b.setValue("", forKey: "people"); a.setValue("", forKey: "people")
            (a.value(forKey: "companions") as? Set<NSManagedObject>)?.forEach(context.delete)
            try context.save()
            XCTAssertEqual(try FoodCloudDuplicateRepair.coalesceIdenticalEntries(in: context) { _ in nil }, 0)
            XCTAssertEqual(try context.count(for: NSFetchRequest<NSManagedObject>(entityName: "FoodEntry")), 2)
        }
    }

    func testSyncErrorMessagesDoNotExposeJournalOrRawServerDetails() {
        let raw = NSError(domain: CKErrorDomain, code: CKError.quotaExceeded.rawValue,
                          userInfo: [NSLocalizedDescriptionKey: "Private note from server"])
        XCTAssertTrue(FoodCloudSyncMonitor.message(for: raw).contains("storage is full"))
        XCTAssertFalse(FoodCloudSyncMonitor.message(for: raw).contains("Private note"))
        XCTAssertTrue(FoodCloudSyncMonitor.message(for: CKError(.networkUnavailable)).contains("tries again automatically"))
        XCTAssertTrue(FoodCloudSyncMonitor.message(for: nil).contains("stay on this device"))
    }

    func testPartialFailureWrappingQuotaExceededIsRecognized() {
        let inner = NSError(domain: CKErrorDomain, code: CKError.quotaExceeded.rawValue)
        let wrapped = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: ["record": inner]])
        XCTAssertTrue(FoodCloudSyncMonitor.message(for: wrapped).contains("storage is full"))
    }

    private func localMirroringContainer() throws -> (NSPersistentCloudKitContainer, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SavourRemoteMerge-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let container = NSPersistentCloudKitContainer(name: "FoodLog", managedObjectModel: try model())
        let description = NSPersistentStoreDescription(url: directory.appendingPathComponent("journal.sqlite"))
        description.shouldAddStoreAsynchronously = false
        // Test the real history merger without any CloudKit options/network.
        FoodCloudSyncConfiguration.configure(description, syncEnabled: false)
        container.persistentStoreDescriptions = [description]
        var failure: Error?
        container.loadPersistentStores { _, error in failure = error }
        if let failure { throw failure }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.transactionAuthor = FoodCloudSyncConfiguration.transactionAuthor
        return (container, directory)
    }

    private func close(_ container: NSPersistentContainer, directory: URL) {
        container.viewContext.reset()
        for store in container.persistentStoreCoordinator.persistentStores {
            try? container.persistentStoreCoordinator.remove(store)
        }
        try? FileManager.default.removeItem(at: directory)
    }

    func testIncomingHistoryUpdatesUIWithoutDiscardingAnUnfinishedEdit() async throws {
        let (container, directory) = try localMirroringContainer()
        defer { close(container, directory: directory) }
        let entry = meal(container.viewContext, id: UUID())
        try container.viewContext.save()
        let merger = FoodCloudHistoryMerger(container: container)
        let id = entry.objectID
        entry.setValue("Unfinished place", forKey: "place")
        let remote = container.newBackgroundContext()
        remote.transactionAuthor = "Remote.fixture"
        try await remote.perform {
            let meal = try remote.existingObject(with: id)
            meal.setValue("Remote note", forKey: "note")
            try remote.save()
        }
        let updated = expectation(description: "Remote change merged")
        merger.processChanges { updated.fulfill() }
        await fulfillment(of: [updated], timeout: 3)
        XCTAssertEqual(entry.value(forKey: "note") as? String, "Remote note")
        XCTAssertEqual(entry.value(forKey: "place") as? String, "Unfinished place")
        XCTAssertTrue(container.viewContext.hasChanges)
        container.viewContext.rollback()
        remote.performAndWait { remote.reset() }
    }

    func testIncomingDeletionIsMergedAndDoesNotAffectOtherMeals() async throws {
        let (container, directory) = try localMirroringContainer()
        defer { close(container, directory: directory) }
        let entry = meal(container.viewContext, id: UUID())
        let other = meal(container.viewContext, id: UUID(), note: "Keep me")
        try container.viewContext.save()
        let merger = FoodCloudHistoryMerger(container: container)
        let id = entry.objectID
        let remote = container.newBackgroundContext()
        remote.transactionAuthor = "Remote.fixture"
        try await remote.perform {
            remote.delete(try remote.existingObject(with: id))
            try remote.save()
        }
        let updated = expectation(description: "Remote deletion merged")
        merger.processChanges { updated.fulfill() }
        await fulfillment(of: [updated], timeout: 3)
        XCTAssertTrue(entry.isDeleted || entry.managedObjectContext == nil)
        XCTAssertEqual(other.value(forKey: "note") as? String, "Keep me")
        XCTAssertEqual(try container.viewContext.count(for: NSFetchRequest<NSManagedObject>(entityName: "FoodEntry")), 1)
        remote.performAndWait { remote.reset() }
    }
}

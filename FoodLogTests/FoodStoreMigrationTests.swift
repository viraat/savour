import CoreData
import XCTest
#if canImport(FoodLogPerformance)
@testable import FoodLogPerformance
#else
@testable import FoodLog
#endif

final class FoodStoreMigrationTests: XCTestCase {
    private enum TestError: Error { case migrationFailed, metadataSaveFailed }

    @MainActor
    func testPopulatedStoreMarkerSurvivesReopeningAndPreservesData() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite")
        let (coordinator, store, context) = try stack(url: url)
        let id = UUID()
        let photo = Data(repeating: 42, count: 300_000)
        let meal = NSEntityDescription.insertNewObject(forEntityName: "Meal", into: context)
        meal.setValue("Existing meal", forKey: "name")
        meal.setValue(id, forKey: "id")
        meal.setValue(photo, forKey: "photo")
        try context.save()
        let originalMetadata = coordinator.metadata(for: store)
        XCTAssertTrue(try FoodStoreMigration.runIfNeeded(in: context, store: store) {
            meal.setValue("Repaired meal", forKey: "name")
        })
        XCTAssertEqual(coordinator.metadata(for: store)[NSStoreUUIDKey] as? String,
                       originalMetadata[NSStoreUUIDKey] as? String)
        XCTAssertEqual(coordinator.metadata(for: store)[NSStoreTypeKey] as? String,
                       originalMetadata[NSStoreTypeKey] as? String)
        context.reset()
        try coordinator.remove(store)

        let (reopenedCoordinator, reopenedStore, reopenedContext) = try stack(url: url)
        defer { reopenedContext.reset(); try? reopenedCoordinator.remove(reopenedStore) }
        XCTAssertFalse(try FoodStoreMigration.runIfNeeded(in: reopenedContext, store: reopenedStore) {
            XCTFail("Completed store must not migrate on relaunch")
        })
        let restored = try XCTUnwrap(reopenedContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Meal")).first)
        XCTAssertEqual(restored.value(forKey: "name") as? String, "Repaired meal")
        XCTAssertEqual(restored.value(forKey: "id") as? UUID, id)
        XCTAssertEqual(restored.value(forKey: "photo") as? Data, photo)
    }

    @MainActor
    func testEmptyStoreMarkerPersistsWithoutDummyRowsOrDirtyContext() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("empty.sqlite")
        let (coordinator, store, context) = try stack(url: url)
        XCTAssertFalse(context.hasChanges)
        XCTAssertTrue(try FoodStoreMigration.runIfNeeded(in: context, store: store) {})
        XCTAssertTrue(context.registeredObjects.isEmpty)
        try coordinator.remove(store)
        let (reopenedCoordinator, reopenedStore, reopenedContext) = try stack(url: url)
        defer { try? reopenedCoordinator.remove(reopenedStore) }
        XCTAssertFalse(try FoodStoreMigration.runIfNeeded(in: reopenedContext, store: reopenedStore) {
            XCTFail("Empty journal must not repeat migration")
        })
        XCTAssertTrue(reopenedContext.registeredObjects.isEmpty)
        XCTAssertEqual(try reopenedContext.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "Meal")), 0)
    }

    @MainActor
    func testSkipDoesNotFetchObjectsOrSaveUnrelatedPendingChanges() async throws {
        let (coordinator, store, context) = try stack()
        XCTAssertTrue(try FoodStoreMigration.runIfNeeded(in: context, store: store) {})
        context.reset()
        let pending = NSEntityDescription.insertNewObject(forEntityName: "Meal", into: context)
        pending.setValue("Unfinished edit", forKey: "name")
        XCTAssertFalse(try FoodStoreMigration.runIfNeeded(in: context, store: store) {
            XCTFail("Skip must happen before migration/fetch")
        })
        XCTAssertTrue(pending.isInserted)
        XCTAssertTrue(context.hasChanges)
        let otherContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        otherContext.persistentStoreCoordinator = coordinator
        XCTAssertEqual(try otherContext.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "Meal")), 0)
    }

    @MainActor
    func testMigrationFailureLeavesNoMarkerAndRetries() async throws {
        let (coordinator, store, context) = try stack()
        var calls = 0
        XCTAssertThrowsError(try FoodStoreMigration.runIfNeeded(in: context, store: store) {
            calls += 1
            throw TestError.migrationFailed
        })
        XCTAssertNil(coordinator.metadata(for: store)[FoodStoreMigration.metadataKey])
        XCTAssertTrue(try FoodStoreMigration.runIfNeeded(in: context, store: store) { calls += 1 })
        XCTAssertEqual(calls, 2)
    }

    @MainActor
    func testDataSaveFailureLeavesNoCompletionMarker() async throws {
        let (coordinator, store, context) = try stack()
        XCTAssertThrowsError(try FoodStoreMigration.runIfNeeded(in: context, store: store) {
            // Missing mandatory name makes the repair's save fail validation.
            _ = NSEntityDescription.insertNewObject(forEntityName: "Meal", into: context)
        })
        XCTAssertNil(coordinator.metadata(for: store)[FoodStoreMigration.metadataKey])
        context.rollback()
        XCTAssertTrue(try FoodStoreMigration.runIfNeeded(in: context, store: store) {})
    }

    @MainActor
    func testMetadataSaveFailureRestoresCachedMarkerAndAllowsRetry() async throws {
        let coordinator = FailingMetadataCoordinator(managedObjectModel: model())
        let store = try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil,
                                                       at: nil, options: nil)
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        let originalUUID = coordinator.metadata(for: store)[NSStoreUUIDKey] as? String
        coordinator.failMetadataSave = true
        XCTAssertThrowsError(try FoodStoreMigration.runIfNeeded(in: context, store: store) {})
        XCTAssertNil(coordinator.metadata(for: store)[FoodStoreMigration.metadataKey])
        XCTAssertEqual(coordinator.metadata(for: store)[NSStoreUUIDKey] as? String, originalUUID)
        coordinator.failMetadataSave = false
        XCTAssertTrue(try FoodStoreMigration.runIfNeeded(in: context, store: store) {})
        XCTAssertFalse(try FoodStoreMigration.runIfNeeded(in: context, store: store) { XCTFail("Retried marker missing") })
    }

    @MainActor
    func testMigrationVersionCanAdvanceAndDoesNotDowngradeNewerMarker() async throws {
        let (coordinator, store, context) = try stack()
        var metadata = coordinator.metadata(for: store)
        metadata[FoodStoreMigration.metadataKey] = "not-a-version"
        metadata["unrelated.custom.metadata"] = "Keep this"
        coordinator.setMetadata(metadata, for: store)
        var calls = 0
        XCTAssertTrue(try FoodStoreMigration.runIfNeeded(in: context, store: store) { calls += 1 })
        XCTAssertFalse(try FoodStoreMigration.runIfNeeded(in: context, store: store) { calls += 1 })
        XCTAssertTrue(try FoodStoreMigration.runIfNeeded(in: context, store: store, version: 2) { calls += 1 })
        XCTAssertFalse(try FoodStoreMigration.runIfNeeded(in: context, store: store, version: 1) { calls += 1 })
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(coordinator.metadata(for: store)[FoodStoreMigration.metadataKey] as? Int, 2)
        XCTAssertEqual(coordinator.metadata(for: store)["unrelated.custom.metadata"] as? String, "Keep this")
    }

    @MainActor
    func testMarkerIsPerStoreNotGlobalToCoordinator() async throws {
        let (coordinator, first, context) = try stack()
        let second = try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil,
                                                        at: nil, options: nil)
        XCTAssertTrue(try FoodStoreMigration.runIfNeeded(in: context, store: first) {})
        XCTAssertNil(coordinator.metadata(for: second)[FoodStoreMigration.metadataKey])
        XCTAssertTrue(try FoodStoreMigration.runIfNeeded(in: context, store: second) {})
        XCTAssertFalse(try FoodStoreMigration.runIfNeeded(in: context, store: first) { XCTFail("First store repeated") })
        XCTAssertFalse(try FoodStoreMigration.runIfNeeded(in: context, store: second) { XCTFail("Second store repeated") })
    }

    @MainActor
    func testReplacementAtSameURLMustMigrateAgain() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("replace.sqlite")
        let (coordinator, store, context) = try stack(url: url)
        XCTAssertTrue(try FoodStoreMigration.runIfNeeded(in: context, store: store) {})
        context.reset()
        try coordinator.remove(store)
        // Only this test-owned database is removed, using Core Data's store API.
        try coordinator.destroyPersistentStore(at: url, ofType: NSSQLiteStoreType, options: nil)
        let (replacementCoordinator, replacementStore, replacementContext) = try stack(url: url)
        defer { try? replacementCoordinator.remove(replacementStore) }
        XCTAssertTrue(try FoodStoreMigration.runIfNeeded(in: replacementContext, store: replacementStore) {})
    }

    @MainActor
    func testForeignStoreIsRejectedWithoutRunningRepair() async throws {
        let (_, _, context) = try stack()
        let (_, foreignStore, _) = try stack()
        XCTAssertThrowsError(try FoodStoreMigration.runIfNeeded(in: context, store: foreignStore) {
            XCTFail("A marker must never be applied to a different coordinator's store")
        })
    }

    private func stack(url: URL? = nil) throws -> (NSPersistentStoreCoordinator, NSPersistentStore, NSManagedObjectContext) {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model())
        let store = try coordinator.addPersistentStore(ofType: url == nil ? NSInMemoryStoreType : NSSQLiteStoreType,
                                                       configurationName: nil, at: url, options: nil)
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.undoManager = nil
        return (coordinator, store, context)
    }

    private func model() -> NSManagedObjectModel {
        let entity = NSEntityDescription()
        entity.name = "Meal"
        entity.managedObjectClassName = "NSManagedObject"
        entity.properties = [("name", NSAttributeType.stringAttributeType, false),
                             ("id", .UUIDAttributeType, true), ("photo", .binaryDataAttributeType, true)].map {
            let attribute = NSAttributeDescription()
            attribute.name = $0.0
            attribute.attributeType = $0.1
            attribute.isOptional = $0.2
            return attribute
        }
        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // Failure injection is confined to the test's main/context queue.
    private final class FailingMetadataCoordinator: NSPersistentStoreCoordinator, @unchecked Sendable {
        var failMetadataSave = false

        override func execute(_ request: NSPersistentStoreRequest, with context: NSManagedObjectContext) throws -> Any {
            if failMetadataSave, request is NSSaveChangesRequest { throw TestError.metadataSaveFailed }
            return try super.execute(request, with: context)
        }
    }
}

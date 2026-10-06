import Combine
import CoreData
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
#if canImport(FoodLogPerformance)
@testable import FoodLogPerformance
#else
@testable import FoodLog
#endif

final class FoodPhotoThumbnailTests: XCTestCase {
    func testJournalPreviewIsSizedForAspectFillRatherThanFullJPEG() throws {
        let photo = try jpeg(width: 1_600, height: 1_200)
        let image = try XCTUnwrap(FoodPhotoDownsampling.image(data: photo, width: 126, height: 126))
        XCTAssertEqual(image.width, 168)
        XCTAssertEqual(image.height, 126)
        XCTAssertLessThan(image.bytesPerRow * image.height, 100_000)
    }

    func testEditorPreviewRetainsEnoughPixelsWithoutFullResolution() throws {
        let image = try XCTUnwrap(FoodPhotoDownsampling.image(data: jpeg(width: 1_600, height: 1_200),
                                                             width: 1_020, height: 570))
        XCTAssertEqual(image.width, 1_020)
        XCTAssertEqual(image.height, 765)
    }

    func testEXIFRotationIsAppliedBeforeSizingForAspectFill() throws {
        let image = try XCTUnwrap(FoodPhotoDownsampling.image(data: jpeg(width: 1_200, height: 1_600, orientation: 6),
                                                             width: 1_020, height: 570))
        XCTAssertEqual(image.width, 1_020)
        XCTAssertEqual(image.height, 765)
    }

    func testInvalidDataFallsBackAndSmallPhotosAreNotUpscaled() throws {
        XCTAssertNil(FoodPhotoDownsampling.image(data: Data(), width: 126, height: 126))
        XCTAssertNil(FoodPhotoDownsampling.image(data: Data([1, 2, 3]), width: 126, height: 126))
        let image = try XCTUnwrap(FoodPhotoDownsampling.image(data: jpeg(width: 40, height: 30),
                                                             width: 1_020, height: 570))
        XCTAssertEqual(image.width, 40)
        XCTAssertEqual(image.height, 30)
    }

    func testExtremeAspectRatiosAndRequestSizesAreBounded() throws {
        let key = FoodPhotoThumbnailKey(version: UUID(), width: .infinity, height: 100_000)
        XCTAssertEqual(key.width, 1)
        XCTAssertEqual(key.height, 2_048)
        let image = try XCTUnwrap(FoodPhotoDownsampling.image(data: jpeg(width: 3_000, height: 30),
                                                             width: 126, height: 126))
        XCTAssertLessThanOrEqual(max(image.width, image.height), 2_048)
    }

    @MainActor
    func testCacheHitDoesNotReadStoredPhotoAgain() async throws {
        let cache = FoodPhotoThumbnailCache()
        let data = try jpeg(width: 1_600, height: 1_200)
        let key = FoodPhotoThumbnailKey(version: UUID(), width: 126, height: 126)
        var loads = 0
        let first = await cache.thumbnail(for: key) { loads += 1; XCTAssertTrue(Thread.isMainThread); return data }
        let second = await cache.thumbnail(for: key) { loads += 1; return nil }
        XCTAssertEqual(loads, 1)
        let firstImage = try XCTUnwrap(first)
        XCTAssertTrue(firstImage === second)
    }

    @MainActor
    func testDifferentPreviewSizesAndPhotoVersionsDoNotReuseWrongImage() async throws {
        let cache = FoodPhotoThumbnailCache()
        let data = try jpeg(width: 1_600, height: 1_200)
        let version = UUID()
        var loads = 0
        let small = await cache.thumbnail(for: .init(version: version, width: 126, height: 126)) {
            loads += 1; return data
        }
        let large = await cache.thumbnail(for: .init(version: version, width: 1_020, height: 570)) {
            loads += 1; return data
        }
        let replacement = await cache.thumbnail(for: .init(version: UUID(), width: 126, height: 126)) {
            loads += 1; return nil
        }
        XCTAssertEqual(loads, 3)
        XCTAssertEqual(small?.width, 168)
        XCTAssertEqual(large?.width, 1_020)
        XCTAssertNil(replacement)
    }

    @MainActor
    func testAbsentAndCorruptPhotosAreCachedWithoutRepeatedReads() async {
        let cache = FoodPhotoThumbnailCache()
        for data in [nil, Data([1, 2, 3])] as [Data?] {
            let key = FoodPhotoThumbnailKey(version: UUID(), width: 126, height: 126)
            var loads = 0
            for _ in 0..<5 {
                let image = await cache.thumbnail(for: key) { loads += 1; return data }
                XCTAssertNil(image)
            }
            XCTAssertEqual(loads, 1)
        }
    }

    @MainActor
    func testSimultaneousRequestsReadAndDecodeOnlyOnce() async throws {
        let cache = FoodPhotoThumbnailCache()
        let gate = PhotoLoadGate(data: try jpeg(width: 1_600, height: 1_200))
        let key = FoodPhotoThumbnailKey(version: UUID(), width: 126, height: 126)
        let first = Task { await cache.thumbnail(for: key) { await gate.load() } }
        await gate.waitUntilStarted()
        let second = Task { await cache.thumbnail(for: key) { XCTFail("A shared request must not read twice"); return nil } }
        // Awaiting the actor's next request gives the second consumer a chance
        // to join the pending work, without relying on a timing threshold.
        _ = await cache.thumbnail(for: .init(version: UUID(), width: 1, height: 1)) { nil }
        gate.resume()
        let firstImage = await first.value
        let secondImage = await second.value
        XCTAssertEqual(gate.loads, 1)
        XCTAssertNotNil(firstImage)
        XCTAssertTrue(firstImage === secondImage)
    }

    @MainActor
    func testMemoryPurgeAllowsFreshRead() async throws {
        let cache = FoodPhotoThumbnailCache()
        let data = try jpeg(width: 1_600, height: 1_200)
        let key = FoodPhotoThumbnailKey(version: UUID(), width: 126, height: 126)
        var loads = 0
        _ = await cache.thumbnail(for: key) { loads += 1; return data }
        await cache.removeAll()
        _ = await cache.thumbnail(for: key) { loads += 1; return data }
        XCTAssertEqual(loads, 2)
    }

    @MainActor
    func testPurgeDuringPendingLoadCannotRepopulateOldCache() async throws {
        let cache = FoodPhotoThumbnailCache()
        let gate = PhotoLoadGate(data: try jpeg(width: 1_600, height: 1_200))
        let key = FoodPhotoThumbnailKey(version: UUID(), width: 126, height: 126)
        let pending = Task { await cache.thumbnail(for: key) { await gate.load() } }
        await gate.waitUntilStarted()
        await cache.removeAll()
        gate.resume()
        let stale = await pending.value
        XCTAssertNil(stale)
        var freshReads = 0
        let fresh = await cache.thumbnail(for: key) { freshReads += 1; return nil }
        XCTAssertNil(fresh)
        XCTAssertEqual(freshReads, 1)
    }

    @MainActor
    func testVersionChangesOnlyForPhotoEditsAndNotOtherMealFields() throws {
        let context = try context()
        let versions = FoodPhotoVersions()
        let meal = NSEntityDescription.insertNewObject(forEntityName: "FoodEntry", into: context)
        let other = NSEntityDescription.insertNewObject(forEntityName: "FoodEntry", into: context)
        meal.setValue(Data([1]), forKey: "photoData")
        try context.save()
        versions.observe(context)
        let original = versions.version(for: meal)
        let otherVersion = versions.version(for: other)
        meal.setValue("Edited note", forKey: "note")
        context.processPendingChanges()
        XCTAssertEqual(versions.version(for: meal), original)
        XCTAssertEqual(versions.revision, 0)

        meal.setValue(Data([2]), forKey: "photoData")
        context.processPendingChanges()
        let replaced = versions.version(for: meal)
        XCTAssertNotEqual(replaced, original)
        XCTAssertEqual(versions.version(for: other), otherVersion)
        meal.setValue(nil, forKey: "photoData")
        context.processPendingChanges()
        XCTAssertNotEqual(versions.version(for: meal), replaced)
    }

    @MainActor
    func testRollbackRefreshDeletionAndResetInvalidatePhotoVersions() throws {
        let context = try context()
        let versions = FoodPhotoVersions()
        let meal = NSEntityDescription.insertNewObject(forEntityName: "FoodEntry", into: context)
        meal.setValue(Data([1]), forKey: "photoData")
        try context.save()
        versions.observe(context)
        let original = versions.version(for: meal)
        meal.setValue(Data([2]), forKey: "photoData")
        context.processPendingChanges()
        let edited = versions.version(for: meal)
        context.rollback()
        let restored = versions.version(for: meal)
        XCTAssertNotEqual(restored, edited)
        XCTAssertNotEqual(restored, original)
        context.refresh(meal, mergeChanges: false)
        context.processPendingChanges()
        let refreshed = versions.version(for: meal)
        XCTAssertNotEqual(refreshed, restored)
        context.delete(meal)
        context.processPendingChanges()
        XCTAssertNotEqual(versions.version(for: meal), refreshed)
        let revision = versions.revision
        context.reset()
        XCTAssertGreaterThan(versions.revision, revision)
    }

    @MainActor
    func testMergedPhotoUpdatesInvalidateVersionAndExposeNewData() throws {
        let context = try context()
        let versions = FoodPhotoVersions()
        let meal = NSEntityDescription.insertNewObject(forEntityName: "FoodEntry", into: context)
        meal.setValue(Data([1]), forKey: "photoData")
        try context.save()
        versions.observe(context)
        let original = versions.version(for: meal)
        let other = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        other.persistentStoreCoordinator = context.persistentStoreCoordinator
        let updated = try other.existingObject(with: meal.objectID)
        updated.setValue(Data([2]), forKey: "photoData")
        // The test uses two main-queue contexts to exercise the actual merge
        // without passing live managed objects across a thread boundary.
        var saveNotification: Notification?
        let observer = NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave,
                                                             object: other).sink {
            saveNotification = $0
        }
        defer { observer.cancel() }
        try other.save()
        context.mergeChanges(fromContextDidSave: try XCTUnwrap(saveNotification))
        context.processPendingChanges()
        XCTAssertEqual(meal.value(forKey: "photoData") as? Data, Data([2]))
        XCTAssertNotEqual(versions.version(for: meal), original)
    }

    @MainActor
    func testSynchronousLookupReturnsOnlyCachedPreviewsWithoutReading() async throws {
        let cache = FoodPhotoThumbnailCache()
        let key = FoodPhotoThumbnailKey(version: UUID(), width: 126, height: 126)
        XCTAssertNil(cache.cachedImage(for: key))
        let loaded = await cache.thumbnail(for: key) { try? self.jpeg(width: 1_600, height: 1_200) }
        let image = try XCTUnwrap(loaded)
        XCTAssertTrue(cache.cachedImage(for: key) === image)
        XCTAssertNil(cache.cachedImage(for: .init(version: key.version, width: 1_020, height: 570)))
        await cache.removeAll()
        XCTAssertNil(cache.cachedImage(for: key))
    }

    @MainActor
    func testPhotoIDQueryFindsOnlyPhotosIncludingUnsavedChangesWithoutLoadingThem() throws {
        let context = try context()
        let withPhoto = NSEntityDescription.insertNewObject(forEntityName: "FoodEntry", into: context)
        withPhoto.setValue(try jpeg(width: 64, height: 64), forKey: "photoData")
        let withoutPhoto = NSEntityDescription.insertNewObject(forEntityName: "FoodEntry", into: context)
        withoutPhoto.setValue("No photo", forKey: "note")
        try context.save()
        context.refresh(withPhoto, mergeChanges: false)
        XCTAssertEqual(FoodEntryPhotoData.entryIDsWithPhotos(in: context), [withPhoto.objectID])
        XCTAssertTrue(withPhoto.isFault, "The ID query must not load photo bytes")

        withoutPhoto.setValue(Data([1]), forKey: "photoData")
        withPhoto.setValue(nil, forKey: "photoData")
        let unsaved = NSEntityDescription.insertNewObject(forEntityName: "FoodEntry", into: context)
        unsaved.setValue(Data([2]), forKey: "photoData")
        XCTAssertEqual(FoodEntryPhotoData.entryIDsWithPhotos(in: context), [withoutPhoto.objectID, unsaved.objectID])
        context.rollback()
    }

    @MainActor
    func testReadingCommittedPhotoLeavesJournalObjectFaulted() async throws {
        let context = try context()
        let meal = NSEntityDescription.insertNewObject(forEntityName: "FoodEntry", into: context)
        let photo = try jpeg(width: 1_600, height: 1_200)
        meal.setValue(photo, forKey: "photoData")
        try context.save()
        context.refresh(meal, mergeChanges: false)
        XCTAssertTrue(meal.isFault)
        let loaded = await FoodEntryPhotoData.read(from: meal)
        XCTAssertEqual(loaded, photo)
        XCTAssertTrue(meal.isFault, "Reading a preview must not load the original photo into the journal object")
    }

    @MainActor
    func testReadingUnsavedPhotoUsesOwningContextAndDoesNotPersistIt() async throws {
        let context = try context()
        let meal = NSEntityDescription.insertNewObject(forEntityName: "FoodEntry", into: context)
        meal.setValue(Data([1]), forKey: "photoData")
        let unsaved = await FoodEntryPhotoData.read(from: meal)
        XCTAssertEqual(unsaved, Data([1]))
        XCTAssertTrue(meal.isInserted)
        try context.save()
        meal.setValue(Data([2]), forKey: "photoData")
        let edited = await FoodEntryPhotoData.read(from: meal)
        XCTAssertEqual(edited, Data([2]))
        meal.setValue(nil, forKey: "photoData")
        let removed = await FoodEntryPhotoData.read(from: meal)
        XCTAssertNil(removed)
        XCTAssertTrue(context.hasChanges)
        context.rollback()
        let restored = await FoodEntryPhotoData.read(from: meal)
        XCTAssertEqual(restored, Data([1]))
        context.delete(meal)
        let deleted = await FoodEntryPhotoData.read(from: meal)
        XCTAssertNil(deleted)
    }

    private func jpeg(width: Int, height: Int, orientation: Int = 1) throws -> Data {
        let drawing = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        drawing.setFillColor(CGColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1))
        drawing.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(drawing.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image,
                                  [kCGImagePropertyOrientation: orientation,
                                   kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func context() throws -> NSManagedObjectContext {
        let entity = NSEntityDescription()
        entity.name = "FoodEntry"
        entity.managedObjectClassName = "NSManagedObject"
        entity.properties = [("photoData", NSAttributeType.binaryDataAttributeType),
                             ("note", NSAttributeType.stringAttributeType)].map { name, type in
            let attribute = NSAttributeDescription()
            attribute.name = name
            attribute.attributeType = type
            attribute.isOptional = true
            return attribute
        }
        let model = NSManagedObjectModel()
        model.entities = [entity]
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }
}

@MainActor
private final class PhotoLoadGate {
    let data: Data
    private(set) var loads = 0
    private var continuation: CheckedContinuation<Data?, Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?

    init(data: Data) { self.data = data }
    func load() async -> Data? {
        loads += 1
        return await withCheckedContinuation {
            continuation = $0
            startContinuation?.resume()
            startContinuation = nil
        }
    }
    func waitUntilStarted() async {
        if loads > 0 { return }
        await withCheckedContinuation { startContinuation = $0 }
    }
    func resume() { continuation?.resume(returning: data); continuation = nil }
}

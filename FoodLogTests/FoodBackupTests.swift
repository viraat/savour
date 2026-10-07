import CoreData
import CryptoKit
import Foundation
import XCTest
import ZIPFoundation
@testable import FoodLogBackup

/// Runs on macOS against the app's real compiled model and private SQLite stores.
/// No app, simulator, user journal, or notification permission is involved.
@MainActor
final class FoodBackupTests: XCTestCase {
    // Report Swift errors with the test that encountered them.
    private func assertNoError(_ operation: () async throws -> Void) async {
        do { try await operation() }
        catch { XCTFail("Unexpected backup error: \(error)") }
    }

    private struct Fixture {
        let directory: URL
        let coordinator: NSPersistentStoreCoordinator
        let context: NSManagedObjectContext
        func cleanup() {
            context.reset()
            for store in coordinator.persistentStores { try? coordinator.remove(store) }
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func fixture(version: String? = nil, modify: ((NSManagedObjectModel) -> Void)? = nil) throws -> Fixture {
        let momd = try XCTUnwrap(SavourBackupExporter.modelBundle.url(forResource: "FoodLog", withExtension: "momd"))
        let url = version.map { momd.appendingPathComponent("\($0).mom") } ?? momd
        let loaded = try XCTUnwrap(NSManagedObjectModel(contentsOf: url))
        let model = try XCTUnwrap(loaded.copy() as? NSManagedObjectModel)
        // Export intentionally depends on the schema, not generated app classes.
        for entity in model.entities { entity.managedObjectClassName = "NSManagedObject" }
        modify?(model)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SavourBackupTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        do {
            try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil,
                at: directory.appendingPathComponent("source.sqlite"), options: [NSPersistentHistoryTrackingKey: true])
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return Fixture(directory: directory, coordinator: coordinator, context: context)
    }

    private func insert(_ entity: String, into fixture: Fixture, values: [String: Any]) -> NSManagedObject {
        let object = NSEntityDescription.insertNewObject(forEntityName: entity, into: fixture.context)
        for (key, value) in values { object.setValue(value, forKey: key) }
        return object
    }

    private func export(_ fixture: Fixture) async throws -> SavourBackupFile {
        try await SavourBackupExporter.export(from: fixture.coordinator, temporaryRoot: fixture.directory,
                                              appVersion: "0.5.3", appBuild: "8")
    }

    private func unpack(_ file: SavourBackupFile, into fixture: Fixture) throws -> (SavourBackupManifest, URL) {
        let folder = fixture.directory.appendingPathComponent("unpacked-\(UUID().uuidString)")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", file.url.path, folder.path]
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "ZIP extraction failed")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
        let manifestURL = try XCTUnwrap(files.allObjects.compactMap { $0 as? URL }.first { $0.lastPathComponent == "manifest.json" })
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return (try decoder.decode(SavourBackupManifest.self, from: Data(contentsOf: manifestURL)), manifestURL.deletingLastPathComponent())
    }

    private func entity(_ name: String, in manifest: SavourBackupManifest) throws -> SavourBackupManifest.Entity {
        try XCTUnwrap(manifest.entities.first { $0.name == name })
    }

    private func objects(_ name: String, in fixture: Fixture) throws -> [NSManagedObject] {
        fixture.context.reset()
        return try fixture.context.fetch(NSFetchRequest<NSManagedObject>(entityName: name))
    }

    private func preview(_ file: SavourBackupFile, into fixture: Fixture) async throws -> SavourRestorePreview {
        try await SavourBackupRestorer.preview(url: file.url, coordinator: fixture.coordinator, temporaryRoot: fixture.directory)
    }

    private func modifiedArchive(_ file: SavourBackupFile, fixture: Fixture,
                                 modify: (inout [String: Any]) throws -> Void = { _ in },
                                 extra: [(String, Data, Entry.EntryType)] = [], omit: Set<String> = []) throws -> URL {
        let (_, payload) = try unpack(file, into: fixture)
        let manifestURL = payload.appendingPathComponent("manifest.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        try modify(&json)
        try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]).write(to: manifestURL)
        let url = fixture.directory.appendingPathComponent("modified-\(UUID().uuidString).zip")
        let archive = try Archive(url: url, accessMode: .create)
        let files = try XCTUnwrap(FileManager.default.enumerator(at: payload, includingPropertiesForKeys: [.isRegularFileKey]))
        for case let source as URL in files {
            guard try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let path = String(source.path.dropFirst(payload.path.count + 1))
            if !omit.contains(path) { try archive.addEntry(with: "SavourBackup-v1/" + path, fileURL: source) }
        }
        for (path, bytes, type) in extra {
            try archive.addEntry(with: path, type: type, uncompressedSize: Int64(bytes.count)) { offset, count in
                bytes.subdata(in: Int(offset)..<min(Int(offset) + count, bytes.count))
            }
        }
        return url
    }

    private func expectRejected(_ url: URL, fixture: Fixture) async {
        do {
            let value = try await SavourBackupRestorer.preview(url: url, coordinator: fixture.coordinator, temporaryRoot: fixture.directory)
            value.cleanup()
            XCTFail("Invalid backup was accepted")
        } catch { /* Expected: validation never writes to the journal. */ }
        XCTAssertEqual(try objects("FoodEntry", in: fixture).count, 0)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).contains { $0.hasPrefix("SavourBackupRestore-") })
    }

    func testRestoreRoundTripPreservesFullGraphPhotosCoordinatesDatesAndRelaunch() async {
        await assertNoError {
            let source = try fixture(); defer { source.cleanup() }
            let target = try fixture(); defer { target.cleanup() }
            let id = UUID(), companionID = UUID(), fastID = UUID()
            let date = Date(timeIntervalSinceReferenceDate: 812_345_678.1234567)
            let bytes = Data([0xFF, 0xD8, 0xFF, 0, 255, 5, 10])
            let meal = insert("FoodEntry", into: source, values: ["id": id, "date": date, "createdAt": date,
                "food": "Rice, \"tofu\"\n🥑", "note": "  Notes\n東京  ", "people": "A, B", "mealType": "Dinner",
                "place": "London, UK", "placeCity": "London", "hasPlaceCoordinates": true,
                "placeLatitude": 51.23456789, "placeLongitude": -0.1234567, "photoData": bytes])
            _ = insert("FoodEntryCompanion", into: source, values: ["id": companionID, "name": "A, B", "sortIndex": 0, "entry": meal])
            _ = insert("FastSession", into: source, values: ["id": fastID, "startDate": date, "createdAt": date, "startEntryID": id])
            _ = insert("FastSession", into: target, values: ["id": fastID, "startDate": date, "createdAt": date, "startEntryID": id])
            try source.context.save()
            try target.context.save()
            let file = try await export(source); defer { file.cleanup() }
            let preview = try await preview(file, into: target); defer { preview.cleanup() }
            XCTAssertEqual(preview.counts.added, ["FoodEntry": 1, "FoodEntryCompanion": 1])
            XCTAssertEqual(preview.counts.newPhotos, 1)
            XCTAssertEqual(try objects("FoodEntry", in: target).count, 0, "Preview must not create entries")
            let result = try await SavourBackupRestorer.restore(preview, coordinator: target.coordinator)
            XCTAssertEqual(result.totalAdded, 2)
            target.context.reset()
            let store = try XCTUnwrap(target.coordinator.persistentStores.first)
            let storeURL = try XCTUnwrap(store.url)
            try target.coordinator.remove(store)
            try target.coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL)
            let restored = try XCTUnwrap(objects("FoodEntry", in: target).first)
            for key in ["id", "date", "createdAt", "food", "note", "people", "mealType", "place", "placeCity", "hasPlaceCoordinates", "placeLatitude", "placeLongitude", "photoData"] {
                XCTAssertEqual(restored.value(forKey: key) as? NSObject, meal.value(forKey: key) as? NSObject, key)
            }
            XCTAssertEqual(restored.value(forKey: "photoData") as? Data, bytes)
            let companion = try XCTUnwrap(objects("FoodEntryCompanion", in: target).first)
            XCTAssertEqual(companion.value(forKey: "id") as? UUID, companionID)
            XCTAssertEqual((companion.value(forKey: "entry") as? NSManagedObject)?.value(forKey: "id") as? UUID, id)
            let fast = try XCTUnwrap(objects("FastSession", in: target).first)
            XCTAssertEqual(fast.value(forKey: "id") as? UUID, fastID)
            XCTAssertNil(fast.value(forKey: "endDate"))
            XCTAssertNil(fast.value(forKey: "targetDuration"))
        }
    }

    func testRepeatedRestoreSkipsIdenticalRecordsIncludingMissingAndDuplicateUUIDs() async {
        await assertNoError {
            let source = try fixture(); defer { source.cleanup() }
            let target = try fixture(); defer { target.cleanup() }
            let duplicate = UUID()
            for (food, id) in [("Rice", duplicate as UUID?), ("Tofu", duplicate), ("Tea", nil)] {
                _ = insert("FoodEntry", into: source, values: ["food": food, "id": id as Any? ?? NSNull()])
            }
            _ = insert("FoodEntryCompanion", into: source, values: ["name": "Orphan"])
            try source.context.save()
            let file = try await export(source); defer { file.cleanup() }
            let first = try await preview(file, into: target); defer { first.cleanup() }
            let firstResult = try await SavourBackupRestorer.restore(first, coordinator: target.coordinator)
            XCTAssertEqual(firstResult.totalAdded, 4)
            let second = try await preview(file, into: target); defer { second.cleanup() }
            XCTAssertEqual(second.counts.totalIdentical, 4)
            XCTAssertEqual(second.counts.totalAdded, 0)
            let secondResult = try await SavourBackupRestorer.restore(second, coordinator: target.coordinator)
            XCTAssertEqual(secondResult.totalAdded, 0)
            XCTAssertEqual(try objects("FoodEntry", in: target).count, 3)
        }
    }

    func testConflictSkipsEntireMealGraphWithoutChangingExistingPeopleOrPhotos() async {
        await assertNoError {
            let source = try fixture(); defer { source.cleanup() }
            let target = try fixture(); defer { target.cleanup() }
            let id = UUID()
            let meal = insert("FoodEntry", into: source, values: ["id": id, "food": "Older food", "photoData": Data([1, 2])])
            _ = insert("FoodEntryCompanion", into: source, values: ["id": UUID(), "name": "Older person", "entry": meal])
            _ = insert("FoodEntry", into: source, values: ["id": UUID(), "food": "New meal"])
            try source.context.save()
            _ = insert("FoodEntry", into: target, values: ["id": id, "food": "Edited food", "photoData": Data([3, 4])])
            try target.context.save()
            let file = try await export(source); defer { file.cleanup() }
            let preview = try await preview(file, into: target); defer { preview.cleanup() }
            XCTAssertEqual(preview.counts.conflicts, ["FoodEntry": 1, "FoodEntryCompanion": 1])
            XCTAssertEqual(preview.counts.totalAdded, 1)
            _ = try await SavourBackupRestorer.restore(preview, coordinator: target.coordinator)
            let meals = try objects("FoodEntry", in: target)
            let existing = try XCTUnwrap(meals.first { $0.value(forKey: "id") as? UUID == id })
            XCTAssertEqual(existing.value(forKey: "food") as? String, "Edited food")
            XCTAssertEqual(existing.value(forKey: "photoData") as? Data, Data([3, 4]))
            XCTAssertEqual(try objects("FoodEntryCompanion", in: target).count, 0)
            XCTAssertEqual(meals.count, 2)
        }
    }

    func testRestoreRechecksJournalChangedAfterPreview() async {
        await assertNoError {
            let source = try fixture(); defer { source.cleanup() }
            let target = try fixture(); defer { target.cleanup() }
            let id = UUID()
            _ = insert("FoodEntry", into: source, values: ["id": id, "food": "Rice"])
            try source.context.save()
            let file = try await export(source); defer { file.cleanup() }
            let preview = try await preview(file, into: target); defer { preview.cleanup() }
            XCTAssertEqual(preview.counts.totalAdded, 1)
            _ = insert("FoodEntry", into: target, values: ["id": id, "food": "Newer rice"])
            try target.context.save()
            let result = try await SavourBackupRestorer.restore(preview, coordinator: target.coordinator)
            XCTAssertEqual(result.totalAdded, 0)
            XCTAssertEqual(result.totalConflicts, 1)
            XCTAssertEqual(try objects("FoodEntry", in: target).first?.value(forKey: "food") as? String, "Newer rice")
        }
    }

    func testBackupsFromEveryOlderModelRestoreIntoCurrentModel() async {
        await assertNoError {
            for version in ["FoodLog", "FoodLogV2", "FoodLogV3", "FoodLogV4", "FoodLogV5"] {
                let source = try fixture(version: version); defer { source.cleanup() }
                let target = try fixture(); defer { target.cleanup() }
                let id = UUID()
                _ = insert("FoodEntry", into: source, values: ["id": id, "food": "Legacy rice", "date": Date(timeIntervalSinceReferenceDate: -12.1234567), "people": "Ana, Dev"])
                try source.context.save()
                let file = try await export(source); defer { file.cleanup() }
                let preview = try await preview(file, into: target); defer { preview.cleanup() }
                let result = try await SavourBackupRestorer.restore(preview, coordinator: target.coordinator)
                XCTAssertEqual(result.totalAdded, 1, version)
                let entry = try XCTUnwrap(objects("FoodEntry", in: target).first)
                XCTAssertEqual(entry.value(forKey: "id") as? UUID, id, version)
                XCTAssertEqual(entry.value(forKey: "people") as? String, "Ana, Dev", version)
            }
        }
    }

    func testRestoreRollsBackAllObjectsWhenCoreDataValidationFails() async {
        await assertNoError {
            let source = try fixture(); defer { source.cleanup() }
            let target = try fixture(modify: { model in
                let food = model.entitiesByName["FoodEntry"]!.attributesByName["food"]!
                food.setValidationPredicates([NSPredicate(format: "SELF != %@", "Rejected")], withValidationWarnings: ["Test rejection"])
            }); defer { target.cleanup() }
            for food in ["Accepted", "Rejected"] { _ = insert("FoodEntry", into: source, values: ["id": UUID(), "food": food]) }
            try source.context.save()
            let file = try await export(source); defer { file.cleanup() }
            let preview = try await preview(file, into: target); defer { preview.cleanup() }
            do { _ = try await SavourBackupRestorer.restore(preview, coordinator: target.coordinator); XCTFail("Validation should fail") }
            catch { XCTAssertEqual(try objects("FoodEntry", in: target).count, 0) }
        }
    }

    func testUnsafePathsSymlinksUnexpectedAndDuplicateFilesAreRejected() async {
        await assertNoError {
            let source = try fixture(); defer { source.cleanup() }
            let target = try fixture(); defer { target.cleanup() }
            let file = try await export(source); defer { file.cleanup() }
            for (path, type) in [("../outside", Entry.EntryType.file), ("/absolute", .file), ("SavourBackup-v1/link", .symlink), ("SavourBackup-v1/extra", .file), ("SavourBackup-v1/manifest.json", .file)] {
                let url = try modifiedArchive(file, fixture: source, extra: [(path, Data("test".utf8), type)])
                await expectRejected(url, fixture: target)
            }
        }
    }

    func testUnsupportedVersionWrongTypesAndIncompleteObjectsAreRejected() async {
        await assertNoError {
            let source = try fixture(); defer { source.cleanup() }
            let target = try fixture(); defer { target.cleanup() }
            _ = insert("FoodEntry", into: source, values: ["id": UUID(), "food": "Rice"])
            try source.context.save()
            let file = try await export(source); defer { file.cleanup() }
            let unknownVersion = try modifiedArchive(file, fixture: source) { $0["version"] = 999 }
            await expectRejected(unknownVersion, fixture: target)
            for change in ["wrongType", "missingField", "duplicateObject", "danglingRelationship", "unknownEntity"] {
                let url = try modifiedArchive(file, fixture: source) { json in
                    var entities = json["entities"] as! [[String: Any]]
                    let index = entities.firstIndex { $0["name"] as? String == "FoodEntry" }!
                    var objects = entities[index]["objects"] as! [[String: Any]]
                    if change == "unknownEntity" { entities[index]["name"] = "Unknown" }
                    else if change == "duplicateObject" { objects.append(objects[0]) }
                    else if change == "danglingRelationship" { objects[0]["relationships"] = ["companions": ["missing"]] }
                    else {
                        var attrs = objects[0]["attributes"] as! [String: Any]
                        if change == "wrongType" { attrs["id"] = ["type": "string", "value": "not a UUID"] }
                        else { attrs.removeValue(forKey: "food") }
                        objects[0]["attributes"] = attrs
                    }
                    entities[index]["objects"] = objects
                    json["entities"] = entities
                }
                await expectRejected(url, fixture: target)
            }
        }
    }

    func testMissingPhotosAndChecksumMismatchAreRejected() async {
        await assertNoError {
            let source = try fixture(); defer { source.cleanup() }
            let target = try fixture(); defer { target.cleanup() }
            _ = insert("FoodEntry", into: source, values: ["id": UUID(), "food": "Rice", "photoData": Data([1, 2, 3])])
            try source.context.save()
            let file = try await export(source); defer { file.cleanup() }
            let (manifest, _) = try unpack(file, into: source)
            guard case let .binary(photo) = try entity("FoodEntry", in: manifest).objects[0].attributes["photoData"] else { return XCTFail("Missing photo") }
            await expectRejected(try modifiedArchive(file, fixture: source, omit: [photo.path]), fixture: target)
            let badHash = try modifiedArchive(file, fixture: source) { json in
                var entities = json["entities"] as! [[String: Any]]
                let index = entities.firstIndex { $0["name"] as? String == "FoodEntry" }!
                var objects = entities[index]["objects"] as! [[String: Any]]
                var attrs = objects[0]["attributes"] as! [String: Any]
                var ref = attrs["photoData"] as! [String: Any]
                var value = ref["value"] as! [String: Any]
                value["sha256"] = String(repeating: "0", count: 64)
                ref["value"] = value; attrs["photoData"] = ref; objects[0]["attributes"] = attrs
                entities[index]["objects"] = objects; json["entities"] = entities
            }
            await expectRejected(badHash, fixture: target)
        }
    }

    func testCancelledRestoreDoesNotWriteAndCancelledPreviewDoesNotStageFiles() async {
        await assertNoError {
            let source = try fixture(); defer { source.cleanup() }
            let target = try fixture(); defer { target.cleanup() }
            _ = insert("FoodEntry", into: source, values: ["id": UUID(), "food": "Rice"])
            try source.context.save()
            let file = try await export(source); defer { file.cleanup() }
            let preview = try await preview(file, into: target); defer { preview.cleanup() }
            let restore = Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                return try await SavourBackupRestorer.restore(preview, coordinator: target.coordinator)
            }
            do { _ = try await restore.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("\(error)") }
            XCTAssertEqual(try objects("FoodEntry", in: target).count, 0)
            let reading = Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                return try await SavourBackupRestorer.preview(url: file.url, coordinator: target.coordinator, temporaryRoot: target.directory)
            }
            do { _ = try await reading.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("\(error)") }
        }
    }

    func testDamagedZIPCRCAndOversizedAttachmentReferencesAreRejected() async {
        await assertNoError {
            let source = try fixture(); defer { source.cleanup() }
            let target = try fixture(); defer { target.cleanup() }
            let bytes = Data((0..<128).map { UInt8(($0 * 7) % 256) })
            _ = insert("FoodEntry", into: source, values: ["id": UUID(), "food": "Rice", "photoData": bytes])
            try source.context.save()
            let file = try await export(source); defer { file.cleanup() }
            let damaged = try modifiedArchive(file, fixture: source)
            var archive = try Data(contentsOf: damaged)
            let location = try XCTUnwrap(archive.range(of: bytes))
            archive[location.lowerBound] ^= 0xFF
            try archive.write(to: damaged)
            await expectRejected(damaged, fixture: target)
            let oversized = try modifiedArchive(file, fixture: source) { json in
                var entities = json["entities"] as! [[String: Any]]
                let index = entities.firstIndex { $0["name"] as? String == "FoodEntry" }!
                var objects = entities[index]["objects"] as! [[String: Any]]
                var attrs = objects[0]["attributes"] as! [String: Any]
                var reference = attrs["photoData"] as! [String: Any]
                var value = reference["value"] as! [String: Any]
                value["byteCount"] = SavourBackupLimits.blobBytes + 1
                reference["value"] = value; attrs["photoData"] = reference; objects[0]["attributes"] = attrs
                entities[index]["objects"] = objects; json["entities"] = entities
            }
            await expectRejected(oversized, fixture: target)
        }
    }

    func testTruncatedSchemaCannotMasqueradeAsAnOlderModel() async {
        await assertNoError {
            let source = try fixture(); defer { source.cleanup() }
            let target = try fixture(); defer { target.cleanup() }
            _ = insert("FoodEntry", into: source, values: ["id": UUID(), "food": "Rice"])
            try source.context.save()
            let file = try await export(source); defer { file.cleanup() }
            let malformed = try modifiedArchive(file, fixture: source) { json in
                var entities = json["entities"] as! [[String: Any]]
                let index = entities.firstIndex { $0["name"] as? String == "FoodEntry" }!
                var attrs = entities[index]["attributes"] as! [String: Any]
                attrs.removeValue(forKey: "food")
                entities[index]["attributes"] = attrs
                var objects = entities[index]["objects"] as! [[String: Any]]
                var values = objects[0]["attributes"] as! [String: Any]
                values.removeValue(forKey: "food")
                objects[0]["attributes"] = values; entities[index]["objects"] = objects; json["entities"] = entities
            }
            await expectRejected(malformed, fixture: target)
        }
    }

    func testOversizedPhotoExportFailsInsteadOfCreatingAnUnrestorableBackup() async {
        await assertNoError {
            let source = try fixture(); defer { source.cleanup() }
            _ = insert("FoodEntry", into: source, values: ["id": UUID(), "photoData": Data(repeating: 0xAB, count: SavourBackupLimits.blobBytes + 1)])
            try source.context.save()
            do { let file = try await export(source); file.cleanup(); XCTFail("Oversized photo should fail") }
            catch SavourBackupError.tooLarge { }
            catch { XCTFail("Unexpected error: \(error)") }
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: source.directory.path).contains { $0.hasPrefix("SavourBackupExport-") })
            XCTAssertEqual(try objects("FoodEntry", in: source).count, 1)
        }
    }

    func testOrderedRestoreRetainsOrderAndChangedOrderIsAConflict() async {
        await assertNoError {
            let modify: (NSManagedObjectModel) -> Void = { model in model.entitiesByName["FoodEntry"]!.relationshipsByName["companions"]!.isOrdered = true }
            let source = try fixture(modify: modify); defer { source.cleanup() }
            let target = try fixture(modify: modify); defer { target.cleanup() }
            let meal = insert("FoodEntry", into: source, values: ["id": UUID(), "food": "Rice"])
            let first = insert("FoodEntryCompanion", into: source, values: ["id": UUID(), "name": "First"])
            let second = insert("FoodEntryCompanion", into: source, values: ["id": UUID(), "name": "Second"])
            meal.setValue(NSOrderedSet(array: [second, first]), forKey: "companions")
            try source.context.save()
            let file = try await export(source); defer { file.cleanup() }
            let preview = try await preview(file, into: target); defer { preview.cleanup() }
            _ = try await SavourBackupRestorer.restore(preview, coordinator: target.coordinator)
            let restored = try XCTUnwrap(objects("FoodEntry", in: target).first)
            let people = try XCTUnwrap(restored.value(forKey: "companions") as? NSOrderedSet)
            let ordered = people.array as! [NSManagedObject]
            XCTAssertEqual(ordered.map { $0.value(forKey: "name") as? String }, ["Second", "First"])
            restored.setValue(NSOrderedSet(array: ordered.reversed()), forKey: "companions")
            try target.context.save()
            let next = try await self.preview(file, into: target); defer { next.cleanup() }
            XCTAssertEqual(next.counts.totalConflicts, 3)
            XCTAssertEqual(next.counts.totalAdded, 0)
        }
    }

    func testEmptyStoreExportsAStandardVersionedZIPAndAllEntitySchemas() async {
        await assertNoError {
            let fixture = try fixture()
            defer { fixture.cleanup() }
            let file = try await export(fixture)
            let (manifest, _) = try unpack(file, into: fixture)
            XCTAssertTrue(file.url.lastPathComponent.hasPrefix("SavourBackup-v1-"))
            XCTAssertEqual(file.url.pathExtension, "zip")
            XCTAssertEqual(manifest.format, "SavourBackup-v1")
            XCTAssertEqual(manifest.version, 1)
            XCTAssertEqual(manifest.appVersion, "0.5.3")
            XCTAssertEqual(manifest.appBuild, "8")
            XCTAssertEqual(manifest.dateEncoding, "secondsSince2001-01-01T00:00:00Z")
            XCTAssertEqual(Set(manifest.entities.map(\.name)), ["FoodEntry", "FoodEntryCompanion"])
            for entity in manifest.entities {
                let original = try XCTUnwrap(fixture.coordinator.managedObjectModel.entitiesByName[entity.name])
                XCTAssertTrue(entity.objects.isEmpty)
                XCTAssertEqual(Set(entity.attributes.keys), Set(original.attributesByName.keys))
                XCTAssertEqual(Set(entity.relationships.keys), Set(original.relationshipsByName.keys))
                XCTAssertEqual(entity.versionHash, original.versionHash.base64EncodedString())
            }
            let permissions = try FileManager.default.attributesOfItem(atPath: file.url.path)[.posixPermissions] as? NSNumber
            XCTAssertEqual(permissions?.intValue, 0o600)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: file.url.deletingLastPathComponent().path), [file.url.lastPathComponent])
            file.cleanup()
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
        }
    }

    func testExactFieldsUUIDsDatesPeopleNotesCoordinatesAndPhotosSurviveZIP() async {
        await assertNoError {
            let fixture = try fixture()
            defer { fixture.cleanup() }
            let id = UUID()
            let timestamp = Date(timeIntervalSinceReferenceDate: 812_345_678.1234567)
            let created = Date(timeIntervalSinceReferenceDate: -1_234_567.987654321)
            let text = "  Rice, \"tofu\"\n豆腐 🥑  "
            let bytes = Data([0xFF, 0xD8, 0xFF, 0, 1, 2, 255, 10, 13])
            let entry = insert("FoodEntry", into: fixture, values: ["id": id, "date": timestamp, "createdAt": created,
                "food": text, "mealType": "Lunch", "people": "Ana, \"B\"\nDev", "note": text,
                "place": "Place, \"quoted\"", "placeCity": "東京", "hasPlaceCoordinates": true,
                "placeLatitude": 12.345678901234, "placeLongitude": -98.765432109876, "photoData": bytes])
            let companion = insert("FoodEntryCompanion", into: fixture,
                values: ["id": UUID(), "name": "A, \"name\"\n😀", "sortIndex": Int16(9), "entry": entry])
            try fixture.context.save()
            let entryRef = entry.objectID.uriRepresentation().absoluteString
            let companionRef = companion.objectID.uriRepresentation().absoluteString
            let file = try await export(fixture)
            let (manifest, folder) = try unpack(file, into: fixture)
            let record = try XCTUnwrap(entity("FoodEntry", in: manifest).objects.first)
            XCTAssertEqual(record.objectID, entryRef)
            XCTAssertEqual(record.attributes["id"], .uuid(id.uuidString))
            XCTAssertEqual(record.attributes["food"], .string(text))
            XCTAssertEqual(record.attributes["note"], .string(text))
            XCTAssertEqual(record.attributes["people"], .string("Ana, \"B\"\nDev"))
            XCTAssertEqual(record.attributes["mealType"], .string("Lunch"))
            XCTAssertEqual(record.attributes["place"], .string("Place, \"quoted\""))
            XCTAssertEqual(record.attributes["placeCity"], .string("東京"))
            XCTAssertEqual(record.attributes["hasPlaceCoordinates"], .boolean(true))
            XCTAssertEqual(record.attributes["placeLatitude"], .number(12.345678901234))
            XCTAssertEqual(record.attributes["placeLongitude"], .number(-98.765432109876))
            XCTAssertEqual(record.attributes["date"], .date(timestamp.timeIntervalSinceReferenceDate))
            XCTAssertEqual(record.attributes["createdAt"], .date(created.timeIntervalSinceReferenceDate))
            XCTAssertEqual(record.relationships["companions"], [companionRef])
            let person = try XCTUnwrap(entity("FoodEntryCompanion", in: manifest).objects.first)
            XCTAssertEqual(person.relationships["entry"], [entryRef])
            XCTAssertEqual(person.attributes["sortIndex"], .integer(9))
            XCTAssertEqual(person.attributes["name"], .string("A, \"name\"\n😀"))
            guard case let .binary(photo) = record.attributes["photoData"] else { return XCTFail("Photo reference missing") }
            XCTAssertTrue(photo.path.hasPrefix("photos/"))
            XCTAssertTrue(photo.path.hasSuffix(".jpg"))
            XCTAssertEqual(photo.byteCount, bytes.count)
            XCTAssertEqual(photo.sha256, SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
            XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(photo.path)), bytes)
            XCTAssertFalse(fixture.context.hasChanges)
            XCTAssertEqual(entry.value(forKey: "id") as? UUID, id)
        }
    }

    func testOrphanPeopleAreIncludedButFastingRecordsAreOmittedAndUnchanged() async {
        await assertNoError {
            let fixture = try fixture()
            defer { fixture.cleanup() }
            let entryID = UUID()
            let date = Date(timeIntervalSinceReferenceDate: 1_234_567.125)
            _ = insert("FoodEntry", into: fixture, values: ["id": entryID, "date": date])
            _ = insert("FoodEntryCompanion", into: fixture, values: ["name": "Orphaned person", "sortIndex": 2])
            let activeID = UUID(), completedID = UUID(), missingEntryID = UUID()
            _ = insert("FastSession", into: fixture, values: ["id": activeID, "startDate": date, "createdAt": date, "startEntryID": entryID])
            _ = insert("FastSession", into: fixture, values: ["id": completedID, "startDate": date, "createdAt": date,
                "endDate": date.addingTimeInterval(50_400), "targetDuration": 50_400.0, "endEntryID": missingEntryID])
            try fixture.context.save()
            let file = try await export(fixture)
            let (manifest, _) = try unpack(file, into: fixture)
            XCTAssertEqual(try entity("FoodEntry", in: manifest).objects.count, 1)
            let orphan = try XCTUnwrap(entity("FoodEntryCompanion", in: manifest).objects.first)
            XCTAssertEqual(orphan.attributes["id"], .null)
            XCTAssertEqual(orphan.relationships["entry"], [])
            XCTAssertFalse(manifest.entities.contains { $0.name == "FastSession" })
            XCTAssertEqual(try objects("FastSession", in: fixture).count, 2)
        }
    }

    func testNullEmptyPhotoAndDuplicateOrMissingUUIDsAreNotNormalizedOrRepaired() async {
        await assertNoError {
            let fixture = try fixture()
            defer { fixture.cleanup() }
            let duplicate = UUID()
            _ = insert("FoodEntry", into: fixture, values: ["id": duplicate, "food": "", "photoData": Data()])
            _ = insert("FoodEntry", into: fixture, values: ["id": duplicate, "food": "Second"])
            let missing = insert("FoodEntry", into: fixture, values: [:])
            try fixture.context.save()
            let file = try await export(fixture)
            let (manifest, folder) = try unpack(file, into: fixture)
            let records = try entity("FoodEntry", in: manifest).objects
            XCTAssertEqual(records.count, 3)
            XCTAssertEqual(Set(records.map(\.objectID)).count, 3)
            XCTAssertEqual(records.filter { $0.attributes["id"] == .uuid(duplicate.uuidString) }.count, 2)
            let blank = try XCTUnwrap(records.first { $0.attributes["food"] == .string("") })
            guard case let .binary(photo) = blank.attributes["photoData"] else { return XCTFail("Empty photo is not null") }
            XCTAssertEqual(photo.byteCount, 0)
            XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(photo.path)), Data())
            XCTAssertTrue(records.contains { $0.attributes["food"] == .null && $0.attributes["photoData"] == .null })
            XCTAssertNil(missing.value(forKey: "id"))
            XCTAssertFalse(fixture.context.hasChanges)
        }
    }

    func testSharedPhotoBytesAreDeduplicatedWithoutLosingPerObjectReferences() async {
        await assertNoError {
            let fixture = try fixture()
            defer { fixture.cleanup() }
            let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 3, 4, 5])
            for _ in 0..<2 { _ = insert("FoodEntry", into: fixture, values: ["id": UUID(), "photoData": bytes]) }
            try fixture.context.save()
            let file = try await export(fixture)
            let (manifest, folder) = try unpack(file, into: fixture)
            let refs = try entity("FoodEntry", in: manifest).objects.compactMap { object -> SavourBackupBinary? in
                if case let .binary(value) = object.attributes["photoData"] { return value }
                return nil
            }
            XCTAssertEqual(refs.count, 2)
            XCTAssertEqual(refs[0], refs[1])
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("photos").path).count, 1)
            XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(refs[0].path)), bytes)
        }
    }

    func testExportExcludesUnsavedInsertionsEditsAndDeletionsWithoutSavingUIContext() async {
        await assertNoError {
            let fixture = try fixture()
            defer { fixture.cleanup() }
            let existing = insert("FoodEntry", into: fixture, values: ["id": UUID(), "food": "Saved original"])
            let deleting = insert("FoodEntry", into: fixture, values: ["id": UUID(), "food": "Not deleted yet"])
            try fixture.context.save()
            existing.setValue("Unsaved edit", forKey: "food")
            fixture.context.delete(deleting)
            let new = insert("FoodEntry", into: fixture, values: ["food": "Unfinished entry"])
            let file = try await export(fixture)
            let (manifest, _) = try unpack(file, into: fixture)
            let records = try entity("FoodEntry", in: manifest).objects
            XCTAssertEqual(records.count, 2)
            XCTAssertEqual(Set(records.compactMap { if case let .string(value) = $0.attributes["food"] { return value }; return nil }),
                           ["Saved original", "Not deleted yet"])
            XCTAssertTrue(fixture.context.hasChanges)
            XCTAssertTrue(new.objectID.isTemporaryID)
            XCTAssertEqual(existing.value(forKey: "food") as? String, "Unsaved edit")
            XCTAssertTrue(deleting.isDeleted)
        }
    }

    func testOrderedRelationshipsKeepTheirOriginalOrder() async {
        await assertNoError {
            let fixture = try fixture(modify: { model in model.entitiesByName["FoodEntry"]?.relationshipsByName["companions"]?.isOrdered = true })
            defer { fixture.cleanup() }
            let entry = insert("FoodEntry", into: fixture, values: ["id": UUID()])
            let first = insert("FoodEntryCompanion", into: fixture, values: ["id": UUID(), "name": "Zoe"])
            let second = insert("FoodEntryCompanion", into: fixture, values: ["id": UUID(), "name": "Ana"])
            entry.setValue(NSOrderedSet(array: [first, second]), forKey: "companions")
            try fixture.context.save()
            let refs = [first, second].map { $0.objectID.uriRepresentation().absoluteString }
            let file = try await export(fixture)
            let (manifest, _) = try unpack(file, into: fixture)
            XCTAssertEqual(try entity("FoodEntry", in: manifest).objects.first?.relationships["companions"], refs)
            XCTAssertEqual(try entity("FoodEntry", in: manifest).relationships["companions"]?.isOrdered, true)
        }
    }

    func testExportHandlesEveryPreviousModelWithoutChangingTheStore() async {
        await assertNoError {
            for version in ["FoodLog", "FoodLogV2", "FoodLogV3", "FoodLogV4", "FoodLogV5"] {
                let fixture = try fixture(version: version)
                let id = UUID()
                let entry = insert("FoodEntry", into: fixture, values: ["id": id, "food": "Legacy \(version)", "date": Date()])
                try fixture.context.save()
                let file = try await export(fixture)
                let (manifest, _) = try unpack(file, into: fixture)
                XCTAssertEqual(Set(manifest.entities.map(\.name)), Set(fixture.coordinator.managedObjectModel.entities.compactMap(\.name).filter { $0 != "FastSession" }))
                let record = try XCTUnwrap(entity("FoodEntry", in: manifest).objects.first)
                XCTAssertEqual(Set(record.attributes.keys), Set(entry.entity.attributesByName.keys))
                XCTAssertEqual(record.attributes["id"], .uuid(id.uuidString))
                XCTAssertFalse(fixture.context.hasChanges)
                fixture.cleanup()
            }
        }
    }

    func testTwoExportsKeepStableObjectReferencesAndIndependentTemporaryFiles() async {
        await assertNoError {
            let fixture = try fixture()
            defer { fixture.cleanup() }
            _ = insert("FoodEntry", into: fixture, values: ["id": UUID(), "date": Date(timeIntervalSinceReferenceDate: -0.000000123)])
            try fixture.context.save()
            let originalZone = NSTimeZone.default
            defer { NSTimeZone.default = originalZone }
            NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
            let first = try await export(fixture)
            let (a, _) = try unpack(first, into: fixture)
            NSTimeZone.default = TimeZone(identifier: "Asia/Kolkata")!
            let second = try await export(fixture)
            let (b, _) = try unpack(second, into: fixture)
            let entryA = try XCTUnwrap(entity("FoodEntry", in: a).objects.first)
            let entryB = try XCTUnwrap(entity("FoodEntry", in: b).objects.first)
            XCTAssertEqual(entryA.objectID, entryB.objectID)
            XCTAssertEqual(entryA.attributes["date"], entryB.attributes["date"])
            XCTAssertNotEqual(first.url, second.url)
            first.cleanup()
            XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: second.url.path))
            second.cleanup()
        }
    }

    func testUnsupportedNonNullFieldFailsInsteadOfLeavingAPartialBackup() async {
        await assertNoError {
            let fixture = try fixture(modify: { model in
                let attribute = NSAttributeDescription()
                attribute.name = "futurePayload"
                attribute.attributeType = .transformableAttributeType
                attribute.attributeValueClassName = "NSString"
                attribute.valueTransformerName = "NSSecureUnarchiveFromData"
                attribute.isOptional = true
                model.entitiesByName["FoodEntry"]?.properties.append(attribute)
            })
            defer { fixture.cleanup() }
            _ = insert("FoodEntry", into: fixture, values: ["id": UUID(), "futurePayload": "Unsupported data"])
            try fixture.context.save()
            do { _ = try await export(fixture); XCTFail("Must fail rather than omit a persisted value") }
            catch { XCTAssertTrue(error.localizedDescription.contains("futurePayload")) }
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).contains { $0.hasPrefix("SavourBackupExport-") })
            XCTAssertFalse(fixture.context.hasChanges)
        }
    }

    func testInvalidOutputLocationDoesNotCreateAPartialExport() async {
        await assertNoError {
            let fixture = try fixture()
            defer { fixture.cleanup() }
            let file = fixture.directory.appendingPathComponent("not-a-directory")
            let marker = Data("Untouched".utf8)
            try marker.write(to: file)
            do {
                _ = try await SavourBackupExporter.export(from: fixture.coordinator, temporaryRoot: file)
                XCTFail("Expected output failure")
            } catch { XCTAssertEqual(try Data(contentsOf: file), marker) }
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).contains { $0.hasPrefix("SavourBackupExport-") })
        }
    }

    func testCancelledExportDoesNotCreateAFile() async {
        await assertNoError {
            let fixture = try fixture()
            defer { fixture.cleanup() }
            let task = Task { try await export(fixture) }
            task.cancel()
            do { _ = try await task.value; XCTFail("Expected cancellation") }
            catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).contains { $0.hasPrefix("SavourBackupExport-") })
        }
    }
}

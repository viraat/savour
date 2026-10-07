import CoreData
import CryptoKit
import Foundation
import ZIPFoundation

enum SavourRestoreError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self {
        case let .invalid(reason): return "This backup cannot be restored: \(reason). Your journal has not been changed."
        }
    }
}

struct SavourRestoreCounts: Sendable {
    var added = [String: Int]()
    var identical = [String: Int]()
    var conflicts = [String: Int]()
    var newPhotos = 0
    var totalAdded: Int { added.values.reduce(0, +) }
    var totalIdentical: Int { identical.values.reduce(0, +) }
    var totalConflicts: Int { conflicts.values.reduce(0, +) }
}

final class SavourRestorePreview: Identifiable, Sendable {
    let id = UUID()
    let fileName: String
    let exportedAt: Date
    let counts: SavourRestoreCounts
    fileprivate let manifest: SavourBackupManifest
    fileprivate let directory: URL
    fileprivate init(fileName: String, manifest: SavourBackupManifest, directory: URL, counts: SavourRestoreCounts) {
        self.fileName = fileName
        self.manifest = manifest
        self.directory = directory
        self.counts = counts
        self.exportedAt = Date(timeIntervalSinceReferenceDate: manifest.exportedAt)
    }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
    deinit { cleanup() }
}

/// Only reads validated ZIP entries into an app-owned staging directory. It
/// never extracts arbitrary archive paths or replaces/deletes existing objects.
enum SavourBackupRestorer {
    private static let maximumManifestBytes = SavourBackupLimits.manifestBytes
    private static let maximumBlobBytes = SavourBackupLimits.blobBytes
    private static let maximumArchiveBytes = SavourBackupLimits.archiveBytes
    private static let maximumObjects = SavourBackupLimits.objects

    static func preview(url: URL, coordinator: NSPersistentStoreCoordinator,
                        temporaryRoot: URL = FileManager.default.temporaryDirectory) async throws -> SavourRestorePreview {
        try Task.checkCancellation()
        let context = worker(coordinator)
        return try await context.perform {
            defer { context.reset() }
            let directory = temporaryRoot.appendingPathComponent("SavourBackupRestore-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            var succeeded = false
            defer { if !succeeded { try? FileManager.default.removeItem(at: directory) } }
            // The caller holds its security scope until this finishes. Copying
            // also isolates validation from subsequent File Provider changes.
            let source = directory.appendingPathComponent("source.zip")
            let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard fileSize >= 0, UInt64(fileSize) <= maximumArchiveBytes else { throw invalid("the archive is too large") }
            try FileManager.default.copyItem(at: url, to: source)
            try SavourBackupExporter.protect(source)
            guard UInt64(try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= maximumArchiveBytes else {
                throw invalid("the archive is too large")
            }
            let manifest = try readArchive(source, into: directory, model: coordinator.managedObjectModel)
            let plan = try makePlan(manifest, in: context)
            let result = SavourRestorePreview(fileName: url.lastPathComponent, manifest: manifest,
                                              directory: directory, counts: plan.counts)
            succeeded = true
            return result
        }
    }

    static func restore(_ preview: SavourRestorePreview, coordinator: NSPersistentStoreCoordinator) async throws -> SavourRestoreCounts {
        try Task.checkCancellation()
        let context = worker(coordinator)
        return try await context.perform {
            defer { context.reset() }
            do {
                // Revalidate staged bytes and recheck the live journal, rather
                // than applying a potentially stale preview plan.
                let manifest = try readArchive(preview.directory.appendingPathComponent("source.zip"),
                                               into: preview.directory, model: coordinator.managedObjectModel)
                let plan = try makePlan(manifest, in: context)
                var objects: [String: NSManagedObject] = [:]
                for record in plan.records {
                    objects[record.object.objectID] = NSEntityDescription.insertNewObject(forEntityName: record.entity, into: context)
                }
                for record in plan.records {
                    guard let object = objects[record.object.objectID] else { throw invalid("an object is missing") }
                    for (key, value) in record.object.attributes {
                        object.setValue(try rawValue(value, directory: preview.directory), forKey: key)
                    }
                }
                for record in plan.records {
                    guard let object = objects[record.object.objectID] else { throw invalid("an object is missing") }
                    for (key, refs) in record.object.relationships {
                        let related = try refs.map { ref -> NSManagedObject in
                            guard let target = objects[ref] else { throw invalid("a relationship is missing") }
                            return target
                        }
                        guard let relation = object.entity.relationshipsByName[key] else { throw invalid("an unknown relationship was found") }
                        if relation.isToMany {
                            object.setValue(relation.isOrdered ? NSOrderedSet(array: related) : NSSet(array: related), forKey: key)
                        } else { object.setValue(related.first, forKey: key) }
                    }
                    try object.validateForInsert()
                }
                // A single Core Data transaction. A failure rolls back the
                // entire import, including photos and companion relationships.
                if context.hasChanges { try context.save() }
                return plan.counts
            } catch { context.rollback(); throw error }
        }
    }

    private static func worker(_ coordinator: NSPersistentStoreCoordinator) -> NSManagedObjectContext {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.mergePolicy = NSErrorMergePolicy
        context.undoManager = nil
        context.transactionAuthor = "SavourBackupRestore-v1"
        return context
    }

    private static func invalid(_ reason: String) -> SavourRestoreError { .invalid(reason) }

    private static func readArchive(_ source: URL, into directory: URL, model: NSManagedObjectModel) throws -> SavourBackupManifest {
        let archive = try Archive(url: source, accessMode: .read)
        var files: [String: Entry] = [:]
        var total: UInt64 = 0
        var entryCount = 0
        for entry in archive {
            entryCount += 1
            guard entryCount <= maximumObjects + 100, safePath(entry.path), entry.type != .symlink,
                  files[entry.path] == nil else { throw invalid("the archive contains an unsafe or duplicate path") }
            guard entry.uncompressedSize <= maximumArchiveBytes - total else { throw invalid("the archive is too large") }
            total += entry.uncompressedSize
            files[entry.path] = entry
        }
        // Foundation's directory upload ZIP has a single root directory.
        let root = SavourBackupExporter.format + "/"
        guard let manifestEntry = files[root + "manifest.json"], manifestEntry.type == .file else {
            throw invalid("a SavourBackup-v1 manifest is missing")
        }
        let data = try extract(manifestEntry, from: archive, maximum: maximumManifestBytes)
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        let decoded = try decoder.decode(SavourBackupManifest.self, from: data)
        let manifest = try validated(decoded, model: model)
        var expected = Set([root + "manifest.json"])
        var binaries: [String: SavourBackupBinary] = [:]
        for value in manifest.entities.flatMap({ $0.objects }).flatMap({ $0.attributes.values }) {
            if case let .binary(binary) = value {
                guard safePath(binary.path), ["photos", "attachments"].contains(binary.path.split(separator: "/").first.map(String.init) ?? ""),
                      binary.byteCount >= 0, binary.byteCount <= maximumBlobBytes,
                      binary.sha256.count == 64, binary.sha256.allSatisfy({ "0123456789abcdef".contains($0) }) else {
                    throw invalid("a photo or attachment reference is invalid")
                }
                if let previous = binaries[binary.path], previous != binary { throw invalid("an attachment has conflicting checksums") }
                binaries[binary.path] = binary
            }
        }
        for binary in binaries.values {
            let path = root + binary.path
            guard let entry = files[path], entry.type == .file, entry.uncompressedSize == UInt64(binary.byteCount) else {
                throw invalid("a photo or attachment is missing or has the wrong size")
            }
            expected.insert(path)
            let bytes = try extract(entry, from: archive, maximum: maximumBlobBytes)
            guard digest(bytes) == binary.sha256 else { throw invalid("a photo or attachment checksum does not match") }
            // Not the archive's filename: the app chooses this safe hash path.
            try SavourBackupExporter.write(bytes, to: directory.appendingPathComponent(binary.sha256 + ".blob"))
        }
        for (path, entry) in files where entry.type != .directory && !expected.contains(path) {
            throw invalid("the archive contains an unexpected file")
        }
        return manifest
    }

    private static func safePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.enumerated().allSatisfy { index, part in
            part != "." && part != ".." && (!part.isEmpty || index == parts.count - 1)
        }
    }

    private static func extract(_ entry: Entry, from archive: Archive, maximum: Int) throws -> Data {
        guard entry.uncompressedSize <= UInt64(maximum) else { throw invalid("an archive item is too large") }
        var bytes = Data()
        let crc = try archive.extract(entry, bufferSize: 64 * 1_024) { chunk in
            guard chunk.count <= maximum - bytes.count else { throw invalid("an archive item exceeds its size limit") }
            bytes.append(chunk)
        }
        guard crc == entry.checksum, UInt64(bytes.count) == entry.uncompressedSize else { throw invalid("an archive item is damaged") }
        return bytes
    }

    private static func validated(_ manifest: SavourBackupManifest, model: NSManagedObjectModel) throws -> SavourBackupManifest {
        guard manifest.format == SavourBackupExporter.format, manifest.version == 1,
              manifest.dateEncoding == "secondsSince2001-01-01T00:00:00Z", manifest.exportedAt.isFinite,
              manifest.entities.count <= model.entities.count,
              Set(manifest.entities.map(\.name)).count == manifest.entities.count,
              manifest.entities.reduce(0, { $0 + $1.objects.count }) <= maximumObjects else {
            throw invalid("the backup format or version is unsupported")
        }
        var allRecords: [String: (String, SavourBackupManifest.Object)] = [:]
        var entities: [SavourBackupManifest.Entity] = []
        let knownModels = historicalModels() + [model]
        for entity in manifest.entities {
            guard entity.name != "FastSession" else { throw invalid("this backup contains fasting records, which are not supported by meal backups") }
            guard let schema = model.entitiesByName[entity.name], !schema.isAbstract else { throw invalid("an unknown entity was found") }
            // Do not accept a fabricated, truncated schema which could hide
            // missing fields as a supposed older model version.
            guard knownModels.contains(where: { known in
                guard let candidate = known.entitiesByName[entity.name] else { return false }
                let attrs = candidate.attributesByName.filter { !$0.value.isTransient }
                let links = candidate.relationshipsByName.filter { !$0.value.isTransient }
                return Set(entity.attributes.keys) == Set(attrs.keys)
                    && Set(entity.relationships.keys) == Set(links.keys)
                    && entity.attributes.allSatisfy { key, value in
                        guard let actual = attrs[key] else { return false }
                        return Int(actual.attributeType.rawValue) == value.coreDataType && actual.isOptional == value.isOptional
                            && actual.allowsExternalBinaryDataStorage == value.allowsExternalBinaryDataStorage
                    }
                    && entity.relationships.allSatisfy { key, value in
                        guard let actual = links[key] else { return false }
                        return actual.destinationEntity?.name == value.destinationEntity && actual.inverseRelationship?.name == value.inverse
                            && actual.isToMany == value.isToMany && actual.isOrdered == value.isOrdered
                            && actual.isOptional == value.isOptional && Int(actual.deleteRule.rawValue) == value.deletionRule
                    }
            }) else { throw invalid("the entity schema is incomplete or unsupported") }
            for (key, attribute) in entity.attributes {
                guard let actual = schema.attributesByName[key], !actual.isTransient,
                      Int(actual.attributeType.rawValue) == attribute.coreDataType else { throw invalid("the schema for \(entity.name).\(key) is unsupported") }
            }
            for (key, relation) in entity.relationships {
                guard let actual = schema.relationshipsByName[key], !actual.isTransient,
                      actual.destinationEntity?.name == relation.destinationEntity, actual.isToMany == relation.isToMany,
                      actual.isOrdered == relation.isOrdered, actual.inverseRelationship?.name == relation.inverse else {
                    throw invalid("the schema for a relationship is unsupported")
                }
            }
            var records: [SavourBackupManifest.Object] = []
            for object in entity.objects {
                guard !object.objectID.isEmpty, allRecords[object.objectID] == nil,
                      Set(object.attributes.keys) == Set(entity.attributes.keys),
                      Set(object.relationships.keys) == Set(entity.relationships.keys) else { throw invalid("an object is duplicated or incomplete") }
                var attrs = object.attributes
                for (key, attribute) in schema.attributesByName where !attribute.isTransient {
                    if attrs[key] == nil { attrs[key] = try SavourBackupExporter.value(attribute.defaultValue, attribute: attribute, payload: nil) }
                    try validate(try required(attrs[key]), attribute: attribute)
                    if case let .uuid(text) = attrs[key], let uuid = UUID(uuidString: text) { attrs[key] = .uuid(uuid.uuidString) }
                }
                var links = object.relationships
                for (key, relation) in schema.relationshipsByName where !relation.isTransient {
                    let refs = links[key] ?? []
                    guard Set(refs).count == refs.count, (relation.isToMany || refs.count <= 1),
                          refs.count >= relation.minCount, (relation.maxCount == 0 || refs.count <= relation.maxCount) else {
                        throw invalid("a relationship has an invalid number of objects")
                    }
                    links[key] = refs
                }
                let normalized = SavourBackupManifest.Object(objectID: object.objectID, attributes: attrs, relationships: links)
                allRecords[object.objectID] = (entity.name, normalized)
                records.append(normalized)
            }
            entities.append(.init(name: entity.name, versionHash: entity.versionHash, attributes: entity.attributes,
                                  relationships: entity.relationships, objects: records))
        }
        for (id, (name, record)) in allRecords {
            for (key, refs) in record.relationships {
                guard let relation = model.entitiesByName[name]?.relationshipsByName[key] else { throw invalid("a relationship is unknown") }
                for ref in refs {
                    guard let (targetName, target) = allRecords[ref], targetName == relation.destinationEntity?.name else {
                        throw invalid("a relationship refers to a missing object")
                    }
                    if let inverse = relation.inverseRelationship?.name, !(target.relationships[inverse] ?? []).contains(id) {
                        throw invalid("a relationship and its inverse disagree")
                    }
                }
            }
        }
        return .init(format: manifest.format, version: manifest.version, exportedAt: manifest.exportedAt,
                     dateEncoding: manifest.dateEncoding, exportTimeZone: manifest.exportTimeZone,
                     appVersion: manifest.appVersion, appBuild: manifest.appBuild,
                     modelVersionIdentifiers: manifest.modelVersionIdentifiers, entities: entities)
    }

    private static func historicalModels() -> [NSManagedObjectModel] {
#if SWIFT_PACKAGE
        let bundle = SavourBackupExporter.modelBundle
#else
        let bundle = Bundle.main
#endif
        guard let directory = bundle.url(forResource: "FoodLog", withExtension: "momd"),
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "mom" }.compactMap(NSManagedObjectModel.init(contentsOf:))
    }

    private static func required<T>(_ value: T?) throws -> T {
        guard let value else { throw invalid("a required value is missing") }
        return value
    }

    private static func validate(_ value: SavourBackupValue, attribute: NSAttributeDescription) throws {
        if case .null = value {
            guard attribute.isOptional else { throw invalid("a required field is empty") }
            return
        }
        switch (attribute.attributeType, value) {
        case (.stringAttributeType, .string), (.booleanAttributeType, .boolean), (.binaryDataAttributeType, .binary): return
        case let (.UUIDAttributeType, .uuid(text)) where UUID(uuidString: text) != nil: return
        case let (.dateAttributeType, .date(seconds)) where seconds.isFinite: return
        case let (.integer16AttributeType, .integer(number)) where Int16(exactly: number) != nil: return
        case let (.integer32AttributeType, .integer(number)) where Int32(exactly: number) != nil: return
        case (.integer64AttributeType, .integer), (.floatAttributeType, .number), (.doubleAttributeType, .number): return
        case let (.decimalAttributeType, .decimal(text)) where NSDecimalNumber(string: text) != .notANumber: return
        case let (.URIAttributeType, .uri(text)) where URL(string: text) != nil: return
        default: throw invalid("the value of \(attribute.entity.name ?? "object").\(attribute.name) has the wrong type")
        }
    }

    private static func rawValue(_ value: SavourBackupValue, directory: URL) throws -> Any? {
        switch value {
        case .null: return nil
        case let .string(value): return value
        case let .uuid(value): return try required(UUID(uuidString: value))
        case let .date(value): return Date(timeIntervalSinceReferenceDate: value)
        case let .integer(value): return NSNumber(value: value)
        case let .number(value): return NSNumber(value: value)
        case let .boolean(value): return NSNumber(value: value)
        case let .decimal(value): return NSDecimalNumber(string: value)
        case let .uri(value): return try required(URL(string: value))
        case let .binary(binary): return try Data(contentsOf: directory.appendingPathComponent(binary.sha256 + ".blob"))
        }
    }

    private struct Record {
        let entity: String
        let object: SavourBackupManifest.Object
    }
    private struct Plan { let records: [Record]; let counts: SavourRestoreCounts }

    private static func makePlan(_ manifest: SavourBackupManifest, in context: NSManagedObjectContext) throws -> Plan {
        let current = try SavourBackupExporter.snapshot(in: context, payload: nil, appVersion: "", appBuild: "")
        let existing = current.entities.flatMap { entity in entity.objects.map { Record(entity: entity.name, object: $0) } }
        let incoming = manifest.entities.flatMap { entity in entity.objects.map { Record(entity: entity.name, object: $0) } }
        var signatures = [String: Int]()
        let model = try required(context.persistentStoreCoordinator?.managedObjectModel)
        for group in groups(existing) { signatures[try signature(group, model: model), default: 0] += 1 }
        let existingIDs = Set(existing.compactMap(identity))
        var records: [Record] = []
        var counts = SavourRestoreCounts()
        for group in groups(incoming) {
            let hash = try signature(group, model: model)
            if signatures[hash, default: 0] > 0 {
                signatures[hash, default: 0] -= 1
                for record in group { counts.identical[record.entity, default: 0] += 1 }
            } else if group.compactMap(identity).contains(where: existingIDs.contains) {
                // Keep the entire connected graph unchanged, including inverse
                // relationships. Never attach an imported child to an old meal.
                for record in group { counts.conflicts[record.entity, default: 0] += 1 }
            } else {
                records.append(contentsOf: group)
                for record in group {
                    counts.added[record.entity, default: 0] += 1
                    if case .binary = record.object.attributes["photoData"] { counts.newPhotos += 1 }
                }
            }
        }
        return Plan(records: records, counts: counts)
    }

    private static func identity(_ record: Record) -> String? {
        if case let .uuid(id) = record.object.attributes["id"], let uuid = UUID(uuidString: id) { return record.entity + ":" + uuid.uuidString }
        return nil
    }

    private static func groups(_ records: [Record]) -> [[Record]] {
        let lookup = Dictionary(uniqueKeysWithValues: records.map { ($0.object.objectID, $0) })
        var neighbours = [String: Set<String>]()
        for record in records {
            for ref in record.object.relationships.values.flatMap({ $0 }) {
                neighbours[record.object.objectID, default: []].insert(ref)
                neighbours[ref, default: []].insert(record.object.objectID)
            }
        }
        var visited = Set<String>()
        var result: [[Record]] = []
        for record in records where !visited.contains(record.object.objectID) {
            var queue = [record.object.objectID]
            var group: [Record] = []
            while let id = queue.popLast() {
                guard visited.insert(id).inserted, let value = lookup[id] else { continue }
                group.append(value)
                queue.append(contentsOf: neighbours[id] ?? [])
            }
            result.append(group)
        }
        return result
    }

    private static func signature(_ group: [Record], model: NSManagedObjectModel) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        var tokens: [String: String] = [:]
        for record in group {
            tokens[record.object.objectID] = record.entity + ":" + digest(try encoder.encode(record.object.attributes))
        }
        var rows: [String] = []
        for record in group {
            var relationships: [String: [String]] = [:]
            for (key, refs) in record.object.relationships {
                let values = try refs.map { try required(tokens[$0]) }
                relationships[key] = model.entitiesByName[record.entity]?.relationshipsByName[key]?.isOrdered == true ? values : values.sorted()
            }
            rows.append(try required(tokens[record.object.objectID]) + ":" + digest(try encoder.encode(relationships)))
        }
        return digest(try encoder.encode(rows.sorted()))
    }

    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

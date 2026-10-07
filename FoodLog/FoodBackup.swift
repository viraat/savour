import CoreData
import CryptoKit
import Foundation

/// Portable, typed object graph. Nulls, UUIDs, precise dates and relationship
/// references are explicit; binary data is never re-encoded as an image.
struct SavourBackupManifest: Codable, Sendable {
    let format: String
    let version: Int
    let exportedAt: Double
    let dateEncoding: String
    let exportTimeZone: String
    let appVersion: String
    let appBuild: String
    let modelVersionIdentifiers: [String]
    let entities: [Entity]

    struct Entity: Codable, Sendable {
        let name: String
        let versionHash: String
        let attributes: [String: Attribute]
        let relationships: [String: Relationship]
        let objects: [Object]
    }
    struct Attribute: Codable, Sendable {
        let coreDataType: Int
        let isOptional: Bool
        let allowsExternalBinaryDataStorage: Bool
    }
    struct Relationship: Codable, Sendable {
        let destinationEntity: String?
        let inverse: String?
        let isToMany: Bool
        let isOrdered: Bool
        let isOptional: Bool
        let deletionRule: Int
    }
    struct Object: Codable, Sendable {
        // Permanent Core Data URI: identifies objects even with a missing or
        // duplicate optional UUID, without repairing or changing the journal.
        let objectID: String
        let attributes: [String: SavourBackupValue]
        let relationships: [String: [String]]
    }
}

struct SavourBackupBinary: Codable, Equatable, Sendable {
    let path: String
    let byteCount: Int
    let sha256: String
}

enum SavourBackupValue: Codable, Equatable, Sendable {
    case null, string(String), uuid(String), date(Double), integer(Int64)
    case number(Double), boolean(Bool), decimal(String), uri(String), binary(SavourBackupBinary)

    private enum Keys: String, CodingKey { case type, value }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        switch try values.decode(String.self, forKey: .type) {
        case "null": self = .null
        case "string": self = .string(try values.decode(String.self, forKey: .value))
        case "uuid": self = .uuid(try values.decode(String.self, forKey: .value))
        case "date": self = .date(try values.decode(Double.self, forKey: .value))
        case "integer": self = .integer(try values.decode(Int64.self, forKey: .value))
        case "number": self = .number(try values.decode(Double.self, forKey: .value))
        case "boolean": self = .boolean(try values.decode(Bool.self, forKey: .value))
        case "decimal": self = .decimal(try values.decode(String.self, forKey: .value))
        case "uri": self = .uri(try values.decode(String.self, forKey: .value))
        case "binary": self = .binary(try values.decode(SavourBackupBinary.self, forKey: .value))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: values, debugDescription: "Unknown backup value type")
        }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: Keys.self)
        switch self {
        case .null:
            try values.encode("null", forKey: .type); try values.encodeNil(forKey: .value)
        case let .string(value):
            try values.encode("string", forKey: .type); try values.encode(value, forKey: .value)
        case let .uuid(value):
            try values.encode("uuid", forKey: .type); try values.encode(value, forKey: .value)
        case let .date(value):
            try values.encode("date", forKey: .type); try values.encode(value, forKey: .value)
        case let .integer(value):
            try values.encode("integer", forKey: .type); try values.encode(value, forKey: .value)
        case let .number(value):
            try values.encode("number", forKey: .type); try values.encode(value, forKey: .value)
        case let .boolean(value):
            try values.encode("boolean", forKey: .type); try values.encode(value, forKey: .value)
        case let .decimal(value):
            try values.encode("decimal", forKey: .type); try values.encode(value, forKey: .value)
        case let .uri(value):
            try values.encode("uri", forKey: .type); try values.encode(value, forKey: .value)
        case let .binary(value):
            try values.encode("binary", forKey: .type); try values.encode(value, forKey: .value)
        }
    }
}

struct SavourBackupFile {
    let url: URL
    fileprivate let temporaryDirectory: URL

    func cleanup() {
        // Only the unique directory created for this particular export.
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }
}

enum SavourBackupError: LocalizedError {
    case missingCoordinator, unsupportedAttribute(String), invalidRelationship(String), archiveUnavailable, tooLarge
    var errorDescription: String? {
        switch self {
        case .missingCoordinator: return "The journal store is unavailable."
        case let .unsupportedAttribute(name): return "The backup cannot safely export the field \(name). No partial backup was created."
        case let .invalidRelationship(name): return "The backup cannot safely export the relationship \(name). No partial backup was created."
        case .archiveUnavailable: return "The backup archive could not be created. Please try again."
        case .tooLarge: return "The journal exceeds the supported backup size. No partial backup was created."
        }
    }
}

enum SavourBackupLimits {
    static let manifestBytes = 64 * 1_024 * 1_024
    static let blobBytes = 64 * 1_024 * 1_024
    static let archiveBytes: UInt64 = 2 * 1_024 * 1_024 * 1_024
    static let objects = 100_000
}

enum SavourBackupExporter {
    static let format = "SavourBackup-v1"
#if SWIFT_PACKAGE
    // The Mac test package compiles the actual app model, without an iOS simulator.
    static let modelBundle = Bundle.module
#endif

    static func export(from coordinator: NSPersistentStoreCoordinator,
                       temporaryRoot: URL = FileManager.default.temporaryDirectory,
                       appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—",
                       appBuild: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—") async throws -> SavourBackupFile {
        try Task.checkCancellation()
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.undoManager = nil
        // Never use/save the UI context: export only committed journal objects,
        // not unfinished entries or an unsaved edit.
        return try await context.perform {
            defer { context.reset() }
            if !coordinator.persistentStores.isEmpty,
               coordinator.persistentStores.allSatisfy({ $0.type == NSSQLiteStoreType }) {
                try context.setQueryGenerationFrom(.current)
            }
            return try makeArchive(in: context, temporaryRoot: temporaryRoot,
                                   appVersion: appVersion, appBuild: appBuild)
        }
    }

    private static func makeArchive(in context: NSManagedObjectContext, temporaryRoot: URL,
                                    appVersion: String, appBuild: String) throws -> SavourBackupFile {
        let manager = FileManager.default
        let directory = temporaryRoot.appendingPathComponent("SavourBackupExport-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var succeeded = false
        defer { if !succeeded { try? manager.removeItem(at: directory) } }
        let payload = directory.appendingPathComponent(format, isDirectory: true)
        try manager.createDirectory(at: payload, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let manifest = try snapshot(in: context, payload: payload, appVersion: appVersion, appBuild: appBuild, includingSavedFasts: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        let encoded = try encoder.encode(manifest)
        guard encoded.count <= SavourBackupLimits.manifestBytes else { throw SavourBackupError.tooLarge }
        let blobSizes = manifest.entities.flatMap { $0.objects }.flatMap { $0.attributes.values }.reduce(into: [String: Int]()) { result, value in
            if case let .binary(blob) = value { result[blob.path] = blob.byteCount }
        }
        guard UInt64(encoded.count) + blobSizes.values.reduce(0, { $0 + UInt64($1) }) <= SavourBackupLimits.archiveBytes else { throw SavourBackupError.tooLarge }
        try write(encoded, to: payload.appendingPathComponent("manifest.json"))

        let output = directory.appendingPathComponent("\(format)-\(UUID().uuidString).zip")
        var coordinationError: NSError?
        var copyError: Error?
        // Foundation creates the ZIP. Copy it before the accessor returns,
        // because the system's archive snapshot is temporary.
        NSFileCoordinator().coordinate(readingItemAt: payload, options: .forUploading, error: &coordinationError) { archive in
            do {
                try manager.copyItem(at: archive, to: output)
                try protect(output)
            } catch { copyError = error }
        }
        if let error = coordinationError { throw error }
        if let error = copyError { throw error }
        guard manager.fileExists(atPath: output.path) else { throw SavourBackupError.archiveUnavailable }
        guard UInt64(try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= SavourBackupLimits.archiveBytes else { throw SavourBackupError.tooLarge }
        try manager.removeItem(at: payload)
        succeeded = true
        return SavourBackupFile(url: output, temporaryDirectory: directory)
    }

    static func snapshot(in context: NSManagedObjectContext, payload: URL?,
                                 appVersion: String, appBuild: String, includingSavedFasts: Bool = true) throws -> SavourBackupManifest {
        guard let model = context.persistentStoreCoordinator?.managedObjectModel else { throw SavourBackupError.missingCoordinator }
        var entities: [SavourBackupManifest.Entity] = []
        for entity in model.entities.sorted(by: { ($0.name ?? "") < ($1.name ?? "") }) {
            guard let name = entity.name else { continue }
            if name == "FastSession", !includingSavedFasts { continue }
            let attributes = entity.attributesByName.filter { !$0.value.isTransient }
            let relationships = entity.relationshipsByName.filter { !$0.value.isTransient }
            var records: [SavourBackupManifest.Object] = []
            if !entity.isAbstract {
                let request = NSFetchRequest<NSManagedObject>(entityName: name)
                request.includesSubentities = false
                request.fetchBatchSize = 100
                guard try context.count(for: request) + entities.reduce(0, { $0 + $1.objects.count }) <= SavourBackupLimits.objects else { throw SavourBackupError.tooLarge }
                let objects = try context.fetch(request).sorted { reference($0) < reference($1) }
                for object in objects {
                    let record = try autoreleasepool { () throws -> SavourBackupManifest.Object in
                        var values: [String: SavourBackupValue] = [:]
                        for (key, attribute) in attributes {
                            values[key] = try value(object.value(forKey: key), attribute: attribute, payload: payload)
                        }
                        var links: [String: [String]] = [:]
                        for (key, relationship) in relationships {
                            if relationship.isToMany {
                                let related = relationship.isOrdered
                                    ? (object.value(forKey: key) as? NSOrderedSet)?.array
                                    : (object.value(forKey: key) as? NSSet)?.allObjects
                                let objects = (related ?? []).compactMap { $0 as? NSManagedObject }
                                guard objects.count == (related ?? []).count else { throw SavourBackupError.invalidRelationship("\(name).\(key)") }
                                let ids = objects.map(reference)
                                links[key] = relationship.isOrdered ? ids : ids.sorted()
                            } else if let related = object.value(forKey: key) as? NSManagedObject {
                                links[key] = [reference(related)]
                            } else { links[key] = [] }
                        }
                        return SavourBackupManifest.Object(objectID: reference(object), attributes: values, relationships: links)
                    }
                    records.append(record)
                    // Release loaded photo bytes before visiting the next entry.
                    context.refresh(object, mergeChanges: false)
                }
            }
            entities.append(SavourBackupManifest.Entity(name: name, versionHash: entity.versionHash.base64EncodedString(),
                attributes: attributes.mapValues { .init(coreDataType: Int($0.attributeType.rawValue), isOptional: $0.isOptional,
                    allowsExternalBinaryDataStorage: $0.allowsExternalBinaryDataStorage) },
                relationships: relationships.mapValues { .init(destinationEntity: $0.destinationEntity?.name, inverse: $0.inverseRelationship?.name,
                    isToMany: $0.isToMany, isOrdered: $0.isOrdered, isOptional: $0.isOptional, deletionRule: Int($0.deleteRule.rawValue)) },
                objects: records))
        }
        let ids = Set(entities.flatMap { $0.objects.map(\.objectID) })
        for entity in entities {
            for object in entity.objects {
                for (name, refs) in object.relationships where !refs.allSatisfy(ids.contains) {
                    throw SavourBackupError.invalidRelationship("\(entity.name).\(name)")
                }
            }
        }
        return SavourBackupManifest(format: format, version: 1, exportedAt: Date().timeIntervalSinceReferenceDate,
            dateEncoding: "secondsSince2001-01-01T00:00:00Z", exportTimeZone: TimeZone.current.identifier,
            appVersion: appVersion, appBuild: appBuild,
            modelVersionIdentifiers: model.versionIdentifiers.map { String(describing: $0) }.sorted(), entities: entities)
    }

    private static func reference(_ object: NSManagedObject) -> String {
        object.objectID.uriRepresentation().absoluteString
    }

    static func value(_ raw: Any?, attribute: NSAttributeDescription, payload: URL?) throws -> SavourBackupValue {
        guard let raw, !(raw is NSNull) else { return .null }
        switch attribute.attributeType {
        case .stringAttributeType: if let value = raw as? String { return .string(value) }
        case .UUIDAttributeType: if let value = raw as? UUID { return .uuid(value.uuidString) }
        case .dateAttributeType: if let value = raw as? Date { return .date(value.timeIntervalSinceReferenceDate) }
        case .booleanAttributeType: if let value = raw as? NSNumber { return .boolean(value.boolValue) }
        case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType:
            if let value = raw as? NSNumber { return .integer(value.int64Value) }
        case .floatAttributeType, .doubleAttributeType:
            if let value = raw as? NSNumber { return .number(value.doubleValue) }
        case .decimalAttributeType: if let value = raw as? NSDecimalNumber { return .decimal(value.stringValue) }
        case .URIAttributeType: if let value = raw as? URL { return .uri(value.absoluteString) }
        case .binaryDataAttributeType:
            if let data = raw as? Data {
                if payload != nil, data.count > SavourBackupLimits.blobBytes { throw SavourBackupError.tooLarge }
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                let folder = attribute.name == "photoData" ? "photos" : "attachments"
                let suffix = data.starts(with: [0xFF, 0xD8, 0xFF]) ? "jpg"
                    : data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) ? "png" : "bin"
                let path = "\(folder)/\(digest).\(suffix)"
                if let url = payload?.appendingPathComponent(path), !FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                           attributes: [.posixPermissions: 0o700])
                    try write(data, to: url)
                }
                return .binary(.init(path: path, byteCount: data.count, sha256: digest))
            }
        default: break
        }
        throw SavourBackupError.unsupportedAttribute("\(attribute.entity.name ?? "object").\(attribute.name)")
    }

    static func write(_ data: Data, to url: URL) throws {
#if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
#else
        try data.write(to: url, options: .atomic)
#endif
        try protect(url)
    }

    static func protect(_ file: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
#if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: file.path)
#endif
        var url = file
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}

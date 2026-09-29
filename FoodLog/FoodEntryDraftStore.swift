import Foundation

enum FoodEntryDraftKey: Hashable {
    case new
    case edit(UUID)

    var storageKey: String {
        switch self {
        case .new: return "new"
        case let .edit(id): return "edit:\(id.uuidString)"
        }
    }

    init?(storageKey: String) {
        if storageKey == "new" {
            self = .new
        } else if storageKey.hasPrefix("edit:"),
                  let id = UUID(uuidString: String(storageKey.dropFirst(5))) {
            self = .edit(id)
        } else {
            return nil
        }
    }
}

struct FoodEntryDraft: Codable, Equatable {
    var food: String
    var date: Date
    var mealType: String
    var place: String
    var placeCity: String
    var placeLatitude: Double
    var placeLongitude: Double
    var hasPlaceCoordinates: Bool
    var selectedPlaceLabel: String?
    var selectedPlaceSavedName: String?
    var companions: [String]
    var companionQuery: String
    var note: String
    var photoData: Data?
    var startFastAfterMeal: Bool
    var detailsExpanded: Bool
}

private struct FoodEntryDraftArchive: Codable {
    var version = 1
    var drafts: [String: FoodEntryDraft] = [:]
    var activeKey: String?
}

enum FoodEntryDraftStoreError: LocalizedError {
    case unsupportedVersion

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "This draft was saved by a newer version of FoodLog."
        }
    }
}

final class FoodEntryDraftStore {
    static let shared = FoodEntryDraftStore(url: defaultURL)

    static var defaultURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            return directory.appendingPathComponent("FoodLogUITestsDrafts.plist")
        }
#endif
        return directory.appendingPathComponent("FoodLogEntryDrafts.plist")
    }

    let url: URL

    init(url: URL) {
        self.url = url
    }

    func draft(for key: FoodEntryDraftKey) throws -> FoodEntryDraft? {
        try readArchive().drafts[key.storageKey]
    }

    func activeDraftKey() throws -> FoodEntryDraftKey? {
        let archive = try readArchive()
        guard let rawKey = archive.activeKey,
              archive.drafts[rawKey] != nil else { return nil }
        return FoodEntryDraftKey(storageKey: rawKey)
    }

    func save(_ draft: FoodEntryDraft, for key: FoodEntryDraftKey, active: Bool) throws {
        var archive = try readArchive()
        archive.drafts[key.storageKey] = draft
        if active {
            archive.activeKey = key.storageKey
        } else if archive.activeKey == key.storageKey {
            archive.activeKey = nil
        }
        try writeArchive(archive)
    }

    func markInactive(_ key: FoodEntryDraftKey) throws {
        var archive = try readArchive()
        guard archive.activeKey == key.storageKey else { return }
        archive.activeKey = nil
        try writeArchive(archive)
    }

    func markActive(_ key: FoodEntryDraftKey) throws {
        var archive = try readArchive()
        guard archive.drafts[key.storageKey] != nil else { return }
        archive.activeKey = key.storageKey
        try writeArchive(archive)
    }

    func discard(_ key: FoodEntryDraftKey) throws {
        var archive = try readArchive()
        archive.drafts.removeValue(forKey: key.storageKey)
        if archive.activeKey == key.storageKey { archive.activeKey = nil }
        try writeArchive(archive)
    }

    private func readArchive() throws -> FoodEntryDraftArchive {
        guard FileManager.default.fileExists(atPath: url.path) else { return .init() }
        let archive = try PropertyListDecoder().decode(FoodEntryDraftArchive.self, from: Data(contentsOf: url))
        guard archive.version == 1 else { throw FoodEntryDraftStoreError.unsupportedVersion }
        return archive
    }

    private func writeArchive(_ archive: FoodEntryDraftArchive) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(archive)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

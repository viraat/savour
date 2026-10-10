import CloudKit
import Combine
import CoreData
import Foundation

enum FoodCloudSyncConfiguration {
    static let enabledKey = "savourCloudSyncEnabled"
    static let bundleIdentifier = "tech.buildboring.Savour"
    static let containerIdentifier = "iCloud.tech.buildboring.Savour"
    static let transactionAuthor = "Savour.app"

    // Tests, previews and the old signing identity must never contact iCloud.
    static func shouldSync(requested: Bool, bundleID: String?, isolatedStore: Bool) -> Bool {
        requested && bundleID == bundleIdentifier && !isolatedStore
    }

    static func configure(_ description: NSPersistentStoreDescription, syncEnabled: Bool) {
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        if syncEnabled {
            let options = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
            options.databaseScope = .private
            description.cloudKitContainerOptions = options
        } else {
            // NSPersistentCloudKitContainer otherwise infers the first entitlement.
            description.cloudKitContainerOptions = nil
        }
    }
}

/// Status, not a manual sync engine. Apple schedules transfers and retries.
/// No journal contents, account identifiers or CloudKit errors are displayed.
@MainActor
final class FoodCloudSyncMonitor: ObservableObject {
    static let shared = FoodCloudSyncMonitor()
    @Published private(set) var enabledForThisLaunch = false
    @Published private(set) var accountStatus: CKAccountStatus = .couldNotDetermine
    @Published private(set) var checkingAccount = false
    @Published private(set) var activeEvents = Set<UUID>()
    @Published private(set) var lastTransfer: Date?
    @Published private(set) var issue: String?
    private var observations = [NSObjectProtocol]()
    private var accountRequest = UUID()

    func observe(_ container: NSPersistentContainer, enabled: Bool) {
        observations.forEach(NotificationCenter.default.removeObserver)
        observations.removeAll()
        enabledForThisLaunch = enabled
        activeEvents.removeAll()
        issue = nil
        guard enabled, container is NSPersistentCloudKitContainer else { return }
        observations.append(NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container, queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
            Task { @MainActor in self?.receive(event) }
        })
        observations.append(NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshAccount() }
        })
    }

    func refreshAccount() async {
        guard enabledForThisLaunch, !checkingAccount else { return }
        let request = UUID()
        accountRequest = request
        checkingAccount = true
        defer { if accountRequest == request { checkingAccount = false } }
        do {
            let status = try await CKContainer(identifier: FoodCloudSyncConfiguration.containerIdentifier).accountStatus()
            guard accountRequest == request else { return }
            accountStatus = status
        } catch {
            accountStatus = .couldNotDetermine
        }
    }

    private func receive(_ event: NSPersistentCloudKitContainer.Event) {
        if event.endDate == nil {
            activeEvents.insert(event.identifier)
        } else {
            activeEvents.remove(event.identifier)
            if event.succeeded {
                if event.type == .import || event.type == .export {
                    lastTransfer = max(lastTransfer ?? .distantPast, event.endDate ?? Date())
                    issue = nil
                }
            } else {
                issue = Self.message(for: event.error)
            }
        }
    }

    static func message(for error: Error?) -> String {
        let error = error as NSError?
        if error?.domain == CKErrorDomain, let code = error.flatMap({ CKError.Code(rawValue: $0.code) }) {
            switch code {
            case .quotaExceeded: return "iCloud storage is full. Your meals are still saved on this device."
            case .notAuthenticated: return "Sign in to iCloud in Settings to resume syncing."
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
                return "Waiting for iCloud. Sync will retry automatically."
            default: break
            }
        }
        return "iCloud couldn't sync. Your meals are still saved on this device."
    }

    var status: String {
        if !enabledForThisLaunch { return "Off" }
        if checkingAccount { return "Checking iCloud…" }
        switch accountStatus {
        case .noAccount: return "Not signed in to iCloud"
        case .restricted: return "iCloud access is restricted"
        case .temporarilyUnavailable: return "iCloud is temporarily unavailable"
        case .couldNotDetermine: return "Waiting for iCloud"
        case .available:
            if !activeEvents.isEmpty { return "Syncing…" }
            return issue == nil ? "iCloud sync enabled" : "Sync paused"
        @unknown default: return "Waiting for iCloud"
        }
    }
}

/// Merge remote object-ID changes without refreshing/resetting the UI context,
/// which would discard pending edits. The cursor is per launch: initial fetches
/// already see the complete store, so old history need not be replayed on launch.
final class FoodCloudHistoryMerger {
    private let worker: NSManagedObjectContext
    private let viewContext: NSManagedObjectContext
    private weak var cloudContainer: NSPersistentCloudKitContainer?
    private let startedAt = Date()
    private var token: NSPersistentHistoryToken?
    private var observation: NSObjectProtocol?
    private var exportObservation: NSObjectProtocol?

    init(container: NSPersistentCloudKitContainer) {
        cloudContainer = container
        viewContext = container.viewContext
        worker = container.newBackgroundContext()
        worker.transactionAuthor = "Savour.cloud-repair"
        worker.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        observation = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator, queue: nil
        ) { [weak self] _ in self?.processChanges() }
        exportObservation = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container, queue: nil
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event,
                  event.type == .export, event.endDate != nil, event.succeeded else { return }
            // A local copy may not have a stable CloudKit record ID until export.
            self?.processChanges()
        }
    }

    deinit {
        if let observation { NotificationCenter.default.removeObserver(observation) }
        if let exportObservation { NotificationCenter.default.removeObserver(exportObservation) }
    }

    func processChanges(completion: (() -> Void)? = nil) {
        worker.perform { [weak self] in
            guard let self else { return }
            defer { if let completion { self.viewContext.perform(completion) } }
            do {
                let request = self.token.map { NSPersistentHistoryChangeRequest.fetchHistory(after: $0) }
                    ?? NSPersistentHistoryChangeRequest.fetchHistory(after: self.startedAt)
                request.resultType = .transactionsAndChanges
                let result = try self.worker.execute(request) as? NSPersistentHistoryResult
                let transactions = result?.result as? [NSPersistentHistoryTransaction] ?? []
                let changes = transactions.filter { $0.author != FoodCloudSyncConfiguration.transactionAuthor }
                    .map { $0.objectIDNotification().userInfo ?? [:] }
                self.viewContext.perform { [weak self] in
                    guard let self else { return }
                    for info in changes {
                        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: info, into: [self.viewContext])
                    }
                }
                if let token = transactions.last?.token { self.token = token }
                // Native mirroring doesn't support UUID uniqueness constraints.
                // Coalesce only complete, identical graphs, never conflicting edits.
                if let container = self.cloudContainer {
                    try FoodCloudDuplicateRepair.coalesceIdenticalEntries(in: self.worker) {
                        container.recordID(for: $0)?.recordName
                    }
                }
            } catch {
                self.worker.rollback()
                // Keep the cursor retryable. Do not remove history: CloudKit uses it.
                NSLog("Savour could not merge iCloud changes: %@", error.localizedDescription)
            }
        }
    }
}

enum FoodCloudDuplicateRepair {
    /// A stable CloudKit record name, not a device-specific Core Data object ID,
    /// makes every device pick the same survivor. Missing cloud IDs defer repair.
    @discardableResult
    static func coalesceIdenticalEntries(in context: NSManagedObjectContext,
                                        recordName: (NSManagedObjectID) -> String?) throws -> Int {
        let request = NSFetchRequest<NSDictionary>(entityName: "FoodEntry")
        request.resultType = .dictionaryResultType
        let objectID = NSExpressionDescription()
        objectID.name = "objectID"
        objectID.expression = NSExpression.expressionForEvaluatedObject()
        objectID.expressionResultType = .objectIDAttributeType
        request.propertiesToFetch = ["id", objectID]
        let rows = try context.fetch(request)
        var grouped = [UUID: [NSManagedObjectID]]()
        for row in rows {
            if let id = row["id"] as? UUID, let objectID = row["objectID"] as? NSManagedObjectID {
                grouped[id, default: []].append(objectID)
            }
        }
        var removed = 0
        for ids in grouped.values where ids.count > 1 {
            let named = ids.compactMap { id in recordName(id).map { (id, $0) } }
            guard named.count == ids.count else { continue }
            let objects = try named.sorted { $0.1 < $1.1 }.map { try context.existingObject(with: $0.0) }
            guard let keeper = objects.first, complete(keeper) else { continue }
            for candidate in objects.dropFirst() where complete(candidate) && identical(keeper, candidate) {
                // Independent CSV imports assign different creation times for
                // the same exported UUID. Retain the earliest known timestamp.
                let dates = [keeper, candidate].compactMap { $0.value(forKey: "createdAt") as? Date }
                if let firstCreated = dates.min() { keeper.setValue(firstCreated, forKey: "createdAt") }
                context.delete(candidate)
                removed += 1
            }
        }
        if context.hasChanges { try context.save() }
        return removed
    }

    private static func companions(_ object: NSManagedObject) -> [NSManagedObject] {
        (object.value(forKey: "companions") as? Set<NSManagedObject> ?? []).sorted {
            (($0.value(forKey: "id") as? UUID)?.uuidString ?? "") < (($1.value(forKey: "id") as? UUID)?.uuidString ?? "")
        }
    }

    private static func complete(_ object: NSManagedObject) -> Bool {
        guard object.value(forKey: "id") != nil, object.value(forKey: "date") != nil,
              object.value(forKey: "food") != nil else { return false }
        let linked = companions(object)
        let people = (object.value(forKey: "people") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !people.isEmpty && linked.isEmpty { return false }
        return linked.allSatisfy { $0.value(forKey: "id") != nil && $0.value(forKey: "name") != nil }
    }

    private static func sameAttributes(_ lhs: NSManagedObject, _ rhs: NSManagedObject, ignoring: Set<String> = []) -> Bool {
        lhs.entity.attributesByName.keys.filter { !ignoring.contains($0) }.allSatisfy { key in
            let a = lhs.value(forKey: key) as? NSObject
            let b = rhs.value(forKey: key) as? NSObject
            return a == b
        }
    }

    private static func identical(_ lhs: NSManagedObject, _ rhs: NSManagedObject) -> Bool {
        guard sameAttributes(lhs, rhs, ignoring: ["createdAt"]) else { return false }
        let a = companions(lhs), b = companions(rhs)
        return a.count == b.count && zip(a, b).allSatisfy { sameAttributes($0.0, $0.1) }
    }
}

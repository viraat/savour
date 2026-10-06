import CoreData

/// Store-local gate for the legacy data repair, separate from Core Data's
/// automatic schema migration. Bump the version when a new repair is needed.
enum FoodStoreMigration {
    static let metadataKey = "com.viraat.foodlog.legacyEntryMigrationVersion"
    static let currentVersion = 1

    enum MarkerError: Error { case missingPersistentStore }

    /// Call on the context's queue before presenting the journal. A successful
    /// repair is saved before the completion marker is persisted. No entry fetch
    /// or context save occurs when the loaded store already has the marker.
    @discardableResult
    static func runIfNeeded(in context: NSManagedObjectContext, store: NSPersistentStore,
                            version: Int = currentVersion, migrate: () throws -> Void) throws -> Bool {
        guard let coordinator = context.persistentStoreCoordinator,
              coordinator.persistentStores.contains(where: { $0 === store }) else {
            throw MarkerError.missingPersistentStore
        }
        let existingMetadata = coordinator.metadata(for: store)
        if let completedVersion = existingMetadata[metadataKey] as? Int,
           completedVersion >= version { return false }

        // Never stamp a failed or unsaved repair as complete.
        try migrate()
        try context.save()

        let originalMetadata = coordinator.metadata(for: store)
        var completedMetadata = originalMetadata
        completedMetadata[metadataKey] = version
        coordinator.setMetadata(completedMetadata, for: store)
        do {
            // A clean context's save can be a no-op. Explicitly execute an empty
            // store save to flush metadata even for an empty/already-repaired
            // journal, without modifying any food object or creating a dummy row.
            let request = NSSaveChangesRequest(inserted: nil, updated: nil, deleted: nil, locked: nil)
            request.affectedStores = [store]
            _ = try coordinator.execute(request, with: context)
        } catch {
            // Do not let a cached, unpersisted marker suppress a same-run retry.
            coordinator.setMetadata(originalMetadata, for: store)
            throw error
        }
        return true
    }
}

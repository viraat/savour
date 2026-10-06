import Combine
import CoreData
import Foundation

/// One bounded, view-owned snapshot. UI-only changes reuse it; journal changes
/// invalidate it, including companion edits, undo/rollback and imported data.
@MainActor
final class FoodHistoryCache<Key: Equatable, Value>: ObservableObject {
    @Published private(set) var revision = 0
    private var storedKey: Key?
    private var storedValue: Value?
    private weak var observedContext: NSManagedObjectContext?
    private var observation: AnyCancellable?

    func value(for key: Key, build: () -> Value) -> Value {
        if storedKey == key, let storedValue { return storedValue }
        let value = build()
        storedKey = key
        storedValue = value
        return value
    }

    func observe(_ context: NSManagedObjectContext) {
        precondition(context.concurrencyType == .mainQueueConcurrencyType)
        guard observedContext !== context else { return }
        observedContext = context
        observation = NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange, object: context
        ).sink { [weak self] notification in
            // This observer is attached only to the UI's main-queue context.
            if Self.affectsMeals(notification) { self?.invalidate() }
        }
        invalidate()
    }

    func invalidate() {
        guard storedValue != nil else { return }
        storedKey = nil
        storedValue = nil
        revision &+= 1
    }

    private static func affectsMeals(_ notification: Notification) -> Bool {
        guard let info = notification.userInfo else { return false }
        if info[NSInvalidatedAllObjectsKey] != nil { return true }
        return [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey,
                NSRefreshedObjectsKey, NSInvalidatedObjectsKey].contains { key in
            let objects = info[key] as? Set<NSManagedObject> ?? []
            return objects.contains { ["FoodEntry", "FoodEntryCompanion"].contains($0.entity.name ?? "") }
        }
    }
}

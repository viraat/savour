import Combine
import CoreData
import CoreGraphics
import Foundation
import ImageIO

struct FoodPhotoThumbnailKey: Hashable {
    let version: UUID
    let width: Int
    let height: Int

    init(version: UUID, width: Double, height: Double) {
        self.version = version
        self.width = Self.pixels(width)
        self.height = Self.pixels(height)
    }

    private static func pixels(_ value: Double) -> Int {
        guard value.isFinite else { return 1 }
        return Int(min(2_048, max(1, ceil(value))))
    }

    fileprivate var cacheKey: NSString { "\(version.uuidString):\(width)x\(height)" as NSString }
}

enum FoodPhotoDownsampling {
    // ImageIO reads dimensions without first expanding the full-resolution JPEG.
    // Size for aspect-fill, including EXIF rotation, and cap extreme panoramas.
    static func image(data: Data, width: Int, height: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData,
                                                       [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let sourceWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let sourceHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let rotated = (5...8).contains(orientation)
        let w = rotated ? sourceHeight.doubleValue : sourceWidth.doubleValue
        let h = rotated ? sourceWidth.doubleValue : sourceHeight.doubleValue
        guard w > 0, h > 0, w.isFinite, h.isFinite else { return nil }
        let ratio = min(1, max(Double(max(1, width)) / w, Double(max(1, height)) / h))
        let maximum = min(2_048, max(1, ceil(max(w, h) * ratio)))
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximum,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
}

enum FoodEntryPhotoData {
    /// Read committed photos on a private Core Data queue, not into the journal's
    /// long-lived managed objects. Unsaved photos stay on their owning queue.
    @MainActor
    static func read(from entry: NSManagedObject) async -> Data? {
        guard !entry.isDeleted, let context = entry.managedObjectContext else { return nil }
        if entry.isInserted || entry.objectID.isTemporaryID || context.parent != nil
            || entry.changedValues().keys.contains("photoData") {
            return entry.value(forKey: "photoData") as? Data
        }
        guard let coordinator = context.persistentStoreCoordinator else { return nil }
        let id = entry.objectID
        let reader = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        reader.persistentStoreCoordinator = coordinator
        return await reader.perform {
            defer { reader.reset() }
            guard let stored = try? reader.existingObject(with: id) else { return nil }
            return stored.value(forKey: "photoData") as? Data
        }
    }

    /// One ID-only query, including unsaved changes, so photo-less rows never
    /// read the store or occupy preview-cache slots. Photo bytes are not loaded.
    static func entryIDsWithPhotos(in context: NSManagedObjectContext) -> Set<NSManagedObjectID> {
        let request = NSFetchRequest<NSManagedObjectID>(entityName: "FoodEntry")
        request.resultType = .managedObjectIDResultType
        request.predicate = NSPredicate(format: "photoData != nil")
        return Set((try? context.fetch(request)) ?? [])
    }
}

/// Only decoded previews are cached, never the original photo data. Actor-owned
/// cache access coalesces simultaneous requests; ImageIO runs on a utility task.
actor FoodPhotoThumbnailCache {
    static let shared = FoodPhotoThumbnailCache()
    private final class CachedPhoto: @unchecked Sendable {
        let image: CGImage?
        init(_ image: CGImage?) { self.image = image }
    }
    private struct Pending {
        let id: UUID
        let task: Task<CGImage?, Never>
    }
    // NSCache is thread-safe; the actor still owns pending work and generations.
    private nonisolated(unsafe) let cache = NSCache<NSString, CachedPhoto>()
    private var pending: [FoodPhotoThumbnailKey: Pending] = [:]
    private var generation = 0

    init(byteLimit: Int = 24 * 1_024 * 1_024, countLimit: Int = 200) {
        cache.totalCostLimit = byteLimit
        cache.countLimit = countLimit
    }

    /// Synchronous lookup for the first rendered frame; never reads or decodes.
    nonisolated func cachedImage(for key: FoodPhotoThumbnailKey) -> CGImage? {
        cache.object(forKey: key.cacheKey)?.image
    }

    func thumbnail(for key: FoodPhotoThumbnailKey,
                   loadData: @escaping @MainActor @Sendable () async -> Data?) async -> CGImage? {
        if let cached = cache.object(forKey: key.cacheKey) { return cached.image }
        let currentGeneration = generation
        let request: Pending
        if let existing = pending[key] {
            request = existing
        } else {
            let task = Task.detached(priority: .utility) { () -> CGImage? in
                guard !Task.isCancelled, let data = await loadData(), !Task.isCancelled else { return nil }
                return autoreleasepool { FoodPhotoDownsampling.image(data: data, width: key.width, height: key.height) }
            }
            request = Pending(id: UUID(), task: task)
            pending[key] = request
        }
        let image = await request.task.value
        guard generation == currentGeneration else { return nil }
        if pending[key]?.id == request.id {
            pending[key] = nil
            cache.setObject(CachedPhoto(image), forKey: key.cacheKey,
                            cost: image.map { $0.bytesPerRow * $0.height } ?? 1)
        }
        return image
    }

    func removeAll() {
        generation &+= 1
        cache.removeAllObjects()
        for request in pending.values { request.task.cancel() }
        pending.removeAll()
    }
}

/// Weak entry keys keep versions stable across row recreation without retaining
/// entries/photos. The version changes only for photo edits or refresh/reset,
/// so a cache hit needs neither photoData nor a hash of the original JPEG.
@MainActor
final class FoodPhotoVersions: ObservableObject {
    static let shared = FoodPhotoVersions()
    @Published private(set) var revision = 0
    private let versions = NSMapTable<NSManagedObject, NSUUID>.weakToStrongObjects()
    private weak var observedContext: NSManagedObjectContext?
    private var observation: AnyCancellable?

    func version(for entry: NSManagedObject) -> UUID {
        if let existing = versions.object(forKey: entry) { return existing as UUID }
        let version = UUID()
        versions.setObject(version as NSUUID, forKey: entry)
        return version
    }

    func observe(_ context: NSManagedObjectContext) {
        precondition(context.concurrencyType == .mainQueueConcurrencyType)
        guard observedContext !== context else { return }
        if observedContext != nil { invalidateAll() }
        observedContext = context
        observation = NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange, object: context
        ).sink { [weak self] notification in self?.objectsChanged(notification) }
    }

    private func invalidateAll() {
        versions.removeAllObjects()
        revision &+= 1
        // New versions make old previews unreachable. Let the cache budget
        // evict them rather than racing new view requests with an async purge.
    }

    private func objectsChanged(_ notification: Notification) {
        guard let info = notification.userInfo else { return }
        if info[NSInvalidatedAllObjectsKey] != nil { invalidateAll(); return }
        var affected = Set<NSManagedObject>()
        for key in [NSDeletedObjectsKey, NSRefreshedObjectsKey, NSInvalidatedObjectsKey] {
            affected.formUnion(info[key] as? Set<NSManagedObject> ?? [])
        }
        for entry in info[NSUpdatedObjectsKey] as? Set<NSManagedObject> ?? [] {
            // A merged store update can lack local changed-value details.
            // Invalidate conservatively rather than showing an old photo.
            let changes = entry.changedValuesForCurrentEvent()
            if changes.isEmpty || changes.keys.contains("photoData") {
                affected.insert(entry)
            }
        }
        let meals = affected.filter { $0.entity.name == "FoodEntry" }
        guard !meals.isEmpty else { return }
        for meal in meals { versions.removeObject(forKey: meal) }
        revision &+= 1
    }
}

#if canImport(UIKit)
import SwiftUI
import UIKit

private struct LoadedPreview {
    let key: FoodPhotoThumbnailKey
    let image: UIImage
}

struct FoodJournalPhoto: View {
    @ObservedObject var entry: FoodEntry
    /// From the journal's ID-only photo query; false skips reads and the cache.
    let hasPhoto: Bool
    @ObservedObject private var versions = FoodPhotoVersions.shared
    @Environment(\.displayScale) private var displayScale
    @State private var loaded: LoadedPreview?

    private var key: FoodPhotoThumbnailKey {
        FoodPhotoThumbnailKey(version: versions.version(for: entry),
                              width: 42 * displayScale, height: 42 * displayScale)
    }

    /// A cached preview renders on the first frame. While a changed photo
    /// decodes, the previous preview stays visible instead of the meal icon.
    private var image: UIImage? {
        guard hasPhoto else { return nil }
        let key = key
        if let loaded, loaded.key == key { return loaded.image }
        if let cached = FoodPhotoThumbnailCache.shared.cachedImage(for: key) {
            return UIImage(cgImage: cached, scale: displayScale, orientation: .up)
        }
        return loaded?.image
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .accessibilityLabel("Photo of \(entry.wrappedFood)")
            } else {
                Image(systemName: FoodTheme.symbol(for: entry.wrappedMealType))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(FoodTheme.color(for: entry.wrappedMealType))
                    .frame(width: 42, height: 42)
                    .background(FoodTheme.color(for: entry.wrappedMealType).opacity(0.16))
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .task(id: hasPhoto ? key : nil) {
            guard hasPhoto else { loaded = nil; return }
            if let context = entry.managedObjectContext { versions.observe(context) }
            let requestKey = key
            if let cached = FoodPhotoThumbnailCache.shared.cachedImage(for: requestKey) {
                loaded = LoadedPreview(key: requestKey,
                                       image: UIImage(cgImage: cached, scale: displayScale, orientation: .up))
                return
            }
            let result = await FoodPhotoThumbnailCache.shared.thumbnail(for: requestKey) {
                await FoodEntryPhotoData.read(from: entry)
            }
            guard !Task.isCancelled, requestKey == key, !entry.isDeleted else { return }
            loaded = result.map {
                LoadedPreview(key: requestKey, image: UIImage(cgImage: $0, scale: displayScale, orientation: .up))
            }
        }
        // Offscreen rows release their preview; the cache restores it on return.
        .onDisappear { loaded = nil }
    }
}

struct FoodEditorPhoto: View {
    let data: Data
    /// The entry's photo version when `data` is its saved photo. Only those
    /// previews can be requested again, so only they use the shared cache.
    let savedVersion: UUID?
    @Environment(\.displayScale) private var displayScale
    @State private var unsavedVersion = UUID()
    @State private var loaded: LoadedPreview?

    private func image(for key: FoodPhotoThumbnailKey) -> UIImage? {
        if let loaded, loaded.key == key { return loaded.image }
        if savedVersion != nil, let cached = FoodPhotoThumbnailCache.shared.cachedImage(for: key) {
            return UIImage(cgImage: cached, scale: displayScale, orientation: .up)
        }
        return loaded?.image
    }

    var body: some View {
        GeometryReader { geometry in
            let key = FoodPhotoThumbnailKey(version: savedVersion ?? unsavedVersion,
                                            width: geometry.size.width * displayScale,
                                            height: 190 * displayScale)
            Group {
                if let image = image(for: key) { Image(uiImage: image).resizable().scaledToFill() }
                else { Color.clear }
            }
            .frame(width: geometry.size.width, height: 190)
            .clipped()
            .task(id: key) {
                let result: CGImage?
                if savedVersion != nil {
                    result = await FoodPhotoThumbnailCache.shared.thumbnail(for: key) { data }
                } else {
                    let data = data
                    result = await Task.detached(priority: .userInitiated) {
                        autoreleasepool { FoodPhotoDownsampling.image(data: data, width: key.width, height: key.height) }
                    }.value
                }
                guard !Task.isCancelled else { return }
                loaded = result.map {
                    LoadedPreview(key: key, image: UIImage(cgImage: $0, scale: displayScale, orientation: .up))
                }
            }
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel("Entry photo")
        // A replacement keeps the previous preview visible until it decodes.
        .onChange(of: data) { _, _ in unsavedVersion = UUID() }
        .onDisappear { loaded = nil }
    }
}
#endif

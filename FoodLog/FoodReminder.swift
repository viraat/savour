import Combine
import Foundation
import UserNotifications

enum FoodReminderTime: String, CaseIterable, Identifiable {
    case morning, evening, custom
    var id: String { rawValue }

    func minutes(custom: Int) -> Int {
        switch self {
        case .morning: return 8 * 60
        case .evening: return 20 * 60
        case .custom: return FoodReminderSchedule.validMinutes(custom)
        }
    }
}

enum FoodReminderSchedule {
    static let identifier = "com.viraat.foodlog.daily-reminder"
    static let enabledKey = "foodLogDailyReminderEnabled"
    static let timeKey = "foodLogDailyReminderTime"
    static let customMinutesKey = "foodLogDailyReminderCustomMinutes"
    static let timesKey = "foodLogDailyReminderTimes"
    static let maximumCount = 3
    static let identifiers = [identifier, identifier + ".2", identifier + ".3"]

    static func normalizedTimes(_ times: [Int]) -> [Int] {
        var result: [Int] = []
        for time in times where (0..<1_440).contains(time) && !result.contains(time) {
            result.append(time)
            if result.count == maximumCount { break }
        }
        return result.isEmpty ? [480] : result
    }

    static func validMinutes(_ minutes: Int) -> Int {
        (0..<1_440).contains(minutes) ? minutes : 8 * 60
    }

    static func request(minutes: Int, slot: Int = 0) -> UNNotificationRequest {
        let minutes = validMinutes(minutes)
        // Only local clock components: no fixed date, UTC offset or time zone.
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let content = UNMutableNotificationContent()
        content.title = "Savour"
        content.body = "A moment to note your meals."
        content.sound = .default
        // Never include journal/draft details, even when App Lock is disabled.
        return UNNotificationRequest(identifier: identifiers[slot], content: content, trigger: trigger)
    }
}

@MainActor
protocol FoodReminderPreferences {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: FoodReminderPreferences {}

@MainActor
protocol FoodReminderNotificationCenter {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removeReminders(identifiers: [String])
}

@MainActor
final class FoodSystemReminderNotificationCenter: FoodReminderNotificationCenter {
    private let center = UNUserNotificationCenter.current()

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func removeReminders(identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

@MainActor
final class FoodDailyReminder: ObservableObject {
    static let shared: FoodDailyReminder = {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let suite = "FoodLogReminderUITests"
            let preferences = UserDefaults(suiteName: suite)!
            if ProcessInfo.processInfo.arguments.contains("--reset-ui-test-store") {
                preferences.removePersistentDomain(forName: suite)
            }
            return FoodDailyReminder(preferences: preferences,
                notifications: FoodUITestReminderNotificationCenter(preferences: preferences))
        }
#endif
        return FoodDailyReminder(preferences: UserDefaults.standard,
            notifications: FoodSystemReminderNotificationCenter())
    }()

    @Published private(set) var isEnabled: Bool
    @Published private(set) var times: [Int]
    @Published private(set) var permission: UNAuthorizationStatus = .notDetermined
    @Published private(set) var isUpdating = false
    @Published private(set) var errorMessage: String?

    private let preferences: FoodReminderPreferences
    private let notifications: FoodReminderNotificationCenter
    private var operationTail: Task<Void, Never>?
    private var pendingOperations = 0

    init(preferences: FoodReminderPreferences, notifications: FoodReminderNotificationCenter) {
        self.preferences = preferences
        self.notifications = notifications
        isEnabled = preferences.object(forKey: FoodReminderSchedule.enabledKey) as? Bool ?? false
        if let saved = preferences.object(forKey: FoodReminderSchedule.timesKey) as? [Int] {
            times = FoodReminderSchedule.normalizedTimes(saved)
        } else {
            // Upgrade the single-reminder preference without opting into extra times.
            // Slot zero reuses its original notification identifier.
            let choice = FoodReminderTime(rawValue: preferences.object(forKey: FoodReminderSchedule.timeKey) as? String ?? "") ?? .morning
            let custom = preferences.object(forKey: FoodReminderSchedule.customMinutesKey) as? Int ?? 480
            times = [choice.minutes(custom: custom)]
        }
        preferences.set(times, forKey: FoodReminderSchedule.timesKey)
    }

    // Serialize system callbacks and lifecycle reconciliation. A slow permission
    // request or scheduling callback cannot overwrite a later Disable/time edit.
    private func enqueue(_ operation: @escaping @MainActor () async -> Void) async {
        let previous = operationTail
        pendingOperations += 1
        isUpdating = true
        let task = Task { @MainActor in
            await previous?.value
            await operation()
            pendingOperations -= 1
            isUpdating = pendingOperations > 0
        }
        operationTail = task
        await task.value
    }

    func refresh() async {
        await enqueue {
            self.permission = await self.notifications.authorizationStatus()
            guard self.isEnabled else { self.removeAllReminders(); return }
            guard self.canNotify else { self.disable(); return }
            do {
                try await self.scheduleAll()
                self.errorMessage = nil
            } catch {
                self.disable()
                self.errorMessage = "Couldn’t schedule reminders. Please try again."
            }
        }
    }

    func setEnabled(_ enabled: Bool) async {
        await enqueue {
            self.errorMessage = nil
            guard enabled else { self.disable(); return }
            self.permission = await self.notifications.authorizationStatus()
            do {
                if self.permission == .notDetermined {
                    _ = try await self.notifications.requestAuthorization()
                    self.permission = await self.notifications.authorizationStatus()
                }
                guard self.canNotify else { self.disable(); return }
                try await self.scheduleAll()
                self.isEnabled = true
                self.preferences.set(true, forKey: FoodReminderSchedule.enabledKey)
            } catch {
                self.disable()
                self.errorMessage = "Couldn’t enable reminders. Please try again."
            }
        }
    }

    func addReminder() async {
        await update { times in
            guard times.count < FoodReminderSchedule.maximumCount,
                  let next = [480, 780, 1_200].first(where: { !times.contains($0) }) else { return times }
            return times + [next]
        }
    }

    func setMinutes(_ minutes: Int, at index: Int) async {
        await update { times in
            guard times.indices.contains(index) else { return times }
            guard (0..<1_440).contains(minutes) else { throw TimeError.invalid }
            guard !times.enumerated().contains(where: { $0.offset != index && $0.element == minutes }) else {
                throw TimeError.duplicate
            }
            var result = times
            result[index] = minutes
            return result
        }
    }

    func removeReminders(at offsets: IndexSet) async {
        await update { times in
            let remaining = times.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
            return remaining.isEmpty ? times : remaining
        }
    }

    private enum TimeError: Error { case invalid, duplicate }

    private func update(_ transform: @escaping ([Int]) throws -> [Int]) async {
        await enqueue {
            self.errorMessage = nil
            let desired: [Int]
            do { desired = try transform(self.times) }
            catch {
                self.errorMessage = "Choose a different valid time for each reminder."
                return
            }
            guard desired != self.times else { return }
            if self.isEnabled {
                self.permission = await self.notifications.authorizationStatus()
                if !self.canNotify { self.disable() }
                else {
                    do {
                        try await self.replaceSchedule(with: desired)
                    } catch {
                        self.errorMessage = self.isEnabled
                            ? "Couldn’t change reminders. Your previous times are unchanged."
                            : "Couldn’t change reminders. Notifications are off; please try again."
                        return
                    }
                }
            }
            self.times = desired
            self.preferences.set(desired, forKey: FoodReminderSchedule.timesKey)
        }
    }

    private func scheduleAll() async throws {
        for (slot, minutes) in times.enumerated() {
            try await notifications.add(FoodReminderSchedule.request(minutes: minutes, slot: slot))
        }
        notifications.removeReminders(identifiers: Array(FoodReminderSchedule.identifiers.dropFirst(times.count)))
    }

    private func replaceSchedule(with desired: [Int]) async throws {
        var changed: [Int] = []
        do {
            for (slot, minutes) in desired.enumerated() where !times.indices.contains(slot) || times[slot] != minutes {
                try await notifications.add(FoodReminderSchedule.request(minutes: minutes, slot: slot))
                changed.append(slot)
            }
        } catch {
            // Multi-request changes can fail partway through. Restore replaced
            // slots and cancel new slots; if restoration fails, turn all off.
            for slot in changed {
                if times.indices.contains(slot) {
                    do { try await notifications.add(FoodReminderSchedule.request(minutes: times[slot], slot: slot)) }
                    catch { disable(); break }
                } else {
                    notifications.removeReminders(identifiers: [FoodReminderSchedule.identifiers[slot]])
                }
            }
            throw error
        }
        notifications.removeReminders(identifiers: Array(FoodReminderSchedule.identifiers.dropFirst(desired.count)))
    }

    private var canNotify: Bool {
        if permission == .authorized || permission == .provisional { return true }
#if os(iOS)
        return permission == .ephemeral
#else
        return false
#endif
    }

    private func disable() {
        removeAllReminders()
        isEnabled = false
        preferences.set(false, forKey: FoodReminderSchedule.enabledKey)
    }

    private func removeAllReminders() {
        notifications.removeReminders(identifiers: FoodReminderSchedule.identifiers)
    }
}

#if DEBUG
/// UI tests never request actual permission or leave real reminders behind.
@MainActor
private final class FoodUITestReminderNotificationCenter: FoodReminderNotificationCenter {
    private let preferences: UserDefaults
    private let permissionKey = "foodLogReminderUITestPermission"
    private var status: UNAuthorizationStatus
    init(preferences: UserDefaults) {
        self.preferences = preferences
        status = UNAuthorizationStatus(rawValue: preferences.integer(forKey: permissionKey)) ?? .notDetermined
    }
    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async throws -> Bool {
        status = ProcessInfo.processInfo.arguments.contains("--simulate-notifications-denied") ? .denied : .authorized
        preferences.set(status.rawValue, forKey: permissionKey)
        return status == .authorized
    }
    func add(_ request: UNNotificationRequest) async throws {}
    func removeReminders(identifiers: [String]) {}
}
#endif

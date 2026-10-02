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

    static func validMinutes(_ minutes: Int) -> Int {
        (0..<1_440).contains(minutes) ? minutes : 8 * 60
    }

    static func request(minutes: Int) -> UNNotificationRequest {
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
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
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
    func removeReminder()
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

    func removeReminder() {
        let identifiers = [FoodReminderSchedule.identifier]
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
    @Published private(set) var time: FoodReminderTime
    @Published private(set) var customMinutes: Int
    @Published private(set) var permission: UNAuthorizationStatus = .notDetermined
    @Published private(set) var isUpdating = false
    @Published private(set) var errorMessage: String?

    var scheduledMinutes: Int { time.minutes(custom: customMinutes) }
    private let preferences: FoodReminderPreferences
    private let notifications: FoodReminderNotificationCenter
    private var operationTail: Task<Void, Never>?
    private var pendingOperations = 0

    init(preferences: FoodReminderPreferences, notifications: FoodReminderNotificationCenter) {
        self.preferences = preferences
        self.notifications = notifications
        isEnabled = preferences.object(forKey: FoodReminderSchedule.enabledKey) as? Bool ?? false
        time = FoodReminderTime(rawValue: preferences.object(forKey: FoodReminderSchedule.timeKey) as? String ?? "") ?? .morning
        customMinutes = FoodReminderSchedule.validMinutes(
            preferences.object(forKey: FoodReminderSchedule.customMinutesKey) as? Int ?? 8 * 60)
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
            guard self.isEnabled else { self.notifications.removeReminder(); return }
            guard self.canNotify else { self.disable(); return }
            do {
                try await self.notifications.add(FoodReminderSchedule.request(minutes: self.scheduledMinutes))
                self.errorMessage = nil
            } catch {
                self.disable()
                self.errorMessage = "Couldn’t schedule the reminder. Please try again."
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
                try await self.notifications.add(FoodReminderSchedule.request(minutes: self.scheduledMinutes))
                self.isEnabled = true
                self.preferences.set(true, forKey: FoodReminderSchedule.enabledKey)
            } catch {
                self.disable()
                self.errorMessage = "Couldn’t enable the reminder. Please try again."
            }
        }
    }

    func setTime(_ time: FoodReminderTime) async {
        await update(time: time, customMinutes: nil)
    }

    func setCustomMinutes(_ minutes: Int) async {
        await update(time: .custom, customMinutes: FoodReminderSchedule.validMinutes(minutes))
    }

    private func update(time: FoodReminderTime, customMinutes: Int?) async {
        await enqueue {
            self.errorMessage = nil
            let custom = customMinutes ?? self.customMinutes
            if self.isEnabled {
                self.permission = await self.notifications.authorizationStatus()
                if !self.canNotify { self.disable() }
                else {
                    do {
                        try await self.notifications.add(FoodReminderSchedule.request(minutes: time.minutes(custom: custom)))
                    } catch {
                        // Retain the old preference and pending notification.
                        self.errorMessage = "Couldn’t change the reminder time. Please try again."
                        return
                    }
                }
            }
            self.time = time
            self.customMinutes = custom
            self.preferences.set(time.rawValue, forKey: FoodReminderSchedule.timeKey)
            self.preferences.set(custom, forKey: FoodReminderSchedule.customMinutesKey)
        }
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
        notifications.removeReminder()
        isEnabled = false
        preferences.set(false, forKey: FoodReminderSchedule.enabledKey)
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
    func removeReminder() {}
}
#endif

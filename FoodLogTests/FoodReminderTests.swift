import Foundation
import UserNotifications
import XCTest
#if SWIFT_PACKAGE
@testable import FoodLogReminder
#else
@testable import FoodLog
#endif

@MainActor
final class FoodReminderTests: XCTestCase {
    func testDefaultIsOffAndRefreshNeverRequestsPermission() async {
        let preferences = MemoryReminderPreferences()
        let center = FakeReminderNotifications()
        let reminder = FoodDailyReminder(preferences: preferences, notifications: center)
        XCTAssertFalse(reminder.isEnabled)
        XCTAssertEqual(reminder.times, [480])
        await reminder.refresh()
        XCTAssertEqual(center.authorizationRequests, 0)
        XCTAssertTrue(center.pending.isEmpty)
    }

    func testLocalCalendarTriggerAndNotificationContentArePrivate() {
        for minutes in [0, 480, 1_200, 1_439] {
            let request = FoodReminderSchedule.request(minutes: minutes)
            let trigger = request.trigger as? UNCalendarNotificationTrigger
            XCTAssertEqual(request.identifier, FoodReminderSchedule.identifier)
            XCTAssertEqual(trigger?.dateComponents.hour, minutes / 60)
            XCTAssertEqual(trigger?.dateComponents.minute, minutes % 60)
            XCTAssertNil(trigger?.dateComponents.timeZone)
            XCTAssertNil(trigger?.dateComponents.calendar)
            XCTAssertNil(trigger?.dateComponents.day)
            XCTAssertNil(trigger?.dateComponents.year)
            XCTAssertEqual(trigger?.repeats, true)
            XCTAssertEqual(request.content.title, "Savour")
            XCTAssertEqual(request.content.body, "A moment to note your meals.")
            XCTAssertTrue(request.content.userInfo.isEmpty)
            XCTAssertTrue(request.content.attachments.isEmpty)
            XCTAssertNil(request.content.badge)
        }
    }

    func testEnablingRequestsPermissionOnceAndDisablingOnlyRemovesOurReminder() async {
        let preferences = MemoryReminderPreferences()
        let center = FakeReminderNotifications()
        center.pending["other-feature"] = UNNotificationRequest(identifier: "other-feature",
            content: UNMutableNotificationContent(), trigger: nil)
        center.delivered = Set(["other-feature"] + FoodReminderSchedule.identifiers)
        let reminder = FoodDailyReminder(preferences: preferences, notifications: center)
        await reminder.setEnabled(true)
        XCTAssertTrue(reminder.isEnabled)
        XCTAssertEqual(preferences.object(forKey: FoodReminderSchedule.enabledKey) as? Bool, true)
        await reminder.setEnabled(true)
        await reminder.addReminder()
        await reminder.addReminder()
        XCTAssertEqual(center.authorizationRequests, 1)
        XCTAssertEqual(center.pending.count, 4)
        await reminder.setEnabled(false)
        XCTAssertFalse(reminder.isEnabled)
        XCTAssertEqual(Set(center.pending.keys), ["other-feature"])
        XCTAssertEqual(center.delivered, ["other-feature"])
    }

    func testDeniedPermissionStaysOffAndDoesNotPromptAgain() async {
        let center = FakeReminderNotifications()
        center.grantPermission = false
        let reminder = FoodDailyReminder(preferences: MemoryReminderPreferences(), notifications: center)
        await reminder.setEnabled(true)
        XCTAssertEqual(reminder.permission, .denied)
        XCTAssertFalse(reminder.isEnabled)
        XCTAssertTrue(center.pending.isEmpty)
        await reminder.setEnabled(true)
        await reminder.refresh()
        XCTAssertEqual(center.authorizationRequests, 1)
    }

    func testConfiguringThreeTimesWhileOffDoesNotAskPermissionAndPersists() async {
        let preferences = MemoryReminderPreferences()
        let center = FakeReminderNotifications()
        let reminder = FoodDailyReminder(preferences: preferences, notifications: center)
        await reminder.setMinutes(777, at: 0)
        await reminder.addReminder()
        await reminder.addReminder()
        await reminder.setMinutes(1_200, at: 2)
        XCTAssertEqual(reminder.times, [777, 480, 1_200])
        XCTAssertEqual(center.authorizationRequests, 0)
        XCTAssertTrue(center.pending.isEmpty)
        let relaunched = FoodDailyReminder(preferences: preferences, notifications: center)
        XCTAssertEqual(relaunched.times, [777, 480, 1_200])
        XCTAssertFalse(relaunched.isEnabled)
    }

    func testTimeEditsAndRelaunchKeepExactlyOnePendingNotification() async {
        let preferences = MemoryReminderPreferences()
        let center = FakeReminderNotifications()
        let reminder = FoodDailyReminder(preferences: preferences, notifications: center)
        await reminder.setEnabled(true)
        await reminder.setMinutes(1_200, at: 0)
        await reminder.setMinutes(0, at: 0)
        XCTAssertEqual(center.pending.count, 1)
        XCTAssertEqual(center.trigger?.dateComponents.hour, 0)
        XCTAssertEqual(center.trigger?.dateComponents.minute, 0)
        let relaunched = FoodDailyReminder(preferences: preferences, notifications: center)
        await relaunched.refresh()
        XCTAssertTrue(relaunched.isEnabled)
        XCTAssertEqual(relaunched.times, [0])
        XCTAssertEqual(center.pending.count, 1)
        XCTAssertEqual(center.authorizationRequests, 1)
    }

    func testRevokedOrResetPermissionCancelsWithoutPromptOnRelaunch() async {
        for status: UNAuthorizationStatus in [.denied, .notDetermined] {
            let preferences = MemoryReminderPreferences()
            let center = FakeReminderNotifications()
            let reminder = FoodDailyReminder(preferences: preferences, notifications: center)
            await reminder.setEnabled(true)
            await reminder.addReminder()
            await reminder.addReminder()
            center.status = status
            let relaunched = FoodDailyReminder(preferences: preferences, notifications: center)
            await relaunched.refresh()
            XCTAssertFalse(relaunched.isEnabled)
            XCTAssertTrue(center.pending.isEmpty)
            XCTAssertEqual(center.authorizationRequests, 1)
            XCTAssertEqual(preferences.object(forKey: FoodReminderSchedule.enabledKey) as? Bool, false)
        }
    }

    func testProvisionalAuthorizationSchedulesWithoutAnotherRequest() async {
        let center = FakeReminderNotifications()
        center.status = .provisional
        let reminder = FoodDailyReminder(preferences: MemoryReminderPreferences(), notifications: center)
        await reminder.setEnabled(true)
        XCTAssertTrue(reminder.isEnabled)
        XCTAssertEqual(center.authorizationRequests, 0)
        XCTAssertEqual(center.pending.count, 1)
    }

    func testSchedulingAndPermissionFailuresNeverShowFalseEnabledState() async {
        for permissionFailure in [false, true] {
            let center = FakeReminderNotifications()
            center.failPermission = permissionFailure
            center.failScheduling = !permissionFailure
            let reminder = FoodDailyReminder(preferences: MemoryReminderPreferences(), notifications: center)
            await reminder.setEnabled(true)
            XCTAssertFalse(reminder.isEnabled)
            XCTAssertNotNil(reminder.errorMessage)
            XCTAssertTrue(center.pending.isEmpty)
        }
    }

    func testFailedTimeEditRetainsOriginalPreferenceAndNotification() async {
        let preferences = MemoryReminderPreferences()
        let center = FakeReminderNotifications()
        let reminder = FoodDailyReminder(preferences: preferences, notifications: center)
        await reminder.setEnabled(true)
        center.failScheduling = true
        await reminder.setMinutes(1_200, at: 0)
        XCTAssertTrue(reminder.isEnabled)
        XCTAssertEqual(reminder.times, [480])
        XCTAssertEqual(center.trigger?.dateComponents.hour, 8)
        XCTAssertNotNil(reminder.errorMessage)
        XCTAssertEqual(preferences.object(forKey: FoodReminderSchedule.timesKey) as? [Int], [480])
        await reminder.refresh()
        XCTAssertFalse(reminder.isEnabled)
        XCTAssertTrue(center.pending.isEmpty)
    }

    func testInvalidStoredChoicesAndTimesUseSafeDefaults() {
        let preferences = MemoryReminderPreferences()
        preferences.set("unknown", forKey: FoodReminderSchedule.timeKey)
        for minutes in [-1, 1_440, Int.max] {
            preferences.set(minutes, forKey: FoodReminderSchedule.customMinutesKey)
            let reminder = FoodDailyReminder(preferences: preferences, notifications: FakeReminderNotifications())
            XCTAssertEqual(reminder.times, [480])
            XCTAssertEqual(FoodReminderSchedule.request(minutes: minutes).trigger
                .flatMap { $0 as? UNCalendarNotificationTrigger }?.dateComponents.hour, 8)
        }
    }

    func testDisableQueuedDuringPermissionPromptWinsAfterItCompletes() async {
        let center = FakeReminderNotifications()
        center.pausePermission = true
        let reminder = FoodDailyReminder(preferences: MemoryReminderPreferences(), notifications: center)
        let enable = Task { await reminder.setEnabled(true) }
        for _ in 0..<100 where center.permissionContinuation == nil { await Task.yield() }
        XCTAssertNotNil(center.permissionContinuation)
        XCTAssertTrue(reminder.isUpdating)
        let disable = Task { await reminder.setEnabled(false) }
        center.status = .authorized
        center.permissionContinuation?.resume(returning: true)
        center.permissionContinuation = nil
        await enable.value
        await disable.value
        XCTAssertFalse(reminder.isEnabled)
        XCTAssertFalse(reminder.isUpdating)
        XCTAssertTrue(center.pending.isEmpty)
    }

    func testLegacyUpgradePreservesExactTimeEnabledStateAndOriginalIdentifier() async {
        for (choice, expected) in [("morning", 480), ("evening", 1_200), ("custom", 777)] {
            for enabled in [true, false] {
                let preferences = MemoryReminderPreferences()
                preferences.set(choice, forKey: FoodReminderSchedule.timeKey)
                preferences.set(777, forKey: FoodReminderSchedule.customMinutesKey)
                preferences.set(enabled, forKey: FoodReminderSchedule.enabledKey)
                let center = FakeReminderNotifications()
                center.status = .authorized
                let reminder = FoodDailyReminder(preferences: preferences, notifications: center)
                XCTAssertEqual(reminder.times, [expected])
                XCTAssertEqual(reminder.isEnabled, enabled)
                await reminder.refresh()
                XCTAssertEqual(Set(center.pending.keys), enabled ? [FoodReminderSchedule.identifier] : [])
                XCTAssertEqual(center.authorizationRequests, 0)
                XCTAssertEqual(preferences.object(forKey: FoodReminderSchedule.timesKey) as? [Int], [expected])
            }
        }
    }

    func testThreeIndependentTimesCapAndRelaunchWithoutDuplicates() async {
        let preferences = MemoryReminderPreferences()
        let center = FakeReminderNotifications()
        let reminder = FoodDailyReminder(preferences: preferences, notifications: center)
        await reminder.setEnabled(true)
        for _ in 0..<5 { await reminder.addReminder() }
        XCTAssertEqual(reminder.times, [480, 780, 1_200])
        await reminder.setMinutes(1_439, at: 2)
        await reminder.setMinutes(0, at: 1)
        for (slot, time) in reminder.times.enumerated() {
            let trigger = center.pending[FoodReminderSchedule.identifiers[slot]]?.trigger as? UNCalendarNotificationTrigger
            XCTAssertEqual(trigger?.dateComponents.hour, time / 60)
            XCTAssertEqual(trigger?.dateComponents.minute, time % 60)
            XCTAssertEqual(trigger?.repeats, true)
        }
        let relaunched = FoodDailyReminder(preferences: preferences, notifications: center)
        await relaunched.refresh()
        await relaunched.refresh()
        XCTAssertEqual(relaunched.times, [480, 0, 1_439])
        XCTAssertEqual(Set(center.pending.keys), Set(FoodReminderSchedule.identifiers))
        XCTAssertEqual(center.authorizationRequests, 1)
    }

    func testRemovingMiddleTimeReindexesAndCancelsUnusedSlot() async {
        let preferences = MemoryReminderPreferences()
        let center = FakeReminderNotifications()
        let reminder = FoodDailyReminder(preferences: preferences, notifications: center)
        await reminder.setEnabled(true)
        await reminder.addReminder()
        await reminder.addReminder()
        center.delivered = Set(FoodReminderSchedule.identifiers)
        await reminder.removeReminders(at: IndexSet(integer: 1))
        XCTAssertEqual(reminder.times, [480, 1_200])
        XCTAssertEqual(center.pending.count, 2)
        XCTAssertNil(center.pending[FoodReminderSchedule.identifiers[2]])
        XCTAssertFalse(center.delivered.contains(FoodReminderSchedule.identifiers[2]))
        let trigger = center.pending[FoodReminderSchedule.identifiers[1]]?.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(trigger?.dateComponents.hour, 20)
        await reminder.removeReminders(at: IndexSet(integer: 1))
        await reminder.removeReminders(at: IndexSet(integer: 0))
        XCTAssertEqual(reminder.times, [480])
        XCTAssertEqual(center.pending.count, 1)
        XCTAssertEqual(FoodDailyReminder(preferences: preferences, notifications: center).times, [480])
    }

    func testDuplicateInvalidAndOutOfBoundsEditsKeepSchedule() async {
        let center = FakeReminderNotifications()
        let reminder = FoodDailyReminder(preferences: MemoryReminderPreferences(), notifications: center)
        await reminder.setEnabled(true)
        await reminder.addReminder()
        for value in [480, -1, 1_440, Int.max] {
            await reminder.setMinutes(value, at: 1)
            XCTAssertEqual(reminder.times, [480, 780])
            XCTAssertNotNil(reminder.errorMessage)
            XCTAssertEqual(center.pending.count, 2)
        }
        await reminder.setMinutes(500, at: 9)
        await reminder.removeReminders(at: IndexSet(integer: 9))
        XCTAssertEqual(reminder.times, [480, 780])
    }

    func testStoredTimesAreValidatedDeduplicatedCappedAndTakePrecedenceOverLegacy() {
        let preferences = MemoryReminderPreferences()
        preferences.set("evening", forKey: FoodReminderSchedule.timeKey)
        for (stored, expected) in [([480, 480, -1, 780, 1_200, 1_300], [480, 780, 1_200]),
                                    ([], [480]), ([1_440, -1], [480]), ([0, 1_439], [0, 1_439])] {
            preferences.set(stored, forKey: FoodReminderSchedule.timesKey)
            let reminder = FoodDailyReminder(preferences: preferences, notifications: FakeReminderNotifications())
            XCTAssertEqual(reminder.times, expected)
            XCTAssertEqual(preferences.object(forKey: FoodReminderSchedule.timesKey) as? [Int], expected)
        }
    }

    func testPartialEnableFailureCancelsAllSlots() async {
        for failedCall in [2, 3] {
            let center = FakeReminderNotifications()
            let reminder = FoodDailyReminder(preferences: MemoryReminderPreferences(), notifications: center)
            await reminder.addReminder()
            await reminder.addReminder()
            center.failedAddCalls = [failedCall]
            await reminder.setEnabled(true)
            XCTAssertFalse(reminder.isEnabled)
            XCTAssertNotNil(reminder.errorMessage)
            XCTAssertTrue(center.pending.isEmpty)
        }
    }

    func testPartialRemovalFailureRestoresOriginalThreeTimes() async {
        let center = FakeReminderNotifications()
        let reminder = FoodDailyReminder(preferences: MemoryReminderPreferences(), notifications: center)
        await reminder.addReminder()
        await reminder.addReminder()
        await reminder.setEnabled(true)
        // Removing the first time replaces slots 0 and 1. Fail the second write.
        center.failedAddCalls = [center.addCalls + 2]
        await reminder.removeReminders(at: IndexSet(integer: 0))
        XCTAssertTrue(reminder.isEnabled)
        XCTAssertEqual(reminder.times, [480, 780, 1_200])
        XCTAssertEqual(center.trigger?.dateComponents.hour, 8)
        XCTAssertEqual(center.pending.count, 3)
        XCTAssertNotNil(reminder.errorMessage)
    }

    func testRollbackFailureTurnsNotificationsOffWithoutLosingConfiguredTimes() async {
        let center = FakeReminderNotifications()
        let reminder = FoodDailyReminder(preferences: MemoryReminderPreferences(), notifications: center)
        await reminder.addReminder()
        await reminder.addReminder()
        await reminder.setEnabled(true)
        center.failedAddCalls = [center.addCalls + 2, center.addCalls + 3]
        await reminder.removeReminders(at: IndexSet(integer: 0))
        XCTAssertFalse(reminder.isEnabled)
        XCTAssertEqual(reminder.times, [480, 780, 1_200])
        XCTAssertTrue(center.pending.isEmpty)
        XCTAssertNotNil(reminder.errorMessage)
    }

    func testRefreshCancelsStaleSlotsAndPartialFailureDisablesAll() async {
        let preferences = MemoryReminderPreferences()
        let center = FakeReminderNotifications()
        let reminder = FoodDailyReminder(preferences: preferences, notifications: center)
        await reminder.setEnabled(true)
        for slot in [1, 2] {
            center.pending[FoodReminderSchedule.identifiers[slot]] = FoodReminderSchedule.request(minutes: 600, slot: slot)
        }
        await reminder.refresh()
        XCTAssertEqual(center.pending.count, 1)
        await reminder.addReminder()
        await reminder.addReminder()
        center.failedAddCalls = [center.addCalls + 2]
        await reminder.refresh()
        XCTAssertFalse(reminder.isEnabled)
        XCTAssertTrue(center.pending.isEmpty)
    }
}

@MainActor
private final class MemoryReminderPreferences: FoodReminderPreferences {
    private var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}

@MainActor
private final class FakeReminderNotifications: FoodReminderNotificationCenter {
    enum Failure: Error { case simulated }
    var status: UNAuthorizationStatus = .notDetermined
    var grantPermission = true
    var failPermission = false
    var failScheduling = false
    var failedAddCalls: Set<Int> = []
    var addCalls = 0
    var pausePermission = false
    var permissionContinuation: CheckedContinuation<Bool, Error>?
    var authorizationRequests = 0
    var pending: [String: UNNotificationRequest] = [:]
    var delivered: Set<String> = []
    var trigger: UNCalendarNotificationTrigger? {
        pending[FoodReminderSchedule.identifier]?.trigger as? UNCalendarNotificationTrigger
    }
    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async throws -> Bool {
        authorizationRequests += 1
        if failPermission { throw Failure.simulated }
        if pausePermission {
            return try await withCheckedThrowingContinuation { permissionContinuation = $0 }
        }
        status = grantPermission ? .authorized : .denied
        return grantPermission
    }
    func add(_ request: UNNotificationRequest) async throws {
        addCalls += 1
        if failScheduling || failedAddCalls.contains(addCalls) { throw Failure.simulated }
        pending[request.identifier] = request
    }
    func removeReminders(identifiers: [String]) {
        for identifier in identifiers {
            pending.removeValue(forKey: identifier)
            delivered.remove(identifier)
        }
    }
}

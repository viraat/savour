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
        XCTAssertEqual(reminder.time, .morning)
        XCTAssertEqual(reminder.scheduledMinutes, 480)
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
        center.delivered = ["other-feature", FoodReminderSchedule.identifier]
        let reminder = FoodDailyReminder(preferences: preferences, notifications: center)
        await reminder.setEnabled(true)
        XCTAssertTrue(reminder.isEnabled)
        XCTAssertEqual(preferences.object(forKey: FoodReminderSchedule.enabledKey) as? Bool, true)
        await reminder.setEnabled(true)
        XCTAssertEqual(center.authorizationRequests, 1)
        XCTAssertEqual(center.pending.count, 2)
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

    func testConfiguringWhileOffDoesNotAskPermissionAndCustomTimeIsRetained() async {
        let preferences = MemoryReminderPreferences()
        let center = FakeReminderNotifications()
        let reminder = FoodDailyReminder(preferences: preferences, notifications: center)
        await reminder.setCustomMinutes(777)
        await reminder.setTime(.evening)
        XCTAssertEqual(reminder.scheduledMinutes, 1_200)
        await reminder.setTime(.custom)
        XCTAssertEqual(reminder.scheduledMinutes, 777)
        XCTAssertEqual(center.authorizationRequests, 0)
        XCTAssertTrue(center.pending.isEmpty)
        let relaunched = FoodDailyReminder(preferences: preferences, notifications: center)
        XCTAssertEqual(relaunched.time, .custom)
        XCTAssertEqual(relaunched.customMinutes, 777)
        XCTAssertFalse(relaunched.isEnabled)
    }

    func testTimeEditsAndRelaunchKeepExactlyOnePendingNotification() async {
        let preferences = MemoryReminderPreferences()
        let center = FakeReminderNotifications()
        let reminder = FoodDailyReminder(preferences: preferences, notifications: center)
        await reminder.setEnabled(true)
        await reminder.setTime(.evening)
        await reminder.setCustomMinutes(0)
        XCTAssertEqual(center.pending.count, 1)
        XCTAssertEqual(center.trigger?.dateComponents.hour, 0)
        XCTAssertEqual(center.trigger?.dateComponents.minute, 0)
        let relaunched = FoodDailyReminder(preferences: preferences, notifications: center)
        await relaunched.refresh()
        XCTAssertTrue(relaunched.isEnabled)
        XCTAssertEqual(relaunched.time, .custom)
        XCTAssertEqual(relaunched.customMinutes, 0)
        XCTAssertEqual(center.pending.count, 1)
        XCTAssertEqual(center.authorizationRequests, 1)
    }

    func testRevokedOrResetPermissionCancelsWithoutPromptOnRelaunch() async {
        for status: UNAuthorizationStatus in [.denied, .notDetermined] {
            let preferences = MemoryReminderPreferences()
            let center = FakeReminderNotifications()
            let reminder = FoodDailyReminder(preferences: preferences, notifications: center)
            await reminder.setEnabled(true)
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
        await reminder.setTime(.evening)
        XCTAssertTrue(reminder.isEnabled)
        XCTAssertEqual(reminder.time, .morning)
        XCTAssertEqual(center.trigger?.dateComponents.hour, 8)
        XCTAssertNotNil(reminder.errorMessage)
        XCTAssertNil(preferences.object(forKey: FoodReminderSchedule.timeKey))
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
            XCTAssertEqual(reminder.time, .morning)
            XCTAssertEqual(reminder.customMinutes, 480)
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
        if failScheduling { throw Failure.simulated }
        pending[request.identifier] = request
    }
    func removeReminder() {
        pending.removeValue(forKey: FoodReminderSchedule.identifier)
        delivered.remove(FoodReminderSchedule.identifier)
    }
}

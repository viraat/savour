import Foundation
import XCTest
#if canImport(FoodLogDrafts)
@testable import FoodLogDrafts
#else
@testable import FoodLog
#endif

final class FoodDraftAutosaveTests: XCTestCase {
    @MainActor
    func testRapidChangesWriteOnlyLatestSnapshotAfterIdle() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("drafts.plist")
        let store = FoodEntryDraftStore(url: url)
        let saver = FoodEntryDraftAutosaver(delayNanoseconds: 20_000_000)
        let saved = expectation(description: "Latest draft saved")
        saved.assertForOverFulfill = true
        var writes = 0
        for index in 0..<100 {
            let snapshot = draft(food: "Tofu \(index)")
            saver.schedule {
                do { try store.save(snapshot, for: .new, active: true) }
                catch { XCTFail("\(error)") }
                writes += 1
                saved.fulfill()
            }
        }
        XCTAssertEqual(writes, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        await fulfillment(of: [saved], timeout: 2)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(try FoodEntryDraftStore(url: url).draft(for: .new), draft(food: "Tofu 99"))
        XCTAssertEqual(try store.activeDraftKey(), .new)
    }

    @MainActor
    func testReschedulingRestartsIdleWindow() async {
        let saver = FoodEntryDraftAutosaver(delayNanoseconds: 150_000_000)
        let scheduled = expectation(description: "Second change scheduled")
        let saved = expectation(description: "Latest change saved")
        let probe = FoodEntryDraftAutosaver(delayNanoseconds: 20_000_000)
        var firstSaved = false
        var lastSaved = false
        saver.schedule { firstSaved = true }
        probe.schedule {
            saver.schedule { lastSaved = true; saved.fulfill() }
            scheduled.fulfill()
        }
        await fulfillment(of: [scheduled], timeout: 2)
        XCTAssertFalse(firstSaved)
        XCTAssertFalse(lastSaved)
        await fulfillment(of: [saved], timeout: 2)
        XCTAssertFalse(firstSaved)
        XCTAssertTrue(lastSaved)
    }

    @MainActor
    func testBackgroundFlushImmediatelySavesLatestCompleteDraft() async throws {
        try await checkImmediateFlush(active: true)
    }

    @MainActor
    func testKeepDraftCloseImmediatelySavesWithoutMarkingActive() async throws {
        try await checkImmediateFlush(active: false)
    }

    @MainActor
    private func checkImmediateFlush(active: Bool) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("drafts.plist")
        let store = FoodEntryDraftStore(url: url)
        let saver = FoodEntryDraftAutosaver(delayNanoseconds: 20_000_000)
        let otherKey = FoodEntryDraftKey.edit(UUID())
        let otherDraft = draft(food: "Existing edit")
        try store.save(otherDraft, for: otherKey, active: false)
        try store.save(draft(food: "Earlier typing"), for: .new, active: true)
        saver.schedule {
            do { try store.save(self.draft(food: "Stale typing"), for: .new, active: true) }
            catch { XCTFail("\(error)") }
        }
        // Mirrors persistDraft: cancel queued typing before synchronous lifecycle save.
        saver.cancel()
        let latest = draft(food: "Latest typing with all optional fields")
        try store.save(latest, for: .new, active: active)
        XCTAssertEqual(try FoodEntryDraftStore(url: url).draft(for: .new), latest)
        await waitPastCancelledSave()
        let reopened = FoodEntryDraftStore(url: url)
        XCTAssertEqual(try reopened.draft(for: .new), latest)
        XCTAssertEqual(try reopened.draft(for: otherKey), otherDraft)
        XCTAssertEqual(try reopened.activeDraftKey(), active ? .new : nil)
    }

    @MainActor
    func testDiscardCancelsDelayedWriteWithoutRecreatingDraft() async throws {
        try await checkTerminalCancellation()
    }

    @MainActor
    func testSuccessfulEntrySaveCancelsDelayedWriteBeforeDraftCleanup() async throws {
        // Journal save happens first; its existing draft cleanup is the same
        // cancel/discard sequence as an explicit Discard. No Core Data mutation here.
        try await checkTerminalCancellation()
    }

    @MainActor
    func testSuccessfulEntryDeletionCancelsDelayedEditSave() async throws {
        try await checkTerminalCancellation(key: .edit(UUID()))
    }

    @MainActor
    private func checkTerminalCancellation(key: FoodEntryDraftKey = .new) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("drafts.plist")
        let store = FoodEntryDraftStore(url: url)
        try store.save(draft(food: "Old draft"), for: key, active: true)
        let saver = FoodEntryDraftAutosaver(delayNanoseconds: 20_000_000)
        saver.schedule {
            do { try store.save(self.draft(food: "Pending draft"), for: key, active: true) }
            catch { XCTFail("\(error)") }
        }
        saver.cancel()
        try store.discard(key)
        await waitPastCancelledSave()
        XCTAssertNil(try FoodEntryDraftStore(url: url).draft(for: key))
        XCTAssertNil(try store.activeDraftKey())
    }

    @MainActor
    func testDelayedSaveFailureIsReportedAndCanBeRetriedImmediately() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocker = directory.appendingPathComponent("not-a-directory")
        try Data([1]).write(to: blocker)
        let store = FoodEntryDraftStore(url: blocker.appendingPathComponent("drafts.plist"))
        let saver = FoodEntryDraftAutosaver(delayNanoseconds: 20_000_000)
        let attempted = expectation(description: "Save error returned")
        var saveError: Error?
        saver.schedule {
            do { try store.save(self.draft(food: "Tofu"), for: .new, active: true) }
            catch { saveError = error }
            attempted.fulfill()
        }
        await fulfillment(of: [attempted], timeout: 2)
        XCTAssertNotNil(saveError)
        try FileManager.default.removeItem(at: blocker)
        saver.cancel()
        try store.save(draft(food: "Tofu"), for: .new, active: true)
        XCTAssertEqual(try store.draft(for: .new), draft(food: "Tofu"))
    }

    @MainActor
    func testCancellingTwiceIsSafeAndSubsequentTypingCanSave() async {
        let saver = FoodEntryDraftAutosaver(delayNanoseconds: 20_000_000)
        saver.schedule { XCTFail("Cancelled work ran") }
        saver.cancel()
        saver.cancel()
        let saved = expectation(description: "Subsequent change saved")
        saver.schedule { saved.fulfill() }
        await fulfillment(of: [saved], timeout: 2)
    }

    @MainActor
    private func waitPastCancelledSave() async {
        let elapsed = expectation(description: "Pending write deadline passed")
        let probe = FoodEntryDraftAutosaver(delayNanoseconds: 80_000_000)
        probe.schedule { elapsed.fulfill() }
        await fulfillment(of: [elapsed], timeout: 2)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func draft(food: String) -> FoodEntryDraft {
        FoodEntryDraft(food: food, date: Date(timeIntervalSince1970: 1_700_000_123),
                       mealType: "Dinner", place: "Tofu Vegan", placeCity: "London",
                       placeLatitude: 51.5, placeLongitude: -0.1, hasPlaceCoordinates: true,
                       selectedPlaceLabel: "Tofu Vegan, London", selectedPlaceSavedName: "Tofu Vegan",
                       companions: ["Evi", "Prasanna"], companionQuery: "Nam", note: "Notes\nwith a line break",
                       photoData: Data(repeating: 42, count: 300_000), startFastAfterMeal: false,
                       detailsExpanded: true)
    }
}

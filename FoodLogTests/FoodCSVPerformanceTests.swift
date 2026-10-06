import Foundation
import XCTest
#if canImport(FoodLogPerformance)
@testable import FoodLogPerformance
#else
@testable import FoodLog
#endif

final class FoodCSVPerformanceTests: XCTestCase {
    func testExistingRowsAreSerializedExactlyOnceInOnePass() {
        var calls = 0
        let source = (0..<3_000).lazy.map { index -> [String] in
            calls += 1
            return self.row(food: "Meal \(index)", id: nil)
        }
        let identities = FoodLogCSVIdentities(existingRows: source)
        XCTAssertEqual(calls, 3_000)
        XCTAssertTrue(identities.contains(row(food: "Meal 2999", id: nil), entryID: nil, isLegacyFormat: false))
        XCTAssertTrue(identities.contains(Array(row(food: "Meal 0", id: nil).prefix(10)),
                                          entryID: nil, isLegacyFormat: true))
        XCTAssertEqual(calls, 3_000)
    }

    func testUUIDAndContentDuplicateRulesAreUnchanged() {
        let id = UUID()
        let original = row(id: id)
        let identities = FoodLogCSVIdentities(existingRows: [original])
        let newID = UUID()
        XCTAssertTrue(identities.contains(row(food: "Changed text", id: id), entryID: id, isLegacyFormat: false))
        XCTAssertTrue(identities.contains(row(id: newID), entryID: newID, isLegacyFormat: false))
        XCTAssertFalse(identities.contains(row(food: "Another meal", id: newID), entryID: newID, isLegacyFormat: false))
        var preciseTime = original
        preciseTime[12] = "1789113600.5"
        XCTAssertFalse(identities.contains(preciseTime, entryID: newID, isLegacyFormat: false))
        XCTAssertTrue(identities.contains(Array(preciseTime.prefix(10)), entryID: nil, isLegacyFormat: true))
    }

    func testWithinFileDuplicatesAndGeneratedLegacyIDsAreTracked() {
        var identities = FoodLogCSVIdentities(existingRows: [[String]]())
        let id = UUID()
        let extended = row(id: id)
        XCTAssertFalse(identities.contains(extended, entryID: id, isLegacyFormat: false))
        identities.insert(extended, entryID: id, isLegacyFormat: false)
        XCTAssertTrue(identities.contains(extended, entryID: id, isLegacyFormat: false))
        let legacy = Array(row(food: "Legacy meal", id: nil).prefix(10))
        let generatedID = UUID()
        identities.insert(legacy, entryID: generatedID, isLegacyFormat: true)
        XCTAssertTrue(identities.contains(legacy, entryID: nil, isLegacyFormat: true))
        XCTAssertTrue(identities.contains(row(food: "Different meal", id: generatedID),
                                          entryID: generatedID, isLegacyFormat: false))
    }

    func testExtendedIdentityKeepsStructuredPeopleAndPreciseTimestamp() {
        let original = row(id: nil)
        let identities = FoodLogCSVIdentities(existingRows: [original])
        var differentPeople = original
        differentPeople[11] = "[\"Ana, Bob\"]"
        XCTAssertFalse(identities.contains(differentPeople, entryID: nil, isLegacyFormat: false))
        XCTAssertTrue(identities.contains(Array(differentPeople.prefix(10)), entryID: nil, isLegacyFormat: true))
    }

    func testReusedFormattersPreserveValidationErrors() throws {
        let formatters = FoodLogCSVDateFormatters(timeZone: TimeZone(secondsFromGMT: 0)!)
        let original = row()
        var cases: [([String], CSVCodecError?)] = [(original, nil), (Array(original.prefix(10)), nil)]
        for (column, text, error) in [
            (0, " \n ", CSVCodecError.emptyFood(row: 42)),
            (1, "invalid-date", .invalidDate(row: 42)),
            (2, "25:00", .invalidTime(row: 42)),
            (6, "91", .invalidCoordinate(row: 42)),
            (7, "", .invalidCoordinate(row: 42)),
            (10, "bad-id", .invalidID(row: 42)),
            (11, "not-json", .invalidPeople(row: 42)),
            (12, "nan", .invalidTimestamp(row: 42)),
            (12, "253402300800", .invalidTimestamp(row: 42))
        ] {
            var invalid = original
            invalid[column] = text
            cases.append((invalid, error))
        }
        // Run repeatedly to exercise formatter reuse after failures as well as success.
        for _ in 0..<10 {
            for (fields, expected) in cases {
                if let expected {
                    XCTAssertThrowsError(try FoodLogCSVDocument.validate(fields, rowNumber: 42,
                                                                         columnCount: fields.count,
                                                                         formatters: formatters)) {
                        XCTAssertEqual($0 as? CSVCodecError, expected)
                    }
                } else {
                    try FoodLogCSVDocument.validate(fields, rowNumber: 42,
                                                    columnCount: fields.count, formatters: formatters)
                }
            }
        }
        XCTAssertThrowsError(try FoodLogCSVDocument.validate(["short"], rowNumber: 42, columnCount: 13,
                                                             formatters: formatters)) {
            XCTAssertEqual($0 as? CSVCodecError, .wrongColumnCount(row: 42, expected: 13, actual: 1))
        }
    }

    func testLegacyParsingRetainsStrictRoundTripAndOperationTimeZone() throws {
        for zone in ["UTC", "Asia/Kolkata", "America/New_York", "Pacific/Kiritimati"] {
            let formatters = FoodLogCSVDateFormatters(timeZone: try XCTUnwrap(TimeZone(identifier: zone)))
            let date = try XCTUnwrap(formatters.legacyDate("2026-09-11 08:30"))
            XCTAssertEqual(formatters.dateString(date), "2026-09-11")
            XCTAssertEqual(formatters.timeString(date), "08:30")
            XCTAssertNil(formatters.legacyDate("2026-02-30 08:30"))
            XCTAssertNil(formatters.legacyDate("2026-09-11 25:00"))
            XCTAssertNil(formatters.legacyDate("2026-9-11 8:30"))
        }
        let newYork = FoodLogCSVDateFormatters(timeZone: try XCTUnwrap(TimeZone(identifier: "America/New_York")))
        // Missing hour during spring-forward remains rejected by exact round trip.
        XCTAssertNil(newYork.legacyDate("2026-03-08 02:30"))
        XCTAssertNotNil(newYork.legacyDate("2026-11-01 01:30"))
    }

    func testIndependentOperationsDoNotShareTimeZoneState() throws {
        let utc = FoodLogCSVDateFormatters(timeZone: TimeZone(secondsFromGMT: 0)!)
        let india = FoodLogCSVDateFormatters(timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata")))
        let date = try XCTUnwrap(utc.legacyDate("2026-09-11 23:30"))
        for _ in 0..<100 {
            XCTAssertEqual(utc.dateString(date), "2026-09-11")
            XCTAssertEqual(utc.timeString(date), "23:30")
            XCTAssertEqual(india.dateString(date), "2026-09-12")
            XCTAssertEqual(india.timeString(date), "05:00")
        }
    }

    func testThousandsOfQuotedRowsDecodeWithReusableValidation() throws {
        let rows = (0..<3_000).map { row(food: "Tofu, \"meal\" \($0)\nTea", id: UUID()) }
        XCTAssertEqual(try FoodLogCSVDocument.decode(FoodLogCSVDocument.encodeExtended(dataRows: rows)), rows)
    }

    func testFormatterReuseMicrobenchmarkPreservesResults() throws {
        let fields = row()
        let iterations = 1_000
        let rebuildingStart = Date()
        for index in 0..<iterations {
            try FoodLogCSVDocument.validate(fields, rowNumber: index + 2, columnCount: fields.count)
        }
        let rebuilding = Date().timeIntervalSince(rebuildingStart)
        let reusedStart = Date()
        let formatters = FoodLogCSVDateFormatters()
        for index in 0..<iterations {
            try FoodLogCSVDocument.validate(fields, rowNumber: index + 2,
                                            columnCount: fields.count, formatters: formatters)
        }
        let reused = Date().timeIntervalSince(reusedStart)
        print("CSV validation microbenchmark (1,000 rows): per-row formatters \(rebuilding)s; operation-local reuse \(reused)s")
        // Diagnostic only: no flaky speed/timing threshold or app-wide claim.
    }

    private func row(food: String = "Tofu", id: UUID? = UUID()) -> [String] {
        [food, "2026-09-11", "08:00", "Breakfast", "Cafe, Central", "London",
         "51.5", "-0.1", "Ana, Bob", "Notes\nwith \"quotes\"", id?.uuidString ?? "",
         "[\"Ana\",\"Bob\"]", "1789113600"]
    }
}

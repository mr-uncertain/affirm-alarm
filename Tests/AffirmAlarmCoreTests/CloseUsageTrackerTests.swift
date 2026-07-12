import XCTest
@testable import AffirmAlarmCore

final class CloseUsageTrackerTests: XCTestCase {
    let calendar = Calendar(identifier: .gregorian)

    func makeDate(year: Int, month: Int, day: Int) -> Date {
        DateComponents(calendar: calendar, year: year, month: month, day: day).date!
    }

    func test_monthKey_formatsYearMonth() {
        let date = makeDate(year: 2026, month: 7, day: 15)
        XCTAssertEqual(CloseUsageTracker.monthKey(for: date, calendar: calendar), "2026-07")
    }

    func test_canUseClose_trueWhenUnderLimit() {
        let record = CloseUsageRecord(monthKey: "2026-07", usesThisMonth: 2)
        let now = makeDate(year: 2026, month: 7, day: 15)
        XCTAssertTrue(CloseUsageTracker.canUseClose(record: record, now: now, calendar: calendar))
    }

    func test_canUseClose_falseWhenAtLimit() {
        let record = CloseUsageRecord(monthKey: "2026-07", usesThisMonth: 3)
        let now = makeDate(year: 2026, month: 7, day: 15)
        XCTAssertFalse(CloseUsageTracker.canUseClose(record: record, now: now, calendar: calendar))
    }

    func test_canUseClose_trueWhenRecordIsFromAPastMonth() {
        let record = CloseUsageRecord(monthKey: "2026-06", usesThisMonth: 3)
        let now = makeDate(year: 2026, month: 7, day: 1)
        XCTAssertTrue(CloseUsageTracker.canUseClose(record: record, now: now, calendar: calendar))
    }

    func test_recordingUse_incrementsWithinSameMonth() {
        let record = CloseUsageRecord(monthKey: "2026-07", usesThisMonth: 1)
        let now = makeDate(year: 2026, month: 7, day: 20)
        let updated = CloseUsageTracker.recordingUse(on: record, now: now, calendar: calendar)
        XCTAssertEqual(updated, CloseUsageRecord(monthKey: "2026-07", usesThisMonth: 2))
    }

    func test_recordingUse_resetsToOneInNewMonth() {
        let record = CloseUsageRecord(monthKey: "2026-06", usesThisMonth: 3)
        let now = makeDate(year: 2026, month: 7, day: 1)
        let updated = CloseUsageTracker.recordingUse(on: record, now: now, calendar: calendar)
        XCTAssertEqual(updated, CloseUsageRecord(monthKey: "2026-07", usesThisMonth: 1))
    }
}

import XCTest
@testable import AffirmAlarmCore

final class ModelsTests: XCTestCase {
    func test_affirmation_hasStableIdentity() {
        let id = UUID()
        let a = Affirmation(id: id, text: "I am capable", isUserAuthored: true)
        XCTAssertEqual(a.id, id)
        XCTAssertEqual(a.text, "I am capable")
        XCTAssertTrue(a.isUserAuthored)
    }

    func test_streakState_defaultsToDayOneNoCompletion() {
        let s = StreakState(streakDay: 1, lastCompletedDate: nil)
        XCTAssertEqual(s.streakDay, 1)
        XCTAssertNil(s.lastCompletedDate)
    }

    func test_closeUsageRecord_tracksMonthAndCount() {
        let r = CloseUsageRecord(monthKey: "2026-07", usesThisMonth: 2)
        XCTAssertEqual(r.monthKey, "2026-07")
        XCTAssertEqual(r.usesThisMonth, 2)
    }
}

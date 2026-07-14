import XCTest
@testable import AffirmAlarmCore

final class LocalNotificationCheckInSchedulerTests: XCTestCase {
    func test_scheduleNextCheckIn_addsPrimaryAndFollowUpRequests() async {
        let center = FakeNotificationScheduling()
        let scheduler = LocalNotificationCheckInScheduler(center: center)

        await scheduler.scheduleNextCheckIn(from: Date())

        XCTAssertEqual(center.addedIdentifiers.count, 2)
        XCTAssertTrue(center.addedIdentifiers.contains("affirmalarm.checkin"))
        XCTAssertTrue(center.addedIdentifiers.contains("affirmalarm.checkin.followup"))
    }

    func test_scheduleNextCheckIn_cancelsAnyPriorPendingRequestsFirst() async {
        let center = FakeNotificationScheduling()
        let scheduler = LocalNotificationCheckInScheduler(center: center)

        await scheduler.scheduleNextCheckIn(from: Date())
        await scheduler.scheduleNextCheckIn(from: Date())

        XCTAssertEqual(center.removeCallCount, 2)
    }

    func test_cancelPendingCheckIns_removesBothIdentifiers() {
        let center = FakeNotificationScheduling()
        let scheduler = LocalNotificationCheckInScheduler(center: center)

        scheduler.cancelPendingCheckIns()

        XCTAssertEqual(center.lastRemovedIdentifiers, ["affirmalarm.checkin", "affirmalarm.checkin.followup"])
    }
}

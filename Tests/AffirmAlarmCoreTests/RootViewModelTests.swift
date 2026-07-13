import XCTest
@testable import AffirmAlarmCore

@MainActor
final class RootViewModelTests: XCTestCase {
    func test_start_routesToHome_whenNoAlarmIsAlerting() async {
        let alarmService = FakeAlarmSchedulingService()
        let viewModel = RootViewModel(alarmService: alarmService)

        await viewModel.start()

        XCTAssertEqual(viewModel.route, .home)
    }

    func test_start_routesToRinging_whenAnAlarmIsAlerting() async {
        let alarmService = FakeAlarmSchedulingService()
        let alertingID = UUID()
        alarmService.alertingIDToReturn = alertingID
        let viewModel = RootViewModel(alarmService: alarmService)

        await viewModel.start()

        XCTAssertEqual(viewModel.route, .ringing)
        XCTAssertEqual(alarmService.syncedAlarmID, alertingID)
    }

    func test_alertingUpdate_routesToRinging_whileObserving() async {
        let alarmService = FakeAlarmSchedulingService()
        let viewModel = RootViewModel(alarmService: alarmService)
        await viewModel.start()
        XCTAssertEqual(viewModel.route, .home)

        let alertingID = UUID()
        alarmService.simulateAlertingUpdate(alertingID)
        await Task.yield()

        XCTAssertEqual(viewModel.route, .ringing)
        XCTAssertEqual(alarmService.syncedAlarmID, alertingID)
    }

    func test_alertingUpdateClears_routesBackToHomeAndCancelsAlarm() async {
        let alarmService = FakeAlarmSchedulingService()
        alarmService.alertingIDToReturn = UUID()
        let viewModel = RootViewModel(alarmService: alarmService)
        await viewModel.start()
        XCTAssertEqual(viewModel.route, .ringing)

        // Simulates the system Stop button being tapped while foregrounded —
        // AlarmKit's alarmUpdates stream reports the alarm is no longer alerting.
        alarmService.simulateAlertingUpdate(nil)
        await Task.yield()

        XCTAssertEqual(viewModel.route, .home)
        XCTAssertTrue(alarmService.wasCancelled)
    }
}

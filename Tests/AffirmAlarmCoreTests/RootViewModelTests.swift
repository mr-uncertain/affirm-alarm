import XCTest
@testable import AffirmAlarmCore

@MainActor
final class RootViewModelTests: XCTestCase {
    // The updates-consuming Task inside RootViewModel hops through the
    // AsyncStream's suspension (and back onto MainActor) an
    // implementation-detail number of times per delivered value. A single
    // `await Task.yield()` isn't a reliable enough synchronization point for
    // that hop chain (confirmed flaky against multiple RootViewModel
    // implementations in CI), so tests that simulate a stream update poll
    // briefly instead of asserting immediately after one yield.
    private func waitUntil(
        timeout: TimeInterval = 1,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            await Task.yield()
        }
    }

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
        await waitUntil { viewModel.route == .ringing }

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
        await waitUntil { viewModel.route == .home }

        XCTAssertEqual(viewModel.route, .home)
        XCTAssertTrue(alarmService.wasCancelled)
    }
}

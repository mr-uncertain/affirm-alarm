import XCTest
@testable import AffirmAlarmCore

@MainActor
final class HomeViewModelTests: XCTestCase {
    func test_init_loadsCurrentStreakDay() {
        let store = SwiftDataStreakStore(inMemory: true)
        store.save(StreakState(streakDay: 5, lastCompletedDate: nil))
        let viewModel = HomeViewModel(alarmService: FakeAlarmSchedulingService(), store: store, aiService: FakeAIContentService())

        XCTAssertEqual(viewModel.streakDay, 5)
    }

    func test_saveAlarmTime_success_setsScheduledTime() async {
        let alarmService = FakeAlarmSchedulingService()
        let viewModel = HomeViewModel(alarmService: alarmService, store: SwiftDataStreakStore(inMemory: true), aiService: FakeAIContentService())
        viewModel.selectedTime = DateComponents(hour: 7, minute: 30)

        await viewModel.saveAlarmTime()

        XCTAssertEqual(viewModel.scheduledTime, DateComponents(hour: 7, minute: 30))
        XCTAssertEqual(alarmService.scheduledTime, DateComponents(hour: 7, minute: 30))
        XCTAssertNil(viewModel.schedulingError)
    }

    func test_saveAlarmTime_failure_setsErrorAndLeavesScheduledTimeNil() async {
        let alarmService = FakeAlarmSchedulingService()
        alarmService.scheduleAlarmError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "denied"])
        let viewModel = HomeViewModel(alarmService: alarmService, store: SwiftDataStreakStore(inMemory: true), aiService: FakeAIContentService())
        viewModel.selectedTime = DateComponents(hour: 7, minute: 30)

        await viewModel.saveAlarmTime()

        XCTAssertNil(viewModel.scheduledTime)
        XCTAssertEqual(viewModel.schedulingError, "denied")
    }
}

import XCTest
@testable import AffirmAlarmCore

@MainActor
final class InsightsViewModelTests: XCTestCase {
    func test_init_loadsGenerationEventsNewestFirst() {
        let store = SwiftDataStreakStore(inMemory: true)
        let older = AffirmationGenerationEvent(date: Date(timeIntervalSince1970: 1), sessionType: .onboarding, generatedTexts: ["a"])
        let newer = AffirmationGenerationEvent(date: Date(timeIntervalSince1970: 2), sessionType: .checkIn, generatedTexts: ["b"])
        store.recordGenerationEvent(older)
        store.recordGenerationEvent(newer)

        let viewModel = InsightsViewModel(store: store)

        XCTAssertEqual(viewModel.events, [newer, older])
    }

    func test_init_withNoEvents_isEmpty() {
        let viewModel = InsightsViewModel(store: SwiftDataStreakStore(inMemory: true))
        XCTAssertTrue(viewModel.events.isEmpty)
    }
}

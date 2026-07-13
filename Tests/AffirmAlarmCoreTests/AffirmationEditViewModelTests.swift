import XCTest
@testable import AffirmAlarmCore

@MainActor
final class AffirmationEditViewModelTests: XCTestCase {
    func test_init_withNoInitialTexts_loadsFromStore() {
        let store = SwiftDataStreakStore(inMemory: true)
        store.save([Affirmation(text: "Existing", isUserAuthored: true)])
        let viewModel = AffirmationEditViewModel(store: store)

        XCTAssertEqual(viewModel.affirmations.map(\.text), ["Existing"])
    }

    func test_init_withInitialTexts_prefillsFromThoseTextsInstead() {
        let store = SwiftDataStreakStore(inMemory: true)
        store.save([Affirmation(text: "Existing", isUserAuthored: true)])
        let viewModel = AffirmationEditViewModel(store: store, initialTexts: ["Generated one", "Generated two"])

        XCTAssertEqual(viewModel.affirmations.map(\.text), ["Generated one", "Generated two"])
    }

    func test_addAffirmation_appendsEmptyEntry() {
        let viewModel = AffirmationEditViewModel(store: SwiftDataStreakStore(inMemory: true), initialTexts: ["One", "Two"])
        viewModel.addAffirmation()
        XCTAssertEqual(viewModel.affirmations.count, 3)
        XCTAssertEqual(viewModel.affirmations.last?.text, "")
    }

    func test_removeAffirmation_removesAtOffset() {
        let viewModel = AffirmationEditViewModel(store: SwiftDataStreakStore(inMemory: true), initialTexts: ["One", "Two"])
        viewModel.removeAffirmation(at: IndexSet(integer: 0))
        XCTAssertEqual(viewModel.affirmations.map(\.text), ["Two"])
    }

    func test_save_succeeds_whenEnoughNonEmptyAffirmationsForStreakDay() {
        let store = SwiftDataStreakStore(inMemory: true)
        store.save(StreakState(streakDay: 1, lastCompletedDate: nil)) // requires 1
        let viewModel = AffirmationEditViewModel(store: store, initialTexts: ["Only one"])

        XCTAssertTrue(viewModel.save())
        XCTAssertNil(viewModel.validationError)
        XCTAssertEqual(store.loadAffirmations().map(\.text), ["Only one"])
    }

    func test_save_fails_whenFewerThanRequiredForStreakDay() {
        let store = SwiftDataStreakStore(inMemory: true)
        store.save(StreakState(streakDay: 20, lastCompletedDate: nil)) // requires 2, per IntensityEngine
        let viewModel = AffirmationEditViewModel(store: store, initialTexts: ["Only one"])

        XCTAssertFalse(viewModel.save())
        XCTAssertNotNil(viewModel.validationError)
    }

    func test_save_ignoresBlankEntriesWhenCountingTowardRequirement() {
        let store = SwiftDataStreakStore(inMemory: true)
        store.save(StreakState(streakDay: 1, lastCompletedDate: nil)) // requires 1
        let viewModel = AffirmationEditViewModel(store: store, initialTexts: ["Real one", "   "])

        XCTAssertTrue(viewModel.save())
        XCTAssertEqual(store.loadAffirmations().map(\.text), ["Real one"])
    }
}

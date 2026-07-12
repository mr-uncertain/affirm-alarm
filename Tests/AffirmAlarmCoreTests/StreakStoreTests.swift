import XCTest
@testable import AffirmAlarmCore

final class StreakStoreTests: XCTestCase {
    func test_loadStreakState_defaultsToDayOneWhenEmpty() {
        let store = SwiftDataStreakStore(inMemory: true)
        let state = store.loadStreakState()
        XCTAssertEqual(state.streakDay, 1)
        XCTAssertNil(state.lastCompletedDate)
    }

    func test_saveThenLoad_roundTripsStreakState() {
        let store = SwiftDataStreakStore(inMemory: true)
        let saved = StreakState(streakDay: 9, lastCompletedDate: Date(timeIntervalSince1970: 1_000_000))
        store.save(saved)
        XCTAssertEqual(store.loadStreakState(), saved)
    }

    func test_loadCloseUsage_defaultsToZeroForCurrentMonthWhenEmpty() {
        let store = SwiftDataStreakStore(inMemory: true)
        let usage = store.loadCloseUsage()
        XCTAssertEqual(usage.usesThisMonth, 0)
    }

    func test_saveThenLoad_roundTripsCloseUsage() {
        let store = SwiftDataStreakStore(inMemory: true)
        let saved = CloseUsageRecord(monthKey: "2026-07", usesThisMonth: 2)
        store.save(saved)
        XCTAssertEqual(store.loadCloseUsage(), saved)
    }

    func test_saveThenLoad_roundTripsAffirmations() {
        let store = SwiftDataStreakStore(inMemory: true)
        let saved = [Affirmation(text: "I am capable", isUserAuthored: true)]
        store.save(saved)
        XCTAssertEqual(store.loadAffirmations(), saved)
    }

    func test_loadAffirmations_preservesSaveOrder() {
        let store = SwiftDataStreakStore(inMemory: true)
        let saved = [
            Affirmation(text: "I am capable", isUserAuthored: true),
            Affirmation(text: "I am strong", isUserAuthored: true),
            Affirmation(text: "I am calm", isUserAuthored: true)
        ]
        store.save(saved)
        XCTAssertEqual(store.loadAffirmations(), saved)
    }
}

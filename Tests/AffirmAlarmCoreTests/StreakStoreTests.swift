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

    func test_freshStore_seedsDefaultAffirmations() {
        let store = SwiftDataStreakStore(inMemory: true)
        let affirmations = store.loadAffirmations()
        XCTAssertGreaterThanOrEqual(affirmations.count, 2)
        XCTAssertTrue(affirmations.allSatisfy { !$0.text.isEmpty })
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

    func test_loadConsentState_defaultsToNotDecidedWhenEmpty() {
        let store = SwiftDataStreakStore(inMemory: true)
        let consent = store.loadConsentState()
        XCTAssertFalse(consent.hasOptedIn)
        XCTAssertNil(consent.decidedAt)
    }

    func test_saveThenLoad_roundTripsConsentState() {
        let store = SwiftDataStreakStore(inMemory: true)
        let saved = ConsentState(hasOptedIn: true, decidedAt: Date(timeIntervalSince1970: 2_000_000))
        store.save(saved)
        XCTAssertEqual(store.loadConsentState(), saved)
    }

    func test_appendChatMessage_thenLoadChatHistory_roundTripsInTimestampOrder() {
        let store = SwiftDataStreakStore(inMemory: true)
        let first = ChatMessage(role: .user, text: "hi", timestamp: Date(timeIntervalSince1970: 1), sessionType: .onboarding)
        let second = ChatMessage(role: .assistant, text: "hello", timestamp: Date(timeIntervalSince1970: 2), sessionType: .onboarding)
        store.appendChatMessage(second)
        store.appendChatMessage(first)

        XCTAssertEqual(store.loadChatHistory(), [first, second])
    }

    func test_recordGenerationEvent_thenLoadGenerationEvents_roundTripsNewestFirst() {
        let store = SwiftDataStreakStore(inMemory: true)
        let older = AffirmationGenerationEvent(date: Date(timeIntervalSince1970: 1), sessionType: .onboarding, generatedTexts: ["a"])
        let newer = AffirmationGenerationEvent(date: Date(timeIntervalSince1970: 2), sessionType: .checkIn, generatedTexts: ["b", "c"])
        store.recordGenerationEvent(older)
        store.recordGenerationEvent(newer)

        XCTAssertEqual(store.loadGenerationEvents(), [newer, older])
    }
}

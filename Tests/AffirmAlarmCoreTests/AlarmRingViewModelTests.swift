import XCTest
@testable import AffirmAlarmCore

final class AlarmRingViewModelTests: XCTestCase {
    func makeViewModel(
        affirmations: [Affirmation] = [Affirmation(text: "I am capable", isUserAuthored: true)],
        streakDay: Int = 1
    ) -> (AlarmRingViewModel, FakeSpeechRecognitionService, FakeAlarmSchedulingService, SwiftDataStreakStore) {
        let store = SwiftDataStreakStore(inMemory: true)
        store.save(affirmations)
        store.save(StreakState(streakDay: streakDay, lastCompletedDate: nil))
        let speech = FakeSpeechRecognitionService()
        let alarm = FakeAlarmSchedulingService()
        let vm = AlarmRingViewModel(speechService: speech, alarmService: alarm, store: store)
        return (vm, speech, alarm, store)
    }

    func test_beginRing_startsInIdleState() {
        let (vm, _, _, _) = makeViewModel()
        vm.beginRing()
        XCTAssertEqual(vm.state, .idle)
    }

    func test_startHolding_movesToListeningAtFirstAffirmation() {
        let (vm, _, _, _) = makeViewModel()
        vm.beginRing()
        vm.startHolding()
        XCTAssertEqual(vm.state, .listening(currentIndex: 0, currentRepeat: 0))
    }

    func test_correctTranscript_advancesRepeatCount() {
        let (vm, speech, _, _) = makeViewModel(streakDay: 7) // day 7 = 1 affirmation x2 repeats
        vm.beginRing()
        vm.startHolding()
        speech.simulateTranscript("I am capable")
        XCTAssertEqual(vm.state, .listening(currentIndex: 0, currentRepeat: 1))
    }

    func test_finalRepeatOfFinalAffirmation_completesSession() {
        let (vm, speech, _, _) = makeViewModel(streakDay: 1) // day 1 = 1 affirmation x1 repeat
        vm.beginRing()
        vm.startHolding()
        speech.simulateTranscript("I am capable")
        XCTAssertEqual(vm.state, .completed)
    }

    func test_completingSession_stopsTheAlarm() {
        let (vm, speech, alarm, _) = makeViewModel(streakDay: 1)
        vm.beginRing()
        vm.startHolding()
        speech.simulateTranscript("I am capable")
        XCTAssertTrue(alarm.wasCancelled)
    }

    func test_completingSession_advancesStreakDayInStore() {
        let (vm, speech, _, store) = makeViewModel(streakDay: 1)
        vm.beginRing()
        vm.startHolding()
        speech.simulateTranscript("I am capable")
        XCTAssertEqual(store.loadStreakState().streakDay, 2)
    }

    func test_releaseHold_beforeMatchResetsCurrentAttemptOnly() {
        let (vm, _, _, _) = makeViewModel(streakDay: 7)
        vm.beginRing()
        vm.startHolding()
        vm.releaseHold()
        XCTAssertEqual(vm.state, .idle)
        vm.startHolding()
        XCTAssertEqual(vm.state, .listening(currentIndex: 0, currentRepeat: 0))
    }

    func test_releaseHold_afterVerifyingOneAffirmation_preservesProgressOnResume() {
        let (vm, speech, _, _) = makeViewModel(
            affirmations: [
                Affirmation(text: "I am capable", isUserAuthored: true),
                Affirmation(text: "I am strong", isUserAuthored: true)
            ],
            streakDay: 14 // 2 affirmations x1 repeat each
        )
        vm.beginRing()
        vm.startHolding()
        speech.simulateTranscript("I am capable")
        XCTAssertEqual(vm.state, .listening(currentIndex: 1, currentRepeat: 0))
        vm.releaseHold()
        XCTAssertEqual(vm.state, .idle)
        vm.startHolding()
        XCTAssertEqual(vm.state, .listening(currentIndex: 1, currentRepeat: 0))
    }

    func test_startHolding_lowersAlarmVolume() {
        let (vm, _, alarm, _) = makeViewModel()
        vm.beginRing()
        vm.startHolding()
        XCTAssertEqual(alarm.volumeLoweredCount, 1)
    }

    func test_releaseHold_restoresAlarmVolume() {
        let (vm, _, alarm, _) = makeViewModel(streakDay: 7)
        vm.beginRing()
        vm.startHolding()
        vm.releaseHold()
        XCTAssertEqual(alarm.volumeRestoredCount, 1)
    }

    func test_beginRing_resetsStreakWhenADayWasMissed() {
        let store = SwiftDataStreakStore(inMemory: true)
        store.save([Affirmation(text: "I am capable", isUserAuthored: true)])
        let calendar = Calendar(identifier: .gregorian)
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: Date())!
        store.save(StreakState(streakDay: 10, lastCompletedDate: twoDaysAgo))
        let vm = AlarmRingViewModel(
            speechService: FakeSpeechRecognitionService(),
            alarmService: FakeAlarmSchedulingService(),
            store: store
        )
        vm.beginRing()
        XCTAssertEqual(store.loadStreakState().streakDay, 1)
    }

    func test_beginRing_doesNotResetStreakWhenCompletedYesterday() {
        let store = SwiftDataStreakStore(inMemory: true)
        store.save([Affirmation(text: "I am capable", isUserAuthored: true)])
        let calendar = Calendar(identifier: .gregorian)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        store.save(StreakState(streakDay: 10, lastCompletedDate: yesterday))
        let vm = AlarmRingViewModel(
            speechService: FakeSpeechRecognitionService(),
            alarmService: FakeAlarmSchedulingService(),
            store: store
        )
        vm.beginRing()
        XCTAssertEqual(store.loadStreakState().streakDay, 10)
    }

    func test_beginRing_doesNotResetOnFirstEverSession() {
        let store = SwiftDataStreakStore(inMemory: true)
        store.save([Affirmation(text: "I am capable", isUserAuthored: true)])
        // lastCompletedDate is nil (SwiftDataStreakStore default) — never completed yet, not a "miss".
        let vm = AlarmRingViewModel(
            speechService: FakeSpeechRecognitionService(),
            alarmService: FakeAlarmSchedulingService(),
            store: store
        )
        vm.beginRing()
        XCTAssertEqual(store.loadStreakState().streakDay, 1)
    }

    func test_tapSnooze_callsAlarmServiceSnoozeAndReturnsToIdle() {
        let (vm, _, alarm, _) = makeViewModel()
        vm.beginRing()
        vm.tapSnooze()
        XCTAssertEqual(alarm.snoozeCallCount, 1)
        XCTAssertEqual(vm.state, .idle)
    }

    func test_canUseClose_trueWithNoPriorUsage() {
        let (vm, _, _, _) = makeViewModel()
        vm.beginRing()
        XCTAssertTrue(vm.canUseClose)
    }

    func test_tapClose_whenAllowed_cancelsAlarmAndResetsStreak() {
        let (vm, _, alarm, store) = makeViewModel(streakDay: 15)
        vm.beginRing()
        vm.tapClose()
        XCTAssertTrue(alarm.wasCancelled)
        XCTAssertEqual(store.loadStreakState().streakDay, 1)
    }

    func test_tapClose_threeTimesInAMonth_disablesFurtherUse() {
        let (vm, _, _, _) = makeViewModel()
        vm.beginRing(); vm.tapClose()
        vm.beginRing(); vm.tapClose()
        vm.beginRing(); vm.tapClose()
        XCTAssertFalse(vm.canUseClose)
    }
}

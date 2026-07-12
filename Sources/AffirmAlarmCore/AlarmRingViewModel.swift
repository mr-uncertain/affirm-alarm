import Foundation
import Combine

public enum RingScreenState: Equatable {
    case idle
    case listening(currentIndex: Int, currentRepeat: Int)
    case completed
}

public final class AlarmRingViewModel: ObservableObject {
    @Published public private(set) var state: RingScreenState = .idle
    @Published public private(set) var canUseClose: Bool = true

    private let speechService: SpeechRecognitionService
    private let alarmService: AlarmSchedulingService
    private let store: StreakStore
    private let now: () -> Date
    private let calendar = Calendar(identifier: .gregorian)

    private var affirmations: [Affirmation] = []
    private var requiredCount = 1
    private var requiredRepeats = 1

    public init(
        speechService: SpeechRecognitionService,
        alarmService: AlarmSchedulingService,
        store: StreakStore,
        now: @escaping () -> Date = Date.init
    ) {
        self.speechService = speechService
        self.alarmService = alarmService
        self.store = store
        self.now = now
    }

    public func beginRing() {
        affirmations = store.loadAffirmations()
        var streakState = store.loadStreakState()
        if hasMissedADay(since: streakState.lastCompletedDate) {
            streakState = StreakState(streakDay: 1, lastCompletedDate: nil)
            store.save(streakState)
        }
        let level = IntensityEngine.level(forStreakDay: streakState.streakDay)
        requiredCount = level.affirmationCount
        requiredRepeats = level.repeatsPerAffirmation
        state = .idle
        canUseClose = CloseUsageTracker.canUseClose(record: store.loadCloseUsage(), now: now(), calendar: calendar)
    }

    public func startHolding() {
        guard case .idle = state else { return }
        state = .listening(currentIndex: 0, currentRepeat: 0)
        alarmService.lowerVolumeForSpeaking()
        listenForCurrentAffirmation()
    }

    public func releaseHold() {
        guard case .listening = state else { return }
        speechService.stopListening()
        alarmService.restoreVolume()
        state = .idle
    }

    /// A "miss" is any completed calendar day with no session finished — i.e. more than
    /// one day elapsed between the last completion and now. `nil` means no session has
    /// ever been completed yet, which is day one of a fresh streak, not a miss.
    private func hasMissedADay(since lastCompletedDate: Date?) -> Bool {
        guard let lastCompletedDate else { return false }
        let today = calendar.startOfDay(for: now())
        let lastDay = calendar.startOfDay(for: lastCompletedDate)
        let daysBetween = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
        return daysBetween > 1
    }

    public func tapSnooze() {
        try? alarmService.snooze(minutes: 9)
        state = .idle
    }

    public func tapClose() {
        let usage = store.loadCloseUsage()
        guard CloseUsageTracker.canUseClose(record: usage, now: now(), calendar: calendar) else { return }
        store.save(CloseUsageTracker.recordingUse(on: usage, now: now(), calendar: calendar))
        resetStreakToStart()
        alarmService.cancelAlarm()
        canUseClose = CloseUsageTracker.canUseClose(record: store.loadCloseUsage(), now: now(), calendar: calendar)
        state = .completed
    }

    private func listenForCurrentAffirmation() {
        guard case let .listening(index, _) = state, index < affirmations.count else { return }
        let target = affirmations[index].text
        speechService.startListening(
            onTranscriptUpdate: { [weak self] transcript in
                self?.handleTranscript(transcript, target: target)
            },
            onError: { _ in }
        )
    }

    private func handleTranscript(_ transcript: String, target: String) {
        guard case let .listening(index, repeatCount) = state else { return }
        guard AffirmationMatcher.matches(transcript: transcript, target: target) else { return }
        speechService.stopListening()

        let nextRepeat = repeatCount + 1
        if nextRepeat < requiredRepeats {
            state = .listening(currentIndex: index, currentRepeat: nextRepeat)
            listenForCurrentAffirmation()
            return
        }

        let nextIndex = index + 1
        if nextIndex < requiredCount && nextIndex < affirmations.count {
            state = .listening(currentIndex: nextIndex, currentRepeat: 0)
            listenForCurrentAffirmation()
            return
        }

        completeSession()
    }

    private func completeSession() {
        advanceStreak()
        alarmService.cancelAlarm()
        state = .completed
    }

    private func advanceStreak() {
        let current = store.loadStreakState()
        store.save(StreakState(streakDay: current.streakDay + 1, lastCompletedDate: now()))
    }

    private func resetStreakToStart() {
        store.save(StreakState(streakDay: 1, lastCompletedDate: nil))
    }
}

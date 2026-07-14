import Foundation
import UserNotifications
@testable import AffirmAlarmCore

final class FakeSpeechRecognitionService: SpeechRecognitionService {
    var onTranscriptUpdate: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    private(set) var isListening = false

    func startListening(onTranscriptUpdate: @escaping (String) -> Void, onError: @escaping (Error) -> Void) {
        self.onTranscriptUpdate = onTranscriptUpdate
        self.onError = onError
        isListening = true
    }

    func stopListening() {
        isListening = false
    }

    // Test helper: simulates the user finishing speaking a transcript.
    func simulateTranscript(_ text: String) {
        onTranscriptUpdate?(text)
    }

    // Test helper: simulates the speech service reporting a failure.
    func simulateError(_ error: Error) {
        onError?(error)
    }
}

final class FakeAlarmSchedulingService: AlarmSchedulingService {
    private(set) var scheduledTime: DateComponents?
    private(set) var wasCancelled = false
    private(set) var snoozeCallCount = 0
    private(set) var volumeLoweredCount = 0
    private(set) var volumeRestoredCount = 0
    private(set) var syncedAlarmID: UUID?
    var alertingIDToReturn: UUID?
    var scheduleAlarmError: Error?
    private var updatesContinuation: AsyncStream<UUID?>.Continuation?

    func scheduleAlarm(at time: DateComponents) async throws {
        if let scheduleAlarmError { throw scheduleAlarmError }
        scheduledTime = time
    }

    func cancelAlarm() {
        wasCancelled = true
    }

    func snooze(minutes: Int) throws {
        snoozeCallCount += 1
    }

    func lowerVolumeForSpeaking() {
        volumeLoweredCount += 1
    }

    func restoreVolume() {
        volumeRestoredCount += 1
    }

    func syncActiveAlarm(id: UUID) {
        syncedAlarmID = id
    }

    func currentlyAlertingAlarmID() async -> UUID? {
        alertingIDToReturn
    }

    func alertingAlarmUpdates() -> AsyncStream<UUID?> {
        AsyncStream { continuation in
            self.updatesContinuation = continuation
        }
    }

    // Test helper: drives the alertingAlarmUpdates() stream.
    func simulateAlertingUpdate(_ id: UUID?) {
        updatesContinuation?.yield(id)
    }
}

final class FakeAIContentService: AIContentService {
    var availabilityToReturn = true
    var sendMessageResult: Result<String, Error> = .success("Thanks for sharing.")
    var generateAffirmationsResult: Result<[String], Error> = .success(["I am capable"])
    private(set) var sentMessages: [String] = []
    private(set) var generateCallCount = 0

    func isAvailable() async -> Bool {
        availabilityToReturn
    }

    func sendMessage(_ message: String, history: [ChatMessage]) async throws -> String {
        sentMessages.append(message)
        return try sendMessageResult.get()
    }

    func generateAffirmations(from history: [ChatMessage]) async throws -> [String] {
        generateCallCount += 1
        return try generateAffirmationsResult.get()
    }
}

final class FakeNotificationScheduling: NotificationScheduling {
    private(set) var addedIdentifiers: [String] = []
    private(set) var lastRemovedIdentifiers: [String] = []
    private(set) var removeCallCount = 0

    func addRequest(_ request: UNNotificationRequest) {
        addedIdentifiers.append(request.identifier)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        lastRemovedIdentifiers = identifiers
        removeCallCount += 1
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        true
    }
}

final class FakeCheckInScheduling: CheckInScheduling {
    private(set) var scheduleCallCount = 0
    private(set) var cancelCallCount = 0

    func scheduleNextCheckIn(from date: Date) async {
        scheduleCallCount += 1
    }

    func cancelPendingCheckIns() {
        cancelCallCount += 1
    }
}

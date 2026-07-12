import Foundation
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

    func scheduleAlarm(at time: DateComponents) throws {
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
}

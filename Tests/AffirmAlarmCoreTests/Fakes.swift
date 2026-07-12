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
}

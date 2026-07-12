import Foundation
import Speech
import AVFoundation

public protocol SpeechRecognitionService: AnyObject {
    func startListening(onTranscriptUpdate: @escaping (String) -> Void, onError: @escaping (Error) -> Void)
    func stopListening()
}

public final class OnDeviceSpeechRecognitionService: NSObject, SpeechRecognitionService {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    public override init() {
        super.init()
    }

    public func startListening(onTranscriptUpdate: @escaping (String) -> Void, onError: @escaping (Error) -> Void) {
        guard let recognizer, recognizer.isAvailable else {
            onError(NSError(domain: "AffirmAlarm.Speech", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer unavailable"]))
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self else { return }
            guard status == .authorized else {
                onError(NSError(domain: "AffirmAlarm.Speech", code: 2, userInfo: [NSLocalizedDescriptionKey: "Speech recognition was not authorized"]))
                return
            }
            self.beginRecognition(onTranscriptUpdate: onTranscriptUpdate, onError: onError)
        }
    }

    private func beginRecognition(onTranscriptUpdate: @escaping (String) -> Void, onError: @escaping (Error) -> Void) {
        guard let recognizer, recognizer.isAvailable else {
            onError(NSError(domain: "AffirmAlarm.Speech", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer unavailable"]))
            return
        }

        // Configure the audio session for recording. Starting a `.record`/`.playAndRecord`
        // session is also what triggers the system microphone permission prompt on iOS —
        // there is no separate explicit request needed alongside speech authorization.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            onError(error)
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            onError(error)
            return
        }

        task = recognizer.recognitionTask(with: request) { result, error in
            if let error {
                onError(error)
                return
            }
            if let result {
                onTranscriptUpdate(result.bestTranscription.formattedString)
            }
        }
    }

    public func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }
}

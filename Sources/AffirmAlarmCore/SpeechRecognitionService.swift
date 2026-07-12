import Foundation
import Speech

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

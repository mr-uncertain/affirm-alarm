import Foundation
import AlarmKit
import AVFoundation
import SwiftUI

public enum AlarmSchedulingError: Error {
    case invalidTime
}

public protocol AlarmSchedulingService: AnyObject {
    func scheduleAlarm(at time: DateComponents) async throws
    func cancelAlarm()
    func snooze(minutes: Int) throws
    func lowerVolumeForSpeaking()
    func restoreVolume()
    func syncActiveAlarm(id: UUID)
    func currentlyAlertingAlarmID() async -> UUID?
    func alertingAlarmUpdates() -> AsyncStream<UUID?>
}

struct AffirmAlarmMetadata: AlarmMetadata {}

public final class AlarmKitSchedulingService: AlarmSchedulingService {
    private var currentAlarmID: UUID?
    private let ringtone = GeneratedTonePlayer()

    public init() {
        // Phase 1 has no home/settings screen yet — AlarmRingView is the entire
        // app UI, so constructing this service happens exactly when the app is
        // launched to handle a firing alarm. Starting the locally-generated
        // ringtone here (rather than from a dedicated "alarm is now ringing"
        // hook, which doesn't exist yet on AlarmRingViewModel) is a Phase 1
        // simplification, not a general-purpose design.
        ringtone.start()
    }

    public func scheduleAlarm(at time: DateComponents) async throws {
        guard let hour = time.hour, let minute = time.minute else {
            throw AlarmSchedulingError.invalidTime
        }
        let id = UUID()

        _ = try await AlarmManager.shared.requestAuthorization()

        // The system now always provides its own Stop button automatically —
        // AlarmPresentation.Alert's `stopButton:` parameter was deprecated in
        // iOS 26.1 and has been removed here. `secondaryButton` +
        // `.custom` is what lets the fired alert's "Open" action launch the
        // app into AlarmRingView; see the Phase 2 design spec's accepted
        // trade-off note on why the system Stop button itself can't be
        // gated or intercepted.
        let openButton = AlarmButton(text: "Open", textColor: .white, systemImageName: "arrow.up.forward.app")
        let alert = AlarmPresentation.Alert(
            title: "AffirmAlarm",
            secondaryButton: openButton,
            secondaryButtonBehavior: .custom
        )
        let presentation = AlarmPresentation(alert: alert)
        let attributes = AlarmAttributes(presentation: presentation, metadata: AffirmAlarmMetadata(), tintColor: .orange)

        let scheduleTime = Alarm.Schedule.Relative.Time(hour: hour, minute: minute)
        let relative = Alarm.Schedule.Relative(time: scheduleTime, repeats: .never)
        let schedule = Alarm.Schedule.relative(relative)

        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: nil,
            schedule: schedule,
            attributes: attributes,
            secondaryIntent: nil,
            sound: .default
        )
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
        currentAlarmID = id
    }

    public func cancelAlarm() {
        // The local ringtone is the only audio Phase 1/2 ever produces (see
        // init() above) and must stop regardless of whether this instance
        // knows the AlarmKit-side id — currentAlarmID only gates the
        // AlarmKit-side stop() call, never the local ringtone.
        if let id = currentAlarmID {
            currentAlarmID = nil
            Task {
                try? await AlarmManager.shared.stop(id: id)
            }
        }
        ringtone.stop()
    }

    public func snooze(minutes: Int) throws {
        // AlarmKit's own post-alert snooze interval is fixed at schedule time
        // and real OS-level snooze requires a Widget Extension (deferred,
        // see Phase 2 design spec). Snoozing here silences the local
        // ringtone only.
        ringtone.stop()
    }

    public func lowerVolumeForSpeaking() {
        ringtone.setVolume(0.08)
    }

    public func restoreVolume() {
        ringtone.setVolume(1.0)
    }

    /// Called by the routing layer (RootViewModel, Task 2) once it discovers
    /// a real alerting alarm's id from AlarmManager on a fresh app launch —
    /// this instance is reconstructed each launch (see AffirmAlarmApp), so
    /// currentAlarmID from a prior session's scheduleAlarm() call is
    /// otherwise lost, leaving cancelAlarm()'s AlarmManager.stop(id:) call
    /// unreachable on the exact launch that matters most.
    public func syncActiveAlarm(id: UUID) {
        currentAlarmID = id
    }

    public func currentlyAlertingAlarmID() async -> UUID? {
        guard let alarms = try? AlarmManager.shared.alarms else { return nil }
        return alarms.first(where: { $0.state == .alerting })?.id
    }

    public func alertingAlarmUpdates() -> AsyncStream<UUID?> {
        AsyncStream { continuation in
            let task = Task {
                for await alarms in AlarmManager.shared.alarmUpdates {
                    let alertingID = alarms.first(where: { $0.state == .alerting })?.id
                    continuation.yield(alertingID)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Exposed for testing: whether the local ringtone is currently playing.
    var isRingtonePlaying: Bool {
        ringtone.isPlaying
    }

    /// Exposed for testing: the local ringtone's current playback volume.
    var ringtoneVolume: Float {
        ringtone.volume
    }
}

/// Generates and loops a simple tone locally so the app can control its
/// volume in real time. AlarmKit exposes no API for an app to adjust the
/// volume of its own alert sound, so "lower but never silence" (a spec
/// requirement) can only be implemented against audio the app itself owns.
final class GeneratedTonePlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private(set) var isPlaying = false

    init() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func start() {
        guard let buffer = makeToneBuffer() else { return }
        do {
            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.play()
            isPlaying = true
        } catch {
            // Best-effort: if the audio engine can't start (e.g. no audio
            // hardware in a CI simulator), the ring screen still functions —
            // volume control simply has nothing to control.
        }
    }

    func stop() {
        player.stop()
        engine.stop()
        isPlaying = false
    }

    func setVolume(_ volume: Float) {
        player.volume = volume
    }

    var volume: Float {
        player.volume
    }

    private func makeToneBuffer() -> AVAudioPCMBuffer? {
        let sampleRate = 44_100.0
        let duration = 1.0
        let frequency = 880.0
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData?[0] else { return nil }
        for frame in 0..<Int(frameCount) {
            let sampleTime = Double(frame) / sampleRate
            channelData[frame] = Float(sin(2.0 * Double.pi * frequency * sampleTime))
        }
        return buffer
    }
}

import Foundation
import AlarmKit
import AVFoundation
import SwiftUI

public enum AlarmSchedulingError: Error {
    case invalidTime
}

public protocol AlarmSchedulingService: AnyObject {
    func scheduleAlarm(at time: DateComponents) throws
    func cancelAlarm()
    func snooze(minutes: Int) throws
    func lowerVolumeForSpeaking()
    func restoreVolume()
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

    public func scheduleAlarm(at time: DateComponents) throws {
        guard let hour = time.hour, let minute = time.minute else {
            throw AlarmSchedulingError.invalidTime
        }
        let id = UUID()
        currentAlarmID = id

        // AlarmManager's real API is async; this protocol's callers (see
        // AlarmRingViewModel) are synchronous and Phase 1 has no alarm-setting
        // UI yet to synchronously await a result, so scheduling is bridged as
        // fire-and-forget. Errors are swallowed here deliberately — there is no
        // synchronous caller to propagate them to yet.
        Task {
            do {
                _ = try await AlarmManager.shared.requestAuthorization()

                let stopButton = AlarmButton(text: "Done", textColor: .white, systemImageName: "checkmark")
                let alert = AlarmPresentation.Alert(title: "AffirmAlarm", stopButton: stopButton)
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
            } catch {
                // Best-effort: see comment above.
            }
        }
    }

    public func cancelAlarm() {
        // The local ringtone is the only audio Phase 1 ever produces (see
        // init() above) and must stop regardless of whether a real AlarmKit
        // alarm was ever scheduled — `currentAlarmID` only gates the
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
        // AlarmKit's own post-alert snooze interval is fixed at schedule time.
        // Phase 1 has no alarm-setting UI to source a re-schedule configuration
        // from, so snoozing here just silences the local ringtone; real
        // re-arming after `minutes` is deferred to the phase that adds
        // alarm-setting.
        ringtone.stop()
    }

    public func lowerVolumeForSpeaking() {
        ringtone.setVolume(0.08)
    }

    public func restoreVolume() {
        ringtone.setVolume(1.0)
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

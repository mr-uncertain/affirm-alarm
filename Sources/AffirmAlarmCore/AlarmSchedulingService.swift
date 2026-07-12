import Foundation
import AlarmKit // Confirm this import and the API below against current Apple docs before merging.

public protocol AlarmSchedulingService: AnyObject {
    func scheduleAlarm(at time: DateComponents) throws
    func cancelAlarm()
    func snooze(minutes: Int) throws
    func lowerVolumeForSpeaking()
    func restoreVolume()
}

public final class AlarmKitSchedulingService: AlarmSchedulingService {
    public init() {}

    public func scheduleAlarm(at time: DateComponents) throws {
        // Body intentionally unimplemented until the AlarmManager/AlarmConfiguration
        // API shape is confirmed against current AlarmKit docs (see Task 7, Step 1).
        fatalError("AlarmKitSchedulingService.scheduleAlarm not yet implemented — verify AlarmKit API first")
    }

    public func cancelAlarm() {
        fatalError("AlarmKitSchedulingService.cancelAlarm not yet implemented — verify AlarmKit API first")
    }

    public func snooze(minutes: Int) throws {
        fatalError("AlarmKitSchedulingService.snooze not yet implemented — verify AlarmKit API first")
    }

    public func lowerVolumeForSpeaking() {
        // AlarmKit may expose a volume/ducking control directly, or this may need to
        // go through AVAudioSession instead — confirm against current docs (Task 7, Step 1).
        fatalError("AlarmKitSchedulingService.lowerVolumeForSpeaking not yet implemented — verify AlarmKit API first")
    }

    public func restoreVolume() {
        fatalError("AlarmKitSchedulingService.restoreVolume not yet implemented — verify AlarmKit API first")
    }
}

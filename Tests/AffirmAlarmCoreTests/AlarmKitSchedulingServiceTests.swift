import XCTest
@testable import AffirmAlarmCore

final class AlarmKitSchedulingServiceTests: XCTestCase {
    // Regression: cancelAlarm() previously only stopped the local ringtone
    // when scheduleAlarm() had already set currentAlarmID — but Phase 1's
    // AlarmRingViewModel never calls scheduleAlarm(), so the ringtone could
    // never actually be silenced.
    func test_cancelAlarm_stopsRingtone_evenWithoutScheduledAlarm() {
        let service = AlarmKitSchedulingService()

        service.cancelAlarm()

        XCTAssertFalse(service.isRingtonePlaying)
    }

    // Same regression as above, for snooze().
    func test_snooze_stopsRingtone_evenWithoutScheduledAlarm() {
        let service = AlarmKitSchedulingService()

        XCTAssertNoThrow(try service.snooze(minutes: 9))
        XCTAssertFalse(service.isRingtonePlaying)
    }

    func test_lowerVolumeForSpeaking_neverFullySilencesRingtone() {
        let service = AlarmKitSchedulingService()

        service.lowerVolumeForSpeaking()

        XCTAssertGreaterThan(service.ringtoneVolume, 0)
    }

    func test_restoreVolume_setsFullVolume() {
        let service = AlarmKitSchedulingService()

        service.lowerVolumeForSpeaking()
        service.restoreVolume()

        XCTAssertEqual(service.ringtoneVolume, 1.0)
    }
}

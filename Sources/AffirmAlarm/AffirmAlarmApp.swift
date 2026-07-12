import SwiftUI
import AffirmAlarmCore

@main
struct AffirmAlarmApp: App {
    var body: some Scene {
        WindowGroup {
            AlarmRingView(
                viewModel: AlarmRingViewModel(
                    speechService: OnDeviceSpeechRecognitionService(),
                    alarmService: AlarmKitSchedulingService(),
                    store: SwiftDataStreakStore()
                )
            )
        }
    }
}

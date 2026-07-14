import SwiftUI
import AffirmAlarmCore

@main
struct AffirmAlarmApp: App {
    var body: some Scene {
        WindowGroup {
            let alarmService = AlarmKitSchedulingService()
            let store = SwiftDataStreakStore()
            let aiService = OnDeviceAIContentService()

            RootView(
                rootViewModel: RootViewModel(alarmService: alarmService),
                alarmRingViewModel: AlarmRingViewModel(
                    speechService: OnDeviceSpeechRecognitionService(),
                    alarmService: alarmService,
                    store: store
                ),
                homeViewModel: HomeViewModel(
                    alarmService: alarmService,
                    store: store,
                    aiService: aiService
                )
            )
        }
    }
}

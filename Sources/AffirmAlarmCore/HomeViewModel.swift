import Foundation

@MainActor
public final class HomeViewModel: ObservableObject {
    @Published public var selectedTime = DateComponents(hour: 7, minute: 0)
    @Published public private(set) var scheduledTime: DateComponents?
    @Published public private(set) var schedulingError: String?
    @Published public private(set) var streakDay: Int

    private let alarmService: AlarmSchedulingService
    public let store: StreakStore
    public let aiService: AIContentService

    public enum ChatEntryDestination: Equatable {
        case chat
        case editAffirmationsDirectly
    }

    public init(alarmService: AlarmSchedulingService, store: StreakStore, aiService: AIContentService) {
        self.alarmService = alarmService
        self.store = store
        self.aiService = aiService
        self.streakDay = store.loadStreakState().streakDay
    }

    public func resolveChatEntry() async -> ChatEntryDestination {
        await aiService.isAvailable() ? .chat : .editAffirmationsDirectly
    }

    public func saveAlarmTime() async {
        schedulingError = nil
        do {
            try await alarmService.scheduleAlarm(at: selectedTime)
            scheduledTime = selectedTime
        } catch {
            schedulingError = error.localizedDescription
        }
    }
}

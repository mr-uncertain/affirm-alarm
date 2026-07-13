import Foundation

@MainActor
public final class RootViewModel: ObservableObject {
    public enum Route: Equatable {
        case home
        case ringing
    }

    @Published public private(set) var route: Route = .home

    private let alarmService: AlarmSchedulingService
    private var updatesTask: Task<Void, Never>?

    public init(alarmService: AlarmSchedulingService) {
        self.alarmService = alarmService
    }

    public func start() async {
        // UI-test-only hook: real AlarmKit alerts cannot be simulated in the
        // CI simulator, so a launch argument forces the ringing route
        // directly for AlarmRingUITests, bypassing any real AlarmManager call.
        if ProcessInfo.processInfo.arguments.contains("-uiTestForceRinging") {
            route = .ringing
            return
        }

        if let alertingID = await alarmService.currentlyAlertingAlarmID() {
            alarmService.syncActiveAlarm(id: alertingID)
            route = .ringing
        }
        observeUpdates()
    }

    private func observeUpdates() {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            guard let self else { return }
            for await alertingID in alarmService.alertingAlarmUpdates() {
                await self.handleUpdate(alertingID: alertingID)
            }
        }
    }

    private func handleUpdate(alertingID: UUID?) async {
        if let alertingID {
            alarmService.syncActiveAlarm(id: alertingID)
            route = .ringing
        } else if route == .ringing {
            alarmService.cancelAlarm()
            route = .home
        }
    }
}

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
        // Obtain the stream synchronously, here on the caller's turn, rather
        // than inside the Task below: alertingAlarmUpdates() is what
        // registers the subscription (the AsyncStream's continuation), and
        // that registration must be in place before start() returns —
        // otherwise an update that arrives immediately after start() would
        // race an unstructured Task that hasn't begun running yet and be
        // silently dropped.
        //
        // The consuming Task is pinned to @MainActor explicitly (matching
        // AlarmRingViewModel's speechService callback-bridging pattern)
        // rather than relying on isolation being inferred from this
        // MainActor method: without it, this Task can start running on a
        // different executor, so a single `await Task.yield()` in a
        // @MainActor test isn't guaranteed to give it a turn before the
        // test's assertions run.
        let updates = alarmService.alertingAlarmUpdates()
        updatesTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await alertingID in updates {
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

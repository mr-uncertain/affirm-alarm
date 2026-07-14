import Foundation
import UserNotifications

public protocol NotificationScheduling {
    func addRequest(_ request: UNNotificationRequest)
    func removePendingRequests(withIdentifiers identifiers: [String])
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
}

extension UNUserNotificationCenter: NotificationScheduling {
    public func addRequest(_ request: UNNotificationRequest) {
        add(request)
    }

    public func removePendingRequests(withIdentifiers identifiers: [String]) {
        removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

public protocol CheckInScheduling {
    func scheduleNextCheckIn(from date: Date) async
    func cancelPendingCheckIns()
}

public final class LocalNotificationCheckInScheduler: CheckInScheduling {
    private static let checkInIdentifier = "affirmalarm.checkin"
    private static let followUpIdentifier = "affirmalarm.checkin.followup"
    private static let checkInInterval: TimeInterval = 7 * 24 * 60 * 60
    private static let followUpInterval: TimeInterval = 10 * 24 * 60 * 60

    private let center: NotificationScheduling

    public init(center: NotificationScheduling = UNUserNotificationCenter.current()) {
        self.center = center
    }

    public func scheduleNextCheckIn(from date: Date) async {
        cancelPendingCheckIns()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])

        let checkInContent = UNMutableNotificationContent()
        checkInContent.title = "Time for a check-in"
        checkInContent.body = "How are things going? Let's revisit your affirmations."
        let checkInTrigger = UNTimeIntervalNotificationTrigger(timeInterval: Self.checkInInterval, repeats: false)
        center.addRequest(UNNotificationRequest(identifier: Self.checkInIdentifier, content: checkInContent, trigger: checkInTrigger))

        let followUpContent = UNMutableNotificationContent()
        followUpContent.title = "Still there?"
        followUpContent.body = "Your check-in is waiting whenever you're ready."
        let followUpTrigger = UNTimeIntervalNotificationTrigger(timeInterval: Self.followUpInterval, repeats: false)
        center.addRequest(UNNotificationRequest(identifier: Self.followUpIdentifier, content: followUpContent, trigger: followUpTrigger))
    }

    public func cancelPendingCheckIns() {
        center.removePendingRequests(withIdentifiers: [Self.checkInIdentifier, Self.followUpIdentifier])
    }
}

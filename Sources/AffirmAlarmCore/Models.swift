import Foundation

public struct Affirmation: Identifiable, Codable, Equatable {
    public let id: UUID
    public var text: String
    public var isUserAuthored: Bool

    public init(id: UUID = UUID(), text: String, isUserAuthored: Bool) {
        self.id = id
        self.text = text
        self.isUserAuthored = isUserAuthored
    }
}

public struct StreakState: Codable, Equatable {
    public var streakDay: Int
    public var lastCompletedDate: Date?

    public init(streakDay: Int, lastCompletedDate: Date?) {
        self.streakDay = streakDay
        self.lastCompletedDate = lastCompletedDate
    }
}

public struct CloseUsageRecord: Codable, Equatable {
    public var monthKey: String
    public var usesThisMonth: Int

    public init(monthKey: String, usesThisMonth: Int) {
        self.monthKey = monthKey
        self.usesThisMonth = usesThisMonth
    }
}

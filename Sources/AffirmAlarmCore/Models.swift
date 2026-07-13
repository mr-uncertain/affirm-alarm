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

public enum ChatRole: String, Codable, Equatable {
    case user
    case assistant
}

public enum ChatSessionType: String, Codable, Equatable {
    case onboarding
    case checkIn
}

public struct ChatMessage: Identifiable, Codable, Equatable {
    public let id: UUID
    public var role: ChatRole
    public var text: String
    public var timestamp: Date
    public var sessionType: ChatSessionType

    public init(id: UUID = UUID(), role: ChatRole, text: String, timestamp: Date, sessionType: ChatSessionType) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.sessionType = sessionType
    }
}

public struct AffirmationGenerationEvent: Identifiable, Codable, Equatable {
    public let id: UUID
    public var date: Date
    public var sessionType: ChatSessionType
    public var generatedTexts: [String]

    public init(id: UUID = UUID(), date: Date, sessionType: ChatSessionType, generatedTexts: [String]) {
        self.id = id
        self.date = date
        self.sessionType = sessionType
        self.generatedTexts = generatedTexts
    }
}

public struct ConsentState: Codable, Equatable {
    public var hasOptedIn: Bool
    public var decidedAt: Date?

    public init(hasOptedIn: Bool, decidedAt: Date?) {
        self.hasOptedIn = hasOptedIn
        self.decidedAt = decidedAt
    }
}

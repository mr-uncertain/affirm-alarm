import Foundation
import SwiftData

@Model
final class StreakStateRecord {
    var streakDay: Int
    var lastCompletedDate: Date?
    init(streakDay: Int, lastCompletedDate: Date?) {
        self.streakDay = streakDay
        self.lastCompletedDate = lastCompletedDate
    }
}

@Model
final class CloseUsageRecordEntity {
    var monthKey: String
    var usesThisMonth: Int
    init(monthKey: String, usesThisMonth: Int) {
        self.monthKey = monthKey
        self.usesThisMonth = usesThisMonth
    }
}

@Model
final class AffirmationRecord {
    var id: UUID
    var text: String
    var isUserAuthored: Bool
    var sortOrder: Int
    init(id: UUID, text: String, isUserAuthored: Bool, sortOrder: Int) {
        self.id = id
        self.text = text
        self.isUserAuthored = isUserAuthored
        self.sortOrder = sortOrder
    }
}

@Model
final class ChatMessageRecord {
    var id: UUID
    var role: ChatRole
    var text: String
    var timestamp: Date
    var sessionType: ChatSessionType
    init(id: UUID, role: ChatRole, text: String, timestamp: Date, sessionType: ChatSessionType) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.sessionType = sessionType
    }
}

@Model
final class AffirmationGenerationEventRecord {
    var id: UUID
    var date: Date
    var sessionType: ChatSessionType
    var generatedTexts: [String]
    init(id: UUID, date: Date, sessionType: ChatSessionType, generatedTexts: [String]) {
        self.id = id
        self.date = date
        self.sessionType = sessionType
        self.generatedTexts = generatedTexts
    }
}

@Model
final class ConsentStateRecord {
    var hasOptedIn: Bool
    var decidedAt: Date?
    init(hasOptedIn: Bool, decidedAt: Date?) {
        self.hasOptedIn = hasOptedIn
        self.decidedAt = decidedAt
    }
}

public protocol StreakStore {
    func loadStreakState() -> StreakState
    func save(_ state: StreakState)
    func loadCloseUsage() -> CloseUsageRecord
    func save(_ usage: CloseUsageRecord)
    func loadAffirmations() -> [Affirmation]
    func save(_ affirmations: [Affirmation])
    func loadConsentState() -> ConsentState
    func save(_ consent: ConsentState)
    func appendChatMessage(_ message: ChatMessage)
    func loadChatHistory() -> [ChatMessage]
    func recordGenerationEvent(_ event: AffirmationGenerationEvent)
    func loadGenerationEvents() -> [AffirmationGenerationEvent]
}

public final class SwiftDataStreakStore: StreakStore {
    private let container: ModelContainer
    private let context: ModelContext

    /// Phase 1 has no affirmation-authoring UI yet, so a fresh install with an
    /// empty store would otherwise leave `listenForCurrentAffirmation()` with
    /// nothing to listen for (see `AlarmRingViewModel.beginRing()`). At least 2
    /// entries are required because `IntensityEngine` uses up to 2 affirmations
    /// at once for higher streak days.
    static let defaultAffirmations = [
        Affirmation(text: "I am capable of starting my day", isUserAuthored: false),
        Affirmation(text: "I choose to show up for myself today", isUserAuthored: false)
    ]

    public init(inMemory: Bool = false) {
        let schema = Schema([
            StreakStateRecord.self,
            CloseUsageRecordEntity.self,
            AffirmationRecord.self,
            ChatMessageRecord.self,
            AffirmationGenerationEventRecord.self,
            ConsentStateRecord.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        container = try! ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)

        if loadAffirmations().isEmpty {
            save(Self.defaultAffirmations)
        }
    }

    public func loadStreakState() -> StreakState {
        let records = try? context.fetch(FetchDescriptor<StreakStateRecord>())
        guard let record = records?.first else { return StreakState(streakDay: 1, lastCompletedDate: nil) }
        return StreakState(streakDay: record.streakDay, lastCompletedDate: record.lastCompletedDate)
    }

    public func save(_ state: StreakState) {
        let existing = try? context.fetch(FetchDescriptor<StreakStateRecord>())
        existing?.forEach { context.delete($0) }
        context.insert(StreakStateRecord(streakDay: state.streakDay, lastCompletedDate: state.lastCompletedDate))
        try? context.save()
    }

    public func loadCloseUsage() -> CloseUsageRecord {
        let records = try? context.fetch(FetchDescriptor<CloseUsageRecordEntity>())
        guard let record = records?.first else { return CloseUsageRecord(monthKey: "", usesThisMonth: 0) }
        return CloseUsageRecord(monthKey: record.monthKey, usesThisMonth: record.usesThisMonth)
    }

    public func save(_ usage: CloseUsageRecord) {
        let existing = try? context.fetch(FetchDescriptor<CloseUsageRecordEntity>())
        existing?.forEach { context.delete($0) }
        context.insert(CloseUsageRecordEntity(monthKey: usage.monthKey, usesThisMonth: usage.usesThisMonth))
        try? context.save()
    }

    public func loadAffirmations() -> [Affirmation] {
        let descriptor = FetchDescriptor<AffirmationRecord>(sortBy: [SortDescriptor(\.sortOrder)])
        let records = (try? context.fetch(descriptor)) ?? []
        return records.map { Affirmation(id: $0.id, text: $0.text, isUserAuthored: $0.isUserAuthored) }
    }

    public func save(_ affirmations: [Affirmation]) {
        let existing = try? context.fetch(FetchDescriptor<AffirmationRecord>())
        existing?.forEach { context.delete($0) }
        for (index, a) in affirmations.enumerated() {
            context.insert(AffirmationRecord(id: a.id, text: a.text, isUserAuthored: a.isUserAuthored, sortOrder: index))
        }
        try? context.save()
    }

    public func loadConsentState() -> ConsentState {
        let records = try? context.fetch(FetchDescriptor<ConsentStateRecord>())
        guard let record = records?.first else { return ConsentState(hasOptedIn: false, decidedAt: nil) }
        return ConsentState(hasOptedIn: record.hasOptedIn, decidedAt: record.decidedAt)
    }

    public func save(_ consent: ConsentState) {
        let existing = try? context.fetch(FetchDescriptor<ConsentStateRecord>())
        existing?.forEach { context.delete($0) }
        context.insert(ConsentStateRecord(hasOptedIn: consent.hasOptedIn, decidedAt: consent.decidedAt))
        try? context.save()
    }

    public func appendChatMessage(_ message: ChatMessage) {
        context.insert(ChatMessageRecord(id: message.id, role: message.role, text: message.text, timestamp: message.timestamp, sessionType: message.sessionType))
        try? context.save()
    }

    public func loadChatHistory() -> [ChatMessage] {
        let descriptor = FetchDescriptor<ChatMessageRecord>(sortBy: [SortDescriptor(\.timestamp)])
        let records = (try? context.fetch(descriptor)) ?? []
        return records.map { ChatMessage(id: $0.id, role: $0.role, text: $0.text, timestamp: $0.timestamp, sessionType: $0.sessionType) }
    }

    public func recordGenerationEvent(_ event: AffirmationGenerationEvent) {
        context.insert(AffirmationGenerationEventRecord(id: event.id, date: event.date, sessionType: event.sessionType, generatedTexts: event.generatedTexts))
        try? context.save()
    }

    public func loadGenerationEvents() -> [AffirmationGenerationEvent] {
        let descriptor = FetchDescriptor<AffirmationGenerationEventRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let records = (try? context.fetch(descriptor)) ?? []
        return records.map { AffirmationGenerationEvent(id: $0.id, date: $0.date, sessionType: $0.sessionType, generatedTexts: $0.generatedTexts) }
    }
}

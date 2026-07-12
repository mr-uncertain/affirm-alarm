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

public protocol StreakStore {
    func loadStreakState() -> StreakState
    func save(_ state: StreakState)
    func loadCloseUsage() -> CloseUsageRecord
    func save(_ usage: CloseUsageRecord)
    func loadAffirmations() -> [Affirmation]
    func save(_ affirmations: [Affirmation])
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
        let schema = Schema([StreakStateRecord.self, CloseUsageRecordEntity.self, AffirmationRecord.self])
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
}

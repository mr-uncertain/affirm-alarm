import Foundation

public enum CloseUsageTracker {
    public static let monthlyLimit = 3

    public static func monthKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year!, components.month!)
    }

    public static func canUseClose(record: CloseUsageRecord, now: Date, calendar: Calendar) -> Bool {
        let currentKey = monthKey(for: now, calendar: calendar)
        guard record.monthKey == currentKey else { return true }
        return record.usesThisMonth < monthlyLimit
    }

    public static func recordingUse(on record: CloseUsageRecord, now: Date, calendar: Calendar) -> CloseUsageRecord {
        let currentKey = monthKey(for: now, calendar: calendar)
        guard record.monthKey == currentKey else {
            return CloseUsageRecord(monthKey: currentKey, usesThisMonth: 1)
        }
        return CloseUsageRecord(monthKey: currentKey, usesThisMonth: record.usesThisMonth + 1)
    }
}

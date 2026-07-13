import Foundation

public enum AIContentError: Error {
    case unavailable
    case generationFailed
}

public protocol AIContentService: AnyObject {
    func isAvailable() async -> Bool
    func sendMessage(_ message: String, history: [ChatMessage]) async throws -> String
    func generateAffirmations(from history: [ChatMessage]) async throws -> [String]
}

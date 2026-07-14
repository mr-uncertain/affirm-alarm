import Foundation

public enum AIContentError: LocalizedError {
    case unavailable
    case generationFailed

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "AI features aren't available on this device right now."
        case .generationFailed:
            return "Something went wrong generating a response. Please try again."
        }
    }
}

public protocol AIContentService: AnyObject {
    func isAvailable() async -> Bool
    func sendMessage(_ message: String, history: [ChatMessage]) async throws -> String
    func generateAffirmations(from history: [ChatMessage]) async throws -> [String]
}

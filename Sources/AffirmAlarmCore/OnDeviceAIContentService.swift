import Foundation
import FoundationModels

@Generable
struct AffirmationList {
    @Guide(description: "A list of short, second-person, present-tense affirmations based on the conversation.")
    var affirmations: [String]
}

public final class OnDeviceAIContentService: AIContentService {
    public init() {}

    public func isAvailable() async -> Bool {
        switch SystemLanguageModel.default.availability {
        case .available:
            return true
        case .unavailable:
            return false
        @unknown default:
            return false
        }
    }

    public func sendMessage(_ message: String, history: [ChatMessage]) async throws -> String {
        guard await isAvailable() else { throw AIContentError.unavailable }
        let session = LanguageModelSession(transcript: Self.transcript(from: history))
        do {
            let response = try await session.respond(to: message)
            return response.content
        } catch {
            throw AIContentError.generationFailed
        }
    }

    public func generateAffirmations(from history: [ChatMessage]) async throws -> [String] {
        guard await isAvailable() else { throw AIContentError.unavailable }
        let session = LanguageModelSession(transcript: Self.transcript(from: history))
        do {
            let response = try await session.respond(
                to: "Based on this conversation, write the affirmations we discussed.",
                generating: AffirmationList.self
            )
            return response.content.affirmations
        } catch {
            throw AIContentError.generationFailed
        }
    }

    private static func transcript(from history: [ChatMessage]) -> Transcript {
        Transcript(entries: history.map { message in
            switch message.role {
            case .user:
                return .prompt(Transcript.Prompt(segments: [.text(Transcript.TextSegment(content: message.text))]))
            case .assistant:
                return .response(Transcript.Response(assetIDs: [], segments: [.text(Transcript.TextSegment(content: message.text))]))
            }
        })
    }
}

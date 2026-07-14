import Foundation

public enum ChatTurnState: Equatable {
    case idle
    case sending
    case error(String)
}

@MainActor
public final class ChatViewModel: ObservableObject {
    @Published public private(set) var messages: [ChatMessage] = []
    @Published public private(set) var turnState: ChatTurnState = .idle
    @Published public private(set) var needsConsentDecision = false
    @Published public private(set) var canGenerate = false
    @Published public private(set) var generatedAffirmations: [String]?

    private let aiService: AIContentService
    private let store: StreakStore
    private let sessionType: ChatSessionType
    private let checkInScheduler: CheckInScheduling
    private let now: () -> Date

    public init(
        aiService: AIContentService,
        store: StreakStore,
        sessionType: ChatSessionType,
        checkInScheduler: CheckInScheduling,
        now: @escaping () -> Date = Date.init
    ) {
        self.aiService = aiService
        self.store = store
        self.sessionType = sessionType
        self.checkInScheduler = checkInScheduler
        self.now = now
    }

    public func start() async {
        let consent = store.loadConsentState()
        guard consent.decidedAt != nil else {
            needsConsentDecision = true
            return
        }
        loadHistoryIfConsented(consent)
    }

    public func recordConsent(optedIn: Bool) {
        store.save(ConsentState(hasOptedIn: optedIn, decidedAt: now()))
        needsConsentDecision = false
        loadHistoryIfConsented(store.loadConsentState())
    }

    public func send(_ text: String) async {
        // If the trailing message is an unanswered user message with this same text, this is a
        // retry of a previously failed send (see ChatView's Retry button, which re-calls send(_:)
        // with the same text). Reuse the already-appended, already-persisted message instead of
        // creating a duplicate.
        let isRetryOfUnansweredMessage = messages.last?.role == .user && messages.last?.text == text
        if !isRetryOfUnansweredMessage {
            let userMessage = ChatMessage(role: .user, text: text, timestamp: now(), sessionType: sessionType)
            messages.append(userMessage)
            persistIfConsented(userMessage)
        }
        turnState = .sending
        do {
            let reply = try await aiService.sendMessage(text, history: messages)
            let assistantMessage = ChatMessage(role: .assistant, text: reply, timestamp: now(), sessionType: sessionType)
            messages.append(assistantMessage)
            persistIfConsented(assistantMessage)
            turnState = .idle
            canGenerate = true
        } catch {
            turnState = .error(error.localizedDescription)
        }
    }

    public func generateAffirmations() async {
        turnState = .sending
        do {
            let texts = try await aiService.generateAffirmations(from: messages)
            generatedAffirmations = texts
            persistGenerationEventIfConsented(texts)
            await checkInScheduler.scheduleNextCheckIn(from: now())
            turnState = .idle
        } catch {
            turnState = .error(error.localizedDescription)
        }
    }

    public func continueWithoutAI() {
        generatedAffirmations = []
    }

    private func loadHistoryIfConsented(_ consent: ConsentState) {
        guard consent.hasOptedIn else { return }
        messages = store.loadChatHistory()
    }

    private func persistIfConsented(_ message: ChatMessage) {
        guard store.loadConsentState().hasOptedIn else { return }
        store.appendChatMessage(message)
    }

    private func persistGenerationEventIfConsented(_ texts: [String]) {
        guard store.loadConsentState().hasOptedIn else { return }
        store.recordGenerationEvent(AffirmationGenerationEvent(date: now(), sessionType: sessionType, generatedTexts: texts))
    }
}

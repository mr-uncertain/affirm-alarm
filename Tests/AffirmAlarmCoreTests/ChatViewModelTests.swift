import XCTest
@testable import AffirmAlarmCore

@MainActor
final class ChatViewModelTests: XCTestCase {
    func test_start_needsConsentDecision_whenNeverDecided() async {
        let viewModel = makeViewModel()
        await viewModel.start()
        XCTAssertTrue(viewModel.needsConsentDecision)
    }

    func test_start_loadsHistory_whenPreviouslyOptedIn() async {
        let store = SwiftDataStreakStore(inMemory: true)
        store.save(ConsentState(hasOptedIn: true, decidedAt: Date()))
        let existing = ChatMessage(role: .user, text: "hi", timestamp: Date(), sessionType: .onboarding)
        store.appendChatMessage(existing)
        let viewModel = makeViewModel(store: store)

        await viewModel.start()

        XCTAssertFalse(viewModel.needsConsentDecision)
        XCTAssertEqual(viewModel.messages, [existing])
    }

    func test_start_doesNotLoadHistory_whenPreviouslyDeclined() async {
        let store = SwiftDataStreakStore(inMemory: true)
        store.save(ConsentState(hasOptedIn: false, decidedAt: Date()))
        store.appendChatMessage(ChatMessage(role: .user, text: "leftover", timestamp: Date(), sessionType: .onboarding))
        let viewModel = makeViewModel(store: store)

        await viewModel.start()

        XCTAssertTrue(viewModel.messages.isEmpty)
    }

    func test_recordConsent_optIn_clearsNeedsDecisionAndPersists() {
        let store = SwiftDataStreakStore(inMemory: true)
        let viewModel = makeViewModel(store: store)

        viewModel.recordConsent(optedIn: true)

        XCTAssertFalse(viewModel.needsConsentDecision)
        XCTAssertTrue(store.loadConsentState().hasOptedIn)
    }

    func test_send_appendsUserAndAssistantMessages_andEnablesGenerate() async {
        let ai = FakeAIContentService()
        ai.sendMessageResult = .success("Good to hear.")
        let viewModel = makeViewModel(ai: ai)
        viewModel.recordConsent(optedIn: false)

        await viewModel.send("I'm doing well")

        XCTAssertEqual(viewModel.messages.map(\.text), ["I'm doing well", "Good to hear."])
        XCTAssertTrue(viewModel.canGenerate)
        XCTAssertEqual(viewModel.turnState, .idle)
    }

    func test_send_persistsMessages_onlyWhenOptedIn() async {
        let store = SwiftDataStreakStore(inMemory: true)
        let viewModel = makeViewModel(store: store)
        viewModel.recordConsent(optedIn: true)

        await viewModel.send("hello")

        XCTAssertEqual(store.loadChatHistory().count, 2)
    }

    func test_send_doesNotPersist_whenDeclined() async {
        let store = SwiftDataStreakStore(inMemory: true)
        let viewModel = makeViewModel(store: store)
        viewModel.recordConsent(optedIn: false)

        await viewModel.send("hello")

        XCTAssertTrue(store.loadChatHistory().isEmpty)
    }

    func test_send_failure_setsErrorState() async {
        let ai = FakeAIContentService()
        ai.sendMessageResult = .failure(AIContentError.generationFailed)
        let viewModel = makeViewModel(ai: ai)
        viewModel.recordConsent(optedIn: false)

        await viewModel.send("hello")

        guard case .error = viewModel.turnState else {
            return XCTFail("expected .error turnState")
        }
    }

    func test_generateAffirmations_success_setsGeneratedAffirmationsAndPersistsEventWhenOptedIn() async {
        let store = SwiftDataStreakStore(inMemory: true)
        let ai = FakeAIContentService()
        ai.generateAffirmationsResult = .success(["I am capable", "I am calm"])
        let viewModel = makeViewModel(ai: ai, store: store)
        viewModel.recordConsent(optedIn: true)

        await viewModel.generateAffirmations()

        XCTAssertEqual(viewModel.generatedAffirmations, ["I am capable", "I am calm"])
        XCTAssertEqual(store.loadGenerationEvents().first?.generatedTexts, ["I am capable", "I am calm"])
    }

    func test_generateAffirmations_failure_setsErrorState() async {
        let ai = FakeAIContentService()
        ai.generateAffirmationsResult = .failure(AIContentError.generationFailed)
        let viewModel = makeViewModel(ai: ai)
        viewModel.recordConsent(optedIn: false)

        await viewModel.generateAffirmations()

        guard case .error = viewModel.turnState else {
            return XCTFail("expected .error turnState")
        }
        XCTAssertNil(viewModel.generatedAffirmations)
    }

    private func makeViewModel(
        ai: FakeAIContentService = FakeAIContentService(),
        store: StreakStore = SwiftDataStreakStore(inMemory: true),
        sessionType: ChatSessionType = .onboarding
    ) -> ChatViewModel {
        ChatViewModel(aiService: ai, store: store, sessionType: sessionType)
    }
}

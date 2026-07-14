import SwiftUI
import AffirmAlarmCore

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    let store: StreakStore
    @State private var draft = ""
    @State private var lastSentText = ""

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.needsConsentDecision {
                    ConsentView { optedIn in viewModel.recordConsent(optedIn: optedIn) }
                } else if let generated = viewModel.generatedAffirmations {
                    AffirmationEditView(viewModel: AffirmationEditViewModel(store: store, initialTexts: generated))
                } else {
                    chatBody
                }
            }
            .task { await viewModel.start() }
        }
    }

    private var chatBody: some View {
        VStack {
            List(viewModel.messages) { message in
                Text(message.text)
                    .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
            }

            if case .error(let message) = viewModel.turnState {
                VStack {
                    Text(message).foregroundColor(.red)
                    Button("Retry") {
                        Task { await viewModel.send(lastSentText) }
                    }
                    .accessibilityIdentifier("chatRetryButton")
                    Button("Continue without AI") {
                        viewModel.continueWithoutAI()
                    }
                    .accessibilityIdentifier("chatFallbackButton")
                }
            }

            HStack {
                TextField("Message", text: $draft)
                    .accessibilityIdentifier("chatInputField")
                Button("Send") {
                    lastSentText = draft
                    let text = draft
                    draft = ""
                    Task { await viewModel.send(text) }
                }
                .accessibilityIdentifier("chatSendButton")
                .disabled(draft.isEmpty || viewModel.turnState == .sending)
            }
            .padding()

            if viewModel.canGenerate {
                Button("Generate my affirmations") {
                    Task { await viewModel.generateAffirmations() }
                }
                .accessibilityIdentifier("generateAffirmationsButton")
                .buttonStyle(.borderedProminent)
                .padding(.bottom)
            }
        }
        .navigationTitle("Chat")
    }
}

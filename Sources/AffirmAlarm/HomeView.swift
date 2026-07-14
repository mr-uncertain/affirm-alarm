import SwiftUI
import AffirmAlarmCore

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    @State private var chatDestination: HomeViewModel.ChatEntryDestination?
    @State private var showChat = false
    @State private var showManualEditDirectly = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Alarm") {
                    DatePicker(
                        "Time",
                        selection: Binding(
                            get: { viewModel.selectedTime.date ?? Date() },
                            set: { viewModel.selectedTime = Calendar.current.dateComponents([.hour, .minute], from: $0) }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .accessibilityIdentifier("alarmTimePicker")

                    if let scheduledTime = viewModel.scheduledTime {
                        Text("Alarm set for \(scheduledTime.hour ?? 0):\(String(format: "%02d", scheduledTime.minute ?? 0))")
                            .accessibilityIdentifier("scheduledTimeLabel")
                    } else {
                        Text("No alarm set")
                            .accessibilityIdentifier("noAlarmSetLabel")
                    }

                    if let error = viewModel.schedulingError {
                        Text(error).foregroundColor(.red)
                    }

                    Button("Save alarm") {
                        Task { await viewModel.saveAlarmTime() }
                    }
                    .accessibilityIdentifier("saveAlarmButton")
                }

                Section("Streak") {
                    Text("Day \(viewModel.streakDay)")
                        .accessibilityIdentifier("streakDayLabel")
                }

                Section {
                    NavigationLink("Edit affirmations") {
                        AffirmationEditView(viewModel: AffirmationEditViewModel(store: viewModel.store))
                    }
                    .accessibilityIdentifier("editAffirmationsLink")
                }

                Section {
                    Button("Chat with AI") {
                        Task {
                            switch await viewModel.resolveChatEntry() {
                            case .chat:
                                showChat = true
                            case .editAffirmationsDirectly:
                                showManualEditDirectly = true
                            }
                        }
                    }
                    .accessibilityIdentifier("chatWithAIButton")
                }
                .navigationDestination(isPresented: $showChat) {
                    ChatView(
                        viewModel: ChatViewModel(aiService: viewModel.aiService, store: viewModel.store, sessionType: .onboarding),
                        store: viewModel.store
                    )
                }
                .navigationDestination(isPresented: $showManualEditDirectly) {
                    AffirmationEditView(viewModel: AffirmationEditViewModel(store: viewModel.store))
                }
            }
            .navigationTitle("AffirmAlarm")
        }
    }
}

private extension DateComponents {
    var date: Date? {
        guard let hour, let minute else { return nil }
        return Calendar.current.date(from: DateComponents(hour: hour, minute: minute))
    }
}

import SwiftUI
import AffirmAlarmCore

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel

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

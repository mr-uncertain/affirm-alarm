import SwiftUI
import AffirmAlarmCore

struct InsightsView: View {
    @ObservedObject var viewModel: InsightsViewModel

    var body: some View {
        List(viewModel.events) { event in
            VStack(alignment: .leading, spacing: 4) {
                Text(event.date, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(event.sessionType == .onboarding ? "Onboarding" : "Check-in")
                    .font(.subheadline)
                ForEach(event.generatedTexts, id: \.self) { text in
                    Text(text)
                }
            }
        }
        .navigationTitle("Insights")
    }
}

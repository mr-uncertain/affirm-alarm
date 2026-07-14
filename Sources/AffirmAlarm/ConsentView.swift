import SwiftUI

struct ConsentView: View {
    let onDecision: (Bool) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Save our conversations?")
                .font(.title2)
                .bold()
            Text("This helps me remember what matters to you next time, and gives you a simple journal of your own reflections. Nothing leaves your device.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                Button("Yes, save my conversations") { onDecision(true) }
                    .accessibilityIdentifier("consentYesButton")
                    .buttonStyle(.borderedProminent)
                Button("No thanks, don't save") { onDecision(false) }
                    .accessibilityIdentifier("consentNoButton")
                    .buttonStyle(.bordered)
            }
        }
        .padding()
    }
}

import SwiftUI
import AffirmAlarmCore

struct AlarmRingView: View {
    @ObservedObject var viewModel: AlarmRingViewModel

    var body: some View {
        VStack(spacing: 32) {
            switch viewModel.state {
            case .completed:
                Text("Alarm dismissed")
                    .font(.title)
                    .accessibilityIdentifier("completedLabel")
            default:
                HStack(spacing: 24) {
                    Button("Snooze") { viewModel.tapSnooze() }
                        .accessibilityIdentifier("snoozeButton")

                    Circle()
                        .fill(isHolding ? Color.yellow : Color.gray)
                        .frame(width: 120, height: 120)
                        .overlay(Text("Hold & Speak").foregroundColor(.black))
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier("holdToSpeakButton")
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in viewModel.startHolding() }
                                .onEnded { _ in viewModel.releaseHold() }
                        )

                    Button("Close") { viewModel.tapClose() }
                        .disabled(!viewModel.canUseClose)
                        .accessibilityIdentifier("closeButton")
                }
            }
        }
        .padding()
        .onAppear { viewModel.beginRing() }
    }

    private var isHolding: Bool {
        if case .listening = viewModel.state { return true }
        return false
    }
}

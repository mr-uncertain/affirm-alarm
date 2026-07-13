import SwiftUI
import AffirmAlarmCore

struct RootView: View {
    @StateObject var rootViewModel: RootViewModel
    let alarmRingViewModel: AlarmRingViewModel

    var body: some View {
        Group {
            switch rootViewModel.route {
            case .home:
                Text("Home")
                    .accessibilityIdentifier("homePlaceholder")
            case .ringing:
                AlarmRingView(viewModel: alarmRingViewModel)
            }
        }
        .task { await rootViewModel.start() }
    }
}

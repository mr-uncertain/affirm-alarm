import SwiftUI
import AffirmAlarmCore

struct RootView: View {
    @StateObject var rootViewModel: RootViewModel
    let alarmRingViewModel: AlarmRingViewModel
    let homeViewModel: HomeViewModel

    var body: some View {
        Group {
            switch rootViewModel.route {
            case .home:
                HomeView(viewModel: homeViewModel)
            case .ringing:
                AlarmRingView(viewModel: alarmRingViewModel)
            }
        }
        .task { await rootViewModel.start() }
    }
}

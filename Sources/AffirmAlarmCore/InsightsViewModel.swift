import Foundation

@MainActor
public final class InsightsViewModel: ObservableObject {
    @Published public private(set) var events: [AffirmationGenerationEvent]

    public init(store: StreakStore) {
        self.events = store.loadGenerationEvents()
    }
}

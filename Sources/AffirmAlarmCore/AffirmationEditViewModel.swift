import Foundation

@MainActor
public final class AffirmationEditViewModel: ObservableObject {
    @Published public var affirmations: [Affirmation]
    @Published public private(set) var validationError: String?

    private let store: StreakStore

    public init(store: StreakStore, initialTexts: [String]? = nil) {
        self.store = store
        if let initialTexts {
            self.affirmations = initialTexts.map { Affirmation(text: $0, isUserAuthored: false) }
        } else {
            self.affirmations = store.loadAffirmations()
        }
    }

    public func addAffirmation() {
        affirmations.append(Affirmation(text: "", isUserAuthored: true))
    }

    public func removeAffirmation(at offsets: IndexSet) {
        affirmations.remove(atOffsets: offsets)
    }

    public func moveAffirmation(from source: IndexSet, to destination: Int) {
        affirmations.move(fromOffsets: source, toOffset: destination)
    }

    @discardableResult
    public func save() -> Bool {
        let nonEmpty = affirmations.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let requiredCount = IntensityEngine.level(forStreakDay: store.loadStreakState().streakDay).affirmationCount
        guard nonEmpty.count >= requiredCount else {
            validationError = "Add at least \(requiredCount) affirmation\(requiredCount == 1 ? "" : "s") for your current streak level."
            return false
        }
        validationError = nil
        store.save(nonEmpty)
        return true
    }
}

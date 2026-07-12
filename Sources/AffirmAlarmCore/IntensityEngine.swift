import Foundation

public enum IntensityEngine {
    public struct Level: Equatable {
        public let affirmationCount: Int
        public let repeatsPerAffirmation: Int

        public init(affirmationCount: Int, repeatsPerAffirmation: Int) {
            self.affirmationCount = affirmationCount
            self.repeatsPerAffirmation = repeatsPerAffirmation
        }
    }

    private static let firstWindowLength = 6
    private static let windowLength = 7

    public static func level(forStreakDay day: Int) -> Level {
        precondition(day >= 1, "streak day must be 1 or greater")

        if day <= firstWindowLength {
            return Level(affirmationCount: 1, repeatsPerAffirmation: 1)
        }

        let dayAfterFirstWindow = day - firstWindowLength - 1
        let windowIndex = dayAfterFirstWindow / windowLength
        let tier = (windowIndex + 1) / 2
        let repeats = windowIndex % 2 == 0 ? 2 : 1

        return Level(affirmationCount: 1 + tier, repeatsPerAffirmation: repeats)
    }
}

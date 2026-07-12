import XCTest
@testable import AffirmAlarmCore

final class IntensityEngineTests: XCTestCase {
    func test_day1_isOneAffirmationOnce() {
        XCTAssertEqual(
            IntensityEngine.level(forStreakDay: 1),
            .init(affirmationCount: 1, repeatsPerAffirmation: 1)
        )
    }

    func test_day6_isStillOneAffirmationOnce() {
        XCTAssertEqual(
            IntensityEngine.level(forStreakDay: 6),
            .init(affirmationCount: 1, repeatsPerAffirmation: 1)
        )
    }

    func test_day7_isOneAffirmationTwice() {
        XCTAssertEqual(
            IntensityEngine.level(forStreakDay: 7),
            .init(affirmationCount: 1, repeatsPerAffirmation: 2)
        )
    }

    func test_day13_isStillOneAffirmationTwice() {
        XCTAssertEqual(
            IntensityEngine.level(forStreakDay: 13),
            .init(affirmationCount: 1, repeatsPerAffirmation: 2)
        )
    }

    func test_day14_isTwoAffirmationsOnce() {
        XCTAssertEqual(
            IntensityEngine.level(forStreakDay: 14),
            .init(affirmationCount: 2, repeatsPerAffirmation: 1)
        )
    }

    func test_day20_isStillTwoAffirmationsOnce() {
        XCTAssertEqual(
            IntensityEngine.level(forStreakDay: 20),
            .init(affirmationCount: 2, repeatsPerAffirmation: 1)
        )
    }

    func test_day21_isTwoAffirmationsTwice() {
        XCTAssertEqual(
            IntensityEngine.level(forStreakDay: 21),
            .init(affirmationCount: 2, repeatsPerAffirmation: 2)
        )
    }

    func test_day28_continuesPatternToThreeAffirmationsOnce() {
        XCTAssertEqual(
            IntensityEngine.level(forStreakDay: 28),
            .init(affirmationCount: 3, repeatsPerAffirmation: 1)
        )
    }
}

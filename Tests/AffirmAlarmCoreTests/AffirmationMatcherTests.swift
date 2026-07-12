import XCTest
@testable import AffirmAlarmCore

final class AffirmationMatcherTests: XCTestCase {
    func test_matches_exactText() {
        XCTAssertTrue(AffirmationMatcher.matches(transcript: "I am capable", target: "I am capable"))
    }

    func test_matches_ignoringCaseAndPunctuation() {
        XCTAssertTrue(AffirmationMatcher.matches(transcript: "i am CAPABLE!", target: "I am capable."))
    }

    func test_matches_ignoringExtraWhitespace() {
        XCTAssertTrue(AffirmationMatcher.matches(transcript: "  I   am  capable ", target: "I am capable"))
    }

    func test_doesNotMatch_differentWords() {
        XCTAssertFalse(AffirmationMatcher.matches(transcript: "I am tired", target: "I am capable"))
    }

    func test_doesNotMatch_partialTranscript() {
        XCTAssertFalse(AffirmationMatcher.matches(transcript: "I am", target: "I am capable"))
    }
}

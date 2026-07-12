import XCTest

final class AlarmRingUITests: XCTestCase {
    func test_snoozeButton_isVisibleOnLaunch() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["snoozeButton"].waitForExistence(timeout: 5))
    }

    func test_closeButton_isVisibleOnLaunch() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["closeButton"].waitForExistence(timeout: 5))
    }

    func test_holdToSpeakButton_isVisibleOnLaunch() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.otherElements["holdToSpeakButton"].waitForExistence(timeout: 5))
    }
}

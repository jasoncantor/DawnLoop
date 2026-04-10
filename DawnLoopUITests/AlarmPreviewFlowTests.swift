import XCTest

/// UI smoke tests for list actions and repair status.
@MainActor
final class AlarmPreviewFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func configuredApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-onboarding", "--reset-home-selection", "--reset-alarms", "--seed-test-home"]
        app.launch()

        if app.buttons["Get Started"].waitForExistence(timeout: 5) {
            app.buttons["Get Started"].tap()
        }
        if app.buttons["Continue"].waitForExistence(timeout: 2) {
            app.buttons["Continue"].tap()
        }
        if app.buttons["Connect to Home"].waitForExistence(timeout: 2) {
            app.buttons["Connect to Home"].tap()
        }
        app.buttons.containing(.staticText, identifier: "Test Home").firstMatch.tap()
        app.buttons.containing(.staticText, identifier: "Living Room Light").firstMatch.tap()
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["No Alarms Yet"].waitForExistence(timeout: 10))
        app.buttons["Create Your First Alarm"].tap()
        let nameField = app.textFields["Alarm Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Sunrise Test")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Sunrise Test"].waitForExistence(timeout: 5))
        return app
    }

    func testToggleEnabledFromAlarmList() throws {
        let app = configuredApp()
        let disableButton = app.buttons["Disable alarm"].firstMatch
        XCTAssertTrue(disableButton.waitForExistence(timeout: 5))
        disableButton.tap()
        XCTAssertTrue(app.buttons["Enable alarm"].waitForExistence(timeout: 5))
    }

    func testDeleteAlarmFromAlarmList() throws {
        let app = configuredApp()
        let alarmLabel = app.staticTexts["Sunrise Test"]
        XCTAssertTrue(alarmLabel.waitForExistence(timeout: 5))
        alarmLabel.swipeLeft()
        app.buttons["Delete"].tap()
        app.alerts.buttons["Delete"].tap()
        XCTAssertFalse(alarmLabel.waitForExistence(timeout: 2))
    }

    func testRepairNeededIndicatorVisibleForSeededAlarm() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--seed-repair-needed-alarm"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Repair Test Alarm"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Needs Repair"].exists)
    }
}

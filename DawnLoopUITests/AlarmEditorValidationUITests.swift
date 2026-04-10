import XCTest

/// UI Tests for Alarm Editor validation
/// Exercises the committed alarm list/editor flow with seeded Home data.
@MainActor
final class AlarmEditorValidationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchConfiguredApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-onboarding", "--reset-home-selection", "--reset-alarms", "--seed-test-home"]
        app.launch()
        completeOnboardingAndHomeSetup(app)
        return app
    }

    private func completeOnboardingAndHomeSetup(_ app: XCUIApplication) {
        if app.buttons["Get Started"].waitForExistence(timeout: 5) {
            app.buttons["Get Started"].tap()
        }
        if app.buttons["Continue"].waitForExistence(timeout: 2) {
            app.buttons["Continue"].tap()
        }
        if app.buttons["Connect to Home"].waitForExistence(timeout: 2) {
            app.buttons["Connect to Home"].tap()
        }
        XCTAssertTrue(app.staticTexts["Choose Your Home"].waitForExistence(timeout: 10))

        let homeButton = app.buttons.containing(.staticText, identifier: "Test Home").firstMatch
        XCTAssertTrue(homeButton.waitForExistence(timeout: 5))
        homeButton.tap()

        XCTAssertTrue(app.staticTexts["Select Your Lights"].waitForExistence(timeout: 10))
        let lightButton = app.buttons.containing(.staticText, identifier: "Living Room Light").firstMatch
        XCTAssertTrue(lightButton.waitForExistence(timeout: 5))
        lightButton.tap()

        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        continueButton.tap()

        XCTAssertTrue(app.staticTexts["No Alarms Yet"].waitForExistence(timeout: 10))
    }

    private func createAlarm(named name: String, in app: XCUIApplication) {
        let createButton = app.buttons["Create Your First Alarm"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        createButton.tap()

        let nameField = app.textFields["Alarm Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)

        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
    }

    private func clearText(in element: XCUIElement) {
        guard let existing = element.value as? String else {
            return
        }
        element.tap()
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count)
        element.typeText(deleteString)
    }

    func testAlarmListEmptyStateAfterOnboarding() throws {
        let app = launchConfiguredApp()
        XCTAssertTrue(app.staticTexts["No Alarms Yet"].exists)
        XCTAssertTrue(app.buttons["Create Your First Alarm"].exists)
    }

    func testCreateAlarmFlow() throws {
        let app = launchConfiguredApp()
        createAlarm(named: "Morning Glow", in: app)
        XCTAssertTrue(app.staticTexts["Morning Glow"].exists)
    }

    func testEditAlarmFlow() throws {
        let app = launchConfiguredApp()
        createAlarm(named: "Morning Glow", in: app)

        app.staticTexts["Morning Glow"].tap()
        let nameField = app.textFields["Alarm Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        clearText(in: nameField)
        nameField.typeText("Early Rise")
        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["Early Rise"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Morning Glow"].exists)
    }
}

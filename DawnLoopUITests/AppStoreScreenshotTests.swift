import XCTest

final class AppStoreScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCapture01Welcome() throws {
        let app = launchApp(arguments: ["--reset-onboarding", "--reset-home-selection", "--reset-alarms", "--seed-test-home"])
        XCTAssertTrue(app.staticTexts["Welcome to DawnLoop"].waitForExistence(timeout: 5))
        capture("01-welcome")
    }

    func testCapture02HomeSelection() throws {
        let app = launchApp(arguments: ["--reset-onboarding", "--reset-home-selection", "--reset-alarms", "--seed-test-home"])
        advanceToHomeSelection(in: app)
        XCTAssertTrue(app.staticTexts["Choose Your Home"].waitForExistence(timeout: 10))
        capture("02-home-selection")
    }

    func testCapture03LightSelection() throws {
        let app = launchApp(arguments: ["--reset-onboarding", "--reset-home-selection", "--reset-alarms", "--seed-test-home"])
        advanceToHomeSelection(in: app)
        app.buttons.containing(.staticText, identifier: "Test Home").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Select Your Lights"].waitForExistence(timeout: 10))
        capture("03-light-selection")
    }

    func testCapture04EmptyAlarmList() throws {
        let app = launchApp(arguments: ["--reset-onboarding", "--reset-home-selection", "--reset-alarms", "--seed-test-home"])
        finishOnboardingIntoAlarmList(in: app)
        XCTAssertTrue(app.staticTexts["No Alarms Yet"].waitForExistence(timeout: 10))
        capture("04-empty-alarm-list")
    }

    func testCapture05AlarmEditor() throws {
        let app = launchApp(arguments: ["--reset-onboarding", "--reset-home-selection", "--reset-alarms", "--seed-test-home"])
        finishOnboardingIntoAlarmList(in: app)

        app.buttons["Create Your First Alarm"].tap()
        XCTAssertTrue(app.navigationBars["New Alarm"].waitForExistence(timeout: 5))

        let nameField = app.textFields["Alarm Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Bedroom Wake")

        if app.keyboards.count > 0 {
            app.navigationBars["New Alarm"].firstMatch.tap()
        }

        capture("05-alarm-editor")
    }

    func testCapture06AlarmListPopulated() throws {
        let app = launchApp(arguments: ["--reset-onboarding", "--reset-home-selection", "--reset-alarms", "--seed-test-home"])
        finishOnboardingIntoAlarmList(in: app)
        createAlarm(named: "Bedroom Wake", in: app)
        XCTAssertTrue(app.staticTexts["Bedroom Wake"].waitForExistence(timeout: 10))
        capture("06-alarm-list-populated")
    }

    func testCapture07RepairNeeded() throws {
        let app = launchApp(arguments: ["--reset-alarms", "--seed-repair-needed-alarm"])
        XCTAssertTrue(app.staticTexts["Repair Test Alarm"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Needs Repair"].exists)
        capture("07-repair-needed")
    }

    private func launchApp(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func advanceToHomeSelection(in app: XCUIApplication) {
        if app.buttons["Get Started"].waitForExistence(timeout: 5) {
            app.buttons["Get Started"].tap()
        }
        if app.buttons["Continue"].waitForExistence(timeout: 5) {
            app.buttons["Continue"].tap()
        }
        if app.buttons["Connect to Home"].waitForExistence(timeout: 5) {
            app.buttons["Connect to Home"].tap()
        }
    }

    private func finishOnboardingIntoAlarmList(in app: XCUIApplication) {
        advanceToHomeSelection(in: app)
        app.buttons.containing(.staticText, identifier: "Test Home").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Select Your Lights"].waitForExistence(timeout: 10))

        let lightButton = app.buttons.containing(.staticText, identifier: "Living Room Light").firstMatch
        XCTAssertTrue(lightButton.waitForExistence(timeout: 5))
        lightButton.tap()

        let continueButton = app.buttons["Continue"].firstMatch
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        continueButton.tap()
    }

    private func createAlarm(named name: String, in app: XCUIApplication) {
        let createButton = app.buttons["Create Your First Alarm"].firstMatch
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        createButton.tap()

        let nameField = app.textFields["Alarm Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)

        app.buttons["Save"].tap()
    }

    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

import XCTest

/// UI Tests for Alarm Preview and Gradient UI
/// Validates VAL-ALARM-003 and VAL-ALARM-004 with visible UI proof
final class AlarmPreviewFlowTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--reset-onboarding"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func completeOnboarding() {
        let getStartedButton = app.buttons["Get Started"]
        if getStartedButton.waitForExistence(timeout: 3) {
            getStartedButton.tap()
            sleep(1)
            app.swipeLeft()
            sleep(1)
            app.swipeLeft()
            sleep(1)
            app.buttons["Continue"].firstMatch.tap()
        }
    }

    func testPreviewSection_ExistsInEditor() throws {
        completeOnboarding()

        // Navigate to create alarm
        let addButton = app.buttons["Create Alarm"]
        if addButton.waitForExistence(timeout: 3) {
            addButton.tap()
        }

        // Check Preview section exists
        let previewHeader = app.staticTexts["Preview"]
        XCTAssertTrue(previewHeader.waitForExistence(timeout: 3),
                     "Preview section header should exist in alarm editor")
    }

    func testPreview_UnavailableState_ShowsMessage() throws {
        completeOnboarding()

        // Navigate to create alarm
        let addButton = app.buttons["Create Alarm"]
        if addButton.waitForExistence(timeout: 3) {
            addButton.tap()
        }

        // Check unavailable message appears before entering data
        let unavailableText = app.staticTexts["Preview unavailable"]
        XCTAssertTrue(unavailableText.waitForExistence(timeout: 3),
                     "Should show 'Preview unavailable' when no data entered")
    }
}

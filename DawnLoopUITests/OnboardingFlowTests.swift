import XCTest

final class OnboardingFlowTests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        
        // Reset onboarding state before each test
        app.launchArguments.append("--reset-onboarding")
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    func testOnboardingShowsThreeScreensInOrder() throws {
        app.launch()
        
        // Verify first screen is shown
        XCTAssertTrue(app.staticTexts["Welcome to DawnLoop"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Gentle sunrise alarms that transform your mornings using the lights you already have."].exists)
        
        // Advance to second screen
        app.buttons["Get Started"].tap()
        
        // Verify second screen
        XCTAssertTrue(app.staticTexts["How It Works"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["DawnLoop creates smart automations in Apple Home that gradually brighten your lights before your alarm time."].exists)
        
        // Advance to third screen
        app.buttons["Continue"].tap()
        
        // Verify third screen
        XCTAssertTrue(app.staticTexts["Ready to Wake"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Connect to Apple Home and set up your first wake-light alarm in under a minute."].exists)
    }
    
    func testCompletedOnboardingDoesNotReappearOnRelaunch() throws {
        // First launch - complete onboarding
        app.launch()
        
        // Verify onboarding is shown
        XCTAssertTrue(app.staticTexts["Welcome to DawnLoop"].waitForExistence(timeout: 5))
        
        // Complete all three screens
        app.buttons["Get Started"].tap()
        XCTAssertTrue(app.staticTexts["How It Works"].waitForExistence(timeout: 2))
        
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Ready to Wake"].waitForExistence(timeout: 2))
        
        // Complete onboarding
        app.buttons["Connect to Home"].tap()
        
        // Wait for main flow to appear
        XCTAssertTrue(app.staticTexts["Good Morning"].waitForExistence(timeout: 2))
        
        // Terminate and relaunch without reset argument
        app.terminate()
        
        let newApp = XCUIApplication()
        newApp.launch()
        
        // Verify main flow appears, not onboarding
        XCTAssertTrue(newApp.staticTexts["Good Morning"].waitForExistence(timeout: 5))
        XCTAssertFalse(newApp.staticTexts["Welcome to DawnLoop"].exists)
    }
    
    func testOnboardingProgressIndicator() throws {
        app.launch()
        
        // First screen - should show progress for step 1
        XCTAssertTrue(app.staticTexts["Welcome to DawnLoop"].waitForExistence(timeout: 5))
        
        // Advance to second screen
        app.buttons["Get Started"].tap()
        XCTAssertTrue(app.staticTexts["How It Works"].waitForExistence(timeout: 2))
        
        // Advance to third screen
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Ready to Wake"].waitForExistence(timeout: 2))
    }
    
    func testOnboardingBackNavigation() throws {
        app.launch()
        
        // Go to second screen
        XCTAssertTrue(app.staticTexts["Welcome to DawnLoop"].waitForExistence(timeout: 5))
        app.buttons["Get Started"].tap()
        
        XCTAssertTrue(app.staticTexts["How It Works"].waitForExistence(timeout: 2))
        
        // Go back
        app.buttons["Back"].tap()
        
        // Verify back on first screen
        XCTAssertTrue(app.staticTexts["Welcome to DawnLoop"].waitForExistence(timeout: 2))
    }
}

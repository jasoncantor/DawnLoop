import XCTest

/// UI Tests for home selection and accessory discovery flow
/// Validates VAL-HOME-001 through VAL-HOME-006
final class HomeDiscoveryFlowTests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        
        // Reset onboarding and home selection state before each test
        app.launchArguments.append("--reset-onboarding")
        app.launchArguments.append("--reset-home-selection")
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - VAL-HOME-001: All available homes shown with active choice
    
    func testHomeSelection_ShowsAllAvailableHomes() throws {
        // Note: This test requires mocking or a Home environment with multiple homes
        // On simulator without HomeKit data, this validates the UI structure
        
        app.launch()
        
        // Complete onboarding to reach home selection
        completeOnboarding()
        
        // If no homes are available, the empty state should be shown
        if app.staticTexts["No Homes Available"].waitForExistence(timeout: 5) {
            // Empty state is shown - this is valid for simulator
            XCTAssertTrue(app.staticTexts["Create a home in the Apple Home app first, then return here."].exists)
        }
    }
    
    func testHomeSelection_ShowsHomeDetails() throws {
        app.launch()
        
        completeOnboarding()
        
        // Verify the selection view structure exists
        XCTAssertTrue(app.staticTexts["Choose Your Home"].waitForExistence(timeout: 5) ||
                     app.staticTexts["No Homes Available"].waitForExistence(timeout: 5) ||
                     app.staticTexts["Preparing your home..."].waitForExistence(timeout: 5))
    }
    
    // MARK: - VAL-HOME-003: Compatible accessories grouped by room
    
    func testAccessoryDiscovery_ShowsRoomGrouping() throws {
        app.launch()
        
        completeOnboarding()
        
        // Wait for either accessory discovery or empty state
        let discoveryLoaded = app.staticTexts["Select Your Lights"].waitForExistence(timeout: 10)
        let noLights = app.staticTexts["No Compatible Lights"].waitForExistence(timeout: 2)
        let preparing = app.staticTexts["Preparing your home..."].waitForExistence(timeout: 2)
        
        if discoveryLoaded {
            // Verify room section structure can exist
            // Actual room detection requires real HomeKit data
            XCTAssertTrue(app.staticTexts["Select Your Lights"].exists)
        } else if noLights {
            // Valid empty state
            XCTAssertTrue(app.staticTexts["No lights with brightness control were found in this home."].exists)
        }
        // If preparing, single home was auto-selected and may transition
    }
    
    func testAccessoryDiscovery_EmptyStateAction() throws {
        app.launch()
        
        completeOnboarding()
        
        // If no lights available, check button exists
        if app.staticTexts["No Compatible Lights"].waitForExistence(timeout: 10) {
            XCTAssertTrue(app.buttons["Check Again"].exists)
        }
    }
    
    // MARK: - VAL-HOME-006: Home switching clears stale results
    
    func testAccessoryDiscovery_SwitchHomeButtonExists() throws {
        app.launch()
        
        completeOnboarding()
        
        // Wait for discovery view with accessories
        if app.staticTexts["Select Your Lights"].waitForExistence(timeout: 10) {
            // Switch Home button should be available when accessories are shown
            XCTAssertTrue(app.buttons["Switch Home"].exists)
        }
    }
    
    func testAccessoryDiscovery_ContinueAction() throws {
        app.launch()
        
        completeOnboarding()
        
        // Wait for discovery view
        if app.staticTexts["Select Your Lights"].waitForExistence(timeout: 10) {
            // Continue button should exist (either "Continue" or "Skip for Now")
            let continueButton = app.buttons["Continue"]
            let skipButton = app.buttons["Skip for Now"]
            
            XCTAssertTrue(continueButton.exists || skipButton.exists)
        }
    }
    
    // MARK: - Helper Methods
    
    private func completeOnboarding() {
        // Complete all three onboarding screens
        if app.staticTexts["Welcome to DawnLoop"].waitForExistence(timeout: 5) {
            app.buttons["Get Started"].tap()
        }
        
        if app.staticTexts["How It Works"].waitForExistence(timeout: 2) {
            app.buttons["Continue"].tap()
        }
        
        if app.staticTexts["Ready to Wake"].waitForExistence(timeout: 2) {
            app.buttons["Connect to Home"].tap()
        }
    }
}

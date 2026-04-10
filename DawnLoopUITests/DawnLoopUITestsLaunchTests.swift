import XCTest

@MainActor
final class DawnLoopUITestsLaunchTests: XCTestCase {
    
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--reset-onboarding")
        app.launch()
        
        // Verify app launches successfully
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        
        // Take screenshot for verification
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

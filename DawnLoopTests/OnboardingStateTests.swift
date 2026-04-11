import XCTest
@testable import DawnLoop

@MainActor
final class OnboardingStateTests: XCTestCase {
    
    override func setUp() async throws {
        try await super.setUp()
        // Reset UserDefaults before each test
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
    }
    
    override func tearDown() async throws {
        // Clean up after each test
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        try await super.tearDown()
    }
    
    func testInitialState_IsNotCompleted() {
        let state = OnboardingState()
        
        XCTAssertFalse(state.hasCompletedOnboarding)
        XCTAssertEqual(state.currentScreen, .welcome)
    }
    
    func testCompleteOnboarding_SetsCompletedTrue() {
        let state = OnboardingState()
        
        state.completeOnboarding()
        
        XCTAssertTrue(state.hasCompletedOnboarding)
    }
    
    func testCompleteOnboarding_PersistsToUserDefaults() {
        let state = OnboardingState()
        
        state.completeOnboarding()
        
        // Create a new state instance to verify persistence
        let newState = OnboardingState()
        XCTAssertTrue(newState.hasCompletedOnboarding)
    }
    
    func testResetOnboarding_ClearsCompletion() {
        let state = OnboardingState()
        
        state.completeOnboarding()
        XCTAssertTrue(state.hasCompletedOnboarding)
        
        state.resetOnboarding()
        
        XCTAssertFalse(state.hasCompletedOnboarding)
        XCTAssertEqual(state.currentScreen, .welcome)
    }
    
    func testOnboardingScreenProperties() {
        // Verify all screens have required properties
        for screen in OnboardingScreen.allCases {
            XCTAssertFalse(screen.title.isEmpty, "Screen \(screen) should have a title")
            XCTAssertFalse(screen.description.isEmpty, "Screen \(screen) should have a description")
            XCTAssertFalse(screen.iconName.isEmpty, "Screen \(screen) should have an icon")
            XCTAssertFalse(screen.primaryAction.isEmpty, "Screen \(screen) should have a primary action")
        }
    }
    
    func testOnboardingScreenCount() {
        XCTAssertEqual(OnboardingScreen.allCases.count, 3, "Should have exactly 3 onboarding screens")
    }
    
    func testOnboardingScreenOrder() {
        let screens = OnboardingScreen.allCases
        
        XCTAssertEqual(screens[0], .welcome)
        XCTAssertEqual(screens[1], .howItWorks)
        XCTAssertEqual(screens[2], .ready)
    }
}

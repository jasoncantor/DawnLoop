import SwiftUI
import SwiftData

@main
struct DawnLoopApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    let container: AppEnvironment
    
    init() {
        // Check for test launch arguments before initializing environment
        LaunchArgumentHandler.handleTestArguments()
        self.container = AppEnvironment()
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        return true
    }
}

/// Global flag set by launch arguments for test environment detection
/// nonisolated(unsafe) because this is set once at app startup and never modified after
enum TestEnvironment {
    /// Deprecated: This flag auto-completes onboarding which violates the requirement
    /// that tests must prove legitimate visible flow outcomes. Use --seed-test-home instead.
    nonisolated(unsafe) static var isSimulatingHomeReady: Bool = false
    
    /// When true, seeds deterministic test homes and accessories for UI testing.
    /// This allows tests to experience the full visible flow with realistic data
    /// without requiring real HomeKit infrastructure.
    nonisolated(unsafe) static var isSeedingTestHome: Bool = false
}

/// Handles launch arguments for testing and debugging
enum LaunchArgumentHandler {
    static func handleTestArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        
        // Reset onboarding state for UI tests
        if arguments.contains("--reset-onboarding") {
            resetOnboardingState()
        }
        
        // Reset home selection for UI tests
        if arguments.contains("--reset-home-selection") {
            resetHomeSelection()
        }
        
        // Simulate Home ready state for UI tests
        // DEPRECATED: This flag auto-completes onboarding which violates test requirements.
        // Use --seed-test-home instead for legitimate visible flow testing.
        if arguments.contains("--simulate-home-ready") {
            TestEnvironment.isSimulatingHomeReady = true
        }
        
        // Seed deterministic test homes and accessories for UI testing.
        // This allows tests to experience the full visible flow with realistic data
        // without requiring real HomeKit infrastructure, while still proving the
        // legitimate completion path through actual UI interaction.
        if arguments.contains("--seed-test-home") {
            TestEnvironment.isSeedingTestHome = true
        }
    }
    
    private static func resetOnboardingState() {
        // Clear UserDefaults
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        UserDefaults.standard.removeObject(forKey: "hasStartedHomeAccessFlow")
        
        // Clear SwiftData onboarding records
        do {
            let schema = Schema([OnboardingCompletion.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)
            
            let descriptor = FetchDescriptor<OnboardingCompletion>()
            let completions = try context.fetch(descriptor)
            for completion in completions {
                context.delete(completion)
            }
            try context.save()
        } catch {
            print("Failed to reset onboarding state: \(error)")
        }
    }
    
    private static func resetHomeSelection() {
        UserDefaults.standard.removeObject(forKey: "activeHomeIdentifier")
        UserDefaults.standard.removeObject(forKey: "activeHomeName")
    }
}

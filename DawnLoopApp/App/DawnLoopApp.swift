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
        
        // Seed deterministic test homes and accessories for UI testing.
        // This allows tests to experience the full visible flow with realistic data
        // without requiring real HomeKit infrastructure, while still proving the
        // legitimate completion path through actual UI interaction.
        if arguments.contains("--seed-test-home") {
            TestEnvironment.isSeedingTestHome = true
            seedTestHomes()
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
    
    /// Seeds deterministic test homes into SwiftData for UI testing.
    /// This provides realistic home data so tests can verify the full visible
    /// home selection flow without requiring real HomeKit infrastructure.
    private static func seedTestHomes() {
        let schema = Schema([HomeReference.self, AccessoryReference.self, OnboardingCompletion.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)
            
            // Check if test homes already exist
            let descriptor = FetchDescriptor<HomeReference>()
            let existingHomes = try context.fetch(descriptor)
            
            // Only seed if no homes exist yet
            guard existingHomes.isEmpty else {
                return
            }
            
            // Create a primary test home with rooms and accessories
            let testHome = HomeReference(
                homeKitIdentifier: "test-home-uuid-001",
                name: "Test Home",
                isActive: true,
                roomCount: 4,
                accessoryCount: 8
            )
            context.insert(testHome)
            
            // Create some accessories in the test home
            let livingRoomLight = AccessoryReference(
                homeKitIdentifier: "test-accessory-living-room-001",
                name: "Living Room Light",
                roomName: "Living Room",
                homeIdentifier: testHome.homeKitIdentifier,
                isCompatible: true
            )
            context.insert(livingRoomLight)
            
            let bedroomLight = AccessoryReference(
                homeKitIdentifier: "test-accessory-bedroom-001",
                name: "Bedroom Light",
                roomName: "Bedroom",
                homeIdentifier: testHome.homeKitIdentifier,
                isCompatible: true
            )
            context.insert(bedroomLight)
            
            let kitchenLight = AccessoryReference(
                homeKitIdentifier: "test-accessory-kitchen-001",
                name: "Kitchen Light",
                roomName: "Kitchen",
                homeIdentifier: testHome.homeKitIdentifier,
                isCompatible: true
            )
            context.insert(kitchenLight)
            
            try context.save()
        } catch {
            print("Failed to seed test homes: \(error)")
        }
    }
}

import SwiftUI
import SwiftData

@main
struct DawnLoopApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    let container: AppEnvironment
    
    init() {
        // Check for test launch arguments and set flags before initializing environment
        LaunchArgumentHandler.handleTestArguments()
        
        // Execute UserDefaults resets BEFORE creating environment
        // This ensures OnboardingState reads fresh values on initialization
        LaunchArgumentHandler.executeUserDefaultsResets()
        
        // Initialize environment (this uses TestEnvironment flags)
        // OnboardingState will now read fresh UserDefaults values
        self.container = AppEnvironment()
        
        // Execute remaining pending test actions using the initialized AppEnvironment
        // This ensures all SwiftData operations use the same ModelContainer
        LaunchArgumentHandler.executePendingActions(using: self.container)
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

/// Pending test actions to be executed after AppEnvironment initialization
/// This ensures all SwiftData operations use the same ModelContainer
/// nonisolated(unsafe) because these are set once at app startup and never modified after
enum PendingTestActions {
    nonisolated(unsafe) static var shouldResetOnboarding: Bool = false
    nonisolated(unsafe) static var shouldResetHomeSelection: Bool = false
    nonisolated(unsafe) static var shouldSeedTestHome: Bool = false
}

/// Handles launch arguments for testing and debugging
enum LaunchArgumentHandler {
    static func handleTestArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        
        // Set test environment flags BEFORE environment initialization
        if arguments.contains("--seed-test-home") {
            TestEnvironment.isSeedingTestHome = true
            PendingTestActions.shouldSeedTestHome = true
        }
        
        // Queue reset actions to be executed after environment initialization
        if arguments.contains("--reset-onboarding") {
            PendingTestActions.shouldResetOnboarding = true
        }
        
        if arguments.contains("--reset-home-selection") {
            PendingTestActions.shouldResetHomeSelection = true
        }
    }
    
    /// Execute UserDefaults resets BEFORE environment initialization
    /// This ensures OnboardingState reads fresh values when it's created
    static func executeUserDefaultsResets() {
        let arguments = ProcessInfo.processInfo.arguments
        
        if arguments.contains("--reset-onboarding") {
            // Clear UserDefaults BEFORE AppEnvironment is created
            // so OnboardingState reads fresh values
            UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
            UserDefaults.standard.removeObject(forKey: "hasStartedHomeAccessFlow")
            // Also reset discovery step to ensure fresh flow
            UserDefaults.standard.removeObject(forKey: "discoveryStep")
        }
        
        if arguments.contains("--reset-home-selection") {
            UserDefaults.standard.removeObject(forKey: "activeHomeIdentifier")
            UserDefaults.standard.removeObject(forKey: "activeHomeName")
        }
    }
    
    /// Execute pending test actions using the initialized AppEnvironment
    /// This ensures all SwiftData operations use the same ModelContainer
    static func executePendingActions(using environment: AppEnvironment) {
        // Note: UserDefaults were already reset in executeUserDefaultsResets()
        // This method handles SwiftData operations that need the environment
        
        if PendingTestActions.shouldResetOnboarding {
            resetOnboardingSwiftData(using: environment)
        }
        
        if PendingTestActions.shouldResetHomeSelection {
            resetHomeSelectionSwiftData(using: environment)
        }
        
        if PendingTestActions.shouldSeedTestHome {
            seedTestHomes(using: environment)
        }
    }
    
    /// Clears SwiftData onboarding records (UserDefaults already cleared in executeUserDefaultsResets)
    private static func resetOnboardingSwiftData(using environment: AppEnvironment) {
        let context = ModelContext(environment.modelContainer)
        
        do {
            let descriptor = FetchDescriptor<OnboardingCompletion>()
            let completions = try context.fetch(descriptor)
            for completion in completions {
                context.delete(completion)
            }
            try context.save()
        } catch {
            print("Failed to reset onboarding SwiftData: \(error)")
        }
    }
    
    /// Clears SwiftData home selection records (UserDefaults already cleared in executeUserDefaultsResets)
    private static func resetHomeSelectionSwiftData(using environment: AppEnvironment) {
        let context = ModelContext(environment.modelContainer)
        
        do {
            var descriptor = FetchDescriptor<HomeReference>()
            descriptor.predicate = #Predicate { $0.isActive }
            
            if let active = try context.fetch(descriptor).first {
                active.isActive = false
                active.updatedAt = Date()
                try context.save()
            }
        } catch {
            print("Failed to reset home selection SwiftData: \(error)")
        }
    }
    
    /// Seeds deterministic test homes into SwiftData for UI testing.
    /// This provides realistic home data so tests can verify the full visible
    /// home selection flow without requiring real HomeKit infrastructure.
    private static func seedTestHomes(using environment: AppEnvironment) {
        let context = ModelContext(environment.modelContainer)
        
        do {
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

import SwiftUI
import SwiftData

@Observable
@MainActor
final class AppEnvironment {
    let onboardingState: OnboardingState
    let homeAccessState: HomeAccessState
    let homeSelectionService: HomeSelectionService
    let accessoryDiscoveryService: AccessoryDiscoveryService
    let modelContainer: ModelContainer
    
    init() {
        self.onboardingState = OnboardingState()
        
        let schema = Schema([
            OnboardingCompletion.self,
            HomeReference.self,
            AccessoryReference.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        
        do {
            self.modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
        
        // Use mock adapter for testing when --seed-test-home is set
        // This allows the seeded test homes to be returned via the adapter
        let homeKitAdapter: (any HomeKitAdapterProtocol)? = TestEnvironment.isSeedingTestHome
            ? MockHomeKitAdapter()
            : nil
        
        self.homeAccessState = HomeAccessState(adapter: homeKitAdapter, modelContainer: modelContainer)
        self.homeSelectionService = HomeSelectionService(modelContainer: modelContainer)
        self.accessoryDiscoveryService = AccessoryDiscoveryService(modelContainer: modelContainer)
    }
}

import SwiftUI
import SwiftData

@Observable
@MainActor
final class AppEnvironment {
    let onboardingState: OnboardingState
    let homeAccessState: HomeAccessState
    let modelContainer: ModelContainer
    
    init() {
        self.onboardingState = OnboardingState()
        self.homeAccessState = HomeAccessState()
        
        let schema = Schema([
            OnboardingCompletion.self,
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
    }
}

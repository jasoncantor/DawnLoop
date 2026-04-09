import SwiftUI
import SwiftData

@Observable
final class AppEnvironment {
    let onboardingState: OnboardingState
    let modelContainer: ModelContainer
    
    init() {
        self.onboardingState = OnboardingState()
        
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

import SwiftUI

/// Root view that handles onboarding vs. main app flow routing
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    
    var body: some View {
        Group {
            // Show main flow only if onboarding is complete AND we're not in the middle of home access flow.
            // This allows the home access flow (home selection, accessory discovery) to complete
            // even after onboarding is marked complete.
            if environment.onboardingState.hasCompletedOnboarding && !environment.onboardingState.showingHomeAccessFlow {
                MainFlowView()
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: environment.onboardingState.hasCompletedOnboarding)
    }
}

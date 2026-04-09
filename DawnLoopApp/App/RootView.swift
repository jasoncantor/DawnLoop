import SwiftUI

/// Root view that handles onboarding vs. main app flow routing
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    
    var body: some View {
        Group {
            if environment.onboardingState.hasCompletedOnboarding {
                MainFlowView()
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: environment.onboardingState.hasCompletedOnboarding)
    }
}

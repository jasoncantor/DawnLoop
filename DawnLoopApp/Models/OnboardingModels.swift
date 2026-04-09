import SwiftData
import Foundation

/// Persistent record of onboarding completion status
@Model
final class OnboardingCompletion {
    var hasCompletedOnboarding: Bool
    var completedAt: Date?
    
    init(hasCompletedOnboarding: Bool = false, completedAt: Date? = nil) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.completedAt = completedAt
    }
}

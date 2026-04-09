import SwiftUI
import SwiftData

/// Observable state for onboarding flow and persistence
@Observable
final class OnboardingState {
    private let onboardingKey = "hasCompletedOnboarding"
    
    var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: onboardingKey)
        }
    }
    
    var currentScreen: OnboardingScreen = .welcome
    
    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
    }
    
    func completeOnboarding() {
        hasCompletedOnboarding = true
        currentScreen = .welcome
    }
    
    func resetOnboarding() {
        hasCompletedOnboarding = false
        currentScreen = .welcome
    }
}

enum OnboardingScreen: Int, CaseIterable {
    case welcome = 0
    case howItWorks = 1
    case ready = 2
    
    var title: String {
        switch self {
        case .welcome:
            return "Welcome to DawnLoop"
        case .howItWorks:
            return "How It Works"
        case .ready:
            return "Ready to Wake"
        }
    }
    
    var description: String {
        switch self {
        case .welcome:
            return "Gentle sunrise alarms that transform your mornings using the lights you already have."
        case .howItWorks:
            return "DawnLoop creates smart automations in Apple Home that gradually brighten your lights before your alarm time."
        case .ready:
            return "Connect to Apple Home and set up your first wake-light alarm in under a minute."
        }
    }
    
    var iconName: String {
        switch self {
        case .welcome:
            return "sunrise.fill"
        case .howItWorks:
            return "house.fill"
        case .ready:
            return "alarm.fill"
        }
    }
    
    var primaryAction: String {
        switch self {
        case .welcome:
            return "Get Started"
        case .howItWorks:
            return "Continue"
        case .ready:
            return "Connect to Home"
        }
    }
}

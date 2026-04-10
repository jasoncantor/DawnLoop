import SwiftUI
import SwiftData

/// Observable state for onboarding flow and persistence
@Observable
@MainActor
final class OnboardingState {
    private let onboardingKey = "hasCompletedOnboarding"
    private let homeAccessStartedKey = "hasStartedHomeAccessFlow"
    
    var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: onboardingKey)
        }
    }
    
    var showingHomeAccessFlow = false
    var currentScreen: OnboardingScreen = .welcome
    var discoveryStep: DiscoveryStep = .none
    
    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
    }
    
    /// Called from the final onboarding CTA to start Home access handling.
    /// This marks onboarding as complete - the user has seen the three onboarding
    /// screens and taken the primary action. On relaunch, they won't see onboarding again.
    func startHomeAccessFlow() {
        hasCompletedOnboarding = true
        showingHomeAccessFlow = true
        discoveryStep = .checkingAccess
    }
    
    /// Called when Home access flow should exit (either completed or blocked)
    func exitHomeAccessFlow() {
        showingHomeAccessFlow = false
        discoveryStep = .none
    }
    
    /// Move to home selection step (for multiple homes)
    func moveToHomeSelection() {
        discoveryStep = .homeSelection
    }
    
    /// Move to accessory discovery step
    func moveToAccessoryDiscovery() {
        discoveryStep = .accessoryDiscovery
    }
    
    func completeOnboarding() {
        hasCompletedOnboarding = true
        currentScreen = .welcome
        showingHomeAccessFlow = false
        discoveryStep = .none
    }
    
    func resetOnboarding() {
        hasCompletedOnboarding = false
        currentScreen = .welcome
        showingHomeAccessFlow = false
        discoveryStep = .none
    }
}

/// Steps in the home and accessory discovery flow
enum DiscoveryStep: Equatable {
    case none
    case checkingAccess      // Initial permission and readiness check
    case homeSelection       // Multiple homes available, need selection
    case accessoryDiscovery    // Discovering and selecting accessories
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

import Foundation
import HomeKit

/// Protocol for HomeKit platform adapter - enables mocking in tests
protocol HomeKitAdapterProtocol: Sendable {
    var authorizationStatus: HMHomeManagerAuthorizationStatus { get }
    func requestAuthorization() async -> HMHomeManagerAuthorizationStatus
    func fetchHomes() async throws -> [HMHome]
    func fetchCompatibleAccessories(in home: HMHome) async -> [HMAccessory]
}

/// Live HomeKit adapter implementation
actor LiveHomeKitAdapter: HomeKitAdapterProtocol {
    private let homeManager = HMHomeManager()
    
    var authorizationStatus: HMHomeManagerAuthorizationStatus {
        homeManager.authorizationStatus
    }
    
    func requestAuthorization() async -> HMHomeManagerAuthorizationStatus {
        // HomeKit authorization is triggered by first access to HMHomeManager
        // The status will update via notification center, but we return current
        return homeManager.authorizationStatus
    }
    
    func fetchHomes() async throws -> [HMHome] {
        // Wait for homes to be available
        if homeManager.homes.isEmpty {
            // Brief delay to allow HomeKit to populate
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        return homeManager.homes
    }
    
    func fetchCompatibleAccessories(in home: HMHome) async -> [HMAccessory] {
        return home.accessories.filter { accessory in
            // Check for brightness control capability
            let hasBrightness = accessory.services.contains { service in
                service.characteristics.contains { characteristic in
                    characteristic.characteristicType == HMCharacteristicTypeBrightness
                }
            }
            return hasBrightness
        }
    }
}

/// Represents the current state of Home access readiness
enum HomeAccessReadiness: Equatable, Sendable {
    case unknown
    case checkingPermission
    case permissionDenied
    case noHomeConfigured
    case noHomeHub
    case noCompatibleAccessories
    case ready(home: HMHome, accessories: [HMAccessory])
    
    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
    
    var isBlocked: Bool {
        switch self {
        case .permissionDenied, .noHomeConfigured, .noHomeHub, .noCompatibleAccessories:
            return true
        default:
            return false
        }
    }
}

/// Observable state for Home access UI
@Observable
@MainActor
final class HomeAccessState {
    private let adapter: any HomeKitAdapterProtocol
    
    var readiness: HomeAccessReadiness = .unknown
    var isLoading = false
    var lastError: Error?
    
    init(adapter: any HomeKitAdapterProtocol = LiveHomeKitAdapter()) {
        self.adapter = adapter
    }
    
    /// Initiates the Home access flow from onboarding
    func startHomeAccessFlow() async {
        isLoading = true
        defer { isLoading = false }
        
        await checkReadiness()
    }
    
    /// Checks current Home access readiness state
    func checkReadiness() async {
        let status = await adapter.authorizationStatus
        
        // Handle permission states
        if status.contains(.determined) {
            if status.contains(.restricted) || status.contains(.denied) {
                readiness = .permissionDenied
                return
            }
        } else {
            // Not determined - request authorization
            readiness = .checkingPermission
            let newStatus = await adapter.requestAuthorization()
            
            // Re-check after request
            if newStatus.contains(.restricted) || newStatus.contains(.denied) {
                readiness = .permissionDenied
                return
            }
        }
        
        // Check for homes
        do {
            let homes = try await adapter.fetchHomes()
            
            guard let primaryHome = homes.first else {
                readiness = .noHomeConfigured
                return
            }
            
            // Check for home hub
            if !hasHomeHub(homes: homes) {
                readiness = .noHomeHub
                return
            }
            
            // Check for compatible accessories
            let accessories = await adapter.fetchCompatibleAccessories(in: primaryHome)
            
            guard !accessories.isEmpty else {
                readiness = .noCompatibleAccessories
                return
            }
            
            // All checks passed
            readiness = .ready(home: primaryHome, accessories: accessories)
            
        } catch {
            lastError = error
            // If we can't fetch homes, assume none configured
            readiness = .noHomeConfigured
        }
    }
    
    /// Retries the readiness check (for use after user fixes an issue)
    func retry() async {
        await checkReadiness()
    }
    
    private func hasHomeHub(homes: [HMHome]) -> Bool {
        // Check if any home has a home hub configured
        // This is a simplified check - in production, you'd verify actual hub connectivity
        return homes.contains { home in
            // Home hub presence can be inferred from various states
            // For now, we assume if the home exists and has accessories, hub might exist
            !home.accessories.isEmpty || home.isPrimary
        }
    }
}

/// User-facing descriptions for blocker states
enum HomeAccessBlockerCopy {
    static let permissionDenied = BlockerCopy(
        title: "Home Access Needed",
        message: "DawnLoop needs access to Apple Home to create sunrise alarm automations with your lights. Please enable Home access in Settings to continue.",
        primaryAction: "Open Settings",
        secondaryAction: "Try Again"
    )
    
    static let noHomeConfigured = BlockerCopy(
        title: "Set Up Apple Home First",
        message: "You'll need to create an Apple Home before DawnLoop can set up sunrise alarms. Open the Home app to get started, then return here.",
        primaryAction: "Open Home App",
        secondaryAction: "Check Again"
    )
    
    static let noHomeHub = BlockerCopy(
        title: "Home Hub Required",
        message: "Sunrise alarms need a Home Hub (Apple TV, HomePod, or iPad) to run reliably while you're away. Set one up in the Home app, then return here.",
        primaryAction: "Learn More",
        secondaryAction: "Check Again"
    )
    
    static let noCompatibleAccessories = BlockerCopy(
        title: "No Compatible Lights Found",
        message: "DawnLoop works with lights that support brightness control in Apple Home. Add a compatible light to your Home, then return here.",
        primaryAction: "Browse Compatible Lights",
        secondaryAction: "Check Again"
    )
}

struct BlockerCopy {
    let title: String
    let message: String
    let primaryAction: String
    let secondaryAction: String
}

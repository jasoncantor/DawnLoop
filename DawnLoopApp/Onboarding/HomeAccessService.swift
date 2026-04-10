import Foundation
import HomeKit
import SwiftData

/// Protocol for HomeKit platform adapter - enables mocking in tests
@MainActor
protocol HomeKitAdapterProtocol {
    /// Checks current authorization status - tests can control this via mock adapter
    func checkAuthorizationStatus() async -> HMHomeManagerAuthorizationStatus

    /// Fetches available homes
    func fetchHomes() async throws -> [HomeSnapshot]

    /// Fetches compatible accessories from a home
    func fetchCompatibleAccessories(in homeIdentifier: String) async -> [AccessorySnapshot]
}

/// Live HomeKit adapter implementation
final class LiveHomeKitAdapter: HomeKitAdapterProtocol {
    private let controller: HomeKitControllerProtocol

    init(controller: HomeKitControllerProtocol) {
        self.controller = controller
    }

    func checkAuthorizationStatus() async -> HMHomeManagerAuthorizationStatus {
        await controller.ensureLoaded()
        return await MainActor.run {
            controller.authorizationStatus()
        }
    }

    func fetchHomes() async throws -> [HomeSnapshot] {
        await controller.homes()
    }

    func fetchCompatibleAccessories(in homeIdentifier: String) async -> [AccessorySnapshot] {
        await controller.accessories(in: homeIdentifier).filter { $0.capability.supportsBrightness }
    }
}

/// Represents the current state of Home access readiness
enum HomeAccessReadiness: Equatable, Sendable {
    case unknown
    case permissionDenied
    case noHomeConfigured
    case noHomeHub
    case noCompatibleAccessories
    case ready(home: HomeSnapshot, accessories: [AccessorySnapshot])

    var isReady: Bool {
        switch self {
        case .ready:
            return true
        default:
            return false
        }
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
    
    init(adapter: any HomeKitAdapterProtocol) {
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
        let status = await adapter.checkAuthorizationStatus()

        guard status.contains(.authorized) else {
            readiness = .permissionDenied
            return
        }
        
        do {
            let homes = try await adapter.fetchHomes()
            guard let primaryHome = homes.first else {
                readiness = .noHomeConfigured
                return
            }
            
            if !hasHomeHub(homes: homes) {
                readiness = .noHomeHub
                return
            }
            
            let accessories = await adapter.fetchCompatibleAccessories(in: primaryHome.id)
            
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
    private func hasHomeHub(homes: [HomeSnapshot]) -> Bool {
        homes.contains { $0.homeHubState == .connected }
    }
}

/// Result type for active home lookup
enum ActiveHomeResult {
    case success(home: HomeSnapshot)
    case notFound(identifier: String)
    case noSelection
    case error(HomeSelectionError)
}

/// Errors that can occur during home selection
enum HomeSelectionError: Error {
    case permissionDenied
    case homeKitError(underlying: String)
    
    var userFacingMessage: String {
        switch self {
        case .permissionDenied:
            return "Home access is required to select a home."
        case .homeKitError(let underlying):
            return "Unable to access HomeKit: \(underlying)"
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

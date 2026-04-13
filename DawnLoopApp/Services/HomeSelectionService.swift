import Foundation
import SwiftData

/// Protocol for home selection operations - enables mocking in tests
protocol HomeSelectionServiceProtocol {
    func availableHomes() async -> [HomeViewModel]
    func activeHome() async -> ActiveHomeResult
    func selectHome(_ homeId: String) async -> Bool
    func clearActiveHome() async
}

/// Service responsible for managing home selection and persistence
/// Handles multiple home display and active home selection (VAL-HOME-001, VAL-HOME-002)
@MainActor
final class HomeSelectionService: HomeSelectionServiceProtocol {
    private let adapter: any HomeKitAdapterProtocol
    private let modelContainer: ModelContainer
    
    init(
        adapter: any HomeKitAdapterProtocol,
        modelContainer: ModelContainer
    ) {
        self.adapter = adapter
        self.modelContainer = modelContainer
    }
    
    /// Returns all available homes with active status indicated
    func availableHomes() async -> [HomeViewModel] {
        do {
            let homes = try await adapter.fetchHomes()
            let activeId = await fetchActiveHomeIdentifier()
            
            return homes.map { home in
                HomeViewModel(
                    id: home.id,
                    homeKitIdentifier: home.id,
                    name: home.name,
                    isActive: home.id == activeId,
                    roomCount: home.roomCount,
                    accessoryCount: home.accessoryCount
                )
            }
        } catch {
            DawnLoopLogger.homeKit.error("Failed to fetch homes: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Returns the currently active home, or appropriate error state
    /// Falls back cleanly if the home no longer exists (VAL-HOME-002)
    func activeHome() async -> ActiveHomeResult {
        // Check permission first using the test-controllable method
        let status = await adapter.checkAuthorizationStatus()
        guard status.contains(.authorized) else {
            return .error(.permissionDenied)
        }
        
        // Get the persisted selection
        let activeId = await fetchActiveHomeIdentifier()
        guard let activeId = activeId else {
            return .noSelection
        }
        
        // Verify the home still exists
        do {
            let homes = try await adapter.fetchHomes()
            
            guard let home = homes.first(where: { $0.id == activeId }) else {
                // Home no longer exists - clear the selection (VAL-HOME-002)
                await clearActiveHome()
                return .notFound(identifier: activeId)
            }
            
            return .success(home: home)
            
        } catch {
            return .error(.homeKitError(underlying: error.localizedDescription))
        }
    }
    
    /// Selects a new active home and persists the selection
    /// Returns true if successful
    func selectHome(_ homeId: String) async -> Bool {
        do {
            let homes = try await adapter.fetchHomes()
            
            guard let home = homes.first(where: { $0.id == homeId }) else {
                return false
            }
            
            await persistHomeSelection(home)
            return true
            
        } catch {
            DawnLoopLogger.homeKit.error("Failed to select home \(homeId): \(error.localizedDescription)")
            return false
        }
    }
    
    /// Clears the active home selection
    func clearActiveHome() async {
        let context = ModelContext(modelContainer)
        
        do {
            var descriptor = FetchDescriptor<HomeReference>()
            descriptor.predicate = #Predicate { $0.isActive }
            
            if let active = try context.fetch(descriptor).first {
                active.isActive = false
                active.updatedAt = Date()
                try context.save()
            }
        } catch {
            DawnLoopLogger.persistence.error("Could not clear active home: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Helpers
    
    private func fetchActiveHomeIdentifier() async -> String? {
        let context = ModelContext(modelContainer)
        
        do {
            var descriptor = FetchDescriptor<HomeReference>()
            descriptor.predicate = #Predicate { $0.isActive }
            
            if let active = try context.fetch(descriptor).first {
                return active.homeKitIdentifier
            }
            
            return nil
        } catch {
            return nil
        }
    }
    
    private func persistHomeSelection(_ home: HomeSnapshot) async {
        let context = ModelContext(modelContainer)
        
        do {
            // Deactivate any currently active home
            var activeDescriptor = FetchDescriptor<HomeReference>()
            activeDescriptor.predicate = #Predicate { $0.isActive }
            
            if let currentlyActive = try context.fetch(activeDescriptor).first {
                currentlyActive.isActive = false
                currentlyActive.updatedAt = Date()
            }
            
            // Find or create reference for the new home
            let homeId = home.id
            var homeDescriptor = FetchDescriptor<HomeReference>()
            homeDescriptor.predicate = #Predicate { $0.homeKitIdentifier == homeId }
            
            let reference: HomeReference
            if let existing = try context.fetch(homeDescriptor).first {
                reference = existing
                reference.update(from: home)
                reference.isActive = true
            } else {
                reference = HomeReference(
                    homeKitIdentifier: homeId,
                    name: home.name,
                    isActive: true,
                    roomCount: home.roomCount,
                    accessoryCount: home.accessoryCount
                )
                context.insert(reference)
            }
            
            try context.save()
            
        } catch {
            DawnLoopLogger.persistence.error("Could not persist home selection: \(error.localizedDescription)")
        }
    }
}

/// Actor-based mock implementation for testing
final class MockHomeSelectionService: HomeSelectionServiceProtocol {
    var mockHomes: [HomeViewModel] = []
    var mockActiveHome: ActiveHomeResult = .noSelection
    var lastSelectedHomeId: String?
    var cleared = false
    
    func setMockHomes(_ homes: [HomeViewModel]) {
        self.mockHomes = homes
    }
    
    func setMockActiveHome(_ result: ActiveHomeResult) {
        self.mockActiveHome = result
    }
    
    func availableHomes() async -> [HomeViewModel] {
        mockHomes
    }
    
    func activeHome() async -> ActiveHomeResult {
        mockActiveHome
    }
    
    func selectHome(_ homeId: String) async -> Bool {
        lastSelectedHomeId = homeId
        return true
    }
    
    func clearActiveHome() async {
        cleared = true
    }
}

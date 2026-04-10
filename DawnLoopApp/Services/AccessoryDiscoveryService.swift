import Foundation
import SwiftData

/// Protocol for accessory discovery operations - enables mocking in tests
protocol AccessoryDiscoveryServiceProtocol {
    func discoverAccessories(in home: HomeSnapshot) async -> AccessoryDiscoveryResult
    func clearDiscoveredAccessories() async
    func selectedAccessories() async -> [AccessoryViewModel]
    func toggleAccessorySelection(_ accessoryId: String) async
}

/// Service responsible for discovering and managing compatible accessories
/// Handles filtering, room grouping, and selection state
@MainActor
final class AccessoryDiscoveryService: AccessoryDiscoveryServiceProtocol {
    private let adapter: any HomeKitAdapterProtocol
    private let modelContainer: ModelContainer
    
    init(
        adapter: any HomeKitAdapterProtocol,
        modelContainer: ModelContainer
    ) {
        self.adapter = adapter
        self.modelContainer = modelContainer
    }
    
    /// Discovers compatible accessories in the given home and groups them by room
    /// Clears any previous accessory results before loading new ones
    func discoverAccessories(in home: HomeSnapshot) async -> AccessoryDiscoveryResult {
        // Clear stale results first (VAL-HOME-006)
        await clearDiscoveredAccessories()
        
        let compatibleAccessories = await adapter.fetchCompatibleAccessories(in: home.id)
        
        guard !compatibleAccessories.isEmpty else {
            return .noCompatibleAccessories
        }
        
        // Build room groups
        let groups = await buildRoomGroups(
            accessories: compatibleAccessories,
            in: home
        )
        
        // Persist discovered accessories
        await persistDiscoveredAccessories(
            compatibleAccessories,
            in: home
        )
        
        return .success(groups: groups)
    }
    
    /// Clears all discovered accessory references
    /// Used when switching homes to prevent stale results (VAL-HOME-006)
    func clearDiscoveredAccessories() async {
        let context = ModelContext(modelContainer)
        
        do {
            let descriptor = FetchDescriptor<AccessoryReference>()
            let existing = try context.fetch(descriptor)
            
            for reference in existing {
                context.delete(reference)
            }
            
            try context.save()
        } catch {
            DawnLoopLogger.persistence.error("Could not clear accessory references: \(error.localizedDescription)")
        }
    }
    
    /// Returns currently selected accessories
    func selectedAccessories() async -> [AccessoryViewModel] {
        let context = ModelContext(modelContainer)
        
        do {
            var descriptor = FetchDescriptor<AccessoryReference>()
            descriptor.predicate = #Predicate { $0.isSelected }
            let selected = try context.fetch(descriptor)
            
            return selected.map { AccessoryViewModel(from: $0) }
        } catch {
            DawnLoopLogger.persistence.error("Could not fetch selected accessories: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Toggles selection state for an accessory
    func toggleAccessorySelection(_ accessoryId: String) async {
        let context = ModelContext(modelContainer)
        
        do {
            var descriptor = FetchDescriptor<AccessoryReference>()
            descriptor.predicate = #Predicate { $0.homeKitIdentifier == accessoryId }
            
            if let reference = try context.fetch(descriptor).first {
                reference.isSelected.toggle()
                reference.updatedAt = Date()
                try context.save()
            }
        } catch {
            DawnLoopLogger.persistence.error("Could not toggle accessory selection: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Helpers
    
    private func buildRoomGroups(
        accessories: [AccessorySnapshot],
        in home: HomeSnapshot
    ) async -> [RoomAccessoryGroup] {
        let viewModels = accessories.map { accessory in
            AccessoryViewModel(
                id: accessory.id,
                homeKitIdentifier: accessory.id,
                name: accessory.name,
                roomName: accessory.roomName,
                capability: accessory.capability,
                isSelected: false,
                isReachable: accessory.isReachable
            )
        }
        
        // Group by room
        let grouped = Dictionary(grouping: viewModels) { $0.roomName }
        
        // Sort rooms: named rooms first (alphabetically), then unassigned
        let sortedGroups = grouped.sorted { a, b in
            let aEmpty = a.key.isEmpty
            let bEmpty = b.key.isEmpty
            
            if aEmpty && !bEmpty { return false }
            if !aEmpty && bEmpty { return true }
            return a.key < b.key
        }
        
        return sortedGroups.map { RoomAccessoryGroup(roomName: $0.key, accessories: $0.value) }
    }
    
    private func persistDiscoveredAccessories(
        _ accessories: [AccessorySnapshot],
        in home: HomeSnapshot
    ) async {
        let context = ModelContext(modelContainer)
        
        for accessory in accessories {
            let reference = AccessoryReference(
                homeKitIdentifier: accessory.id,
                name: accessory.name,
                homeIdentifier: home.id,
                roomName: accessory.roomName,
                capability: accessory.capability
            )
            
            context.insert(reference)
        }
        
        do {
            try context.save()
        } catch {
            DawnLoopLogger.persistence.error("Could not persist accessory references: \(error.localizedDescription)")
        }
    }
}

/// Actor-based mock implementation for testing
final class MockAccessoryDiscoveryService: AccessoryDiscoveryServiceProtocol {
    var mockResult: AccessoryDiscoveryResult?
    var mockSelectedAccessories: [AccessoryViewModel] = []
    var cleared = false
    
    func setMockResult(_ result: AccessoryDiscoveryResult) {
        self.mockResult = result
    }
    
    func setMockSelectedAccessories(_ accessories: [AccessoryViewModel]) {
        self.mockSelectedAccessories = accessories
    }
    
    func discoverAccessories(in home: HomeSnapshot) async -> AccessoryDiscoveryResult {
        // Clear stale results (VAL-HOME-006)
        await clearDiscoveredAccessories()
        return mockResult ?? .noCompatibleAccessories
    }
    
    func clearDiscoveredAccessories() async {
        cleared = true
    }
    
    func selectedAccessories() async -> [AccessoryViewModel] {
        return mockSelectedAccessories
    }
    
    func toggleAccessorySelection(_ accessoryId: String) async {
        // Mock implementation - no-op
    }
}

import SwiftData
import Foundation
import HomeKit

/// Persistent record of a home selection for DawnLoop
/// Stores the home identifier and display name for re-selection on app relaunch
@Model
final class HomeReference {
    /// HomeKit home unique identifier (persistent across sessions)
    @Attribute(.unique) var homeKitIdentifier: String
    
    /// Display name of the home (may change, used for UI)
    var name: String
    
    /// Whether this is the currently active home selection
    var isActive: Bool
    
    /// Number of rooms in the home (for UI display)
    var roomCount: Int
    
    /// Number of accessories in the home (for UI display)
    var accessoryCount: Int
    
    /// When this record was created or last updated
    var updatedAt: Date
    
    init(homeKitIdentifier: String, name: String, isActive: Bool = true, roomCount: Int = 0, accessoryCount: Int = 0) {
        self.homeKitIdentifier = homeKitIdentifier
        self.name = name
        self.isActive = isActive
        self.roomCount = roomCount
        self.accessoryCount = accessoryCount
        self.updatedAt = Date()
    }
    
    /// Updates the reference from a live HMHome object
    func update(from home: HMHome) {
        self.name = home.name
        self.roomCount = home.rooms.count
        self.accessoryCount = home.accessories.count
        self.updatedAt = Date()
    }

    func update(from home: HomeSnapshot) {
        self.name = home.name
        self.roomCount = home.roomCount
        self.accessoryCount = home.accessoryCount
        self.updatedAt = Date()
    }
}

/// Domain model for home selection UI
struct HomeViewModel: Identifiable, Equatable, Sendable {
    let id: String
    let homeKitIdentifier: String
    let name: String
    let isActive: Bool
    let roomCount: Int
    let accessoryCount: Int
    
    init(id: String, homeKitIdentifier: String, name: String, isActive: Bool, roomCount: Int, accessoryCount: Int) {
        self.id = id
        self.homeKitIdentifier = homeKitIdentifier
        self.name = name
        self.isActive = isActive
        self.roomCount = roomCount
        self.accessoryCount = accessoryCount
    }
    
    init(from home: HMHome, isActive: Bool = false) {
        self.id = home.uniqueIdentifier.uuidString
        self.homeKitIdentifier = home.uniqueIdentifier.uuidString
        self.name = home.name
        self.isActive = isActive
        self.roomCount = home.rooms.count
        self.accessoryCount = home.accessories.count
    }
    
    init(from reference: HomeReference) {
        self.id = reference.homeKitIdentifier
        self.homeKitIdentifier = reference.homeKitIdentifier
        self.name = reference.name
        self.isActive = reference.isActive
        self.roomCount = reference.roomCount
        self.accessoryCount = reference.accessoryCount
    }
}

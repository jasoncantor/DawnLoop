import SwiftData
import Foundation
import HomeKit

/// Represents the capability class of a HomeKit accessory for wake-light routines
enum AccessoryCapability: String, Codable, Sendable, CaseIterable {
    case brightnessOnly = "brightness_only"
    case tunableWhite = "tunable_white"
    case fullColor = "full_color"
    case unsupported = "unsupported"
    
    var displayName: String {
        switch self {
        case .brightnessOnly:
            return "Brightness"
        case .tunableWhite:
            return "Brightness + Warmth"
        case .fullColor:
            return "Brightness + Color"
        case .unsupported:
            return "Not Supported"
        }
    }
    
    var supportsBrightness: Bool {
        switch self {
        case .brightnessOnly, .tunableWhite, .fullColor:
            return true
        case .unsupported:
            return false
        }
    }
    
    var supportsColorTemperature: Bool {
        switch self {
        case .tunableWhite, .fullColor:
            return true
        case .brightnessOnly, .unsupported:
            return false
        }
    }
    
    var supportsHueSaturation: Bool {
        switch self {
        case .fullColor:
            return true
        case .brightnessOnly, .tunableWhite, .unsupported:
            return false
        }
    }
}

/// Persistent record of a discovered accessory for DawnLoop
@Model
final class AccessoryReference {
    /// HomeKit accessory unique identifier
    @Attribute(.unique) var homeKitIdentifier: String
    
    /// Display name of the accessory
    var name: String
    
    /// Identifier of the home this accessory belongs to
    var homeIdentifier: String
    
    /// Room name where this accessory is located (may be empty for unassigned)
    var roomName: String
    
    /// Whether this accessory is currently selected for alarm creation
    var isSelected: Bool
    
    /// The capability class of this accessory
    var capabilityRaw: String
    
    /// When this record was created or last updated
    var updatedAt: Date
    
    var capability: AccessoryCapability {
        get { AccessoryCapability(rawValue: capabilityRaw) ?? .unsupported }
        set { capabilityRaw = newValue.rawValue }
    }
    
    init(
        homeKitIdentifier: String,
        name: String,
        homeIdentifier: String,
        roomName: String,
        capability: AccessoryCapability,
        isSelected: Bool = false
    ) {
        self.homeKitIdentifier = homeKitIdentifier
        self.name = name
        self.homeIdentifier = homeIdentifier
        self.roomName = roomName
        self.capabilityRaw = capability.rawValue
        self.isSelected = isSelected
        self.updatedAt = Date()
    }
    
    /// Convenience initializer for testing with isCompatible flag
    init(
        homeKitIdentifier: String,
        name: String,
        roomName: String,
        homeIdentifier: String,
        isCompatible: Bool
    ) {
        self.homeKitIdentifier = homeKitIdentifier
        self.name = name
        self.homeIdentifier = homeIdentifier
        self.roomName = roomName
        self.capabilityRaw = isCompatible ? AccessoryCapability.brightnessOnly.rawValue : AccessoryCapability.unsupported.rawValue
        self.isSelected = false
        self.updatedAt = Date()
    }
    
    /// Updates the reference from a live HMAccessory and room info
    func update(from accessory: HMAccessory, roomName: String, capability: AccessoryCapability) {
        self.name = accessory.name
        self.roomName = roomName
        self.capabilityRaw = capability.rawValue
        self.updatedAt = Date()
    }
}

/// Domain model for accessory display in UI
struct AccessoryViewModel: Identifiable, Equatable, Sendable {
    let id: String
    let homeKitIdentifier: String
    let name: String
    let roomName: String
    let capability: AccessoryCapability
    var isSelected: Bool
    let isReachable: Bool

    init(
        id: String,
        homeKitIdentifier: String,
        name: String,
        roomName: String,
        capability: AccessoryCapability,
        isSelected: Bool,
        isReachable: Bool
    ) {
        self.id = id
        self.homeKitIdentifier = homeKitIdentifier
        self.name = name
        self.roomName = roomName
        self.capability = capability
        self.isSelected = isSelected
        self.isReachable = isReachable
    }
    
    init(from accessory: HMAccessory, roomName: String, isSelected: Bool = false) {
        self.id = accessory.uniqueIdentifier.uuidString
        self.homeKitIdentifier = accessory.uniqueIdentifier.uuidString
        self.name = accessory.name
        self.roomName = roomName
        self.capability = AccessoryCapabilityDetector.detectCapability(for: accessory)
        self.isSelected = isSelected
        self.isReachable = accessory.isReachable
    }
    
    init(from reference: AccessoryReference) {
        self.id = reference.homeKitIdentifier
        self.homeKitIdentifier = reference.homeKitIdentifier
        self.name = reference.name
        self.roomName = reference.roomName
        self.capability = reference.capability
        self.isSelected = reference.isSelected
        self.isReachable = true // Persisted references assume reachable
    }
    
    var isCompatible: Bool {
        capability.supportsBrightness
    }
}

/// Groups accessories by room for display
struct RoomAccessoryGroup: Identifiable, Equatable, Sendable {
    let id: String
    let roomName: String
    var accessories: [AccessoryViewModel]
    
    init(roomName: String, accessories: [AccessoryViewModel]) {
        self.id = roomName.isEmpty ? "unassigned" : roomName
        self.roomName = roomName.isEmpty ? "Unassigned" : roomName
        self.accessories = accessories
    }
    
    var selectedCount: Int {
        accessories.filter(\.isSelected).count
    }
    
    var hasSelection: Bool {
        selectedCount > 0
    }
}

/// Result of accessory discovery for a home
enum AccessoryDiscoveryResult {
    case success(groups: [RoomAccessoryGroup])
    case noCompatibleAccessories
    case homeNotFound
    case error(Error)
}

/// Detects the capability class of a HomeKit accessory
enum AccessoryCapabilityDetector {
    static func detectCapability(for accessory: HMAccessory) -> AccessoryCapability {
        var hasBrightness = false
        var hasHue = false
        var hasSaturation = false
        var hasColorTemp = false
        
        for service in accessory.services {
            for characteristic in service.characteristics {
                switch characteristic.characteristicType {
                case HMCharacteristicTypeBrightness:
                    hasBrightness = true
                case HMCharacteristicTypeHue:
                    hasHue = true
                case HMCharacteristicTypeSaturation:
                    hasSaturation = true
                case HMCharacteristicTypeColorTemperature:
                    hasColorTemp = true
                default:
                    break
                }
            }
        }
        
        // Determine capability based on available characteristics
        if hasBrightness && hasHue && hasSaturation {
            return .fullColor
        } else if hasBrightness && hasColorTemp {
            return .tunableWhite
        } else if hasBrightness {
            return .brightnessOnly
        } else {
            return .unsupported
        }
    }
}

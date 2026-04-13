import SwiftData
import Foundation

/// Persistent model for alarm validation state
/// Provides a dedicated validation-state model + repository mapping (VAL-ALARM contract)
@Model
final class ValidationStateRecord: @unchecked Sendable {
    /// Unique identifier for this validation state record
    @Attribute(.unique) var id: UUID

    /// Reference to the alarm this validation state belongs to
    @Attribute(.unique) var alarmId: UUID

    /// Validation state raw value
    var stateRaw: String

    /// When this validation state was created
    var createdAt: Date

    /// When this validation state was last updated
    var updatedAt: Date

    /// Human-readable message explaining the validation state
    var message: String?

    /// Error details if validation failed
    var errorDetails: String?

    /// Whether this state requires user action
    var requiresUserAction: Bool

    init(
        id: UUID = UUID(),
        alarmId: UUID,
        state: AlarmValidationState = .unknown,
        message: String? = nil,
        errorDetails: String? = nil,
        requiresUserAction: Bool = false
    ) {
        self.id = id
        self.alarmId = alarmId
        self.stateRaw = state.rawValue
        self.message = message
        self.errorDetails = errorDetails
        self.requiresUserAction = requiresUserAction
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// The validation state as an enum
    var state: AlarmValidationState {
        get { AlarmValidationState(rawValue: stateRaw) ?? .unknown }
        set {
            stateRaw = newValue.rawValue
            updatedAt = Date()
        }
    }

    /// Update the validation state
    func updateState(
        _ newState: AlarmValidationState,
        message: String? = nil,
        errorDetails: String? = nil,
        requiresUserAction: Bool? = nil
    ) {
        self.stateRaw = newState.rawValue
        if let message = message { self.message = message }
        if let errorDetails = errorDetails { self.errorDetails = errorDetails }
        if let requiresUserAction = requiresUserAction { self.requiresUserAction = requiresUserAction }
        self.updatedAt = Date()
    }
}

/// Summary of validation state for display
struct ValidationStateSummary: Equatable, Sendable {
    let state: AlarmValidationState
    let message: String?
    let requiresUserAction: Bool
    let lastUpdated: Date?

    var displayText: String {
        switch state {
        case .unknown:
            return "Unknown"
        case .valid:
            return "Ready"
        case .needsSync:
            return "Syncing..."
        case .outOfSync:
            return "Needs Repair"
        case .invalidAccessories:
            return "Accessories Changed"
        case .permissionRevoked:
            return "No Access"
        case .homeUnavailable:
            return "Home Unavailable"
        }
    }

    var isHealthy: Bool {
        state == .valid || state == .unknown
    }

    var isActionable: Bool {
        requiresUserAction || state == .outOfSync || state == .invalidAccessories
    }
}

extension ValidationStateRecord {
    /// Convert to a summary for UI display
    func toSummary() -> ValidationStateSummary {
        ValidationStateSummary(
            state: state,
            message: message,
            requiresUserAction: requiresUserAction,
            lastUpdated: updatedAt
        )
    }
}

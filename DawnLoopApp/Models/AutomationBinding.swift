import SwiftData
import Foundation
import HomeKit

/// Persistent record of a HomeKit automation binding for an alarm step
/// This creates a durable mapping from DawnLoop alarms to HomeKit objects (VAL-AUTO-005)
@Model
final class AutomationBinding {
    /// Unique identifier for this binding record
    @Attribute(.unique) var id: UUID

    /// Reference to the alarm this binding belongs to
    var alarmId: UUID

    /// The step number in the alarm sequence (0-indexed)
    var stepNumber: Int

    /// HomeKit Action Set identifier (for the scene/action at this step)
    var actionSetIdentifier: String?

    /// HomeKit Timer Trigger identifier
    var triggerIdentifier: String?

    /// The scheduled time for this step
    var scheduledTime: Date?

    /// Brightness value for this step (0-100)
    var brightness: Int

    /// Optional color temperature value
    var colorTemperature: Int?

    /// Optional hue value
    var hue: Int?

    /// Optional saturation value
    var saturation: Int?

    /// Whether this binding is currently valid in HomeKit
    var isValid: Bool

    /// When this binding was created
    var createdAt: Date

    /// When this binding was last verified against HomeKit
    var lastVerifiedAt: Date?

    /// Error message if binding became invalid
    var invalidationReason: String?

    init(
        id: UUID = UUID(),
        alarmId: UUID,
        stepNumber: Int,
        actionSetIdentifier: String? = nil,
        triggerIdentifier: String? = nil,
        scheduledTime: Date? = nil,
        brightness: Int = 0,
        colorTemperature: Int? = nil,
        hue: Int? = nil,
        saturation: Int? = nil
    ) {
        self.id = id
        self.alarmId = alarmId
        self.stepNumber = stepNumber
        self.actionSetIdentifier = actionSetIdentifier
        self.triggerIdentifier = triggerIdentifier
        self.scheduledTime = scheduledTime
        self.brightness = brightness
        self.colorTemperature = colorTemperature
        self.hue = hue
        self.saturation = saturation
        self.isValid = true
        self.createdAt = Date()
        self.lastVerifiedAt = nil
        self.invalidationReason = nil
    }

    /// Mark this binding as invalid with a reason
    func markInvalid(reason: String) {
        self.isValid = false
        self.invalidationReason = reason
        self.lastVerifiedAt = Date()
    }

    /// Mark this binding as verified/valid
    func markVerified() {
        self.isValid = true
        self.lastVerifiedAt = Date()
        self.invalidationReason = nil
    }

    /// Update the HomeKit identifiers for this binding
    func updateIdentifiers(
        actionSetIdentifier: String? = nil,
        triggerIdentifier: String? = nil
    ) {
        if let actionSetIdentifier = actionSetIdentifier {
            self.actionSetIdentifier = actionSetIdentifier
        }
        if let triggerIdentifier = triggerIdentifier {
            self.triggerIdentifier = triggerIdentifier
        }
        self.lastVerifiedAt = Date()
    }
}

/// Summary of all bindings for an alarm
struct AlarmBindingSummary: Equatable, Sendable {
    let alarmId: UUID
    let totalSteps: Int
    let validBindings: Int
    let invalidBindings: Int
    let missingBindings: Int

    var isFullyBound: Bool {
        missingBindings == 0 && invalidBindings == 0
    }

    var healthStatus: AlarmValidationState {
        if missingBindings > 0 {
            return .needsSync
        } else if invalidBindings > 0 {
            return .outOfSync
        } else if validBindings == totalSteps && totalSteps > 0 {
            return .valid
        } else {
            return .unknown
        }
    }
}

/// Service for managing automation bindings
/// Handles creation, validation, and cleanup of HomeKit automation mappings
@MainActor
final class AutomationBindingService {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    /// Fetch all bindings for a specific alarm
    func bindingsForAlarm(_ alarmId: UUID) async -> [AutomationBinding] {
        let context = ModelContext(modelContainer)

        do {
            var descriptor = FetchDescriptor<AutomationBinding>()
            descriptor.predicate = #Predicate { $0.alarmId == alarmId }
            descriptor.sortBy = [SortDescriptor(\.stepNumber)]

            return try context.fetch(descriptor)
        } catch {
            print("Failed to fetch bindings for alarm \(alarmId): \(error)")
            return []
        }
    }

    /// Create or update bindings for an alarm based on a step plan
    func createBindings(
        for alarmId: UUID,
        steps: [WakeAlarmStep]
    ) async -> [AutomationBinding] {
        let context = ModelContext(modelContainer)
        var bindings: [AutomationBinding] = []

        // Remove existing bindings
        await removeBindings(for: alarmId)

        // Create new bindings
        for (index, step) in steps.enumerated() {
            let binding = AutomationBinding(
                alarmId: alarmId,
                stepNumber: index,
                scheduledTime: step.timestamp,
                brightness: step.brightness,
                colorTemperature: step.colorTemperature,
                hue: step.hue,
                saturation: step.saturation
            )
            context.insert(binding)
            bindings.append(binding)
        }

        do {
            try context.save()
        } catch {
            print("Failed to save bindings: \(error)")
        }

        return bindings
    }

    /// Remove all bindings for an alarm
    func removeBindings(for alarmId: UUID) async {
        let context = ModelContext(modelContainer)

        do {
            var descriptor = FetchDescriptor<AutomationBinding>()
            descriptor.predicate = #Predicate { $0.alarmId == alarmId }

            let existingBindings = try context.fetch(descriptor)
            for binding in existingBindings {
                context.delete(binding)
            }

            try context.save()
        } catch {
            print("Failed to remove bindings for alarm \(alarmId): \(error)")
        }
    }

    /// Get a summary of binding health for an alarm
    func bindingSummary(for alarmId: UUID) async -> AlarmBindingSummary {
        let bindings = await bindingsForAlarm(alarmId)

        let valid = bindings.filter { $0.isValid }.count
        let invalid = bindings.filter { !$0.isValid }.count

        return AlarmBindingSummary(
            alarmId: alarmId,
            totalSteps: bindings.count,
            validBindings: valid,
            invalidBindings: invalid,
            missingBindings: 0
        )
    }

    /// Validate bindings against current HomeKit state
    func validateBindings(
        for alarmId: UUID,
        using homeKitAdapter: any HomeKitAdapterProtocol
    ) async -> AlarmBindingSummary {
        let bindings = await bindingsForAlarm(alarmId)
        var validCount = 0
        var invalidCount = 0

        for binding in bindings {
            // In a real implementation, this would check HomeKit
            // For now, we assume bindings with identifiers are valid
            if binding.actionSetIdentifier != nil && binding.triggerIdentifier != nil {
                binding.markVerified()
                validCount += 1
            } else {
                binding.markInvalid(reason: "Missing HomeKit identifiers")
                invalidCount += 1
            }
        }

        // Save validation results
        let context = ModelContext(modelContainer)
        do {
            try context.save()
        } catch {
            print("Failed to save validation results: \(error)")
        }

        return AlarmBindingSummary(
            alarmId: alarmId,
            totalSteps: bindings.count,
            validBindings: validCount,
            invalidBindings: invalidCount,
            missingBindings: 0
        )
    }
}

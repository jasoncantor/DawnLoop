import Foundation
import SwiftData

@MainActor
final class AutomationRepairService {
    private let homeKitController: HomeKitControllerProtocol
    private let modelContainer: ModelContainer
    private let alarmRepository: WakeAlarmRepository
    private let generationService: AutomationGenerationService

    init(
        homeKitController: HomeKitControllerProtocol,
        modelContainer: ModelContainer,
        alarmRepository: WakeAlarmRepository,
        generationService: AutomationGenerationService
    ) {
        self.homeKitController = homeKitController
        self.modelContainer = modelContainer
        self.alarmRepository = alarmRepository
        self.generationService = generationService
    }

    func validateAlarm(_ alarm: WakeAlarm, schedule: WeekdaySchedule?) async -> ValidationStateSummary {
        if let completed = await completeFiredOneShotIfNeeded(alarm, schedule: schedule) {
            return completed
        }

        let summary = await validationSummary(for: alarm, schedule: schedule)
        try? await alarmRepository.updateValidationState(
            for: alarm.id,
            state: summary.state,
            message: summary.message,
            requiresUserAction: summary.requiresUserAction
        )
        return summary
    }

    func repairAlarm(_ alarm: WakeAlarm, schedule: WeekdaySchedule?) async throws -> ValidationStateSummary {
        if let completed = await completeFiredOneShotIfNeeded(alarm, schedule: schedule) {
            return completed
        }

        let current = await validationSummary(for: alarm, schedule: schedule)
        if current.state == .invalidAccessories || current.state == .homeUnavailable || current.state == .permissionRevoked {
            try await alarmRepository.updateValidationState(
                for: alarm.id,
                state: current.state,
                message: current.message,
                requiresUserAction: current.requiresUserAction
            )
            return current
        }

        try await generationService.syncAlarm(alarm, schedule: schedule)
        return await validateAlarm(alarm, schedule: schedule)
    }

    /// A non-repeating alarm is done once its wake step has fired (the executeOnce
    /// HomeKit triggers disable themselves). Turn the alarm off like a regular clock
    /// alarm instead of leaving it claiming a next run forever.
    private func completeFiredOneShotIfNeeded(
        _ alarm: WakeAlarm,
        schedule: WeekdaySchedule?,
        now: Date = Date()
    ) async -> ValidationStateSummary? {
        guard
            alarm.isEnabled,
            alarm.timeReference == .clock,
            !(schedule ?? .never).isRepeating
        else {
            return nil
        }

        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<AutomationBinding>()
        let alarmID = alarm.id
        descriptor.predicate = #Predicate { $0.alarmId == alarmID }
        let bindings = (try? context.fetch(descriptor)) ?? []

        let scheduledTimes = bindings.compactMap(\.scheduledTime)
        guard !scheduledTimes.isEmpty, let lastFire = scheduledTimes.max(), lastFire < now else {
            return nil
        }

        // If the alarm was edited or toggled after those steps fired, the bindings are
        // stale leftovers of a pending re-sync, not proof the alarm is finished -
        // disabling here would turn off an alarm the user just rescheduled.
        guard alarm.updatedAt <= lastFire else {
            return nil
        }

        try? await alarmRepository.setAlarmEnabled(alarm, enabled: false)
        let summary = ValidationStateSummary(
            state: .valid,
            message: "One-time alarm finished. Turn it on again to reschedule it.",
            requiresUserAction: false,
            lastUpdated: now
        )
        try? await alarmRepository.updateValidationState(
            for: alarm.id,
            state: summary.state,
            message: summary.message,
            requiresUserAction: summary.requiresUserAction
        )
        return summary
    }

    private func validationSummary(for alarm: WakeAlarm, schedule: WeekdaySchedule?) async -> ValidationStateSummary {
        guard alarm.isEnabled else {
            return ValidationStateSummary(
                state: .valid,
                message: "Alarm is disabled.",
                requiresUserAction: false,
                lastUpdated: Date()
            )
        }

        guard homeKitController.authorizationStatus().contains(.authorized) else {
            return ValidationStateSummary(
                state: .permissionRevoked,
                message: "Home access is no longer authorized.",
                requiresUserAction: true,
                lastUpdated: Date()
            )
        }

        guard let homeIdentifier = alarm.homeIdentifier else {
            return ValidationStateSummary(
                state: .homeUnavailable,
                message: "Choose an Apple Home for this alarm.",
                requiresUserAction: true,
                lastUpdated: Date()
            )
        }

        let homes = await homeKitController.homes()
        guard homes.contains(where: { $0.id == homeIdentifier }) else {
            return ValidationStateSummary(
                state: .homeUnavailable,
                message: "The selected Apple Home is no longer available.",
                requiresUserAction: true,
                lastUpdated: Date()
            )
        }

        let accessories = await homeKitController.accessories(in: homeIdentifier)
        let availableAccessoryIDs = Set(accessories.map(\.id))
        let selectedAccessoryIDs = Set(alarm.selectedAccessoryIdentifiers)

        guard !selectedAccessoryIDs.isEmpty else {
            return ValidationStateSummary(
                state: .invalidAccessories,
                message: "Select at least one light for this alarm.",
                requiresUserAction: true,
                lastUpdated: Date()
            )
        }

        let missingAccessories = selectedAccessoryIDs.subtracting(availableAccessoryIDs)
        guard missingAccessories.isEmpty else {
            return ValidationStateSummary(
                state: .invalidAccessories,
                message: "One or more selected lights are no longer available.",
                requiresUserAction: true,
                lastUpdated: Date()
            )
        }

        // Mirror syncAlarm's accessory filter exactly - including unsupported
        // accessories here would degrade the plan differently than generation did
        // and flag healthy alarms with a value drift that repair can never fix.
        let expectedBindings = generationService.expectedBindings(
            for: alarm,
            schedule: schedule,
            accessories: accessories.filter {
                selectedAccessoryIDs.contains($0.id) && $0.capability.supportsBrightness
            }
        )

        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<AutomationBinding>()
        let alarmID = alarm.id
        descriptor.predicate = #Predicate { $0.alarmId == alarmID }

        let allBindings = (try? context.fetch(descriptor)) ?? []
        if allBindings.isEmpty {
            return ValidationStateSummary(
                state: .needsSync,
                message: "Home automation has not been created yet.",
                requiresUserAction: false,
                lastUpdated: Date()
            )
        }

        // For a one-shot alarm mid-ramp, steps that already fired are intentionally
        // absent from the expected set; ignore their bindings instead of flagging drift.
        let isRepeating = (schedule ?? .never).isRepeating
        let now = Date()
        let bindings: [AutomationBinding]
        if !isRepeating, alarm.timeReference == .clock {
            bindings = allBindings.filter { ($0.scheduledTime ?? .distantFuture) > now }
        } else {
            bindings = allBindings
        }

        let expectedKeys = Set(expectedBindings.map(\.bindingKey))
        let actualKeys = Set(bindings.map(BindingKey.init(binding:)))
        if expectedKeys != actualKeys {
            return ValidationStateSummary(
                state: .outOfSync,
                message: "Home automation bindings are missing or outdated.",
                requiresUserAction: true,
                lastUpdated: Date()
            )
        }

        let calendar = Calendar.current
        for expected in expectedBindings {
            guard let binding = bindings.first(where: {
                $0.stepNumber == expected.stepNumber && $0.weekday == expected.weekday
            }) else {
                return ValidationStateSummary(
                    state: .outOfSync,
                    message: "Home automation bindings are incomplete.",
                    requiresUserAction: true,
                    lastUpdated: Date()
                )
            }

            let actionSetExists = await homeKitController.actionSetExists(
                homeIdentifier: homeIdentifier,
                identifier: binding.actionSetIdentifier
            )
            let triggerExists = await homeKitController.triggerExists(
                homeIdentifier: homeIdentifier,
                identifier: binding.triggerIdentifier
            )

            guard actionSetExists, triggerExists else {
                binding.markInvalid(reason: "Missing HomeKit automation objects")
                try? context.save()
                return ValidationStateSummary(
                    state: .outOfSync,
                    message: "HomeKit automation is missing pieces and needs repair.",
                    requiresUserAction: true,
                    lastUpdated: Date()
                )
            }

            if let expectedScheduledTime = expected.scheduledTime {
                guard let scheduledTime = binding.scheduledTime else {
                    binding.markInvalid(reason: "Scheduled time missing from binding")
                    try? context.save()
                    return ValidationStateSummary(
                        state: .outOfSync,
                        message: "The next HomeKit run time drifted and needs repair.",
                        requiresUserAction: true,
                        lastUpdated: Date()
                    )
                }

                // Repeating triggers fire at a time of day on recurrence weekdays, so the
                // absolute occurrence advancing past each firing is normal, not drift.
                // Comparing absolute dates here is what used to flag every healthy
                // repeating alarm as "Needs Repair" the morning after it ran.
                let drifted: Bool
                if isRepeating {
                    let expectedTime = calendar.dateComponents([.hour, .minute], from: expectedScheduledTime)
                    let actualTime = calendar.dateComponents([.hour, .minute], from: scheduledTime)
                    drifted = expectedTime != actualTime
                } else {
                    drifted = abs(scheduledTime.timeIntervalSince(expectedScheduledTime)) > 61
                }

                if drifted {
                    binding.markInvalid(reason: "Scheduled time drifted from expected plan")
                    try? context.save()
                    return ValidationStateSummary(
                        state: .outOfSync,
                        message: "The next HomeKit run time drifted and needs repair.",
                        requiresUserAction: true,
                        lastUpdated: Date()
                    )
                }
            }

            // Catch value drift (edits that never reached HomeKit, partial syncs).
            let valuesMatch = binding.brightness == expected.step.brightness
                && binding.colorTemperature == expected.step.colorTemperature
                && binding.hue == expected.step.hue
                && binding.saturation == expected.step.saturation
            guard valuesMatch else {
                binding.markInvalid(reason: "Light settings drifted from the alarm plan")
                try? context.save()
                return ValidationStateSummary(
                    state: .outOfSync,
                    message: "Light settings drifted from this alarm and need repair.",
                    requiresUserAction: true,
                    lastUpdated: Date()
                )
            }

            binding.markVerified()
        }

        try? context.save()
        return ValidationStateSummary(
            state: .valid,
            message: "Home automation is healthy.",
            requiresUserAction: false,
            lastUpdated: Date()
        )
    }
}

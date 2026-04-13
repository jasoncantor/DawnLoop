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

        let expectedBindings = generationService.expectedBindings(
            for: alarm,
            schedule: schedule,
            accessories: accessories.filter { selectedAccessoryIDs.contains($0.id) }
        )

        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<AutomationBinding>()
        let alarmID = alarm.id
        descriptor.predicate = #Predicate { $0.alarmId == alarmID }

        let bindings = (try? context.fetch(descriptor)) ?? []
        if bindings.isEmpty {
            return ValidationStateSummary(
                state: .needsSync,
                message: "Home automation has not been created yet.",
                requiresUserAction: false,
                lastUpdated: Date()
            )
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

                if abs(scheduledTime.timeIntervalSince(expectedScheduledTime)) > 61 {
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

import Foundation
import SwiftData
import HomeKit

@MainActor
final class AutomationGenerationService {
    private let homeKitController: HomeKitControllerProtocol
    private let modelContainer: ModelContainer
    private let alarmRepository: WakeAlarmRepository

    init(
        homeKitController: HomeKitControllerProtocol,
        modelContainer: ModelContainer,
        alarmRepository: WakeAlarmRepository
    ) {
        self.homeKitController = homeKitController
        self.modelContainer = modelContainer
        self.alarmRepository = alarmRepository
    }

    func syncAlarm(_ alarm: WakeAlarm, schedule: WeekdaySchedule?) async throws {
        guard alarm.isEnabled else {
            try await removeAutomations(for: alarm, markDisabled: true)
            return
        }

        guard let homeIdentifier = alarm.homeIdentifier else {
            try await alarmRepository.updateValidationState(
                for: alarm.id,
                state: .homeUnavailable,
                message: "Pick an Apple Home before enabling this alarm.",
                requiresUserAction: true
            )
            throw AutomationGenerationError.homeUnavailable
        }

        let accessories = await selectedAccessories(for: alarm, in: homeIdentifier)
        guard !accessories.isEmpty else {
            try await alarmRepository.updateValidationState(
                for: alarm.id,
                state: .invalidAccessories,
                message: "Select at least one compatible light to enable this alarm.",
                requiresUserAction: true
            )
            throw AutomationGenerationError.noAccessories
        }

        let expectedBindings = expectedBindings(for: alarm, schedule: schedule, accessories: accessories)
        guard !expectedBindings.isEmpty else {
            try await alarmRepository.updateValidationState(
                for: alarm.id,
                state: .needsSync,
                message: "DawnLoop could not calculate the next sunrise run time.",
                requiresUserAction: true
            )
            throw AutomationGenerationError.noUpcomingRun
        }

        let context = ModelContext(modelContainer)
        let existingBindings = try fetchBindings(for: alarm.id, in: context)

        var actionSetByStep: [Int: String] = [:]
        for binding in existingBindings {
            guard
                let actionSetIdentifier = binding.actionSetIdentifier,
                actionSetByStep[binding.stepNumber] == nil
            else {
                continue
            }
            actionSetByStep[binding.stepNumber] = actionSetIdentifier
        }

        var createdTriggers: [String] = []
        var createdActionSets: [String] = []

        do {
            for expected in expectedBindings {
                let existingBinding = existingBindings.first {
                    $0.stepNumber == expected.stepNumber && $0.weekday == expected.weekday
                }

                let actionSetIdentifier = actionSetByStep[expected.stepNumber] ?? existingBinding?.actionSetIdentifier
                let actionSetResult = try await homeKitController.upsertActionSet(
                    homeIdentifier: homeIdentifier,
                    identifier: actionSetIdentifier,
                    name: namespacedActionSetName(for: alarm.id, stepNumber: expected.stepNumber),
                    requests: expected.actionRequests
                )
                actionSetByStep[expected.stepNumber] = actionSetResult.identifier
                if actionSetResult.created {
                    createdActionSets.append(actionSetResult.identifier)
                }

                let triggerResult = try await homeKitController.upsertTimerTrigger(
                    homeIdentifier: homeIdentifier,
                    identifier: existingBinding?.triggerIdentifier,
                    name: namespacedTriggerName(
                        for: alarm.id,
                        stepNumber: expected.stepNumber,
                        weekday: expected.weekday
                    ),
                    fireDate: expected.fireDate,
                    recurrence: expected.recurrence,
                    actionSetIdentifier: actionSetResult.identifier,
                    isEnabled: true
                )
                if triggerResult.created {
                    createdTriggers.append(triggerResult.identifier)
                }

                let binding = existingBinding ?? AutomationBinding(
                    alarmId: alarm.id,
                    stepNumber: expected.stepNumber,
                    weekday: expected.weekday
                )
                if existingBinding == nil {
                    context.insert(binding)
                }

                binding.weekday = expected.weekday
                binding.actionSetIdentifier = actionSetResult.identifier
                binding.triggerIdentifier = triggerResult.identifier
                binding.scheduledTime = expected.fireDate
                binding.brightness = expected.step.brightness
                binding.colorTemperature = expected.step.colorTemperature
                binding.hue = expected.step.hue
                binding.saturation = expected.step.saturation
                binding.markVerified()
            }

            let expectedKeys = Set(expectedBindings.map(\.bindingKey))
            let staleBindings = existingBindings.filter { !expectedKeys.contains(BindingKey(binding: $0)) }
            try await deleteBindings(
                staleBindings,
                homeIdentifier: homeIdentifier,
                activeStepNumbers: Set(expectedBindings.map(\.stepNumber)),
                in: context
            )

            try context.save()
            try await alarmRepository.updateValidationState(
                for: alarm.id,
                state: .valid,
                message: "Home automation is synced.",
                requiresUserAction: false
            )
        } catch {
            for triggerIdentifier in createdTriggers {
                try? await homeKitController.deleteTimerTrigger(homeIdentifier: homeIdentifier, identifier: triggerIdentifier)
            }
            for actionSetIdentifier in createdActionSets {
                try? await homeKitController.deleteActionSet(homeIdentifier: homeIdentifier, identifier: actionSetIdentifier)
            }

            try? await alarmRepository.updateValidationState(
                for: alarm.id,
                state: .outOfSync,
                message: error.localizedDescription,
                requiresUserAction: true
            )
            throw error
        }
    }

    func removeAutomations(for alarm: WakeAlarm, markDisabled: Bool = false) async throws {
        let context = ModelContext(modelContainer)
        let bindings = try fetchBindings(for: alarm.id, in: context)
        let homeIdentifier = alarm.homeIdentifier

        if let homeIdentifier {
            let triggerIdentifiers = Set(bindings.compactMap(\.triggerIdentifier))
            let actionSetIdentifiers = Set(bindings.compactMap(\.actionSetIdentifier))

            for triggerIdentifier in triggerIdentifiers {
                try? await homeKitController.deleteTimerTrigger(homeIdentifier: homeIdentifier, identifier: triggerIdentifier)
            }

            for actionSetIdentifier in actionSetIdentifiers {
                try? await homeKitController.deleteActionSet(homeIdentifier: homeIdentifier, identifier: actionSetIdentifier)
            }
        }

        bindings.forEach(context.delete)
        try context.save()

        if markDisabled {
            try await alarmRepository.updateValidationState(
                for: alarm.id,
                state: .valid,
                message: "Alarm saved and disabled.",
                requiresUserAction: false
            )
        }
    }

    func expectedBindings(
        for alarm: WakeAlarm,
        schedule: WeekdaySchedule?,
        accessories: [AccessorySnapshot]
    ) -> [ExpectedAutomationBinding] {
        let schedule = schedule ?? .never
        let weekdayNumbers: [Int?] = schedule.isRepeating ? schedule.weekdayNumbers.map(Optional.some) : [nil]
        let capabilities = accessories.map(\.capability)
        var bindings: [ExpectedAutomationBinding] = []

        for weekday in weekdayNumbers {
            guard let wakeDate = nextWakeDate(
                for: alarm,
                schedule: schedule,
                weekday: weekday
            ) else {
                continue
            }

            let planned = WakeAlarmStepPlanner.planSteps(
                wakeTime: wakeDate,
                durationMinutes: alarm.durationMinutes,
                curve: alarm.gradientCurve,
                startBrightness: alarm.startBrightness,
                targetBrightness: alarm.targetBrightness,
                targetColorTemperature: alarm.targetColorTemperature,
                targetHue: alarm.targetHue,
                targetSaturation: alarm.targetSaturation,
                stepCount: WakeAlarmStepPlanner.defaultStepCount
            )

            for (stepNumber, step) in planned.enumerated() {
                bindings.append(
                    ExpectedAutomationBinding(
                        alarmID: alarm.id,
                        stepNumber: stepNumber,
                        weekday: weekday,
                        fireDate: step.timestamp.roundedToMinute(),
                        recurrence: schedule.isRepeating ? DateComponents(weekOfYear: 1) : nil,
                        step: WakeAlarmStepPlanner.planSteps(
                            for: alarm,
                            capabilities: capabilities,
                            stepCount: WakeAlarmStepPlanner.defaultStepCount
                        ).steps[stepNumber],
                        actionRequests: actionRequests(
                            for: stepNumber,
                            alarm: alarm,
                            accessories: accessories,
                            capabilities: capabilities
                        )
                    )
                )
            }
        }

        return bindings
    }

    private func actionRequests(
        for stepNumber: Int,
        alarm: WakeAlarm,
        accessories: [AccessorySnapshot],
        capabilities: [AccessoryCapability]
    ) -> [HomeKitActionRequest] {
        let degradedPlan = WakeAlarmStepPlanner.planSteps(
            for: alarm,
            capabilities: capabilities,
            stepCount: WakeAlarmStepPlanner.defaultStepCount
        )
        let step = degradedPlan.steps[stepNumber]

        return accessories.flatMap { accessory -> [HomeKitActionRequest] in
            var requests: [HomeKitActionRequest] = [
                HomeKitActionRequest(
                    accessoryIdentifier: accessory.id,
                    characteristicType: HMCharacteristicTypePowerState,
                    value: .bool(true)
                ),
                HomeKitActionRequest(
                    accessoryIdentifier: accessory.id,
                    characteristicType: HMCharacteristicTypeBrightness,
                    value: .int(step.brightness)
                ),
            ]

            if accessory.capability.supportsColorTemperature, let colorTemperature = step.colorTemperature {
                requests.append(
                    HomeKitActionRequest(
                        accessoryIdentifier: accessory.id,
                        characteristicType: HMCharacteristicTypeColorTemperature,
                        value: .int(colorTemperature)
                    )
                )
            }

            if accessory.capability.supportsHueSaturation,
               let hue = step.hue,
               let saturation = step.saturation {
                requests.append(
                    HomeKitActionRequest(
                        accessoryIdentifier: accessory.id,
                        characteristicType: HMCharacteristicTypeHue,
                        value: .double(Double(hue))
                    )
                )
                requests.append(
                    HomeKitActionRequest(
                        accessoryIdentifier: accessory.id,
                        characteristicType: HMCharacteristicTypeSaturation,
                        value: .double(Double(saturation))
                    )
                )
            }

            return requests
        }
    }

    private func fetchBindings(for alarmID: UUID, in context: ModelContext) throws -> [AutomationBinding] {
        var descriptor = FetchDescriptor<AutomationBinding>()
        descriptor.predicate = #Predicate { $0.alarmId == alarmID }
        descriptor.sortBy = [SortDescriptor(\.stepNumber), SortDescriptor(\.weekday)]
        return try context.fetch(descriptor)
    }

    private func deleteBindings(
        _ bindings: [AutomationBinding],
        homeIdentifier: String,
        activeStepNumbers: Set<Int>,
        in context: ModelContext
    ) async throws {
        let triggerIdentifiers = Set(bindings.compactMap(\.triggerIdentifier))
        let actionSetIdentifiers = Set<String>(
            bindings.compactMap { binding in
                guard !activeStepNumbers.contains(binding.stepNumber) else {
                    return nil
                }
                return binding.actionSetIdentifier
            }
        )

        for triggerIdentifier in triggerIdentifiers {
            try? await homeKitController.deleteTimerTrigger(homeIdentifier: homeIdentifier, identifier: triggerIdentifier)
        }

        for actionSetIdentifier in actionSetIdentifiers {
            try? await homeKitController.deleteActionSet(homeIdentifier: homeIdentifier, identifier: actionSetIdentifier)
        }

        bindings.forEach(context.delete)
    }

    private func nextWakeDate(
        for alarm: WakeAlarm,
        schedule: WeekdaySchedule,
        weekday: Int?
    ) -> Date? {
        let record = WakeAlarmSchedule(alarmId: alarm.id, weekdaySchedule: schedule)
        return record.nextOccurrence(
            wakeTimeSeconds: alarm.wakeTimeSeconds,
            restrictedToWeekday: weekday
        )
    }

    private func selectedAccessories(for alarm: WakeAlarm, in homeIdentifier: String) async -> [AccessorySnapshot] {
        let allAccessories = await homeKitController.accessories(in: homeIdentifier)
        let selectedIDs = Set(alarm.selectedAccessoryIdentifiers)
        return allAccessories.filter { selectedIDs.contains($0.id) && $0.capability.supportsBrightness }
    }

    private func namespacedActionSetName(for alarmID: UUID, stepNumber: Int) -> String {
        "DawnLoop.\(alarmID.uuidString).step.\(stepNumber).scene"
    }

    private func namespacedTriggerName(for alarmID: UUID, stepNumber: Int, weekday: Int?) -> String {
        if let weekday {
            return "DawnLoop.\(alarmID.uuidString).step.\(stepNumber).weekday.\(weekday).trigger"
        }
        return "DawnLoop.\(alarmID.uuidString).step.\(stepNumber).trigger"
    }
}

struct BindingKey: Hashable {
    let stepNumber: Int
    let weekday: Int?

    init(stepNumber: Int, weekday: Int?) {
        self.stepNumber = stepNumber
        self.weekday = weekday
    }

    init(binding: AutomationBinding) {
        self.stepNumber = binding.stepNumber
        self.weekday = binding.weekday
    }
}

struct ExpectedAutomationBinding {
    let alarmID: UUID
    let stepNumber: Int
    let weekday: Int?
    let fireDate: Date
    let recurrence: DateComponents?
    let step: WakeAlarmStep
    let actionRequests: [HomeKitActionRequest]

    var bindingKey: BindingKey {
        BindingKey(stepNumber: stepNumber, weekday: weekday)
    }
}

enum AutomationGenerationError: LocalizedError {
    case homeUnavailable
    case noAccessories
    case noUpcomingRun

    var errorDescription: String? {
        switch self {
        case .homeUnavailable:
            return "The selected Apple Home is unavailable."
        case .noAccessories:
            return "No compatible lights are selected for this alarm."
        case .noUpcomingRun:
            return "DawnLoop could not calculate the next run time."
        }
    }
}

private extension Date {
    func roundedToMinute(calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: self)
        return calendar.date(from: components) ?? self
    }
}

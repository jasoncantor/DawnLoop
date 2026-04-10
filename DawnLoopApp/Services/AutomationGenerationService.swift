import Foundation
import SwiftData
import HomeKit

struct AutomationSyncProgress: Sendable {
    let completedUnits: Int
    let totalUnits: Int
    let message: String

    var fractionCompleted: Double {
        guard totalUnits > 0 else { return 1 }
        return min(max(Double(completedUnits) / Double(totalUnits), 0), 1)
    }
}

struct DawnLoopHomeKitResetSummary: Sendable {
    let homesVisited: Int
    let triggersRemoved: Int
    let actionSetsRemoved: Int
    let bindingsCleared: Int
}

private struct StepScenePlan {
    let stepNumber: Int
    let actionRequests: [HomeKitActionRequest]
}

private enum DawnLoopHomeKitNamespace {
    static let currentPrefix = "zzzz DawnLoop."
    static let legacyPrefixes = ["DawnLoop."]
    static let allPrefixes = [currentPrefix] + legacyPrefixes
}

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

    func syncAlarm(
        _ alarm: WakeAlarm,
        schedule: WeekdaySchedule?,
        progress: ((AutomationSyncProgress) -> Void)? = nil
    ) async throws {
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
                message: "DawnLoop could not calculate the next alarm run time.",
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

        let scenePlans = scenePlans(for: alarm, accessories: accessories)
        let existingBindingsByKey = Dictionary(
            uniqueKeysWithValues: existingBindings.map { (BindingKey(binding: $0), $0) }
        )

        var createdTriggers: [String] = []
        var createdActionSets: [String] = []
        let totalUnits = max(scenePlans.count + expectedBindings.count + 2, 1)
        var completedUnits = 0

        func reportProgress(_ message: String) {
            progress?(AutomationSyncProgress(
                completedUnits: completedUnits,
                totalUnits: totalUnits,
                message: message
            ))
        }

        reportProgress("Preparing HomeKit automations")

        do {
            for scenePlan in scenePlans {
                let existingBinding = existingBindings.first { $0.stepNumber == scenePlan.stepNumber }
                let actionSetIdentifier = actionSetByStep[scenePlan.stepNumber] ?? existingBinding?.actionSetIdentifier
                let actionSetResult = try await homeKitController.upsertActionSet(
                    homeIdentifier: homeIdentifier,
                    identifier: actionSetIdentifier,
                    name: namespacedActionSetName(for: alarm.id, stepNumber: scenePlan.stepNumber),
                    requests: scenePlan.actionRequests
                )
                actionSetByStep[scenePlan.stepNumber] = actionSetResult.identifier
                if actionSetResult.created {
                    createdActionSets.append(actionSetResult.identifier)
                }
                completedUnits += 1
                reportProgress("Configuring light scenes")
            }

            for expected in expectedBindings {
                let existingBinding = existingBindingsByKey[expected.bindingKey]
                guard let actionSetIdentifier = actionSetByStep[expected.stepNumber] else {
                    throw HomeKitControllerError.actionSetNotFound(namespacedActionSetName(for: alarm.id, stepNumber: expected.stepNumber))
                }

                let triggerResult = try await homeKitController.upsertScheduledTrigger(
                    homeIdentifier: homeIdentifier,
                    identifier: existingBinding?.triggerIdentifier,
                    name: namespacedTriggerName(
                        for: alarm.id,
                        stepNumber: expected.stepNumber,
                        weekday: expected.weekday
                    ),
                    schedule: expected.triggerSchedule,
                    actionSetIdentifier: actionSetIdentifier,
                    requiredOnAccessoryIdentifiers: accessories.map(\.id),
                    isEnabled: true
                )
                if triggerResult.created {
                    createdTriggers.append(triggerResult.identifier)
                }
                completedUnits += 1
                reportProgress("Scheduling alarm triggers")

                let binding = existingBinding ?? AutomationBinding(
                    alarmId: alarm.id,
                    stepNumber: expected.stepNumber,
                    weekday: expected.weekday
                )
                if existingBinding == nil {
                    context.insert(binding)
                }

                binding.weekday = expected.weekday
                binding.actionSetIdentifier = actionSetIdentifier
                binding.triggerIdentifier = triggerResult.identifier
                binding.scheduledTime = expected.scheduledTime
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
            completedUnits += 1
            reportProgress("Cleaning up old automations")

            try context.save()
            try await alarmRepository.updateValidationState(
                for: alarm.id,
                state: .valid,
                message: "Home automation is synced.",
                requiresUserAction: false
            )
            completedUnits += 1
            reportProgress("Finishing up")
        } catch {
            for triggerIdentifier in createdTriggers {
                try? await homeKitController.deleteTrigger(homeIdentifier: homeIdentifier, identifier: triggerIdentifier)
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
                try? await homeKitController.deleteTrigger(homeIdentifier: homeIdentifier, identifier: triggerIdentifier)
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

    func resetDawnLoopArtifacts() async throws -> DawnLoopHomeKitResetSummary {
        var homesVisited = 0
        var triggersRemoved = 0
        var actionSetsRemoved = 0

        for prefix in DawnLoopHomeKitNamespace.allPrefixes {
            let cleanup = await homeKitController.removeObjects(prefixedBy: prefix)
            homesVisited = max(homesVisited, cleanup.homesVisited)
            triggersRemoved += cleanup.triggersRemoved
            actionSetsRemoved += cleanup.actionSetsRemoved
        }

        let context = ModelContext(modelContainer)
        let bindings = try context.fetch(FetchDescriptor<AutomationBinding>())
        let alarms = await alarmRepository.fetchAllAlarms()

        bindings.forEach(context.delete)
        try context.save()

        for alarm in alarms {
            if alarm.isEnabled {
                try? await alarmRepository.updateValidationState(
                    for: alarm.id,
                    state: .needsSync,
                    message: "HomeKit automations were reset. Repair or re-enable this alarm to recreate them.",
                    requiresUserAction: true
                )
            } else {
                try? await alarmRepository.updateValidationState(
                    for: alarm.id,
                    state: .valid,
                    message: "Alarm is disabled.",
                    requiresUserAction: false
                )
            }
        }

        return DawnLoopHomeKitResetSummary(
            homesVisited: homesVisited,
            triggersRemoved: triggersRemoved,
            actionSetsRemoved: actionSetsRemoved,
            bindingsCleared: bindings.count
        )
    }

    func expectedBindings(
        for alarm: WakeAlarm,
        schedule: WeekdaySchedule?,
        accessories: [AccessorySnapshot]
    ) -> [ExpectedAutomationBinding] {
        let schedule = schedule ?? .never
        let weekdayNumbers: [Int?] = schedule.isRepeating ? schedule.weekdayNumbers.map(Optional.some) : [nil]
        let capabilities = accessories.map(\.capability)
        let degradedPlan = WakeAlarmStepPlanner.planSteps(
            for: alarm,
            capabilities: capabilities,
            stepCount: WakeAlarmStepPlanner.defaultStepCount
        )
        let planningWakeDate = alarm.wakeTimeDate()
        var bindings: [ExpectedAutomationBinding] = []

        for weekday in weekdayNumbers {
            let resolvedWakeDate = if alarm.timeReference == .clock {
                nextWakeDate(
                    for: alarm,
                    schedule: schedule,
                    weekday: weekday
                )
            } else {
                planningWakeDate
            }

            guard let resolvedWakeDate else {
                continue
            }

            let planned = WakeAlarmStepPlanner.planSteps(
                wakeTime: resolvedWakeDate,
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
                let roundedStepDate = step.timestamp.roundedToMinute()
                let relativeOffsetMinutes = Int(roundedStepDate.timeIntervalSince(resolvedWakeDate.roundedToMinute()) / 60)
                guard let triggerSchedule = triggerSchedule(
                    for: alarm,
                    weekday: weekday,
                    scheduledTime: roundedStepDate,
                    relativeOffsetMinutes: relativeOffsetMinutes
                ) else {
                    continue
                }
                bindings.append(
                    ExpectedAutomationBinding(
                        alarmID: alarm.id,
                        stepNumber: stepNumber,
                        weekday: weekday,
                        scheduledTime: alarm.timeReference == .clock
                            ? roundedStepDate
                            : nil,
                        triggerSchedule: triggerSchedule,
                        step: degradedPlan.steps[stepNumber],
                        actionRequests: []
                    )
                )
            }
        }

        return bindings
    }

    private func scenePlans(
        for alarm: WakeAlarm,
        accessories: [AccessorySnapshot]
    ) -> [StepScenePlan] {
        let capabilities = accessories.map(\.capability)
        let degradedPlan = WakeAlarmStepPlanner.planSteps(
            for: alarm,
            capabilities: capabilities,
            stepCount: WakeAlarmStepPlanner.defaultStepCount
        )

        return degradedPlan.steps.enumerated().map { stepNumber, step in
            StepScenePlan(
                stepNumber: stepNumber,
                actionRequests: actionRequests(
                    for: step,
                    accessories: accessories
                )
            )
        }
    }

    private func actionRequests(
        for step: WakeAlarmStep,
        accessories: [AccessorySnapshot]
    ) -> [HomeKitActionRequest] {
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
            try? await homeKitController.deleteTrigger(homeIdentifier: homeIdentifier, identifier: triggerIdentifier)
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
        return record.nextOccurrence(after: Date(), alarm: alarm, coordinate: nil, restrictedToWeekday: weekday)
    }

    private func triggerSchedule(
        for alarm: WakeAlarm,
        weekday: Int?,
        scheduledTime: Date,
        relativeOffsetMinutes: Int
    ) -> HomeKitTriggerSchedule? {
        switch alarm.timeReference {
        case .clock:
            return .calendar(fireDate: scheduledTime, weekday: weekday)
        case .sunrise, .sunset:
            return .significant(
                reference: alarm.timeReference,
                offsetMinutes: alarm.timeOffsetMinutes + relativeOffsetMinutes,
                weekday: weekday
            )
        }
    }

    private func selectedAccessories(for alarm: WakeAlarm, in homeIdentifier: String) async -> [AccessorySnapshot] {
        let allAccessories = await homeKitController.accessories(in: homeIdentifier)
        let selectedIDs = Set(alarm.selectedAccessoryIdentifiers)
        return allAccessories.filter { selectedIDs.contains($0.id) && $0.capability.supportsBrightness }
    }

    private func namespacedActionSetName(for alarmID: UUID, stepNumber: Int) -> String {
        "\(DawnLoopHomeKitNamespace.currentPrefix)\(alarmID.uuidString).step.\(stepNumber).scene"
    }

    private func namespacedTriggerName(for alarmID: UUID, stepNumber: Int, weekday: Int?) -> String {
        if let weekday {
            return "\(DawnLoopHomeKitNamespace.currentPrefix)\(alarmID.uuidString).step.\(stepNumber).weekday.\(weekday).trigger"
        }
        return "\(DawnLoopHomeKitNamespace.currentPrefix)\(alarmID.uuidString).step.\(stepNumber).trigger"
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
    let scheduledTime: Date?
    let triggerSchedule: HomeKitTriggerSchedule
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

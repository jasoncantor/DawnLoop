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

        // Only build scenes for steps that will actually get a trigger - creating a
        // scene for a skipped step would orphan a named HomeKit object that collides
        // with the next sync's create-by-name.
        let expectedStepNumbers = Set(expectedBindings.map(\.stepNumber))
        let scenePlans = scenePlans(for: alarm, accessories: accessories)
            .filter { expectedStepNumbers.contains($0.stepNumber) }
        let existingBindingsByKey = Dictionary(
            uniqueKeysWithValues: existingBindings.map { (BindingKey(binding: $0), $0) }
        )
        DawnLoopLogger.automation.info(
            "Scheduled run sync started for alarm \(alarm.id.uuidString, privacy: .public); steps=\(scenePlans.count, privacy: .public); bindings=\(expectedBindings.count, privacy: .public)"
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
                    requiredOnAccessoryIdentifiers: [],
                    isEnabled: true
                )
                if expected.stepNumber == 0 {
                    DawnLoopLogger.automation.info(
                        "First wake step configured as authoritative command for alarm \(alarm.id.uuidString, privacy: .public); brightness=\(expected.step.brightness, privacy: .public)"
                    )
                }
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
            let staleLeftovers = try await deleteBindings(
                staleBindings,
                homeIdentifier: homeIdentifier,
                activeStepNumbers: expectedStepNumbers,
                in: context
            )
            completedUnits += 1
            reportProgress("Cleaning up old automations")

            try context.save()
            if staleLeftovers > 0 {
                // The new automations are armed, but outdated HomeKit objects survived
                // their delete attempt - report it honestly so validation and the
                // repair flow agree instead of flip-flopping valid/outOfSync.
                try await alarmRepository.updateValidationState(
                    for: alarm.id,
                    state: .outOfSync,
                    message: "Alarm is armed, but some outdated HomeKit automations could not be removed yet. Repair to retry.",
                    requiresUserAction: true
                )
            } else {
                try await alarmRepository.updateValidationState(
                    for: alarm.id,
                    state: .valid,
                    message: "Home automation is synced.",
                    requiresUserAction: false
                )
            }
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

        var failedTriggerIdentifiers: Set<String> = []
        var failedActionSetIdentifiers: Set<String> = []

        if let homeIdentifier {
            for triggerIdentifier in Set(bindings.compactMap(\.triggerIdentifier)) {
                do {
                    try await homeKitController.deleteTrigger(homeIdentifier: homeIdentifier, identifier: triggerIdentifier)
                } catch {
                    failedTriggerIdentifiers.insert(triggerIdentifier)
                    DawnLoopLogger.homeKit.error("Failed to delete trigger \(triggerIdentifier): \(error.localizedDescription)")
                }
            }

            for actionSetIdentifier in Set(bindings.compactMap(\.actionSetIdentifier)) {
                do {
                    try await homeKitController.deleteActionSet(homeIdentifier: homeIdentifier, identifier: actionSetIdentifier)
                } catch {
                    failedActionSetIdentifiers.insert(actionSetIdentifier)
                    DawnLoopLogger.homeKit.error("Failed to delete action set \(actionSetIdentifier): \(error.localizedDescription)")
                }
            }
        }

        // Keep bindings whose HomeKit objects survived the delete attempt; they are the
        // only record of those trigger identifiers, and wiping them would leave the
        // automations firing forever with no way to clean them up later.
        let removableBindings = bindings.filter { binding in
            let triggerFailed = binding.triggerIdentifier.map(failedTriggerIdentifiers.contains) ?? false
            let actionSetFailed = binding.actionSetIdentifier.map(failedActionSetIdentifiers.contains) ?? false
            return !triggerFailed && !actionSetFailed
        }
        removableBindings.forEach(context.delete)
        try context.save()

        if !failedTriggerIdentifiers.isEmpty || !failedActionSetIdentifiers.isEmpty {
            throw AutomationGenerationError.cleanupIncomplete
        }

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
        accessories: [AccessorySnapshot],
        now: Date = Date()
    ) -> [ExpectedAutomationBinding] {
        let schedule = schedule ?? .never
        let capabilities = accessories.map(\.capability)
        let degradedPlan = WakeAlarmStepPlanner.planSteps(
            for: alarm,
            capabilities: capabilities,
            stepCount: alarm.stepCount
        )

        // One binding (and HomeKit trigger) per step. Repeating schedules carry the full
        // weekday set on each trigger's recurrence instead of duplicating triggers per day.
        let resolvedWakeDate: Date?
        if alarm.timeReference == .clock {
            resolvedWakeDate = nextWakeDate(for: alarm, schedule: schedule, weekday: nil, after: now)
        } else {
            resolvedWakeDate = alarm.wakeTimeDate()
        }

        guard let resolvedWakeDate else {
            return []
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
            stepCount: alarm.stepCount
        )

        let calendar = Calendar.current
        let roundedWakeDate = resolvedWakeDate.roundedToMinute()
        var bindings: [ExpectedAutomationBinding] = []

        for (stepNumber, step) in planned.enumerated() {
            let roundedStepDate = step.timestamp.roundedToMinute()
            let relativeOffsetMinutes = Int(roundedStepDate.timeIntervalSince(roundedWakeDate) / 60)

            // A one-shot calendar trigger whose fire time already passed would next match
            // its month/day components a year out, so drop steps that are already behind us.
            if alarm.timeReference == .clock, !schedule.isRepeating, roundedStepDate <= now {
                continue
            }

            let weekdays = recurrenceWeekdays(
                for: alarm,
                schedule: schedule,
                stepDate: roundedStepDate,
                wakeDate: roundedWakeDate,
                calendar: calendar
            )

            bindings.append(
                ExpectedAutomationBinding(
                    alarmID: alarm.id,
                    stepNumber: stepNumber,
                    weekday: nil,
                    scheduledTime: alarm.timeReference == .clock
                        ? roundedStepDate
                        : nil,
                    triggerSchedule: triggerSchedule(
                        for: alarm,
                        weekdays: weekdays,
                        scheduledTime: roundedStepDate,
                        relativeOffsetMinutes: relativeOffsetMinutes
                    ),
                    step: degradedPlan.steps[stepNumber],
                    actionRequests: []
                )
            )
        }

        return bindings
    }

    /// Recurrence weekdays for a step's trigger. Ramp steps that land on the calendar day
    /// before the wake target (a just-after-midnight alarm) must fire on the *previous*
    /// weekday, otherwise HomeKit runs them almost a day late.
    private func recurrenceWeekdays(
        for alarm: WakeAlarm,
        schedule: WeekdaySchedule,
        stepDate: Date,
        wakeDate: Date,
        calendar: Calendar
    ) -> [Int]? {
        guard schedule.isRepeating else {
            return nil
        }

        guard alarm.timeReference == .clock else {
            // Solar triggers fire relative to the event on each recurrence day,
            // so their weekdays are used as configured.
            return schedule.weekdayNumbers
        }

        let dayShift = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: stepDate),
            to: calendar.startOfDay(for: wakeDate)
        ).day ?? 0

        guard dayShift > 0 else {
            return schedule.weekdayNumbers
        }

        return schedule.weekdayNumbers.map { weekday in
            (weekday - 1 - dayShift + 14) % 7 + 1
        }
    }

    private func scenePlans(
        for alarm: WakeAlarm,
        accessories: [AccessorySnapshot]
    ) -> [StepScenePlan] {
        let capabilities = accessories.map(\.capability)
        let degradedPlan = WakeAlarmStepPlanner.planSteps(
            for: alarm,
            capabilities: capabilities,
            stepCount: alarm.stepCount
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

            // Prefer hue/saturation on lights that support it; writing color temperature
            // in the same scene would fight the color write on full-color bulbs.
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
            } else if accessory.capability.supportsColorTemperature, let colorTemperature = step.colorTemperature {
                requests.append(
                    HomeKitActionRequest(
                        accessoryIdentifier: accessory.id,
                        characteristicType: HMCharacteristicTypeColorTemperature,
                        value: .int(colorTemperature)
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

    /// Deletes stale bindings and their HomeKit objects. Returns the number of
    /// bindings kept because their HomeKit objects could not be removed.
    @discardableResult
    private func deleteBindings(
        _ bindings: [AutomationBinding],
        homeIdentifier: String,
        activeStepNumbers: Set<Int>,
        in context: ModelContext
    ) async throws -> Int {
        var failedTriggerIdentifiers: Set<String> = []
        var failedActionSetIdentifiers: Set<String> = []

        let actionSetIdentifiers = Set<String>(
            bindings.compactMap { binding in
                guard !activeStepNumbers.contains(binding.stepNumber) else {
                    return nil
                }
                return binding.actionSetIdentifier
            }
        )

        for triggerIdentifier in Set(bindings.compactMap(\.triggerIdentifier)) {
            do {
                try await homeKitController.deleteTrigger(homeIdentifier: homeIdentifier, identifier: triggerIdentifier)
            } catch {
                failedTriggerIdentifiers.insert(triggerIdentifier)
                DawnLoopLogger.homeKit.error("Failed to delete stale trigger \(triggerIdentifier): \(error.localizedDescription)")
            }
        }

        for actionSetIdentifier in actionSetIdentifiers {
            do {
                try await homeKitController.deleteActionSet(homeIdentifier: homeIdentifier, identifier: actionSetIdentifier)
            } catch {
                failedActionSetIdentifiers.insert(actionSetIdentifier)
                DawnLoopLogger.homeKit.error("Failed to delete stale action set \(actionSetIdentifier): \(error.localizedDescription)")
            }
        }

        // Bindings with surviving HomeKit objects stay in the store so the next
        // sync or repair can retry their deletion instead of orphaning them.
        let removableBindings = bindings.filter { binding in
            let triggerFailed = binding.triggerIdentifier.map(failedTriggerIdentifiers.contains) ?? false
            let actionSetFailed = binding.actionSetIdentifier.map(failedActionSetIdentifiers.contains) ?? false
            return !triggerFailed && !actionSetFailed
        }
        removableBindings.forEach(context.delete)
        return bindings.count - removableBindings.count
    }

    private func nextWakeDate(
        for alarm: WakeAlarm,
        schedule: WeekdaySchedule,
        weekday: Int?,
        after date: Date = Date()
    ) -> Date? {
        let record = WakeAlarmSchedule(alarmId: alarm.id, weekdaySchedule: schedule)
        return record.nextOccurrence(after: date, alarm: alarm, coordinate: nil, restrictedToWeekday: weekday)
    }

    private func triggerSchedule(
        for alarm: WakeAlarm,
        weekdays: [Int]?,
        scheduledTime: Date,
        relativeOffsetMinutes: Int
    ) -> HomeKitTriggerSchedule {
        switch alarm.timeReference {
        case .clock:
            return .calendar(fireDate: scheduledTime, weekdays: weekdays)
        case .sunrise, .sunset:
            return .significant(
                reference: alarm.timeReference,
                offsetMinutes: alarm.timeOffsetMinutes + relativeOffsetMinutes,
                weekdays: weekdays
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
    case cleanupIncomplete

    var errorDescription: String? {
        switch self {
        case .homeUnavailable:
            return "The selected Apple Home is unavailable."
        case .noAccessories:
            return "No compatible lights are selected for this alarm."
        case .noUpcomingRun:
            return "DawnLoop could not calculate the next run time."
        case .cleanupIncomplete:
            return "Some HomeKit automations could not be removed. They will be retried on the next sync, or you can use Nuke HomeKit."
        }
    }
}

private extension Date {
    /// Rounds to the nearest whole minute so trigger times stay as close as possible
    /// to the canonical step plan instead of always firing early.
    func roundedToMinute(calendar: Calendar = .current) -> Date {
        let reference = addingTimeInterval(30)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reference)
        return calendar.date(from: components) ?? self
    }
}

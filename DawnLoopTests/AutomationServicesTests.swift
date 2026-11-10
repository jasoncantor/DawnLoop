import XCTest
import HomeKit
import SwiftData
@testable import DawnLoop

@MainActor
final class AutomationServicesTests: XCTestCase {
    var modelContainer: ModelContainer!
    var repository: WakeAlarmRepository!
    var controller: MockHomeKitController!
    var generationService: AutomationGenerationService!
    var repairService: AutomationRepairService!

    override func setUp() async throws {
        let schema = Schema([
            WakeAlarm.self,
            WakeAlarmSchedule.self,
            ValidationStateRecord.self,
            AutomationBinding.self,
            HomeReference.self,
            AccessoryReference.self,
            OnboardingCompletion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try? ModelContainer(for: schema, configurations: [configuration])
        repository = WakeAlarmRepository(modelContainer: modelContainer)
        controller = MockHomeKitController.seededTestHome()
        generationService = AutomationGenerationService(
            homeKitController: controller,
            modelContainer: modelContainer,
            alarmRepository: repository
        )
        repairService = AutomationRepairService(
            homeKitController: controller,
            modelContainer: modelContainer,
            alarmRepository: repository,
            generationService: generationService
        )
    }

    override func tearDown() async throws {
        modelContainer = nil
        repository = nil
        controller = nil
        generationService = nil
        repairService = nil
    }

    func testSyncAlarm_CreatesBindingsAndHomeKitObjects() async throws {
        let alarm = WakeAlarm(
            name: "Wake Up",
            wakeTimeSeconds: 7 * 3600,
            durationMinutes: 30,
            gradientCurve: .easeInOut,
            colorMode: .brightnessOnly,
            startBrightness: 0,
            targetBrightness: 100,
            isEnabled: true,
            selectedAccessoryIdentifiers: ["test-accessory-living-room-001"],
            homeIdentifier: "test-home-uuid-001"
        )
        try await repository.saveAlarm(alarm, schedule: .weekdays, validationState: .needsSync)

        try await generationService.syncAlarm(alarm, schedule: .weekdays)

        let bindings = await AutomationBindingService(modelContainer: modelContainer).bindingsForAlarm(alarm.id)
        XCTAssertFalse(bindings.isEmpty)
        XCTAssertFalse(controller.storedActionSets(for: "test-home-uuid-001").isEmpty)
        XCTAssertFalse(controller.storedTriggers(for: "test-home-uuid-001").isEmpty)
    }

    func testRemoveAutomations_CleansBindings() async throws {
        let alarm = WakeAlarm(
            name: "Disable Me",
            wakeTimeSeconds: 7 * 3600,
            durationMinutes: 30,
            gradientCurve: .easeInOut,
            colorMode: .brightnessOnly,
            startBrightness: 0,
            targetBrightness: 100,
            isEnabled: true,
            selectedAccessoryIdentifiers: ["test-accessory-living-room-001"],
            homeIdentifier: "test-home-uuid-001"
        )
        try await repository.saveAlarm(alarm, schedule: .weekdays, validationState: .needsSync)
        try await generationService.syncAlarm(alarm, schedule: .weekdays)

        try await generationService.removeAutomations(for: alarm, markDisabled: true)

        let bindings = await AutomationBindingService(modelContainer: modelContainer).bindingsForAlarm(alarm.id)
        XCTAssertTrue(bindings.isEmpty)
    }

    func testRepairAlarm_FixesMissingTrigger() async throws {
        let alarm = WakeAlarm(
            name: "Repair Me",
            wakeTimeSeconds: 7 * 3600,
            durationMinutes: 30,
            gradientCurve: .easeInOut,
            colorMode: .brightnessOnly,
            startBrightness: 0,
            targetBrightness: 100,
            isEnabled: true,
            selectedAccessoryIdentifiers: ["test-accessory-living-room-001"],
            homeIdentifier: "test-home-uuid-001"
        )
        try await repository.saveAlarm(alarm, schedule: .weekdays, validationState: .needsSync)
        try await generationService.syncAlarm(alarm, schedule: .weekdays)

        let homeID = "test-home-uuid-001"
        let triggerID = try XCTUnwrap(controller.storedTriggers(for: homeID).first?.identifier)
        try await controller.deleteTrigger(homeIdentifier: homeID, identifier: triggerID)

        let preRepair = await repairService.validateAlarm(alarm, schedule: .weekdays)
        XCTAssertEqual(preRepair.state, .outOfSync)

        let repaired = try await repairService.repairAlarm(alarm, schedule: .weekdays)
        XCTAssertEqual(repaired.state, .valid)
    }

    func testValidateAlarm_MissingScheduledTimeCountsAsDrift() async throws {
        let alarm = WakeAlarm(
            name: "Missing Scheduled Time",
            wakeTimeSeconds: 7 * 3600,
            durationMinutes: 30,
            gradientCurve: .easeInOut,
            colorMode: .brightnessOnly,
            startBrightness: 0,
            targetBrightness: 100,
            isEnabled: true,
            selectedAccessoryIdentifiers: ["test-accessory-living-room-001"],
            homeIdentifier: "test-home-uuid-001"
        )
        try await repository.saveAlarm(alarm, schedule: .never, validationState: .needsSync)
        try await generationService.syncAlarm(alarm, schedule: .never)

        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<AutomationBinding>()
        let alarmID = alarm.id
        descriptor.predicate = #Predicate { $0.alarmId == alarmID }
        let bindings = try context.fetch(descriptor)
        let binding = try XCTUnwrap(bindings.first)
        binding.scheduledTime = nil
        try context.save()

        let summary = await repairService.validateAlarm(alarm, schedule: .never)

        XCTAssertEqual(summary.state, .outOfSync)
        XCTAssertEqual(summary.message, "The next HomeKit run time drifted and needs repair.")
        XCTAssertTrue(summary.requiresUserAction)
    }

    func testSyncAlarm_ReusesScenesAcrossRepeatingDays() async throws {
        let alarm = WakeAlarm(
            name: "Weekday Light Alarm",
            wakeTimeSeconds: 7 * 3600,
            durationMinutes: 30,
            gradientCurve: .easeInOut,
            colorMode: .brightnessOnly,
            startBrightness: 0,
            targetBrightness: 100,
            isEnabled: true,
            selectedAccessoryIdentifiers: ["test-accessory-living-room-001"],
            homeIdentifier: "test-home-uuid-001"
        )
        try await repository.saveAlarm(alarm, schedule: .weekdays, validationState: .needsSync)

        try await generationService.syncAlarm(alarm, schedule: .weekdays)

        XCTAssertEqual(controller.upsertActionSetCallCount, WakeAlarmStepPlanner.defaultStepCount)
        // One trigger per step; the repeat days ride on each trigger's recurrence set.
        XCTAssertEqual(controller.upsertScheduledTriggerCallCount, WakeAlarmStepPlanner.defaultStepCount)

        let triggers = controller.storedTriggers(for: "test-home-uuid-001")
        XCTAssertEqual(triggers.count, WakeAlarmStepPlanner.defaultStepCount)
        XCTAssertTrue(
            triggers.allSatisfy {
                Set($0.schedule.recurrenceWeekdays ?? []) == Set(WeekdaySchedule.weekdays.weekdayNumbers)
            }
        )
    }

    func testSyncAlarm_RampCrossingMidnight_ShiftsRecurrenceWeekdaysBack() async throws {
        // Wake at 00:05 on weekdays with a 30-minute ramp: most steps fire the
        // evening before, so their recurrences must run on the previous weekdays.
        let alarm = WakeAlarm(
            name: "Just After Midnight",
            wakeTimeSeconds: 5 * 60,
            durationMinutes: 30,
            gradientCurve: .linear,
            colorMode: .brightnessOnly,
            startBrightness: 0,
            targetBrightness: 100,
            isEnabled: true,
            selectedAccessoryIdentifiers: ["test-accessory-living-room-001"],
            homeIdentifier: "test-home-uuid-001"
        )
        let accessories = await controller.accessories(in: "test-home-uuid-001")
            .filter { $0.id == "test-accessory-living-room-001" }

        let bindings = generationService.expectedBindings(
            for: alarm,
            schedule: .weekdays,
            accessories: accessories
        )
        XCTAssertEqual(bindings.count, WakeAlarmStepPlanner.defaultStepCount)

        let configuredWeekdays = Set(WeekdaySchedule.weekdays.weekdayNumbers) // Mon-Fri
        let shiftedWeekdays = Set([1, 2, 3, 4, 5]) // Sun-Thu

        let firstStep = try XCTUnwrap(bindings.first(where: { $0.stepNumber == 0 }))
        XCTAssertEqual(
            Set(firstStep.triggerSchedule.recurrenceWeekdays ?? []),
            shiftedWeekdays,
            "Steps firing before midnight must recur on the previous weekday"
        )

        let wakeStep = try XCTUnwrap(bindings.max(by: { $0.stepNumber < $1.stepNumber }))
        XCTAssertEqual(
            Set(wakeStep.triggerSchedule.recurrenceWeekdays ?? []),
            configuredWeekdays,
            "The wake step itself fires on the configured weekdays"
        )
    }

    func testValidateAlarm_RepeatingAlarm_StaysValidAfterOccurrencePasses() async throws {
        let alarm = WakeAlarm(
            name: "Every Morning",
            wakeTimeSeconds: 7 * 3600,
            durationMinutes: 30,
            gradientCurve: .easeInOut,
            colorMode: .brightnessOnly,
            startBrightness: 0,
            targetBrightness: 100,
            isEnabled: true,
            selectedAccessoryIdentifiers: ["test-accessory-living-room-001"],
            homeIdentifier: "test-home-uuid-001"
        )
        try await repository.saveAlarm(alarm, schedule: .everyDay, validationState: .needsSync)
        try await generationService.syncAlarm(alarm, schedule: .everyDay)

        // Simulate the alarm having fired: the stored next-occurrence dates are now in
        // the past, but the HomeKit triggers (time-of-day + weekday recurrence) are
        // unchanged and perfectly healthy.
        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<AutomationBinding>()
        let alarmID = alarm.id
        descriptor.predicate = #Predicate { $0.alarmId == alarmID }
        for binding in try context.fetch(descriptor) {
            if let scheduledTime = binding.scheduledTime {
                binding.scheduledTime = Calendar.current.date(byAdding: .day, value: -7, to: scheduledTime)
            }
        }
        try context.save()

        let summary = await repairService.validateAlarm(alarm, schedule: .everyDay)

        XCTAssertEqual(
            summary.state, .valid,
            "A healthy repeating alarm must not be flagged for repair just because its last occurrence passed"
        )
    }

    func testValidateAlarm_FiredOneShot_DisablesItself() async throws {
        let alarm = WakeAlarm(
            name: "One Time Alarm",
            wakeTimeSeconds: 7 * 3600,
            durationMinutes: 30,
            gradientCurve: .easeInOut,
            colorMode: .brightnessOnly,
            startBrightness: 0,
            targetBrightness: 100,
            isEnabled: true,
            selectedAccessoryIdentifiers: ["test-accessory-living-room-001"],
            homeIdentifier: "test-home-uuid-001"
        )
        try await repository.saveAlarm(alarm, schedule: .never, validationState: .needsSync)
        try await generationService.syncAlarm(alarm, schedule: .never)

        // Backdate every step: the executeOnce triggers have all fired. The alarm
        // itself was last edited before the fire (the normal create-then-fire timeline).
        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<AutomationBinding>()
        let alarmID = alarm.id
        descriptor.predicate = #Predicate { $0.alarmId == alarmID }
        for binding in try context.fetch(descriptor) {
            if let scheduledTime = binding.scheduledTime {
                binding.scheduledTime = Calendar.current.date(byAdding: .day, value: -2, to: scheduledTime)
            }
        }
        var alarmDescriptor = FetchDescriptor<WakeAlarm>()
        alarmDescriptor.predicate = #Predicate { $0.id == alarmID }
        let storedAlarm = try XCTUnwrap(try context.fetch(alarmDescriptor).first)
        storedAlarm.updatedAt = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -3, to: Date()))
        try context.save()

        let maybeRefetched = await repository.fetchAlarm(byId: alarm.id)
        let refetchedForValidation = try XCTUnwrap(maybeRefetched)
        let summary = await repairService.validateAlarm(refetchedForValidation, schedule: .never)

        XCTAssertEqual(summary.state, .valid)
        let refetched = await repository.fetchAlarm(byId: alarm.id)
        XCTAssertEqual(refetched?.isEnabled, false, "A fired one-time alarm should turn itself off")
    }

    func testSyncAlarm_DoesNotGateTriggersOnCurrentLightPowerState() async throws {
        let alarm = WakeAlarm(
            name: "Bedroom Light Alarm",
            wakeTimeSeconds: 7 * 3600,
            durationMinutes: 30,
            gradientCurve: .easeInOut,
            colorMode: .brightnessOnly,
            startBrightness: 0,
            targetBrightness: 100,
            isEnabled: true,
            selectedAccessoryIdentifiers: [
                "test-accessory-living-room-001",
                "test-accessory-bedroom-001",
            ],
            homeIdentifier: "test-home-uuid-001"
        )
        try await repository.saveAlarm(alarm, schedule: .weekdays, validationState: .needsSync)

        try await generationService.syncAlarm(alarm, schedule: .weekdays)

        let triggers = controller.storedTriggers(for: "test-home-uuid-001")
        XCTAssertFalse(triggers.isEmpty)
        XCTAssertTrue(
            triggers.allSatisfy {
                $0.requiredOnAccessoryIdentifiers.isEmpty
            }
        )
    }

    func testMockUpsertScheduledTrigger_SortsRequiredOnAccessoryIdentifiers() async throws {
        let homeID = "test-home-uuid-001"
        let actionSet = try await controller.upsertActionSet(
            homeIdentifier: homeID,
            identifier: nil,
            name: "precondition.test.scene",
            requests: []
        )
        _ = try await controller.upsertScheduledTrigger(
            homeIdentifier: homeID,
            identifier: nil,
            name: "precondition.test.trigger",
            schedule: .calendar(fireDate: Date(), weekdays: nil),
            actionSetIdentifier: actionSet.identifier,
            requiredOnAccessoryIdentifiers: ["zebra-id", "alpha-id", "alpha-id"],
            isEnabled: true
        )
        let trigger = try XCTUnwrap(controller.storedTriggers(for: homeID).first)
        XCTAssertEqual(trigger.requiredOnAccessoryIdentifiers, ["alpha-id", "zebra-id"])
    }

    func testSyncAlarm_FirstStepSceneAlwaysTurnsLightOnAndAppliesStepZeroBrightness() async throws {
        let alarm = WakeAlarm(
            name: "Low Start Brightness Alarm",
            wakeTimeSeconds: 7 * 3600,
            durationMinutes: 30,
            gradientCurve: .easeInOut,
            colorMode: .brightnessOnly,
            startBrightness: 0,
            targetBrightness: 60,
            isEnabled: true,
            selectedAccessoryIdentifiers: ["test-accessory-living-room-001"],
            homeIdentifier: "test-home-uuid-001"
        )
        try await repository.saveAlarm(alarm, schedule: .never, validationState: .needsSync)

        let plannedStepZero = try XCTUnwrap(WakeAlarmStepPlanner.planSteps(for: alarm, stepCount: alarm.stepCount).first)
        try await generationService.syncAlarm(alarm, schedule: .never)

        let stepZeroScene = try XCTUnwrap(
            controller
                .storedActionSets(for: "test-home-uuid-001")
                .first(where: { $0.name.contains(".step.0.scene") })
        )

        XCTAssertTrue(
            stepZeroScene.requests.contains(
                HomeKitActionRequest(
                    accessoryIdentifier: "test-accessory-living-room-001",
                    characteristicType: HMCharacteristicTypePowerState,
                    value: .bool(true)
                )
            )
        )
        XCTAssertTrue(
            stepZeroScene.requests.contains(
                HomeKitActionRequest(
                    accessoryIdentifier: "test-accessory-living-room-001",
                    characteristicType: HMCharacteristicTypeBrightness,
                    value: .int(plannedStepZero.brightness)
                )
            )
        )
    }

    func testSyncAlarm_PreflightDisagreementCannotAbortStepZeroSchedule() async throws {
        let alarm = WakeAlarm(
            name: "No Preflight Gating Alarm",
            wakeTimeSeconds: 6 * 3600,
            durationMinutes: 15,
            gradientCurve: .linear,
            colorMode: .brightnessOnly,
            startBrightness: 1,
            targetBrightness: 80,
            isEnabled: true,
            selectedAccessoryIdentifiers: ["test-accessory-bedroom-001"],
            homeIdentifier: "test-home-uuid-001"
        )
        try await repository.saveAlarm(alarm, schedule: .never, validationState: .needsSync)

        try await generationService.syncAlarm(alarm, schedule: .never)

        let firstStepTrigger = try XCTUnwrap(
            controller
                .storedTriggers(for: "test-home-uuid-001")
                .first(where: { $0.name.contains(".step.0.trigger") })
        )
        XCTAssertTrue(firstStepTrigger.requiredOnAccessoryIdentifiers.isEmpty)
        XCTAssertEqual(firstStepTrigger.isEnabled, true)
    }

    func testSyncAlarm_SunriseAlarm_UsesSignificantTimeTriggersWithOffsets() async throws {
        let alarm = WakeAlarm(
            name: "Sunrise Light Alarm",
            wakeTimeSeconds: 7 * 3600,
            timeReference: .sunrise,
            timeOffsetMinutes: -15,
            durationMinutes: 30,
            gradientCurve: .easeInOut,
            colorMode: .brightnessOnly,
            startBrightness: 0,
            targetBrightness: 100,
            isEnabled: true,
            selectedAccessoryIdentifiers: ["test-accessory-living-room-001"],
            homeIdentifier: "test-home-uuid-001"
        )
        try await repository.saveAlarm(alarm, schedule: .weekdays, validationState: .needsSync)

        try await generationService.syncAlarm(alarm, schedule: .weekdays)

        let triggers = controller.storedTriggers(for: "test-home-uuid-001")
        XCTAssertEqual(triggers.count, WakeAlarmStepPlanner.defaultStepCount)

        var offsets: [Int] = []
        for trigger in triggers {
            guard case .significant(let reference, let offsetMinutes, let weekdays) = trigger.schedule else {
                XCTFail("Expected significant-time trigger, got \(trigger.schedule)")
                return
            }
            XCTAssertEqual(reference, .sunrise)
            XCTAssertEqual(Set(weekdays ?? []), Set(WeekdaySchedule.weekdays.weekdayNumbers))
            offsets.append(offsetMinutes)
        }

        // 30-minute ramp ending at sunrise - 15: first step fires 45 minutes
        // before sunrise, the wake step exactly at the configured offset.
        XCTAssertEqual(offsets.min(), -45)
        XCTAssertEqual(offsets.max(), -15)
        XCTAssertEqual(Set(offsets).count, offsets.count, "Each step needs a distinct solar offset")

        let bindings = await AutomationBindingService(modelContainer: modelContainer).bindingsForAlarm(alarm.id)
        XCTAssertFalse(bindings.isEmpty)
        XCTAssertTrue(bindings.allSatisfy { $0.scheduledTime == nil })
    }

    func testSyncAlarm_CustomStepCount_UsesExactNumberOfScenesAndTriggers() async throws {
        let alarm = WakeAlarm(
            name: "Dense Light Alarm",
            wakeTimeSeconds: 7 * 3600,
            durationMinutes: 20,
            stepCount: 20,
            gradientCurve: .easeInOut,
            colorMode: .brightnessOnly,
            startBrightness: 0,
            targetBrightness: 100,
            isEnabled: true,
            selectedAccessoryIdentifiers: ["test-accessory-living-room-001"],
            homeIdentifier: "test-home-uuid-001"
        )
        try await repository.saveAlarm(alarm, schedule: .weekdays, validationState: .needsSync)

        try await generationService.syncAlarm(alarm, schedule: .weekdays)

        XCTAssertEqual(controller.upsertActionSetCallCount, 20)
        XCTAssertEqual(controller.upsertScheduledTriggerCallCount, 20)
    }

    // MARK: - VAL-CROSS-001: Automation generation uses the redistributed plan

    func testSyncAlarm_DenseRamp_AutomationBrightnessMatchesPlannerOutput() async throws {
        // Arrange - Dense fixture: 20 steps with 0-100 brightness range
        // Use .never schedule for 1:1 binding-to-step comparison
        let alarm = WakeAlarm(
            name: "Dense Parity Test Alarm",
            wakeTimeSeconds: 7 * 3600,
            durationMinutes: 25,
            stepCount: 20,
            gradientCurve: .linear,  // Linear for predictable brightness distribution
            colorMode: .brightnessOnly,
            startBrightness: 0,
            targetBrightness: 100,
            isEnabled: true,
            selectedAccessoryIdentifiers: ["test-accessory-living-room-001"],
            homeIdentifier: "test-home-uuid-001"
        )
        try await repository.saveAlarm(alarm, schedule: .never, validationState: .needsSync)

        // Get the planner output for comparison
        let plannerSteps = WakeAlarmStepPlanner.planSteps(for: alarm, stepCount: alarm.stepCount)

        // Act - Generate automation
        try await generationService.syncAlarm(alarm, schedule: .never)

        // Assert - Compare automation bindings brightness with planner output
        let bindings = await AutomationBindingService(modelContainer: modelContainer).bindingsForAlarm(alarm.id)
        XCTAssertEqual(bindings.count, 20, "Should have 20 bindings for 20 steps")

        // Sort bindings by step number and compare brightness with planner
        let sortedBindings = bindings.sorted { $0.stepNumber < $1.stepNumber }
        for (index, binding) in sortedBindings.enumerated() {
            let plannerBrightness = plannerSteps[index].brightness
            XCTAssertEqual(binding.brightness, plannerBrightness,
                        "Binding step \(index) brightness (\(binding.brightness)) should match planner (\(plannerBrightness))")
        }
    }

    func testSyncAlarm_DenseRamp_AutomationPreservesEndpointBrightness() async throws {
        // Arrange - Alarm with specific start/target brightness endpoints
        // Use .never schedule for 1:1 binding-to-step comparison (VAL-CROSS-001)
        let alarm = WakeAlarm(
            name: "Endpoint Parity Test",
            wakeTimeSeconds: 7 * 3600,
            durationMinutes: 20,
            stepCount: 15,
            gradientCurve: .easeInOut,
            colorMode: .brightnessOnly,
            startBrightness: 15,
            targetBrightness: 85,
            isEnabled: true,
            selectedAccessoryIdentifiers: ["test-accessory-living-room-001"],
            homeIdentifier: "test-home-uuid-001"
        )
        try await repository.saveAlarm(alarm, schedule: .never, validationState: .needsSync)

        // Get planner output
        let plannerSteps = WakeAlarmStepPlanner.planSteps(for: alarm, stepCount: alarm.stepCount)

        // Act
        try await generationService.syncAlarm(alarm, schedule: .never)

        // Assert - Verify endpoints in automation match planner and configured values
        let bindings = await AutomationBindingService(modelContainer: modelContainer).bindingsForAlarm(alarm.id)
        let sortedBindings = bindings.sorted { $0.stepNumber < $1.stepNumber }

        // First binding should match start brightness
        XCTAssertEqual(sortedBindings.first?.brightness, 15,
                      "First automation binding should match configured start brightness (15)")
        XCTAssertEqual(sortedBindings.first?.brightness, plannerSteps.first?.brightness,
                      "First automation binding should match planner output")

        // Last binding should match target brightness
        XCTAssertEqual(sortedBindings.last?.brightness, 85,
                      "Last automation binding should match configured target brightness (85)")
        XCTAssertEqual(sortedBindings.last?.brightness, plannerSteps.last?.brightness,
                      "Last automation binding should match planner output")
    }

    func testSyncAlarm_DenseRamp_AutomationStepCountMatchesPlanner() async throws {
        // Arrange - Dense fixture with custom step count
        // Use .never schedule for 1:1 binding-to-step comparison (VAL-CROSS-001)
        let alarm = WakeAlarm(
            name: "Step Count Parity Test",
            wakeTimeSeconds: 7 * 3600,
            durationMinutes: 24,
            stepCount: 24,  // Maximum density
            gradientCurve: .linear,
            colorMode: .brightnessOnly,
            startBrightness: 0,
            targetBrightness: 100,
            isEnabled: true,
            selectedAccessoryIdentifiers: ["test-accessory-living-room-001"],
            homeIdentifier: "test-home-uuid-001"
        )
        try await repository.saveAlarm(alarm, schedule: .never, validationState: .needsSync)

        // Get planner step count
        let plannerSteps = WakeAlarmStepPlanner.planSteps(for: alarm, stepCount: alarm.stepCount)
        XCTAssertEqual(plannerSteps.count, 24, "Planner should produce 24 steps")

        // Act
        try await generationService.syncAlarm(alarm, schedule: .never)

        // Assert - Automation bindings count should match planner step count
        let bindings = await AutomationBindingService(modelContainer: modelContainer).bindingsForAlarm(alarm.id)
        XCTAssertEqual(bindings.count, plannerSteps.count,
                      "Automation binding count (\(bindings.count)) should match planner step count (\(plannerSteps.count))")

        // Also verify action sets created match step count
        XCTAssertEqual(controller.upsertActionSetCallCount, plannerSteps.count,
                      "Action set count should match planner step count")
    }

    func testSyncAlarm_WithDifferentStepCounts_AutomationParityMaintained() async throws {
        // Test various step counts to ensure parity is maintained across different densities
        let testCases = [
            (stepCount: 5, duration: 10),
            (stepCount: 10, duration: 15),
            (stepCount: 15, duration: 20),
            (stepCount: 20, duration: 25)
        ]

        for testCase in testCases {
            // Create fresh services for each test case
            let testController = MockHomeKitController.seededTestHome()
            let testService = AutomationGenerationService(
                homeKitController: testController,
                modelContainer: modelContainer,
                alarmRepository: repository
            )

            let alarm = WakeAlarm(
                name: "Parity Test \(testCase.stepCount) Steps",
                wakeTimeSeconds: 8 * 3600,
                durationMinutes: testCase.duration,
                stepCount: testCase.stepCount,
                gradientCurve: .linear,
                colorMode: .brightnessOnly,
                startBrightness: 0,
                targetBrightness: 100,
                isEnabled: true,
                selectedAccessoryIdentifiers: ["test-accessory-living-room-001"],
                homeIdentifier: "test-home-uuid-001"
            )

            try await repository.saveAlarm(alarm, schedule: .never, validationState: .needsSync)

            // Get planner output
            let plannerSteps = WakeAlarmStepPlanner.planSteps(for: alarm, stepCount: alarm.stepCount)

            // Generate automation
            try await testService.syncAlarm(alarm, schedule: .never)

            // Verify parity
            let bindings = await AutomationBindingService(modelContainer: modelContainer).bindingsForAlarm(alarm.id)
            XCTAssertEqual(bindings.count, testCase.stepCount,
                        "Step count \(testCase.stepCount): binding count should match")
            XCTAssertEqual(plannerSteps.count, testCase.stepCount,
                        "Step count \(testCase.stepCount): planner steps should match requested count")

            // Clean up for next iteration
            try await testService.removeAutomations(for: alarm, markDisabled: false)
        }
    }

    // MARK: - Live HomeKit drift and recoverable cleanup

    private func syncedReliabilityAlarm(timeReference: AlarmTimeReference = .clock) async throws -> WakeAlarm {
        let alarm = WakeAlarm(
            name: "Reliability Test",
            wakeTimeSeconds: 7 * 3600,
            timeReference: timeReference,
            durationMinutes: 10,
            stepCount: 3,
            colorMode: .brightnessOnly,
            isEnabled: true,
            selectedAccessoryIdentifiers: ["test-accessory-living-room-001"],
            homeIdentifier: "test-home-uuid-001"
        )
        try await repository.saveAlarm(alarm, schedule: .weekdays, validationState: .needsSync)
        try await generationService.syncAlarm(alarm, schedule: .weekdays)
        return alarm
    }

    private func assertDriftIsRepairable(_ alarm: WakeAlarm) async throws {
        let before = await repairService.validateAlarm(alarm, schedule: .weekdays)
        XCTAssertEqual(before.state, .outOfSync)
        XCTAssertTrue(before.requiresUserAction)
        let after = try await repairService.repairAlarm(alarm, schedule: .weekdays)
        XCTAssertEqual(after.state, .valid)
    }

    func testValidateAlarm_DetectsTriggerDisabledInHomeAndRepairsIt() async throws {
        let alarm = try await syncedReliabilityAlarm()
        let homeID = try XCTUnwrap(alarm.homeIdentifier)
        let trigger = try XCTUnwrap(controller.storedTriggers(for: homeID).first)
        _ = try await controller.upsertScheduledTrigger(
            homeIdentifier: homeID, identifier: trigger.identifier, name: trigger.name,
            schedule: trigger.schedule, actionSetIdentifier: trigger.actionSetIdentifier,
            requiredOnAccessoryIdentifiers: [], isEnabled: false
        )
        try await assertDriftIsRepairable(alarm)
        XCTAssertTrue(controller.storedTriggers(for: homeID).allSatisfy(\.isEnabled))
    }

    func testValidateAlarm_DetectsChangedWeekdaysAndRepairsThem() async throws {
        let alarm = try await syncedReliabilityAlarm()
        let homeID = try XCTUnwrap(alarm.homeIdentifier)
        let trigger = try XCTUnwrap(controller.storedTriggers(for: homeID).first)
        guard case .calendar(let fireDate, _) = trigger.schedule else {
            return XCTFail("Expected a clock trigger")
        }
        _ = try await controller.upsertScheduledTrigger(
            homeIdentifier: homeID, identifier: trigger.identifier, name: trigger.name,
            schedule: .calendar(fireDate: fireDate, weekdays: [1, 7]),
            actionSetIdentifier: trigger.actionSetIdentifier,
            requiredOnAccessoryIdentifiers: [], isEnabled: true
        )
        try await assertDriftIsRepairable(alarm)
    }

    func testValidateAlarm_DetectsChangedSolarOffsetAndRepairsIt() async throws {
        let alarm = try await syncedReliabilityAlarm(timeReference: .sunrise)
        let homeID = try XCTUnwrap(alarm.homeIdentifier)
        let trigger = try XCTUnwrap(controller.storedTriggers(for: homeID).first)
        guard case .significant(let reference, let offset, let weekdays) = trigger.schedule else {
            return XCTFail("Expected a solar trigger")
        }
        _ = try await controller.upsertScheduledTrigger(
            homeIdentifier: homeID, identifier: trigger.identifier, name: trigger.name,
            schedule: .significant(reference: reference, offsetMinutes: offset + 30, weekdays: weekdays),
            actionSetIdentifier: trigger.actionSetIdentifier,
            requiredOnAccessoryIdentifiers: [], isEnabled: true
        )
        try await assertDriftIsRepairable(alarm)
    }

    func testValidateAlarm_DetectsSceneEditsWithoutLocalBindingChanges() async throws {
        let alarm = try await syncedReliabilityAlarm()
        let homeID = try XCTUnwrap(alarm.homeIdentifier)
        let scene = try XCTUnwrap(controller.storedActionSets(for: homeID).first)
        let changedRequests = scene.requests.map { request in
            HomeKitActionRequest(
                accessoryIdentifier: request.accessoryIdentifier,
                characteristicType: request.characteristicType,
                value: request.characteristicType == HMCharacteristicTypeBrightness ? .int(42) : request.value
            )
        }
        _ = try await controller.upsertActionSet(
            homeIdentifier: homeID, identifier: scene.identifier, name: scene.name, requests: changedRequests
        )
        try await assertDriftIsRepairable(alarm)
        XCTAssertEqual(controller.storedActionSets(for: homeID).first { $0.identifier == scene.identifier }?.requests,
                       scene.requests)
    }

    func testDisabledAlarm_FailedCleanupStaysVisibleAndCanBeRepaired() async throws {
        let alarm = try await syncedReliabilityAlarm()
        let homeID = try XCTUnwrap(alarm.homeIdentifier)
        let triggerID = try XCTUnwrap(controller.storedTriggers(for: homeID).first?.identifier)
        controller.failingTriggerDeletions = [triggerID]
        try await repository.setAlarmEnabled(alarm, enabled: false)
        let saved = await repository.fetchAlarm(byId: alarm.id)
        let disabled = try XCTUnwrap(saved)
        do {
            try await generationService.removeAutomations(for: disabled, markDisabled: true)
            XCTFail("A failed HomeKit deletion must not report success")
        } catch {
            XCTAssertTrue(error is AutomationGenerationError)
        }
        let summary = await repairService.validateAlarm(disabled, schedule: .weekdays)
        XCTAssertEqual(summary.state, .outOfSync)
        XCTAssertTrue(summary.requiresUserAction)
        let survivors = await AutomationBindingService(modelContainer: modelContainer).bindingsForAlarm(alarm.id)
        XCTAssertEqual(survivors.count, 1)
        XCTAssertEqual(survivors.first?.triggerIdentifier, triggerID)

        controller.failingTriggerDeletions = []
        let repaired = try await repairService.repairAlarm(disabled, schedule: .weekdays)
        XCTAssertEqual(repaired.state, .valid)
        XCTAssertTrue(controller.storedTriggers(for: homeID).isEmpty)
        let after = await AutomationBindingService(modelContainer: modelContainer).bindingsForAlarm(alarm.id)
        XCTAssertTrue(after.isEmpty)
    }

    func testDeleteAlarm_PreservesAlarmAndBindingsUntilCleanupSucceeds() async throws {
        let alarm = try await syncedReliabilityAlarm()
        let homeID = try XCTUnwrap(alarm.homeIdentifier)
        controller.failingTriggerDeletions = Set(controller.storedTriggers(for: homeID).map(\.identifier))
        do {
            try await generationService.deleteAlarm(alarm)
            XCTFail("Deletion must wait for HomeKit cleanup")
        } catch {
            XCTAssertTrue(error is AutomationGenerationError)
        }
        let retained = await repository.fetchAlarm(byId: alarm.id)
        XCTAssertNotNil(retained)
        let bindings = await AutomationBindingService(modelContainer: modelContainer).bindingsForAlarm(alarm.id)
        XCTAssertEqual(bindings.count, alarm.stepCount)

        controller.failingTriggerDeletions = []
        try await generationService.deleteAlarm(alarm)
        let deleted = await repository.fetchAlarm(byId: alarm.id)
        XCTAssertNil(deleted)
        XCTAssertTrue(controller.storedTriggers(for: homeID).isEmpty)
    }

    func testReset_FailedCleanupPreservesBindingsForRetry() async throws {
        let alarm = try await syncedReliabilityAlarm()
        let homeID = try XCTUnwrap(alarm.homeIdentifier)
        controller.failingTriggerDeletions = Set(controller.storedTriggers(for: homeID).map(\.identifier))
        do {
            _ = try await generationService.resetDawnLoopArtifacts()
            XCTFail("An incomplete reset must not erase the bindings")
        } catch {
            XCTAssertTrue(error is AutomationGenerationError)
        }
        let retained = await AutomationBindingService(modelContainer: modelContainer).bindingsForAlarm(alarm.id)
        XCTAssertEqual(retained.count, alarm.stepCount)
        controller.failingTriggerDeletions = []
        let summary = try await generationService.resetDawnLoopArtifacts()
        XCTAssertEqual(summary.bindingsCleared, alarm.stepCount)
        XCTAssertTrue(controller.storedTriggers(for: homeID).isEmpty)
        let after = await AutomationBindingService(modelContainer: modelContainer).bindingsForAlarm(alarm.id)
        XCTAssertTrue(after.isEmpty)
    }

    func testRepair_DuplicateBindingsDoNotCrashOrDeleteActiveObjects() async throws {
        let alarm = try await syncedReliabilityAlarm()
        let context = ModelContext(modelContainer)
        let original = try XCTUnwrap(try context.fetch(FetchDescriptor<AutomationBinding>()).first)
        context.insert(AutomationBinding(
            alarmId: alarm.id, stepNumber: original.stepNumber,
            actionSetIdentifier: original.actionSetIdentifier, triggerIdentifier: original.triggerIdentifier,
            scheduledTime: original.scheduledTime, brightness: original.brightness
        ))
        try context.save()
        try await assertDriftIsRepairable(alarm)
        let bindings = await AutomationBindingService(modelContainer: modelContainer).bindingsForAlarm(alarm.id)
        XCTAssertEqual(bindings.count, alarm.stepCount)
        let homeID = try XCTUnwrap(alarm.homeIdentifier)
        XCTAssertEqual(controller.storedActionSets(for: homeID).count, alarm.stepCount)
        XCTAssertEqual(controller.storedTriggers(for: homeID).count, alarm.stepCount)
    }
}

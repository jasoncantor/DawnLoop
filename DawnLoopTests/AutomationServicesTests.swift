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
        XCTAssertEqual(
            controller.upsertScheduledTriggerCallCount,
            WakeAlarmStepPlanner.defaultStepCount * WeekdaySchedule.weekdays.activeDaysCount
        )
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
            schedule: .calendar(fireDate: Date(), weekday: nil),
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
        XCTAssertFalse(triggers.isEmpty)
        XCTAssertTrue(
            triggers.allSatisfy {
                if case .significant(let reference, _, let weekday) = $0.schedule {
                    return reference == .sunrise && weekday != nil
                }
                return false
            }
        )

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
        XCTAssertEqual(controller.upsertScheduledTriggerCallCount, 20 * WeekdaySchedule.weekdays.activeDaysCount)
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
}

import XCTest
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
        try await super.setUp()

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
        try await super.tearDown()
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

    func testSyncAlarm_StopsFutureStepsWhenSelectedLightsAreTurnedOff() async throws {
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
                $0.requiredOnAccessoryIdentifiers == [
                    "test-accessory-bedroom-001",
                    "test-accessory-living-room-001",
                ]
            }
        )
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
}

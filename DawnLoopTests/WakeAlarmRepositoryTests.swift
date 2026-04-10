import XCTest
import SwiftData
@testable import DawnLoop

/// Tests for WakeAlarmRepository persistence operations
/// Validates VAL-ALARM-005, VAL-ALARM-006, and VAL-ALARM-007
@MainActor
final class WakeAlarmRepositoryTests: XCTestCase {

    var modelContainer: ModelContainer!
    var repository: WakeAlarmRepository!

    override func setUp() {
        super.setUp()

        let schema = Schema([
            WakeAlarm.self,
            WakeAlarmSchedule.self,
            AutomationBinding.self,
            OnboardingCompletion.self,
            HomeReference.self,
            AccessoryReference.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            XCTFail("Failed to create model container: \(error)")
            return
        }

        repository = WakeAlarmRepository(modelContainer: modelContainer)
    }

    override func tearDown() {
        modelContainer = nil
        repository = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func createTestAlarm(
        name: String = "Test Alarm",
        wakeTimeSeconds: Int = 7 * 3600, // 7:00 AM
        isEnabled: Bool = true
    ) -> WakeAlarm {
        return WakeAlarm(
            name: name,
            wakeTimeSeconds: wakeTimeSeconds,
            durationMinutes: 30,
            gradientCurve: .easeInOut,
            colorMode: .brightnessOnly,
            startBrightness: 0,
            targetBrightness: 100,
            isEnabled: isEnabled,
            selectedAccessoryIdentifiers: ["test-accessory-1"],
            homeIdentifier: "test-home"
        )
    }

    // MARK: - VAL-ALARM-005: Saved alarms persist and reopen with the same configuration

    func testSaveAlarm_PersistsAllConfigurationFields() async throws {
        let alarm = createTestAlarm(
            name: "Morning Sunrise",
            wakeTimeSeconds: 7 * 3600 + 30 * 60 // 7:30 AM
        )

        // Save the alarm
        try await repository.saveAlarm(alarm)

        // Fetch and verify all fields round-tripped
        let fetched = await repository.fetchAlarm(byId: alarm.id)
        XCTAssertNotNil(fetched)

        XCTAssertEqual(fetched?.name, "Morning Sunrise")
        XCTAssertEqual(fetched?.wakeTimeSeconds, 7 * 3600 + 30 * 60)
        XCTAssertEqual(fetched?.durationMinutes, 30)
        XCTAssertEqual(fetched?.gradientCurve, .easeInOut)
        XCTAssertEqual(fetched?.colorMode, .brightnessOnly)
        XCTAssertEqual(fetched?.startBrightness, 0)
        XCTAssertEqual(fetched?.targetBrightness, 100)
        XCTAssertEqual(fetched?.isEnabled, true)
        XCTAssertEqual(fetched?.selectedAccessoryIdentifiers, ["test-accessory-1"])
        XCTAssertEqual(fetched?.homeIdentifier, "test-home")
    }

    func testFetchAllAlarms_ReturnsSavedAlarms() async throws {
        let alarm1 = createTestAlarm(name: "Alarm 1")
        let alarm2 = createTestAlarm(name: "Alarm 2")

        try await repository.saveAlarm(alarm1)
        try await repository.saveAlarm(alarm2)

        let allAlarms = await repository.fetchAllAlarms()
        XCTAssertEqual(allAlarms.count, 2)
        XCTAssertTrue(allAlarms.contains { $0.name == "Alarm 1" })
        XCTAssertTrue(allAlarms.contains { $0.name == "Alarm 2" })
    }

    func testFetchAlarmById_ReturnsCorrectAlarm() async throws {
        let alarm = createTestAlarm(name: "Specific Alarm")
        try await repository.saveAlarm(alarm)

        let fetched = await repository.fetchAlarm(byId: alarm.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.name, "Specific Alarm")
        XCTAssertEqual(fetched?.id, alarm.id)
    }

    func testFetchAlarmById_ReturnsNilForUnknownId() async {
        let unknownId = UUID()
        let fetched = await repository.fetchAlarm(byId: unknownId)
        XCTAssertNil(fetched)
    }

    // MARK: - VAL-ALARM-006: Enable state persists independently of alarm details

    func testToggleEnabled_OnlyMutatesEnabledState() async throws {
        let alarm = createTestAlarm(name: "Toggle Test", isEnabled: true)
        let originalWakeTime = alarm.wakeTimeSeconds
        let originalDuration = alarm.durationMinutes
        let originalBrightness = alarm.targetBrightness

        try await repository.saveAlarm(alarm)

        // Toggle enabled state
        try await repository.toggleAlarmEnabled(alarm)

        // Verify alarm was updated
        let fetched = await repository.fetchAlarm(byId: alarm.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.isEnabled, false)

        // Verify other fields unchanged
        XCTAssertEqual(fetched?.wakeTimeSeconds, originalWakeTime)
        XCTAssertEqual(fetched?.durationMinutes, originalDuration)
        XCTAssertEqual(fetched?.targetBrightness, originalBrightness)
        XCTAssertEqual(fetched?.name, "Toggle Test")
    }

    func testSetEnabled_OnlyMutatesEnabledState() async throws {
        let alarm = createTestAlarm(name: "Set Enabled Test", isEnabled: false)
        let originalConfig = (
            wakeTime: alarm.wakeTimeSeconds,
            duration: alarm.durationMinutes,
            brightness: alarm.targetBrightness,
            accessories: alarm.selectedAccessoryIdentifiers
        )

        try await repository.saveAlarm(alarm)

        // Enable the alarm
        try await repository.setAlarmEnabled(alarm, enabled: true)

        // Verify only enabled changed
        let fetched = await repository.fetchAlarm(byId: alarm.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.isEnabled, true)
        XCTAssertEqual(fetched?.wakeTimeSeconds, originalConfig.wakeTime)
        XCTAssertEqual(fetched?.durationMinutes, originalConfig.duration)
        XCTAssertEqual(fetched?.targetBrightness, originalConfig.brightness)
        XCTAssertEqual(fetched?.selectedAccessoryIdentifiers, originalConfig.accessories)
    }

    func testFetchEnabledAlarms_ReturnsOnlyEnabled() async throws {
        let enabledAlarm = createTestAlarm(name: "Enabled", isEnabled: true)
        let disabledAlarm = createTestAlarm(name: "Disabled", isEnabled: false)

        try await repository.saveAlarm(enabledAlarm)
        try await repository.saveAlarm(disabledAlarm)

        let enabledAlarms = await repository.fetchEnabledAlarms()
        XCTAssertEqual(enabledAlarms.count, 1)
        XCTAssertEqual(enabledAlarms.first?.name, "Enabled")
    }

    func testSaveAlarm_PreservesEnabledStateIndependently() async throws {
        // Create and save an enabled alarm
        let alarm = createTestAlarm(name: "Enabled Alarm", isEnabled: true)
        try await repository.saveAlarm(alarm)

        // Update configuration without touching enabled state
        let updated = try await repository.updateAlarm(
            alarm,
            name: "Updated Name",
            wakeTimeSeconds: 8 * 3600, // 8:00 AM
            durationMinutes: 45,
            targetBrightness: 80
        )

        // Verify enabled state preserved
        XCTAssertEqual(updated.isEnabled, true)
        XCTAssertEqual(updated.name, "Updated Name")
        XCTAssertEqual(updated.wakeTimeSeconds, 8 * 3600)
    }

    // MARK: - VAL-ALARM-007: Creating and editing preserve the correct alarm identity

    func testSaveExistingAlarm_UpdatesRatherThanCreatesDuplicate() async throws {
        let alarm = createTestAlarm(name: "Original Alarm")
        try await repository.saveAlarm(alarm)

        // Verify one alarm exists
        let allAlarms1 = await repository.fetchAllAlarms()
        XCTAssertEqual(allAlarms1.count, 1)

        // Modify and save again with same ID
        alarm.name = "Updated Alarm"
        alarm.wakeTimeSeconds = 9 * 3600 // 9:00 AM
        try await repository.saveAlarm(alarm)

        // Verify still only one alarm, but with updated values
        let allAlarms2 = await repository.fetchAllAlarms()
        XCTAssertEqual(allAlarms2.count, 1)
        XCTAssertEqual(allAlarms2.first?.name, "Updated Alarm")
        XCTAssertEqual(allAlarms2.first?.wakeTimeSeconds, 9 * 3600)
        XCTAssertEqual(allAlarms2.first?.id, alarm.id) // Same ID
    }

    func testUpdateAlarm_PreservesIdentity() async throws {
        let alarm = createTestAlarm(name: "Editable Alarm")
        let originalId = alarm.id
        try await repository.saveAlarm(alarm)

        // Update via repository method
        let updated = try await repository.updateAlarm(
            alarm,
            name: "New Name",
            wakeTimeSeconds: 10 * 3600,
            targetBrightness: 75
        )

        // Verify same ID
        XCTAssertEqual(updated.id, originalId)

        // Verify in persistence
        let fetched = await repository.fetchAlarm(byId: originalId)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, originalId)
        XCTAssertEqual(fetched?.name, "New Name")
    }

    func testCreateAlarm_GeneratesNewIdentity() async throws {
        let alarm1 = try await repository.createAlarm(
            name: "First Alarm",
            wakeTimeSeconds: 7 * 3600
        )

        let alarm2 = try await repository.createAlarm(
            name: "Second Alarm",
            wakeTimeSeconds: 8 * 3600
        )

        // Verify different IDs
        XCTAssertNotEqual(alarm1.id, alarm2.id)

        // Both exist in persistence
        let allAlarms = await repository.fetchAllAlarms()
        XCTAssertEqual(allAlarms.count, 2)
    }

    func testDuplicateAlarm_CreatesNewIdentityWithCopiedConfiguration() async throws {
        let original = createTestAlarm(
            name: "Original",
            wakeTimeSeconds: 7 * 3600,
            isEnabled: true
        )
        original.targetBrightness = 85
        original.colorMode = .fullColor
        try await repository.saveAlarm(original)

        // Duplicate
        let copy = try await repository.duplicateAlarm(original)

        // Verify different IDs
        XCTAssertNotEqual(original.id, copy.id)

        // Verify copied configuration
        XCTAssertEqual(copy.name, "Original Copy")
        XCTAssertEqual(copy.wakeTimeSeconds, 7 * 3600)
        XCTAssertEqual(copy.targetBrightness, 85)
        XCTAssertEqual(copy.colorMode, .fullColor)
        XCTAssertEqual(copy.selectedAccessoryIdentifiers, original.selectedAccessoryIdentifiers)

        // Duplicated alarm starts disabled
        XCTAssertEqual(copy.isEnabled, false)
    }

    // MARK: - Delete Operations

    func testDeleteAlarm_RemovesFromPersistence() async throws {
        let alarm = createTestAlarm(name: "To Delete")
        try await repository.saveAlarm(alarm)

        // Verify exists
        var allAlarms = await repository.fetchAllAlarms()
        XCTAssertEqual(allAlarms.count, 1)

        // Delete
        try await repository.deleteAlarm(alarm)

        // Verify removed
        allAlarms = await repository.fetchAllAlarms()
        XCTAssertEqual(allAlarms.count, 0)
    }

    func testDeleteAlarmById_RemovesFromPersistence() async throws {
        let alarm = createTestAlarm(name: "Delete By ID")
        try await repository.saveAlarm(alarm)

        // Delete by ID
        try await repository.deleteAlarm(byId: alarm.id)

        // Verify removed
        let fetched = await repository.fetchAlarm(byId: alarm.id)
        XCTAssertNil(fetched)
    }

    func testDeleteAlarmById_ThrowsForUnknownId() async {
        let unknownId = UUID()

        do {
            try await repository.deleteAlarm(byId: unknownId)
            XCTFail("Expected error for unknown alarm ID")
        } catch {
            // Expected
            XCTAssertTrue(error is WakeAlarmRepositoryError)
        }
    }

    // MARK: - Complex Color Mode Tests

    func testSaveAlarm_WithFullColorConfiguration() async throws {
        let alarm = WakeAlarm(
            name: "Color Alarm",
            wakeTimeSeconds: 7 * 3600,
            durationMinutes: 30,
            gradientCurve: .easeIn,
            colorMode: .fullColor,
            startBrightness: 0,
            targetBrightness: 100,
            targetColorTemperature: nil,
            targetHue: 30,
            targetSaturation: 80,
            isEnabled: true,
            selectedAccessoryIdentifiers: ["accessory-1", "accessory-2"]
        )

        try await repository.saveAlarm(alarm)

        let fetched = await repository.fetchAlarm(byId: alarm.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.colorMode, .fullColor)
        XCTAssertEqual(fetched?.targetHue, 30)
        XCTAssertEqual(fetched?.targetSaturation, 80)
        XCTAssertEqual(fetched?.selectedAccessoryIdentifiers.count, 2)
    }

    func testSaveAlarm_WithColorTemperatureConfiguration() async throws {
        let alarm = WakeAlarm(
            name: "Warm Light Alarm",
            wakeTimeSeconds: 6 * 3600,
            durationMinutes: 45,
            gradientCurve: .easeOut,
            colorMode: .colorTemperature,
            startBrightness: 5,
            targetBrightness: 95,
            targetColorTemperature: 300,
            targetHue: nil,
            targetSaturation: nil,
            isEnabled: false
        )

        try await repository.saveAlarm(alarm)

        let fetched = await repository.fetchAlarm(byId: alarm.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.colorMode, .colorTemperature)
        XCTAssertEqual(fetched?.targetColorTemperature, 300)
        XCTAssertEqual(fetched?.targetHue, nil)
        XCTAssertEqual(fetched?.isEnabled, false)
    }

    // MARK: - Validation State Tests

    func testUpdateValidationState_PersistsCorrectly() async throws {
        let alarm = createTestAlarm(name: "Validation Test")
        try await repository.saveAlarm(alarm)

        // Update validation state
        try await repository.updateValidationState(alarm, state: .outOfSync)

        let fetched = await repository.fetchAlarm(byId: alarm.id)
        XCTAssertEqual(fetched?.validationState, .outOfSync)
    }

    // MARK: - Home-Specific Fetch Tests

    func testFetchAlarmsForHome_ReturnsOnlyMatchingHome() async throws {
        let home1Alarm = createTestAlarm(name: "Home 1 Alarm")
        home1Alarm.homeIdentifier = "home-1"

        let home2Alarm = createTestAlarm(name: "Home 2 Alarm")
        home2Alarm.homeIdentifier = "home-2"

        try await repository.saveAlarm(home1Alarm)
        try await repository.saveAlarm(home2Alarm)

        let home1Alarms = await repository.fetchAlarms(forHomeId: "home-1")
        XCTAssertEqual(home1Alarms.count, 1)
        XCTAssertEqual(home1Alarms.first?.name, "Home 1 Alarm")
    }

    // MARK: - Round-Trip Persistence Tests

    func testRoundTrip_AllConfigurationFields() async throws {
        // Create alarm with all fields populated
        let original = WakeAlarm(
            id: UUID(),
            name: "Complete Alarm",
            wakeTimeSeconds: 7 * 3600 + 15 * 60, // 7:15 AM
            durationMinutes: 45,
            gradientCurve: .easeInOut,
            colorMode: .fullColor,
            startBrightness: 5,
            targetBrightness: 95,
            targetColorTemperature: nil,
            targetHue: 45,
            targetSaturation: 70,
            isEnabled: true,
            selectedAccessoryIdentifiers: ["light-1", "light-2", "light-3"],
            homeIdentifier: "my-home-id"
        )

        original.setValidationState(.valid)

        // Save
        try await repository.saveAlarm(original)

        // Fetch and verify everything round-tripped correctly
        let fetched = await repository.fetchAlarm(byId: original.id)
        XCTAssertNotNil(fetched)

        XCTAssertEqual(fetched?.id, original.id)
        XCTAssertEqual(fetched?.name, "Complete Alarm")
        XCTAssertEqual(fetched?.wakeTimeSeconds, 7 * 3600 + 15 * 60)
        XCTAssertEqual(fetched?.durationMinutes, 45)
        XCTAssertEqual(fetched?.gradientCurve, .easeInOut)
        XCTAssertEqual(fetched?.colorMode, .fullColor)
        XCTAssertEqual(fetched?.startBrightness, 5)
        XCTAssertEqual(fetched?.targetBrightness, 95)
        XCTAssertEqual(fetched?.targetHue, 45)
        XCTAssertEqual(fetched?.targetSaturation, 70)
        XCTAssertEqual(fetched?.targetColorTemperature, nil)
        XCTAssertEqual(fetched?.isEnabled, true)
        XCTAssertEqual(fetched?.selectedAccessoryIdentifiers, ["light-1", "light-2", "light-3"])
        XCTAssertEqual(fetched?.homeIdentifier, "my-home-id")
        XCTAssertEqual(fetched?.validationState, .valid)
    }

    func testRoundTrip_EnableStateAfterEdit() async throws {
        // Create and save disabled alarm
        let alarm = createTestAlarm(name: "Test", isEnabled: false)
        try await repository.saveAlarm(alarm)

        // Edit configuration
        let edited = try await repository.updateAlarm(
            alarm,
            name: "Edited Name",
            wakeTimeSeconds: 9 * 3600,
            durationMinutes: 60
        )

        // Should still be disabled (VAL-ALARM-006)
        XCTAssertEqual(edited.isEnabled, false)

        // Re-fetch to confirm persistence
        let fetched = await repository.fetchAlarm(byId: alarm.id)
        XCTAssertEqual(fetched?.isEnabled, false)
        XCTAssertEqual(fetched?.name, "Edited Name")
    }
}

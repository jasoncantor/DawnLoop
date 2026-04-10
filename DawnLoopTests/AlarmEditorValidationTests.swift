import XCTest
@testable import DawnLoop

/// Tests for Alarm Editor validation
/// Validates VAL-ALARM-001, VAL-ALARM-002, and VAL-ALARM-008
@MainActor
final class AlarmEditorValidationTests: XCTestCase {

    var editorState: AlarmEditorState!

    override func setUp() {
        super.setUp()
        editorState = AlarmEditorState()
    }

    override func tearDown() {
        editorState = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func createAccessory(
        id: String,
        name: String,
        capability: AccessoryCapability,
        roomName: String = "Test Room"
    ) -> AccessoryViewModel {
        return AccessoryViewModel(
            from: AccessoryReference(
                homeKitIdentifier: id,
                name: name,
                roomName: roomName,
                homeIdentifier: "test-home",
                isCompatible: capability != .unsupported
            )
        )
    }

    // MARK: - VAL-ALARM-001: Invalid editor input blocks save without losing entered values

    func testValidate_EmptyName_ReturnsErrorAndBlocksSave() {
        // Arrange
        editorState.alarmName = ""
        editorState.selectedAccessoryIds = ["acc-1"]

        // Act
        let isValid = editorState.validate()

        // Assert
        XCTAssertFalse(isValid)
        XCTAssertNotNil(editorState.validation.nameError)
        XCTAssertEqual(editorState.validation.nameError, "Alarm name is required")
    }

    func testValidate_LongName_ReturnsErrorAndBlocksSave() {
        // Arrange
        editorState.alarmName = String(repeating: "A", count: 51)
        editorState.selectedAccessoryIds = ["acc-1"]

        // Act
        let isValid = editorState.validate()

        // Assert
        XCTAssertFalse(isValid)
        XCTAssertNotNil(editorState.validation.nameError)
        XCTAssertEqual(editorState.validation.nameError, "Alarm name must be 50 characters or less")
    }

    func testValidate_NoAccessoriesSelected_ReturnsErrorAndBlocksSave() {
        // Arrange
        editorState.alarmName = "Test Alarm"
        editorState.selectedAccessoryIds = []

        // Act
        let isValid = editorState.validate()

        // Assert
        XCTAssertFalse(isValid)
        XCTAssertNotNil(editorState.validation.accessoryError)
        XCTAssertEqual(editorState.validation.accessoryError, "Select at least one light")
    }

    func testValidate_InvalidBrightnessRange_ReturnsErrorAndBlocksSave() {
        // Arrange
        editorState.alarmName = "Test Alarm"
        editorState.selectedAccessoryIds = ["acc-1"]
        editorState.startBrightness = 60
        editorState.targetBrightness = 40

        // Act
        let isValid = editorState.validate()

        // Assert
        XCTAssertFalse(isValid)
        XCTAssertNotNil(editorState.validation.brightnessError)
        XCTAssertEqual(editorState.validation.brightnessError, "Target brightness must be higher than start brightness")
    }

    func testValidate_ShortDuration_ReturnsErrorAndBlocksSave() {
        // Arrange
        editorState.alarmName = "Test Alarm"
        editorState.selectedAccessoryIds = ["acc-1"]
        editorState.durationMinutes = 0

        // Act
        let isValid = editorState.validate()

        // Assert
        XCTAssertFalse(isValid)
        XCTAssertNotNil(editorState.validation.durationError)
        XCTAssertEqual(editorState.validation.durationError, "Duration must be at least 1 minute")
    }

    func testValidate_LongDuration_ReturnsErrorAndBlocksSave() {
        // Arrange
        editorState.alarmName = "Test Alarm"
        editorState.selectedAccessoryIds = ["acc-1"]
        editorState.durationMinutes = 121

        // Act
        let isValid = editorState.validate()

        // Assert
        XCTAssertFalse(isValid)
        XCTAssertNotNil(editorState.validation.durationError)
        XCTAssertEqual(editorState.validation.durationError, "Duration must be 2 hours or less")
    }

    func testValidate_InvalidationPreservesOtherInputs() {
        // Arrange - Set all valid values
        editorState.alarmName = "Test Alarm"
        editorState.durationMinutes = 30
        editorState.startBrightness = 10
        editorState.targetBrightness = 80
        editorState.gradientCurve = .easeIn
        editorState.colorMode = .brightnessOnly
        editorState.selectedAccessoryIds = ["acc-1"]

        // Make one field invalid (empty name)
        editorState.alarmName = ""

        // Act
        let isValid = editorState.validate()

        // Assert
        XCTAssertFalse(isValid)
        XCTAssertNotNil(editorState.validation.nameError)

        // Verify other values are preserved (VAL-ALARM-001)
        XCTAssertEqual(editorState.durationMinutes, 30)
        XCTAssertEqual(editorState.startBrightness, 10)
        XCTAssertEqual(editorState.targetBrightness, 80)
        XCTAssertEqual(editorState.gradientCurve, .easeIn)
        XCTAssertEqual(editorState.colorMode, .brightnessOnly)
        XCTAssertEqual(editorState.selectedAccessoryIds, ["acc-1"])
    }

    func testValidate_MultipleErrors_CollectsAllErrors() {
        // Arrange - Multiple invalid fields
        editorState.alarmName = ""
        editorState.selectedAccessoryIds = []
        editorState.durationMinutes = 0
        editorState.startBrightness = 60
        editorState.targetBrightness = 40

        // Act
        let isValid = editorState.validate()

        // Assert
        XCTAssertFalse(isValid)
        XCTAssertNotNil(editorState.validation.nameError)
        XCTAssertNotNil(editorState.validation.accessoryError)
        XCTAssertNotNil(editorState.validation.durationError)
        XCTAssertNotNil(editorState.validation.brightnessError)
    }

    func testCreateAlarm_InvalidState_ReturnsNil() {
        // Arrange - Invalid state
        editorState.alarmName = ""
        editorState.selectedAccessoryIds = []

        // Act
        let alarm = editorState.createAlarm()

        // Assert
        XCTAssertNil(alarm)
    }

    func testCreateAlarm_ValidState_ReturnsAlarm() {
        // Arrange - Valid state
        editorState.alarmName = "Morning Alarm"
        editorState.durationMinutes = 30
        editorState.startBrightness = 0
        editorState.targetBrightness = 100
        editorState.gradientCurve = .easeInOut
        editorState.colorMode = .brightnessOnly
        editorState.selectedAccessoryIds = ["acc-1"]

        // Act
        let alarm = editorState.createAlarm()

        // Assert
        XCTAssertNotNil(alarm)
        XCTAssertEqual(alarm?.name, "Morning Alarm")
        XCTAssertEqual(alarm?.durationMinutes, 30)
        XCTAssertEqual(alarm?.selectedAccessoryIdentifiers, ["acc-1"])
    }

    // MARK: - VAL-ALARM-002: Capability-aware controls appear only when supported

    func testCanShowColorTemperature_BrightnessOnlyAccessory_ReturnsFalse() {
        // Arrange
        let accessory = createAccessory(id: "acc-1", name: "Basic Light", capability: .brightnessOnly)
        editorState.availableAccessories = [accessory]
        editorState.selectedAccessoryIds = ["acc-1"]

        // Assert
        XCTAssertFalse(editorState.canShowColorTemperature)
        XCTAssertFalse(editorState.canShowFullColor)
    }

    func testCanShowColorTemperature_TunableWhiteAccessory_ReturnsTrue() {
        // Arrange
        let accessory = createAccessory(id: "acc-1", name: "Warm Light", capability: .tunableWhite)
        editorState.availableAccessories = [accessory]
        editorState.selectedAccessoryIds = ["acc-1"]

        // Assert
        XCTAssertTrue(editorState.canShowColorTemperature)
        XCTAssertFalse(editorState.canShowFullColor)
    }

    func testCanShowFullColor_FullColorAccessory_ReturnsTrue() {
        // Arrange
        let accessory = createAccessory(id: "acc-1", name: "Color Light", capability: .fullColor)
        editorState.availableAccessories = [accessory]
        editorState.selectedAccessoryIds = ["acc-1"]

        // Assert
        XCTAssertTrue(editorState.canShowColorTemperature)
        XCTAssertTrue(editorState.canShowFullColor)
    }

    func testCanShowColorTemperature_MixedAccessories_ReturnsTrue() {
        // Arrange - Mix of capabilities
        let brightnessOnly = createAccessory(id: "acc-1", name: "Basic Light", capability: .brightnessOnly)
        let tunableWhite = createAccessory(id: "acc-2", name: "Warm Light", capability: .tunableWhite)
        editorState.availableAccessories = [brightnessOnly, tunableWhite]
        editorState.selectedAccessoryIds = ["acc-1", "acc-2"]

        // Assert - Should show controls because at least one supports it (VAL-ALARM-002)
        XCTAssertTrue(editorState.canShowColorTemperature)
    }

    func testDegradationExplanation_MixedBrightnessOnlyAndTunableWhite_ColorTemperatureMode_ReturnsExplanation() {
        // Arrange
        let brightnessOnly = createAccessory(id: "acc-1", name: "Basic Light", capability: .brightnessOnly)
        let tunableWhite = createAccessory(id: "acc-2", name: "Warm Light", capability: .tunableWhite)
        editorState.availableAccessories = [brightnessOnly, tunableWhite]
        editorState.selectedAccessoryIds = ["acc-1", "acc-2"]
        editorState.colorMode = .colorTemperature

        // Assert
        XCTAssertEqual(editorState.degradationExplanation, "Some lights will use brightness only.")
    }

    func testDegradationExplanation_MixedBrightnessOnlyAndFullColor_FullColorMode_ReturnsExplanation() {
        // Arrange
        let brightnessOnly = createAccessory(id: "acc-1", name: "Basic Light", capability: .brightnessOnly)
        let fullColor = createAccessory(id: "acc-2", name: "Color Light", capability: .fullColor)
        editorState.availableAccessories = [brightnessOnly, fullColor]
        editorState.selectedAccessoryIds = ["acc-1", "acc-2"]
        editorState.colorMode = .fullColor

        // Assert
        XCTAssertEqual(editorState.degradationExplanation, "Some lights will use brightness only.")
    }

    func testDegradationExplanation_MixedTunableWhiteAndFullColor_FullColorMode_ReturnsExplanation() {
        // Arrange
        let tunableWhite = createAccessory(id: "acc-1", name: "Warm Light", capability: .tunableWhite)
        let fullColor = createAccessory(id: "acc-2", name: "Color Light", capability: .fullColor)
        editorState.availableAccessories = [tunableWhite, fullColor]
        editorState.selectedAccessoryIds = ["acc-1", "acc-2"]
        editorState.colorMode = .fullColor

        // Assert
        XCTAssertEqual(editorState.degradationExplanation, "Some lights will use warm light instead of full color.")
    }

    func testDegradationExplanation_AllSameCapabilities_ReturnsNil() {
        // Arrange
        let fullColor1 = createAccessory(id: "acc-1", name: "Color Light 1", capability: .fullColor)
        let fullColor2 = createAccessory(id: "acc-2", name: "Color Light 2", capability: .fullColor)
        editorState.availableAccessories = [fullColor1, fullColor2]
        editorState.selectedAccessoryIds = ["acc-1", "acc-2"]
        editorState.colorMode = .fullColor

        // Assert
        XCTAssertNil(editorState.degradationExplanation)
    }

    func testHasMixedCapabilities_AllSame_ReturnsFalse() {
        // Arrange
        let fullColor1 = createAccessory(id: "acc-1", name: "Color Light 1", capability: .fullColor)
        let fullColor2 = createAccessory(id: "acc-2", name: "Color Light 2", capability: .fullColor)
        editorState.availableAccessories = [fullColor1, fullColor2]
        editorState.selectedAccessoryIds = ["acc-1", "acc-2"]

        // Assert
        XCTAssertFalse(editorState.hasMixedCapabilities)
    }

    func testHasMixedCapabilities_DifferentCapabilities_ReturnsTrue() {
        // Arrange
        let brightnessOnly = createAccessory(id: "acc-1", name: "Basic Light", capability: .brightnessOnly)
        let fullColor = createAccessory(id: "acc-2", name: "Color Light", capability: .fullColor)
        editorState.availableAccessories = [brightnessOnly, fullColor]
        editorState.selectedAccessoryIds = ["acc-1", "acc-2"]

        // Assert
        XCTAssertTrue(editorState.hasMixedCapabilities)
    }

    // MARK: - VAL-ALARM-008: Editing handles invalidated accessory selections safely

    func testLoad_WithInvalidatedAccessory_MarksAsInvalidated() {
        // Arrange - Alarm with accessories that no longer exist
        let alarm = WakeAlarm(
            name: "Test Alarm",
            wakeTimeSeconds: 7 * 3600,
            selectedAccessoryIdentifiers: ["old-acc-1", "old-acc-2"],
            homeIdentifier: "test-home"
        )

        // Only one accessory still available
        let availableAccessory = createAccessory(id: "acc-new", name: "New Light", capability: .brightnessOnly)

        // Act
        editorState.load(alarm: alarm, availableAccessories: [availableAccessory])

        // Assert
        XCTAssertEqual(editorState.invalidatedAccessoryIds, ["old-acc-1", "old-acc-2"])
        XCTAssertTrue(editorState.selectedAccessoryIds.isEmpty)
    }

    func testLoad_WithPartiallyInvalidatedAccessory_SelectsOnlyValidOnes() {
        // Arrange - Alarm with some accessories that still exist
        let alarm = WakeAlarm(
            name: "Test Alarm",
            wakeTimeSeconds: 7 * 3600,
            selectedAccessoryIdentifiers: ["valid-acc", "invalid-acc"],
            homeIdentifier: "test-home"
        )

        // Only one accessory still available
        let availableAccessory = createAccessory(id: "valid-acc", name: "Valid Light", capability: .brightnessOnly)

        // Act
        editorState.load(alarm: alarm, availableAccessories: [availableAccessory])

        // Assert
        XCTAssertEqual(editorState.invalidatedAccessoryIds, ["invalid-acc"])
        XCTAssertEqual(editorState.selectedAccessoryIds, ["valid-acc"])
    }

    func testValidate_WithInvalidatedAccessory_ReturnsErrorAndBlocksSave() {
        // Arrange
        let alarm = WakeAlarm(
            name: "Test Alarm",
            wakeTimeSeconds: 7 * 3600,
            selectedAccessoryIdentifiers: ["old-acc"],
            homeIdentifier: "test-home"
        )

        let newAccessory = createAccessory(id: "new-acc", name: "New Light", capability: .brightnessOnly)
        editorState.load(alarm: alarm, availableAccessories: [newAccessory])

        // Act
        let isValid = editorState.validate()

        // Assert
        XCTAssertFalse(isValid)
        XCTAssertNotNil(editorState.validation.invalidatedAccessoryError)
    }

    func testValidate_InvalidatedAccessoryError_ContainsCount() {
        // Arrange
        let alarm = WakeAlarm(
            name: "Test Alarm",
            wakeTimeSeconds: 7 * 3600,
            selectedAccessoryIdentifiers: ["old-acc-1", "old-acc-2", "old-acc-3"],
            homeIdentifier: "test-home"
        )

        let newAccessory = createAccessory(id: "new-acc", name: "New Light", capability: .brightnessOnly)
        editorState.load(alarm: alarm, availableAccessories: [newAccessory])

        // Act
        _ = editorState.validate()

        // Assert
        XCTAssertEqual(
            editorState.validation.invalidatedAccessoryError,
            "3 previously selected lights are no longer available. Please reselect."
        )
    }

    func testLoad_PreservesAllAlarmConfiguration() {
        // Arrange
        let alarm = WakeAlarm(
            name: "Test Alarm",
            wakeTimeSeconds: 7 * 3600 + 30 * 60,
            durationMinutes: 45,
            gradientCurve: .easeIn,
            colorMode: .fullColor,
            startBrightness: 5,
            targetBrightness: 95,
            targetColorTemperature: nil,
            targetHue: 30,
            targetSaturation: 80,
            isEnabled: false,
            selectedAccessoryIdentifiers: ["acc-1"],
            homeIdentifier: "test-home"
        )

        let accessory = createAccessory(id: "acc-1", name: "Light", capability: .fullColor)

        // Act
        editorState.load(alarm: alarm, availableAccessories: [accessory])

        // Assert
        XCTAssertEqual(editorState.editingAlarmId, alarm.id)
        XCTAssertEqual(editorState.alarmName, "Test Alarm")
        XCTAssertEqual(editorState.durationMinutes, 45)
        XCTAssertEqual(editorState.gradientCurve, .easeIn)
        XCTAssertEqual(editorState.colorMode, .fullColor)
        XCTAssertEqual(editorState.startBrightness, 5)
        XCTAssertEqual(editorState.targetBrightness, 95)
        XCTAssertEqual(editorState.targetHue, 30)
        XCTAssertEqual(editorState.targetSaturation, 80)
        XCTAssertEqual(editorState.isEnabled, false)
    }

    func testValidate_ClearingInvalidatedAccessoryBySelectingNewOne_ClearsError() {
        // Arrange
        let alarm = WakeAlarm(
            name: "Test Alarm",
            wakeTimeSeconds: 7 * 3600,
            selectedAccessoryIdentifiers: ["old-acc"],
            homeIdentifier: "test-home"
        )

        let newAccessory = createAccessory(id: "new-acc", name: "New Light", capability: .brightnessOnly)
        editorState.load(alarm: alarm, availableAccessories: [newAccessory])
        _ = editorState.validate()
        XCTAssertNotNil(editorState.validation.invalidatedAccessoryError)

        // Act - Select a new accessory
        editorState.selectedAccessoryIds = ["new-acc"]

        // Assert - Error is cleared
        XCTAssertNil(editorState.validation.invalidatedAccessoryError)
    }

    // MARK: - Validation State Tests

    func testValidationStateAllErrors_CollectsAllErrors() {
        // Arrange
        let validation = AlarmEditorValidationState(
            nameError: "Name error",
            accessoryError: "Accessory error",
            brightnessError: nil,
            durationError: "Duration error",
            colorError: nil,
            invalidatedAccessoryError: nil
        )

        // Act
        let errors = validation.allErrors

        // Assert
        XCTAssertEqual(errors.count, 3)
        XCTAssertTrue(errors.contains("Name error"))
        XCTAssertTrue(errors.contains("Accessory error"))
        XCTAssertTrue(errors.contains("Duration error"))
    }

    func testValidationStateHasErrors_WithAnyError_ReturnsTrue() {
        // Arrange
        let validation = AlarmEditorValidationState(
            nameError: nil,
            accessoryError: "Accessory error",
            brightnessError: nil,
            durationError: nil,
            colorError: nil,
            invalidatedAccessoryError: nil
        )

        // Assert
        XCTAssertTrue(validation.hasErrors)
    }

    func testValidationStateHasErrors_NoErrors_ReturnsFalse() {
        // Arrange
        let validation = AlarmEditorValidationState.empty

        // Assert
        XCTAssertFalse(validation.hasErrors)
    }
}

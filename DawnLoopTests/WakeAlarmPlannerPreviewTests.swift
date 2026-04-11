import XCTest
@testable import DawnLoop

/// Tests for WakeAlarmPlanner preview generation
/// Validates VAL-ALARM-003 (gradient curve changes preview) and VAL-ALARM-004 (valid state only)
@MainActor
final class WakeAlarmPlannerPreviewTests: XCTestCase {

    var editorState: AlarmEditorState!

    override func setUp() async throws {
        editorState = AlarmEditorState()
    }

    override func tearDown() async throws {
        editorState = nil
    }

    // MARK: - Helper Methods

    private func createAccessory(
        id: String,
        name: String,
        capability: AccessoryCapability,
        roomName: String = "Test Room"
    ) -> AccessoryViewModel {
        // Preserve requested capability to properly test mixed-capability behavior (VAL-ALARM-004)
        return AccessoryViewModel(
            from: AccessoryReference(
                homeKitIdentifier: id,
                name: name,
                homeIdentifier: "test-home",
                roomName: roomName,
                capability: capability
            )
        )
    }

    private func setupValidEditorState() {
        editorState.alarmName = "Test Alarm"
        editorState.durationMinutes = 30
        editorState.startBrightness = 0
        editorState.targetBrightness = 100
        editorState.selectedAccessoryIds = ["acc-1"]
        editorState.availableAccessories = [
            createAccessory(id: "acc-1", name: "Test Light", capability: .brightnessOnly)
        ]
    }

    // MARK: - VAL-ALARM-003: Gradient curve changes the preview plan

    func testGradientCurve_Linear_ProducesDifferentStepsThanEaseIn() {
        // Arrange - Setup valid state with linear curve
        setupValidEditorState()
        editorState.gradientCurve = .linear
        editorState.regeneratePreview()

        let linearSteps = editorState.previewSteps
        XCTAssertFalse(linearSteps.isEmpty, "Preview should generate steps")

        // Act - Change to easeIn
        editorState.gradientCurve = .easeIn
        editorState.regeneratePreview()

        let easeInSteps = editorState.previewSteps
        XCTAssertFalse(easeInSteps.isEmpty, "Preview should generate steps")

        // Assert - Different curves should produce different step distributions
        // At least some timestamps should differ
        let linearTimestamps = linearSteps.map { $0.timestamp }
        let easeInTimestamps = easeInSteps.map { $0.timestamp }
        XCTAssertNotEqual(linearTimestamps, easeInTimestamps, "Linear and easeIn should produce different step timing")
    }

    func testGradientCurve_EaseOut_ProducesDifferentStepsThanEaseInOut() {
        // Arrange - Setup valid state
        setupValidEditorState()
        editorState.gradientCurve = .easeOut
        editorState.regeneratePreview()

        let easeOutSteps = editorState.previewSteps

        // Act - Change to easeInOut
        editorState.gradientCurve = .easeInOut
        editorState.regeneratePreview()

        let easeInOutSteps = editorState.previewSteps

        // Assert - Different curves should produce different timing
        let easeOutTimestamps = easeOutSteps.map { $0.timestamp }
        let easeInOutTimestamps = easeInOutSteps.map { $0.timestamp }
        XCTAssertNotEqual(easeOutTimestamps, easeInOutTimestamps, "EaseOut and easeInOut should produce different step timing")
    }

    func testGradientCurve_Change_UpdatesPreviewAutomatically() {
        // Arrange - Start with linear
        setupValidEditorState()
        editorState.gradientCurve = .linear
        editorState.regeneratePreview()
        let initialFirstStepBrightness = editorState.previewSteps.first?.brightness

        // Act - Change curve and regenerate
        editorState.gradientCurve = .easeInOut
        editorState.regeneratePreview()

        // Assert - Preview should be updated with new curve
        // The step timing will be different even if brightness range is same
        XCTAssertEqual(editorState.previewSteps.first?.brightness, initialFirstStepBrightness,
                      "First step brightness should remain start brightness regardless of curve")
        XCTAssertEqual(editorState.previewSteps.last?.brightness, 100,
                      "Last step should reach target brightness")
    }

    func testGradientCurve_AllCurves_ProduceValidStepCount() {
        // Arrange
        setupValidEditorState()
        let curves: [GradientCurve] = [.linear, .easeIn, .easeOut, .easeInOut]

        for curve in curves {
            // Act
            editorState.gradientCurve = curve
            editorState.regeneratePreview()

            // Assert
            XCTAssertEqual(editorState.previewSteps.count, WakeAlarmStepPlanner.defaultStepCount,
                          "Curve \(curve) should produce \(WakeAlarmStepPlanner.defaultStepCount) steps")
        }
    }

    func testPreview_CustomStepCount_ProducesRequestedNumberOfSteps() {
        setupValidEditorState()
        editorState.durationMinutes = 24
        editorState.stepCount = 24

        editorState.regeneratePreview()

        XCTAssertEqual(editorState.previewSteps.count, 24)
    }

    // MARK: - VAL-STEP-001: Selected custom step count survives create/edit paths and preserves preview endpoints

    func testStepCount_SurvivesCreateAlarm() {
        // Arrange
        setupValidEditorState()
        editorState.stepCount = 20
        editorState.startBrightness = 5
        editorState.targetBrightness = 95

        // Act
        let alarm = editorState.createAlarm()

        // Assert
        XCTAssertNotNil(alarm)
        XCTAssertEqual(alarm?.stepCount, 20)
    }

    func testStepCount_LoadExistingAlarm_PreservesCustomStepCount() {
        // Arrange - Create alarm with custom step count
        let alarm = WakeAlarm(
            name: "Dense Alarm",
            wakeTimeSeconds: 7 * 3600,
            durationMinutes: 25,
            stepCount: 25,
            startBrightness: 0,
            targetBrightness: 100,
            selectedAccessoryIdentifiers: ["acc-1"],
            homeIdentifier: "test-home"
        )

        let accessory = createAccessory(id: "acc-1", name: "Test Light", capability: .brightnessOnly)

        // Act
        editorState.load(alarm: alarm, availableAccessories: [accessory])

        // Assert
        XCTAssertEqual(editorState.stepCount, 25)
    }

    func testPreview_PreservesExactEndpoints() {
        // Arrange
        setupValidEditorState()
        editorState.startBrightness = 10
        editorState.targetBrightness = 90
        editorState.stepCount = 15

        // Act
        editorState.regeneratePreview()

        // Assert - First and last steps should match configured endpoints exactly
        XCTAssertEqual(editorState.previewSteps.first?.brightness, 10,
                      "First step brightness should match configured start brightness")
        XCTAssertEqual(editorState.previewSteps.last?.brightness, 90,
                      "Last step brightness should match configured target brightness")
    }

    // MARK: - VAL-STEP-002: Dense ramps redistribute brightness across the full configured range

    func testDenseRamp_RedistributesBrightness_StrictlyIncreasingSequence() {
        // Arrange - Dense fixture: 20 steps with 0-100 brightness range (enough for unique values)
        // Use linear curve for predictable linear redistribution
        setupValidEditorState()
        editorState.gradientCurve = .linear  // Linear ensures even redistribution
        editorState.durationMinutes = 24  // Supports up to 24 steps
        editorState.stepCount = 20  // Dense: >10 steps
        editorState.startBrightness = 0
        editorState.targetBrightness = 100  // Full range: 100 units

        // Act
        editorState.regeneratePreview()

        // Assert
        let steps = editorState.previewSteps
        XCTAssertEqual(steps.count, 20, "Should produce exactly 20 steps")

        // Verify strictly increasing brightness sequence (linear curve ensures this)
        var previousBrightness = -1
        for (index, step) in steps.enumerated() {
            XCTAssertGreaterThan(step.brightness, previousBrightness,
                               "Step \(index) brightness (\(step.brightness)) should be greater than previous (\(previousBrightness))")
            previousBrightness = step.brightness
        }

        // Verify endpoints are preserved
        XCTAssertEqual(steps.first?.brightness, 0, "First step should be at minimum brightness")
        XCTAssertEqual(steps.last?.brightness, 100, "Last step should be at maximum brightness")
    }

    func testDenseRamp_WithNarrowRange_StillRedistributes() {
        // Arrange - 15 steps with 10-30 brightness range (20 units, less than step count)
        setupValidEditorState()
        editorState.durationMinutes = 20
        editorState.stepCount = 15
        editorState.startBrightness = 10
        editorState.targetBrightness = 30

        // Act
        editorState.regeneratePreview()

        // Assert
        let steps = editorState.previewSteps
        XCTAssertEqual(steps.count, 15)

        // Verify monotonic non-decreasing (may have duplicates with narrow range)
        var previousBrightness = -1
        for (index, step) in steps.enumerated() {
            XCTAssertGreaterThanOrEqual(step.brightness, previousBrightness,
                                      "Step \(index) should not decrease brightness")
            previousBrightness = step.brightness
        }

        // Endpoints preserved
        XCTAssertEqual(steps.first?.brightness, 10)
        XCTAssertEqual(steps.last?.brightness, 30)
    }

    // MARK: - VAL-STEP-003: Density guardrails still apply after redistribution

    func testStepCount_DurationClamping_LimitsToOnePerMinute() {
        // Arrange - 10 minute duration should clamp to max 10 steps
        setupValidEditorState()
        editorState.durationMinutes = 10
        editorState.stepCount = 30  // Try to set more than duration allows

        // Assert - stepCount should be clamped
        XCTAssertEqual(editorState.stepCount, 10,
                      "Step count should be clamped to duration (1 per minute)")
        XCTAssertEqual(editorState.maxStepCount, 10)
    }

    func testStepCount_GlobalCapOf30Preserved() {
        // Arrange - 60 minute duration supports 60 steps, but global cap is 30
        setupValidEditorState()
        editorState.durationMinutes = 60
        editorState.stepCount = 35  // Try to exceed global cap

        // Assert - stepCount should be clamped to global max
        XCTAssertEqual(editorState.stepCount, 30,
                      "Step count should be clamped to global maximum of 30")
        XCTAssertEqual(editorState.maxStepCount, 30)
    }

    func testDurationReduction_AutoClampsStepCount() {
        // Arrange - Start with longer duration
        setupValidEditorState()
        editorState.durationMinutes = 30
        editorState.stepCount = 25
        XCTAssertEqual(editorState.stepCount, 25)

        // Act - Reduce duration
        editorState.durationMinutes = 15

        // Assert - Step count auto-clamped
        XCTAssertEqual(editorState.stepCount, 15,
                      "Step count should auto-clamp when duration is reduced")
    }

    // MARK: - VAL-ALARM-004: Preview only runs from valid editor state

    func testPreview_InvalidState_NoName_NoPreviewGenerated() {
        // Arrange - Missing name
        editorState.alarmName = ""
        editorState.selectedAccessoryIds = ["acc-1"]
        editorState.availableAccessories = [
            createAccessory(id: "acc-1", name: "Test Light", capability: .brightnessOnly)
        ]

        // Act
        editorState.regeneratePreview()

        // Assert
        XCTAssertTrue(editorState.previewSteps.isEmpty, "Preview should be empty when name is missing")
        XCTAssertNil(editorState.currentPreview, "Current preview should be nil when invalid")
    }

    func testPreview_InvalidState_NoAccessories_NoPreviewGenerated() {
        // Arrange - Missing accessories
        editorState.alarmName = "Test Alarm"
        editorState.selectedAccessoryIds = []

        // Act
        editorState.regeneratePreview()

        // Assert
        XCTAssertTrue(editorState.previewSteps.isEmpty, "Preview should be empty when no accessories selected")
        XCTAssertNil(editorState.currentPreview, "Current preview should be nil when invalid")
    }

    func testPreview_ValidState_GeneratesPreview() {
        // Arrange
        setupValidEditorState()

        // Act
        editorState.regeneratePreview()

        // Assert
        XCTAssertFalse(editorState.previewSteps.isEmpty, "Preview should generate steps for valid state")
        XCTAssertNotNil(editorState.currentPreview, "Current preview should exist for valid state")
    }

    func testPreview_TransitionFromInvalidToValid_GeneratesPreview() {
        // Arrange - Start invalid
        editorState.alarmName = ""
        editorState.selectedAccessoryIds = []
        editorState.regeneratePreview()
        XCTAssertTrue(editorState.previewSteps.isEmpty)

        // Act - Make valid
        editorState.alarmName = "Test Alarm"
        editorState.selectedAccessoryIds = ["acc-1"]
        editorState.availableAccessories = [
            createAccessory(id: "acc-1", name: "Test Light", capability: .brightnessOnly)
        ]
        editorState.regeneratePreview()

        // Assert
        XCTAssertFalse(editorState.previewSteps.isEmpty, "Preview should generate after becoming valid")
    }

    func testCanGeneratePreview_ValidState_ReturnsTrue() {
        // Arrange
        setupValidEditorState()

        // Assert
        XCTAssertTrue(editorState.canGeneratePreview, "Should be able to generate preview with valid state")
    }

    func testCanGeneratePreview_MissingName_ReturnsFalse() {
        // Arrange
        editorState.alarmName = ""
        editorState.selectedAccessoryIds = ["acc-1"]

        // Assert
        XCTAssertFalse(editorState.canGeneratePreview, "Should not generate preview without name")
    }

    func testCanGeneratePreview_MissingAccessories_ReturnsFalse() {
        // Arrange
        editorState.alarmName = "Test Alarm"
        editorState.selectedAccessoryIds = []

        // Assert
        XCTAssertFalse(editorState.canGeneratePreview, "Should not generate preview without accessories")
    }

    // MARK: - VAL-ALARM-004: Mixed capabilities produce degradation messaging

    func testPreview_MixedCapabilities_ShowsDegradation() {
        // Arrange
        editorState.alarmName = "Test Alarm"
        editorState.selectedAccessoryIds = ["acc-1", "acc-2"]
        editorState.availableAccessories = [
            createAccessory(id: "acc-1", name: "Basic Light", capability: .brightnessOnly),
            createAccessory(id: "acc-2", name: "Warm Light", capability: .tunableWhite)
        ]
        editorState.colorMode = .colorTemperature
        editorState.targetColorTemperature = 220

        // Act
        editorState.regeneratePreview()

        // Assert
        XCTAssertNotNil(editorState.previewDegradationExplanation,
                       "Should show degradation explanation for mixed capabilities")
        XCTAssertTrue(editorState.previewHasMixedCapabilities,
                     "Should indicate mixed capabilities in preview")
    }

    func testPreview_SameCapabilities_NoDegradation() {
        // Arrange - All same capability
        editorState.alarmName = "Test Alarm"
        editorState.selectedAccessoryIds = ["acc-1", "acc-2"]
        editorState.availableAccessories = [
            createAccessory(id: "acc-1", name: "Color Light 1", capability: .fullColor),
            createAccessory(id: "acc-2", name: "Color Light 2", capability: .fullColor)
        ]
        editorState.colorMode = .fullColor

        // Act
        editorState.regeneratePreview()

        // Assert
        XCTAssertNil(editorState.previewDegradationExplanation,
                    "Should not show degradation when all accessories support the mode")
        XCTAssertFalse(editorState.previewHasMixedCapabilities,
                      "Should not indicate mixed capabilities when all same")
    }
}

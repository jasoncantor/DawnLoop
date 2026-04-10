import XCTest
@testable import DawnLoop

/// Tests for WakeAlarmPlanner preview generation
/// Validates VAL-ALARM-003 (gradient curve changes preview) and VAL-ALARM-004 (valid state only)
@MainActor
final class WakeAlarmPlannerPreviewTests: XCTestCase {

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

import Foundation
import SwiftUI
import SwiftData

/// Validation state for the alarm editor form
/// Tracks field-level validation errors to support VAL-ALARM-001
struct AlarmEditorValidationState: Equatable, Sendable {
    var nameError: String?
    var accessoryError: String?
    var brightnessError: String?
    var durationError: String?
    var colorError: String?
    var invalidatedAccessoryError: String?

    var hasErrors: Bool {
        nameError != nil ||
        accessoryError != nil ||
        brightnessError != nil ||
        durationError != nil ||
        colorError != nil ||
        invalidatedAccessoryError != nil
    }

    var isValid: Bool {
        !hasErrors
    }

    static let empty = AlarmEditorValidationState()

    /// Returns all error messages as an array
    var allErrors: [String] {
        var errors: [String] = []
        if let error = nameError { errors.append(error) }
        if let error = accessoryError { errors.append(error) }
        if let error = brightnessError { errors.append(error) }
        if let error = durationError { errors.append(error) }
        if let error = colorError { errors.append(error) }
        if let error = invalidatedAccessoryError { errors.append(error) }
        return errors
    }
}

/// Represents the editable state of an alarm in the editor
/// Preserves user inputs even when validation fails (VAL-ALARM-001)
@Observable
@MainActor
final class AlarmEditorState {
    // MARK: - Form Fields

    var alarmName: String = "" {
        didSet { clearValidationError(for: \.alarmName) }
    }

    var wakeTime: Date = Date() {
        didSet { clearValidationError(for: \.wakeTime) }
    }

    var timeReference: AlarmTimeReference = .clock {
        didSet {
            if timeReference == .clock {
                timeOffsetMinutes = 0
            }
            clearValidationError(for: \.timeReference)
        }
    }

    var timeOffsetMinutes: Int = 0 {
        didSet { clearValidationError(for: \.timeOffsetMinutes) }
    }

    var durationMinutes: Int = 30 {
        didSet {
            clampStepCount()
            clearValidationError(for: \.durationMinutes)
        }
    }

    var stepCount: Int = WakeAlarmStepPlanner.defaultStepCount {
        didSet {
            clampStepCount()
            clearValidationError(for: \.stepCount)
        }
    }

    var gradientCurve: GradientCurve = .easeInOut {
        didSet { clearValidationError(for: \.gradientCurve) }
    }

    var colorMode: AlarmColorMode = .brightnessOnly {
        didSet { clearValidationError(for: \.colorMode) }
    }

    var startBrightness: Int = 0 {
        didSet { clearValidationError(for: \.startBrightness) }
    }

    var targetBrightness: Int = 100 {
        didSet { clearValidationError(for: \.targetBrightness) }
    }

    var targetColorTemperature: Int? = nil {
        didSet { clearValidationError(for: \.targetColorTemperature) }
    }

    var targetHue: Int? = nil {
        didSet { clearValidationError(for: \.targetHue) }
    }

    var targetSaturation: Int? = nil {
        didSet { clearValidationError(for: \.targetSaturation) }
    }

    var selectedAccessoryIds: Set<String> = [] {
        didSet { clearValidationError(for: \.selectedAccessoryIds) }
    }

    var repeatSchedule: WeekdaySchedule = .never

    var isEnabled: Bool = true

    var maxStepCount: Int {
        WakeAlarmStepPlanner.maxStepCount(forDurationMinutes: durationMinutes)
    }

    var stepDensityDescription: String {
        let minutesPerStep = Double(durationMinutes) / Double(max(stepCount, 1))
        if minutesPerStep <= 1.05 {
            return "About 1 step per minute"
        }
        return String(format: "About 1 step every %.1f minutes", minutesPerStep)
    }

    // MARK: - Validation State

    var validation = AlarmEditorValidationState.empty

    // MARK: - Editor Mode

    var editingAlarmId: UUID?
    var isEditing: Bool { editingAlarmId != nil }

    // MARK: - Accessory State

    var availableAccessories: [AccessoryViewModel] = []
    var invalidatedAccessoryIds: Set<String> = []

    // MARK: - Capability Detection

    var selectedCapabilities: [AccessoryCapability] {
        availableAccessories
            .filter { selectedAccessoryIds.contains($0.homeKitIdentifier) }
            .map { $0.capability }
    }

    var canShowColorTemperature: Bool {
        // Show if at least one selected accessory supports color temperature (VAL-ALARM-002)
        selectedCapabilities.contains { $0.supportsColorTemperature }
    }

    var canShowFullColor: Bool {
        // Show if at least one selected accessory supports hue/saturation (VAL-ALARM-002)
        selectedCapabilities.contains { $0.supportsHueSaturation }
    }

    var hasMixedCapabilities: Bool {
        let caps = selectedCapabilities
        let hasBrightnessOnly = caps.contains { $0 == .brightnessOnly }
        let hasTunableWhite = caps.contains { $0 == .tunableWhite }
        let hasFullColor = caps.contains { $0 == .fullColor }
        return (hasBrightnessOnly ? 1 : 0) + (hasTunableWhite ? 1 : 0) + (hasFullColor ? 1 : 0) > 1
    }

    var degradationExplanation: String? {
        guard hasMixedCapabilities else { return nil }

        let caps = selectedCapabilities
        let hasBrightnessOnly = caps.contains { $0 == .brightnessOnly }
        let hasTunableWhite = caps.contains { $0 == .tunableWhite }
        let hasFullColor = caps.contains { $0 == .fullColor }

        switch colorMode {
        case .brightnessOnly:
            return nil
        case .colorTemperature:
            if hasBrightnessOnly {
                return "Some lights will use brightness only."
            }
            return nil
        case .fullColor:
            if hasBrightnessOnly && hasTunableWhite {
                return "Some lights will use brightness or warm light instead of full color."
            } else if hasBrightnessOnly {
                return "Some lights will use brightness only."
            } else if hasTunableWhite {
                return "Some lights will use warm light instead of full color."
            }
            return nil
        }
    }

    // MARK: - Validation

    /// Validates the form and returns whether it's valid
    /// Preserves entered values even when validation fails (VAL-ALARM-001)
    func validate() -> Bool {
        var newValidation = AlarmEditorValidationState()

        // Validate name
        if alarmName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newValidation.nameError = "Alarm name is required"
        } else if alarmName.count > 50 {
            newValidation.nameError = "Alarm name must be 50 characters or less"
        }

        // Validate accessory selection
        if selectedAccessoryIds.isEmpty {
            newValidation.accessoryError = "Select at least one light"
        }

        // Validate invalidated accessories (VAL-ALARM-008)
        if !invalidatedAccessoryIds.isEmpty {
            let count = invalidatedAccessoryIds.count
            newValidation.invalidatedAccessoryError = count == 1
                ? "One previously selected light is no longer available. Please reselect."
                : "\(count) previously selected lights are no longer available. Please reselect."
        }

        // Validate brightness values
        if startBrightness < 0 || startBrightness > 100 {
            newValidation.brightnessError = "Start brightness must be between 0 and 100"
        } else if targetBrightness < 0 || targetBrightness > 100 {
            newValidation.brightnessError = "Target brightness must be between 0 and 100"
        } else if startBrightness >= targetBrightness {
            newValidation.brightnessError = "Target brightness must be higher than start brightness"
        }

        // Validate duration
        if durationMinutes < 1 {
            newValidation.durationError = "Duration must be at least 1 minute"
        } else if durationMinutes > 120 {
            newValidation.durationError = "Duration must be 2 hours or less"
        }

        // Validate color values based on mode
        switch colorMode {
        case .colorTemperature:
            if let temp = targetColorTemperature {
                // Color temperature in mireds typically ranges from 153 (6500K) to 454 (2200K)
                if temp < 153 || temp > 454 {
                    newValidation.colorError = "Color temperature must be between 153 and 454 mireds"
                }
            } else {
                newValidation.colorError = "Color temperature is required for this mode"
            }

        case .fullColor:
            if let hue = targetHue {
                if hue < 0 || hue > 360 {
                    newValidation.colorError = "Hue must be between 0 and 360"
                }
            } else {
                newValidation.colorError = "Hue is required for full color mode"
            }

            if let sat = targetSaturation {
                if sat < 0 || sat > 100 {
                    newValidation.colorError = "Saturation must be between 0 and 100"
                }
            } else {
                newValidation.colorError = "Saturation is required for full color mode"
            }

        case .brightnessOnly:
            break
        }

        validation = newValidation
        return newValidation.isValid
    }

    /// Clears validation error for a specific field when it changes
    private func clearValidationError<T>(for keyPath: KeyPath<AlarmEditorState, T>) {
        switch keyPath {
        case \.alarmName:
            if validation.nameError != nil {
                validation.nameError = nil
            }
        case \.selectedAccessoryIds:
            if validation.accessoryError != nil || validation.invalidatedAccessoryError != nil {
                validation.accessoryError = nil
                validation.invalidatedAccessoryError = nil
            }
        case \.startBrightness, \.targetBrightness:
            if validation.brightnessError != nil {
                validation.brightnessError = nil
            }
        case \.durationMinutes:
            if validation.durationError != nil {
                validation.durationError = nil
            }
        case \.stepCount:
            break
        case \.colorMode, \.targetColorTemperature, \.targetHue, \.targetSaturation:
            if validation.colorError != nil {
                validation.colorError = nil
            }
        default:
            break
        }
    }

    private func clampStepCount() {
        let clamped = min(max(stepCount, 1), maxStepCount)
        if stepCount != clamped {
            stepCount = clamped
        }
    }

    // MARK: - Initialization

    init() {
        // Set default wake time to 7:00 AM
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 7
        components.minute = 0
        components.second = 0
        self.wakeTime = calendar.date(from: components) ?? Date()
    }

    // MARK: - Load/Save

    /// Loads an existing alarm into the editor state
    /// Checks for invalidated accessories (VAL-ALARM-008)
    func load(
        alarm: WakeAlarm,
        availableAccessories: [AccessoryViewModel],
        schedule: WeekdaySchedule = .never
    ) {
        self.editingAlarmId = alarm.id
        self.alarmName = alarm.name
        self.durationMinutes = alarm.durationMinutes
        self.gradientCurve = alarm.gradientCurve
        self.colorMode = alarm.colorMode
        self.startBrightness = alarm.startBrightness
        self.targetBrightness = alarm.targetBrightness
        self.targetColorTemperature = alarm.targetColorTemperature
        self.targetHue = alarm.targetHue
        self.targetSaturation = alarm.targetSaturation
        self.isEnabled = alarm.isEnabled
        self.repeatSchedule = schedule
        self.availableAccessories = availableAccessories
        self.timeReference = alarm.timeReference
        self.timeOffsetMinutes = alarm.timeOffsetMinutes
        self.stepCount = alarm.stepCount

        // Set wake time
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        let hours = alarm.wakeTimeSeconds / 3600
        let minutes = (alarm.wakeTimeSeconds % 3600) / 60
        components.hour = hours
        components.minute = minutes
        components.second = 0
        self.wakeTime = calendar.date(from: components) ?? Date()

        // Check for invalidated accessories (VAL-ALARM-008)
        let availableIds = Set(availableAccessories.map { $0.homeKitIdentifier })
        let storedIds = alarm.selectedAccessoryIdentifiers

        // Find accessories that are selected but no longer available
        self.invalidatedAccessoryIds = Set(storedIds).subtracting(availableIds)

        // Only pre-select accessories that are still valid
        let validSelectedIds = Set(storedIds).intersection(availableIds)
        self.selectedAccessoryIds = validSelectedIds

        // Run validation to show invalidated accessory warnings
        _ = validate()
    }

    /// Creates a new alarm from the current editor state
    func createAlarm() -> WakeAlarm? {
        guard validate() else { return nil }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: wakeTime)
        let wakeTimeSeconds = (components.hour ?? 7) * 3600 + (components.minute ?? 0) * 60

        return WakeAlarm(
            id: editingAlarmId ?? UUID(),
            name: alarmName.trimmingCharacters(in: .whitespacesAndNewlines),
            wakeTimeSeconds: wakeTimeSeconds,
            timeReference: timeReference,
            timeOffsetMinutes: timeOffsetMinutes,
            durationMinutes: durationMinutes,
            stepCount: stepCount,
            gradientCurve: gradientCurve,
            colorMode: colorMode,
            startBrightness: startBrightness,
            targetBrightness: targetBrightness,
            targetColorTemperature: targetColorTemperature,
            targetHue: targetHue,
            targetSaturation: targetSaturation,
            isEnabled: isEnabled,
            selectedAccessoryIdentifiers: Array(selectedAccessoryIds),
            homeIdentifier: nil // Set by caller
        )
    }

    /// Resets the editor to default state
    func reset() {
        self.editingAlarmId = nil
        self.alarmName = ""
        self.durationMinutes = 30
        self.timeReference = .clock
        self.timeOffsetMinutes = 0
        self.stepCount = WakeAlarmStepPlanner.defaultStepCount
        self.gradientCurve = .easeInOut
        self.colorMode = .brightnessOnly
        self.startBrightness = 0
        self.targetBrightness = 100
        self.targetColorTemperature = nil
        self.targetHue = nil
        self.targetSaturation = nil
        self.isEnabled = true
        self.repeatSchedule = .never
        self.selectedAccessoryIds = []
        self.availableAccessories = []
        self.invalidatedAccessoryIds = []
        self.validation = .empty

        // Reset wake time to 7:00 AM
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 7
        components.minute = 0
        components.second = 0
        self.wakeTime = calendar.date(from: components) ?? Date()

        // Clear preview on reset
        self.currentPreview = nil
    }

    // MARK: - Preview Section

    /// The current preview plan based on editor inputs
    /// Only valid when the editor state passes validation (VAL-ALARM-004)
    var currentPreview: CapabilityAwarePlan?

    /// Whether the editor is in a valid state for preview generation
    /// Preview is blocked from all invalid editor states including:
    /// - Invalid brightness relationships (start >= target)
    /// - Invalid duration or color values
    /// - Invalidated accessories (VAL-ALARM-004)
    var canGeneratePreview: Bool {
        // Basic requirements: name and accessories
        guard !selectedAccessoryIds.isEmpty && !alarmName.isEmpty else {
            return false
        }

        // Must pass all validation checks
        // Block preview if any validation errors exist
        if !validation.isValid {
            return false
        }

        // Additional explicit validation for preview safety
        // Validate brightness relationship
        if startBrightness >= targetBrightness {
            return false
        }

        // Validate duration bounds
        if durationMinutes < 1 || durationMinutes > 120 {
            return false
        }

        // Validate color mode requirements
        switch colorMode {
        case .colorTemperature:
            if let temp = targetColorTemperature {
                if temp < 153 || temp > 454 {
                    return false
                }
            } else {
                return false
            }
        case .fullColor:
            if targetHue == nil || targetSaturation == nil {
                return false
            }
            if let hue = targetHue, hue < 0 || hue > 360 {
                return false
            }
            if let sat = targetSaturation, sat < 0 || sat > 100 {
                return false
            }
        case .brightnessOnly:
            break
        }

        return true
    }

    /// The preview steps to display (empty if invalid state)
    var previewSteps: [WakeAlarmStep] {
        currentPreview?.steps ?? []
    }

    /// Degradation explanation from the preview plan
    var previewDegradationExplanation: String? {
        currentPreview?.degradation.explanation
    }

    /// Whether the preview shows mixed capability behavior
    var previewHasMixedCapabilities: Bool {
        currentPreview?.hasMixedCapabilities ?? false
    }

    // MARK: - Preview Generation

    /// Regenerates the preview plan based on current editor inputs
    /// Only generates from valid state - invalid states clear the preview (VAL-ALARM-004)
    func regeneratePreview() {
        // Only generate preview from valid state
        guard canGeneratePreview else {
            currentPreview = nil
            return
        }

        // Get capabilities of selected accessories
        let selectedAccessories = availableAccessories.filter {
            selectedAccessoryIds.contains($0.homeKitIdentifier)
        }
        let capabilities = selectedAccessories.map { $0.capability }

        // Create a temporary alarm for planning
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: wakeTime)
        let wakeTimeSeconds = (components.hour ?? 7) * 3600 + (components.minute ?? 0) * 60

        let tempAlarm = WakeAlarm(
            id: UUID(),
            name: alarmName,
            wakeTimeSeconds: wakeTimeSeconds,
            timeReference: timeReference,
            timeOffsetMinutes: timeOffsetMinutes,
            durationMinutes: durationMinutes,
            stepCount: stepCount,
            gradientCurve: gradientCurve,
            colorMode: colorMode,
            startBrightness: startBrightness,
            targetBrightness: targetBrightness,
            targetColorTemperature: targetColorTemperature,
            targetHue: targetHue,
            targetSaturation: targetSaturation,
            isEnabled: isEnabled,
            selectedAccessoryIdentifiers: Array(selectedAccessoryIds),
            homeIdentifier: nil
        )

        // Generate capability-aware plan
        currentPreview = WakeAlarmStepPlanner.planSteps(
            for: tempAlarm,
            capabilities: capabilities,
            stepCount: stepCount
        )
    }

    /// Clears the current preview
    func clearPreview() {
        currentPreview = nil
    }
}

// MARK: - Preview Support

extension AlarmEditorState {
    /// Creates a preview state with sample data
    static func previewState() -> AlarmEditorState {
        let state = AlarmEditorState()
        state.alarmName = "Morning Alarm"
        state.availableAccessories = [
            AccessoryViewModel(
                from: AccessoryReference(
                    homeKitIdentifier: "acc-1",
                    name: "Bedroom Light",
                    roomName: "Bedroom",
                    homeIdentifier: "home-1",
                    isCompatible: true
                )
            ),
            AccessoryViewModel(
                from: AccessoryReference(
                    homeKitIdentifier: "acc-2",
                    name: "Living Room Light",
                    roomName: "Living Room",
                    homeIdentifier: "home-1",
                    isCompatible: true
                )
            )
        ]
        state.selectedAccessoryIds = ["acc-1"]
        return state
    }
}

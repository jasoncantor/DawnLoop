import SwiftData
import Foundation

/// Gradient curve type for the sunrise transition
enum GradientCurve: String, Codable, Sendable, CaseIterable {
    case linear = "linear"
    case easeIn = "ease_in"
    case easeOut = "ease_out"
    case easeInOut = "ease_in_out"

    var displayName: String {
        switch self {
        case .linear:
            return "Linear"
        case .easeIn:
            return "Ease In"
        case .easeOut:
            return "Ease Out"
        case .easeInOut:
            return "Ease In-Out"
        }
    }
}

/// Represents the color mode for the alarm
enum AlarmColorMode: String, Codable, Sendable, CaseIterable {
    case brightnessOnly = "brightness_only"
    case colorTemperature = "color_temperature"
    case fullColor = "full_color"

    var displayName: String {
        switch self {
        case .brightnessOnly:
            return "Brightness Only"
        case .colorTemperature:
            return "Warm Light"
        case .fullColor:
            return "Full Color"
        }
    }
}

/// Persistent model for a wake alarm
/// Stores all alarm configuration and maintains identity across edits (VAL-ALARM-007)
@Model
final class WakeAlarm: @unchecked Sendable {
    /// Unique identifier for the alarm - stable across edits
    @Attribute(.unique) var id: UUID

    /// Display name for the alarm
    var name: String

    /// Target wake time (stored as seconds from midnight for consistency)
    var wakeTimeSeconds: Int

    /// Duration of the sunrise ramp in minutes
    var durationMinutes: Int

    /// Gradient curve for the transition
    var gradientCurveRaw: String

    /// Color mode for the alarm
    var colorModeRaw: String

    /// Start brightness (0-100)
    var startBrightness: Int

    /// Target brightness (0-100)
    var targetBrightness: Int

    /// Optional color temperature in mireds (for tunable white)
    var targetColorTemperature: Int?

    /// Optional hue for full color mode (0-360)
    var targetHue: Int?

    /// Optional saturation for full color mode (0-100)
    var targetSaturation: Int?

    /// Whether the alarm is currently enabled
    /// This is independent of other alarm settings (VAL-ALARM-006)
    var isEnabled: Bool

    /// Whether the next scheduled occurrence should be skipped
    var isSkipped: Bool

    /// When the alarm was created
    var createdAt: Date

    /// When the alarm was last modified
    var updatedAt: Date

    /// Selected accessory identifiers (HomeKit IDs)
    var selectedAccessoryIdentifiers: [String]

    /// Home identifier this alarm belongs to
    var homeIdentifier: String?

    /// Validation state indicating sync health
    var validationStateRaw: String

    // MARK: - Computed Properties

    var gradientCurve: GradientCurve {
        get { GradientCurve(rawValue: gradientCurveRaw) ?? .easeInOut }
        set { gradientCurveRaw = newValue.rawValue }
    }

    var colorMode: AlarmColorMode {
        get { AlarmColorMode(rawValue: colorModeRaw) ?? .brightnessOnly }
        set { colorModeRaw = newValue.rawValue }
    }

    var validationState: AlarmValidationState {
        get { AlarmValidationState(rawValue: validationStateRaw) ?? .unknown }
        set { validationStateRaw = newValue.rawValue }
    }

    /// Returns the wake time as a Date for the next occurrence
    func wakeTimeDate(baseDate: Date = Date()) -> Date {
        let calendar = Calendar.current
        let seconds = wakeTimeSeconds
        let hour = seconds / 3600
        let minute = (seconds % 3600) / 60

        var components = calendar.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = hour
        components.minute = minute
        components.second = 0

        return calendar.date(from: components) ?? baseDate
    }

    /// Initialize a new alarm with default values
    init(
        id: UUID = UUID(),
        name: String,
        wakeTimeSeconds: Int,
        durationMinutes: Int = 30,
        gradientCurve: GradientCurve = .easeInOut,
        colorMode: AlarmColorMode = .brightnessOnly,
        startBrightness: Int = 0,
        targetBrightness: Int = 100,
        targetColorTemperature: Int? = nil,
        targetHue: Int? = nil,
        targetSaturation: Int? = nil,
        isEnabled: Bool = true,
        selectedAccessoryIdentifiers: [String] = [],
        homeIdentifier: String? = nil
    ) {
        self.id = id
        self.name = name
        self.wakeTimeSeconds = wakeTimeSeconds
        self.durationMinutes = durationMinutes
        self.gradientCurveRaw = gradientCurve.rawValue
        self.colorModeRaw = colorMode.rawValue
        self.startBrightness = startBrightness
        self.targetBrightness = targetBrightness
        self.targetColorTemperature = targetColorTemperature
        self.targetHue = targetHue
        self.targetSaturation = targetSaturation
        self.isEnabled = isEnabled
        self.isSkipped = false
        self.createdAt = Date()
        self.updatedAt = Date()
        self.selectedAccessoryIdentifiers = selectedAccessoryIdentifiers
        self.homeIdentifier = homeIdentifier
        self.validationStateRaw = AlarmValidationState.unknown.rawValue
    }

    /// Update the alarm with new configuration values
    /// Preserves identity (id), createdAt, and isEnabled state (VAL-ALARM-007, VAL-ALARM-006)
    func update(
        name: String? = nil,
        wakeTimeSeconds: Int? = nil,
        durationMinutes: Int? = nil,
        gradientCurve: GradientCurve? = nil,
        colorMode: AlarmColorMode? = nil,
        startBrightness: Int? = nil,
        targetBrightness: Int? = nil,
        targetColorTemperature: Int? = nil,
        targetHue: Int? = nil,
        targetSaturation: Int? = nil,
        selectedAccessoryIdentifiers: [String]? = nil,
        homeIdentifier: String? = nil
    ) {
        if let name = name { self.name = name }
        if let wakeTimeSeconds = wakeTimeSeconds { self.wakeTimeSeconds = wakeTimeSeconds }
        if let durationMinutes = durationMinutes { self.durationMinutes = durationMinutes }
        if let gradientCurve = gradientCurve { self.gradientCurveRaw = gradientCurve.rawValue }
        if let colorMode = colorMode { self.colorModeRaw = colorMode.rawValue }
        if let startBrightness = startBrightness { self.startBrightness = startBrightness }
        if let targetBrightness = targetBrightness { self.targetBrightness = targetBrightness }
        if let targetColorTemperature = targetColorTemperature { self.targetColorTemperature = targetColorTemperature }
        if let targetHue = targetHue { self.targetHue = targetHue }
        if let targetSaturation = targetSaturation { self.targetSaturation = targetSaturation }
        if let selectedAccessoryIdentifiers = selectedAccessoryIdentifiers { self.selectedAccessoryIdentifiers = selectedAccessoryIdentifiers }
        if let homeIdentifier = homeIdentifier { self.homeIdentifier = homeIdentifier }

        self.updatedAt = Date()
    }

    /// Toggle the enabled state without mutating other configuration (VAL-ALARM-006)
    func toggleEnabled() {
        self.isEnabled.toggle()
        self.updatedAt = Date()
    }

    /// Set the enabled state explicitly
    func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
        self.updatedAt = Date()
    }

    /// Set the skipped state for the next occurrence
    func setSkipped(_ skipped: Bool) {
        self.isSkipped = skipped
        self.updatedAt = Date()
    }

    /// Update validation state
    func setValidationState(_ state: AlarmValidationState) {
        self.validationStateRaw = state.rawValue
        self.updatedAt = Date()
    }
}

/// Validation/sync state for an alarm
enum AlarmValidationState: String, Codable, Sendable {
    case unknown = "unknown"
    case valid = "valid"
    case needsSync = "needs_sync"
    case outOfSync = "out_of_sync"
    case invalidAccessories = "invalid_accessories"
    case permissionRevoked = "permission_revoked"
    case homeUnavailable = "home_unavailable"
}

/// Domain model for alarm display in UI
struct AlarmViewModel: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let wakeTime: String
    let duration: String
    let isEnabled: Bool
    let accessoryCount: Int
    let validationState: AlarmValidationState
    let nextRunDate: Date?

    init(
        id: UUID,
        name: String,
        wakeTime: String,
        duration: String,
        isEnabled: Bool,
        accessoryCount: Int,
        validationState: AlarmValidationState,
        nextRunDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.wakeTime = wakeTime
        self.duration = duration
        self.isEnabled = isEnabled
        self.accessoryCount = accessoryCount
        self.validationState = validationState
        self.nextRunDate = nextRunDate
    }

    init(from alarm: WakeAlarm) {
        self.id = alarm.id
        self.name = alarm.name

        // Format wake time
        let hours = alarm.wakeTimeSeconds / 3600
        let minutes = (alarm.wakeTimeSeconds % 3600) / 60
        self.wakeTime = String(format: "%02d:%02d", hours, minutes)

        // Format duration
        if alarm.durationMinutes < 60 {
            self.duration = "\(alarm.durationMinutes) min"
        } else {
            let hours = alarm.durationMinutes / 60
            let mins = alarm.durationMinutes % 60
            if mins == 0 {
                self.duration = "\(hours) hr"
            } else {
                self.duration = "\(hours) hr \(mins) min"
            }
        }

        self.isEnabled = alarm.isEnabled
        self.accessoryCount = alarm.selectedAccessoryIdentifiers.count
        self.validationState = alarm.validationState
        self.nextRunDate = alarm.isEnabled ? alarm.wakeTimeDate() : nil
    }

    var statusText: String {
        switch validationState {
        case .valid:
            return isEnabled ? "On" : "Off"
        case .needsSync:
            return "Syncing..."
        case .outOfSync:
            return "Needs Repair"
        case .invalidAccessories:
            return "Accessories Changed"
        case .permissionRevoked:
            return "No Access"
        case .homeUnavailable:
            return "Home Unavailable"
        case .unknown:
            return isEnabled ? "On" : "Off"
        }
    }

    var isHealthy: Bool {
        validationState == .valid || validationState == .unknown
    }
}

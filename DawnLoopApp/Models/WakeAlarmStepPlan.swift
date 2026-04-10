import SwiftData
import Foundation

/// Represents a single step in the wake alarm plan
/// Contains the target values for a specific point in time
struct WakeAlarmStep: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let brightness: Int
    let colorTemperature: Int?
    let hue: Int?
    let saturation: Int?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        brightness: Int,
        colorTemperature: Int? = nil,
        hue: Int? = nil,
        saturation: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.brightness = brightness
        self.colorTemperature = colorTemperature
        self.hue = hue
        self.saturation = saturation
    }

    /// Whether this step includes color temperature
    var hasColorTemperature: Bool {
        colorTemperature != nil
    }

    /// Whether this step includes full color (hue/saturation)
    var hasFullColor: Bool {
        hue != nil && saturation != nil
    }
}

/// The gradient curve function for interpolation
enum GradientFunction {
    case linear
    case easeIn
    case easeOut
    case easeInOut

    /// Apply the curve function to a normalized value (0.0 - 1.0)
    func apply(_ t: Double) -> Double {
        switch self {
        case .linear:
            return t
        case .easeIn:
            return t * t
        case .easeOut:
            return 1 - (1 - t) * (1 - t)
        case .easeInOut:
            if t < 0.5 {
                return 2 * t * t
            } else {
                return 1 - pow(-2 * t + 2, 2) / 2
            }
        }
    }
}

/// Pure step-planning engine for wake alarms
/// Converts alarm settings into discrete brightness and color steps (VAL-AUTO-001)
struct WakeAlarmStepPlanner {
    /// Default number of steps for the sunrise transition
    static let defaultStepCount = 10

    /// Plan steps for an alarm configuration
    /// - Parameters:
    ///   - wakeTime: The target wake time
    ///   - durationMinutes: Duration of the sunrise ramp
    ///   - curve: The gradient curve to use
    ///   - startBrightness: Starting brightness (0-100)
    ///   - targetBrightness: Target brightness (0-100)
    ///   - targetColorTemperature: Optional target color temperature
    ///   - targetHue: Optional target hue
    ///   - targetSaturation: Optional target saturation
    ///   - stepCount: Number of discrete steps
    /// - Returns: Array of ordered steps with timestamps and target values
    static func planSteps(
        wakeTime: Date,
        durationMinutes: Int,
        curve: GradientCurve,
        startBrightness: Int = 0,
        targetBrightness: Int = 100,
        targetColorTemperature: Int? = nil,
        targetHue: Int? = nil,
        targetSaturation: Int? = nil,
        stepCount: Int = defaultStepCount
    ) -> [WakeAlarmStep] {
        guard stepCount > 0 else { return [] }

        let calendar = Calendar.current
        let curveFunction = GradientFunction.from(curve)

        var steps: [WakeAlarmStep] = []

        // Calculate the start time
        guard let startTime = calendar.date(
            byAdding: .minute,
            value: -durationMinutes,
            to: wakeTime
        ) else {
            return []
        }

        // Total duration in seconds
        let totalSeconds = Double(durationMinutes * 60)

        for stepIndex in 0..<stepCount {
            // Normalized position in the transition (0.0 to 1.0)
            let t = Double(stepIndex) / Double(stepCount - 1)

            // Apply the gradient curve
            let curvedT = curveFunction.apply(t)

            // Calculate timestamp for this step
            let secondsOffset = curvedT * totalSeconds
            guard let timestamp = calendar.date(
                byAdding: .second,
                value: Int(secondsOffset),
                to: startTime
            ) else {
                continue
            }

            // Interpolate brightness
            let brightness = Int(
                Double(startBrightness) + curvedT * Double(targetBrightness - startBrightness)
            )

            // Interpolate color values if provided
            let colorTemp = targetColorTemperature.map { temp in
                // For color temperature, we typically want a fixed target
                // But we could interpolate from a warm "night" temp to the target
                temp
            }

            let hue = targetHue.map { h in
                // Hue could also be interpolated if we had a start hue
                h
            }

            let saturation = targetSaturation.map { s in
                // Saturation could be interpolated (start dim, end at target)
                Int(Double(s) * curvedT)
            }

            let step = WakeAlarmStep(
                timestamp: timestamp,
                brightness: max(0, min(100, brightness)),
                colorTemperature: colorTemp,
                hue: hue,
                saturation: saturation
            )

            steps.append(step)
        }

        return steps
    }

    /// Plan steps specifically for an alarm model
    static func planSteps(for alarm: WakeAlarm, stepCount: Int = defaultStepCount) -> [WakeAlarmStep] {
        let wakeTime = alarm.wakeTimeDate()

        return planSteps(
            wakeTime: wakeTime,
            durationMinutes: alarm.durationMinutes,
            curve: alarm.gradientCurve,
            startBrightness: alarm.startBrightness,
            targetBrightness: alarm.targetBrightness,
            targetColorTemperature: alarm.targetColorTemperature,
            targetHue: alarm.targetHue,
            targetSaturation: alarm.targetSaturation,
            stepCount: stepCount
        )
    }

    /// Plan steps with capability-aware degradation
    /// Adapts the plan based on accessory capabilities (VAL-AUTO-002, VAL-AUTO-003, VAL-AUTO-004)
    static func planSteps(
        for alarm: WakeAlarm,
        capabilities: [AccessoryCapability],
        stepCount: Int = defaultStepCount
    ) -> CapabilityAwarePlan {
        let fullPlan = planSteps(for: alarm, stepCount: stepCount)

        // Determine which accessories can use which features
        let canUseColorTemp = capabilities.contains { $0.supportsColorTemperature }
        let allSupportColorTemp = !capabilities.isEmpty && capabilities.allSatisfy { $0.supportsColorTemperature }
        let allSupportFullColor = !capabilities.isEmpty && capabilities.allSatisfy { $0.supportsHueSaturation }

        // Adjust plan based on color mode and capabilities
        let adjustedSteps: [WakeAlarmStep]
        let degradation: PlanDegradation

        switch alarm.colorMode {
        case .brightnessOnly:
            adjustedSteps = fullPlan.map { step in
                WakeAlarmStep(
                    timestamp: step.timestamp,
                    brightness: step.brightness,
                    colorTemperature: nil,
                    hue: nil,
                    saturation: nil
                )
            }
            degradation = .none

        case .colorTemperature:
            if allSupportColorTemp {
                adjustedSteps = fullPlan
                degradation = .none
            } else {
                // Degrade to brightness-only for all accessories
                adjustedSteps = fullPlan.map { step in
                    WakeAlarmStep(
                        timestamp: step.timestamp,
                        brightness: step.brightness,
                        colorTemperature: nil,
                        hue: nil,
                        saturation: nil
                    )
                }
                degradation = .colorTemperatureUnavailable
            }

        case .fullColor:
            if allSupportFullColor {
                adjustedSteps = fullPlan
                degradation = .none
            } else if canUseColorTemp {
                // Degrade to color temperature
                adjustedSteps = fullPlan.map { step in
                    WakeAlarmStep(
                        timestamp: step.timestamp,
                        brightness: step.brightness,
                        colorTemperature: step.colorTemperature,
                        hue: nil,
                        saturation: nil
                    )
                }
                degradation = .fullColorUnavailable
            } else {
                // Degrade to brightness-only
                adjustedSteps = fullPlan.map { step in
                    WakeAlarmStep(
                        timestamp: step.timestamp,
                        brightness: step.brightness,
                        colorTemperature: nil,
                        hue: nil,
                        saturation: nil
                    )
                }
                degradation = .fullColorAndTemperatureUnavailable
            }
        }

        return CapabilityAwarePlan(
            steps: adjustedSteps,
            degradation: degradation,
            brightnessOnlyCount: capabilities.filter { $0 == .brightnessOnly }.count,
            tunableWhiteCount: capabilities.filter { $0 == .tunableWhite }.count,
            fullColorCount: capabilities.filter { $0 == .fullColor }.count
        )
    }
}

/// Represents how the plan was degraded for mixed capabilities
enum PlanDegradation: Equatable, Sendable {
    case none
    case colorTemperatureUnavailable
    case fullColorUnavailable
    case fullColorAndTemperatureUnavailable

    var requiresExplanation: Bool {
        self != .none
    }

    var explanation: String? {
        switch self {
        case .none:
            return nil
        case .colorTemperatureUnavailable:
            return "Some lights will use brightness only."
        case .fullColorUnavailable:
            return "Some lights will use warm light instead of color."
        case .fullColorAndTemperatureUnavailable:
            return "Some lights will use brightness only."
        }
    }
}

/// A capability-aware step plan with degradation information
struct CapabilityAwarePlan: Equatable, Sendable {
    let steps: [WakeAlarmStep]
    let degradation: PlanDegradation
    let brightnessOnlyCount: Int
    let tunableWhiteCount: Int
    let fullColorCount: Int

    var totalAccessoryCount: Int {
        brightnessOnlyCount + tunableWhiteCount + fullColorCount
    }

    var hasMixedCapabilities: Bool {
        (brightnessOnlyCount > 0 ? 1 : 0) +
        (tunableWhiteCount > 0 ? 1 : 0) +
        (fullColorCount > 0 ? 1 : 0) > 1
    }
}

extension GradientFunction {
    static func from(_ curve: GradientCurve) -> GradientFunction {
        switch curve {
        case .linear:
            return .linear
        case .easeIn:
            return .easeIn
        case .easeOut:
            return .easeOut
        case .easeInOut:
            return .easeInOut
        }
    }
}

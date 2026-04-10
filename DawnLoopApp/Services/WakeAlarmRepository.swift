import Foundation
import SwiftData

/// Protocol for alarm repository operations - enables mocking in tests
protocol WakeAlarmRepositoryProtocol: Sendable {
    func fetchAllAlarms() async -> [WakeAlarm]
    func fetchAlarm(byId id: UUID) async -> WakeAlarm?
    func fetchEnabledAlarms() async -> [WakeAlarm]
    func saveAlarm(_ alarm: WakeAlarm) async throws
    func deleteAlarm(_ alarm: WakeAlarm) async throws
    func deleteAlarm(byId id: UUID) async throws
    func duplicateAlarm(_ alarm: WakeAlarm) async throws -> WakeAlarm
    func toggleAlarmEnabled(_ alarm: WakeAlarm) async throws
    func updateAlarm(
        _ alarm: WakeAlarm,
        name: String?,
        wakeTimeSeconds: Int?,
        durationMinutes: Int?,
        gradientCurve: GradientCurve?,
        colorMode: AlarmColorMode?,
        startBrightness: Int?,
        targetBrightness: Int?,
        targetColorTemperature: Int?,
        targetHue: Int?,
        targetSaturation: Int?,
        selectedAccessoryIdentifiers: [String]?,
        homeIdentifier: String?
    ) async throws -> WakeAlarm
}

/// Repository for WakeAlarm persistence operations
/// Handles CRUD operations while preserving alarm identity (VAL-ALARM-007)
/// and maintaining enabled state independently (VAL-ALARM-006)
@MainActor
final class WakeAlarmRepository: WakeAlarmRepositoryProtocol {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Fetch Operations

    /// Fetch all alarms from persistence
    func fetchAllAlarms() async -> [WakeAlarm] {
        let context = ModelContext(modelContainer)

        do {
            let descriptor = FetchDescriptor<WakeAlarm>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            return try context.fetch(descriptor)
        } catch {
            print("Failed to fetch alarms: \(error)")
            return []
        }
    }

    /// Fetch a specific alarm by ID
    func fetchAlarm(byId id: UUID) async -> WakeAlarm? {
        let context = ModelContext(modelContainer)

        do {
            var descriptor = FetchDescriptor<WakeAlarm>()
            descriptor.predicate = #Predicate { $0.id == id }

            return try context.fetch(descriptor).first
        } catch {
            print("Failed to fetch alarm \(id): \(error)")
            return nil
        }
    }

    /// Fetch all enabled alarms
    func fetchEnabledAlarms() async -> [WakeAlarm] {
        let context = ModelContext(modelContainer)

        do {
            var descriptor = FetchDescriptor<WakeAlarm>()
            descriptor.predicate = #Predicate { $0.isEnabled == true }
            descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]

            return try context.fetch(descriptor)
        } catch {
            print("Failed to fetch enabled alarms: \(error)")
            return []
        }
    }

    /// Fetch alarms for a specific home
    func fetchAlarms(forHomeId homeId: String) async -> [WakeAlarm] {
        let context = ModelContext(modelContainer)

        do {
            var descriptor = FetchDescriptor<WakeAlarm>()
            descriptor.predicate = #Predicate { $0.homeIdentifier == homeId }
            descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]

            return try context.fetch(descriptor)
        } catch {
            print("Failed to fetch alarms for home \(homeId): \(error)")
            return []
        }
    }

    // MARK: - Save Operations

    /// Save an alarm to persistence
    /// If the alarm already exists (by ID), updates the existing record (VAL-ALARM-007)
    /// Otherwise, inserts a new alarm
    func saveAlarm(_ alarm: WakeAlarm) async throws {
        let context = ModelContext(modelContainer)

        // Check if an alarm with this ID already exists
        let alarmId = alarm.id
        var descriptor = FetchDescriptor<WakeAlarm>()
        descriptor.predicate = #Predicate { alarm in alarm.id == alarmId }

        if let existing = try context.fetch(descriptor).first {
            // Update existing alarm - this preserves identity (VAL-ALARM-007)
            existing.update(
                name: alarm.name,
                wakeTimeSeconds: alarm.wakeTimeSeconds,
                durationMinutes: alarm.durationMinutes,
                gradientCurve: alarm.gradientCurve,
                colorMode: alarm.colorMode,
                startBrightness: alarm.startBrightness,
                targetBrightness: alarm.targetBrightness,
                targetColorTemperature: alarm.targetColorTemperature,
                targetHue: alarm.targetHue,
                targetSaturation: alarm.targetSaturation,
                selectedAccessoryIdentifiers: alarm.selectedAccessoryIdentifiers,
                homeIdentifier: alarm.homeIdentifier
            )

            // Preserve enabled state separately (VAL-ALARM-006)
            existing.setEnabled(alarm.isEnabled)
            existing.setSkipped(alarm.isSkipped)
            existing.setValidationState(alarm.validationState)
        } else {
            // Insert new alarm
            context.insert(alarm)
        }

        do {
            try context.save()
        } catch {
            throw WakeAlarmRepositoryError.saveFailed(underlying: error)
        }
    }

    /// Create a new alarm with the given configuration
    func createAlarm(
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
        selectedAccessoryIdentifiers: [String] = [],
        homeIdentifier: String? = nil,
        isEnabled: Bool = true
    ) async throws -> WakeAlarm {
        let alarm = WakeAlarm(
            name: name,
            wakeTimeSeconds: wakeTimeSeconds,
            durationMinutes: durationMinutes,
            gradientCurve: gradientCurve,
            colorMode: colorMode,
            startBrightness: startBrightness,
            targetBrightness: targetBrightness,
            targetColorTemperature: targetColorTemperature,
            targetHue: targetHue,
            targetSaturation: targetSaturation,
            isEnabled: isEnabled,
            selectedAccessoryIdentifiers: selectedAccessoryIdentifiers,
            homeIdentifier: homeIdentifier
        )

        try await saveAlarm(alarm)
        return alarm
    }

    /// Update an existing alarm with new configuration values
    /// Preserves alarm identity (id) and enabled state (VAL-ALARM-007, VAL-ALARM-006)
    func updateAlarm(
        _ alarm: WakeAlarm,
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
    ) async throws -> WakeAlarm {
        // Perform update on the alarm object
        alarm.update(
            name: name,
            wakeTimeSeconds: wakeTimeSeconds,
            durationMinutes: durationMinutes,
            gradientCurve: gradientCurve,
            colorMode: colorMode,
            startBrightness: startBrightness,
            targetBrightness: targetBrightness,
            targetColorTemperature: targetColorTemperature,
            targetHue: targetHue,
            targetSaturation: targetSaturation,
            selectedAccessoryIdentifiers: selectedAccessoryIdentifiers,
            homeIdentifier: homeIdentifier
        )

        try await saveAlarm(alarm)
        return alarm
    }

    // MARK: - Delete Operations

    /// Delete an alarm from persistence
    func deleteAlarm(_ alarm: WakeAlarm) async throws {
        let context = ModelContext(modelContainer)

        // Fetch the alarm in this context before deleting
        let alarmId = alarm.id
        var descriptor = FetchDescriptor<WakeAlarm>()
        descriptor.predicate = #Predicate { alarm in alarm.id == alarmId }

        guard let alarmInContext = try context.fetch(descriptor).first else {
            throw WakeAlarmRepositoryError.alarmNotFound(id: alarm.id)
        }

        context.delete(alarmInContext)

        do {
            try context.save()
        } catch {
            throw WakeAlarmRepositoryError.deleteFailed(underlying: error)
        }
    }

    /// Delete an alarm by ID
    func deleteAlarm(byId id: UUID) async throws {
        let context = ModelContext(modelContainer)

        var descriptor = FetchDescriptor<WakeAlarm>()
        descriptor.predicate = #Predicate { alarm in alarm.id == id }

        guard let alarm = try context.fetch(descriptor).first else {
            throw WakeAlarmRepositoryError.alarmNotFound(id: id)
        }

        context.delete(alarm)

        do {
            try context.save()
        } catch {
            throw WakeAlarmRepositoryError.deleteFailed(underlying: error)
        }
    }

    // MARK: - Special Operations

    /// Duplicate an alarm with a new identity
    /// Creates a copy with a new ID while preserving all configuration
    func duplicateAlarm(_ alarm: WakeAlarm) async throws -> WakeAlarm {
        let copy = WakeAlarm(
            name: "\(alarm.name) Copy",
            wakeTimeSeconds: alarm.wakeTimeSeconds,
            durationMinutes: alarm.durationMinutes,
            gradientCurve: alarm.gradientCurve,
            colorMode: alarm.colorMode,
            startBrightness: alarm.startBrightness,
            targetBrightness: alarm.targetBrightness,
            targetColorTemperature: alarm.targetColorTemperature,
            targetHue: alarm.targetHue,
            targetSaturation: alarm.targetSaturation,
            isEnabled: false, // Duplicated alarms start disabled
            selectedAccessoryIdentifiers: alarm.selectedAccessoryIdentifiers,
            homeIdentifier: alarm.homeIdentifier
        )

        try await saveAlarm(copy)
        return copy
    }

    /// Toggle the enabled state of an alarm
    /// Only mutates the enabled flag, not other configuration (VAL-ALARM-006)
    func toggleAlarmEnabled(_ alarm: WakeAlarm) async throws {
        let context = ModelContext(modelContainer)

        // Fetch the alarm in this context
        let alarmId = alarm.id
        var descriptor = FetchDescriptor<WakeAlarm>()
        descriptor.predicate = #Predicate { alarm in alarm.id == alarmId }

        guard let alarmInContext = try context.fetch(descriptor).first else {
            throw WakeAlarmRepositoryError.alarmNotFound(id: alarm.id)
        }

        alarmInContext.toggleEnabled()

        do {
            try context.save()
        } catch {
            throw WakeAlarmRepositoryError.saveFailed(underlying: error)
        }
    }

    /// Set the enabled state explicitly
    func setAlarmEnabled(_ alarm: WakeAlarm, enabled: Bool) async throws {
        let context = ModelContext(modelContainer)

        // Fetch the alarm in this context
        let alarmId = alarm.id
        var descriptor = FetchDescriptor<WakeAlarm>()
        descriptor.predicate = #Predicate { alarm in alarm.id == alarmId }

        guard let alarmInContext = try context.fetch(descriptor).first else {
            throw WakeAlarmRepositoryError.alarmNotFound(id: alarm.id)
        }

        alarmInContext.setEnabled(enabled)

        do {
            try context.save()
        } catch {
            throw WakeAlarmRepositoryError.saveFailed(underlying: error)
        }
    }

    /// Update validation state for an alarm
    func updateValidationState(_ alarm: WakeAlarm, state: AlarmValidationState) async throws {
        let context = ModelContext(modelContainer)

        // Fetch the alarm in this context
        let alarmId = alarm.id
        var descriptor = FetchDescriptor<WakeAlarm>()
        descriptor.predicate = #Predicate { alarm in alarm.id == alarmId }

        guard let alarmInContext = try context.fetch(descriptor).first else {
            throw WakeAlarmRepositoryError.alarmNotFound(id: alarm.id)
        }

        alarmInContext.setValidationState(state)

        do {
            try context.save()
        } catch {
            throw WakeAlarmRepositoryError.saveFailed(underlying: error)
        }
    }
}

/// Errors that can occur in the alarm repository
enum WakeAlarmRepositoryError: Error {
    case saveFailed(underlying: Error)
    case deleteFailed(underlying: Error)
    case alarmNotFound(id: UUID)
    case duplicateFailed(underlying: Error)

    var localizedDescription: String {
        switch self {
        case .saveFailed(let error):
            return "Failed to save alarm: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete alarm: \(error.localizedDescription)"
        case .alarmNotFound(let id):
            return "Alarm not found: \(id)"
        case .duplicateFailed(let error):
            return "Failed to duplicate alarm: \(error.localizedDescription)"
        }
    }
}

/// Actor-based mock implementation for testing
actor MockWakeAlarmRepository: WakeAlarmRepositoryProtocol {
    private var alarms: [WakeAlarm] = []
    private var nextId: Int = 1

    func setMockAlarms(_ alarms: [WakeAlarm]) {
        self.alarms = alarms
    }

    func fetchAllAlarms() async -> [WakeAlarm] {
        return alarms.sorted { $0.createdAt > $1.createdAt }
    }

    func fetchAlarm(byId id: UUID) async -> WakeAlarm? {
        return alarms.first { $0.id == id }
    }

    func fetchEnabledAlarms() async -> [WakeAlarm] {
        return alarms.filter { $0.isEnabled }.sorted { $0.createdAt > $1.createdAt }
    }

    func saveAlarm(_ alarm: WakeAlarm) async throws {
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index] = alarm
        } else {
            alarms.append(alarm)
        }
    }

    func deleteAlarm(_ alarm: WakeAlarm) async throws {
        alarms.removeAll { $0.id == alarm.id }
    }

    func deleteAlarm(byId id: UUID) async throws {
        alarms.removeAll { $0.id == id }
    }

    func duplicateAlarm(_ alarm: WakeAlarm) async throws -> WakeAlarm {
        let copy = WakeAlarm(
            name: "\(alarm.name) Copy",
            wakeTimeSeconds: alarm.wakeTimeSeconds,
            durationMinutes: alarm.durationMinutes,
            gradientCurve: alarm.gradientCurve,
            colorMode: alarm.colorMode,
            startBrightness: alarm.startBrightness,
            targetBrightness: alarm.targetBrightness,
            targetColorTemperature: alarm.targetColorTemperature,
            targetHue: alarm.targetHue,
            targetSaturation: alarm.targetSaturation,
            isEnabled: false,
            selectedAccessoryIdentifiers: alarm.selectedAccessoryIdentifiers,
            homeIdentifier: alarm.homeIdentifier
        )
        alarms.append(copy)
        return copy
    }

    func toggleAlarmEnabled(_ alarm: WakeAlarm) async throws {
        alarm.toggleEnabled()
        try await saveAlarm(alarm)
    }

    func updateAlarm(
        _ alarm: WakeAlarm,
        name: String?,
        wakeTimeSeconds: Int?,
        durationMinutes: Int?,
        gradientCurve: GradientCurve?,
        colorMode: AlarmColorMode?,
        startBrightness: Int?,
        targetBrightness: Int?,
        targetColorTemperature: Int?,
        targetHue: Int?,
        targetSaturation: Int?,
        selectedAccessoryIdentifiers: [String]?,
        homeIdentifier: String?
    ) async throws -> WakeAlarm {
        alarm.update(
            name: name,
            wakeTimeSeconds: wakeTimeSeconds,
            durationMinutes: durationMinutes,
            gradientCurve: gradientCurve,
            colorMode: colorMode,
            startBrightness: startBrightness,
            targetBrightness: targetBrightness,
            targetColorTemperature: targetColorTemperature,
            targetHue: targetHue,
            targetSaturation: targetSaturation,
            selectedAccessoryIdentifiers: selectedAccessoryIdentifiers,
            homeIdentifier: homeIdentifier
        )
        try await saveAlarm(alarm)
        return alarm
    }
}

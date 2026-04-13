import Foundation
import SwiftData

/// Protocol for alarm repository operations - enables mocking in tests
protocol WakeAlarmRepositoryProtocol: Sendable {
    func fetchAllAlarms() async -> [WakeAlarm]
    func fetchAlarm(byId id: UUID) async -> WakeAlarm?
    func fetchEnabledAlarms() async -> [WakeAlarm]
    func saveAlarm(_ alarm: WakeAlarm) async throws
    func saveAlarm(_ alarm: WakeAlarm, schedule: WeekdaySchedule?) async throws
    func saveAlarm(_ alarm: WakeAlarm, schedule: WeekdaySchedule?, validationState: AlarmValidationState?) async throws
    func deleteAlarm(_ alarm: WakeAlarm) async throws
    func deleteAlarm(byId id: UUID) async throws
    func duplicateAlarm(_ alarm: WakeAlarm) async throws -> WakeAlarm
    func toggleAlarmEnabled(_ alarm: WakeAlarm) async throws
    func updateAlarm(
        _ alarm: WakeAlarm,
        name: String?,
        wakeTimeSeconds: Int?,
        timeReference: AlarmTimeReference?,
        timeOffsetMinutes: Int?,
        durationMinutes: Int?,
        stepCount: Int?,
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

    // MARK: - Schedule Operations

    func fetchSchedule(for alarmId: UUID) async -> WakeAlarmSchedule?
    func saveSchedule(_ schedule: WakeAlarmSchedule) async throws
    func deleteSchedule(for alarmId: UUID) async throws

    // MARK: - Validation State Operations

    func fetchValidationState(for alarmId: UUID) async -> ValidationStateRecord?
    func saveValidationState(_ record: ValidationStateRecord) async throws
    func updateValidationState(for alarmId: UUID, state: AlarmValidationState, message: String?, requiresUserAction: Bool?) async throws
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
            DawnLoopLogger.persistence.error("Failed to fetch alarms: \(error.localizedDescription)")
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
            DawnLoopLogger.persistence.error("Failed to fetch alarm \(id.uuidString): \(error.localizedDescription)")
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
            DawnLoopLogger.persistence.error("Failed to fetch enabled alarms: \(error.localizedDescription)")
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
            DawnLoopLogger.persistence.error("Failed to fetch alarms for home \(homeId): \(error.localizedDescription)")
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
                timeReference: alarm.timeReference,
                timeOffsetMinutes: alarm.timeOffsetMinutes,
                durationMinutes: alarm.durationMinutes,
                stepCount: alarm.stepCount,
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

    /// Save an alarm with its associated schedule
    /// Round-trips the schedule through the dedicated WakeAlarmSchedule model (VAL-ALARM contract)
    func saveAlarm(_ alarm: WakeAlarm, schedule: WeekdaySchedule?) async throws {
        let context = ModelContext(modelContainer)

        // Save the alarm first
        try await saveAlarm(alarm)

        if let schedule = schedule {
            let alarmId = alarm.id
            var descriptor = FetchDescriptor<WakeAlarmSchedule>()
            descriptor.predicate = #Predicate { $0.alarmId == alarmId }

            if let existingSchedule = try context.fetch(descriptor).first {
                // Update existing schedule
                existingSchedule.update(weekdaySchedule: schedule)
            } else {
                // Create new schedule record
                let newSchedule = WakeAlarmSchedule(
                    alarmId: alarm.id,
                    weekdaySchedule: schedule
                )
                context.insert(newSchedule)
                alarm.scheduleRecordId = newSchedule.id
            }

            try context.save()
        } else {
            try await deleteSchedule(for: alarm.id)
        }
    }

    /// Save an alarm with both schedule and validation state
    /// Full persistence contract round-tripping through dedicated models (VAL-ALARM contract)
    func saveAlarm(_ alarm: WakeAlarm, schedule: WeekdaySchedule?, validationState: AlarmValidationState?) async throws {
        let context = ModelContext(modelContainer)

        // Save alarm and schedule
        try await saveAlarm(alarm, schedule: schedule)

        // Handle validation state persistence if provided
        if let state = validationState {
            let alarmId = alarm.id
            var descriptor = FetchDescriptor<ValidationStateRecord>()
            descriptor.predicate = #Predicate { $0.alarmId == alarmId }

            if let existingRecord = try context.fetch(descriptor).first {
                // Update existing record
                existingRecord.updateState(state)
            } else {
                // Create new validation state record
                let newRecord = ValidationStateRecord(
                    alarmId: alarm.id,
                    state: state
                )
                context.insert(newRecord)
                alarm.validationStateRecordId = newRecord.id
            }

            try context.save()
        }
    }

    /// Create a new alarm with the given configuration
    func createAlarm(
        name: String,
        wakeTimeSeconds: Int,
        timeReference: AlarmTimeReference = .clock,
        timeOffsetMinutes: Int = 0,
        durationMinutes: Int = 30,
        stepCount: Int = WakeAlarmStepPlanner.defaultStepCount,
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
        timeReference: AlarmTimeReference? = nil,
        timeOffsetMinutes: Int? = nil,
        durationMinutes: Int? = nil,
        stepCount: Int? = nil,
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

        try deleteRelatedRecords(for: alarm.id, in: context)

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

        try deleteRelatedRecords(for: id, in: context)

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
    /// Also copies schedule and validation state through dedicated models (VAL-ALARM contract)
    func duplicateAlarm(_ alarm: WakeAlarm) async throws -> WakeAlarm {
        let context = ModelContext(modelContainer)

        // Fetch existing schedule for this alarm
        let alarmId = alarm.id
        var scheduleDescriptor = FetchDescriptor<WakeAlarmSchedule>()
        scheduleDescriptor.predicate = #Predicate { $0.alarmId == alarmId }
        let existingSchedule = try? context.fetch(scheduleDescriptor).first

        // Create the copy
        let copy = WakeAlarm(
            name: "\(alarm.name) Copy",
            wakeTimeSeconds: alarm.wakeTimeSeconds,
            timeReference: alarm.timeReference,
            timeOffsetMinutes: alarm.timeOffsetMinutes,
            durationMinutes: alarm.durationMinutes,
            stepCount: alarm.stepCount,
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

        context.insert(copy)

        // Copy the schedule if it exists
        if let schedule = existingSchedule {
            let copiedSchedule = WakeAlarmSchedule(
                alarmId: copy.id,
                weekdaySchedule: schedule.weekdaySchedule
            )
            context.insert(copiedSchedule)
            copy.scheduleRecordId = copiedSchedule.id
        }

        try context.save()
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

    // MARK: - Schedule Operations

    /// Fetch the schedule for a specific alarm
    /// Round-trips through the dedicated WakeAlarmSchedule model (VAL-ALARM contract)
    func fetchSchedule(for alarmId: UUID) async -> WakeAlarmSchedule? {
        let context = ModelContext(modelContainer)

        do {
            var descriptor = FetchDescriptor<WakeAlarmSchedule>()
            descriptor.predicate = #Predicate { $0.alarmId == alarmId }
            return try context.fetch(descriptor).first
        } catch {
            DawnLoopLogger.persistence.error("Failed to fetch schedule for alarm \(alarmId.uuidString): \(error.localizedDescription)")
            return nil
        }
    }

    /// Save a schedule record
    func saveSchedule(_ schedule: WakeAlarmSchedule) async throws {
        let context = ModelContext(modelContainer)
        context.insert(schedule)

        do {
            try context.save()
        } catch {
            throw WakeAlarmRepositoryError.saveFailed(underlying: error)
        }
    }

    /// Delete the schedule for a specific alarm
    func deleteSchedule(for alarmId: UUID) async throws {
        let context = ModelContext(modelContainer)

        var descriptor = FetchDescriptor<WakeAlarmSchedule>()
        descriptor.predicate = #Predicate { $0.alarmId == alarmId }

        guard let schedule = try context.fetch(descriptor).first else {
            return // No schedule to delete
        }

        context.delete(schedule)

        do {
            try context.save()
        } catch {
            throw WakeAlarmRepositoryError.deleteFailed(underlying: error)
        }
    }

    // MARK: - Validation State Operations

    /// Fetch the validation state record for a specific alarm
    /// Uses the dedicated ValidationStateRecord model (VAL-ALARM contract)
    func fetchValidationState(for alarmId: UUID) async -> ValidationStateRecord? {
        let context = ModelContext(modelContainer)

        do {
            var descriptor = FetchDescriptor<ValidationStateRecord>()
            descriptor.predicate = #Predicate { $0.alarmId == alarmId }
            return try context.fetch(descriptor).first
        } catch {
            DawnLoopLogger.persistence.error("Failed to fetch validation state for alarm \(alarmId.uuidString): \(error.localizedDescription)")
            return nil
        }
    }

    /// Save a validation state record
    func saveValidationState(_ record: ValidationStateRecord) async throws {
        let context = ModelContext(modelContainer)
        context.insert(record)

        do {
            try context.save()
        } catch {
            throw WakeAlarmRepositoryError.saveFailed(underlying: error)
        }
    }

    /// Update validation state for an alarm using the dedicated model
    func updateValidationState(
        for alarmId: UUID,
        state: AlarmValidationState,
        message: String? = nil,
        requiresUserAction: Bool? = nil
    ) async throws {
        let context = ModelContext(modelContainer)

        var descriptor = FetchDescriptor<ValidationStateRecord>()
        descriptor.predicate = #Predicate { $0.alarmId == alarmId }

        if let existingRecord = try context.fetch(descriptor).first {
            // Update existing record
            existingRecord.updateState(
                state,
                message: message,
                requiresUserAction: requiresUserAction
            )
        } else {
            // Create new validation state record
            let newRecord = ValidationStateRecord(
                alarmId: alarmId,
                state: state,
                message: message,
                requiresUserAction: requiresUserAction ?? false
            )
            context.insert(newRecord)
        }

        do {
            try context.save()
        } catch {
            throw WakeAlarmRepositoryError.saveFailed(underlying: error)
        }
    }

    private func deleteRelatedRecords(for alarmId: UUID, in context: ModelContext) throws {
        var scheduleDescriptor = FetchDescriptor<WakeAlarmSchedule>()
        scheduleDescriptor.predicate = #Predicate { $0.alarmId == alarmId }
        try context.fetch(scheduleDescriptor).forEach(context.delete)

        var validationDescriptor = FetchDescriptor<ValidationStateRecord>()
        validationDescriptor.predicate = #Predicate { $0.alarmId == alarmId }
        try context.fetch(validationDescriptor).forEach(context.delete)

        var bindingDescriptor = FetchDescriptor<AutomationBinding>()
        bindingDescriptor.predicate = #Predicate { $0.alarmId == alarmId }
        try context.fetch(bindingDescriptor).forEach(context.delete)
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
    private var schedules: [UUID: WakeAlarmSchedule] = [:] // alarmId -> schedule
    private var validationStates: [UUID: ValidationStateRecord] = [:] // alarmId -> state
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

    func saveAlarm(_ alarm: WakeAlarm, schedule: WeekdaySchedule?) async throws {
        try await saveAlarm(alarm)

        if let schedule = schedule {
            let scheduleRecord = WakeAlarmSchedule(
                alarmId: alarm.id,
                weekdaySchedule: schedule
            )
            schedules[alarm.id] = scheduleRecord
        }
    }

    func saveAlarm(_ alarm: WakeAlarm, schedule: WeekdaySchedule?, validationState: AlarmValidationState?) async throws {
        try await saveAlarm(alarm, schedule: schedule)

        if let state = validationState {
            let record = ValidationStateRecord(
                alarmId: alarm.id,
                state: state
            )
            validationStates[alarm.id] = record
        }
    }

    func deleteAlarm(_ alarm: WakeAlarm) async throws {
        alarms.removeAll { $0.id == alarm.id }
        schedules.removeValue(forKey: alarm.id)
        validationStates.removeValue(forKey: alarm.id)
    }

    func deleteAlarm(byId id: UUID) async throws {
        alarms.removeAll { $0.id == id }
        schedules.removeValue(forKey: id)
        validationStates.removeValue(forKey: id)
    }

    func duplicateAlarm(_ alarm: WakeAlarm) async throws -> WakeAlarm {
        let copy = WakeAlarm(
            name: "\(alarm.name) Copy",
            wakeTimeSeconds: alarm.wakeTimeSeconds,
            timeReference: alarm.timeReference,
            timeOffsetMinutes: alarm.timeOffsetMinutes,
            durationMinutes: alarm.durationMinutes,
            stepCount: alarm.stepCount,
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

        // Copy schedule if exists
        if let schedule = schedules[alarm.id] {
            let copiedSchedule = WakeAlarmSchedule(
                alarmId: copy.id,
                weekdaySchedule: schedule.weekdaySchedule
            )
            schedules[copy.id] = copiedSchedule
        }

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
        timeReference: AlarmTimeReference?,
        timeOffsetMinutes: Int?,
        durationMinutes: Int?,
        stepCount: Int?,
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
            selectedAccessoryIdentifiers: selectedAccessoryIdentifiers,
            homeIdentifier: homeIdentifier
        )
        try await saveAlarm(alarm)
        return alarm
    }

    // MARK: - Schedule Operations

    func fetchSchedule(for alarmId: UUID) async -> WakeAlarmSchedule? {
        return schedules[alarmId]
    }

    func saveSchedule(_ schedule: WakeAlarmSchedule) async throws {
        schedules[schedule.alarmId] = schedule
    }

    func deleteSchedule(for alarmId: UUID) async throws {
        schedules.removeValue(forKey: alarmId)
    }

    // MARK: - Validation State Operations

    func fetchValidationState(for alarmId: UUID) async -> ValidationStateRecord? {
        return validationStates[alarmId]
    }

    func saveValidationState(_ record: ValidationStateRecord) async throws {
        validationStates[record.alarmId] = record
    }

    func updateValidationState(
        for alarmId: UUID,
        state: AlarmValidationState,
        message: String?,
        requiresUserAction: Bool?
    ) async throws {
        let record = validationStates[alarmId] ?? ValidationStateRecord(
            alarmId: alarmId,
            state: state
        )
        record.updateState(state, message: message, requiresUserAction: requiresUserAction)
        validationStates[alarmId] = record
    }
}

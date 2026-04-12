import SwiftUI
import SwiftData

@main
struct DawnLoopApp: App {
    let container: AppEnvironment
    
    init() {
        // Check for test launch arguments and set flags before initializing environment
        LaunchArgumentHandler.handleTestArguments()
        
        // Execute UserDefaults resets BEFORE creating environment
        // This ensures OnboardingState reads fresh values on initialization
        LaunchArgumentHandler.executeUserDefaultsResets()
        
        // Initialize environment (this uses TestEnvironment flags)
        // OnboardingState will now read fresh UserDefaults values
        self.container = AppEnvironment()
        
        // Execute remaining pending test actions using the initialized AppEnvironment
        // This ensures all SwiftData operations use the same ModelContainer
        LaunchArgumentHandler.executePendingActions(using: self.container)
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
        }
    }
}

/// Global flag set by launch arguments for test environment detection
/// nonisolated(unsafe) because this is set once at app startup and never modified after
enum TestEnvironment {
    /// When true, seeds deterministic test homes and accessories for UI testing.
    /// This allows tests to experience the full visible flow with realistic data
    /// without requiring real HomeKit infrastructure.
    nonisolated(unsafe) static var isSeedingTestHome: Bool = false
}

/// Pending test actions to be executed after AppEnvironment initialization
/// This ensures all SwiftData operations use the same ModelContainer
/// nonisolated(unsafe) because these are set once at app startup and never modified after
enum PendingTestActions {
    nonisolated(unsafe) static var shouldResetOnboarding: Bool = false
    nonisolated(unsafe) static var shouldResetHomeSelection: Bool = false
    nonisolated(unsafe) static var shouldResetAlarms: Bool = false
    nonisolated(unsafe) static var shouldSeedTestHome: Bool = false
    nonisolated(unsafe) static var shouldSeedRepairNeededAlarm: Bool = false
}

/// Handles launch arguments for testing and debugging
enum LaunchArgumentHandler {
    static func handleTestArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        
        // Set test environment flags BEFORE environment initialization
        if arguments.contains("--seed-test-home") {
            TestEnvironment.isSeedingTestHome = true
            PendingTestActions.shouldSeedTestHome = true
        }

        if arguments.contains("--seed-repair-needed-alarm") {
            TestEnvironment.isSeedingTestHome = true
            PendingTestActions.shouldSeedTestHome = true
            PendingTestActions.shouldSeedRepairNeededAlarm = true
        }
        
        // Queue reset actions to be executed after environment initialization
        if arguments.contains("--reset-onboarding") {
            PendingTestActions.shouldResetOnboarding = true
        }
        
        if arguments.contains("--reset-home-selection") {
            PendingTestActions.shouldResetHomeSelection = true
        }

        if arguments.contains("--reset-alarms") {
            PendingTestActions.shouldResetAlarms = true
        }
    }
    
    /// Execute UserDefaults resets BEFORE environment initialization
    /// This ensures OnboardingState reads fresh values when it's created
    static func executeUserDefaultsResets() {
        let arguments = ProcessInfo.processInfo.arguments
        
        if arguments.contains("--reset-onboarding") {
            // Clear UserDefaults BEFORE AppEnvironment is created
            // so OnboardingState reads fresh values
            UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
            UserDefaults.standard.removeObject(forKey: "hasStartedHomeAccessFlow")
            // Also reset discovery step to ensure fresh flow
            UserDefaults.standard.removeObject(forKey: "discoveryStep")
        }
        
        if arguments.contains("--reset-home-selection") {
            UserDefaults.standard.removeObject(forKey: "activeHomeIdentifier")
            UserDefaults.standard.removeObject(forKey: "activeHomeName")
        }
    }
    
    /// Execute pending test actions using the initialized AppEnvironment
    /// This ensures all SwiftData operations use the same ModelContainer
    @MainActor
    static func executePendingActions(using environment: AppEnvironment) {
        // Note: UserDefaults were already reset in executeUserDefaultsResets()
        // This method handles SwiftData operations that need the environment
        
        if PendingTestActions.shouldResetOnboarding {
            resetOnboardingSwiftData(using: environment)
            environment.onboardingState.resetOnboarding()
        }
        
        if PendingTestActions.shouldResetHomeSelection {
            resetHomeSelectionSwiftData(using: environment)
        }

        if PendingTestActions.shouldResetAlarms {
            resetAlarmSwiftData(using: environment)
        }
        
        if PendingTestActions.shouldSeedTestHome {
            seedTestHomes(using: environment)
        }

        if PendingTestActions.shouldSeedRepairNeededAlarm {
            seedRepairNeededAlarm(using: environment)
        }
    }
    
    /// Clears SwiftData onboarding records (UserDefaults already cleared in executeUserDefaultsResets)
    private static func resetOnboardingSwiftData(using environment: AppEnvironment) {
        let context = ModelContext(environment.modelContainer)
        
        do {
            let descriptor = FetchDescriptor<OnboardingCompletion>()
            let completions = try context.fetch(descriptor)
            for completion in completions {
                context.delete(completion)
            }
            try context.save()
        } catch {
            DawnLoopLogger.persistence.error("Failed to reset onboarding SwiftData: \(error.localizedDescription)")
        }
    }
    
    /// Clears SwiftData home selection records (UserDefaults already cleared in executeUserDefaultsResets)
    private static func resetHomeSelectionSwiftData(using environment: AppEnvironment) {
        let context = ModelContext(environment.modelContainer)
        
        do {
            var descriptor = FetchDescriptor<HomeReference>()
            descriptor.predicate = #Predicate { $0.isActive }
            
            if let active = try context.fetch(descriptor).first {
                active.isActive = false
                active.updatedAt = Date()
            }

            let accessories = try context.fetch(FetchDescriptor<AccessoryReference>())
            for accessory in accessories {
                accessory.isSelected = false
                accessory.updatedAt = Date()
            }

            try context.save()
        } catch {
            DawnLoopLogger.persistence.error("Failed to reset home selection SwiftData: \(error.localizedDescription)")
        }
    }

    private static func resetAlarmSwiftData(using environment: AppEnvironment) {
        let context = ModelContext(environment.modelContainer)

        do {
            try context.fetch(FetchDescriptor<AutomationBinding>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<ValidationStateRecord>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<WakeAlarmSchedule>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<WakeAlarm>()).forEach(context.delete)
            try context.save()
        } catch {
            DawnLoopLogger.persistence.error("Failed to reset alarm SwiftData: \(error.localizedDescription)")
        }
    }
    
    /// Seeds deterministic test homes into SwiftData for UI testing.
    /// This provides realistic home data so tests can verify the full visible
    /// home selection flow without requiring real HomeKit infrastructure.
    private static func seedTestHomes(using environment: AppEnvironment) {
        let context = ModelContext(environment.modelContainer)
        
        do {
            // Check if test homes already exist
            let descriptor = FetchDescriptor<HomeReference>()
            let existingHomes = try context.fetch(descriptor)
            
            // Only seed if no homes exist yet
            guard existingHomes.isEmpty else {
                return
            }
            
            // Create a primary test home with rooms and accessories
            let testHome = HomeReference(
                homeKitIdentifier: "test-home-uuid-001",
                name: "Test Home",
                isActive: true,
                roomCount: 4,
                accessoryCount: 8
            )
            context.insert(testHome)
            
            // Create some accessories in the test home
            let livingRoomLight = AccessoryReference(
                homeKitIdentifier: "test-accessory-living-room-001",
                name: "Living Room Light",
                roomName: "Living Room",
                homeIdentifier: testHome.homeKitIdentifier,
                isCompatible: true
            )
            context.insert(livingRoomLight)
            
            let bedroomLight = AccessoryReference(
                homeKitIdentifier: "test-accessory-bedroom-001",
                name: "Bedroom Light",
                roomName: "Bedroom",
                homeIdentifier: testHome.homeKitIdentifier,
                isCompatible: true
            )
            context.insert(bedroomLight)
            
            let kitchenLight = AccessoryReference(
                homeKitIdentifier: "test-accessory-kitchen-001",
                name: "Kitchen Light",
                roomName: "Kitchen",
                homeIdentifier: testHome.homeKitIdentifier,
                isCompatible: true
            )
            context.insert(kitchenLight)
            
            try context.save()
        } catch {
            DawnLoopLogger.persistence.error("Failed to seed test homes: \(error.localizedDescription)")
        }
    }

    private static func seedRepairNeededAlarm(using environment: AppEnvironment) {
        let context = ModelContext(environment.modelContainer)

        do {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")

            let homeID = "test-home-uuid-001"
            let alarmID = UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID()

            var homeDescriptor = FetchDescriptor<HomeReference>()
            homeDescriptor.predicate = #Predicate { $0.homeKitIdentifier == homeID }
            let home = try context.fetch(homeDescriptor).first ?? {
                let home = HomeReference(
                    homeKitIdentifier: homeID,
                    name: "Test Home",
                    isActive: true,
                    roomCount: 4,
                    accessoryCount: 8
                )
                context.insert(home)
                return home
            }()
            home.isActive = true

            var accessoryDescriptor = FetchDescriptor<AccessoryReference>()
            accessoryDescriptor.predicate = #Predicate { $0.homeKitIdentifier == "test-accessory-living-room-001" }
            let accessory = try context.fetch(accessoryDescriptor).first ?? {
                let accessory = AccessoryReference(
                    homeKitIdentifier: "test-accessory-living-room-001",
                    name: "Living Room Light",
                    homeIdentifier: homeID,
                    roomName: "Living Room",
                    capability: .fullColor,
                    isSelected: true
                )
                context.insert(accessory)
                return accessory
            }()
            accessory.isSelected = true

            var alarmDescriptor = FetchDescriptor<WakeAlarm>()
            alarmDescriptor.predicate = #Predicate { $0.id == alarmID }
            let alarm = try context.fetch(alarmDescriptor).first ?? {
                let alarm = WakeAlarm(
                    id: alarmID,
                    name: "Repair Test Alarm",
                    wakeTimeSeconds: 7 * 3600,
                    durationMinutes: 30,
                    gradientCurve: .easeInOut,
                    colorMode: .brightnessOnly,
                    startBrightness: 0,
                    targetBrightness: 100,
                    isEnabled: true,
                    selectedAccessoryIdentifiers: ["test-accessory-living-room-001"],
                    homeIdentifier: homeID
                )
                context.insert(alarm)
                return alarm
            }()

            let alarmIdentifier = alarm.id

            var scheduleDescriptor = FetchDescriptor<WakeAlarmSchedule>()
            scheduleDescriptor.predicate = #Predicate { $0.alarmId == alarmIdentifier }
            let schedule = try context.fetch(scheduleDescriptor).first ?? {
                let schedule = WakeAlarmSchedule(alarmId: alarmIdentifier, weekdaySchedule: .weekdays)
                context.insert(schedule)
                return schedule
            }()
            schedule.update(weekdaySchedule: .weekdays)
            alarm.scheduleRecordId = schedule.id

            var validationDescriptor = FetchDescriptor<ValidationStateRecord>()
            validationDescriptor.predicate = #Predicate { $0.alarmId == alarmIdentifier }
            let validation = try context.fetch(validationDescriptor).first ?? {
                let validation = ValidationStateRecord(
                    alarmId: alarmIdentifier,
                    state: .outOfSync,
                    message: "HomeKit automation is missing pieces and needs repair.",
                    requiresUserAction: true
                )
                context.insert(validation)
                return validation
            }()
            validation.updateState(
                .outOfSync,
                message: "HomeKit automation is missing pieces and needs repair.",
                requiresUserAction: true
            )
            alarm.validationStateRecordId = validation.id

            let bindingDescriptor = FetchDescriptor<AutomationBinding>()
            let existingBindings = try context.fetch(bindingDescriptor).filter { $0.alarmId == alarmIdentifier }
            existingBindings.forEach(context.delete)

            context.insert(
                AutomationBinding(
                    alarmId: alarmIdentifier,
                    stepNumber: 0,
                    weekday: 2,
                    actionSetIdentifier: "missing-action-set",
                    triggerIdentifier: "missing-trigger",
                    scheduledTime: Date().addingTimeInterval(3600),
                    brightness: 10
                )
            )

            try context.save()
        } catch {
            DawnLoopLogger.persistence.error("Failed to seed repair-needed alarm: \(error.localizedDescription)")
        }
    }
}

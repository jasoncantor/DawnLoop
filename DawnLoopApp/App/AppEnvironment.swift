import SwiftUI
import SwiftData

@Observable
@MainActor
final class AppEnvironment {
    let onboardingState: OnboardingState
    let homeAccessState: HomeAccessState
    let homeSelectionService: HomeSelectionService
    let accessoryDiscoveryService: AccessoryDiscoveryService
    let alarmRepository: WakeAlarmRepository
    let automationBindingService: AutomationBindingService
    let automationGenerationService: AutomationGenerationService
    let automationRepairService: AutomationRepairService
    let homeKitController: HomeKitControllerProtocol
    let modelContainer: ModelContainer

    init() {
        self.onboardingState = OnboardingState()

        let schema = Schema([
            OnboardingCompletion.self,
            HomeReference.self,
            AccessoryReference.self,
            WakeAlarm.self,
            WakeAlarmSchedule.self,
            ValidationStateRecord.self,
            AutomationBinding.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            self.modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }

        if TestEnvironment.isSeedingTestHome {
            self.homeKitController = MockHomeKitController.seededTestHome()
        } else {
            self.homeKitController = HomeKitController()
        }

        let homeKitAdapter = LiveHomeKitAdapter(controller: homeKitController)

        self.homeAccessState = HomeAccessState(adapter: homeKitAdapter)
        self.homeSelectionService = HomeSelectionService(
            adapter: homeKitAdapter,
            modelContainer: modelContainer
        )
        self.accessoryDiscoveryService = AccessoryDiscoveryService(
            adapter: homeKitAdapter,
            modelContainer: modelContainer
        )
        self.alarmRepository = WakeAlarmRepository(modelContainer: modelContainer)
        self.automationBindingService = AutomationBindingService(modelContainer: modelContainer)
        self.automationGenerationService = AutomationGenerationService(
            homeKitController: homeKitController,
            modelContainer: modelContainer,
            alarmRepository: alarmRepository
        )
        self.automationRepairService = AutomationRepairService(
            homeKitController: homeKitController,
            modelContainer: modelContainer,
            alarmRepository: alarmRepository,
            generationService: automationGenerationService
        )
    }
}

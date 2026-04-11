import SwiftUI
import SwiftData
import CoreLocation

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
    let currentLocationService: CurrentLocationServiceProtocol
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
        self.currentLocationService = CurrentLocationService()

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

@MainActor
protocol CurrentLocationServiceProtocol: AnyObject {
    func authorizationStatus() -> CLAuthorizationStatus
    func requestAuthorizationIfNeeded()
    func currentCoordinateIfAuthorized() async -> SolarCoordinate?
}

@MainActor
final class CurrentLocationService: NSObject, CurrentLocationServiceProtocol {
    private let manager: CLLocationManager
    private let coordinateContinuations = PendingCheckedContinuations<SolarCoordinate?>()

    override init() {
        self.manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func authorizationStatus() -> CLAuthorizationStatus {
        manager.authorizationStatus
    }

    func requestAuthorizationIfNeeded() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func currentCoordinateIfAuthorized() async -> SolarCoordinate? {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            break
        default:
            return nil
        }

        if let coordinate = manager.location?.coordinate {
            return SolarCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }

        return await withCheckedContinuation { continuation in
            let shouldRequest = coordinateContinuations.add(continuation)
            if shouldRequest {
                manager.requestLocation()
            }
        }
    }
}

extension CurrentLocationService: @preconcurrency CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last.map {
            SolarCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
        coordinateContinuations.resumeAll(returning: coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DawnLoopLogger.homeKit.debug("Location lookup failed: \(error.localizedDescription)")
        coordinateContinuations.resumeAll(returning: nil)
    }
}

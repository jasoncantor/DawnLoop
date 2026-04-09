import XCTest
import HomeKit
@testable import DawnLoopApp

/// Mock HomeKit adapter for testing
actor MockHomeKitAdapter: HomeKitAdapterProtocol {
    var mockAuthorizationStatus: HMHomeManagerAuthorizationStatus = .notDetermined
    var mockHomes: [MockHome] = []
    var mockAccessories: [MockAccessory] = []
    var shouldThrowOnFetchHomes = false
    
    var authorizationStatus: HMHomeManagerAuthorizationStatus {
        mockAuthorizationStatus
    }
    
    func requestAuthorization() async -> HMHomeManagerAuthorizationStatus {
        // Simulate authorization request returning determined + authorized
        mockAuthorizationStatus = [.determined, .authorized]
        return mockAuthorizationStatus
    }
    
    func fetchHomes() async throws -> [MockHome] {
        if shouldThrowOnFetchHomes {
            throw HomeKitError.fetchFailed
        }
        return mockHomes
    }
    
    func fetchCompatibleAccessories(in home: MockHome) async -> [MockAccessory] {
        return mockAccessories
    }
}

enum HomeKitError: Error {
    case fetchFailed
}

/// Mock HMHome for testing - wraps a real HMHome reference
final class MockHome: NSObject {
    var uniqueIdentifier: UUID = UUID()
    var name: String = "Test Home"
    var isPrimary: Bool = true
    var mockAccessories: [MockAccessory] = []
}

/// Tests for HomeAccessState and blocker state handling
@MainActor
final class HomeAccessStateTests: XCTestCase {
    
    // MARK: - Permission States
    
    func testInitialState_IsUnknown() {
        let mockAdapter = MockHomeKitAdapter()
        let state = HomeAccessState(adapter: mockAdapter)
        
        XCTAssertEqual(state.readiness, .unknown)
        XCTAssertFalse(state.isLoading)
    }
    
    func testPermissionDenied_ShowsBlockedState() async {
        let mockAdapter = MockHomeKitAdapter()
        await mockAdapter.mockAuthorizationStatus = [.determined, .denied]
        
        let state = HomeAccessState(adapter: mockAdapter)
        await state.checkReadiness()
        
        XCTAssertEqual(state.readiness, .permissionDenied)
        XCTAssertTrue(state.readiness.isBlocked)
    }
    
    func testPermissionRestricted_ShowsBlockedState() async {
        let mockAdapter = MockHomeKitAdapter()
        await mockAdapter.mockAuthorizationStatus = [.determined, .restricted]
        
        let state = HomeAccessState(adapter: mockAdapter)
        await state.checkReadiness()
        
        XCTAssertEqual(state.readiness, .permissionDenied)
        XCTAssertTrue(state.readiness.isBlocked)
    }
    
    func testPermissionNotDetermined_RequestsAuthorization() async {
        let mockAdapter = MockHomeKitAdapter()
        await mockAdapter.mockAuthorizationStatus = .notDetermined
        
        let state = HomeAccessState(adapter: mockAdapter)
        await state.checkReadiness()
        
        // Should have requested authorization and moved to checking
        let status = await mockAdapter.authorizationStatus
        XCTAssertTrue(status.contains(.determined))
    }
    
    // MARK: - Home Configuration States
    
    func testNoHomesConfigured_ShowsBlockedState() async {
        let mockAdapter = MockHomeKitAdapter()
        await mockAdapter.mockAuthorizationStatus = [.determined, .authorized]
        await mockAdapter.mockHomes = []
        
        let state = HomeAccessState(adapter: mockAdapter)
        await state.checkReadiness()
        
        XCTAssertEqual(state.readiness, .noHomeConfigured)
        XCTAssertTrue(state.readiness.isBlocked)
    }
    
    func testFetchHomesError_ShowsNoHomeState() async {
        let mockAdapter = MockHomeKitAdapter()
        await mockAdapter.mockAuthorizationStatus = [.determined, .authorized]
        await mockAdapter.shouldThrowOnFetchHomes = true
        
        let state = HomeAccessState(adapter: mockAdapter)
        await state.checkReadiness()
        
        // Error during fetch should fall back to noHomeConfigured
        XCTAssertEqual(state.readiness, .noHomeConfigured)
    }
    
    // MARK: - Home Hub States
    
    func testHomeExistsButNoHub_ShowsBlockedState() async {
        let mockAdapter = MockHomeKitAdapter()
        await mockAdapter.mockAuthorizationStatus = [.determined, .authorized]
        
        // Create a home with no accessories and not primary (simulating no hub)
        let emptyHome = MockHome(accessories: [], isPrimary: false)
        await mockAdapter.mockHomes = [emptyHome]
        
        let state = HomeAccessState(adapter: mockAdapter)
        await state.checkReadiness()
        
        XCTAssertEqual(state.readiness, .noHomeHub)
        XCTAssertTrue(state.readiness.isBlocked)
    }
    
    func testPrimaryHome_AvoidsNoHubState() async {
        let mockAdapter = MockHomeKitAdapter()
        await mockAdapter.mockAuthorizationStatus = [.determined, .authorized]
        
        // Primary home with no accessories should still pass hub check
        let primaryHome = MockHome(accessories: [], isPrimary: true)
        await mockAdapter.mockHomes = [primaryHome]
        await mockAdapter.mockAccessories = [] // No compatible accessories
        
        let state = HomeAccessState(adapter: mockAdapter)
        await state.checkReadiness()
        
        // Should pass hub check but fail on accessories
        XCTAssertEqual(state.readiness, .noCompatibleAccessories)
    }
    
    // MARK: - Accessory States
    
    func testNoCompatibleAccessories_ShowsBlockedState() async {
        let mockAdapter = MockHomeKitAdapter()
        await mockAdapter.mockAuthorizationStatus = [.determined, .authorized]
        
        let home = MockHome(accessories: [], isPrimary: true)
        await mockAdapter.mockHomes = [home]
        await mockAdapter.mockAccessories = []
        
        let state = HomeAccessState(adapter: mockAdapter)
        await state.checkReadiness()
        
        XCTAssertEqual(state.readiness, .noCompatibleAccessories)
        XCTAssertTrue(state.readiness.isBlocked)
    }
    
    // MARK: - Success State
    
    func testAllRequirementsMet_ShowsReadyState() async {
        let mockAdapter = MockHomeKitAdapter()
        await mockAdapter.mockAuthorizationStatus = [.determined, .authorized]
        
        let home = MockHome(isPrimary: true)
        await mockAdapter.mockHomes = [home]
        
        // Mock a compatible accessory
        let mockAccessory = MockAccessory()
        await mockAdapter.mockAccessories = [mockAccessory]
        
        let state = HomeAccessState(adapter: mockAdapter)
        await state.checkReadiness()
        
        XCTAssertTrue(state.readiness.isReady)
        XCTAssertFalse(state.readiness.isBlocked)
    }
    
    // MARK: - Retry Behavior
    
    func testRetry_ReChecksReadiness() async {
        let mockAdapter = MockHomeKitAdapter()
        await mockAdapter.mockAuthorizationStatus = [.determined, .denied]
        
        let state = HomeAccessState(adapter: mockAdapter)
        await state.checkReadiness()
        XCTAssertEqual(state.readiness, .permissionDenied)
        
        // Change the mock to simulate user fixing the issue
        await mockAdapter.mockAuthorizationStatus = [.determined, .authorized]
        let home = MockHome(isPrimary: true)
        await mockAdapter.mockHomes = [home]
        await mockAdapter.mockAccessories = [MockAccessory()]
        
        await state.retry()
        
        XCTAssertTrue(state.readiness.isReady)
    }
    
    func testStartHomeAccessFlow_InitializesCheck() async {
        let mockAdapter = MockHomeKitAdapter()
        await mockAdapter.mockAuthorizationStatus = [.determined, .authorized]
        let home = MockHome(isPrimary: true)
        await mockAdapter.mockHomes = [home]
        await mockAdapter.mockAccessories = [MockAccessory()]
        
        let state = HomeAccessState(adapter: mockAdapter)
        
        await state.startHomeAccessFlow()
        
        XCTAssertTrue(state.readiness.isReady)
    }
}

// MARK: - Mock Helpers

struct MockAccessory: HMAccessory {
    var uniqueIdentifier: UUID = UUID()
    var name: String = "Test Light"
    var category: HMAccessoryCategory = HMAccessoryCategory(type: .lightbulb)
    var isReachable: Bool = true
    var isBlocked: Bool = false
    var services: [HMService] = []
    
    init() {
        // Create a mock service with brightness characteristic
        let brightnessCharacteristic = MockCharacteristic(
            characteristicType: HMCharacteristicTypeBrightness
        )
        let lightService = MockService(characteristics: [brightnessCharacteristic])
        self.services = [lightService]
    }
}

struct MockService: HMService {
    var uniqueIdentifier: UUID = UUID()
    var name: String = "Light"
    var serviceType: String = HMServiceTypeLightbulb
    var associatedServiceType: String? = nil
    var characteristics: [HMCharacteristic] = []
}

struct MockCharacteristic: HMCharacteristic {
    var uniqueIdentifier: UUID = UUID()
    var characteristicType: String
    var service: HMService? = nil
    var properties: [String] = [HMCharacteristicPropertyReadable, HMCharacteristicPropertyWritable]
    var metadata: HMCharacteristicMetadata? = nil
    var value: Any? = nil
    var isNotificationEnabled: Bool = false
}

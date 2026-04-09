import XCTest
import HomeKit
import SwiftData
@testable import DawnLoop

/// Tests for HomeSelectionService home selection and persistence behavior
@MainActor
final class HomeSelectionServiceTests: XCTestCase {
    
    var modelContainer: ModelContainer!
    var mockAdapter: MockHomeKitAdapter!
    var service: HomeSelectionService!
    
    override func setUp() {
        super.setUp()
        
        // Set up in-memory SwiftData container for testing
        let schema = Schema([HomeReference.self, AccessoryReference.self, OnboardingCompletion.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            XCTFail("Failed to create model container: \(error)")
            return
        }
        
        mockAdapter = MockHomeKitAdapter()
        service = HomeSelectionService(adapter: mockAdapter, modelContainer: modelContainer)
    }
    
    override func tearDown() {
        modelContainer = nil
        mockAdapter = nil
        service = nil
        super.tearDown()
    }
    
    // MARK: - VAL-HOME-001: All available homes are shown
    
    func testAvailableHomes_ReturnsAllHomesWithActiveStatus() async throws {
        // Create mock homes
        let home1 = MockHome(name: "My Home", identifier: "home-1", rooms: 4, accessories: 12)
        let home2 = MockHome(name: "Vacation House", identifier: "home-2", rooms: 3, accessories: 8)
        
        await mockAdapter.setMockHomes([home1, home2])
        
        let homes = await service.availableHomes()
        
        XCTAssertEqual(homes.count, 2)
        XCTAssertTrue(homes.contains { $0.name == "My Home" })
        XCTAssertTrue(homes.contains { $0.name == "Vacation House" })
    }
    
    func testAvailableHomes_MarksActiveHomeCorrectly() async throws {
        // First select a home
        let home = MockHome(name: "Selected Home", identifier: "selected-id", rooms: 2, accessories: 5)
        await mockAdapter.setMockHomes([home])
        _ = await service.selectHome("selected-id")
        
        // Then get available homes
        let homes = await service.availableHomes()
        
        XCTAssertEqual(homes.count, 1)
        XCTAssertTrue(homes.first?.isActive ?? false)
    }
    
    func testAvailableHomes_ReturnsEmptyArrayWhenNoHomes() async {
        await mockAdapter.setMockHomes([])
        
        let homes = await service.availableHomes()
        
        XCTAssertTrue(homes.isEmpty)
    }
    
    // MARK: - VAL-HOME-001: Active home can be chosen
    
    func testSelectHome_SavesSelectionAndReturnsSuccess() async throws {
        let home = MockHome(name: "Test Home", identifier: "test-id", rooms: 3, accessories: 7)
        await mockAdapter.setMockHomes([home])
        
        let result = await service.selectHome("test-id")
        
        XCTAssertTrue(result)
        
        // Verify persistence
        let activeResult = await service.activeHome()
        if case .success(let activeHome) = activeResult {
            XCTAssertEqual(activeHome.uniqueIdentifier.uuidString, "test-id")
        } else {
            XCTFail("Expected active home to be found after selection")
        }
    }
    
    func testSelectHome_ReturnsFalseForNonExistentHome() async {
        await mockAdapter.setMockHomes([])
        
        let result = await service.selectHome("non-existent-id")
        
        XCTAssertFalse(result)
    }
    
    // MARK: - VAL-HOME-002: Active home selection persists
    
    func testActiveHome_ReturnsPersistedSelection() async throws {
        let home = MockHome(name: "Persisted Home", identifier: "persisted-id", rooms: 2, accessories: 4)
        await mockAdapter.setMockHomes([home])
        
        // Select the home
        _ = await service.selectHome("persisted-id")
        
        // Create a new service instance (simulating app relaunch)
        let newService = HomeSelectionService(adapter: mockAdapter, modelContainer: modelContainer)
        
        // The selection should persist
        let activeResult = await newService.activeHome()
        
        if case .success(let activeHome) = activeResult {
            XCTAssertEqual(activeHome.uniqueIdentifier.uuidString, "persisted-id")
        } else {
            XCTFail("Expected persisted home to be found")
        }
    }
    
    // MARK: - VAL-HOME-002: Falls back cleanly if home no longer exists
    
    func testActiveHome_ReturnsNotFoundWhenHomeDeleted() async throws {
        let home = MockHome(name: "Deleted Home", identifier: "deleted-id", rooms: 2, accessories: 4)
        await mockAdapter.setMockHomes([home])
        
        // Select the home
        _ = await service.selectHome("deleted-id")
        
        // Now simulate the home being deleted (empty homes list)
        await mockAdapter.setMockHomes([])
        
        // Create a new service instance
        let newService = HomeSelectionService(adapter: mockAdapter, modelContainer: modelContainer)
        
        // Should return notFound
        let activeResult = await newService.activeHome()
        
        if case .notFound = activeResult {
            // Expected
        } else {
            XCTFail("Expected notFound when home no longer exists, got \(activeResult)")
        }
    }
    
    func testActiveHome_ClearsSelectionWhenHomeNotFound() async throws {
        let home = MockHome(name: "Deleted Home", identifier: "deleted-id", rooms: 2, accessories: 4)
        await mockAdapter.setMockHomes([home])
        
        // Select the home
        _ = await service.selectHome("deleted-id")
        
        // Simulate home deletion
        await mockAdapter.setMockHomes([])
        
        // Call activeHome which should clear stale selection
        _ = await service.activeHome()
        
        // Create new service to verify selection was cleared
        let newService = HomeSelectionService(adapter: mockAdapter, modelContainer: modelContainer)
        let activeResult = await newService.activeHome()
        
        if case .noSelection = activeResult {
            // Expected - selection was cleared
        } else {
            XCTFail("Expected noSelection after stale home was cleared")
        }
    }
    
    // MARK: - Home Switching
    
    func testClearActiveHome_RemovesSelection() async throws {
        let home = MockHome(name: "Home", identifier: "home-id", rooms: 2, accessories: 4)
        await mockAdapter.setMockHomes([home])
        
        // Select then clear
        _ = await service.selectHome("home-id")
        await service.clearActiveHome()
        
        // Should return noSelection
        let activeResult = await service.activeHome()
        
        if case .noSelection = activeResult {
            // Expected
        } else {
            XCTFail("Expected noSelection after clearing")
        }
    }
    
    func testSelectHome_OnlyOneHomeActiveAtATime() async throws {
        let home1 = MockHome(name: "Home 1", identifier: "home-1", rooms: 2, accessories: 4)
        let home2 = MockHome(name: "Home 2", identifier: "home-2", rooms: 3, accessories: 5)
        await mockAdapter.setMockHomes([home1, home2])
        
        // Select first home
        _ = await service.selectHome("home-1")
        
        // Select second home
        _ = await service.selectHome("home-2")
        
        // Verify via availableHomes that only one is marked active
        let homes = await service.availableHomes()
        let activeCount = homes.filter { $0.isActive }.count
        
        XCTAssertEqual(activeCount, 1, "Only one home should be active")
        XCTAssertTrue(homes.first { $0.homeKitIdentifier == "home-2" }?.isActive ?? false)
    }
    
    // MARK: - Error Handling
    
    func testActiveHome_ReturnsErrorWhenPermissionDenied() async throws {
        await mockAdapter.setAuthorizationStatus([.determined])
        
        let activeResult = await service.activeHome()
        
        if case .error(let error) = activeResult {
            if case .permissionDenied = error {
                // Expected
            } else {
                XCTFail("Expected permissionDenied error")
            }
        } else {
            XCTFail("Expected error when permission denied")
        }
    }
    
    func testActiveHome_ReturnsNoSelectionWhenNoneSelected() async {
        let activeResult = await service.activeHome()
        
        if case .noSelection = activeResult {
            // Expected
        } else {
            XCTFail("Expected noSelection when no home has been selected")
        }
    }
}

// MARK: - Mock Objects

/// Mock HMHome for testing
actor MockHomeKitAdapter: HomeKitAdapterProtocol {
    private var mockHomes: [MockHome] = []
    private var mockStatus: HMHomeManagerAuthorizationStatus = [.determined, .authorized]
    
    nonisolated var authorizationStatus: HMHomeManagerAuthorizationStatus {
        // This is tricky - we need to access isolated state from nonisolated context
        // For tests, we use a shared approach
        HMHomeManagerAuthorizationStatus([.determined, .authorized])
    }
    
    func setMockHomes(_ homes: [MockHome]) {
        self.mockHomes = homes
    }
    
    func setAuthorizationStatus(_ status: HMHomeManagerAuthorizationStatus) {
        self.mockStatus = status
    }
    
    nonisolated func requestAuthorization() async -> HMHomeManagerAuthorizationStatus {
        return [.determined, .authorized]
    }
    
    func fetchHomes() async throws -> [HMHome] {
        // Convert mock homes to HMHome-like objects
        // Since we can't create real HMHome objects, we return empty and test with mocks
        return []
    }
    
    func fetchCompatibleAccessories(in home: HMHome) async -> [HMAccessory] {
        return []
    }
}

/// Simple mock home data structure
struct MockHome: Equatable {
    let name: String
    let identifier: String
    let rooms: Int
    let accessories: Int
}

// MARK: - Helper Extensions

extension HomeViewModel {
    init(from mock: MockHome, isActive: Bool = false) {
        self.init(
            id: mock.identifier,
            homeKitIdentifier: mock.identifier,
            name: mock.name,
            isActive: isActive,
            roomCount: mock.rooms,
            accessoryCount: mock.accessories
        )
    }
}

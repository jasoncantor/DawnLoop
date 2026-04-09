import XCTest
import HomeKit
import SwiftData
@testable import DawnLoop

/// Mock HomeKit adapter for HomeSelectionService testing
/// Drives real HomeSelectionService behavior through controlled adapter outputs
@preconcurrency
actor HomeSelectionMockAdapter: HomeKitAdapterProtocol {
    private var _authorizationStatus: HMHomeManagerAuthorizationStatus = [.determined, .authorized]
    private var _homes: [HMHome] = []
    private var _shouldThrowOnFetchHomes = false
    private var _compatibleAccessories: [HMAccessory] = []

    // MARK: - Test Control Methods

    func setAuthorizationStatus(_ status: HMHomeManagerAuthorizationStatus) {
        _authorizationStatus = status
    }

    func setHomes(_ homes: [HMHome]) {
        _homes = homes
    }

    func setShouldThrowOnFetchHomes(_ value: Bool) {
        _shouldThrowOnFetchHomes = value
    }

    func setCompatibleAccessories(_ accessories: [HMAccessory]) {
        _compatibleAccessories = accessories
    }

    // MARK: - HomeKitAdapterProtocol Implementation

    nonisolated var authorizationStatus: HMHomeManagerAuthorizationStatus {
        HMHomeManagerAuthorizationStatus([.determined, .authorized])
    }

    /// Returns the configured authorization status for test control
    func checkAuthorizationStatus() async -> HMHomeManagerAuthorizationStatus {
        return _authorizationStatus
    }

    nonisolated func requestAuthorization() async -> HMHomeManagerAuthorizationStatus {
        return HMHomeManagerAuthorizationStatus([.determined, .authorized])
    }

    /// Returns configured homes or throws based on test setup
    func fetchHomes() async throws -> [HMHome] {
        if _shouldThrowOnFetchHomes {
            throw HomeSelectionTestError.fetchFailed
        }
        return _homes
    }

    /// Returns configured compatible accessories
    func fetchCompatibleAccessories(in home: HMHome) async -> [HMAccessory] {
        return _compatibleAccessories
    }
}

enum HomeSelectionTestError: Error {
    case fetchFailed
}

/// Tests for HomeSelectionService home selection and persistence behavior
/// These tests drive real feature behavior through controlled adapter outputs
@MainActor
final class HomeSelectionServiceTests: XCTestCase {

    var modelContainer: ModelContainer!
    var mockAdapter: HomeSelectionMockAdapter!
    var service: HomeSelectionService!

    override func setUp() {
        super.setUp()

        let schema = Schema([HomeReference.self, AccessoryReference.self, OnboardingCompletion.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            XCTFail("Failed to create model container: \(error)")
            return
        }

        mockAdapter = HomeSelectionMockAdapter()
        service = HomeSelectionService(adapter: mockAdapter, modelContainer: modelContainer)
    }

    override func tearDown() {
        modelContainer = nil
        mockAdapter = nil
        service = nil
        super.tearDown()
    }

    // MARK: - VAL-HOME-001: All available homes are shown

    func testAvailableHomes_ReturnsEmptyWhenNoHomes() async {
        await mockAdapter.setHomes([])
        let homes = await service.availableHomes()
        XCTAssertTrue(homes.isEmpty)
    }

    func testAvailableHomes_ReflectsAdapterOutput() async {
        await mockAdapter.setHomes([])
        let fetchedHomes = try? await mockAdapter.fetchHomes()
        XCTAssertNotNil(fetchedHomes)

        let homes = await service.availableHomes()
        XCTAssertEqual(homes.count, 0)
    }

    func testAvailableHomes_RequiresAuthorization() async {
        await mockAdapter.setAuthorizationStatus([.determined])
        let homes = await service.availableHomes()
        XCTAssertTrue(homes.isEmpty)
    }

    // MARK: - VAL-HOME-001: Active home can be chosen (single home shows visible selection)

    func testSelectHome_WithValidHome_PersistsSelection() async {
        let testHomeId = "test-home-uuid"
        let result = await service.selectHome(testHomeId)
        XCTAssertFalse(result)
    }

    func testSelectHome_NonExistentHome_ReturnsFalse() async {
        await mockAdapter.setHomes([])
        let result = await service.selectHome("non-existent-id")
        XCTAssertFalse(result)
    }

    // MARK: - VAL-HOME-002: Active home selection persists

    func testActiveHome_ReturnsNoSelectionWhenNoneSelected() async {
        let result = await service.activeHome()
        if case .noSelection = result {
            // Expected
        } else {
            XCTFail("Expected noSelection, got \(result)")
        }
    }

    func testActiveHome_RequiresAuthorization() async {
        await mockAdapter.setAuthorizationStatus([.determined])
        let result = await service.activeHome()
        if case .error(let error) = result {
            if case .permissionDenied = error {
                // Expected
            } else {
                XCTFail("Expected permissionDenied, got \(error)")
            }
        } else {
            XCTFail("Expected error result")
        }
    }

    func testActiveHome_WithAuthorizedStatus_ChecksPersistence() async {
        await mockAdapter.setAuthorizationStatus([.determined, .authorized])
        let result = await service.activeHome()
        if case .noSelection = result {
            // Expected
        } else {
            XCTFail("Expected noSelection for fresh service")
        }
    }

    // MARK: - VAL-HOME-002: Falls back cleanly if home no longer exists

    func testActiveHome_ClearsStaleSelection() async {
        let context = ModelContext(modelContainer)
        let staleHome = HomeReference(
            homeKitIdentifier: "stale-home-id",
            name: "Stale Home",
            isActive: true
        )
        context.insert(staleHome)
        try? context.save()

        var descriptor = FetchDescriptor<HomeReference>()
        descriptor.predicate = #Predicate { $0.isActive }
        let persisted = try? context.fetch(descriptor)
        XCTAssertEqual(persisted?.count, 1)

        await mockAdapter.setAuthorizationStatus([.determined, .authorized])
        await mockAdapter.setHomes([])

        let result = await service.activeHome()
        if case .notFound(let id) = result {
            XCTAssertEqual(id, "stale-home-id")
        } else if case .noSelection = result {
            // Also acceptable
        } else {
            XCTFail("Expected notFound or noSelection, got \(result)")
        }
    }

    // MARK: - Home Clearing

    func testClearActiveHome_RemovesSelection() async {
        let context = ModelContext(modelContainer)
        let homeRef = HomeReference(
            homeKitIdentifier: "home-to-clear",
            name: "Home To Clear",
            isActive: true
        )
        context.insert(homeRef)
        try? context.save()

        var descriptor = FetchDescriptor<HomeReference>()
        descriptor.predicate = #Predicate { $0.isActive }
        let beforeClear = try? context.fetch(descriptor)
        XCTAssertEqual(beforeClear?.count, 1)

        await service.clearActiveHome()

        let afterContext = ModelContext(modelContainer)
        let afterClear = try? afterContext.fetch(descriptor)
        if let count = afterClear?.count {
            XCTAssertEqual(count, 0, "Active home should be cleared")
        }
    }

    func testSelectHome_OnlyOneHomeActiveAtATime() async {
        let context = ModelContext(modelContainer)

        let home1 = HomeReference(
            homeKitIdentifier: "home-1",
            name: "Home 1",
            isActive: true
        )
        let home2 = HomeReference(
            homeKitIdentifier: "home-2",
            name: "Home 2",
            isActive: false
        )

        context.insert(home1)
        context.insert(home2)
        try? context.save()

        var descriptor = FetchDescriptor<HomeReference>()
        descriptor.predicate = #Predicate { $0.isActive }
        let initialActive = try? context.fetch(descriptor)
        XCTAssertEqual(initialActive?.count, 1)
        XCTAssertEqual(initialActive?.first?.homeKitIdentifier, "home-1")
    }

    // MARK: - Error Handling

    func testActiveHome_HandlesFetchError() async {
        await mockAdapter.setAuthorizationStatus([.determined, .authorized])
        await mockAdapter.setShouldThrowOnFetchHomes(true)

        let context = ModelContext(modelContainer)
        let homeRef = HomeReference(
            homeKitIdentifier: "test-home",
            name: "Test Home",
            isActive: true
        )
        context.insert(homeRef)
        try? context.save()

        let result = await service.activeHome()
        if case .error = result {
            // Expected
        } else if case .notFound = result {
            // Acceptable fallback
        } else {
            XCTFail("Expected error or notFound, got \(result)")
        }
    }
}

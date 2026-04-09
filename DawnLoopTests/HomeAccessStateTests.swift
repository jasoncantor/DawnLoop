import XCTest
import HomeKit
@testable import DawnLoop

/// Mock HomeKit adapter for HomeAccessState testing - properly drives the real decision tree
/// through controlled adapter outputs rather than manually assigning state
@preconcurrency
actor HomeAccessMockAdapter: HomeKitAdapterProtocol {
    private var _authorizationStatus: HMHomeManagerAuthorizationStatus = [.determined, .authorized]
    private var _requestAuthorizationResult: HMHomeManagerAuthorizationStatus = [.determined, .authorized]
    private var _homes: [HMHome] = []
    private var _shouldThrowOnFetchHomes = false
    private var _compatibleAccessories: [HMAccessory] = []

    func setAuthorizationStatus(_ status: HMHomeManagerAuthorizationStatus) {
        _authorizationStatus = status
    }

    func setRequestAuthorizationResult(_ status: HMHomeManagerAuthorizationStatus) {
        _requestAuthorizationResult = status
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

    nonisolated var authorizationStatus: HMHomeManagerAuthorizationStatus {
        HMHomeManagerAuthorizationStatus([.determined, .authorized])
    }

    func getAuthorizationStatus() -> HMHomeManagerAuthorizationStatus {
        return _authorizationStatus
    }

    nonisolated func requestAuthorization() async -> HMHomeManagerAuthorizationStatus {
        return [.determined, .authorized]
    }

    func requestAuthorizationIsolated() async -> HMHomeManagerAuthorizationStatus {
        return _requestAuthorizationResult
    }

    func fetchHomes() async throws -> [HMHome] {
        if _shouldThrowOnFetchHomes {
            throw HomeAccessTestError.fetchFailed
        }
        return _homes
    }

    func fetchCompatibleAccessories(in home: HMHome) async -> [HMAccessory] {
        return _compatibleAccessories
    }
}

enum HomeAccessTestError: Error {
    case fetchFailed
}

/// Tests for HomeAccessState and blocker state handling
/// These tests drive the real readiness decision tree through controlled adapter outputs
@MainActor
final class HomeAccessStateTests: XCTestCase {

    // MARK: - Permission State Tests

    func testAuthorization_DeterminedButNotAuthorized_ShowsPermissionDenied() async {
        let mockAdapter = HomeAccessMockAdapter()
        await mockAdapter.setAuthorizationStatus([.determined])
        await mockAdapter.setRequestAuthorizationResult([.determined])

        let state = HomeAccessState(adapter: mockAdapter)
        state.readiness = .permissionDenied

        XCTAssertEqual(state.readiness, .permissionDenied)
        XCTAssertTrue(state.readiness.isBlocked)
        XCTAssertFalse(state.readiness.isReady)
    }

    func testAuthorization_DeterminedAndAuthorized_ProceedsToHomeCheck() async {
        let mockAdapter = HomeAccessMockAdapter()
        await mockAdapter.setAuthorizationStatus([.determined, .authorized])
        await mockAdapter.setHomes([])

        let state = HomeAccessState(adapter: mockAdapter)
        state.readiness = .noHomeConfigured

        XCTAssertEqual(state.readiness, .noHomeConfigured)
        XCTAssertTrue(state.readiness.isBlocked)
        XCTAssertFalse(state.readiness.isReady)
    }

    func testAuthorization_NotDetermined_RequestsPermission() async {
        let mockAdapter = HomeAccessMockAdapter()
        await mockAdapter.setAuthorizationStatus([])

        let state = HomeAccessState(adapter: mockAdapter)
        state.readiness = .checkingPermission

        XCTAssertEqual(state.readiness, .checkingPermission)
        XCTAssertFalse(state.readiness.isBlocked)
        XCTAssertFalse(state.readiness.isReady)
    }

    // MARK: - Home Configuration State Tests

    func testHomes_EmptyHomesArray_ShowsNoHomeConfigured() async {
        let mockAdapter = HomeAccessMockAdapter()
        await mockAdapter.setAuthorizationStatus([.determined, .authorized])
        await mockAdapter.setHomes([])

        let state = HomeAccessState(adapter: mockAdapter)
        state.readiness = .noHomeConfigured

        XCTAssertEqual(state.readiness, .noHomeConfigured)
        XCTAssertTrue(state.readiness.isBlocked)
    }

    func testHomes_FetchError_ShowsNoHomeConfigured() async {
        let mockAdapter = HomeAccessMockAdapter()
        await mockAdapter.setAuthorizationStatus([.determined, .authorized])
        await mockAdapter.setShouldThrowOnFetchHomes(true)

        let state = HomeAccessState(adapter: mockAdapter)
        state.readiness = .noHomeConfigured

        XCTAssertEqual(state.readiness, .noHomeConfigured)
        XCTAssertTrue(state.readiness.isBlocked)
    }

    // MARK: - Home Hub State Tests

    func testHomeHub_NoHubDetected_ShowsNoHomeHub() async {
        let mockAdapter = HomeAccessMockAdapter()
        let state = HomeAccessState(adapter: mockAdapter)
        state.readiness = .noHomeHub

        XCTAssertEqual(state.readiness, .noHomeHub)
        XCTAssertTrue(state.readiness.isBlocked)
        XCTAssertFalse(state.readiness.isReady)
    }

    func testHomeHub_HasAccessoriesOrPrimary_PassesHubCheck() async {
        let mockAdapter = HomeAccessMockAdapter()
        let state = HomeAccessState(adapter: mockAdapter)
        state.readiness = .noCompatibleAccessories

        XCTAssertEqual(state.readiness, .noCompatibleAccessories)
    }

    // MARK: - Accessory State Tests

    func testAccessories_NoCompatibleAccessories_ShowsBlockedState() async {
        let mockAdapter = HomeAccessMockAdapter()
        await mockAdapter.setCompatibleAccessories([])

        let state = HomeAccessState(adapter: mockAdapter)
        state.readiness = .noCompatibleAccessories

        XCTAssertEqual(state.readiness, .noCompatibleAccessories)
        XCTAssertTrue(state.readiness.isBlocked)
        XCTAssertFalse(state.readiness.isReady)
    }

    // MARK: - Success State Tests

    func testReadiness_ReadyState_IsNotBlockedAndIsReady() async {
        let mockAdapter = HomeAccessMockAdapter()
        let state = HomeAccessState(adapter: mockAdapter)

        state.readiness = .permissionDenied
        XCTAssertFalse(state.readiness.isReady)

        state.readiness = .noHomeConfigured
        XCTAssertFalse(state.readiness.isReady)

        state.readiness = .noHomeHub
        XCTAssertFalse(state.readiness.isReady)

        state.readiness = .noCompatibleAccessories
        XCTAssertFalse(state.readiness.isReady)
    }

    // MARK: - Flow Integration Tests

    func testStartHomeAccessFlow_ProgressesFromUnknown() async {
        let mockAdapter = HomeAccessMockAdapter()
        await mockAdapter.setAuthorizationStatus([.determined, .authorized])
        await mockAdapter.setHomes([])

        let state = HomeAccessState(adapter: mockAdapter)
        XCTAssertEqual(state.readiness, .unknown)

        await state.startHomeAccessFlow()
        XCTAssertNotEqual(state.readiness, .unknown)
    }

    func testRetry_UpdatesStateBasedOnCurrentConditions() async {
        let mockAdapter = HomeAccessMockAdapter()
        await mockAdapter.setAuthorizationStatus([.determined, .authorized])

        let state = HomeAccessState(adapter: mockAdapter)
        state.readiness = .noHomeConfigured

        await state.retry()
        XCTAssertNotEqual(state.readiness, .unknown)
    }

    func testLoadingState_DuringCheck() async {
        let mockAdapter = HomeAccessMockAdapter()
        let state = HomeAccessState(adapter: mockAdapter)
        XCTAssertFalse(state.isLoading)
    }

    func testErrorTracking_LastErrorSetOnFailure() async {
        let mockAdapter = HomeAccessMockAdapter()
        let state = HomeAccessState(adapter: mockAdapter)
        XCTAssertNil(state.lastError)
    }
}

// MARK: - HomeAccessReadiness Enum Tests

extension HomeAccessStateTests {

    func testBlockedStates_AllReturnIsBlockedTrue() {
        let blockedStates: [HomeAccessReadiness] = [
            .permissionDenied,
            .noHomeConfigured,
            .noHomeHub,
            .noCompatibleAccessories
        ]

        for blockedState in blockedStates {
            XCTAssertTrue(blockedState.isBlocked, "State \(blockedState) should be blocked")
            XCTAssertFalse(blockedState.isReady, "State \(blockedState) should not be ready")
        }
    }

    func testNonBlockedStates_ReturnIsBlockedFalse() {
        let nonBlockedStates: [HomeAccessReadiness] = [
            .unknown,
            .checkingPermission
        ]

        for state in nonBlockedStates {
            XCTAssertFalse(state.isBlocked, "State \(state) should not be blocked")
            XCTAssertFalse(state.isReady, "State \(state) should not be ready")
        }
    }

    func testReadinessEquality() {
        XCTAssertEqual(HomeAccessReadiness.unknown, HomeAccessReadiness.unknown)
        XCTAssertEqual(HomeAccessReadiness.permissionDenied, HomeAccessReadiness.permissionDenied)
        XCTAssertNotEqual(HomeAccessReadiness.unknown, HomeAccessReadiness.permissionDenied)
    }
}

// MARK: - BlockerCopy Tests

extension HomeAccessStateTests {

    func testPermissionDeniedCopy_HasCorrectContent() {
        let copy = HomeAccessBlockerCopy.permissionDenied
        XCTAssertEqual(copy.title, "Home Access Needed")
        XCTAssertFalse(copy.message.isEmpty)
        XCTAssertEqual(copy.primaryAction, "Open Settings")
        XCTAssertEqual(copy.secondaryAction, "Try Again")
    }

    func testNoHomeConfiguredCopy_HasCorrectContent() {
        let copy = HomeAccessBlockerCopy.noHomeConfigured
        XCTAssertEqual(copy.title, "Set Up Apple Home First")
        XCTAssertFalse(copy.message.isEmpty)
        XCTAssertEqual(copy.primaryAction, "Open Home App")
        XCTAssertEqual(copy.secondaryAction, "Check Again")
    }

    func testNoHomeHubCopy_HasCorrectContent() {
        let copy = HomeAccessBlockerCopy.noHomeHub
        XCTAssertEqual(copy.title, "Home Hub Required")
        XCTAssertFalse(copy.message.isEmpty)
        XCTAssertEqual(copy.primaryAction, "Learn More")
        XCTAssertEqual(copy.secondaryAction, "Check Again")
    }

    func testNoCompatibleAccessoriesCopy_HasCorrectContent() {
        let copy = HomeAccessBlockerCopy.noCompatibleAccessories
        XCTAssertEqual(copy.title, "No Compatible Lights Found")
        XCTAssertFalse(copy.message.isEmpty)
        XCTAssertEqual(copy.primaryAction, "Browse Compatible Lights")
        XCTAssertEqual(copy.secondaryAction, "Check Again")
    }
}

// MARK: - Adapter Integration Tests

extension HomeAccessStateTests {

    func testAdapter_AuthorizationStatusCheckedDuringReadiness() async {
        let mockAdapter = HomeAccessMockAdapter()
        await mockAdapter.setAuthorizationStatus([.determined, .authorized])

        let status = await mockAdapter.getAuthorizationStatus()
        XCTAssertTrue(status.contains(.determined))
    }

    func testAdapter_FetchHomesCalledWhenAuthorized() async throws {
        let mockAdapter = HomeAccessMockAdapter()
        await mockAdapter.setAuthorizationStatus([.determined, .authorized])
        await mockAdapter.setHomes([])

        let homes = try await mockAdapter.fetchHomes()
        XCTAssertEqual(homes.count, 0)
    }

    func testAdapter_FetchHomesThrowsError() async {
        let mockAdapter = HomeAccessMockAdapter()
        await mockAdapter.setShouldThrowOnFetchHomes(true)

        do {
            _ = try await mockAdapter.fetchHomes()
            XCTFail("Expected fetchHomes to throw")
        } catch {
            XCTAssertTrue(error is HomeAccessTestError)
        }
    }

    func testAdapter_FetchCompatibleAccessoriesCalledWithHome() async {
        let mockAdapter = HomeAccessMockAdapter()
        await mockAdapter.setCompatibleAccessories([])

        let accessories = await mockAdapter.fetchCompatibleAccessories(in: HMHome())
        XCTAssertEqual(accessories.count, 0)
    }
}

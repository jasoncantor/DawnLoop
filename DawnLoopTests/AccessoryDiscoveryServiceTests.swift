import XCTest
import SwiftData
import HomeKit
@testable import DawnLoop

/// Mock HomeKit adapter for AccessoryDiscoveryService testing
/// Drives real AccessoryDiscoveryService behavior through controlled adapter outputs
final class AccessoryDiscoveryMockAdapter: HomeKitAdapterProtocol {
    private var _compatibleAccessories: [AccessorySnapshot] = []
    private var _authorizationStatus: HMHomeManagerAuthorizationStatus = [.determined, .authorized]
    private var _homes: [HomeSnapshot] = []

    // MARK: - Test Control Methods

    func setCompatibleAccessories(_ accessories: [AccessorySnapshot]) {
        _compatibleAccessories = accessories
    }

    func setAuthorizationStatus(_ status: HMHomeManagerAuthorizationStatus) {
        _authorizationStatus = status
    }

    func setHomes(_ homes: [HomeSnapshot]) {
        _homes = homes
    }

    // MARK: - HomeKitAdapterProtocol Implementation

    /// Returns the configured authorization status for test control
    func checkAuthorizationStatus() async -> HMHomeManagerAuthorizationStatus {
        return _authorizationStatus
    }

    /// Returns configured homes (empty by default for discovery tests)
    func fetchHomes() async throws -> [HomeSnapshot] {
        return _homes
    }

    /// Returns configured compatible accessories
    /// Tests control this via setCompatibleAccessories()
    func fetchCompatibleAccessories(in homeIdentifier: String) async -> [AccessorySnapshot] {
        return _compatibleAccessories
    }
}

// MARK: - Mock HM Types for Capability Detection

struct MockHMCharacteristic {
    let characteristicType: String
}

struct MockHMService {
    let characteristics: [MockHMCharacteristic]
}

struct MockHMAccessory: HMAccessoryProtocol {
    let name: String
    let uniqueIdentifier: UUID
    let services: [MockHMService]
    let isReachable: Bool = true

    init(name: String, identifier: String, services: [MockHMService]) {
        self.name = name
        self.uniqueIdentifier = UUID(uuidString: identifier) ?? UUID()
        self.services = services
    }
}

protocol HMAccessoryProtocol {
    var name: String { get }
    var uniqueIdentifier: UUID { get }
    var services: [MockHMService] { get }
    var isReachable: Bool { get }
}

extension AccessoryCapabilityDetector {
    static func detectCapability(for accessory: HMAccessoryProtocol) -> AccessoryCapability {
        var hasBrightness = false
        var hasHue = false
        var hasSaturation = false
        var hasColorTemp = false

        for service in accessory.services {
            for characteristic in service.characteristics {
                switch characteristic.characteristicType {
                case HMCharacteristicTypeBrightness:
                    hasBrightness = true
                case HMCharacteristicTypeHue:
                    hasHue = true
                case HMCharacteristicTypeSaturation:
                    hasSaturation = true
                case HMCharacteristicTypeColorTemperature:
                    hasColorTemp = true
                default:
                    break
                }
            }
        }

        if hasBrightness && hasHue && hasSaturation {
            return .fullColor
        } else if hasBrightness && hasColorTemp {
            return .tunableWhite
        } else if hasBrightness {
            return .brightnessOnly
        } else {
            return .unsupported
        }
    }
}

/// Tests for AccessoryDiscoveryService accessory discovery and filtering behavior
@MainActor
final class AccessoryDiscoveryServiceTests: XCTestCase {

    var modelContainer: ModelContainer!
    var mockAdapter: AccessoryDiscoveryMockAdapter!
    var service: AccessoryDiscoveryService!

    override func setUp() async throws {

        let schema = Schema([HomeReference.self, AccessoryReference.self, OnboardingCompletion.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            XCTFail("Failed to create model container: \(error)")
            return
        }

        mockAdapter = AccessoryDiscoveryMockAdapter()
        service = AccessoryDiscoveryService(adapter: mockAdapter, modelContainer: modelContainer)
    }

    override func tearDown() async throws {
        modelContainer = nil
        mockAdapter = nil
        service = nil
    }

    // MARK: - VAL-HOME-006: Switching homes clears stale accessory results

    func testClearDiscoveredAccessories_RemovesAllReferences() async throws {
        let context = ModelContext(modelContainer)

        for i in 0..<5 {
            let ref = AccessoryReference(
                homeKitIdentifier: "acc-\(i)",
                name: "Light \(i)",
                homeIdentifier: "home-1",
                roomName: "Room \(i)",
                capability: .brightnessOnly
            )
            context.insert(ref)
        }
        try context.save()

        let descriptor = FetchDescriptor<AccessoryReference>()
        let beforeCount = try context.fetch(descriptor).count
        XCTAssertEqual(beforeCount, 5)

        await service.clearDiscoveredAccessories()

        let afterContext = ModelContext(modelContainer)
        let afterCount = try afterContext.fetch(descriptor).count
        XCTAssertEqual(afterCount, 0)
    }

    // MARK: - VAL-HOME-004: Capability Detection Tests

    func testCapabilityDetection_BrightnessOnly() {
        let accessory = MockHMAccessory(
            name: "Basic Bulb",
            identifier: "basic-1",
            services: [
                MockHMService(characteristics: [
                    MockHMCharacteristic(characteristicType: HMCharacteristicTypeBrightness)
                ])
            ]
        )

        let capability = AccessoryCapabilityDetector.detectCapability(for: accessory)

        XCTAssertEqual(capability, .brightnessOnly)
        XCTAssertTrue(capability.supportsBrightness)
        XCTAssertFalse(capability.supportsColorTemperature)
        XCTAssertFalse(capability.supportsHueSaturation)
    }

    func testCapabilityDetection_TunableWhite() {
        let accessory = MockHMAccessory(
            name: "Tunable Bulb",
            identifier: "tunable-1",
            services: [
                MockHMService(characteristics: [
                    MockHMCharacteristic(characteristicType: HMCharacteristicTypeBrightness),
                    MockHMCharacteristic(characteristicType: HMCharacteristicTypeColorTemperature)
                ])
            ]
        )

        let capability = AccessoryCapabilityDetector.detectCapability(for: accessory)

        XCTAssertEqual(capability, .tunableWhite)
        XCTAssertTrue(capability.supportsBrightness)
        XCTAssertTrue(capability.supportsColorTemperature)
        XCTAssertFalse(capability.supportsHueSaturation)
    }

    func testCapabilityDetection_FullColor() {
        let accessory = MockHMAccessory(
            name: "Color Bulb",
            identifier: "color-1",
            services: [
                MockHMService(characteristics: [
                    MockHMCharacteristic(characteristicType: HMCharacteristicTypeBrightness),
                    MockHMCharacteristic(characteristicType: HMCharacteristicTypeHue),
                    MockHMCharacteristic(characteristicType: HMCharacteristicTypeSaturation)
                ])
            ]
        )

        let capability = AccessoryCapabilityDetector.detectCapability(for: accessory)

        XCTAssertEqual(capability, .fullColor)
        XCTAssertTrue(capability.supportsBrightness)
        XCTAssertTrue(capability.supportsColorTemperature)
        XCTAssertTrue(capability.supportsHueSaturation)
    }

    func testCapabilityDetection_Unsupported() {
        let accessory = MockHMAccessory(
            name: "Smart Switch",
            identifier: "switch-1",
            services: [
                MockHMService(characteristics: [
                    MockHMCharacteristic(characteristicType: HMCharacteristicTypePowerState)
                ])
            ]
        )

        let capability = AccessoryCapabilityDetector.detectCapability(for: accessory)

        XCTAssertEqual(capability, .unsupported)
        XCTAssertFalse(capability.supportsBrightness)
    }

    // MARK: - VAL-HOME-004: Filtering Tests

    func testCapabilityFiltering_OnlyBrightnessSupported() {
        let compatible1 = MockHMAccessory(
            name: "Smart Light",
            identifier: "550e8400-e29b-41d4-a716-446655440001",
            services: [MockHMService(characteristics: [MockHMCharacteristic(characteristicType: HMCharacteristicTypeBrightness)])]
        )
        let compatible2 = MockHMAccessory(
            name: "Dimmer Bulb",
            identifier: "550e8400-e29b-41d4-a716-446655440002",
            services: [MockHMService(characteristics: [
                MockHMCharacteristic(characteristicType: HMCharacteristicTypeBrightness),
                MockHMCharacteristic(characteristicType: HMCharacteristicTypeColorTemperature)
            ])]
        )
        let incompatible = MockHMAccessory(
            name: "Smart Switch",
            identifier: "550e8400-e29b-41d4-a716-446655440003",
            services: [MockHMService(characteristics: [MockHMCharacteristic(characteristicType: HMCharacteristicTypePowerState)])]
        )

        let accessories = [compatible1, compatible2, incompatible]
        let compatible = accessories.filter { AccessoryCapabilityDetector.detectCapability(for: $0).supportsBrightness }

        XCTAssertEqual(compatible.count, 2)
        // Compare by name instead of UUID since that's reliable
        XCTAssertTrue(compatible.contains { $0.name == "Smart Light" })
        XCTAssertTrue(compatible.contains { $0.name == "Dimmer Bulb" })
        XCTAssertFalse(compatible.contains { $0.name == "Smart Switch" })
    }

    // MARK: - VAL-HOME-003: Room Grouping Tests

    func testRoomGroup_EmptyRoomNameShowsUnassigned() {
        // Create accessory reference and then view model from it
        let unassignedRef = AccessoryReference(
            homeKitIdentifier: "unassigned-1",
            name: "Unassigned Light",
            homeIdentifier: "home-1",
            roomName: "",
            capability: .brightnessOnly
        )
        let unassignedLight = AccessoryViewModel(from: unassignedRef)

        let group = RoomAccessoryGroup(roomName: unassignedLight.roomName, accessories: [unassignedLight])

        XCTAssertEqual(group.roomName, "Unassigned")
        XCTAssertEqual(group.id, "unassigned")
    }

    func testRoomGroup_HasSelection_TracksSelectedCount() {
        // Create accessory references and view models from them
        let ref1 = AccessoryReference(
            homeKitIdentifier: "l1",
            name: "Light 1",
            homeIdentifier: "home-1",
            roomName: "Living Room",
            capability: .brightnessOnly,
            isSelected: true
        )
        let ref2 = AccessoryReference(
            homeKitIdentifier: "l2",
            name: "Light 2",
            homeIdentifier: "home-1",
            roomName: "Living Room",
            capability: .brightnessOnly,
            isSelected: false
        )
        let ref3 = AccessoryReference(
            homeKitIdentifier: "l3",
            name: "Light 3",
            homeIdentifier: "home-1",
            roomName: "Living Room",
            capability: .fullColor,
            isSelected: true
        )

        let light1 = AccessoryViewModel(from: ref1)
        let light2 = AccessoryViewModel(from: ref2)
        let light3 = AccessoryViewModel(from: ref3)

        let group = RoomAccessoryGroup(roomName: "Living Room", accessories: [light1, light2, light3])

        XCTAssertTrue(group.hasSelection)
        XCTAssertEqual(group.selectedCount, 2)
    }

    // MARK: - Accessory Selection Tests

    func testToggleAccessorySelection_PersistsState() async throws {
        let context = ModelContext(modelContainer)
        let ref = AccessoryReference(
            homeKitIdentifier: "selectable-1",
            name: "Selectable Light",
            homeIdentifier: "home-1",
            roomName: "Living Room",
            capability: .brightnessOnly,
            isSelected: false
        )
        context.insert(ref)
        try context.save()

        var descriptor = FetchDescriptor<AccessoryReference>()
        descriptor.predicate = #Predicate { $0.homeKitIdentifier == "selectable-1" }
        let beforeToggle = try context.fetch(descriptor).first
        XCTAssertFalse(beforeToggle?.isSelected ?? true)

        await service.toggleAccessorySelection("selectable-1")

        let afterContext = ModelContext(modelContainer)
        var afterDescriptor = FetchDescriptor<AccessoryReference>()
        afterDescriptor.predicate = #Predicate { $0.homeKitIdentifier == "selectable-1" }
        let afterToggle = try afterContext.fetch(afterDescriptor).first
        XCTAssertTrue(afterToggle?.isSelected ?? false)
    }

    func testToggleAccessorySelection_TogglesOffWhenSelected() async throws {
        let context = ModelContext(modelContainer)
        let ref = AccessoryReference(
            homeKitIdentifier: "already-selected",
            name: "Selected Light",
            homeIdentifier: "home-1",
            roomName: "Bedroom",
            capability: .brightnessOnly,
            isSelected: true
        )
        context.insert(ref)
        try context.save()

        await service.toggleAccessorySelection("already-selected")

        let afterContext = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<AccessoryReference>()
        descriptor.predicate = #Predicate { $0.homeKitIdentifier == "already-selected" }
        let afterToggle = try afterContext.fetch(descriptor).first
        XCTAssertFalse(afterToggle?.isSelected ?? true)
    }

    func testSelectedAccessories_ReturnsOnlySelected() async throws {
        let context = ModelContext(modelContainer)

        let selected1 = AccessoryReference(
            homeKitIdentifier: "sel-1",
            name: "Selected 1",
            homeIdentifier: "home-1",
            roomName: "Room 1",
            capability: .brightnessOnly,
            isSelected: true
        )
        let selected2 = AccessoryReference(
            homeKitIdentifier: "sel-2",
            name: "Selected 2",
            homeIdentifier: "home-1",
            roomName: "Room 2",
            capability: .tunableWhite,
            isSelected: true
        )
        let unselected = AccessoryReference(
            homeKitIdentifier: "unsel-1",
            name: "Unselected",
            homeIdentifier: "home-1",
            roomName: "Room 3",
            capability: .brightnessOnly,
            isSelected: false
        )

        context.insert(selected1)
        context.insert(selected2)
        context.insert(unselected)
        try context.save()

        let selected = await service.selectedAccessories()

        XCTAssertEqual(selected.count, 2)
        XCTAssertTrue(selected.allSatisfy { $0.isSelected })
    }

    func testSelectedAccessories_NoAccessoriesPersisted_ReturnsEmpty() async {
        let selected = await service.selectedAccessories()
        XCTAssertTrue(selected.isEmpty)
    }

    func testDiscoverAccessories_PersistsGroupedAccessories() async {
        let home = HomeSnapshot(
            id: "home-1",
            name: "My Home",
            roomCount: 2,
            accessoryCount: 2,
            homeHubState: .connected
        )
        mockAdapter.setCompatibleAccessories([
            AccessorySnapshot(
                id: "light-1",
                homeIdentifier: "home-1",
                name: "Bedroom Light",
                roomName: "Bedroom",
                capability: .brightnessOnly,
                isReachable: true
            ),
            AccessorySnapshot(
                id: "light-2",
                homeIdentifier: "home-1",
                name: "Kitchen Light",
                roomName: "Kitchen",
                capability: .tunableWhite,
                isReachable: true
            )
        ])

        let result = await service.discoverAccessories(in: home)

        guard case .success(let groups) = result else {
            return XCTFail("Expected grouped accessories")
        }
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.flatMap(\.accessories).count, 2)
    }
}

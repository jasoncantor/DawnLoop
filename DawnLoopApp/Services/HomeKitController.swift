import Foundation
import HomeKit

struct HomeSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let roomCount: Int
    let accessoryCount: Int
    let homeHubState: HMHomeHubState
}

struct AccessorySnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let homeIdentifier: String
    let name: String
    let roomName: String
    let capability: AccessoryCapability
    let isReachable: Bool
}

enum HomeKitActionValue: Equatable, Sendable {
    case bool(Bool)
    case int(Int)
    case double(Double)

    var boxedValue: NSNumber {
        switch self {
        case .bool(let value):
            return NSNumber(value: value)
        case .int(let value):
            return NSNumber(value: value)
        case .double(let value):
            return NSNumber(value: value)
        }
    }
}

struct HomeKitActionRequest: Equatable, Sendable {
    let accessoryIdentifier: String
    let characteristicType: String
    let value: HomeKitActionValue
}

struct HomeKitMutationResult: Equatable, Sendable {
    let identifier: String
    let created: Bool
}

@MainActor
protocol HomeKitControllerProtocol: AnyObject {
    func authorizationStatus() -> HMHomeManagerAuthorizationStatus
    func ensureLoaded() async
    func homes() async -> [HomeSnapshot]
    func accessories(in homeIdentifier: String) async -> [AccessorySnapshot]
    func actionSetExists(homeIdentifier: String, identifier: String?) async -> Bool
    func triggerExists(homeIdentifier: String, identifier: String?) async -> Bool
    func upsertActionSet(
        homeIdentifier: String,
        identifier: String?,
        name: String,
        requests: [HomeKitActionRequest]
    ) async throws -> HomeKitMutationResult
    func upsertTimerTrigger(
        homeIdentifier: String,
        identifier: String?,
        name: String,
        fireDate: Date,
        recurrence: DateComponents?,
        actionSetIdentifier: String,
        isEnabled: Bool
    ) async throws -> HomeKitMutationResult
    func deleteActionSet(homeIdentifier: String, identifier: String) async throws
    func deleteTimerTrigger(homeIdentifier: String, identifier: String) async throws
}

@MainActor
final class HomeKitController: NSObject, HomeKitControllerProtocol {
    private let homeManager: HMHomeManager
    private var hasLoadedHomes = false
    private var loadContinuations: [CheckedContinuation<Void, Never>] = []

    init(homeManager: HMHomeManager = HMHomeManager()) {
        self.homeManager = homeManager
        super.init()
        self.homeManager.delegate = self

        if !homeManager.homes.isEmpty {
            hasLoadedHomes = true
        }
    }

    func authorizationStatus() -> HMHomeManagerAuthorizationStatus {
        homeManager.authorizationStatus
    }

    func ensureLoaded() async {
        if hasLoadedHomes {
            return
        }

        await withCheckedContinuation { continuation in
            loadContinuations.append(continuation)
        }
    }

    func homes() async -> [HomeSnapshot] {
        await ensureLoaded()

        return homeManager.homes.map {
            HomeSnapshot(
                id: $0.uniqueIdentifier.uuidString,
                name: $0.name,
                roomCount: $0.rooms.count,
                accessoryCount: $0.accessories.count,
                homeHubState: $0.homeHubState
            )
        }
    }

    func accessories(in homeIdentifier: String) async -> [AccessorySnapshot] {
        await ensureLoaded()

        guard let home = home(with: homeIdentifier) else {
            return []
        }

        var roomLookup: [String: String] = [:]
        for room in home.rooms {
            for accessory in room.accessories {
                roomLookup[accessory.uniqueIdentifier.uuidString] = room.name
            }
        }

        return home.accessories.map { accessory in
            let accessoryID = accessory.uniqueIdentifier.uuidString
            return AccessorySnapshot(
                id: accessoryID,
                homeIdentifier: homeIdentifier,
                name: accessory.name,
                roomName: roomLookup[accessoryID] ?? "",
                capability: AccessoryCapabilityDetector.detectCapability(for: accessory),
                isReachable: accessory.isReachable
            )
        }
    }

    func actionSetExists(homeIdentifier: String, identifier: String?) async -> Bool {
        guard let identifier else {
            return false
        }

        await ensureLoaded()
        guard let home = home(with: homeIdentifier) else {
            return false
        }

        return home.actionSets.contains { $0.uniqueIdentifier.uuidString == identifier }
    }

    func triggerExists(homeIdentifier: String, identifier: String?) async -> Bool {
        guard let identifier else {
            return false
        }

        await ensureLoaded()
        guard let home = home(with: homeIdentifier) else {
            return false
        }

        return home.triggers.contains {
            guard let timerTrigger = $0 as? HMTimerTrigger else {
                return false
            }
            return timerTrigger.uniqueIdentifier.uuidString == identifier
        }
    }

    func upsertActionSet(
        homeIdentifier: String,
        identifier: String?,
        name: String,
        requests: [HomeKitActionRequest]
    ) async throws -> HomeKitMutationResult {
        await ensureLoaded()

        guard let home = home(with: homeIdentifier) else {
            throw HomeKitControllerError.homeNotFound(homeIdentifier)
        }

        let actionSet: HMActionSet
        let created: Bool

        if let identifier, let existing = home.actionSets.first(where: { $0.uniqueIdentifier.uuidString == identifier }) {
            actionSet = existing
            created = false
        } else {
            actionSet = try await home.addActionSet(named: name)
            created = true
        }

        if actionSet.name != name {
            try await actionSet.updateName(name)
        }

        for action in actionSet.actions {
            try await actionSet.removeAction(action)
        }

        let actions = try writeActions(for: requests, in: home)
        guard !actions.isEmpty else {
            if created {
            try? await home.removeActionSet(actionSet)
            }
            throw HomeKitControllerError.noWritableCharacteristics
        }

        for action in actions {
            try await actionSet.addAction(action)
        }

        return HomeKitMutationResult(
            identifier: actionSet.uniqueIdentifier.uuidString,
            created: created
        )
    }

    func upsertTimerTrigger(
        homeIdentifier: String,
        identifier: String?,
        name: String,
        fireDate: Date,
        recurrence: DateComponents?,
        actionSetIdentifier: String,
        isEnabled: Bool
    ) async throws -> HomeKitMutationResult {
        await ensureLoaded()

        guard let home = home(with: homeIdentifier) else {
            throw HomeKitControllerError.homeNotFound(homeIdentifier)
        }
        guard let actionSet = home.actionSets.first(where: { $0.uniqueIdentifier.uuidString == actionSetIdentifier }) else {
            throw HomeKitControllerError.actionSetNotFound(actionSetIdentifier)
        }

        let normalizedFireDate = fireDate.roundedToMinute()
        let trigger: HMTimerTrigger
        let created: Bool

        if let identifier,
           let existing = home.triggers.compactMap({ $0 as? HMTimerTrigger }).first(where: { $0.uniqueIdentifier.uuidString == identifier }) {
            trigger = existing
            created = false
            if trigger.name != name {
                try await trigger.updateName(name)
            }
            if trigger.fireDate != normalizedFireDate {
                try await trigger.updateFireDate(normalizedFireDate)
            }
            if trigger.recurrence != recurrence {
                try await trigger.updateRecurrence(recurrence)
            }
        } else {
            trigger = HMTimerTrigger(name: name, fireDate: normalizedFireDate, recurrence: recurrence)
            created = true
            try await home.addTrigger(trigger)
        }

        for existingActionSet in trigger.actionSets where existingActionSet.uniqueIdentifier.uuidString != actionSetIdentifier {
            try await trigger.removeActionSet(existingActionSet)
        }
        if !trigger.actionSets.contains(where: { $0.uniqueIdentifier.uuidString == actionSetIdentifier }) {
            try await trigger.addActionSet(actionSet)
        }

        if trigger.isEnabled != isEnabled {
            try await trigger.enable(isEnabled)
        }

        return HomeKitMutationResult(
            identifier: trigger.uniqueIdentifier.uuidString,
            created: created
        )
    }

    func deleteActionSet(homeIdentifier: String, identifier: String) async throws {
        await ensureLoaded()

        guard let home = home(with: homeIdentifier) else {
            throw HomeKitControllerError.homeNotFound(homeIdentifier)
        }
        guard let actionSet = home.actionSets.first(where: { $0.uniqueIdentifier.uuidString == identifier }) else {
            return
        }

        try await home.removeActionSet(actionSet)
    }

    func deleteTimerTrigger(homeIdentifier: String, identifier: String) async throws {
        await ensureLoaded()

        guard let home = home(with: homeIdentifier) else {
            throw HomeKitControllerError.homeNotFound(homeIdentifier)
        }
        guard let trigger = home.triggers.compactMap({ $0 as? HMTimerTrigger }).first(where: { $0.uniqueIdentifier.uuidString == identifier }) else {
            return
        }

        try await home.removeTrigger(trigger)
    }

    private func home(with identifier: String) -> HMHome? {
        homeManager.homes.first { $0.uniqueIdentifier.uuidString == identifier }
    }

    private func writeActions(for requests: [HomeKitActionRequest], in home: HMHome) throws -> [HMAction] {
        let accessoriesByID = Dictionary(uniqueKeysWithValues: home.accessories.map { ($0.uniqueIdentifier.uuidString, $0) })
        var actions: [HMAction] = []

        for request in requests {
            guard let accessory = accessoriesByID[request.accessoryIdentifier] else {
                continue
            }

            guard let characteristic = accessory.services
                .flatMap(\.characteristics)
                .first(where: { $0.characteristicType == request.characteristicType }) else {
                continue
            }

            actions.append(
                HMCharacteristicWriteAction(
                    characteristic: characteristic,
                    targetValue: request.value.boxedValue
                )
            )
        }

        return actions
    }

    private func finishLoading() {
        hasLoadedHomes = true
        let continuations = loadContinuations
        loadContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }
}

extension HomeKitController: @preconcurrency HMHomeManagerDelegate {
    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor in
            DawnLoopLogger.homeKit.debug("Home manager updated homes")
            finishLoading()
        }
    }

    func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) {
        Task { @MainActor in
            DawnLoopLogger.homeKit.debug("Home authorization updated: \(status.rawValue)")
            finishLoading()
        }
    }
}

enum HomeKitControllerError: LocalizedError {
    case homeNotFound(String)
    case actionSetNotFound(String)
    case noWritableCharacteristics

    var errorDescription: String? {
        switch self {
        case .homeNotFound(let identifier):
            return "The selected Apple Home (\(identifier)) is no longer available."
        case .actionSetNotFound(let identifier):
            return "The HomeKit action set (\(identifier)) could not be found."
        case .noWritableCharacteristics:
            return "The selected lights no longer expose writable characteristics for this alarm."
        }
    }
}

@MainActor
final class MockHomeKitController: HomeKitControllerProtocol {
    struct StoredActionSet: Equatable, Sendable {
        let identifier: String
        var name: String
        var requests: [HomeKitActionRequest]
    }

    struct StoredTrigger: Equatable, Sendable {
        let identifier: String
        var name: String
        var fireDate: Date
        var recurrence: DateComponents?
        var actionSetIdentifier: String
        var isEnabled: Bool
    }

    private var status: HMHomeManagerAuthorizationStatus
    private var storedHomes: [HomeSnapshot]
    private var storedAccessories: [String: [AccessorySnapshot]]
    private var actionSets: [String: [String: StoredActionSet]]
    private var triggers: [String: [String: StoredTrigger]]

    init(
        status: HMHomeManagerAuthorizationStatus = [.determined, .authorized],
        homes: [HomeSnapshot] = [],
        accessories: [String: [AccessorySnapshot]] = [:]
    ) {
        self.status = status
        self.storedHomes = homes
        self.storedAccessories = accessories
        self.actionSets = [:]
        self.triggers = [:]
    }

    static func seededTestHome() -> MockHomeKitController {
        let homeID = "test-home-uuid-001"
        let home = HomeSnapshot(
            id: homeID,
            name: "Test Home",
            roomCount: 4,
            accessoryCount: 8,
            homeHubState: .connected
        )
        let accessories = [
            AccessorySnapshot(
                id: "test-accessory-living-room-001",
                homeIdentifier: homeID,
                name: "Living Room Light",
                roomName: "Living Room",
                capability: .fullColor,
                isReachable: true
            ),
            AccessorySnapshot(
                id: "test-accessory-bedroom-001",
                homeIdentifier: homeID,
                name: "Bedroom Light",
                roomName: "Bedroom",
                capability: .tunableWhite,
                isReachable: true
            ),
            AccessorySnapshot(
                id: "test-accessory-kitchen-001",
                homeIdentifier: homeID,
                name: "Kitchen Light",
                roomName: "Kitchen",
                capability: .brightnessOnly,
                isReachable: true
            ),
        ]

        return MockHomeKitController(
            homes: [home],
            accessories: [homeID: accessories]
        )
    }

    func setAuthorizationStatus(_ status: HMHomeManagerAuthorizationStatus) {
        self.status = status
    }

    func setHomes(_ homes: [HomeSnapshot]) {
        storedHomes = homes
    }

    func setAccessories(_ accessories: [AccessorySnapshot], for homeIdentifier: String) {
        storedAccessories[homeIdentifier] = accessories
    }

    func authorizationStatus() -> HMHomeManagerAuthorizationStatus {
        status
    }

    func ensureLoaded() async {}

    func homes() async -> [HomeSnapshot] {
        storedHomes
    }

    func accessories(in homeIdentifier: String) async -> [AccessorySnapshot] {
        storedAccessories[homeIdentifier] ?? []
    }

    func actionSetExists(homeIdentifier: String, identifier: String?) async -> Bool {
        guard let identifier else {
            return false
        }
        return actionSets[homeIdentifier]?[identifier] != nil
    }

    func triggerExists(homeIdentifier: String, identifier: String?) async -> Bool {
        guard let identifier else {
            return false
        }
        return triggers[homeIdentifier]?[identifier] != nil
    }

    func upsertActionSet(
        homeIdentifier: String,
        identifier: String?,
        name: String,
        requests: [HomeKitActionRequest]
    ) async throws -> HomeKitMutationResult {
        var homeActionSets = actionSets[homeIdentifier] ?? [:]
        let identifier = identifier ?? UUID().uuidString
        let created = homeActionSets[identifier] == nil
        homeActionSets[identifier] = StoredActionSet(
            identifier: identifier,
            name: name,
            requests: requests
        )
        actionSets[homeIdentifier] = homeActionSets
        return HomeKitMutationResult(identifier: identifier, created: created)
    }

    func upsertTimerTrigger(
        homeIdentifier: String,
        identifier: String?,
        name: String,
        fireDate: Date,
        recurrence: DateComponents?,
        actionSetIdentifier: String,
        isEnabled: Bool
    ) async throws -> HomeKitMutationResult {
        var homeTriggers = triggers[homeIdentifier] ?? [:]
        let identifier = identifier ?? UUID().uuidString
        let created = homeTriggers[identifier] == nil
        homeTriggers[identifier] = StoredTrigger(
            identifier: identifier,
            name: name,
            fireDate: fireDate,
            recurrence: recurrence,
            actionSetIdentifier: actionSetIdentifier,
            isEnabled: isEnabled
        )
        triggers[homeIdentifier] = homeTriggers
        return HomeKitMutationResult(identifier: identifier, created: created)
    }

    func deleteActionSet(homeIdentifier: String, identifier: String) async throws {
        actionSets[homeIdentifier]?[identifier] = nil
    }

    func deleteTimerTrigger(homeIdentifier: String, identifier: String) async throws {
        triggers[homeIdentifier]?[identifier] = nil
    }

    func storedActionSets(for homeIdentifier: String) -> [StoredActionSet] {
        Array(actionSets[homeIdentifier]?.values ?? Dictionary<String, StoredActionSet>().values)
    }

    func storedTriggers(for homeIdentifier: String) -> [StoredTrigger] {
        Array(triggers[homeIdentifier]?.values ?? Dictionary<String, StoredTrigger>().values)
    }
}

private extension Date {
    func roundedToMinute(calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: self)
        return calendar.date(from: components) ?? self
    }
}

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

struct HomeKitNamespaceCleanupResult: Equatable, Sendable {
    let homesVisited: Int
    let triggersRemoved: Int
    let actionSetsRemoved: Int
}

enum HomeKitTriggerSchedule: Equatable, Sendable {
    case calendar(fireDate: Date, weekday: Int?)
    case significant(reference: AlarmTimeReference, offsetMinutes: Int, weekday: Int?)
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
    func upsertScheduledTrigger(
        homeIdentifier: String,
        identifier: String?,
        name: String,
        schedule: HomeKitTriggerSchedule,
        actionSetIdentifier: String,
        requiredOnAccessoryIdentifiers: [String],
        isEnabled: Bool
    ) async throws -> HomeKitMutationResult
    func deleteActionSet(homeIdentifier: String, identifier: String) async throws
    func deleteTrigger(homeIdentifier: String, identifier: String) async throws
    func removeObjects(prefixedBy prefix: String) async -> HomeKitNamespaceCleanupResult
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

        return home.triggers.contains { $0.uniqueIdentifier.uuidString == identifier }
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

    func upsertScheduledTrigger(
        homeIdentifier: String,
        identifier: String?,
        name: String,
        schedule: HomeKitTriggerSchedule,
        actionSetIdentifier: String,
        requiredOnAccessoryIdentifiers: [String],
        isEnabled: Bool
    ) async throws -> HomeKitMutationResult {
        await ensureLoaded()

        guard let home = home(with: homeIdentifier) else {
            throw HomeKitControllerError.homeNotFound(homeIdentifier)
        }
        guard let actionSet = home.actionSets.first(where: { $0.uniqueIdentifier.uuidString == actionSetIdentifier }) else {
            throw HomeKitControllerError.actionSetNotFound(actionSetIdentifier)
        }

        let desiredEvent = event(for: schedule)
        let desiredRecurrences = recurrences(for: schedule)
        let desiredPredicate = powerStatePredicate(
            for: requiredOnAccessoryIdentifiers,
            in: home
        )
        let desiredExecuteOnce = !isRepeating(schedule)

        let existingTrigger: HMTrigger? = if let identifier {
            existingTrigger(with: identifier, in: home)
        } else {
            nil
        }
        let trigger: HMEventTrigger
        let created: Bool

        if let existingEventTrigger = existingTrigger as? HMEventTrigger {
            trigger = existingEventTrigger
            created = false
        } else {
            if let existingTrigger {
                try await home.removeTrigger(existingTrigger)
            }
            trigger = HMEventTrigger(
                name: name,
                events: [desiredEvent],
                end: nil,
                recurrences: desiredRecurrences,
                predicate: desiredPredicate
            )
            created = true
            try await home.addTrigger(trigger)
        }

        if trigger.name != name {
            try await trigger.updateName(name)
        }
        if !matchesEvent(trigger.events, desired: desiredEvent) {
            try await trigger.updateEvents([desiredEvent])
        }
        if !matchesRecurrences(trigger.recurrences, desired: desiredRecurrences) {
            try await trigger.updateRecurrences(desiredRecurrences)
        }
        if !matchesPredicate(trigger.predicate, desired: desiredPredicate) {
            try await trigger.updatePredicate(desiredPredicate)
        }
        if trigger.executeOnce != desiredExecuteOnce {
            try await trigger.updateExecuteOnce(desiredExecuteOnce)
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

    func deleteTrigger(homeIdentifier: String, identifier: String) async throws {
        await ensureLoaded()

        guard let home = home(with: homeIdentifier) else {
            throw HomeKitControllerError.homeNotFound(homeIdentifier)
        }
        guard let trigger = existingTrigger(with: identifier, in: home) else {
            return
        }

        try await home.removeTrigger(trigger)
    }

    func removeObjects(prefixedBy prefix: String) async -> HomeKitNamespaceCleanupResult {
        await ensureLoaded()

        var removedTriggers = 0
        var removedActionSets = 0

        for home in homeManager.homes {
            let triggers = home.triggers.filter { $0.name.hasPrefix(prefix) }

            for trigger in triggers {
                do {
                    try await home.removeTrigger(trigger)
                    removedTriggers += 1
                } catch {
                    DawnLoopLogger.homeKit.error("Failed to remove trigger \(trigger.name): \(error.localizedDescription)")
                }
            }

            let actionSets = home.actionSets.filter { $0.name.hasPrefix(prefix) }
            for actionSet in actionSets {
                do {
                    try await home.removeActionSet(actionSet)
                    removedActionSets += 1
                } catch {
                    DawnLoopLogger.homeKit.error("Failed to remove action set \(actionSet.name): \(error.localizedDescription)")
                }
            }
        }

        return HomeKitNamespaceCleanupResult(
            homesVisited: homeManager.homes.count,
            triggersRemoved: removedTriggers,
            actionSetsRemoved: removedActionSets
        )
    }

    private func home(with identifier: String) -> HMHome? {
        homeManager.homes.first { $0.uniqueIdentifier.uuidString == identifier }
    }

    private func existingTrigger(with identifier: String, in home: HMHome) -> HMTrigger? {
        home.triggers.first { $0.uniqueIdentifier.uuidString == identifier }
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

    private func event(for schedule: HomeKitTriggerSchedule) -> HMEvent {
        switch schedule {
        case .calendar(let fireDate, let weekday):
            let normalizedFireDate = fireDate.roundedToMinute()
            return HMCalendarEvent(
                fire: calendarEventComponents(
                    for: normalizedFireDate,
                    weekday: weekday
                )
            )
        case .significant(let reference, let offsetMinutes, _):
            return HMSignificantTimeEvent(
                significantEvent: significantEvent(for: reference),
                offset: significantOffset(minutes: offsetMinutes)
            )
        }
    }

    private func recurrences(for schedule: HomeKitTriggerSchedule) -> [DateComponents]? {
        switch schedule {
        case .calendar(_, let weekday), .significant(_, _, let weekday):
            return weekday.map { [DateComponents(weekday: $0)] }
        }
    }

    private func isRepeating(_ schedule: HomeKitTriggerSchedule) -> Bool {
        switch schedule {
        case .calendar(_, let weekday), .significant(_, _, let weekday):
            return weekday != nil
        }
    }

    private func calendarEventComponents(
        for fireDate: Date,
        weekday: Int?,
        calendar: Calendar = .current
    ) -> DateComponents {
        if weekday == nil {
            return calendar.dateComponents([.month, .day, .hour, .minute], from: fireDate)
        }

        return calendar.dateComponents([.hour, .minute], from: fireDate)
    }

    private func significantOffset(minutes: Int) -> DateComponents? {
        guard minutes != 0 else {
            return nil
        }
        return DateComponents(minute: minutes)
    }

    private func significantEvent(for reference: AlarmTimeReference) -> HMSignificantEvent {
        switch reference {
        case .clock:
            return .sunrise
        case .sunrise:
            return .sunrise
        case .sunset:
            return .sunset
        }
    }

    private func powerStatePredicate(
        for accessoryIdentifiers: [String],
        in home: HMHome
    ) -> NSPredicate? {
        let accessoryIdentifiers = Array(Set(accessoryIdentifiers)).sorted()
        let accessoriesByID = Dictionary(uniqueKeysWithValues: home.accessories.map { ($0.uniqueIdentifier.uuidString, $0) })
        let predicates = accessoryIdentifiers.compactMap { accessoryIdentifier -> NSPredicate? in
            guard
                let accessory = accessoriesByID[accessoryIdentifier],
                let characteristic = powerStateCharacteristic(for: accessory)
            else {
                return nil
            }

            return HMEventTrigger.predicateForEvaluatingTrigger(
                characteristic,
                relatedBy: .equalTo,
                toValue: 1
            )
        }

        guard !predicates.isEmpty else {
            return nil
        }
        if predicates.count == 1 {
            return predicates[0]
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    private func powerStateCharacteristic(for accessory: HMAccessory) -> HMCharacteristic? {
        accessory.services
            .flatMap(\.characteristics)
            .first(where: { $0.characteristicType == HMCharacteristicTypePowerState })
    }

    private func matchesEvent(_ events: [HMEvent], desired: HMEvent) -> Bool {
        guard events.count == 1 else {
            return false
        }
        switch (events.first, desired) {
        case (let existing as HMCalendarEvent, let desired as HMCalendarEvent):
            return normalizedCalendarEventComponents(existing.fireDateComponents) ==
                normalizedCalendarEventComponents(desired.fireDateComponents)
        case (let existing as HMSignificantTimeEvent, let desired as HMSignificantTimeEvent):
            return existing.significantEvent == desired.significantEvent &&
                existing.offset == desired.offset
        default:
            return false
        }
    }

    private func normalizedCalendarEventComponents(_ components: DateComponents) -> DateComponents {
        var normalized = DateComponents()
        normalized.month = components.month
        normalized.day = components.day
        normalized.hour = components.hour
        normalized.minute = components.minute
        return normalized
    }

    private func matchesRecurrences(_ lhs: [DateComponents]?, desired rhs: [DateComponents]?) -> Bool {
        let lhsWeekdays = lhs?.compactMap(\.weekday) ?? []
        let rhsWeekdays = rhs?.compactMap(\.weekday) ?? []
        return lhsWeekdays == rhsWeekdays
    }

    private func matchesPredicate(_ lhs: NSPredicate?, desired rhs: NSPredicate?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (let lhs?, let rhs?):
            return lhs.predicateFormat == rhs.predicateFormat
        default:
            return false
        }
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
        var schedule: HomeKitTriggerSchedule
        var actionSetIdentifier: String
        var requiredOnAccessoryIdentifiers: [String]
        var executeOnce: Bool
        var isEnabled: Bool
    }

    private var status: HMHomeManagerAuthorizationStatus
    private var storedHomes: [HomeSnapshot]
    private var storedAccessories: [String: [AccessorySnapshot]]
    private var actionSets: [String: [String: StoredActionSet]]
    private var triggers: [String: [String: StoredTrigger]]
    private(set) var upsertActionSetCallCount = 0
    private(set) var upsertScheduledTriggerCallCount = 0

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
        upsertActionSetCallCount += 1
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

    func upsertScheduledTrigger(
        homeIdentifier: String,
        identifier: String?,
        name: String,
        schedule: HomeKitTriggerSchedule,
        actionSetIdentifier: String,
        requiredOnAccessoryIdentifiers: [String],
        isEnabled: Bool
    ) async throws -> HomeKitMutationResult {
        upsertScheduledTriggerCallCount += 1
        var homeTriggers = triggers[homeIdentifier] ?? [:]
        let identifier = identifier ?? UUID().uuidString
        let created = homeTriggers[identifier] == nil
        homeTriggers[identifier] = StoredTrigger(
            identifier: identifier,
            name: name,
            schedule: schedule,
            actionSetIdentifier: actionSetIdentifier,
            requiredOnAccessoryIdentifiers: requiredOnAccessoryIdentifiers.sorted(),
            executeOnce: {
                switch schedule {
                case .calendar(_, let weekday), .significant(_, _, let weekday):
                    return weekday == nil
                }
            }(),
            isEnabled: isEnabled
        )
        triggers[homeIdentifier] = homeTriggers
        return HomeKitMutationResult(identifier: identifier, created: created)
    }

    func deleteActionSet(homeIdentifier: String, identifier: String) async throws {
        actionSets[homeIdentifier]?[identifier] = nil
    }

    func deleteTrigger(homeIdentifier: String, identifier: String) async throws {
        triggers[homeIdentifier]?[identifier] = nil
    }

    func removeObjects(prefixedBy prefix: String) async -> HomeKitNamespaceCleanupResult {
        var homesVisited = 0
        var removedTriggers = 0
        var removedActionSets = 0

        for home in storedHomes {
            homesVisited += 1

            let homeIdentifier = home.id
            let triggerMatches = storedTriggers(for: homeIdentifier).filter { $0.name.hasPrefix(prefix) }
            for trigger in triggerMatches {
                triggers[homeIdentifier]?[trigger.identifier] = nil
                removedTriggers += 1
            }

            let actionSetMatches = storedActionSets(for: homeIdentifier).filter { $0.name.hasPrefix(prefix) }
            for actionSet in actionSetMatches {
                actionSets[homeIdentifier]?[actionSet.identifier] = nil
                removedActionSets += 1
            }
        }

        return HomeKitNamespaceCleanupResult(
            homesVisited: homesVisited,
            triggersRemoved: removedTriggers,
            actionSetsRemoved: removedActionSets
        )
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

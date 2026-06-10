import SwiftUI
import SwiftData

@MainActor
@Observable
final class AlarmListStore {
    let environment: AppEnvironment

    var items: [AlarmListItem] = []
    var isLoading = false
    var alertMessage: String?
    var showingEditor = false
    var isSavingEditor = false
    var isResettingHomeKit = false
    var showingResetConfirmation = false
    var showingOnboardingResetConfirmation = false
    var saveProgress: Double = 0
    var saveProgressMessage = "Saving alarm..."
    var isValidating = false
    var editorState = AlarmEditorState()
    var editingAlarmID: UUID?
    var pendingDeleteItem: AlarmListItem?
    var togglingAlarmIDs: Set<UUID> = []
    var activeHomeName: String?
    var activeHomeIdentifier: String?
    var configuredLightCount = 0
    var isHomeConfigured = false
    @ObservationIgnored private var validationTask: Task<Void, Never>?
    @ObservationIgnored private var validationRunID: UUID?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    deinit {
        validationTask?.cancel()
    }

    func refresh() async {
        validationTask?.cancel()
        isLoading = items.isEmpty
        defer { isLoading = false }

        let activeHomeResult = await environment.homeSelectionService.activeHome()
        switch activeHomeResult {
        case .success(let home):
            activeHomeName = home.name
            activeHomeIdentifier = home.id
            isHomeConfigured = true
        case .notFound, .noSelection:
            activeHomeName = nil
            activeHomeIdentifier = nil
            isHomeConfigured = false
        case .error:
            activeHomeName = nil
            activeHomeIdentifier = nil
            isHomeConfigured = false
        }

        configuredLightCount = (await selectedAccessories()).count
        let solarCoordinate = await environment.currentLocationService.currentCoordinateIfAuthorized()

        // Show every alarm, not just the active home's - an alarm scoped to another
        // home still has live HomeKit automations, and hiding it here would leave it
        // firing with no way to manage or delete it.
        let alarms = await environment.alarmRepository.fetchAllAlarms()
        var schedulesByAlarmId: [UUID: WeekdaySchedule] = [:]
        var loadedItems: [AlarmListItem] = []
        loadedItems.reserveCapacity(alarms.count)

        for alarm in alarms {
            let scheduleRecord = await environment.alarmRepository.fetchSchedule(for: alarm.id)
            let schedule = scheduleRecord?.weekdaySchedule ?? .never
            schedulesByAlarmId[alarm.id] = schedule

            loadedItems.append(
                AlarmListItem(
                    alarm: alarm,
                    schedule: schedule,
                    validation: await storedValidationSummary(for: alarm),
                    nextRunDate: nextRunDate(for: alarm, schedule: schedule, coordinate: solarCoordinate)
                )
            )
        }

        items = sortedItems(loadedItems)
        validateItemsInBackground(
            alarms: alarms,
            schedulesByAlarmId: schedulesByAlarmId,
            solarCoordinate: solarCoordinate
        )
    }

    private func validateItemsInBackground(
        alarms: [WakeAlarm],
        schedulesByAlarmId: [UUID: WeekdaySchedule],
        solarCoordinate: SolarCoordinate?
    ) {
        guard !alarms.isEmpty else {
            isValidating = false
            validationRunID = nil
            return
        }

        let runID = UUID()
        validationRunID = runID
        isValidating = true
        validationTask = Task { [weak self] in
            guard let self else { return }

            for alarm in alarms {
                guard !Task.isCancelled, self.validationRunID == runID else {
                    return
                }

                // Skip alarms deleted since this run started so validation doesn't
                // re-persist records for them.
                guard let currentAlarm = await self.environment.alarmRepository.fetchAlarm(byId: alarm.id) else {
                    continue
                }

                let schedule = schedulesByAlarmId[alarm.id] ?? .never
                let validation = await self.environment.automationRepairService.validateAlarm(
                    currentAlarm,
                    schedule: schedule
                )

                // Re-check after the await: a refresh or delete may have superseded this run.
                guard !Task.isCancelled, self.validationRunID == runID else {
                    return
                }

                // Validation can change the alarm itself (e.g. a finished one-time
                // alarm turns itself off), so re-fetch before updating the row.
                let displayAlarm = await self.environment.alarmRepository.fetchAlarm(byId: alarm.id) ?? currentAlarm
                guard !Task.isCancelled, self.validationRunID == runID else {
                    return
                }

                self.replaceItem(
                    AlarmListItem(
                        alarm: displayAlarm,
                        schedule: schedule,
                        validation: validation,
                        nextRunDate: self.nextRunDate(
                            for: displayAlarm,
                            schedule: schedule,
                            coordinate: solarCoordinate
                        )
                    )
                )
            }

            guard self.validationRunID == runID else { return }
            self.validationRunID = nil
            self.isValidating = false
        }
    }

    private func cancelBackgroundValidation() {
        validationTask?.cancel()
        validationRunID = nil
        isValidating = false
    }

    private func replaceItem(_ updatedItem: AlarmListItem) {
        // Only update rows that still exist - re-adding a missing row would
        // resurrect an alarm the user deleted while validation was running.
        guard let index = items.firstIndex(where: { $0.id == updatedItem.id }) else {
            return
        }

        items[index] = updatedItem
        items = sortedItems(items)
    }

    private func sortedItems(_ loadedItems: [AlarmListItem]) -> [AlarmListItem] {
        loadedItems.sorted { lhs, rhs in
            (lhs.nextRunDate ?? .distantFuture) < (rhs.nextRunDate ?? .distantFuture)
        }
    }

    private func nextRunDate(
        for alarm: WakeAlarm,
        schedule: WeekdaySchedule,
        coordinate: SolarCoordinate?
    ) -> Date? {
        guard alarm.isEnabled else { return nil }
        return WakeAlarmSchedule(alarmId: alarm.id, weekdaySchedule: schedule).nextOccurrence(
            alarm: alarm,
            coordinate: coordinate
        )
    }

    private func storedValidationSummary(for alarm: WakeAlarm) async -> ValidationStateSummary {
        if let record = await environment.alarmRepository.fetchValidationState(for: alarm.id) {
            return record.toSummary()
        }

        return ValidationStateSummary(
            state: alarm.isEnabled ? .needsSync : .valid,
            message: alarm.isEnabled ? "Home automation needs a check." : "Alarm is disabled.",
            requiresUserAction: false,
            lastUpdated: nil
        )
    }

    var enabledCount: Int {
        items.filter(\.alarm.isEnabled).count
    }

    var needsAttentionCount: Int {
        items.filter { $0.validation.isActionable }.count
    }

    var nextAlarmDate: Date? {
        items.compactMap(\.nextRunDate).min()
    }

    var nextAlarmName: String? {
        guard let nextAlarmDate else { return nil }
        return items.first(where: { $0.nextRunDate == nextAlarmDate })?.alarm.name
    }

    func startSetupFlow() {
        environment.onboardingState.startHomeAccessFlow()
    }

    func startCreate() async {
        guard let homeIdentifier = activeHomeIdentifier else {
            alertMessage = "Choose an Apple Home before creating an alarm."
            return
        }

        editorState.reset()
        editorState.availableAccessories = await availableAccessories(for: homeIdentifier)
        editorState.selectedAccessoryIds = Set((await selectedAccessories()).map(\.homeKitIdentifier))
        editorState.regeneratePreview()
        editingAlarmID = nil
        showingEditor = true
    }

    func edit(_ item: AlarmListItem) async {
        guard let homeIdentifier = item.alarm.homeIdentifier ?? activeHomeIdentifier else {
            alertMessage = "The Apple Home for this alarm is unavailable."
            return
        }

        editorState.reset()
        editorState.load(
            alarm: item.alarm,
            availableAccessories: await availableAccessories(for: homeIdentifier),
            schedule: item.schedule
        )
        editorState.regeneratePreview()
        editingAlarmID = item.id
        showingEditor = true
    }

    func saveEditor() async {
        guard !isSavingEditor else {
            return
        }

        guard let homeIdentifier = saveHomeIdentifier else {
            alertMessage = "Choose an Apple Home before saving this alarm."
            return
        }

        guard let alarm = editorState.createAlarm() else {
            return
        }

        cancelBackgroundValidation()

        if alarm.isSolarBased {
            environment.currentLocationService.requestAuthorizationIfNeeded()
        }

        alarm.homeIdentifier = homeIdentifier
        isSavingEditor = true
        saveProgress = 0.05
        saveProgressMessage = "Saving alarm details"
        defer {
            isSavingEditor = false
            saveProgress = 0
            saveProgressMessage = "Saving alarm..."
        }

        do {
            let initialState: AlarmValidationState = alarm.isEnabled ? .needsSync : .valid
            try await environment.alarmRepository.saveAlarm(
                alarm,
                schedule: editorState.repeatSchedule,
                validationState: initialState
            )
            saveProgress = 0.2
            saveProgressMessage = alarm.isEnabled
                ? "Preparing HomeKit automations"
                : "Removing disabled automations"

            var syncFailureMessage: String?

            do {
                if alarm.isEnabled {
                    try await environment.automationGenerationService.syncAlarm(
                        alarm,
                        schedule: editorState.repeatSchedule,
                        progress: { [weak self] progress in
                            guard let self else { return }
                            self.saveProgress = 0.2 + (progress.fractionCompleted * 0.75)
                            self.saveProgressMessage = progress.message
                        }
                    )
                } else {
                    try await environment.automationGenerationService.removeAutomations(
                        for: alarm,
                        markDisabled: true
                    )
                    saveProgress = 0.95
                    saveProgressMessage = "Finishing up"
                }
            } catch {
                let detail = error.localizedDescription.isEmpty
                    ? "Home automation could not be synced right now."
                    : error.localizedDescription
                syncFailureMessage = "Alarm saved, but HomeKit sync needs attention. \(detail)"
            }

            saveProgress = 1
            saveProgressMessage = "Done"
            showingEditor = false
            await refresh()
            if let syncFailureMessage {
                alertMessage = syncFailureMessage
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func cancelEditing() {
        showingEditor = false
        editorState.reset()
    }

    func toggleEnabled(_ item: AlarmListItem) async {
        // A second tap mid-toggle would interleave HomeKit sync and removal
        // for the same alarm; ignore taps until the in-flight toggle finishes.
        guard !togglingAlarmIDs.contains(item.id) else {
            return
        }
        togglingAlarmIDs.insert(item.id)
        defer { togglingAlarmIDs.remove(item.id) }

        // Stop in-flight background validation: it could observe the half-toggled
        // state (e.g. re-enabled alarm with stale fired bindings) and act on it.
        cancelBackgroundValidation()

        guard let alarm = await environment.alarmRepository.fetchAlarm(byId: item.id) else {
            return
        }

        do {
            try await environment.alarmRepository.setAlarmEnabled(alarm, enabled: !alarm.isEnabled)
            let updated = await environment.alarmRepository.fetchAlarm(byId: item.id) ?? alarm
            let schedule = await environment.alarmRepository.fetchSchedule(for: item.id)
            let scheduleValue = schedule?.weekdaySchedule
            if updated.isEnabled {
                try await environment.automationGenerationService.syncAlarm(updated, schedule: scheduleValue)
            } else {
                try await environment.automationGenerationService.removeAutomations(
                    for: updated,
                    markDisabled: true
                )
            }

            await refresh()
        } catch {
            alertMessage = error.localizedDescription
            await refresh()
        }
    }

    func duplicate(_ item: AlarmListItem) async {
        guard let alarm = await environment.alarmRepository.fetchAlarm(byId: item.id) else {
            return
        }

        do {
            let duplicate = try await environment.alarmRepository.duplicateAlarm(alarm)
            try await environment.alarmRepository.updateValidationState(
                for: duplicate.id,
                state: .valid,
                message: "Duplicated alarms start disabled until you enable them.",
                requiresUserAction: false
            )
            await refresh()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func delete(_ item: AlarmListItem) async {
        cancelBackgroundValidation()
        do {
            let alarm = await environment.alarmRepository.fetchAlarm(byId: item.id)
            var cleanupFailed = false

            if let alarm {
                do {
                    try await environment.automationGenerationService.removeAutomations(for: alarm)
                } catch {
                    cleanupFailed = true
                    DawnLoopLogger.homeKit.error("Failed to remove HomeKit automations during delete: \(error.localizedDescription)")
                }
            }

            try await environment.alarmRepository.deleteAlarm(byId: item.id)
            await refresh()

            if cleanupFailed {
                alertMessage = "Alarm deleted, but some HomeKit automations may need manual cleanup."
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func repair(_ item: AlarmListItem) async {
        cancelBackgroundValidation()
        guard let alarm = await environment.alarmRepository.fetchAlarm(byId: item.id) else {
            return
        }

        do {
            let schedule = await environment.alarmRepository.fetchSchedule(for: item.id)
            _ = try await environment.automationRepairService.repairAlarm(
                alarm,
                schedule: schedule?.weekdaySchedule
            )
            await refresh()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func resetHomeKitArtifacts() async {
        guard !isResettingHomeKit else {
            return
        }

        isResettingHomeKit = true
        defer { isResettingHomeKit = false }

        do {
            let summary = try await environment.automationGenerationService.resetDawnLoopArtifacts()
            await refresh()
            alertMessage = "Removed \(summary.triggersRemoved) triggers and \(summary.actionSetsRemoved) scenes across \(summary.homesVisited) homes. Cleared \(summary.bindingsCleared) local bindings."
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func availableAccessories(for homeIdentifier: String) async -> [AccessoryViewModel] {
        let context = ModelContext(environment.modelContainer)
        var descriptor = FetchDescriptor<AccessoryReference>()
        descriptor.predicate = #Predicate { $0.homeIdentifier == homeIdentifier }
        let references = (try? context.fetch(descriptor)) ?? []

        // Overlay live HomeKit capabilities so the editor preview degrades the same
        // way the generated automations will; persisted capabilities are only a
        // fallback for when HomeKit is unavailable.
        let liveSnapshots = await environment.homeKitController.accessories(in: homeIdentifier)
        let liveByID = Dictionary(uniqueKeysWithValues: liveSnapshots.map { ($0.id, $0) })

        return references
            .map { reference -> AccessoryViewModel in
                guard let snapshot = liveByID[reference.homeKitIdentifier] else {
                    return AccessoryViewModel(from: reference)
                }
                return AccessoryViewModel(
                    id: reference.homeKitIdentifier,
                    homeKitIdentifier: reference.homeKitIdentifier,
                    name: snapshot.name,
                    roomName: snapshot.roomName.isEmpty ? reference.roomName : snapshot.roomName,
                    capability: snapshot.capability,
                    isSelected: reference.isSelected,
                    isReachable: snapshot.isReachable
                )
            }
            .sorted { $0.roomName == $1.roomName ? $0.name < $1.name : $0.roomName < $1.roomName }
    }

    private func selectedAccessories() async -> [AccessoryViewModel] {
        await environment.accessoryDiscoveryService.selectedAccessories()
    }

    private var saveHomeIdentifier: String? {
        guard let editingAlarmID else {
            return activeHomeIdentifier
        }

        return items.first(where: { $0.id == editingAlarmID })?.alarm.homeIdentifier ?? activeHomeIdentifier
    }
}

struct AlarmListItem: Identifiable {
    let alarm: WakeAlarm
    let schedule: WeekdaySchedule
    let validation: ValidationStateSummary
    let nextRunDate: Date?

    var id: UUID { alarm.id }

    var viewModel: AlarmViewModel {
        AlarmViewModel(
            from: alarm,
            validationSummary: validation,
            nextRunDate: nextRunDate
        )
    }
}

struct AlarmListView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var store: AlarmListStore?

    var body: some View {
        Group {
            if let store {
                content(store: store)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task {
                        let configured = AlarmListStore(environment: environment)
                        self.store = configured
                        await configured.refresh()
                    }
            }
        }
    }

    @ViewBuilder
    private func content(store: AlarmListStore) -> some View {
        @Bindable var store = store

        List {
            if store.isHomeConfigured {
                Section {
                    DashboardSummaryCard(
                        homeName: store.activeHomeName ?? "Apple Home",
                        lightCount: store.configuredLightCount,
                        alarmCount: store.items.count,
                        enabledCount: store.enabledCount,
                        needsAttentionCount: store.needsAttentionCount,
                        nextAlarmDate: store.nextAlarmDate,
                        nextAlarmName: store.nextAlarmName,
                        isValidating: store.isValidating,
                        onCreate: {
                            Task { await store.startCreate() }
                        },
                        onChangeHome: store.startSetupFlow
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if store.items.isEmpty {
                    Section {
                        EmptyAlarmStateView(onCreate: {
                            Task { await store.startCreate() }
                        })
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(store.items) { item in
                            AlarmRow(
                                item: item,
                                onToggle: {
                                    Task { await store.toggleEnabled(item) }
                                }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Task { await store.edit(item) }
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) {
                                    store.pendingDeleteItem = item
                                }
                                Button("Duplicate") {
                                    Task { await store.duplicate(item) }
                                }
                                if item.validation.isActionable {
                                    Button("Repair") {
                                        Task { await store.repair(item) }
                                    }
                                    .tint(.orange)
                                }
                            }
                        }
                    } header: {
                        AlarmSectionHeader(
                            title: "Light Alarms",
                            count: store.items.count,
                            isValidating: store.isValidating
                        )
                    }
                }

                Section {
                    RecoveryToolsCard {
                        store.showingResetConfirmation = true
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    AlarmSetupRequiredView(onStart: store.startSetupFlow)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Gradients.appBackground.ignoresSafeArea())
        .navigationTitle("DawnLoop")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if store.isHomeConfigured {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.startCreate() }
                    } label: {
                        Label("New Alarm", systemImage: "plus")
                    }
                    .accessibilityIdentifier("newAlarmButton")
                }
            }

#if DEBUG
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Reset Onboarding") {
                        store.showingOnboardingResetConfirmation = true
                    }
                } label: {
                    Image(systemName: "gearshape")
                }
            }
#endif
        }
        .sheet(isPresented: $store.showingEditor) {
            AlarmEditorView(
                state: store.editorState,
                isSaving: store.isSavingEditor,
                saveProgress: store.saveProgress,
                saveProgressMessage: store.saveProgressMessage,
                onSave: {
                    Task { await store.saveEditor() }
                },
                onCancel: {
                    store.cancelEditing()
                }
            )
        }
        .refreshable {
            await store.refresh()
        }
        .alert("Delete Alarm?", isPresented: .init(
            get: { store.pendingDeleteItem != nil },
            set: { isPresented in
                if !isPresented {
                    store.pendingDeleteItem = nil
                }
            }
        )) {
            Button("Delete", role: .destructive) {
                if let item = store.pendingDeleteItem {
                    Task { await store.delete(item) }
                }
                store.pendingDeleteItem = nil
            }
            Button("Cancel", role: .cancel) {
                store.pendingDeleteItem = nil
            }
        } message: {
            Text("This removes the alarm and its HomeKit automations.")
        }
#if DEBUG
        .alert("Reset Onboarding?", isPresented: $store.showingOnboardingResetConfirmation) {
            Button("Reset", role: .destructive) {
                environment.onboardingState.resetOnboarding()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This sends the app back to the onboarding flow on the next screen refresh.")
        }
#endif
        .alert("Nuke DawnLoop HomeKit?", isPresented: $store.showingResetConfirmation) {
            Button("Nuke", role: .destructive) {
                Task { await store.resetHomeKitArtifacts() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes DawnLoop-created HomeKit scenes and triggers, then clears local automation bindings.")
        }
        .alert("DawnLoop", isPresented: .init(
            get: { store.alertMessage != nil },
            set: { isPresented in
                if !isPresented {
                    store.alertMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                store.alertMessage = nil
            }
        } message: {
            Text(store.alertMessage ?? "")
        }
        .overlay {
            if store.isResettingHomeKit {
                ZStack {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()

                    VStack(spacing: Theme.Spacing.medium) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Resetting HomeKit")
                            .font(Theme.Typography.bodyBold)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Removing DawnLoop-created scenes, triggers, and bindings.")
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(Theme.Spacing.xLarge)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.large)
                            .fill(Theme.Colors.surface)
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
                    .padding(.horizontal, Theme.Spacing.xxLarge)
                }
            }
        }
        .tint(Theme.Colors.sunriseOrange)
    }
}

private struct DashboardSummaryCard: View {
    let homeName: String
    let lightCount: Int
    let alarmCount: Int
    let enabledCount: Int
    let needsAttentionCount: Int
    let nextAlarmDate: Date?
    let nextAlarmName: String?
    let isValidating: Bool
    let onCreate: () -> Void
    let onChangeHome: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            HStack(alignment: .top, spacing: Theme.Spacing.medium) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                    Text(homeName)
                        .font(Theme.Typography.title2)
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(summaryText)
                        .font(Theme.Typography.callout)
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Theme.Spacing.medium)

                Button(action: onCreate) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.Colors.dawnPurple)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.white))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New Alarm")
                .accessibilityIdentifier("newAlarmDashboardButton")
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.small), count: 3),
                spacing: Theme.Spacing.small
            ) {
                DashboardMetric(value: "\(lightCount)", label: "Lights", systemImage: "lightbulb.fill")
                DashboardMetric(value: "\(enabledCount)", label: "Enabled", systemImage: "power.circle.fill")
                DashboardMetric(value: "\(needsAttentionCount)", label: "Attention", systemImage: "wrench.and.screwdriver.fill")
            }

            Divider()
                .overlay(Color.white.opacity(0.18))

            HStack(alignment: .center, spacing: Theme.Spacing.medium) {
                Image(systemName: nextAlarmDate == nil ? "moon.zzz.fill" : "sunrise.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.Colors.morningGold)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(nextRunTitle)
                        .font(Theme.Typography.bodyBold)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(nextRunSubtitle)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(2)
                }

                Spacer()

                Button("Lights") {
                    onChangeHome()
                }
                .font(Theme.Typography.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.medium)
                .padding(.vertical, Theme.Spacing.xSmall)
                .background(Capsule().fill(Color.white.opacity(0.16)))
            }

            if isValidating {
                HStack(spacing: Theme.Spacing.small) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("Checking HomeKit")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.white.opacity(0.78))
                }
                .transition(.opacity)
            }
        }
        .padding(Theme.Spacing.xLarge)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.xLarge)
                .fill(Theme.Gradients.dashboard)
                .overlay(
                    // Soft rising-sun glow tucked into the corner of the dawn sky
                    Circle()
                        .fill(Theme.Gradients.sunGlow)
                        .frame(width: 320, height: 320)
                        .offset(x: 130, y: -150)
                        .blendMode(.plusLighter)
                        .opacity(0.75)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.xLarge)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xLarge))
        )
        .shadow(color: Theme.Colors.dawnPurple.opacity(0.25), radius: 18, x: 0, y: 12)
        .padding(.vertical, Theme.Spacing.small)
    }

    private var summaryText: String {
        if alarmCount == 0 {
            return "\(lightCount) selected light\(lightCount == 1 ? "" : "s") ready for a sunrise alarm."
        }
        if needsAttentionCount > 0 {
            return "\(needsAttentionCount) alarm\(needsAttentionCount == 1 ? "" : "s") need attention."
        }
        return "\(alarmCount) alarm\(alarmCount == 1 ? "" : "s") synced for selected lights."
    }

    private var nextRunTitle: String {
        guard let nextAlarmDate else { return "No upcoming alarm" }
        return nextAlarmDate.formatted(date: .omitted, time: .shortened)
    }

    private var nextRunSubtitle: String {
        guard let nextAlarmDate else {
            return "Enable an alarm to schedule the next sunrise ramp."
        }

        let dateText = nextAlarmDate.formatted(date: .abbreviated, time: .omitted)
        if let nextAlarmName {
            return "\(nextAlarmName) on \(dateText)"
        }
        return "Next run on \(dateText)"
    }
}

private struct DashboardMetric: View {
    let value: String
    let label: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
            HStack(spacing: Theme.Spacing.xSmall) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))

                Text(label)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Text(value)
                .font(Theme.Typography.title3)
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.medium)
                .fill(Color.white.opacity(0.14))
        )
    }
}

private struct AlarmSectionHeader: View {
    let title: String
    let count: Int
    let isValidating: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            Text(title)
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.xSmall)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.Colors.surface))

            Spacer()

            if isValidating {
                Label("Checking", systemImage: "arrow.triangle.2.circlepath")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }
}

private struct EmptyAlarmStateView: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.large) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Gradients.warmGlow)

            VStack(spacing: Theme.Spacing.small) {
                Text("No Alarms Yet")
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Create your first Light Alarm to brighten selected lights before wake-up.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            PrimaryButton(title: "Create Your First Alarm", action: onCreate)
                .accessibilityIdentifier("createFirstAlarmButton")
        }
        .padding(Theme.Spacing.xLarge)
        .frame(maxWidth: .infinity)
        .background(CardBackground(cornerRadius: Theme.Radius.xLarge))
        .padding(.vertical, Theme.Spacing.small)
    }
}

private struct RecoveryToolsCard: View {
    let onNuke: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack(spacing: Theme.Spacing.small) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)

                Text("HomeKit Recovery")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            Text("If sync gets stuck or alarms drift badly, clear DawnLoop's HomeKit scenes, triggers, and local bindings so you can repair or recreate them cleanly.")
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.textSecondary)

            Button(role: .destructive, action: onNuke) {
                Label("Nuke HomeKit", systemImage: "trash")
                    .font(Theme.Typography.bodyBold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.Colors.warning)
            .accessibilityIdentifier("nukeHomeKitButton")
        }
        .padding(Theme.Spacing.large)
        .background(CardBackground())
        .padding(.vertical, Theme.Spacing.small)
    }
}

private struct AlarmSetupRequiredView: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.large) {
            Image(systemName: "house.fill")
                .font(.system(size: 42))
                .foregroundStyle(Theme.Gradients.warmGlow)

            VStack(spacing: Theme.Spacing.small) {
                Text("Finish Home Setup")
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Choose an Apple Home and the lights DawnLoop should control before creating alarms.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            PrimaryButton(title: "Choose Home and Lights", action: onStart)
                .accessibilityIdentifier("chooseHomeAndLightsButton")
        }
        .padding(Theme.Spacing.xLarge)
        .frame(maxWidth: .infinity)
        .background(CardBackground(cornerRadius: Theme.Radius.xLarge))
        .padding(.vertical, Theme.Spacing.small)
    }
}

private struct AlarmRow: View {
    let item: AlarmListItem
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Sunrise accent on enabled alarms; quiet hairline on disabled ones
            Capsule()
                .fill(
                    item.alarm.isEnabled
                        ? AnyShapeStyle(Theme.Gradients.warmGlow)
                        : AnyShapeStyle(Theme.Colors.hairline)
                )
                .frame(width: 4)
                .padding(.vertical, Theme.Spacing.medium)
                .padding(.leading, Theme.Spacing.small)

            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                HStack(alignment: .top, spacing: Theme.Spacing.medium) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                        Text(item.viewModel.wakeTime)
                            .font(Theme.Typography.largeTitle)
                            .foregroundStyle(item.alarm.isEnabled ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text(item.alarm.name)
                            .font(Theme.Typography.bodyBold)
                            .foregroundStyle(item.alarm.isEnabled ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .trailing, spacing: Theme.Spacing.small) {
                        Button(action: onToggle) {
                            Image(systemName: item.alarm.isEnabled ? "power.circle.fill" : "power.circle")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(item.alarm.isEnabled ? Theme.Colors.sunriseOrange : Theme.Colors.textTertiary)
                                .frame(width: 40, height: 40)
                                .background(
                                    Circle()
                                        .fill(item.alarm.isEnabled ? Theme.Colors.sunriseOrange.opacity(0.12) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.alarm.isEnabled ? "Disable alarm" : "Enable alarm")
                        .accessibilityIdentifier("toggle-\(item.alarm.id.uuidString)")

                        StatusBadge(
                            text: item.validation.displayText,
                            systemImage: statusIcon,
                            color: statusColor
                        )
                        .layoutPriority(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                HStack(spacing: Theme.Spacing.small) {
                    Label(item.schedule.displayText, systemImage: "calendar")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)

                    if let nextRunDate = item.nextRunDate {
                        Text("•")
                            .foregroundStyle(Theme.Colors.textTertiary)

                        Text("Next: \(nextRunDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }

                if item.validation.isActionable, let message = item.validation.message {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(statusColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Spacing.large)
        }
        .background(CardBackground())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(alarmAccessibilityLabel)
        .accessibilityHint("Opens alarm editor")
        .accessibilityIdentifier("alarmRow-\(item.alarm.id.uuidString)")
    }

    private var alarmAccessibilityLabel: String {
        var parts = [
            item.alarm.name,
            item.viewModel.wakeTime,
            item.schedule.displayText,
            item.validation.displayText
        ]

        if let nextRunDate = item.nextRunDate {
            parts.append("Next \(nextRunDate.formatted(date: .abbreviated, time: .shortened))")
        }

        return parts.joined(separator: ", ")
    }

    private var statusIcon: String {
        switch item.validation.state {
        case .valid:
            return "checkmark.circle.fill"
        case .needsSync:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .outOfSync, .invalidAccessories:
            return "exclamationmark.triangle.fill"
        case .permissionRevoked, .homeUnavailable:
            return "lock.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch item.validation.state {
        case .valid:
            return Theme.Colors.success
        case .needsSync:
            return Theme.Colors.sunriseOrange
        case .outOfSync, .invalidAccessories, .permissionRevoked, .homeUnavailable:
            return .orange
        case .unknown:
            return Theme.Colors.textSecondary
        }
    }
}

private struct StatusBadge: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: Theme.Spacing.xSmall) {
            Image(systemName: systemImage)
                .imageScale(.small)

            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .font(Theme.Typography.caption.weight(.semibold))
        .foregroundStyle(color)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, Theme.Spacing.small)
        .padding(.vertical, Theme.Spacing.xSmall)
        .background(Capsule().fill(color.opacity(0.12)))
    }
}

private struct CardBackground: View {
    var cornerRadius: CGFloat = Theme.Radius.large

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Theme.Colors.elevatedSurface)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Theme.Colors.hairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 5)
    }
}

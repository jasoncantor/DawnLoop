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
    var editorState = AlarmEditorState()
    var editingAlarmID: UUID?
    var pendingDeleteItem: AlarmListItem?
    var activeHomeName: String?
    var activeHomeIdentifier: String?
    var configuredLightCount = 0
    var isHomeConfigured = false

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func refresh() async {
        isLoading = true
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

        let alarms = await environment.alarmRepository.fetchAllAlarms()
        var loadedItems: [AlarmListItem] = []
        for alarm in alarms {
            let scheduleRecord = await environment.alarmRepository.fetchSchedule(for: alarm.id)
            let schedule = scheduleRecord?.weekdaySchedule ?? .never
            let validation = await environment.automationRepairService.validateAlarm(
                alarm,
                schedule: scheduleRecord?.weekdaySchedule
            )

            loadedItems.append(
                AlarmListItem(
                    alarm: alarm,
                    schedule: schedule,
                    validation: validation,
                    nextRunDate: alarm.isEnabled
                        ? WakeAlarmSchedule(alarmId: alarm.id, weekdaySchedule: schedule).nextOccurrence(
                            alarm: alarm,
                            coordinate: solarCoordinate
                        )
                        : nil
                )
            )
        }

        items = loadedItems.sorted { lhs, rhs in
            (lhs.nextRunDate ?? .distantFuture) < (rhs.nextRunDate ?? .distantFuture)
        }
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

        guard let homeIdentifier = activeHomeIdentifier else {
            alertMessage = "Choose an Apple Home before saving this alarm."
            return
        }

        guard let alarm = editorState.createAlarm() else {
            return
        }

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

        return ((try? context.fetch(descriptor)) ?? [])
            .map(AccessoryViewModel.init(from:))
            .sorted { $0.roomName == $1.roomName ? $0.name < $1.name : $0.roomName < $1.roomName }
    }

    private func selectedAccessories() async -> [AccessoryViewModel] {
        await environment.accessoryDiscoveryService.selectedAccessories()
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
                    HomeSummaryCard(
                        homeName: store.activeHomeName ?? "Apple Home",
                        lightCount: store.configuredLightCount,
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
                    Section("Light Alarms") {
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
        .task {
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

private struct HomeSummaryCard: View {
    let homeName: String
    let lightCount: Int
    let onChangeHome: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Text(homeName)
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("\(lightCount) selected light\(lightCount == 1 ? "" : "s") ready for light alarms")
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textSecondary)

            Button("Change Home or Lights") {
                onChangeHome()
            }
            .font(Theme.Typography.footnote)
            .foregroundStyle(Theme.Colors.sunriseOrange)
        }
        .padding(Theme.Spacing.large)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.large)
                .fill(Theme.Colors.surface)
        )
        .padding(.vertical, Theme.Spacing.small)
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
    }
}

private struct RecoveryToolsCard: View {
    let onNuke: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Label("HomeKit Recovery", systemImage: "wrench.and.screwdriver.fill")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("If sync gets stuck or alarms drift badly, clear DawnLoop's HomeKit scenes, triggers, and local bindings so you can repair or recreate them cleanly.")
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textSecondary)

            Button(role: .destructive, action: onNuke) {
                Label("Nuke HomeKit", systemImage: "trash")
                    .font(Theme.Typography.bodyBold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Colors.warning)
            .accessibilityIdentifier("nukeHomeKitButton")
        }
        .padding(Theme.Spacing.large)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.large)
                .fill(Theme.Colors.surface)
        )
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
    }
}

private struct AlarmRow: View {
    let item: AlarmListItem
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.viewModel.wakeTime)
                    .font(Theme.Typography.title2)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Spacer()

                Button(action: onToggle) {
                    Image(systemName: item.alarm.isEnabled ? "power.circle.fill" : "power.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(item.alarm.isEnabled ? Theme.Colors.sunriseOrange : Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.alarm.isEnabled ? "Disable alarm" : "Enable alarm")
                    .accessibilityIdentifier("toggle-\(item.alarm.id.uuidString)")
            }

            Text(item.alarm.name)
                .font(Theme.Typography.bodyBold)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(item.schedule.displayText)
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.textSecondary)

            HStack(spacing: Theme.Spacing.small) {
                Label(item.validation.displayText, systemImage: statusIcon)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(statusColor)

                if let nextRunDate = item.nextRunDate {
                    Text("•")
                        .foregroundStyle(Theme.Colors.textTertiary)

                    Text("Next: \(nextRunDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xSmall)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("alarmRow-\(item.alarm.id.uuidString)")
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
            return .green
        case .needsSync:
            return Theme.Colors.sunriseOrange
        case .outOfSync, .invalidAccessories, .permissionRevoked, .homeUnavailable:
            return .orange
        case .unknown:
            return Theme.Colors.textSecondary
        }
    }
}

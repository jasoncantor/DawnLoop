import SwiftUI
import SwiftData

/// The main alarm editor form with validation
/// Implements VAL-ALARM-001 (validation), VAL-ALARM-002 (capability-aware controls), and VAL-ALARM-008 (invalidated accessories)
struct AlarmEditorView: View {
    @Bindable var state: AlarmEditorState
    let isSaving: Bool
    let saveProgress: Double
    let saveProgressMessage: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        let previewRefreshState = PreviewRefreshState(state: state)

        NavigationStack {
            Form {
                    // MARK: - Name Section
                    Section {
                        TextField("Alarm Name", text: $state.alarmName)
                            .font(Theme.Typography.body)

                        if let error = state.validation.nameError {
                            ValidationErrorMessage(message: error)
                        }
                    } header: {
                        Text("Name")
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    // MARK: - Time Section
                    Section {
                        Picker("Based On", selection: $state.timeReference) {
                            ForEach(AlarmTimeReference.allCases, id: \.self) { reference in
                                Text(reference.displayName)
                                    .tag(reference)
                            }
                        }
                        .pickerStyle(.segmented)

                        if state.timeReference == .clock {
                            DatePicker(
                                "Time",
                                selection: $state.wakeTime,
                                displayedComponents: .hourAndMinute
                            )
                            .font(Theme.Typography.body)
                        } else {
                            Stepper(
                                value: $state.timeOffsetMinutes,
                                in: -180...180,
                                step: 5
                            ) {
                                HStack {
                                    Text("Offset")
                                        .font(Theme.Typography.body)
                                    Spacer()
                                    Text(offsetLabel(for: state.timeReference, minutes: state.timeOffsetMinutes))
                                        .font(Theme.Typography.body)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }

                            Text("Uses your local \(state.timeReference.displayName.lowercased()) time when available for previews. HomeKit still creates the real solar automation.")
                                .font(Theme.Typography.footnote)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }

                        Stepper(
                            value: $state.durationMinutes,
                            in: 1...120,
                            step: 5
                        ) {
                            HStack {
                                Text("Duration")
                                    .font(Theme.Typography.body)
                                Spacer()
                                Text("\(state.durationMinutes) min")
                                    .font(Theme.Typography.body)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }

                        if let error = state.validation.durationError {
                            ValidationErrorMessage(message: error)
                        }
                    } header: {
                        Text("Schedule")
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    Section {
                        Picker("Repeat", selection: Binding(
                            get: { repeatPreset(for: state.repeatSchedule) },
                            set: { preset in
                                switch preset {
                                case .once:
                                    state.repeatSchedule = .never
                                case .weekdays:
                                    state.repeatSchedule = .weekdays
                                case .everyDay:
                                    state.repeatSchedule = .everyDay
                                case .custom:
                                    break
                                }
                            }
                        )) {
                            ForEach(RepeatPreset.allCases, id: \.self) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .pickerStyle(.segmented)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: Theme.Spacing.small) {
                            ForEach(WeekdayDescriptor.allCases, id: \.self) { day in
                                Button(day.shortTitle) {
                                    toggle(day, in: state)
                                }
                                .font(Theme.Typography.footnote)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Theme.Spacing.small)
                                .background(
                                    Capsule()
                                        .fill(day.isEnabled(in: state.repeatSchedule) ? Theme.Colors.sunriseOrange : Theme.Colors.surface)
                                )
                                .foregroundStyle(day.isEnabled(in: state.repeatSchedule) ? Color.white : Theme.Colors.textSecondary)
                            }
                        }
                    } header: {
                        Text("Repeat")
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    // MARK: - Brightness Section
                    Section {
                        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                            Text("Start Brightness: \(state.startBrightness)%")
                                .font(Theme.Typography.body)
                            Slider(
                                value: .init(
                                    get: { Double(state.startBrightness) },
                                    set: { state.startBrightness = Int($0) }
                                ),
                                in: 0...100,
                                step: 1
                            )
                            .tint(Theme.Colors.sunriseOrange)
                        }

                        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                            Text("Target Brightness: \(state.targetBrightness)%")
                                .font(Theme.Typography.body)
                            Slider(
                                value: .init(
                                    get: { Double(state.targetBrightness) },
                                    set: { state.targetBrightness = Int($0) }
                                ),
                                in: 0...100,
                                step: 1
                            )
                            .tint(Theme.Colors.sunriseOrange)
                        }

                        if let error = state.validation.brightnessError {
                            ValidationErrorMessage(message: error)
                        }
                    } header: {
                        Text("Brightness")
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    // MARK: - Gradient Curve Section
                    Section {
                        Picker("Gradient", selection: $state.gradientCurve) {
                            ForEach(GradientCurve.allCases, id: \.self) { curve in
                                Text(curve.displayName)
                                    .tag(curve)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(Theme.Typography.body)
                        .onChange(of: state.gradientCurve) { _, _ in
                            // Regenerate preview when gradient curve changes (VAL-ALARM-003)
                            state.regeneratePreview()
                        }
                    } header: {
                        Text("Transition Style")
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    // MARK: - Preview Section (VAL-ALARM-003, VAL-ALARM-004)
                    Section {
                        if state.canGeneratePreview {
                            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                                // Preview degradation message for mixed capabilities (VAL-ALARM-004)
                                if let explanation = state.previewDegradationExplanation {
                                    HStack(spacing: Theme.Spacing.small) {
                                        Image(systemName: "info.circle.fill")
                                            .foregroundStyle(Theme.Colors.sunriseOrange)
                                        Text(explanation)
                                            .font(Theme.Typography.footnote)
                                            .foregroundStyle(Theme.Colors.textSecondary)
                                    }
                                    .padding(.bottom, Theme.Spacing.small)
                                }

                                // Preview steps visualization
                                AlarmPreviewChart(steps: state.previewSteps)
                                    .frame(height: 120)

                                // Legend
                                HStack(spacing: Theme.Spacing.medium) {
                                    HStack(spacing: Theme.Spacing.xSmall) {
                                        Circle()
                                            .fill(Theme.Colors.sunriseOrange)
                                            .frame(width: 8, height: 8)
                                        Text("Brightness")
                                            .font(Theme.Typography.caption)
                                            .foregroundStyle(Theme.Colors.textSecondary)
                                    }

                                    if state.previewSteps.contains(where: { $0.hasColorTemperature }) {
                                        HStack(spacing: Theme.Spacing.xSmall) {
                                            Circle()
                                                .fill(Theme.Colors.morningGold)
                                                .frame(width: 8, height: 8)
                                            Text("Warmth")
                                                .font(Theme.Typography.caption)
                                                .foregroundStyle(Theme.Colors.textSecondary)
                                        }
                                    }
                                }
                                .padding(.top, Theme.Spacing.small)
                            }
                        } else {
                            // Invalid state - show message explaining why preview is unavailable (VAL-ALARM-004)
                            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                                HStack(spacing: Theme.Spacing.small) {
                                    Image(systemName: "eye.slash.fill")
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                    Text("Preview unavailable")
                                        .font(Theme.Typography.body)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }

                                if state.alarmName.isEmpty {
                                    Text("Add an alarm name to see preview")
                                        .font(Theme.Typography.footnote)
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                } else if state.selectedAccessoryIds.isEmpty {
                                    Text("Select at least one light to see preview")
                                        .font(Theme.Typography.footnote)
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                }
                            }
                            .padding(.vertical, Theme.Spacing.small)
                        }
                    } header: {
                        Text("Preview")
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .onAppear {
                        // Generate initial preview if valid
                        state.regeneratePreview()
                    }
                    .onChange(of: state.canGeneratePreview) { _, canGenerate in
                        if canGenerate {
                            state.regeneratePreview()
                        } else {
                            state.clearPreview()
                        }
                    }

                    // MARK: - Accessories Section
                    Section {
                        if state.availableAccessories.isEmpty {
                            Text("No lights available")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        } else {
                            ForEach(state.availableAccessories) { accessory in
                                AccessorySelectionRow(
                                    accessory: accessory,
                                    isSelected: state.selectedAccessoryIds.contains(accessory.homeKitIdentifier),
                                    onToggle: {
                                        if state.selectedAccessoryIds.contains(accessory.homeKitIdentifier) {
                                            state.selectedAccessoryIds.remove(accessory.homeKitIdentifier)
                                        } else {
                                            state.selectedAccessoryIds.insert(accessory.homeKitIdentifier)
                                        }
                                    }
                                )
                            }
                        }

                        if let error = state.validation.accessoryError {
                            ValidationErrorMessage(message: error)
                        }

                        if let error = state.validation.invalidatedAccessoryError {
                            HStack(spacing: Theme.Spacing.small) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Theme.Colors.sunriseOrange)
                                Text(error)
                                    .font(Theme.Typography.footnote)
                                    .foregroundStyle(Theme.Colors.sunriseOrange)
                            }
                            .padding(.vertical, Theme.Spacing.small)
                        }
                    } header: {
                        Text("Lights")
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    // MARK: - Color Mode Section
                    Section {
                        Picker("Color Mode", selection: $state.colorMode) {
                            ForEach(AlarmColorMode.allCases, id: \.self) { mode in
                                Text(mode.displayName)
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        // Color temperature controls - only show if capability supports it (VAL-ALARM-002)
                        if state.colorMode == .colorTemperature && state.canShowColorTemperature {
                            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                                Text("Warmth: \(state.targetColorTemperature ?? 300) mireds")
                                    .font(Theme.Typography.body)
                                Slider(
                                    value: .init(
                                        get: { Double(state.targetColorTemperature ?? 300) },
                                        set: { state.targetColorTemperature = Int($0) }
                                    ),
                                    in: 153...454,
                                    step: 1
                                )
                                .tint(Theme.Colors.sunriseOrange)
                            }
                            .padding(.top, Theme.Spacing.small)
                        }

                        // Full color controls - only show if capability supports it (VAL-ALARM-002)
                        if state.colorMode == .fullColor && state.canShowFullColor {
                            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                                    Text("Hue: \(state.targetHue ?? 0)°")
                                        .font(Theme.Typography.body)
                                    Slider(
                                        value: .init(
                                            get: { Double(state.targetHue ?? 0) },
                                            set: { state.targetHue = Int($0) }
                                        ),
                                        in: 0...360,
                                        step: 1
                                    )
                                    .tint(Theme.Colors.sunriseOrange)
                                }

                                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                                    Text("Saturation: \(state.targetSaturation ?? 0)%")
                                        .font(Theme.Typography.body)
                                    Slider(
                                        value: .init(
                                            get: { Double(state.targetSaturation ?? 0) },
                                            set: { state.targetSaturation = Int($0) }
                                        ),
                                        in: 0...100,
                                        step: 1
                                    )
                                    .tint(Theme.Colors.sunriseOrange)
                                }
                            }
                            .padding(.top, Theme.Spacing.small)
                        }

                        // Show degradation explanation for mixed capabilities (VAL-ALARM-002)
                        if let explanation = state.degradationExplanation {
                            HStack(spacing: Theme.Spacing.small) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(Theme.Colors.textTertiary)
                                Text(explanation)
                                    .font(Theme.Typography.footnote)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            .padding(.top, Theme.Spacing.small)
                        }

                        // Show message when color mode isn't supported by any selected accessory (VAL-ALARM-002)
                        if state.colorMode != .brightnessOnly && !state.selectedAccessoryIds.isEmpty {
                            if !state.canShowColorTemperature && state.colorMode == .colorTemperature {
                                HStack(spacing: Theme.Spacing.small) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(Theme.Colors.sunriseOrange)
                                    Text("None of your selected lights support color temperature. They'll use brightness only.")
                                        .font(Theme.Typography.footnote)
                                        .foregroundStyle(Theme.Colors.sunriseOrange)
                                }
                                .padding(.top, Theme.Spacing.small)
                            } else if !state.canShowFullColor && state.colorMode == .fullColor {
                                HStack(spacing: Theme.Spacing.small) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(Theme.Colors.sunriseOrange)
                                    Text("None of your selected lights support full color. They'll fall back to available features.")
                                        .font(Theme.Typography.footnote)
                                        .foregroundStyle(Theme.Colors.sunriseOrange)
                                }
                                .padding(.top, Theme.Spacing.small)
                            }
                        }

                        if let error = state.validation.colorError {
                            ValidationErrorMessage(message: error)
                        }
                    } header: {
                        Text("Color")
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    // MARK: - Status Section
                    Section {
                        Toggle("Enabled", isOn: $state.isEnabled)
                            .font(Theme.Typography.body)
                    } header: {
                        Text("Status")
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .formStyle(.grouped)
                .disabled(isSaving)
                .onChange(of: previewRefreshState) { _, _ in
                    refreshPreview(state)
                }
            .navigationTitle(state.isEditing ? "Edit Alarm" : "New Alarm")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Validate before saving (VAL-ALARM-001)
                        if state.validate() {
                            onSave()
                        }
                    }
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(state.validation.isValid ? Theme.Colors.sunriseOrange : Theme.Colors.textTertiary)
                    .disabled(isSaving || (!state.validation.isValid && state.validation.hasErrors))
                }
            }
            .tint(Theme.Colors.sunriseOrange)
            .interactiveDismissDisabled(isSaving)
            .overlay {
                if isSaving {
                    ZStack {
                        Color.black.opacity(0.12)
                            .ignoresSafeArea()

                        VStack(spacing: Theme.Spacing.medium) {
                            ProgressView(value: saveProgress, total: 1)
                                .progressViewStyle(.linear)
                                .tint(Theme.Colors.sunriseOrange)
                            Text("\(Int((saveProgress * 100).rounded()))%")
                                .font(Theme.Typography.bodyBold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text(saveProgressMessage)
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
        }
    }
}

private enum RepeatPreset: CaseIterable {
    case once
    case weekdays
    case everyDay
    case custom

    var title: String {
        switch self {
        case .once: return "Once"
        case .weekdays: return "Weekdays"
        case .everyDay: return "Daily"
        case .custom: return "Custom"
        }
    }
}

private struct PreviewRefreshState: Equatable {
    let alarmName: String
    let wakeTime: Date
    let timeReference: AlarmTimeReference
    let timeOffsetMinutes: Int
    let durationMinutes: Int
    let startBrightness: Int
    let targetBrightness: Int
    let colorMode: AlarmColorMode
    let targetColorTemperature: Int?
    let targetHue: Int?
    let targetSaturation: Int?
    let selectedAccessoryIds: Set<String>

    @MainActor
    init(state: AlarmEditorState) {
        alarmName = state.alarmName
        wakeTime = state.wakeTime
        timeReference = state.timeReference
        timeOffsetMinutes = state.timeOffsetMinutes
        durationMinutes = state.durationMinutes
        startBrightness = state.startBrightness
        targetBrightness = state.targetBrightness
        colorMode = state.colorMode
        targetColorTemperature = state.targetColorTemperature
        targetHue = state.targetHue
        targetSaturation = state.targetSaturation
        selectedAccessoryIds = state.selectedAccessoryIds
    }
}

@MainActor
private func refreshPreview(_ state: AlarmEditorState) {
    if state.canGeneratePreview {
        state.regeneratePreview()
    } else {
        state.clearPreview()
    }
}

private enum WeekdayDescriptor: CaseIterable {
    case sun, mon, tue, wed, thu, fri, sat

    var shortTitle: String {
        switch self {
        case .sun: return "S"
        case .mon: return "M"
        case .tue: return "T"
        case .wed: return "W"
        case .thu: return "T"
        case .fri: return "F"
        case .sat: return "S"
        }
    }

    func isEnabled(in schedule: WeekdaySchedule) -> Bool {
        switch self {
        case .sun: return schedule.sunday
        case .mon: return schedule.monday
        case .tue: return schedule.tuesday
        case .wed: return schedule.wednesday
        case .thu: return schedule.thursday
        case .fri: return schedule.friday
        case .sat: return schedule.saturday
        }
    }
}

private func repeatPreset(for schedule: WeekdaySchedule) -> RepeatPreset {
    if schedule == .never {
        return .once
    }
    if schedule == .weekdays {
        return .weekdays
    }
    if schedule == .everyDay {
        return .everyDay
    }
    return .custom
}

private func offsetLabel(for reference: AlarmTimeReference, minutes: Int) -> String {
    WakeAlarm.displayText(for: reference, offsetMinutes: minutes)
}

@MainActor
private func toggle(_ day: WeekdayDescriptor, in state: AlarmEditorState) {
    switch day {
    case .sun: state.repeatSchedule.sunday.toggle()
    case .mon: state.repeatSchedule.monday.toggle()
    case .tue: state.repeatSchedule.tuesday.toggle()
    case .wed: state.repeatSchedule.wednesday.toggle()
    case .thu: state.repeatSchedule.thursday.toggle()
    case .fri: state.repeatSchedule.friday.toggle()
    case .sat: state.repeatSchedule.saturday.toggle()
    }
}

// MARK: - Preview Chart

/// Visualizes the alarm preview steps as a gradient curve chart
struct AlarmPreviewChart: View {
    let steps: [WakeAlarmStep]

    var body: some View {
        GeometryReader { geometry in
            if steps.isEmpty {
                EmptyView()
            } else {
                ZStack {
                    // Background grid
                    VStack(spacing: 0) {
                        Divider()
                            .opacity(0.2)
                        Spacer()
                        Divider()
                            .opacity(0.2)
                        Spacer()
                        Divider()
                            .opacity(0.2)
                    }

                    // Brightness curve
                    brightnessCurve(in: geometry)
                        .stroke(Theme.Colors.sunriseOrange, lineWidth: 2)

                    // Step markers
                    ForEach(steps.indices, id: \.self) { index in
                        stepMarker(at: index, in: geometry)
                    }
                }
            }
        }
    }

    private func brightnessCurve(in geometry: GeometryProxy) -> Path {
        var path = Path()

        let width = geometry.size.width
        let height = geometry.size.height
        let stepWidth = width / CGFloat(max(steps.count - 1, 1))

        for (index, step) in steps.enumerated() {
            let x = CGFloat(index) * stepWidth
            let y = height - (CGFloat(step.brightness) / 100.0 * height)

            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        return path
    }

    private func stepMarker(at index: Int, in geometry: GeometryProxy) -> some View {
        let width = geometry.size.width
        let height = geometry.size.height
        let stepWidth = width / CGFloat(max(steps.count - 1, 1))

        let step = steps[index]
        let x = CGFloat(index) * stepWidth
        let y = height - (CGFloat(step.brightness) / 100.0 * height)

        return Circle()
            .fill(stepMarkerColor(for: step))
            .frame(width: 6, height: 6)
            .position(x: x, y: y)
    }

    private func stepMarkerColor(for step: WakeAlarmStep) -> Color {
        if step.hasFullColor {
            return Theme.Colors.morningGold
        } else if step.hasColorTemperature {
            return Theme.Colors.morningGold
        } else {
            return Theme.Colors.sunriseOrange
        }
    }
}

// MARK: - Supporting Views

struct ValidationErrorMessage: View {
    let message: String

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(Theme.Typography.footnote)
                .foregroundStyle(.red)
        }
        .padding(.vertical, Theme.Spacing.small)
    }
}

struct AccessorySelectionRow: View {
    let accessory: AccessoryViewModel
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: Theme.Spacing.medium) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Theme.Colors.sunriseOrange : Theme.Colors.textTertiary)

                // Accessory icon based on capability
                Image(systemName: iconName)
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.Colors.textSecondary)

                // Accessory info
                VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                    Text(accessory.name)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("\(accessory.roomName) · \(accessory.capability.displayName)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch accessory.capability {
        case .brightnessOnly:
            return "lightbulb"
        case .tunableWhite:
            return "lightbulb.fill"
        case .fullColor:
            return "lightbulb.2.fill"
        case .unsupported:
            return "lightbulb.slash"
        }
    }
}

// MARK: - Previews

#Preview("New Alarm") {
    AlarmEditorView(
        state: AlarmEditorState.previewState(),
        isSaving: false,
        saveProgress: 0,
        saveProgressMessage: "Saving alarm...",
        onSave: {},
        onCancel: {}
    )
}

#Preview("Edit Alarm") {
    let state = AlarmEditorState.previewState()
    state.editingAlarmId = UUID()
    return AlarmEditorView(
        state: state,
        isSaving: false,
        saveProgress: 0,
        saveProgressMessage: "Saving alarm...",
        onSave: {},
        onCancel: {}
    )
}

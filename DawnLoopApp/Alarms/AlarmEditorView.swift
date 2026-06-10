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
                    Section {
                        AlarmEditorSummaryCard(state: state)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }

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

                        Stepper(
                            value: $state.stepCount,
                            in: 1...state.maxStepCount
                        ) {
                            HStack {
                                Text("Steps")
                                    .font(Theme.Typography.body)
                                Spacer()
                                Text("\(state.stepCount)")
                                    .font(Theme.Typography.body)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }

                        Text("\(state.stepDensityDescription). Maximum density is 1 step per minute, capped at 30 steps.")
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    } header: {
                        Text("Schedule")
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    Section {
                        Picker("Repeat", selection: Binding(
                            get: { state.repeatPreset },
                            set: { state.setRepeatPreset($0) }
                        )) {
                            ForEach(AlarmRepeatPreset.allCases, id: \.self) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .pickerStyle(.segmented)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: Theme.Spacing.small) {
                            ForEach(WeekdaySchedule.Weekday.allCases, id: \.self) { day in
                                let isEnabled = state.repeatSchedule.contains(day)

                                Button(day.shortTitle) {
                                    state.toggleRepeatDay(day)
                                }
                                .buttonStyle(.plain)
                                .font(Theme.Typography.footnote)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Theme.Spacing.small)
                                .background(
                                    Capsule()
                                        .fill(isEnabled ? Theme.Colors.sunriseOrange : Theme.Colors.surface)
                                )
                                .foregroundStyle(isEnabled ? Color.white : Theme.Colors.textSecondary)
                                .accessibilityLabel(day.displayName)
                                .accessibilityValue(isEnabled ? "Selected" : "Not selected")
                            }
                        }
                    } header: {
                        Text("Repeat")
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    // MARK: - Brightness Section
                    Section {
                        EditorSliderRow(
                            title: "Start Brightness",
                            valueText: "\(state.startBrightness)%",
                            value: .init(
                                get: { Double(state.startBrightness) },
                                set: { state.startBrightness = Int($0) }
                            ),
                            bounds: 0...100
                        )

                        EditorSliderRow(
                            title: "Target Brightness",
                            valueText: "\(state.targetBrightness)%",
                            value: .init(
                                get: { Double(state.targetBrightness) },
                                set: { state.targetBrightness = Int($0) }
                            ),
                            bounds: 0...100
                        )

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
                                    EditorCallout(
                                        message: explanation,
                                        systemImage: "info.circle.fill",
                                        tint: Theme.Colors.sunriseOrange
                                    )
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
                            EditorCallout(
                                message: error,
                                systemImage: "exclamationmark.triangle.fill",
                                tint: Theme.Colors.sunriseOrange
                            )
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
                            EditorSliderRow(
                                title: "Warmth",
                                valueText: "\(state.targetColorTemperature ?? AlarmEditorState.defaultColorTemperature) mireds",
                                value: .init(
                                    get: { Double(state.targetColorTemperature ?? AlarmEditorState.defaultColorTemperature) },
                                    set: { state.targetColorTemperature = Int($0) }
                                ),
                                bounds: 153...454
                            )
                            .padding(.top, Theme.Spacing.small)
                        }

                        // Full color controls - only show if capability supports it (VAL-ALARM-002)
                        if state.colorMode == .fullColor && state.canShowFullColor {
                            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                                EditorSliderRow(
                                    title: "Hue",
                                    valueText: "\(state.targetHue ?? AlarmEditorState.defaultHue)°",
                                    value: .init(
                                        get: { Double(state.targetHue ?? AlarmEditorState.defaultHue) },
                                        set: { state.targetHue = Int($0) }
                                    ),
                                    bounds: 0...360
                                )

                                EditorSliderRow(
                                    title: "Saturation",
                                    valueText: "\(state.targetSaturation ?? AlarmEditorState.defaultSaturation)%",
                                    value: .init(
                                        get: { Double(state.targetSaturation ?? AlarmEditorState.defaultSaturation) },
                                        set: { state.targetSaturation = Int($0) }
                                    ),
                                    bounds: 0...100
                                )
                            }
                            .padding(.top, Theme.Spacing.small)
                        }

                        // Show degradation explanation for mixed capabilities (VAL-ALARM-002)
                        if let explanation = state.degradationExplanation {
                            EditorCallout(
                                message: explanation,
                                systemImage: "info.circle.fill",
                                tint: Theme.Colors.textSecondary
                            )
                            .padding(.top, Theme.Spacing.small)
                        }

                        // Show message when color mode isn't supported by any selected accessory (VAL-ALARM-002)
                        if state.colorMode != .brightnessOnly && !state.selectedAccessoryIds.isEmpty {
                            if !state.canShowColorTemperature && state.colorMode == .colorTemperature {
                                EditorCallout(
                                    message: "None of your selected lights support color temperature. They'll use brightness only.",
                                    systemImage: "exclamationmark.triangle.fill",
                                    tint: Theme.Colors.sunriseOrange
                                )
                                .padding(.top, Theme.Spacing.small)
                            } else if !state.canShowFullColor && state.colorMode == .fullColor {
                                EditorCallout(
                                    message: "None of your selected lights support full color. They'll fall back to available features.",
                                    systemImage: "exclamationmark.triangle.fill",
                                    tint: Theme.Colors.sunriseOrange
                                )
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
                .scrollContentBackground(.hidden)
                .background(Theme.Gradients.appBackground.ignoresSafeArea())
                .disabled(isSaving)
                .onAppear {
                    refreshPreview(state)
                }
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

private struct AlarmEditorSummaryCard: View {
    let state: AlarmEditorState

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            HStack(alignment: .top, spacing: Theme.Spacing.medium) {
                ZStack {
                    Circle()
                        .fill(Theme.Gradients.warmGlow)
                    Image(systemName: "sunrise.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                    Text(state.alarmName.isEmpty ? "New sunrise alarm" : state.alarmName)
                        .font(Theme.Typography.title3)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)

                    Text(summaryText)
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: Theme.Spacing.small) {
                EditorMetricPill(value: timeText, label: "Wake", systemImage: "clock")
                EditorMetricPill(value: "\(state.durationMinutes)m", label: "Ramp", systemImage: "timer")
                EditorMetricPill(value: "\(state.stepCount)", label: "Steps", systemImage: "chart.bar.fill")
            }
        }
        .padding(Theme.Spacing.large)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.xLarge)
                .fill(Theme.Colors.elevatedSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.xLarge)
                        .stroke(Theme.Colors.hairline, lineWidth: 1)
                )
        )
        .padding(.vertical, Theme.Spacing.small)
    }

    private var summaryText: String {
        let lightCount = state.selectedAccessoryIds.count
        let repeatText = state.repeatSchedule.displayText.lowercased()
        let lightText = "\(lightCount) light\(lightCount == 1 ? "" : "s")"
        return "\(lightText) • \(repeatText) • \(state.gradientCurve.displayName)"
    }

    private var timeText: String {
        if state.timeReference == .clock {
            return state.wakeTime.formatted(date: .omitted, time: .shortened)
        }
        return WakeAlarm.displayText(
            for: state.timeReference,
            offsetMinutes: state.timeOffsetMinutes
        )
    }
}

private struct EditorMetricPill: View {
    let value: String
    let label: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: systemImage)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(value)
                .font(Theme.Typography.footnote.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.medium)
                .fill(Theme.Colors.surface)
        )
    }
}

private struct EditorSliderRow: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let bounds: ClosedRange<Double>

    init(
        title: String,
        valueText: String,
        value: Binding<Double>,
        bounds: ClosedRange<Double>
    ) {
        self.title = title
        self.valueText = valueText
        self._value = value
        self.bounds = bounds
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Spacer(minLength: Theme.Spacing.medium)

                Text(valueText)
                    .font(Theme.Typography.bodyBold)
                    .foregroundStyle(Theme.Colors.sunriseOrange)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Slider(value: $value, in: bounds, step: 1)
                .tint(Theme.Colors.sunriseOrange)
        }
        .padding(.vertical, Theme.Spacing.xSmall)
    }
}

private struct EditorCallout: View {
    let message: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.small) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18)

            Text(message)
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.medium)
                .fill(tint.opacity(0.10))
        )
    }
}

private struct PreviewRefreshState: Equatable {
    let alarmName: String
    let wakeTime: Date
    let timeReference: AlarmTimeReference
    let timeOffsetMinutes: Int
    let durationMinutes: Int
    let stepCount: Int
    let startBrightness: Int
    let targetBrightness: Int
    let gradientCurve: GradientCurve
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
        stepCount = state.stepCount
        startBrightness = state.startBrightness
        targetBrightness = state.targetBrightness
        gradientCurve = state.gradientCurve
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

private func offsetLabel(for reference: AlarmTimeReference, minutes: Int) -> String {
    WakeAlarm.displayText(for: reference, offsetMinutes: minutes)
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

                    // Warm wash under the ramp - the room filling with light
                    brightnessArea(in: geometry)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Theme.Colors.morningGold.opacity(0.45),
                                    Theme.Colors.sunriseOrange.opacity(0.20),
                                    Theme.Colors.sunriseOrange.opacity(0.02)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Brightness curve
                    brightnessCurve(in: geometry)
                        .stroke(
                            Theme.Gradients.warmGlow,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                        )

                    // Step markers
                    ForEach(steps.indices, id: \.self) { index in
                        stepMarker(at: index, in: geometry)
                    }
                }
            }
        }
    }

    private func curvePoints(in geometry: GeometryProxy) -> [CGPoint] {
        let width = geometry.size.width
        let height = geometry.size.height
        let stepWidth = width / CGFloat(max(steps.count - 1, 1))

        return steps.enumerated().map { index, step in
            CGPoint(
                x: CGFloat(index) * stepWidth,
                y: height - (CGFloat(step.brightness) / 100.0 * height)
            )
        }
    }

    private func brightnessCurve(in geometry: GeometryProxy) -> Path {
        var path = Path()

        for (index, point) in curvePoints(in: geometry).enumerated() {
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        return path
    }

    private func brightnessArea(in geometry: GeometryProxy) -> Path {
        let points = curvePoints(in: geometry)
        guard let first = points.first, let last = points.last else {
            return Path()
        }

        var path = Path()
        path.move(to: CGPoint(x: first.x, y: geometry.size.height))
        for point in points {
            path.addLine(to: point)
        }
        path.addLine(to: CGPoint(x: last.x, y: geometry.size.height))
        path.closeSubpath()
        return path
    }

    private func stepMarker(at index: Int, in geometry: GeometryProxy) -> some View {
        let point = curvePoints(in: geometry)[index]
        let step = steps[index]

        return Circle()
            .fill(stepMarkerColor(for: step))
            .frame(width: 7, height: 7)
            .overlay(
                Circle()
                    .stroke(Theme.Colors.elevatedSurface, lineWidth: 1.5)
            )
            .position(point)
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
                    .foregroundStyle(isSelected ? Theme.Colors.sunriseOrange : Theme.Colors.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(isSelected ? Theme.Colors.sunriseOrange.opacity(0.12) : Theme.Colors.surface)
                    )

                // Accessory info
                VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                    Text(accessory.name)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)

                    Text("\(accessory.roomName) · \(accessory.capability.displayName)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.vertical, Theme.Spacing.xSmall)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(accessory.name), \(accessory.roomName), \(accessory.capability.displayName)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
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

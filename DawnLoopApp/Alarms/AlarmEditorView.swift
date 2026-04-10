import SwiftUI
import SwiftData

/// The main alarm editor form with validation
/// Implements VAL-ALARM-001 (validation), VAL-ALARM-002 (capability-aware controls), and VAL-ALARM-008 (invalidated accessories)
struct AlarmEditorView: View {
    @Bindable var state: AlarmEditorState
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

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
                        DatePicker(
                            "Wake Time",
                            selection: $state.wakeTime,
                            displayedComponents: .hourAndMinute
                        )
                        .font(Theme.Typography.body)

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
                    } header: {
                        Text("Transition Style")
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
                .scrollContentBackground(.hidden)
                .formStyle(.grouped)
            }
            .navigationTitle(state.isEditing ? "Edit Alarm" : "New Alarm")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
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
                    .disabled(!state.validation.isValid && state.validation.hasErrors)
                }
            }
            .tint(Theme.Colors.sunriseOrange)
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
        onSave: {},
        onCancel: {}
    )
}

#Preview("Edit Alarm") {
    let state = AlarmEditorState.previewState()
    state.editingAlarmId = UUID()
    return AlarmEditorView(
        state: state,
        onSave: {},
        onCancel: {}
    )
}

import SwiftUI
import HomeKit

/// View for discovering and selecting compatible accessories grouped by room
/// Shows room-grouped accessories for the active home only (VAL-HOME-003)
struct AccessoryDiscoveryView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var roomGroups: [RoomAccessoryGroup] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedCount = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: Theme.Spacing.medium) {
                Text("Select Your Lights")
                    .font(Theme.Typography.title2)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Text("Choose which lights to include in your Light Alarm")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.large)
            }
            .padding(.top, Theme.Spacing.xxLarge)
            
            // Content
            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.2)
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Discovery Error",
                    message: error,
                    actionTitle: "Try Again",
                    action: { Task { await loadAccessories() } }
                )
                Spacer()
            } else if roomGroups.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: "lightbulb.slash",
                    title: "No Compatible Lights",
                    message: "No lights with brightness control were found in this home. Add compatible lights to Apple Home and try again.",
                    actionTitle: "Check Again",
                    action: { Task { await loadAccessories() } }
                )
                Spacer()
            } else {
                // Accessory list grouped by room
                ScrollView {
                    VStack(spacing: Theme.Spacing.xLarge) {
                        ForEach(roomGroups) { group in
                            RoomSection(group: group) { accessoryId in
                                Task {
                                    await toggleAccessory(accessoryId)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.large)
                    .padding(.vertical, Theme.Spacing.large)
                }
            }
            
            // Bottom action bar
            if !isLoading && !roomGroups.isEmpty {
                VStack(spacing: Theme.Spacing.medium) {
                    Text("\(selectedCount) light\(selectedCount == 1 ? "" : "s") selected")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    
                    PrimaryButton(
                        title: selectedCount > 0 ? "Continue" : "Skip for Now",
                        action: {
                            environment.onboardingState.completeOnboarding()
                        }
                    )
                    
                    Button("Switch Home") {
                        Task {
                            await environment.homeSelectionService.clearActiveHome()
                            environment.onboardingState.moveToHomeSelection()
                        }
                    }
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(.horizontal, Theme.Spacing.large)
                .padding(.bottom, Theme.Spacing.xxLarge)
                .padding(.top, Theme.Spacing.large)
                .background(
                    Theme.Colors.surface
                        .ignoresSafeArea(edges: .bottom)
                )
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .task {
            await loadAccessories()
        }
    }
    
    private func loadAccessories() async {
        isLoading = true
        errorMessage = nil
        
        // Get active home
        let homeResult = await environment.homeSelectionService.activeHome()
        
        switch homeResult {
        case .success(let home):
            let result = await environment.accessoryDiscoveryService.discoverAccessories(in: home)
            
            switch result {
            case .success(let groups):
                roomGroups = groups
                updateSelectedCount()
            case .noCompatibleAccessories:
                roomGroups = []
            case .homeNotFound:
                errorMessage = "Home not found. Please select a home again."
            case .error(let error):
                errorMessage = error.localizedDescription
            }
            
        case .notFound, .noSelection:
            errorMessage = "Please select a home first."
        case .error(let error):
            errorMessage = error.userFacingMessage
        }
        
        isLoading = false
    }
    
    private func toggleAccessory(_ accessoryId: String) async {
        await environment.accessoryDiscoveryService.toggleAccessorySelection(accessoryId)
        
        // Update local state to reflect change
        for groupIndex in roomGroups.indices {
            for accessoryIndex in roomGroups[groupIndex].accessories.indices {
                if roomGroups[groupIndex].accessories[accessoryIndex].homeKitIdentifier == accessoryId {
                    roomGroups[groupIndex].accessories[accessoryIndex].isSelected.toggle()
                }
            }
        }
        
        updateSelectedCount()
    }
    
    private func updateSelectedCount() {
        selectedCount = roomGroups.reduce(0) { count, group in
            count + group.accessories.filter(\.isSelected).count
        }
    }
}

/// Section view for a room and its accessories
struct RoomSection: View {
    let group: RoomAccessoryGroup
    let onToggle: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            // Room header
            HStack {
                Text(group.roomName)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                if group.hasSelection {
                    Text("(\(group.selectedCount) selected)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.primary)
                }
                
                Spacer()
            }
            
            // Accessories in room
            VStack(spacing: Theme.Spacing.small) {
                ForEach(group.accessories) { accessory in
                    AccessoryRow(accessory: accessory) {
                        onToggle(accessory.homeKitIdentifier)
                    }
                }
            }
        }
    }
}

/// Row view for a single accessory
struct AccessoryRow: View {
    let accessory: AccessoryViewModel
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: Theme.Spacing.medium) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(accessory.isSelected ? Theme.Colors.primary : Theme.Colors.textTertiary, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if accessory.isSelected {
                        Circle()
                            .fill(Theme.Colors.primary)
                            .frame(width: 16, height: 16)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                
                // Accessory icon
                Image(systemName: iconForCapability(accessory.capability))
                    .font(.system(size: 20))
                    .foregroundStyle(accessory.isSelected ? Theme.Colors.primary : Theme.Colors.textSecondary)
                    .frame(width: 32)
                
                // Accessory info
                VStack(alignment: .leading, spacing: 2) {
                    Text(accessory.name)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    
                    Text(accessory.capability.displayName)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                
                Spacer()
                
                // Reachability indicator
                if !accessory.isReachable {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Colors.warning)
                }
            }
            .padding(Theme.Spacing.medium)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.medium)
                    .fill(accessory.isSelected ? Theme.Colors.primary.opacity(0.08) : Theme.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium)
                    .stroke(
                        accessory.isSelected ? Theme.Colors.primary.opacity(0.2) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func iconForCapability(_ capability: AccessoryCapability) -> String {
        switch capability {
        case .fullColor:
            return "lightbulb.fill"
        case .tunableWhite:
            return "lightbulb.2.fill"
        case .brightnessOnly:
            return "lightbulb"
        case .unsupported:
            return "lightbulb.slash"
        }
    }
}

/// Empty state view with action
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: Theme.Spacing.large) {
            Image(systemName: icon)
                .font(.system(size: 50))
                .foregroundStyle(Theme.Colors.textSecondary)
            
            VStack(spacing: Theme.Spacing.small) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Spacing.large)
            
            Button(action: action) {
                Text(actionTitle)
                    .font(Theme.Typography.bodyBold)
                    .foregroundStyle(Theme.Colors.primary)
                    .padding(.horizontal, Theme.Spacing.large)
                    .padding(.vertical, Theme.Spacing.small)
                    .background(
                        Capsule()
                            .stroke(Theme.Colors.primary, lineWidth: 1)
                    )
            }
        }
    }
}

// MARK: - Preview

#Preview("Room Grouped Accessories") {
    AccessoryDiscoveryView()
        .environment(AppEnvironment())
}

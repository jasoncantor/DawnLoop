import SwiftUI
import HomeKit

/// View for selecting the active home from multiple available homes
/// Shows all homes with visible active choice (VAL-HOME-001)
struct HomeSelectionView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var homes: [HomeViewModel] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: Theme.Spacing.medium) {
                Text("Choose Your Home")
                    .font(Theme.Typography.title2)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Text("Select which Apple Home to use for Light Alarms")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Theme.Spacing.large)
            .padding(.top, Theme.Spacing.xxLarge)
            
            // Content
            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.2)
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: Theme.Spacing.medium) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.Colors.warning)
                    
                    Text(error)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Try Again") {
                        Task { await loadHomes() }
                    }
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.primary)
                }
                .padding(.horizontal, Theme.Spacing.large)
                Spacer()
            } else if homes.isEmpty {
                Spacer()
                VStack(spacing: Theme.Spacing.medium) {
                    Image(systemName: "house.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    
                    Text("No Homes Available")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    
                    Text("Create a home in the Apple Home app first, then return here.")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, Theme.Spacing.large)
                Spacer()
            } else {
                // Home list
                ScrollView {
                    VStack(spacing: Theme.Spacing.medium) {
                        ForEach(homes) { home in
                            HomeCard(home: home) {
                                Task {
                                    await selectHome(home)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.large)
                    .padding(.vertical, Theme.Spacing.large)
                }
            }
            
            // Bottom info
            if !isLoading && homes.count > 1 {
                Text("You can change this later in settings")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.bottom, Theme.Spacing.xxLarge)
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .task {
            await loadHomes()
        }
    }
    
    private func loadHomes() async {
        isLoading = true
        errorMessage = nil
        
        do {
            homes = await environment.homeSelectionService.availableHomes()
            // Note: Even with a single home, we show the selection UI
            // so the user can visibly see and confirm the active-home choice.
            // The user must explicitly tap to proceed (VAL-HOME-001).
        } catch {
            errorMessage = "Unable to load homes. Please try again."
        }
        
        isLoading = false
    }
    
    private func selectHome(_ home: HomeViewModel) async {
        let success = await environment.homeSelectionService.selectHome(home.homeKitIdentifier)
        
        if success {
            // Move to accessory discovery
            environment.onboardingState.moveToAccessoryDiscovery()
        } else {
            errorMessage = "Could not select home. Please try again."
            isLoading = false
        }
    }
}

/// Card view for a single home option
struct HomeCard: View {
    let home: HomeViewModel
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.medium) {
                // Home icon
                ZStack {
                    Circle()
                        .fill(home.isActive ? Theme.Colors.primary.opacity(0.15) : Theme.Colors.surface)
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "house.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(home.isActive ? Theme.Colors.primary : Theme.Colors.textSecondary)
                }
                
                // Home info
                VStack(alignment: .leading, spacing: 4) {
                    Text(home.name)
                        .font(Theme.Typography.bodyBold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    
                    HStack(spacing: Theme.Spacing.small) {
                        Label("\(home.roomCount) rooms", systemImage: "door.left.hand.closed")
                            .font(Theme.Typography.caption)
                        
                        Text("•")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                        
                        Label("\(home.accessoryCount) accessories", systemImage: "lightbulb.fill")
                            .font(Theme.Typography.caption)
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
                
                Spacer()
                
                // Selection indicator
                if home.isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.Colors.primary)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .padding(Theme.Spacing.large)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.large)
                    .fill(Theme.Colors.surface)
                    .shadow(
                        color: home.isActive ? Theme.Colors.primary.opacity(0.1) : Color.black.opacity(0.05),
                        radius: home.isActive ? 8 : 4,
                        x: 0,
                        y: home.isActive ? 4 : 2
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.large)
                    .stroke(
                        home.isActive ? Theme.Colors.primary.opacity(0.3) : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview("Multiple Homes") {
    let mockService = MockHomeSelectionService()
    
    Task {
        await mockService.setMockHomes([
            HomeViewModel(
                id: "home-1",
                homeKitIdentifier: "home-1",
                name: "My Home",
                isActive: true,
                roomCount: 4,
                accessoryCount: 12
            ),
            HomeViewModel(
                id: "home-2",
                homeKitIdentifier: "home-2",
                name: "Vacation House",
                isActive: false,
                roomCount: 3,
                accessoryCount: 8
            ),
            HomeViewModel(
                id: "home-3",
                homeKitIdentifier: "home-3",
                name: "Office",
                isActive: false,
                roomCount: 2,
                accessoryCount: 5
            )
        ])
    }
    
    return HomeSelectionView()
        .environment(AppEnvironment())
}

#Preview("Loading") {
    HomeSelectionView()
        .environment(AppEnvironment())
}

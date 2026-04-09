import SwiftUI

/// Dedicated view for Home access blocker/recovery states
struct HomeAccessBlockerView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var homeAccessState = HomeAccessState()
    
    let blockerState: HomeAccessReadiness
    
    var body: some View {
        VStack(spacing: 0) {
            // Content area
            ScrollView {
                VStack(spacing: Theme.Spacing.xxxLarge) {
                    Spacer()
                    
                    // Icon with themed styling
                    blockerIcon
                    
                    // Text content
                    VStack(spacing: Theme.Spacing.medium) {
                        Text(blockerCopy.title)
                            .font(Theme.Typography.title1)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .multilineTextAlignment(.center)
                        
                        Text(blockerCopy.message)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Theme.Spacing.xLarge)
                    
                    Spacer()
                }
                .padding(.vertical, Theme.Spacing.xxLarge)
            }
            
            // Bottom action area
            VStack(spacing: Theme.Spacing.medium) {
                PrimaryButton(
                    title: blockerCopy.primaryAction,
                    action: handlePrimaryAction
                )
                
                Button(blockerCopy.secondaryAction) {
                    Task {
                        await homeAccessState.retry()
                        updateReadiness()
                    }
                }
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
                .disabled(homeAccessState.isLoading)
            }
            .padding(.horizontal, Theme.Spacing.large)
            .padding(.bottom, Theme.Spacing.xxLarge)
            .padding(.top, Theme.Spacing.large)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .overlay {
            if homeAccessState.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.background.opacity(0.8))
            }
        }
        .onChange(of: homeAccessState.readiness) { _, newReadiness in
            handleReadinessChange(newReadiness)
        }
    }
    
    private var blockerIcon: some View {
        ZStack {
            // Outer glow rings based on state type
            ForEach(0..<2) { i in
                Circle()
                    .fill(blockerGlowGradient)
                    .opacity(0.15 - Double(i) * 0.05)
                    .frame(width: 140 + CGFloat(i * 30))
                    .blur(radius: 15)
            }
            
            // Icon background
            Circle()
                .fill(Theme.Colors.surface)
                .frame(width: 100, height: 100)
                .shadow(
                    color: blockerShadowColor.opacity(0.3),
                    radius: 15,
                    x: 0,
                    y: 8
                )
            
            // State-specific icon
            Image(systemName: blockerIconName)
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(blockerIconGradient)
        }
    }
    
    private var blockerCopy: BlockerCopy {
        switch blockerState {
        case .permissionDenied:
            return HomeAccessBlockerCopy.permissionDenied
        case .noHomeConfigured:
            return HomeAccessBlockerCopy.noHomeConfigured
        case .noHomeHub:
            return HomeAccessBlockerCopy.noHomeHub
        case .noCompatibleAccessories:
            return HomeAccessBlockerCopy.noCompatibleAccessories
        default:
            return BlockerCopy(
                title: "Checking...",
                message: "Please wait while we check your Home setup.",
                primaryAction: "Continue",
                secondaryAction: "Cancel"
            )
        }
    }
    
    private var blockerIconName: String {
        switch blockerState {
        case .permissionDenied:
            return "lock.fill"
        case .noHomeConfigured:
            return "house.badge.plus"
        case .noHomeHub:
            return "wifi.router"
        case .noCompatibleAccessories:
            return "lightbulb.slash"
        default:
            return "gear"
        }
    }
    
    private var blockerIconGradient: LinearGradient {
        switch blockerState {
        case .permissionDenied:
            return Theme.Gradients.warningGradient
        case .noHomeConfigured, .noHomeHub, .noCompatibleAccessories:
            return Theme.Gradients.infoGradient
        default:
            return Theme.Gradients.warmGlow
        }
    }
    
    private var blockerGlowGradient: LinearGradient {
        switch blockerState {
        case .permissionDenied:
            return Theme.Gradients.warningGradient
        default:
            return Theme.Gradients.warmGlow
        }
    }
    
    private var blockerShadowColor: Color {
        switch blockerState {
        case .permissionDenied:
            return Theme.Colors.sunriseOrange
        default:
            return Theme.Colors.dawnPurple
        }
    }
    
    private func handlePrimaryAction() {
        switch blockerState {
        case .permissionDenied:
            openSettings()
        case .noHomeConfigured:
            openHomeApp()
        case .noHomeHub:
            showHubInfo()
        case .noCompatibleAccessories:
            showCompatibleLightsInfo()
        default:
            break
        }
    }
    
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func openHomeApp() {
        // Try to open the Home app
        if let url = URL(string: "com.apple.home://") {
            UIApplication.shared.open(url)
        }
    }
    
    private func showHubInfo() {
        // In a real implementation, this would show an educational sheet
        // For now, we'll open Apple's support page
        if let url = URL(string: "https://support.apple.com/en-us/HT207057") {
            UIApplication.shared.open(url)
        }
    }
    
    private func showCompatibleLightsInfo() {
        // In a real implementation, this would show compatible devices
        // For now, we'll open Apple's Home accessories page
        if let url = URL(string: "https://www.apple.com/ios/home/accessories/") {
            UIApplication.shared.open(url)
        }
    }
    
    private func updateReadiness() {
        // Triggered after retry - parent view should observe this
    }
    
    private func handleReadinessChange(_ newReadiness: HomeAccessReadiness) {
        // If readiness changed to ready, update environment to proceed
        if newReadiness.isReady {
            environment.onboardingState.completeOnboarding()
        }
    }
}

// MARK: - Theme Extensions for Blocker States

extension Theme.Gradients {
    static let warningGradient = LinearGradient(
        colors: [
            Color(red: 1.0, green: 0.6, blue: 0.3),
            Color(red: 1.0, green: 0.4, blue: 0.2)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let infoGradient = LinearGradient(
        colors: [
            Color(red: 0.5, green: 0.7, blue: 1.0),
            Color(red: 0.3, green: 0.5, blue: 0.9)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Preview

#Preview("Permission Denied") {
    HomeAccessBlockerView(blockerState: .permissionDenied)
        .environment(AppEnvironment())
}

#Preview("No Home") {
    HomeAccessBlockerView(blockerState: .noHomeConfigured)
        .environment(AppEnvironment())
}

#Preview("No Hub") {
    HomeAccessBlockerView(blockerState: .noHomeHub)
        .environment(AppEnvironment())
}

#Preview("No Accessories") {
    HomeAccessBlockerView(blockerState: .noCompatibleAccessories)
        .environment(AppEnvironment())
}

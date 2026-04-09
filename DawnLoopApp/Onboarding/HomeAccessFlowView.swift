import SwiftUI
import HomeKit

/// Flow view that handles onboarding completion and Home access orchestration
struct HomeAccessFlowView: View {
    @Environment(AppEnvironment.self) private var environment
    
    var body: some View {
        Group {
            switch environment.homeAccessState.readiness {
            case .unknown, .checkingPermission:
                // Show loading during initial check
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.background)
                    .task {
                        await environment.homeAccessState.startHomeAccessFlow()
                    }
                    
            case .permissionDenied:
                HomeAccessBlockerView(blockerState: .permissionDenied)
                
            case .noHomeConfigured:
                HomeAccessBlockerView(blockerState: .noHomeConfigured)
                
            case .noHomeHub:
                HomeAccessBlockerView(blockerState: .noHomeHub)
                
            case .noCompatibleAccessories:
                HomeAccessBlockerView(blockerState: .noCompatibleAccessories)
                
            case .ready:
                // Show setup surface for alarm creation
                AlarmSetupReadyView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: environment.homeAccessState.readiness)
    }
}

/// View shown when Home access is ready - offers next step toward alarm creation
struct AlarmSetupReadyView: View {
    @Environment(AppEnvironment.self) private var environment
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Theme.Spacing.xxxLarge) {
                    Spacer()
                    
                    // Success icon
                    ZStack {
                        ForEach(0..<3) { i in
                            Circle()
                                .fill(Theme.Gradients.warmGlow)
                                .opacity(0.1 - Double(i) * 0.03)
                                .frame(width: 160 + CGFloat(i * 40))
                                .blur(radius: 20)
                        }
                        
                        Circle()
                            .fill(Theme.Colors.surface)
                            .frame(width: 120, height: 120)
                            .shadow(
                                color: Theme.Colors.dawnPurple.opacity(0.3),
                                radius: 20,
                                x: 0,
                                y: 10
                            )
                        
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 50, weight: .medium))
                            .foregroundStyle(Theme.Gradients.successGradient)
                    }
                    
                    // Text content
                    VStack(spacing: Theme.Spacing.medium) {
                        Text("You're All Set")
                            .font(Theme.Typography.title1)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .multilineTextAlignment(.center)
                        
                        Text("Your Home is connected and ready. Let's set up your first wake-light alarm.")
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
                    title: "Create First Alarm",
                    action: {
                        environment.onboardingState.completeOnboarding()
                    }
                )
                
                Button("Review Compatible Lights") {
                    // In future, this would navigate to accessory review
                }
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(.horizontal, Theme.Spacing.large)
            .padding(.bottom, Theme.Spacing.xxLarge)
            .padding(.top, Theme.Spacing.large)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
    }
}

// MARK: - Theme Extensions

extension Theme.Gradients {
    static let successGradient = LinearGradient(
        colors: [
            Color(red: 0.4, green: 0.8, blue: 0.4),
            Color(red: 0.2, green: 0.6, blue: 0.3)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Preview

#Preview("Home Access Flow - Loading") {
    HomeAccessFlowView()
        .environment(AppEnvironment())
}

#Preview("Home Access Flow - Ready") {
    let env = AppEnvironment()
    // Note: Ready state with actual HomeKit types can only be tested on real device
    // Simulator preview shows the setup ready UI
    return AlarmSetupReadyView()
        .environment(env)
}

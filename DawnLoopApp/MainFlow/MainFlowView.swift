import SwiftUI

/// Main app flow shown after onboarding completion
struct MainFlowView: View {
    @Environment(AppEnvironment.self) private var environment
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                
                VStack(spacing: Theme.Spacing.xxxLarge) {
                    Spacer()
                    
                    // Welcome icon with sunrise gradient
                    ZStack {
                        // Glow effect
                        ForEach(0..<3) { i in
                            Circle()
                                .fill(Theme.Gradients.warmGlow)
                                .opacity(0.15 - Double(i) * 0.04)
                                .frame(width: 140 + CGFloat(i * 30))
                                .blur(radius: 15)
                        }
                        
                        Circle()
                            .fill(Theme.Colors.surface)
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Theme.Gradients.warmGlow)
                    }
                    
                    // Content
                    VStack(spacing: Theme.Spacing.medium) {
                        Text("Good Morning")
                            .font(Theme.Typography.title1)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        
                        Text("Your sunrise alarm setup begins here. Connect to Apple Home to create your first wake-light alarm.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, Theme.Spacing.xLarge)
                    }
                    
                    Spacer()
                    
                    // CTA
                    VStack(spacing: Theme.Spacing.medium) {
                        PrimaryButton(
                            title: "Connect to Apple Home",
                            action: {
                                // TODO: Navigate to Home access flow
                            }
                        )
                        
                        Button("Reset Onboarding (Debug)") {
                            environment.onboardingState.resetOnboarding()
                        }
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .padding(.top, Theme.Spacing.small)
                    }
                    .padding(.horizontal, Theme.Spacing.large)
                    .padding(.bottom, Theme.Spacing.xxLarge)
                }
            }
            .navigationTitle("DawnLoop")
            .navigationBarTitleDisplayMode(.large)
        }
        .tint(Theme.Colors.sunriseOrange)
    }
}

// MARK: - Preview

#Preview("Main Flow") {
    MainFlowView()
        .environment(AppEnvironment())
}

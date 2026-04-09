import SwiftUI

struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var environment
    
    var body: some View {
        Group {
            if environment.onboardingState.showingHomeAccessFlow {
                HomeAccessFlowView()
            } else {
                onboardingContent
            }
        }
    }
    
    private var onboardingContent: some View {
        VStack(spacing: 0) {
            // Progress indicator
            ProgressIndicator(
                currentStep: environment.onboardingState.currentScreen.rawValue + 1,
                totalSteps: OnboardingScreen.allCases.count
            )
            .padding(.top, Theme.Spacing.xLarge)
            .padding(.horizontal, Theme.Spacing.large)
            
            // Screen content
            TabView(selection: currentScreenBinding) {
                ForEach(OnboardingScreen.allCases, id: \.self) { screen in
                    OnboardingScreenView(screen: screen)
                        .tag(screen)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: environment.onboardingState.currentScreen)
            
            // Bottom action area
            VStack(spacing: Theme.Spacing.medium) {
                PrimaryButton(
                    title: environment.onboardingState.currentScreen.primaryAction,
                    action: advanceToNextScreen
                )
                
                if environment.onboardingState.currentScreen != .welcome {
                    Button("Back") {
                        goToPreviousScreen()
                    }
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .padding(.horizontal, Theme.Spacing.large)
            .padding(.bottom, Theme.Spacing.xxLarge)
            .padding(.top, Theme.Spacing.large)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
    }
    
    private var currentScreenBinding: Binding<OnboardingScreen> {
        Binding(
            get: { environment.onboardingState.currentScreen },
            set: { environment.onboardingState.currentScreen = $0 }
        )
    }
    
    private func advanceToNextScreen() {
        let currentIndex = environment.onboardingState.currentScreen.rawValue
        
        if currentIndex < OnboardingScreen.allCases.count - 1 {
            withAnimation(.easeInOut(duration: 0.3)) {
                environment.onboardingState.currentScreen = OnboardingScreen.allCases[currentIndex + 1]
            }
        } else {
            // Start Home access flow from final onboarding step
            environment.onboardingState.startHomeAccessFlow()
        }
    }
    
    private func goToPreviousScreen() {
        let currentIndex = environment.onboardingState.currentScreen.rawValue
        
        if currentIndex > 0 {
            withAnimation(.easeInOut(duration: 0.3)) {
                environment.onboardingState.currentScreen = OnboardingScreen.allCases[currentIndex - 1]
            }
        }
    }
}

// MARK: - Onboarding Screen Content

struct OnboardingScreenView: View {
    let screen: OnboardingScreen
    
    var body: some View {
        VStack(spacing: Theme.Spacing.xxxLarge) {
            Spacer()
            
            // Icon with animated glow
            ZStack {
                // Outer glow rings
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Theme.Gradients.warmGlow)
                        .opacity(0.1 - Double(i) * 0.03)
                        .frame(width: 160 + CGFloat(i * 40))
                        .blur(radius: 20)
                }
                
                // Icon background
                Circle()
                    .fill(Theme.Colors.surface)
                    .frame(width: 120, height: 120)
                    .shadow(
                        color: Theme.Colors.dawnPurple.opacity(0.3),
                        radius: 20,
                        x: 0,
                        y: 10
                    )
                
                // Icon
                Image(systemName: screen.iconName)
                    .font(.system(size: 50, weight: .medium))
                    .foregroundStyle(Theme.Gradients.warmGlow)
            }
            
            // Text content
            VStack(spacing: Theme.Spacing.medium) {
                Text(screen.title)
                    .font(Theme.Typography.title1)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                
                Text(screen.description)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Spacing.xLarge)
            
            Spacer()
            Spacer()
        }
    }
}

// MARK: - Progress Indicator

struct ProgressIndicator: View {
    let currentStep: Int
    let totalSteps: Int
    
    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index < currentStep ? Theme.Colors.sunriseOrange : Theme.Colors.surface)
                    .frame(width: index < currentStep ? 24 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
        }
    }
}

// MARK: - Primary Button

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Theme.Gradients.primaryButton)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Onboarding") {
    OnboardingView()
        .environment(AppEnvironment())
}

#Preview("Main Flow") {
    MainFlowView()
        .environment(AppEnvironment())
}

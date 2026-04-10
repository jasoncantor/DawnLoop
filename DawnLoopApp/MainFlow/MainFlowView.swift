import SwiftUI

/// Main app flow shown after onboarding completion
struct MainFlowView: View {
    var body: some View {
        NavigationStack {
            AlarmListView()
        }
        .tint(Theme.Colors.sunriseOrange)
    }
}

// MARK: - Preview

#Preview("Main Flow") {
    MainFlowView()
        .environment(AppEnvironment())
}

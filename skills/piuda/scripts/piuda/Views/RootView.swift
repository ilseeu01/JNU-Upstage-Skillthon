import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            if !state.isOnboarded {
                OnboardingView()
            } else {
                switch state.userProfile?.role {
                case .caregiver:
                    CaregiverTabView()
                case .elder:
                    ElderHomeView()
                case nil:
                    OnboardingView()
                }
            }
        }
        .animation(.easeInOut, value: state.isOnboarded)
    }
}

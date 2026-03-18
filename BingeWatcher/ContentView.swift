import SwiftUI

struct RootView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        Group {
            if container.repository.hasUnlockedRecommendations {
                MainTabView(repository: container.repository)
            } else {
                NavigationStack {
                    OnboardingView(viewModel: OnboardingViewModel(repository: container.repository))
                }
            }
        }
        .task {
            await container.repository.bootstrap()
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppContainer())
}

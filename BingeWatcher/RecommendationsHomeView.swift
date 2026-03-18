import SwiftUI

struct RecommendationsHomeView: View {
    @ObservedObject var repository: MovieRepository
    @State private var isRefreshing = false

    var body: some View {
        SwipeDeckView(repository: repository, isRefreshing: $isRefreshing)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(destination: TasteProfileView(repository: repository)) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.headline)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("CineMatch")
                        .font(.headline.weight(.semibold))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Button {
                            Task { await refreshDeck(force: true) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.headline)
                        }
                    }
                }
            }
            .task {
                await refreshDeck(force: false)
            }
    }

    private func refreshDeck(force: Bool) async {
        isRefreshing = true
        defer { isRefreshing = false }
        await repository.refreshRecommendationDeckIfNeeded(force: force)
    }
}

import SwiftUI

struct TasteProfileView: View {
    @ObservedObject var repository: MovieRepository

    private let decades = [1960, 1970, 1980, 1990, 2000, 2010, 2020]

    var body: some View {
        Form {
            Section("Filter overrides") {
                TextField("Mood keyword", text: $repository.filters.mood)

                Picker("Decade", selection: Binding(
                    get: { repository.filters.decade ?? 0 },
                    set: { repository.filters.decade = $0 == 0 ? nil : $0 }
                )) {
                    Text("Any decade").tag(0)
                    ForEach(decades, id: \.self) { decade in
                        Text("\(decade)s").tag(decade)
                    }
                }

                Picker("Runtime", selection: $repository.filters.runtime) {
                    ForEach(RuntimeFilter.allCases) { runtime in
                        Text(runtime.title).tag(runtime)
                    }
                }

                Button("Apply filters") {
                    Task { await repository.refreshRecommendationDeckIfNeeded(force: true) }
                }

                Button("Clear filters", role: .destructive) {
                    repository.filters = RecommendationFilters()
                    Task { await repository.refreshRecommendationDeckIfNeeded(force: true) }
                }
            }

            Section("Current taste snapshot") {
                Text("Onboarding ratings: \(repository.onboardingProgress.ratedCount)")
                Text("Watchlist saves: \(repository.watchlist.count)")
                Text("History events: \(repository.history.count)")
                Text("Deck size: \(repository.recommendationDeck.count)")
            }
        }
        .navigationTitle("Taste Profile")
    }
}

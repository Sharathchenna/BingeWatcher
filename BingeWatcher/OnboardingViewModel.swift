import Combine
import Foundation

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var searchResults: [TMDBMovieSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRatingMovieID: Int?
    @Published private(set) var successMessage: String?

    private var hiddenMovieIDs: Set<Int> = []

    let repository: MovieRepository

    init(repository: MovieRepository) {
        self.repository = repository
    }

    func loadBrowseFeedIfNeeded() async {
        await repository.bootstrap()
    }

    func performSearch() async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
            searchResults = []
            errorMessage = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            searchResults = try await repository.searchMovies(query: trimmedQuery)
            errorMessage = searchResults.isEmpty ? "No matches yet. Try another title." : nil
        } catch {
            errorMessage = error.localizedDescription
            searchResults = []
        }
    }

    func saveRating(_ rating: UserSentiment, for movie: TMDBMovieSummary) async {
        isRatingMovieID = movie.id
        defer { isRatingMovieID = nil }

        do {
            try await repository.saveRating(for: movie, rating: rating)
            errorMessage = nil
            successMessage = "Saved \(movie.title) as \(rating.title)."
            hiddenMovieIDs.insert(movie.id)
        } catch {
            errorMessage = error.localizedDescription
            successMessage = nil
        }
    }

    func dismissUnwatched(_ movie: TMDBMovieSummary) {
        hiddenMovieIDs.insert(movie.id)
        errorMessage = nil
        successMessage = "Removed \(movie.title) from onboarding picks."
    }

    func shouldShow(_ movie: TMDBMovieSummary) -> Bool {
        !hiddenMovieIDs.contains(movie.id)
    }
}

import Combine
import Foundation

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var query = ""
    @Published var selectedGenreID: Int? = nil
    @Published private(set) var searchResults: [TMDBMovieSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRatingMovieID: Int?
    @Published private(set) var successMessage: String?

    private var hiddenMovieIDs: Set<Int> = []

    let repository: MovieRepository

    static let genreChips: [(label: String, id: Int)] = [
        ("Action", 28),
        ("Comedy", 35),
        ("Drama", 18),
        ("Horror", 27),
        ("Sci-Fi", 878),
        ("Romance", 10749),
        ("Thriller", 53),
        ("Animation", 16),
        ("Documentary", 99)
    ]

    init(repository: MovieRepository) {
        self.repository = repository
    }

    func loadBrowseFeedIfNeeded() async {
        await repository.bootstrap()
    }

    func loadMoreBrowse() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        await repository.loadMoreBrowseMovies()
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

    var filteredBrowseMovies: [TMDBMovieSummary] {
        let base = repository.browseMovies.filter(shouldShow)
        guard let genreID = selectedGenreID else { return base }
        return base.filter { $0.genreIDs.contains(genreID) }
    }
}

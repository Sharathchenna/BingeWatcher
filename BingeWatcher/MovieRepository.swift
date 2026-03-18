import Combine
import CoreData
import Foundation

@MainActor
final class MovieRepository: ObservableObject {
    @Published private(set) var onboardingProgress = OnboardingProgress(ratedCount: 0, minimumRequired: 10)
    @Published private(set) var ratedMovies: [RatedMovie] = []
    @Published private(set) var browseMovies: [TMDBMovieSummary] = []
    @Published private(set) var recommendationDeck: [RecommendationCard] = []
    @Published private(set) var watchlist: [LibraryMovie] = []
    @Published private(set) var history: [LibraryMovie] = []
    @Published var filters = RecommendationFilters()

    private let coreDataStack: CoreDataStack
    private let client: TMDBClient
    private let collabLookup: CollabLookup
    private let featureVectorBuilder: FeatureVectorBuilder
    private let bandit: LinUCBBandit
    private let recommendationEngine: RecommendationEngine

    init(
        coreDataStack: CoreDataStack,
        client: TMDBClient,
        collabLookup: CollabLookup,
        featureVectorBuilder: FeatureVectorBuilder,
        bandit: LinUCBBandit,
        recommendationEngine: RecommendationEngine
    ) {
        self.coreDataStack = coreDataStack
        self.client = client
        self.collabLookup = collabLookup
        self.featureVectorBuilder = featureVectorBuilder
        self.bandit = bandit
        self.recommendationEngine = recommendationEngine
    }

    var hasUnlockedRecommendations: Bool {
        onboardingProgress.isUnlocked
    }

    func bootstrap() async {
        refreshOnboardingState()
        refreshLibraryCollections()

        guard browseMovies.isEmpty else {
            return
        }

        do {
            browseMovies = try await client.discoverMovies()
        } catch {
        }

        if hasUnlockedRecommendations {
            await refreshRecommendationDeckIfNeeded(force: true)
        }
    }

    func searchMovies(query: String) async throws -> [TMDBMovieSummary] {
        try await client.searchMovies(query: query)
    }

    func posterURL(for path: String?) -> URL? {
        client.posterURL(path: path)
    }

    func collaborativeNeighbors(for tmdbID: Int, limit: Int = 50) -> [NeighborCandidate] {
        collabLookup.nearestNeighbors(forTMDBID: tmdbID, limit: limit)
    }

    func saveRating(for summary: TMDBMovieSummary, rating: UserSentiment) async throws {
        let movie = try await fetchOrCreateMovie(for: summary)
        let request = UserRatingEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "movie.tmdbId == %lld", summary.id)

        let userRating = try coreDataStack.viewContext.fetch(request).first ?? UserRatingEntity(context: coreDataStack.viewContext)
        userRating.movie = movie
        userRating.rating = rating.rawValue
        userRating.timestamp = Date()

        try coreDataStack.saveIfNeeded()
        refreshOnboardingState()
        refreshLibraryCollections()

        if hasUnlockedRecommendations {
            await refreshRecommendationDeckIfNeeded(force: true)
        }
    }

    func refreshRecommendationDeckIfNeeded(force: Bool = false) async {
        guard hasUnlockedRecommendations else {
            recommendationDeck = []
            return
        }

        if !force, !recommendationDeck.isEmpty {
            return
        }

        let candidateSummaries = await fetchCandidatePool(limit: 200)
        let candidateMovies = await materializeCandidates(from: candidateSummaries).filter(matchesFilters(movie:))
        let ratings = fetchUserRatings()
        let recentHistory = fetchRecentSwipedMovies(limit: 3)
        let state = fetchBanditState()

        recommendationDeck = recommendationEngine.rankedDeck(
            candidates: candidateMovies,
            ratings: ratings,
            banditState: state,
            recentMovieHistory: recentHistory,
            limit: 20
        )
    }

    func toggleWatchlist(for recommendation: RecommendationCard) throws {
        guard let movie = try fetchMovie(tmdbId: recommendation.id) else { return }
        movie.isWatchlisted.toggle()
        try coreDataStack.saveIfNeeded()
        refreshLibraryCollections()
    }

    func isWatchlisted(_ recommendation: RecommendationCard) -> Bool {
        ((try? fetchMovie(tmdbId: recommendation.id)) ?? nil)?.isWatchlisted ?? false
    }

    func logSwipe(for recommendation: RecommendationCard, action: SwipeAction, timeOnCard: Float) throws {
        guard let movie = try fetchMovie(tmdbId: recommendation.id) else {
            return
        }

        let swipe = SwipeLogEntity(context: coreDataStack.viewContext)
        swipe.movie = movie
        swipe.action = action.rawValue
        swipe.timeOnCard = timeOnCard
        swipe.timestamp = Date()

        let vector = featureVectorBuilder.decode(movie.featureVec)
        let updatedBanditState = bandit.updatedState(from: fetchBanditState(), with: vector, reward: action.reward)
        persistBanditState(updatedBanditState)

        recommendationDeck.removeAll { $0.id == recommendation.id }
        try coreDataStack.saveIfNeeded()
        refreshLibraryCollections()

        let swipeCount = fetchSwipeCount()
        if swipeCount.isMultiple(of: 5) {
            Task {
                await refreshRecommendationDeckIfNeeded(force: true)
            }
        }
    }

    private func fetchOrCreateMovie(for summary: TMDBMovieSummary) async throws -> MovieEntity {
        if let existing = try fetchMovie(tmdbId: summary.id) {
            existing.title = summary.title
            existing.year = Int16(summary.releaseYear ?? 0)
            existing.popularity = Float(summary.popularity)
            existing.posterPath = existing.posterPath ?? summary.posterPath
            existing.overview = (existing.overview?.isEmpty == false) ? existing.overview : summary.overview

            if existing.overview == nil || existing.posterPath == nil || existing.runtime == 0 || existing.voteCount == 0 {
                do {
                    async let detail = client.movieDetails(id: summary.id)
                    async let keywords = client.movieKeywords(id: summary.id)
                    let detailValue = try await detail
                    let keywordsValue = try await keywords
                    apply(detailValue: detailValue, keywordsValue: keywordsValue, to: existing, fallbackSummary: summary)
                } catch {
                    applyFallback(summary: summary, to: existing)
                }
            }

            existing.featureVec = encodedFeatureVector(for: existing)
            try coreDataStack.saveIfNeeded()
            return existing
        }

        let movie = MovieEntity(context: coreDataStack.viewContext)
        movie.tmdbId = Int64(summary.id)
        applyFallback(summary: summary, to: movie)

        do {
            async let detail = client.movieDetails(id: summary.id)
            async let keywords = client.movieKeywords(id: summary.id)
            let detailValue = try await detail
            let keywordsValue = try await keywords
            apply(detailValue: detailValue, keywordsValue: keywordsValue, to: movie, fallbackSummary: summary)
        } catch {
            applyFallback(summary: summary, to: movie)
        }

        movie.featureVec = encodedFeatureVector(for: movie)

        try coreDataStack.saveIfNeeded()
        return movie
    }

    private func fetchMovie(tmdbId: Int) throws -> MovieEntity? {
        let request = MovieEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "tmdbId == %lld", tmdbId)
        return try coreDataStack.viewContext.fetch(request).first
    }

    private func apply(detailValue: TMDBMovieDetail, keywordsValue: [TMDBKeyword], to movie: MovieEntity, fallbackSummary: TMDBMovieSummary) {
        movie.title = detailValue.title
        movie.genres = detailValue.genres.map(\.name)
        movie.director = detailValue.credits?.crew.first(where: { $0.job == "Director" })?.name
        movie.cast = Array(detailValue.credits?.cast.prefix(5).map(\.name) ?? [])
        movie.overview = detailValue.overview
        movie.posterPath = detailValue.posterPath ?? fallbackSummary.posterPath
        movie.year = Int16(detailValue.releaseDate.flatMap { Int($0.prefix(4)) } ?? fallbackSummary.releaseYear ?? 0)
        movie.moodTags = keywordsValue.map(\.name)
        movie.popularity = Float(detailValue.popularity)
        movie.voteCount = Int32(detailValue.voteCount)
        movie.runtime = Int16(detailValue.runtime ?? 0)
    }

    private func applyFallback(summary: TMDBMovieSummary, to movie: MovieEntity) {
        movie.title = summary.title
        movie.posterPath = summary.posterPath
        movie.overview = summary.overview
        movie.year = Int16(summary.releaseYear ?? 0)
        movie.popularity = Float(summary.popularity)
        if movie.voteCount == 0 {
            movie.voteCount = Int32(summary.voteCount)
        }
    }

    private func encodedFeatureVector(for movie: MovieEntity) -> Data {
        featureVectorBuilder.encode(
            featureVectorBuilder.buildVector(
                for: MovieMetadata(
                    tmdbID: Int(movie.tmdbId),
                    genres: movie.genres,
                    director: movie.director,
                    cast: movie.cast,
                    year: Int(movie.year),
                    moodTags: movie.moodTags,
                    popularity: Double(movie.popularity),
                    voteCount: Int(movie.voteCount),
                    runtime: movie.runtime > 0 ? Int(movie.runtime) : nil,
                    affinity: currentAffinitySnapshot()
                )
            )
        )
    }

    private func fetchUserRatings() -> [UserRatingEntity] {
        let request = UserRatingEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        return (try? coreDataStack.viewContext.fetch(request)) ?? []
    }

    private func fetchSwipeCount() -> Int {
        let request = SwipeLogEntity.fetchRequest()
        return (try? coreDataStack.viewContext.count(for: request)) ?? 0
    }

    private func fetchRecentSwipedMovies(limit: Int) -> [MovieEntity] {
        let request = SwipeLogEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.fetchLimit = limit
        let swipes = (try? coreDataStack.viewContext.fetch(request)) ?? []
        return swipes.compactMap(\.movie)
    }

    private func fetchBanditState() -> LinUCBState {
        let request = BanditStateEntity.fetchRequest()
        request.fetchLimit = 1

        guard let stored = try? coreDataStack.viewContext.fetch(request).first else {
            return LinUCBState.initial(dimension: FeatureVectorBuilder.vectorLength)
        }

        return LinUCBState(
            aMatrix: bandit.decodeMatrix(stored.aMatrix),
            bVector: bandit.decodeVector(stored.bVector)
        )
    }

    private func persistBanditState(_ state: LinUCBState) {
        let request = BanditStateEntity.fetchRequest()
        request.fetchLimit = 1

        let stored = (try? coreDataStack.viewContext.fetch(request).first) ?? BanditStateEntity(context: coreDataStack.viewContext)
        stored.aMatrix = bandit.encodeMatrix(state.aMatrix)
        stored.bVector = bandit.encodeVector(state.bVector)
        stored.updatedAt = Date()
    }

    private func fetchCandidatePool(limit: Int) async -> [TMDBMovieSummary] {
        let seenIDs = Set(fetchUserRatings().compactMap { $0.movie.map { Int($0.tmdbId) } })
        var collected: [TMDBMovieSummary] = []
        var page = 1

        while collected.count < limit, page <= 10 {
            do {
                let pageResults = try await client.discoverMovies(page: page)
                let filtered = pageResults.filter { !seenIDs.contains($0.id) && matchesFilters(summary: $0) }
                collected.append(contentsOf: filtered)
                page += 1
            } catch {
                break
            }
        }

        var unique: [Int: TMDBMovieSummary] = [:]
        for movie in collected {
            unique[movie.id] = movie
        }
        return Array(unique.values.prefix(limit))
    }

    private func materializeCandidates(from summaries: [TMDBMovieSummary]) async -> [MovieEntity] {
        var movies: [MovieEntity] = []
        for summary in summaries {
            if let movie = try? await fetchOrCreateMovie(for: summary) {
                movies.append(movie)
            }
        }
        return movies
    }

    private func refreshOnboardingState() {
        let ratings = fetchUserRatings()
        ratedMovies = ratings.compactMap { rating in
            guard let movie = rating.movie, let sentiment = UserSentiment(rawValue: rating.rating) else {
                return nil
            }

            return RatedMovie(
                id: Int(movie.tmdbId),
                title: movie.title,
                year: movie.year > 0 ? Int(movie.year) : nil,
                posterPath: nil,
                rating: sentiment
            )
        }

        onboardingProgress = OnboardingProgress(ratedCount: ratings.count, minimumRequired: 10)
    }

    private func refreshLibraryCollections() {
        let movieRequest = MovieEntity.fetchRequest()
        movieRequest.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        let movies = (try? coreDataStack.viewContext.fetch(movieRequest)) ?? []

        watchlist = movies
            .filter(\.isWatchlisted)
            .map {
                LibraryMovie(
                    id: Int($0.tmdbId),
                    title: $0.title,
                    year: $0.year > 0 ? Int($0.year) : nil,
                    posterPath: $0.posterPath,
                    subtitle: $0.genres.prefix(2).joined(separator: " • "),
                    detail: $0.overview ?? "Saved to watchlist"
                )
            }

        let ratings = fetchUserRatings()
        let historySwipeRequest = SwipeLogEntity.fetchRequest()
        historySwipeRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        let swipes = (try? coreDataStack.viewContext.fetch(historySwipeRequest)) ?? []

        var historyItems: [LibraryMovie] = ratings.compactMap { rating in
            guard let movie = rating.movie, let sentiment = UserSentiment(rawValue: rating.rating) else { return nil }
            return LibraryMovie(
                id: Int(movie.tmdbId),
                title: movie.title,
                year: movie.year > 0 ? Int(movie.year) : nil,
                posterPath: movie.posterPath,
                subtitle: "Onboarding: \(sentiment.title)",
                detail: movie.overview ?? "Rated during onboarding"
            )
        }

        historyItems.append(contentsOf: swipes.compactMap { swipe in
            guard let movie = swipe.movie else { return nil }
            return LibraryMovie(
                id: Int(movie.tmdbId) * 10_000 + Int(swipe.timestamp.timeIntervalSince1970),
                title: movie.title,
                year: movie.year > 0 ? Int(movie.year) : nil,
                posterPath: movie.posterPath,
                subtitle: "Swipe: \(swipe.action.capitalized)",
                detail: movie.overview ?? "Interacted from recommendation deck"
            )
        })

        history = historyItems
    }

    private func matchesFilters(summary: TMDBMovieSummary) -> Bool {
        if let decade = filters.decade {
            guard let year = summary.releaseYear else { return false }
            if year < decade || year >= decade + 10 { return false }
        }

        if !filters.mood.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let search = filters.mood.lowercased()
            let haystack = "\(summary.title) \(summary.overview)".lowercased()
            if !haystack.contains(search) {
                return false
            }
        }

        return true
    }

    private func matchesFilters(movie: MovieEntity) -> Bool {
        if let decade = filters.decade {
            let year = Int(movie.year)
            if year < decade || year >= decade + 10 { return false }
        }

        switch filters.runtime {
        case .any:
            break
        case .short:
            if movie.runtime >= 90 || movie.runtime == 0 { return false }
        case .medium:
            if movie.runtime < 90 || movie.runtime >= 140 { return false }
        case .long:
            if movie.runtime < 140 { return false }
        }

        if !filters.mood.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let search = filters.mood.lowercased()
            let haystack = "\(movie.title) \(movie.overview ?? "") \(movie.moodTags.joined(separator: " "))".lowercased()
            if !haystack.contains(search) {
                return false
            }
        }

        return true
    }

    private func currentAffinitySnapshot() -> AffinitySnapshot {
        let request = UserRatingEntity.fetchRequest()
        let ratings = (try? coreDataStack.viewContext.fetch(request)) ?? []

        var directorWeights: [String: Float] = [:]
        var castWeights: [String: Float] = [:]

        for rating in ratings {
            guard let movie = rating.movie, let sentiment = UserSentiment(rawValue: rating.rating) else {
                continue
            }

            let weight = sentiment.affinityWeight
            if let director = movie.director, !director.isEmpty {
                directorWeights[director, default: 0] += weight
            }

            for castMember in movie.cast.prefix(5) {
                castWeights[castMember, default: 0] += weight * 0.5
            }
        }

        return AffinitySnapshot(directorWeights: directorWeights, castWeights: castWeights)
    }
}

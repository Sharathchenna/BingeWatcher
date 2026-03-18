import Foundation

struct RecommendationEngine {
    private let contentScorer: ContentScorer
    private let collabScorer: CollabScorer
    private let bandit: LinUCBBandit
    private let featureVectorBuilder: FeatureVectorBuilder

    init(
        contentScorer: ContentScorer,
        collabScorer: CollabScorer,
        bandit: LinUCBBandit,
        featureVectorBuilder: FeatureVectorBuilder
    ) {
        self.contentScorer = contentScorer
        self.collabScorer = collabScorer
        self.bandit = bandit
        self.featureVectorBuilder = featureVectorBuilder
    }

    func rankedDeck(
        candidates: [MovieEntity],
        ratings: [UserRatingEntity],
        banditState: LinUCBState,
        recentMovieHistory: [MovieEntity],
        limit: Int = 20
    ) -> [RecommendationCard] {
        let centroid = contentScorer.preferenceCentroid(from: ratings)
        let ratingsByMovieID: [Int: UserSentiment] = Dictionary(uniqueKeysWithValues: ratings.compactMap { rating in
            guard let movie = rating.movie, let sentiment = UserSentiment(rawValue: rating.rating) else {
                return nil
            }
            return (Int(movie.tmdbId), sentiment)
        })

        return candidates
            .map { movie in
                let vector = featureVectorBuilder.decode(movie.featureVec)
                let contentScore = contentScorer.score(candidate: vector, centroid: centroid)
                let collabScore = collabScorer.score(candidateTMDBID: Int(movie.tmdbId), ratingsByMovieID: ratingsByMovieID)
                let banditScore = bandit.score(candidate: vector, state: banditState)
                let diversityPenalty = self.diversityPenalty(for: movie, recentHistory: recentMovieHistory)
                let finalScore = (0.40 * collabScore) + (0.35 * contentScore) + (0.25 * banditScore) - diversityPenalty

                return RecommendationCard(
                    id: Int(movie.tmdbId),
                    title: movie.title,
                    year: movie.year > 0 ? Int(movie.year) : nil,
                    posterPath: movie.posterPath,
                    overview: movie.overview ?? "",
                    genres: movie.genres,
                    director: movie.director,
                    cast: movie.cast,
                    breakdown: RecommendationBreakdown(
                        contentScore: contentScore,
                        collabScore: collabScore,
                        banditScore: banditScore,
                        diversityPenalty: diversityPenalty,
                        finalScore: finalScore
                    ),
                    reason: recommendationReason(
                        for: movie,
                        contentScore: contentScore,
                        collabScore: collabScore,
                        banditScore: banditScore,
                        ratings: ratings
                    )
                )
            }
            .sorted { $0.breakdown.finalScore > $1.breakdown.finalScore }
            .prefix(limit)
            .map { $0 }
    }

    private func diversityPenalty(for movie: MovieEntity, recentHistory: [MovieEntity]) -> Float {
        let recentSlice = recentHistory.suffix(3)
        let sharedGenre = recentSlice.contains { !$0.genres.isDisjoint(with: movie.genres) }
        let sharedDirector = recentSlice.contains { $0.director == movie.director && movie.director != nil }
        return (sharedGenre || sharedDirector) ? 0.15 : 0
    }

    private func recommendationReason(
        for movie: MovieEntity,
        contentScore: Float,
        collabScore: Float,
        banditScore: Float,
        ratings: [UserRatingEntity]
    ) -> String {
        if collabScore >= contentScore, collabScore >= banditScore,
           let similar = ratings.compactMap({ $0.movie }).first(where: { ratedMovie in
               !Set(ratedMovie.genres).isDisjoint(with: movie.genres) || ratedMovie.director == movie.director
           }) {
            let genreHint = movie.genres.prefix(2).joined(separator: " and ").lowercased()
            return "Because you responded well to \(similar.title), similar viewers also cluster around this \(genreHint) pick."
        }

        if contentScore >= banditScore,
           let genre = movie.genres.first {
            let castHint = movie.cast.prefix(2).joined(separator: " and ")
            if let director = movie.director, !director.isEmpty {
                return "Because your ratings lean toward \(genre.lowercased()) stories and \(director)'s style, this one fits your profile\(castHint.isEmpty ? "" : " with \(castHint) in the mix")."
            }
            return "Because your ratings lean toward \(genre.lowercased()) stories\(castHint.isEmpty ? "" : " featuring \(castHint)"), this matches your current taste profile."
        }

        return "Because your recent swipes suggest curiosity around this blend of mood, cast, and momentum, the bandit is testing it as a high-upside pick."
    }
}

private extension Array where Element == String {
    func isDisjoint(with other: [String]) -> Bool {
        Set(self).isDisjoint(with: Set(other))
    }
}

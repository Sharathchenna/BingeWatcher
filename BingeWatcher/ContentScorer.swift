import Foundation

struct ContentScorer {
    private let featureVectorBuilder: FeatureVectorBuilder

    init(featureVectorBuilder: FeatureVectorBuilder) {
        self.featureVectorBuilder = featureVectorBuilder
    }

    func preferenceCentroid(from ratings: [UserRatingEntity]) -> [Float] {
        var centroid = Array(repeating: Float.zero, count: FeatureVectorBuilder.vectorLength)
        var totalWeight: Float = 0

        for rating in ratings {
            guard
                let movie = rating.movie,
                let sentiment = UserSentiment(rawValue: rating.rating)
            else {
                continue
            }

            let vector = featureVectorBuilder.decode(movie.featureVec)
            let weight = sentiment.affinityWeight
            totalWeight += abs(weight)

            for index in vector.indices {
                centroid[index] += vector[index] * weight
            }
        }

        guard totalWeight > 0 else {
            return centroid
        }

        return centroid.map { $0 / totalWeight }
    }

    func score(candidate: [Float], centroid: [Float]) -> Float {
        cosineSimilarity(lhs: candidate, rhs: centroid)
    }

    private func cosineSimilarity(lhs: [Float], rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else {
            return 0
        }

        var dot: Float = 0
        var lhsNorm: Float = 0
        var rhsNorm: Float = 0

        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            lhsNorm += lhs[index] * lhs[index]
            rhsNorm += rhs[index] * rhs[index]
        }

        let denominator = sqrt(lhsNorm) * sqrt(rhsNorm)
        guard denominator > 0 else {
            return 0
        }

        return dot / denominator
    }
}

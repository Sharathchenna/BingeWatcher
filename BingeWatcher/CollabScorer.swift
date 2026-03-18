import Foundation

struct CollabScorer {
    private let collabLookup: CollabLookup

    init(collabLookup: CollabLookup) {
        self.collabLookup = collabLookup
    }

    func score(candidateTMDBID: Int, ratingsByMovieID: [Int: UserSentiment]) -> Float {
        let neighbors = collabLookup.nearestNeighbors(forTMDBID: candidateTMDBID, limit: 50)

        var weightedTotal: Float = 0
        var similarityTotal: Float = 0

        for neighbor in neighbors {
            guard let sentiment = ratingsByMovieID[neighbor.neighborTMDBID] else {
                continue
            }

            let sentimentWeight: Float
            switch sentiment {
            case .loved:
                sentimentWeight = 1
            case .liked:
                sentimentWeight = 0.7
            case .meh:
                sentimentWeight = 0.2
            }

            weightedTotal += neighbor.similarity * sentimentWeight
            similarityTotal += neighbor.similarity
        }

        guard similarityTotal > 0 else {
            return 0
        }

        return weightedTotal / similarityTotal
    }
}

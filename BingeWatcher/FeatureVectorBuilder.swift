import Foundation

struct FeatureVectorBuilder {
    static let vectorLength = 100

    private let collabLookup: CollabLookup
    private let keywordModel: KeywordTFIDFModel
    private let genreIndex: [String: Int]
    private let decadeBuckets: [DecadeBucket]

    init(
        collabLookup: CollabLookup,
        keywordModel: KeywordTFIDFModel = .default,
        genreIndex: [String: Int] = Self.defaultGenreIndex,
        decadeBuckets: [DecadeBucket] = Self.defaultDecadeBuckets
    ) {
        self.collabLookup = collabLookup
        self.keywordModel = keywordModel
        self.genreIndex = genreIndex
        self.decadeBuckets = decadeBuckets
    }

    func buildVector(for movie: MovieMetadata) -> [Float] {
        var vector = Array(repeating: Float.zero, count: Self.vectorLength)

        encodeGenres(movie.genres, into: &vector)
        encodeDecade(year: movie.year, into: &vector)
        encodeAffinity(director: movie.director, cast: movie.cast, affinity: movie.affinity, into: &vector)
        encodeKeywords(movie.moodTags, into: &vector)
        vector[50] = normalizedLogValue(movie.popularity)
        vector[51] = normalizedLogValue(Double(movie.voteCount), scale: 1_000_000)
        vector[52] = runtimeBucketValue(for: movie.runtime)

        let factors = collabLookup.latentFactors(forTMDBID: movie.tmdbID)
        for (offset, factor) in factors.prefix(47).enumerated() {
            vector[53 + offset] = factor
        }

        return vector
    }

    func encode(_ vector: [Float]) -> Data {
        var mutableVector = vector
        return Data(bytes: &mutableVector, count: mutableVector.count * MemoryLayout<Float>.size)
    }

    func decode(_ data: Data?) -> [Float] {
        guard let data, !data.isEmpty else {
            return Array(repeating: .zero, count: Self.vectorLength)
        }

        let values = data.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Float.self))
        }

        if values.count == Self.vectorLength {
            return values
        }

        var padded = Array(repeating: Float.zero, count: Self.vectorLength)
        for (index, value) in values.prefix(Self.vectorLength).enumerated() {
            padded[index] = value
        }
        return padded
    }

    private func encodeGenres(_ genres: [String], into vector: inout [Float]) {
        for genre in genres {
            guard let index = genreIndex[genre] else {
                continue
            }
            vector[index] = 1
        }
    }

    private func encodeDecade(year: Int, into vector: inout [Float]) {
        guard let index = decadeBuckets.firstIndex(where: { $0.contains(year: year) }) else {
            return
        }
        vector[18 + index] = 1
    }

    private func encodeAffinity(director: String?, cast: [String], affinity: AffinitySnapshot, into vector: inout [Float]) {
        vector[24] = affinity.score(forDirector: director)

        for index in 0..<5 {
            let castMember = index < cast.count ? cast[index] : nil
            vector[25 + index] = affinity.score(forCastMember: castMember)
        }
    }

    private func encodeKeywords(_ keywords: [String], into vector: inout [Float]) {
        let embedding = keywordModel.encode(keywords: keywords)
        for (offset, value) in embedding.enumerated() {
            vector[30 + offset] = value
        }
    }

    private func normalizedLogValue(_ raw: Double, scale: Double = 10_000) -> Float {
        guard raw > 0 else {
            return 0
        }
        return Float(min(log1p(raw) / log1p(scale), 1))
    }

    private func runtimeBucketValue(for runtime: Int?) -> Float {
        guard let runtime else {
            return 0.5
        }

        switch runtime {
        case ..<90:
            return 0
        case 90..<140:
            return 0.5
        default:
            return 1
        }
    }

    private static let defaultGenreIndex: [String: Int] = [
        "Action": 0,
        "Adventure": 1,
        "Animation": 2,
        "Comedy": 3,
        "Crime": 4,
        "Documentary": 5,
        "Drama": 6,
        "Family": 7,
        "Fantasy": 8,
        "History": 9,
        "Horror": 10,
        "Music": 11,
        "Mystery": 12,
        "Romance": 13,
        "Science Fiction": 14,
        "TV Movie": 15,
        "Thriller": 16,
        "War": 17
    ]

    private static let defaultDecadeBuckets: [DecadeBucket] = [
        DecadeBucket(lowerBound: 1960, upperBound: 1969),
        DecadeBucket(lowerBound: 1970, upperBound: 1979),
        DecadeBucket(lowerBound: 1980, upperBound: 1989),
        DecadeBucket(lowerBound: 1990, upperBound: 1999),
        DecadeBucket(lowerBound: 2000, upperBound: 2009),
        DecadeBucket(lowerBound: 2010, upperBound: 2029)
    ]
}

struct MovieMetadata {
    let tmdbID: Int
    let genres: [String]
    let director: String?
    let cast: [String]
    let year: Int
    let moodTags: [String]
    let popularity: Double
    let voteCount: Int
    let runtime: Int?
    let affinity: AffinitySnapshot
}

struct AffinitySnapshot {
    let directorWeights: [String: Float]
    let castWeights: [String: Float]

    static let empty = AffinitySnapshot(directorWeights: [:], castWeights: [:])

    func score(forDirector director: String?) -> Float {
        guard let director else {
            return 0
        }
        return directorWeights[director, default: 0]
    }

    func score(forCastMember castMember: String?) -> Float {
        guard let castMember else {
            return 0
        }
        return castWeights[castMember, default: 0]
    }
}

struct DecadeBucket {
    let lowerBound: Int
    let upperBound: Int

    func contains(year: Int) -> Bool {
        lowerBound...upperBound ~= year
    }
}

struct KeywordTFIDFModel {
    let vocabulary: [String]
    let inverseDocumentFrequency: [String: Float]

    static let `default` = KeywordTFIDFModel(
        vocabulary: [
            "love", "friendship", "revenge", "murder", "alien", "space", "future", "dystopia", "family", "school",
            "war", "crime", "magic", "survival", "based on novel", "time travel", "police", "serial killer", "superhero", "heist"
        ],
        inverseDocumentFrequency: [
            "love": 1.1, "friendship": 1.2, "revenge": 1.4, "murder": 1.3, "alien": 1.7, "space": 1.6, "future": 1.5,
            "dystopia": 1.8, "family": 1.0, "school": 1.2, "war": 1.3, "crime": 1.1, "magic": 1.6, "survival": 1.5,
            "based on novel": 1.2, "time travel": 1.9, "police": 1.1, "serial killer": 1.8, "superhero": 1.7, "heist": 1.6
        ]
    )

    func encode(keywords: [String]) -> [Float] {
        let normalizedKeywords = keywords.map { $0.lowercased() }
        let totalCount = max(Float(normalizedKeywords.count), 1)

        return vocabulary.map { token in
            let matches = normalizedKeywords.filter { $0.contains(token) }.count
            let tf = Float(matches) / totalCount
            let idf = inverseDocumentFrequency[token, default: 1]
            return tf * idf
        }
    }
}

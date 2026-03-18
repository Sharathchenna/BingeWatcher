import Foundation

struct TMDBSearchResponse: Decodable {
    let page: Int
    let results: [TMDBMovieSummary]
}

struct TMDBDiscoverResponse: Decodable {
    let page: Int
    let results: [TMDBMovieSummary]
}

struct TMDBMovieSummary: Decodable, Identifiable, Equatable {
    let id: Int
    let title: String
    let overview: String
    let posterPath: String?
    let releaseDate: String?
    let genreIDs: [Int]
    let popularity: Double
    let voteCount: Int

    var releaseYear: Int? {
        guard let releaseDate else {
            return nil
        }

        return Int(releaseDate.prefix(4))
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case overview
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case genreIDs = "genre_ids"
        case popularity
        case voteCount = "vote_count"
    }
}

struct TMDBMovieDetail: Decodable {
    let id: Int
    let title: String
    let overview: String
    let posterPath: String?
    let releaseDate: String?
    let runtime: Int?
    let genres: [TMDBGenre]
    let popularity: Double
    let voteCount: Int
    let credits: TMDBCredits?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case overview
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case runtime
        case genres
        case popularity
        case voteCount = "vote_count"
        case credits
    }
}

struct TMDBGenre: Decodable, Equatable {
    let id: Int
    let name: String
}

struct TMDBCredits: Decodable {
    let cast: [TMDBCastMember]
    let crew: [TMDBCrewMember]
}

struct TMDBCastMember: Decodable {
    let name: String
}

struct TMDBCrewMember: Decodable {
    let job: String
    let name: String
}

struct TMDBKeywordsResponse: Decodable {
    let keywords: [TMDBKeyword]
}

struct TMDBKeyword: Decodable {
    let id: Int
    let name: String
}

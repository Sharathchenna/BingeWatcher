import Foundation

struct TMDBClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let baseURL = URL(string: "https://api.themoviedb.org/3")!
    private let imageBaseURL = URL(string: "https://image.tmdb.org/t/p/w500")!

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    func searchMovies(query: String, page: Int = 1) async throws -> [TMDBMovieSummary] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let response: TMDBSearchResponse = try await request(
            path: "search/movie",
            queryItems: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "include_adult", value: "false"),
                URLQueryItem(name: "language", value: "en-US")
            ]
        )
        return response.results
    }

    func discoverMovies(page: Int = 1, genreID: Int? = nil) async throws -> [TMDBMovieSummary] {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "include_video", value: "false"),
            URLQueryItem(name: "language", value: "en-US"),
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "with_original_language", value: "en")
        ]
        if let genreID {
            queryItems.append(URLQueryItem(name: "with_genres", value: String(genreID)))
        }
        let response: TMDBDiscoverResponse = try await request(path: "discover/movie", queryItems: queryItems)
        return response.results
    }

    func movieDetails(id: Int) async throws -> TMDBMovieDetail {
        try await request(
            path: "movie/\(id)",
            queryItems: [
                URLQueryItem(name: "append_to_response", value: "credits"),
                URLQueryItem(name: "language", value: "en-US")
            ]
        )
    }

    func movieKeywords(id: Int) async throws -> [TMDBKeyword] {
        let response: TMDBKeywordsResponse = try await request(path: "movie/\(id)/keywords")
        return response.keywords
    }

    func posterURL(path: String?) -> URL? {
        guard let path else {
            return nil
        }

        return imageBaseURL.appendingPathComponent(path)
    }

    private func request<T: Decodable>(path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        guard let apiKey = TMDBConfig.apiKey else {
            throw TMDBConfigError.missingAPIKey
        }

        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "api_key", value: apiKey)] + queryItems

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        return try decoder.decode(T.self, from: data)
    }
}

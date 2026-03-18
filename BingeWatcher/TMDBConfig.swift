import Foundation

enum TMDBConfigError: LocalizedError {
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your TMDB API key to Config/Local.xcconfig before using live movie data."
        }
    }
}

enum TMDBConfig {
    static var apiKey: String? {
        let rawValue = Bundle.main.object(forInfoDictionaryKey: "TMDBAPIKey") as? String
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }
}

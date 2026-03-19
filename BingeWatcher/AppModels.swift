import Foundation

enum UserSentiment: String, CaseIterable, Identifiable {
    case loved
    case liked
    case meh

    var id: String { rawValue }

    var title: String {
        switch self {
        case .loved:
            return "Loved"
        case .liked:
            return "Liked"
        case .meh:
            return "Meh"
        }
    }

    var affinityWeight: Float {
        switch self {
        case .loved:
            return 1
        case .liked:
            return 0.6
        case .meh:
            return -0.2
        }
    }
}

struct RatedMovie: Identifiable, Equatable {
    let id: Int
    let title: String
    let year: Int?
    let posterPath: String?
    let rating: UserSentiment
}

struct OnboardingProgress {
    let ratedCount: Int
    let minimumRequired: Int

    var remainingCount: Int {
        max(minimumRequired - ratedCount, 0)
    }

    var isUnlocked: Bool {
        ratedCount >= minimumRequired
    }

    var fractionComplete: Double {
        guard minimumRequired > 0 else {
            return 1
        }

        return min(Double(ratedCount) / Double(minimumRequired), 1)
    }
}

enum SwipeAction: String, CaseIterable, Identifiable {
    case like
    case dislike
    case skip

    var id: String { rawValue }

    var reward: Float {
        switch self {
        case .like:
            return 1
        case .dislike:
            return -0.5
        case .skip:
            return 0
        }
    }
}

struct RecommendationBreakdown: Equatable {
    let contentScore: Float
    let collabScore: Float
    let banditScore: Float
    let diversityPenalty: Float
    let finalScore: Float
}

struct RecommendationCard: Identifiable, Equatable {
    let id: Int
    let title: String
    let year: Int?
    let posterPath: String?
    let overview: String
    let genres: [String]
    let director: String?
    let cast: [String]
    let breakdown: RecommendationBreakdown
    let reason: String
}

enum RuntimeFilter: String, CaseIterable, Identifiable {
    case any
    case short
    case medium
    case long

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "Any runtime"
        case .short: return "Under 90m"
        case .medium: return "90-139m"
        case .long: return "140m+"
        }
    }
}

struct RecommendationFilters: Equatable {
    var mood: String = ""
    var decade: Int?
    var runtime: RuntimeFilter = .any
}

struct LibraryMovie: Identifiable, Equatable {
    let id: Int
    let tmdbId: Int
    let title: String
    let year: Int?
    let posterPath: String?
    let subtitle: String
    let detail: String
}

struct TasteSnapshot {
    struct Item: Identifiable {
        let id: String
        let label: String
        let weight: Float
    }

    struct DecadeEntry: Identifiable {
        let id: Int
        let decade: Int
        let count: Int
    }

    let topGenres: [Item]
    let topDirectors: [Item]
    let topCast: [Item]
    let decades: [DecadeEntry]

    static let empty = TasteSnapshot(topGenres: [], topDirectors: [], topCast: [], decades: [])
}

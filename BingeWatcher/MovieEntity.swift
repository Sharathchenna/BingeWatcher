import CoreData
import Foundation

@objc(MovieEntity)
final class MovieEntity: NSManagedObject {
    @NSManaged var tmdbId: Int64
    @NSManaged var title: String
    @NSManaged var genresRaw: String?
    @NSManaged var director: String?
    @NSManaged var castRaw: String?
    @NSManaged var overview: String?
    @NSManaged var posterPath: String?
    @NSManaged var year: Int16
    @NSManaged var moodTagsRaw: String?
    @NSManaged var popularity: Float
    @NSManaged var voteCount: Int32
    @NSManaged var runtime: Int16
    @NSManaged var isWatchlisted: Bool
    @NSManaged var featureVec: Data?
    @NSManaged var ratings: Set<UserRatingEntity>?
    @NSManaged var swipes: Set<SwipeLogEntity>?

    var genres: [String] {
        get { Self.decodeList(genresRaw) }
        set { genresRaw = Self.encodeList(newValue) }
    }

    var cast: [String] {
        get { Self.decodeList(castRaw) }
        set { castRaw = Self.encodeList(newValue) }
    }

    var moodTags: [String] {
        get { Self.decodeList(moodTagsRaw) }
        set { moodTagsRaw = Self.encodeList(newValue) }
    }

    private static func encodeList(_ values: [String]) -> String {
        values.joined(separator: "|")
    }

    private static func decodeList(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else {
            return []
        }

        return raw
            .split(separator: "|")
            .map(String.init)
    }
}

extension MovieEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<MovieEntity> {
        NSFetchRequest<MovieEntity>(entityName: "MovieEntity")
    }
}

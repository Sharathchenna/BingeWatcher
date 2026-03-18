import CoreData
import Foundation

@objc(UserRatingEntity)
final class UserRatingEntity: NSManagedObject {
    @NSManaged var rating: String
    @NSManaged var timestamp: Date
    @NSManaged var movie: MovieEntity?
}

extension UserRatingEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<UserRatingEntity> {
        NSFetchRequest<UserRatingEntity>(entityName: "UserRatingEntity")
    }
}

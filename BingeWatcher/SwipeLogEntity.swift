import CoreData
import Foundation

@objc(SwipeLogEntity)
final class SwipeLogEntity: NSManagedObject {
    @NSManaged var action: String
    @NSManaged var timeOnCard: Float
    @NSManaged var timestamp: Date
    @NSManaged var movie: MovieEntity?
}

extension SwipeLogEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<SwipeLogEntity> {
        NSFetchRequest<SwipeLogEntity>(entityName: "SwipeLogEntity")
    }
}

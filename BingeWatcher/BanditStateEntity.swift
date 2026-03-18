import CoreData
import Foundation

@objc(BanditStateEntity)
final class BanditStateEntity: NSManagedObject {
    @NSManaged var aMatrix: Data?
    @NSManaged var bVector: Data?
    @NSManaged var updatedAt: Date
}

extension BanditStateEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<BanditStateEntity> {
        NSFetchRequest<BanditStateEntity>(entityName: "BanditStateEntity")
    }
}

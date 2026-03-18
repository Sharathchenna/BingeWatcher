import CoreData
import Foundation

final class CoreDataStack {
    let container: NSPersistentContainer

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    init(inMemory: Bool = false) {
        let model = Self.makeManagedObjectModel()
        container = NSPersistentContainer(name: "BingeWatcher", managedObjectModel: model)

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Failed to load persistent stores: \(error.localizedDescription)")
            }
        }

        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.undoManager = nil
    }

    func saveIfNeeded() throws {
        guard viewContext.hasChanges else {
            return
        }

        try viewContext.save()
    }

    private static func makeManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let movieEntity = NSEntityDescription()
        movieEntity.name = "MovieEntity"
        movieEntity.managedObjectClassName = NSStringFromClass(MovieEntity.self)

        let tmdbId = attribute(name: "tmdbId", type: .integer64AttributeType)
        tmdbId.isOptional = false
        let title = attribute(name: "title", type: .stringAttributeType)
        title.isOptional = false
        let genresRaw = attribute(name: "genresRaw", type: .stringAttributeType)
        let director = attribute(name: "director", type: .stringAttributeType)
        let castRaw = attribute(name: "castRaw", type: .stringAttributeType)
        let overview = attribute(name: "overview", type: .stringAttributeType)
        let posterPath = attribute(name: "posterPath", type: .stringAttributeType)
        let year = attribute(name: "year", type: .integer16AttributeType)
        let moodTagsRaw = attribute(name: "moodTagsRaw", type: .stringAttributeType)
        let popularity = attribute(name: "popularity", type: .floatAttributeType)
        popularity.defaultValue = 0
        let voteCount = attribute(name: "voteCount", type: .integer32AttributeType)
        voteCount.defaultValue = 0
        let runtime = attribute(name: "runtime", type: .integer16AttributeType)
        let isWatchlisted = attribute(name: "isWatchlisted", type: .booleanAttributeType)
        isWatchlisted.defaultValue = false
        let featureVec = attribute(name: "featureVec", type: .binaryDataAttributeType)
        featureVec.allowsExternalBinaryDataStorage = true
        movieEntity.properties = [tmdbId, title, genresRaw, director, castRaw, overview, posterPath, year, moodTagsRaw, popularity, voteCount, runtime, isWatchlisted, featureVec]
        movieEntity.uniquenessConstraints = [["tmdbId"]]

        let userRatingEntity = NSEntityDescription()
        userRatingEntity.name = "UserRatingEntity"
        userRatingEntity.managedObjectClassName = NSStringFromClass(UserRatingEntity.self)
        let rating = attribute(name: "rating", type: .stringAttributeType)
        rating.isOptional = false
        let ratingTimestamp = attribute(name: "timestamp", type: .dateAttributeType)
        ratingTimestamp.isOptional = false
        userRatingEntity.properties = [rating, ratingTimestamp]

        let swipeLogEntity = NSEntityDescription()
        swipeLogEntity.name = "SwipeLogEntity"
        swipeLogEntity.managedObjectClassName = NSStringFromClass(SwipeLogEntity.self)
        let action = attribute(name: "action", type: .stringAttributeType)
        action.isOptional = false
        let timeOnCard = attribute(name: "timeOnCard", type: .floatAttributeType)
        timeOnCard.defaultValue = 0
        let swipeTimestamp = attribute(name: "timestamp", type: .dateAttributeType)
        swipeTimestamp.isOptional = false
        swipeLogEntity.properties = [action, timeOnCard, swipeTimestamp]

        let banditStateEntity = NSEntityDescription()
        banditStateEntity.name = "BanditStateEntity"
        banditStateEntity.managedObjectClassName = NSStringFromClass(BanditStateEntity.self)
        let aMatrix = attribute(name: "aMatrix", type: .binaryDataAttributeType)
        aMatrix.allowsExternalBinaryDataStorage = true
        let bVector = attribute(name: "bVector", type: .binaryDataAttributeType)
        bVector.allowsExternalBinaryDataStorage = true
        let updatedAt = attribute(name: "updatedAt", type: .dateAttributeType)
        updatedAt.isOptional = false
        banditStateEntity.properties = [aMatrix, bVector, updatedAt]

        let movieToRatings = relationship(name: "ratings", destination: userRatingEntity, toMany: true, deleteRule: .cascadeDeleteRule)
        let ratingToMovie = relationship(name: "movie", destination: movieEntity, toMany: false, deleteRule: .nullifyDeleteRule)
        movieToRatings.inverseRelationship = ratingToMovie
        ratingToMovie.inverseRelationship = movieToRatings

        let movieToSwipes = relationship(name: "swipes", destination: swipeLogEntity, toMany: true, deleteRule: .cascadeDeleteRule)
        let swipeToMovie = relationship(name: "movie", destination: movieEntity, toMany: false, deleteRule: .nullifyDeleteRule)
        movieToSwipes.inverseRelationship = swipeToMovie
        swipeToMovie.inverseRelationship = movieToSwipes

        movieEntity.properties.append(contentsOf: [movieToRatings, movieToSwipes])
        userRatingEntity.properties.append(ratingToMovie)
        swipeLogEntity.properties.append(swipeToMovie)

        model.entities = [movieEntity, userRatingEntity, swipeLogEntity, banditStateEntity]
        return model
    }

    private static func attribute(name: String, type: NSAttributeType) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = true
        return attribute
    }

    private static func relationship(name: String, destination: NSEntityDescription, toMany: Bool, deleteRule: NSDeleteRule) -> NSRelationshipDescription {
        let relationship = NSRelationshipDescription()
        relationship.name = name
        relationship.destinationEntity = destination
        relationship.minCount = 0
        relationship.maxCount = toMany ? 0 : 1
        relationship.isOptional = true
        relationship.isOrdered = false
        relationship.deleteRule = deleteRule
        return relationship
    }
}

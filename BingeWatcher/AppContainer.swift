import Combine
import Foundation

@MainActor
final class AppContainer: ObservableObject {
    let coreDataStack: CoreDataStack
    let repository: MovieRepository
    let collabLookup: CollabLookup
    let featureVectorBuilder: FeatureVectorBuilder
    let recommendationEngine: RecommendationEngine
    let bandit: LinUCBBandit
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let stack = CoreDataStack()
        let collabLookup = CollabLookup()
        let featureVectorBuilder = FeatureVectorBuilder(collabLookup: collabLookup)
        let bandit = LinUCBBandit()
        let recommendationEngine = RecommendationEngine(
            contentScorer: ContentScorer(featureVectorBuilder: featureVectorBuilder),
            collabScorer: CollabScorer(collabLookup: collabLookup),
            bandit: bandit,
            featureVectorBuilder: featureVectorBuilder
        )
        self.coreDataStack = stack
        self.collabLookup = collabLookup
        self.featureVectorBuilder = featureVectorBuilder
        self.bandit = bandit
        self.recommendationEngine = recommendationEngine
        self.repository = MovieRepository(
            coreDataStack: stack,
            client: TMDBClient(),
            collabLookup: collabLookup,
            featureVectorBuilder: featureVectorBuilder,
            bandit: bandit,
            recommendationEngine: recommendationEngine
        )

        repository.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}

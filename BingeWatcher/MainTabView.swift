import SwiftUI

struct MainTabView: View {
    @ObservedObject var repository: MovieRepository

    var body: some View {
        TabView {
            NavigationStack {
                RecommendationsHomeView(repository: repository)
            }
            .tabItem {
                Label("Deck", systemImage: "rectangle.stack.fill")
            }

            NavigationStack {
                WatchlistView(repository: repository)
            }
            .tabItem {
                Label("Library", systemImage: "bookmark.fill")
            }

            NavigationStack {
                TasteProfileView(repository: repository)
            }
            .tabItem {
                Label("Taste", systemImage: "slider.horizontal.3")
            }
        }
    }
}

import SwiftUI

struct WatchlistView: View {
    @ObservedObject var repository: MovieRepository

    var body: some View {
        List {
            Section("Watchlist") {
                if repository.watchlist.isEmpty {
                    Text("Save movies from the deck to build your watchlist.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(repository.watchlist) { movie in
                        libraryRow(movie, allowRerate: false)
                    }
                }
            }

            Section("History") {
                if repository.history.isEmpty {
                    Text("Your onboarding ratings and deck swipes will show up here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(repository.history) { movie in
                        libraryRow(movie, allowRerate: true)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                rerateButtons(for: movie)
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Library")
    }

    // MARK: - Row

    private func libraryRow(_ movie: LibraryMovie, allowRerate: Bool) -> some View {
        HStack(spacing: 12) {
            posterThumbnail(for: movie)

            VStack(alignment: .leading, spacing: 4) {
                Text(movie.title)
                    .font(.headline)
                Text(movie.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(movie.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func rerateButtons(for movie: LibraryMovie) -> some View {
        Button {
            try? repository.rerateMovie(tmdbId: movie.tmdbId, rating: .loved)
        } label: {
            Label("Loved", systemImage: "heart.fill")
        }
        .tint(.red)

        Button {
            try? repository.rerateMovie(tmdbId: movie.tmdbId, rating: .liked)
        } label: {
            Label("Liked", systemImage: "hand.thumbsup.fill")
        }
        .tint(.orange)

        Button {
            try? repository.rerateMovie(tmdbId: movie.tmdbId, rating: .meh)
        } label: {
            Label("Meh", systemImage: "hand.thumbsdown")
        }
        .tint(.gray)
    }

    // MARK: - Poster thumbnail

    private func posterThumbnail(for movie: LibraryMovie) -> some View {
        let url = repository.posterURL(for: movie.posterPath)
        return PosterBackdrop(url: url)
            .scaledToFill()
            .frame(width: 48, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

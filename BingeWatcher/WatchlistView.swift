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
                        libraryRow(movie)
                    }
                }
            }

            Section("History") {
                if repository.history.isEmpty {
                    Text("Your onboarding ratings and deck swipes will show up here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(repository.history) { movie in
                        libraryRow(movie)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Library")
    }

    private func libraryRow(_ movie: LibraryMovie) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
                .frame(width: 48, height: 72)
                .overlay(Image(systemName: "film"))

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
}

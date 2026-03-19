import SwiftUI

struct OnboardingView: View {
    @StateObject private var viewModel: OnboardingViewModel

    init(viewModel: OnboardingViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                searchSection
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if let successMessage = viewModel.successMessage {
                    Text(successMessage)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
                ratedSection
                browseSection
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("CineMatch")
        .task {
            await viewModel.loadBrowseFeedIfNeeded()
        }
        .task(id: viewModel.query) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await viewModel.performSearch()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Teach CineMatch your taste")
                .font(.largeTitle.bold())
            Text("Rate 10 movies you have already seen. We will use those picks to unlock your first recommendation deck.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: viewModel.repository.onboardingProgress.fractionComplete)
                    .tint(.red)
                Text(progressText)
                    .font(.headline)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }

    // MARK: - Search

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search watched movies")
                .font(.title3.weight(.semibold))

            TextField("Search for a title", text: $viewModel.query)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }

            ForEach(viewModel.searchResults.filter(viewModel.shouldShow)) { movie in
                MovieRow(movie: movie, ratingInFlight: viewModel.isRatingMovieID == movie.id, onDismiss: {
                    viewModel.dismissUnwatched(movie)
                }) { rating in
                    await viewModel.saveRating(rating, for: movie)
                }
            }
        }
    }

    // MARK: - Rated movies

    private var ratedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your onboarding picks")
                .font(.title3.weight(.semibold))

            if viewModel.repository.ratedMovies.isEmpty {
                Text("No ratings yet. Start with a few favorites, guilty pleasures, and one or two films you were lukewarm on.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.repository.ratedMovies) { movie in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(movie.title)
                                .font(.headline)
                            if let year = movie.year {
                                Text(String(year))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Text(movie.rating.title)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(.tertiarySystemBackground), in: Capsule())
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
            }
        }
    }

    // MARK: - Browse

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse popular movies")
                .font(.title3.weight(.semibold))

            genreChips

            if viewModel.repository.browseMovies.isEmpty {
                Text("Add your TMDB key to load live browse results.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.filteredBrowseMovies) { movie in
                    MovieRow(movie: movie, ratingInFlight: viewModel.isRatingMovieID == movie.id, onDismiss: {
                        viewModel.dismissUnwatched(movie)
                    }) { rating in
                        await viewModel.saveRating(rating, for: movie)
                    }
                }

                Button {
                    Task { await viewModel.loadMoreBrowse() }
                } label: {
                    HStack {
                        if viewModel.isLoadingMore {
                            ProgressView()
                        } else {
                            Label("Load more", systemImage: "arrow.down.circle")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isLoadingMore)
            }
        }
    }

    private var genreChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                genreChip(label: "All", genreID: nil)
                ForEach(OnboardingViewModel.genreChips, id: \.id) { chip in
                    genreChip(label: chip.label, genreID: chip.id)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func genreChip(label: String, genreID: Int?) -> some View {
        let selected = viewModel.selectedGenreID == genreID
        return Button {
            viewModel.selectedGenreID = genreID
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? Color.red : Color(.secondarySystemBackground), in: Capsule())
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Progress text

    private var progressText: String {
        let progress = viewModel.repository.onboardingProgress
        if progress.isUnlocked {
            return "Deck unlocked! Head back to start swiping."
        }
        return "\(progress.ratedCount) of \(progress.minimumRequired) rated — \(progress.remainingCount) to go"
    }
}

// MARK: - Movie row

private struct MovieRow: View {
    let movie: TMDBMovieSummary
    let ratingInFlight: Bool
    let onDismiss: () -> Void
    let onRate: (UserSentiment) async -> Void

    @StateObject private var imageLoader = PosterImageLoader.shared

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            poster

            VStack(alignment: .leading, spacing: 8) {
                Text(movie.title)
                    .font(.headline)
                if let year = movie.releaseYear {
                    Text(String(year))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !movie.overview.isEmpty {
                    Text(movie.overview)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                HStack(spacing: 8) {
                    ForEach(UserSentiment.allCases) { sentiment in
                        Button(sentiment.title) {
                            Task { await onRate(sentiment) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(tint(for: sentiment))
                        .disabled(ratingInFlight)
                    }
                }

                Button("Didn't watch this") {
                    onDismiss()
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .disabled(ratingInFlight)
            }

            if ratingInFlight {
                ProgressView()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .task {
            await imageLoader.load(from: TMDBClient().posterURL(path: movie.posterPath))
        }
    }

    private var poster: some View {
        let url = TMDBClient().posterURL(path: movie.posterPath)

        return Group {
            if let image = imageLoader.image(for: url) {
                posterImage(image)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.tertiarySystemBackground))
                    .overlay(Image(systemName: "film"))
            }
        }
        .frame(width: 72, height: 108)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func posterImage(_ image: PlatformImage) -> some View {
#if canImport(UIKit)
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
#elseif canImport(AppKit)
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
#endif
    }

    private func tint(for sentiment: UserSentiment) -> Color {
        switch sentiment {
        case .loved: return .red
        case .liked: return .orange
        case .meh: return .gray
        }
    }
}

struct RecommendationUnlockedView: View {
    let progress: OnboardingProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Deck unlocked")
                .font(.largeTitle.bold())
            Text("You rated \(progress.ratedCount) movies. Your recommendation deck is ready — tap the Deck tab to start swiping.")
                .foregroundStyle(.secondary)
            Label("Onboarding complete", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .background(Color(.systemGroupedBackground))
    }
}

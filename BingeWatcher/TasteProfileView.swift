import SwiftUI

struct TasteProfileView: View {
    @ObservedObject var repository: MovieRepository

    private let filterDecades = [1960, 1970, 1980, 1990, 2000, 2010, 2020]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                statsRow

                if !repository.tasteSnapshot.topGenres.isEmpty {
                    genreSection
                }

                if !repository.tasteSnapshot.decades.isEmpty {
                    decadeSection
                }

                if !repository.tasteSnapshot.topDirectors.isEmpty || !repository.tasteSnapshot.topCast.isEmpty {
                    affinitySection
                }

                filterSection
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Taste Profile")
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCard(value: "\(repository.onboardingProgress.ratedCount)", label: "Rated")
            statCard(value: "\(repository.watchlist.count)", label: "Saved")
            statCard(value: "\(repository.recommendationDeck.count)", label: "In deck")
        }
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Genre section

    private var genreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Top Genres", symbol: "film")
            let maxWeight = repository.tasteSnapshot.topGenres.map(\.weight).max() ?? 1
            VStack(spacing: 10) {
                ForEach(repository.tasteSnapshot.topGenres) { item in
                    HStack(spacing: 12) {
                        Text(item.label)
                            .font(.subheadline)
                            .frame(width: 110, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color(.systemFill))
                                    .frame(height: 8)
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.red.gradient)
                                    .frame(width: geo.size.width * CGFloat(item.weight / maxWeight), height: 8)
                                    .animation(.easeOut(duration: 0.5), value: item.weight)
                            }
                        }
                        .frame(height: 8)
                    }
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Decade section

    private var decadeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Decades", symbol: "calendar")
            let maxCount = repository.tasteSnapshot.decades.map(\.count).max() ?? 1
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(repository.tasteSnapshot.decades) { entry in
                    VStack(spacing: 4) {
                        Text("\(entry.count)")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.orange.gradient)
                            .frame(width: 36, height: max(8, 60 * CGFloat(entry.count) / CGFloat(maxCount)))
                            .animation(.easeOut(duration: 0.5), value: entry.count)
                        Text("\(entry.decade)s")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .cardStyle()
    }

    // MARK: - Affinity section

    private var affinitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("People you like", symbol: "person.2")

            if !repository.tasteSnapshot.topDirectors.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Directors")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    FlowTagRow(items: repository.tasteSnapshot.topDirectors.map(\.label), color: .blue)
                }
            }

            if !repository.tasteSnapshot.topCast.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cast")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    FlowTagRow(items: repository.tasteSnapshot.topCast.map(\.label), color: .purple)
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Filter section

    private var filterSection: some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                TextField("Mood keyword", text: $repository.filters.mood)
                    .padding(.top, 12)

                Divider().padding(.vertical, 8)

                Picker("Decade", selection: Binding(
                    get: { repository.filters.decade ?? 0 },
                    set: { repository.filters.decade = $0 == 0 ? nil : $0 }
                )) {
                    Text("Any decade").tag(0)
                    ForEach(filterDecades, id: \.self) { decade in
                        Text("\(decade)s").tag(decade)
                    }
                }

                Divider().padding(.vertical, 8)

                Picker("Runtime", selection: $repository.filters.runtime) {
                    ForEach(RuntimeFilter.allCases) { runtime in
                        Text(runtime.title).tag(runtime)
                    }
                }

                Divider().padding(.vertical, 8)

                HStack(spacing: 12) {
                    Button("Apply") {
                        Task { await repository.refreshRecommendationDeckIfNeeded(force: true) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)

                    Button("Clear", role: .destructive) {
                        repository.filters = RecommendationFilters()
                        Task { await repository.refreshRecommendationDeckIfNeeded(force: true) }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
        } label: {
            Label("Filter overrides", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.headline)
    }
}

// MARK: - Flow tag row

private struct FlowTagRow: View {
    let items: [String]
    let color: Color

    var body: some View {
        // Simple wrapping row using a fixed-height scroll
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(color.opacity(0.12), in: Capsule())
                        .foregroundStyle(color)
                }
            }
        }
    }
}

// MARK: - View modifier

private extension View {
    func cardStyle() -> some View {
        self
            .padding(16)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

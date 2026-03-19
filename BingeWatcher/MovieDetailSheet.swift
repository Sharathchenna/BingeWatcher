import SwiftUI

struct MovieDetailSheet: View {
    let card: RecommendationCard
    let posterURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PosterBackdrop(url: posterURL)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                VStack(alignment: .leading, spacing: 14) {
                    Text(card.title)
                        .font(.largeTitle.bold())
                    if let year = card.year {
                        Text(String(year))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    if !card.overview.isEmpty {
                        Text(card.overview)
                            .font(.body)
                    }

                    if !card.genres.isEmpty {
                        detailSection("Genres", text: card.genres.joined(separator: ", "))
                    }
                    if let director = card.director {
                        detailSection("Director", text: director)
                    }
                    if !card.cast.isEmpty {
                        detailSection("Cast", text: card.cast.joined(separator: ", "))
                    }

                    whyRecommendedSection
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .presentationDragIndicator(.visible)
    }

    // MARK: - Why recommended

    private var whyRecommendedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Why recommended")
                .font(.title3.weight(.semibold))

            Text(card.reason)
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                scoreBar(label: "Viewers like you", value: card.breakdown.collabScore, color: .blue)
                scoreBar(label: "Your taste match", value: card.breakdown.contentScore, color: .red)
                scoreBar(label: "Discovery score", value: card.breakdown.banditScore, color: .orange)
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func scoreBar(label: String, value: Float, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Text(String(format: "%.0f%%", value * 100))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(.systemFill))
                        .frame(height: 7)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(color.gradient)
                        .frame(width: geo.size.width * CGFloat(max(0, min(value, 1))), height: 7)
                        .animation(.easeOut(duration: 0.6), value: value)
                }
            }
            .frame(height: 7)
        }
    }

    // MARK: - Helpers

    private func detailSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}

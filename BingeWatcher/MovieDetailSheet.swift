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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Why recommended")
                            .font(.title3.weight(.semibold))
                        Text(card.reason)
                        Text(String(format: "Content %.2f  Collab %.2f  Bandit %.2f  Diversity -%.2f  Final %.2f", card.breakdown.contentScore, card.breakdown.collabScore, card.breakdown.banditScore, card.breakdown.diversityPenalty, card.breakdown.finalScore))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .presentationDragIndicator(.visible)
    }

    private func detailSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}

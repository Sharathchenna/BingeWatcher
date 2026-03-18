import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct SwipeDeckView: View {
    @ObservedObject var repository: MovieRepository
    @Binding var isRefreshing: Bool

    @State private var dragOffset: CGSize = .zero
    @State private var selectedCard: RecommendationCard?
    @State private var startedAt = Date()
    @State private var errorMessage: String?

    private let swipeThreshold: CGFloat = 120

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [Color(red: 0.14, green: 0.16, blue: 0.21), Color(red: 0.31, green: 0.24, blue: 0.18), Color(red: 0.87, green: 0.80, blue: 0.67)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 220, height: 220)
                    .blur(radius: 16)
                    .offset(x: 120, y: -300)

                Circle()
                    .fill(Color.orange.opacity(0.18))
                    .frame(width: 300, height: 300)
                    .blur(radius: 24)
                    .offset(x: -140, y: 340)

                VStack(alignment: .leading, spacing: 20) {
                    header
                    deckArea(height: min(max(360, proxy.size.height * 0.46), 500))
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .safeAreaInset(edge: .bottom) {
                controls
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 92)
                    .background(
                        LinearGradient(
                            colors: [.clear, Color.black.opacity(0.16), Color.black.opacity(0.22)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .sheet(item: $selectedCard) { card in
            MovieDetailSheet(card: card, posterURL: repository.posterURL(for: card.posterPath))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tonight's Deck")
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.68))
                    Text("Adaptive Deck")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Live collaborative, content, and bandit scoring.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }

                Spacer(minLength: 16)

                deckStat
            }

            HStack(spacing: 8) {
                hintChip(symbol: "hand.draw", title: "Like / pass")
                hintChip(symbol: "sparkles", title: "Live taste")
            }
        }
    }

    private func deckArea(height: CGFloat) -> some View {
        ZStack {
            if repository.recommendationDeck.isEmpty {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .overlay {
                        VStack(spacing: 12) {
                            if isRefreshing {
                                ProgressView()
                            }
                            Text(isRefreshing ? "Refreshing your recommendations..." : "No cards yet. Pull a fresh deck.")
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
            } else {
                ForEach(Array(repository.recommendationDeck.prefix(3).enumerated()), id: \.element.id) { index, card in
                    deckCard(for: card, depth: index)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                guard let card = repository.recommendationDeck.first else { return }
                do {
                    try repository.toggleWatchlist(for: card)
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            } label: {
                Label(repository.recommendationDeck.first.map { repository.isWatchlisted($0) } == true ? "Saved" : "Save", systemImage: "bookmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.white.opacity(0.14))

            Button {
                guard let card = repository.recommendationDeck.first else { return }
                selectedCard = card
            } label: {
                Label("Details", systemImage: "info.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.black.opacity(0.86))
            .disabled(repository.recommendationDeck.isEmpty)
        }
        .foregroundStyle(.white)
        .buttonBorderShape(.capsule)
    }

    private func deckCard(for card: RecommendationCard, depth: Int) -> some View {
        let isTopCard = depth == 0
        let offsetY = CGFloat(depth) * 12
        let scale = 1 - (CGFloat(depth) * 0.035)

        return RecommendationCardView(
            card: card,
            posterURL: repository.posterURL(for: card.posterPath),
            overlayTint: overlayTint,
            dragOffset: isTopCard ? dragOffset : .zero
        )
        .scaleEffect(scale)
        .offset(x: isTopCard ? dragOffset.width : 0, y: offsetY + (isTopCard ? dragOffset.height * 0.12 : 0))
        .rotationEffect(.degrees(isTopCard ? Double(dragOffset.width / 18) : 0))
        .zIndex(Double(10 - depth))
        .gesture(isTopCard ? dragGesture(for: card) : nil)
        .onTapGesture {
            selectedCard = card
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: dragOffset)
    }

    private func dragGesture(for card: RecommendationCard) -> some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let width = value.translation.width
                let timeOnCard = Float(Date().timeIntervalSince(startedAt))

                if width > swipeThreshold {
                    completeSwipe(.like, for: card, offscreenX: 700, timeOnCard: timeOnCard)
                } else if width < -swipeThreshold {
                    completeSwipe(.dislike, for: card, offscreenX: -700, timeOnCard: timeOnCard)
                } else {
                    dragOffset = .zero
                }
            }
    }

    private func completeSwipe(_ action: SwipeAction, for card: RecommendationCard, offscreenX: CGFloat, timeOnCard: Float) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            dragOffset = CGSize(width: offscreenX, height: 40)
        }

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(action == .like ? .success : .warning)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            do {
                try repository.logSwipe(for: card, action: action, timeOnCard: max(timeOnCard, 0.2))
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }

            startedAt = Date()
            dragOffset = .zero
        }
    }

    private var deckStat: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(repository.recommendationDeck.count)")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text("cards live")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func hintChip(symbol: String, title: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.82))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.1), in: Capsule())
    }

    private var overlayTint: Color {
        if dragOffset.width > 20 {
            return .green
        }
        if dragOffset.width < -20 {
            return .red
        }
        return .clear
    }
}

private struct RecommendationCardView: View {
    let card: RecommendationCard
    let posterURL: URL?
    let overlayTint: Color
    let dragOffset: CGSize

    var body: some View {
        let finalScoreText = String(format: "%.2f", card.breakdown.finalScore)

        ZStack(alignment: .bottomLeading) {
            PosterBackdrop(url: posterURL)

            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)

            LinearGradient(colors: [.black.opacity(0.05), .clear, .black.opacity(0.88)], startPoint: .top, endPoint: .bottom)

            overlayTint.opacity(Double(min(abs(dragOffset.width) / CGFloat(180), CGFloat(0.28))))

            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        scorePill(text: dragOffset.width > 20 ? "LIKE" : dragOffset.width < -20 ? "PASS" : "CINEMATCH")
                    }
                }
                Spacer()
            }
            .padding(16)

            VStack(alignment: .leading, spacing: 10) {
                Text(card.title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if let year = card.year {
                    Text(String(year))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                Text(card.reason)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    badge("Final \(finalScoreText)")
                    if let genre = card.genres.first {
                        badge(genre)
                    }
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, minHeight: 360, maxHeight: 500)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 22, x: 0, y: 16)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.white.opacity(0.18), in: Capsule())
            .foregroundStyle(.white)
    }

    private func scorePill(text: String) -> some View {
        Text(text)
            .font(.caption.weight(.black))
            .kerning(0.8)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(.white)
    }
}

struct PosterBackdrop: View {
    let url: URL?
    @StateObject private var loader = PosterImageLoader.shared

    var body: some View {
        Group {
            if let image = loader.image(for: url) {
                platformImage(image)
            } else {
                LinearGradient(colors: [Color(red: 0.18, green: 0.23, blue: 0.34), Color(red: 0.43, green: 0.26, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay {
                        Image(systemName: "film.stack")
                            .font(.system(size: 68))
                            .foregroundStyle(.white.opacity(0.22))
                    }
                    .task {
                        await loader.load(from: url)
                    }
            }
        }
        .scaledToFill()
    }

    @ViewBuilder
    private func platformImage(_ image: PlatformImage) -> some View {
#if canImport(UIKit)
        Image(uiImage: image)
            .resizable()
#elseif canImport(AppKit)
        Image(nsImage: image)
            .resizable()
#endif
    }
}

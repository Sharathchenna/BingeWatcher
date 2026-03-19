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
    private let deckSize = 20

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.14, green: 0.16, blue: 0.21),
                        Color(red: 0.31, green: 0.24, blue: 0.18),
                        Color(red: 0.87, green: 0.80, blue: 0.67)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
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
        .onChange(of: repository.recommendationDeck.first?.id) { _, _ in
            startedAt = Date()
            dragOffset = .zero
        }
    }

    // MARK: - Header

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
                hintChip(symbol: "arrow.left.and.right", title: "Swipe to react")
                hintChip(symbol: "arrow.up", title: "Up to skip")
                hintChip(symbol: "sparkles", title: "Live taste")
            }
        }
    }

    // MARK: - Deck area

    private func deckArea(height: CGFloat) -> some View {
        ZStack {
            if repository.recommendationDeck.isEmpty {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .overlay {
                        VStack(spacing: 16) {
                            if isRefreshing {
                                ProgressView()
                                    .tint(.white)
                                Text("Refreshing your recommendations…")
                                    .foregroundStyle(.white.opacity(0.75))
                                    .font(.subheadline)
                            } else {
                                Image(systemName: "film.stack")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.white.opacity(0.4))
                                Text("Your deck is empty.")
                                    .font(.headline)
                                    .foregroundStyle(.white.opacity(0.85))
                                Button {
                                    Task { await refreshDeck() }
                                } label: {
                                    Label("Get fresh picks", systemImage: "arrow.clockwise")
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                        .background(.white.opacity(0.18), in: Capsule())
                                        .foregroundStyle(.white)
                                }
                            }
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

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 10) {
            // Not interested
            actionButton(
                symbol: "xmark",
                tint: .red.opacity(0.85),
                expand: false,
                disabled: repository.recommendationDeck.isEmpty
            ) {
                guard let card = repository.recommendationDeck.first else { return }
                let t = Float(Date().timeIntervalSince(startedAt))
                completeSwipe(.dislike, for: card, offscreen: CGSize(width: -700, height: 40), timeOnCard: t)
            }

            // Save to watchlist
            Button {
                guard let card = repository.recommendationDeck.first else { return }
                do {
                    try repository.toggleWatchlist(for: card)
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            } label: {
                let saved = repository.recommendationDeck.first.map { repository.isWatchlisted($0) } == true
                Image(systemName: saved ? "bookmark.fill" : "bookmark")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.white.opacity(0.14))
            .disabled(repository.recommendationDeck.isEmpty)

            // Details
            Button {
                guard let card = repository.recommendationDeck.first else { return }
                selectedCard = card
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(.black.opacity(0.86))
            .disabled(repository.recommendationDeck.isEmpty)

            // Like
            actionButton(
                symbol: "hand.thumbsup.fill",
                tint: .green.opacity(0.85),
                expand: false,
                disabled: repository.recommendationDeck.isEmpty
            ) {
                guard let card = repository.recommendationDeck.first else { return }
                let t = Float(Date().timeIntervalSince(startedAt))
                completeSwipe(.like, for: card, offscreen: CGSize(width: 700, height: 40), timeOnCard: t)
            }
        }
        .foregroundStyle(.white)
        .buttonBorderShape(.capsule)
    }

    @ViewBuilder
    private func actionButton(
        symbol: String,
        tint: Color,
        expand: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: expand ? nil : 52, height: 52)
                .frame(maxWidth: expand ? .infinity : nil)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .disabled(disabled)
    }

    // MARK: - Card

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

    // MARK: - Gesture

    private func dragGesture(for card: RecommendationCard) -> some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let width = value.translation.width
                let height = value.translation.height
                let timeOnCard = Float(Date().timeIntervalSince(startedAt))

                if width > swipeThreshold {
                    completeSwipe(.like, for: card, offscreen: CGSize(width: 700, height: 40), timeOnCard: timeOnCard)
                } else if width < -swipeThreshold {
                    completeSwipe(.dislike, for: card, offscreen: CGSize(width: -700, height: 40), timeOnCard: timeOnCard)
                } else if height < -swipeThreshold {
                    completeSwipe(.skip, for: card, offscreen: CGSize(width: 0, height: -700), timeOnCard: timeOnCard)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dragOffset = .zero
                    }
                }
            }
    }

    private func completeSwipe(_ action: SwipeAction, for card: RecommendationCard, offscreen: CGSize, timeOnCard: Float) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            dragOffset = offscreen
        }

        if action != .skip {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(action == .like ? .success : .warning)
        }

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

    private func refreshDeck() async {
        isRefreshing = true
        await repository.refreshRecommendationDeckIfNeeded(force: true)
        isRefreshing = false
    }

    // MARK: - Accessories

    private var deckStat: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(repository.recommendationDeck.count) / \(deckSize)")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text("cards left")
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
        if dragOffset.width > 20 { return .green }
        if dragOffset.width < -20 { return .red }
        if dragOffset.height < -20 { return .blue.opacity(0.6) }
        return .clear
    }
}

// MARK: - Card View

private struct RecommendationCardView: View {
    let card: RecommendationCard
    let posterURL: URL?
    let overlayTint: Color
    let dragOffset: CGSize

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PosterBackdrop(url: posterURL)

            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)

            LinearGradient(
                colors: [.black.opacity(0.05), .clear, .black.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )

            overlayTint.opacity(Double(min(abs(dragOffset.width) / CGFloat(180), CGFloat(0.28))))

            VStack {
                HStack {
                    Spacer()
                    statusPill
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
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    badge(matchLabel(for: card.breakdown.finalScore))
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

    private var statusPill: some View {
        let text: String
        if dragOffset.width > 20 {
            text = "LIKE"
        } else if dragOffset.width < -20 {
            text = "PASS"
        } else if dragOffset.height < -20 {
            text = "SKIP"
        } else {
            text = "CINEMATCH"
        }

        return Text(text)
            .font(.caption.weight(.black))
            .kerning(0.8)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(.white)
    }

    private func matchLabel(for score: Float) -> String {
        switch score {
        case 0.65...: return "Great match"
        case 0.45..<0.65: return "Good match"
        default: return "Worth a look"
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.white.opacity(0.18), in: Capsule())
            .foregroundStyle(.white)
    }
}

// MARK: - Poster backdrop with shimmer

struct PosterBackdrop: View {
    let url: URL?
    @StateObject private var loader = PosterImageLoader.shared

    var body: some View {
        Group {
            if let image = loader.image(for: url) {
                platformImage(image)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.18, green: 0.23, blue: 0.34), Color(red: 0.43, green: 0.26, blue: 0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    ShimmerOverlay()
                    Image(systemName: "film.stack")
                        .font(.system(size: 68))
                        .foregroundStyle(.white.opacity(0.12))
                }
                .task { await loader.load(from: url) }
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

private struct ShimmerOverlay: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .clear, location: max(phase - 0.3, 0)),
                .init(color: .white.opacity(0.12), location: phase),
                .init(color: .clear, location: min(phase + 0.3, 1))
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 1.6
            }
        }
    }
}

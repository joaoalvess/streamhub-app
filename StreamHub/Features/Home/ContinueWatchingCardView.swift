import SwiftUI

struct ContinueWatchingCardView: View {
    let item: MediaItem
    var onSelect: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: onSelect) {
                CardLabel(item: item)
            }
            .buttonStyle(.borderless)

            if let metaLabel {
                Text(metaLabel)
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .padding(.leading, 4)
            }
        }
        .frame(width: Theme.Size.wideCardWidth)
    }

    private var metaLabel: String? {
        let parts = [item.genres.first, item.episodeLabel]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct CardLabel: View {
    let item: MediaItem

    var body: some View {
        ZStack {
            AsyncImage(url: item.backdropURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                default:
                    ZStack {
                        Theme.bgElevated
                        ProgressView()
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: Theme.Size.wideCardWidth, height: Theme.Size.wideCardHeight)
            .overlay { Theme.genreScrim }

            titleLockup
                .padding(.horizontal, 24)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    if let serviceBadge = item.serviceBadge {
                        ServiceBadge(text: serviceBadge)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 18)
            }

            VStack {
                Spacer()
                MediaProgressBar(progress: item.progress ?? 0)
            }
        }
        .frame(width: Theme.Size.wideCardWidth, height: Theme.Size.wideCardHeight)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .hoverEffect(.highlight)
    }

    @ViewBuilder
    private var titleLockup: some View {
        if let logoURL = item.logoURL {
            AsyncImage(url: logoURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 64)
                        .transition(.opacity)
                case .failure:
                    titleText
                default:
                    Color.clear
                        .frame(width: 1, height: 1)
                }
            }
        } else {
            titleText
        }
    }

    private var titleText: some View {
        Text(item.title)
            .font(Theme.Font.cardTitle)
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(2)
            .multilineTextAlignment(.center)
    }
}

private struct ServiceBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Font.badge)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .environment(\.colorScheme, .dark)
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}

#Preview {
    HStack(alignment: .top, spacing: Theme.Metrics.cardSpacing) {
        ContinueWatchingCardView(
            item: MediaItem(
                title: "Devoradores de Estrelas",
                kind: .movie,
                genres: ["Ficção científica", "Aventura"],
                posterURL: nil,
                backdropURL: URL(string: "https://image.tmdb.org/t/p/w780/8Tfys3mDZVp4tNoH2ktm06a0Tau.jpg"),
                logoURL: URL(string: "https://image.tmdb.org/t/p/w500/o3t631d9vGoDTSPkUhGZ4GfW4Pa.png"),
                synopsis: "O professor de ciências Ryland Grace acorda em uma espaçonave a anos-luz de casa.",
                year: 2026,
                serviceBadge: "max",
                progress: 0.65,
                episodeLabel: "Restam 42 min"
            )
        )

        ContinueWatchingCardView(
            item: MediaItem(
                title: "The Big Bang Theory",
                kind: .series,
                genres: [],
                posterURL: nil,
                backdropURL: URL(string: "https://image.tmdb.org/t/p/w780/ooBGRQBdbGzBxAVfExiO8r7kloE.jpg"),
                synopsis: "Dois físicos brilhantes dividem apartamento com uma vizinha aspirante a atriz.",
                year: 2007,
                serviceBadge: "netflix",
                progress: 0.3,
                episodeLabel: "Restam 17 min"
            )
        )
    }
    .padding(Theme.Metrics.focusHeadroom)
    .background(Theme.bg)
}

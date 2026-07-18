import SwiftUI

struct MediaCardView: View {
    let item: MediaItem
    var onSelect: () -> Void = {}

    var body: some View {
        Button(action: onSelect) {
            PosterCard(item: item)
        }
        .buttonStyle(.borderless)
    }
}

/// Card de pôster base, no tamanho único da Home. Reutilizado pelo Top 10
/// (passando `rank`). Mostra um sombreado na base do card com o gênero quando
/// focado; o realce de foco é o lockup padrão do sistema (lift + liquid glass).
struct PosterCard: View {
    let item: MediaItem
    var rank: Int? = nil
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        poster
            .frame(width: Theme.Size.posterWidth, height: Theme.Size.posterHeight)
            .overlay { Theme.genreScrim.opacity(isFocused ? 1 : 0) }
            .overlay(alignment: .bottom) { genreLabel.opacity(isFocused ? 1 : 0) }
            .animation(.easeInOut(duration: 0.2), value: isFocused)
            .overlay(alignment: .topLeading) { rankNumeral }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .hoverEffect(.highlight)
    }

    private var poster: some View {
        AsyncImage(url: item.posterURL, transaction: Transaction(animation: .default)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            case .failure:
                Theme.bgElevated
            case .empty:
                ZStack {
                    Theme.bgElevated
                    ProgressView()
                }
            @unknown default:
                Theme.bgElevated
            }
        }
    }

    @ViewBuilder
    private var genreLabel: some View {
        if let label = (item.kind == .anime ? item.title : item.genres.first) {
            Text(label)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var rankNumeral: some View {
        if let rank {
            Text("\(rank)")
                .font(.system(size: 108, weight: .heavy))
                .foregroundStyle(Theme.textPrimary.opacity(0.95))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
                .padding(.leading, 14)
                .padding(.top, 4)
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    HStack(spacing: Theme.Metrics.cardSpacing) {
        MediaCardView(
            item: MediaItem(
                title: "For All Mankind",
                kind: .series,
                genres: ["Drama", "Ficção Científica"],
                posterURL: URL(string: "https://image.tmdb.org/t/p/w500/q6cYZjQAfvJqGGz0e0HQVwL2zFD.jpg"),
                backdropURL: nil,
                synopsis: "Uma releitura da corrida espacial em que a União Soviética chega primeiro à Lua.",
                year: 2019
            )
        )
        Button(action: {}) {
            PosterCard(
                item: MediaItem(
                    title: "Oppenheimer",
                    kind: .movie,
                    genres: ["Drama"],
                    posterURL: URL(string: "https://image.tmdb.org/t/p/w500/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg"),
                    backdropURL: nil,
                    synopsis: "",
                    year: 2023
                ),
                rank: 1
            )
        }
        .buttonStyle(.borderless)
    }
    .padding(Theme.Metrics.focusHeadroom)
    .background(Theme.bg)
}

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
    var showsProgress: Bool = true
    @Environment(\.isFocused) private var isFocused
    @Environment(PlaybackProgressStore.self) private var store: PlaybackProgressStore?

    var body: some View {
        let badge = progressBadge
        poster
            .frame(width: Theme.Size.posterWidth, height: Theme.Size.posterHeight)
            .overlay { Theme.genreScrim.opacity(isFocused ? 1 : 0) }
            .overlay(alignment: .bottom) { genreLabel(above: badge).opacity(isFocused ? 1 : 0) }
            .animation(.easeInOut(duration: 0.2), value: isFocused)
            .overlay(alignment: .bottom) { progressBar(for: badge) }
            .overlay(alignment: .topTrailing) { watchedMark(for: badge) }
            .overlay(alignment: .topLeading) { rankNumeral }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .hoverEffect(.highlight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityTitle)
            .accessibilityValue(accessibilityProgress(for: badge))
    }

    private var progressBadge: ProgressBadge {
        guard showsProgress, let store else { return .none }
        return store.progressBadge(for: item)
    }

    private var poster: some View {
        RemoteImage(url: item.posterURL, maxPixelSize: ImageSize.poster) {
            Theme.bgElevated
        }
    }

    @ViewBuilder
    private func genreLabel(above badge: ProgressBadge) -> some View {
        if let label = (item.kind == .anime ? item.title : item.genres.first) {
            Text(label)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.bottom, genreBottomPadding(for: badge))
        }
    }

    private func genreBottomPadding(for badge: ProgressBadge) -> CGFloat {
        if case .inProgress = badge { return 28 }
        return 12
    }

    @ViewBuilder
    private func progressBar(for badge: ProgressBadge) -> some View {
        if case .inProgress(let progress) = badge {
            MediaProgressBar(progress: progress)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
        }
    }

    @ViewBuilder
    private func watchedMark(for badge: ProgressBadge) -> some View {
        if badge == .watched {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 30, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Theme.textPrimary, Color.black.opacity(0.55))
                .padding(12)
        }
    }

    private var accessibilityTitle: String {
        let year = item.year > 0 ? String(item.year) : nil
        let rankLabel = rank.map { "Top \($0)" }
        return [item.title, year, rankLabel].compactMap { $0 }.joined(separator: ", ")
    }

    private func accessibilityProgress(for badge: ProgressBadge) -> String {
        switch badge {
        case .none: ""
        case .inProgress(let progress): "\(Int((progress * 100).rounded()))% assistido"
        case .watched: "Assistido"
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

import SwiftUI

struct ContinueWatchingCardView: View {
    let item: MediaItem
    var onSelect: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: onSelect) {
                CardLabel(item: item)
            }
            .buttonStyle(.card)

            if let episodeLabel = item.episodeLabel {
                Text(episodeLabel)
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .padding(.leading, 4)
            }
        }
        .frame(width: Theme.Size.wideCardWidth)
    }
}

private struct CardLabel: View {
    let item: MediaItem
    @Environment(\.isFocused) private var isFocused

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
                ProgressBar(progress: item.progress ?? 0)
            }
        }
        .frame(width: Theme.Size.wideCardWidth, height: Theme.Size.wideCardHeight)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .liquidGlassFocusBorder(isFocused)
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

private struct ProgressBar: View {
    let progress: Double

    private let height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.progressTrack)
                Capsule()
                    .fill(Theme.progressFill)
                    .frame(width: max(0, min(1, progress)) * geo.size.width)
            }
        }
        .frame(height: height)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }
}

#Preview {
    let item = MediaItem(
        title: "The Big Bang Theory",
        kind: .series,
        genres: ["Comédia"],
        posterURL: nil,
        backdropURL: URL(string: "https://image.tmdb.org/t/p/w780/ooBGRQBdbGzBxAVfExiO8r7kloE.jpg"),
        synopsis: "Dois físicos brilhantes dividem apartamento com uma vizinha aspirante a atriz.",
        year: 2007,
        serviceBadge: "max",
        progress: 0.65,
        episodeLabel: "T1, E8 · 15 min"
    )

    return ContinueWatchingCardView(item: item)
        .padding(Theme.Metrics.focusHeadroom)
        .background(Theme.bg)
}

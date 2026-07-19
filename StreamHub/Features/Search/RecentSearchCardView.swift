import SwiftUI

struct RecentSearchCardView: View {
    let item: MediaItem
    let isFocused: Bool
    var onSelect: () -> Void = {}

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 20) {
                poster
                text
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(width: Theme.Size.recentCardWidth, height: Theme.Size.recentCardHeight)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(isFocused ? 0.16 : 0.08))
            }
            .scaleEffect(isFocused ? 1.05 : 1)
            .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 20, y: 10)
            .animation(.easeOut(duration: 0.18), value: isFocused)
        }
        .buttonStyle(RecentSearchButtonStyle())
    }

    private var poster: some View {
        AsyncImage(url: item.posterURL, transaction: Transaction(animation: .default)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            default:
                Theme.bgElevated
            }
        }
        .frame(width: 92, height: 138)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(Theme.Font.cardTitle)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
            Text(subtitle)
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }

    private var subtitle: String {
        var parts = [kindLabel]
        if let genre = item.genres.first, !genre.isEmpty {
            parts.append(genre)
        }
        if item.kind == .movie, item.year > 0 {
            parts.append(String(item.year))
        }
        return parts.joined(separator: " · ")
    }

    private var kindLabel: String {
        switch item.kind {
        case .movie: "Filme"
        case .series: "Série"
        case .anime: "Anime"
        }
    }
}

private struct RecentSearchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

import SwiftUI

struct SearchResultCardView: View {
    let item: MediaItem
    var onSelect: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: onSelect) {
                PosterCard(item: item)
            }
            .buttonStyle(.borderless)

            caption
        }
        .frame(width: Theme.Size.posterWidth)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(Theme.Font.cardTitle)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if item.year > 0 {
                Text(String(item.year))
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 4)
    }
}

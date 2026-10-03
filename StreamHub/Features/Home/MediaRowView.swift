import SwiftUI

struct MediaRowView: View {
    let row: CatalogRow
    @Environment(DetailRouter.self) private var router: DetailRouter?
    @Environment(MyListStore.self) private var myList: MyListStore?
    @Environment(PlaybackProgressStore.self) private var progressStore: PlaybackProgressStore?
    @Environment(ToastCenter.self) private var toasts: ToastCenter?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.titleGap) {
            Text(row.title)
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
                .padding(.leading, Theme.Metrics.edgeH)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Metrics.cardSpacing) {
                    ForEach(0..<row.displayCount, id: \.self) { index in
                        card(at: index)
                            .onAppear { row.onCardAppear(index) }
                    }
                }
                .padding(.leading, Theme.Metrics.edgeH)
                .padding(.trailing, Theme.Metrics.edgeH)
                .padding(.vertical, Theme.Metrics.focusHeadroom)
            }
            .scrollClipDisabled()
            .focusSection()
        }
    }

    @ViewBuilder
    private func card(at index: Int) -> some View {
        let item = row.item(at: index)
        switch row.style {
        case .standard:
            MediaCardView(item: item, onSelect: { openDetail(at: index) })
                .contextMenu { cardMenu(for: item) }
        case .continueWatching:
            ContinueWatchingCardView(item: item, onSelect: { openDetail(at: index) })
        case .top10:
            Top10CardView(rank: row.rank(at: index), item: item, onSelect: { openDetail(at: index) })
                .contextMenu { cardMenu(for: item) }
        }
    }

    @ViewBuilder
    private func cardMenu(for item: MediaItem) -> some View {
        if item.contentId != nil || item.imdbId != nil {
            if let myList {
                let isInList = myList.contains(item)
                Button(isInList ? "Remover da Minha lista" : "Adicionar à Minha lista") {
                    myList.toggle(item)
                    toasts?.show(
                        isInList ? "Removido da Minha lista" : "Adicionado à Minha lista",
                        systemImage: isInList ? "xmark" : "checkmark"
                    )
                }
            }
            if item.kind == .movie, let progressStore {
                let isWatched = progressStore.isMovieWatched(item)
                Button(isWatched ? "Marcar como não assistido" : "Marcar como assistido") {
                    let watched = progressStore.toggleMovieWatched(item)
                    toasts?.show(
                        watched ? "Marcado como assistido" : "Marcado como não assistido",
                        systemImage: watched ? "checkmark" : "xmark"
                    )
                }
            }
        }
    }

    private func openDetail(at index: Int) {
        router?.open(row: row, index: index)
    }
}

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: Theme.Metrics.rowSpacing) {
            ForEach(MockData.rows) { row in
                MediaRowView(row: CatalogRow(staticTitle: row.title, style: row.style, items: row.items))
            }
        }
    }
    .background(Theme.backgroundGradient)
}

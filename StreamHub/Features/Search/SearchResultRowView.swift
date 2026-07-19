import SwiftUI

struct SearchResultRowView: View {
    let title: String
    let items: [MediaItem]
    var onOpen: (MediaItem) -> Void = { _ in }
    @Environment(DetailRouter.self) private var router: DetailRouter?

    private struct IndexedItem: Identifiable {
        let id: String
        let index: Int
        let item: MediaItem
    }

    var body: some View {
        let indexed = items.indices.map {
            IndexedItem(id: items[$0].searchIdentity, index: $0, item: items[$0])
        }
        VStack(alignment: .leading, spacing: Theme.Metrics.titleGap) {
            Text(title)
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
                .padding(.leading, Theme.Metrics.edgeH)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.Metrics.cardSpacing) {
                    ForEach(indexed) { entry in
                        SearchResultCardView(item: entry.item) {
                            open(at: entry.index)
                        }
                    }
                }
                .padding(.horizontal, Theme.Metrics.edgeH)
                .padding(.vertical, Theme.Metrics.focusHeadroom)
            }
            .scrollClipDisabled()
            .focusSection()
        }
    }

    private func open(at index: Int) {
        guard let router, items.indices.contains(index) else { return }
        onOpen(items[index])
        let row = CatalogRow(staticTitle: title, style: .standard, items: items)
        router.open(row: row, index: index)
    }
}

nonisolated extension MediaItem {
    var searchIdentity: String {
        contentId ?? imdbId ?? title
    }
}

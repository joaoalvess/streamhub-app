import SwiftUI

struct RecentSearchesRowView: View {
    let items: [MediaItem]
    var onOpen: (MediaItem) -> Void = { _ in }
    @Environment(DetailRouter.self) private var router: DetailRouter?
    @FocusState private var focusedId: String?

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
            Text("Buscas Recentes")
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
                .padding(.leading, Theme.Metrics.edgeH)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Metrics.cardSpacing) {
                    ForEach(indexed) { entry in
                        RecentSearchCardView(item: entry.item, isFocused: focusedId == entry.id) {
                            open(at: entry.index)
                        }
                        .focused($focusedId, equals: entry.id)
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
        let row = CatalogRow(staticTitle: "Buscas Recentes", style: .standard, items: items)
        router.open(row: row, index: index)
    }
}
